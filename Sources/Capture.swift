// Capture — screenshots and video recordings of the pond alone (no desktop icons,
// windows or menu bar), rendered straight from SpriteKit so no screen-recording
// permission is needed. Saved to a folder of the user's choice and announced with a
// notification that can open the file or show it in Finder.

import AppKit
import AVFoundation
import SpriteKit
import UserNotifications

// MARK: - Save folder

enum CaptureFolder {
    /// UserDefaults key; empty means "same as macOS screenshots".
    static let key = "captureFolder"

    /// Where captures go: the chosen folder if it still exists, else the system default.
    static var url: URL {
        if let custom, isFolder(custom) { return custom }
        return systemDefault
    }

    static var custom: URL? {
        guard let path = UserDefaults.standard.string(forKey: key), !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// The folder set in the Screenshot app's Options, else the Desktop.
    static var systemDefault: URL {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        guard let path = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") else { return desktop }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        return isFolder(url) ? url : desktop
    }

    private static func isFolder(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// "Kolam 2026-09-29 at 08.59.12", like the system's screenshot names.
    static func baseName(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Kolam \(f.string(from: date))"
    }
}

// MARK: - Screenshot

enum Screenshot {
    /// Saves each display's pond as a PNG. Returns the files written.
    static func take(_ windows: [WallpaperWindow]) -> [URL] {
        let dir = CaptureFolder.url
        let base = CaptureFolder.baseName()
        var saved: [URL] = []
        for (i, window) in windows.enumerated() {
            guard let data = window.pondPNG() else { continue }
            let name = windows.count > 1 ? "\(base) (\(i + 1)).png" : "\(base).png"
            let url = dir.appendingPathComponent(name)
            if (try? data.write(to: url)) != nil { saved.append(url) }
        }
        if saved.isEmpty {
            NSSound.beep()
        } else {
            // The system's screenshot sound; not in /System/Library/Sounds, so load it by path.
            let grab = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Grab.aif"
            (NSSound(contentsOfFile: grab, byReference: true) ?? NSSound(named: "Tink"))?.play()
            CaptureNotifier.shared.saved(saved, kind: .screenshot)
        }
        return saved
    }
}

// MARK: - Video

/// Records one display's pond to an H.264 MP4. SKRenderer draws the live scene
/// straight into the encoder's pixel buffers on the GPU (no read-back), and each
/// frame is stamped with the real elapsed time, so a dropped frame never changes
/// the video's length.
final class PondRecorder {
    static let fps = 30.0
    /// Long edge cap: 5K/6K displays record at 4K, which H.264 handles everywhere.
    static let maxLongEdge = 3840

    let url: URL
    let duration: TimeInterval
    private weak var view: SKView?
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let renderer: SKRenderer
    private let queue: MTLCommandQueue
    private let textureCache: CVMetalTextureCache
    private let width: Int, height: Int
    private var savedScaleMode: SKSceneScaleMode?
    private var timer: Timer?
    private var start: CFTimeInterval = 0
    private var frames = 0
    private var inFlight = 0
    private var stopping = false
    private var finished = false
    var onFinish: ((URL?) -> Void)?

    var remaining: TimeInterval { max(0, duration - (CACurrentMediaTime() - start)) }

    init?(view: SKView, duration: TimeInterval) {
        let scale = view.window?.backingScaleFactor ?? 2
        var w = view.bounds.width * scale, h = view.bounds.height * scale
        let fit = min(1, CGFloat(Self.maxLongEdge) / max(w, h))
        w *= fit; h *= fit
        // H.264 wants even dimensions.
        width = Int(w) & ~1
        height = Int(h) & ~1

        // Render on the GPU driving this display, so the scene's textures are usable.
        let displayID = view.window?.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        guard width > 0, height > 0,
              let device = displayID.flatMap(CGDirectDisplayCopyCurrentMetalDevice) ?? MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        guard let cache else { return nil }
        self.queue = queue
        textureCache = cache
        renderer = SKRenderer(device: device)

        url = CaptureFolder.url.appendingPathComponent("\(CaptureFolder.baseName()).mp4")
        self.view = view
        self.duration = duration
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return nil }
        self.writer = writer
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                // About 0.15 bits per pixel per frame: 4K30 ≈ 37 Mbit/s, 1080p30 ≈ 9 Mbit/s.
                AVVideoAverageBitRateKey: Int(Double(width * height) * Self.fps * 0.15),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: Int(Self.fps),
            ],
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ])
        input.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ])
        guard writer.canAdd(input) else { return nil }
        writer.add(input)
    }

    func begin() {
        guard let scene = view?.scene, writer.startWriting() else { finish(); return }
        writer.startSession(atSourceTime: .zero)
        // resizeFill would let the renderer resize the live scene to the video's pixel
        // size; aspectFill keeps its size and, at the same aspect ratio, looks identical.
        savedScaleMode = scene.scaleMode
        scene.scaleMode = .aspectFill
        renderer.scene = scene
        start = CACurrentMediaTime()
        let t = Timer(timeInterval: 1 / Self.fps, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    /// Ends early; whatever was recorded so far is kept.
    func stop() { finish() }

    private func tick() {
        let elapsed = CACurrentMediaTime() - start
        if elapsed >= duration { finish(); return }
        // The view updates the scene; we only draw it. Skip a frame if the GPU is behind.
        guard !stopping, inFlight < 3, input.isReadyForMoreMediaData,
              let pool = adaptor.pixelBufferPool else { return }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        var cvTexture: CVMetalTexture?
        guard let buffer,
              CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, buffer, nil, .bgra8Unorm,
                                                        width, height, 0, &cvTexture) == kCVReturnSuccess,
              let cvTexture, let texture = CVMetalTextureGetTexture(cvTexture),
              let commands = queue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        renderer.render(withViewport: CGRect(x: 0, y: 0, width: width, height: height),
                        commandBuffer: commands, renderPassDescriptor: pass)
        inFlight += 1
        let time = CMTime(seconds: elapsed, preferredTimescale: 600)
        commands.addCompletedHandler { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                _ = cvTexture  // keeps the texture alive until the GPU is done with it
                self.inFlight -= 1
                if self.writer.status == .writing, self.adaptor.append(buffer, withPresentationTime: time) {
                    self.frames += 1
                }
                if self.stopping && self.inFlight == 0 { self.finalize() }
            }
        }
        commands.commit()
    }

    private func finish() {
        guard !stopping else { return }
        stopping = true
        timer?.invalidate()
        timer = nil
        if let savedScaleMode { view?.scene?.scaleMode = savedScaleMode }
        if inFlight == 0 { finalize() }  // else the last frame's completion calls it
    }

    private func finalize() {
        guard !finished else { return }
        finished = true
        guard writer.status == .writing, frames > 0 else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            onFinish?(nil)
            return
        }
        input.markAsFinished()
        let url = url
        writer.finishWriting { [writer] in
            DispatchQueue.main.async { [weak self] in
                self?.onFinish?(writer.status == .completed ? url : nil)
            }
        }
    }
}

// MARK: - Notifications

final class CaptureNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = CaptureNotifier()

    enum Kind { case screenshot, video }

    private let center = UNUserNotificationCenter.current()
    private let category = "capture"
    private let openAction = "open"
    private let revealAction = "reveal"

    func setUp() {
        center.delegate = self
        center.setNotificationCategories([UNNotificationCategory(
            identifier: category,
            actions: [
                UNNotificationAction(identifier: openAction, title: "Open", options: []),
                UNNotificationAction(identifier: revealAction, title: "Show in Folder", options: []),
            ],
            intentIdentifiers: [], options: [])])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func saved(_ urls: [URL], kind: Kind) {
        guard let first = urls.first else { return }
        let content = UNMutableNotificationContent()
        let folder = (first.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
        switch (kind, urls.count) {
        case (.screenshot, 1):
            content.title = "Screenshot saved"
            content.body = (first.path as NSString).abbreviatingWithTildeInPath
        case (.screenshot, let n):
            content.title = "\(n) screenshots saved"
            content.body = "One per display, in \(folder)"
        case (.video, _):
            content.title = "Video saved"
            content.body = (first.path as NSString).abbreviatingWithTildeInPath
        }
        // Screenshots already play the camera sound.
        if kind == .video { content.sound = .default }
        content.categoryIdentifier = category
        content.userInfo = ["paths": urls.map(\.path)]
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    /// A video that couldn't be written.
    func failed(_ message: String) {
        let content = UNMutableNotificationContent()
        content.title = "Recording failed"
        content.body = message
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let urls = (response.notification.request.content.userInfo["paths"] as? [String] ?? []).map(URL.init(fileURLWithPath:))
        // Resolved before dispatching: capturing `self` in this closure crashes
        // the Swift 6.1 compiler (SILGenCleanup assertion) in release builds.
        let action = response.actionIdentifier
        let reveal = action == revealAction
        let open = action == openAction || action == UNNotificationDefaultActionIdentifier
        DispatchQueue.main.async {
            if reveal {
                NSWorkspace.shared.activateFileViewerSelecting(urls)
            } else if open {
                urls.forEach { NSWorkspace.shared.open($0) }
            }
        }
        completionHandler()
    }
}
