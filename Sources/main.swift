// Kolam — a native koi pond wallpaper for macOS, drawn with SpriteKit.
//
// One borderless desktop-level window per display, each hosting an SKView.
// SpriteKit renders on Metal and syncs to the display's refresh rate.
// A view is paused whenever nobody can see it (covered, locked, asleep).

import AppKit
import SpriteKit

// MARK: - Wallpaper window

/// Takes the first click even though the app is never frontmost.
final class PondView: SKView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class WallpaperWindow: NSWindow {
    let skView: PondView
    private(set) var displayID: CGDirectDisplayID?
    private var maxFPS: Int

    init(screen: NSScreen) {
        skView = PondView(frame: NSRect(origin: .zero, size: screen.frame.size))
        skView.autoresizingMask = [.width, .height]
        displayID = screen.displayID
        maxFPS = screen.maximumFramesPerSecond
        skView.ignoresSiblingOrder = true
        skView.shouldCullNonVisibleNodes = true

        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        setInteractive(Settings.interactive)
        isOpaque = true
        hasShadow = false
        backgroundColor = .black
        isReleasedWhenClosed = false
        animationBehavior = .none
        contentView = skView
        setFrame(screen.frame, display: false)

        skView.presentScene(PondScene(size: screen.frame.size))
        applySettings()
        orderFrontRegardless()
    }

    /// Follows the same display to a new frame or refresh rate without replacing the pond.
    func fit(to screen: NSScreen) {
        if frame != screen.frame { setFrame(screen.frame, display: true) }
        if maxFPS != screen.maximumFramesPerSecond {
            maxFPS = screen.maximumFramesPerSecond
            applySettings()
        }
        orderFrontRegardless()
    }

    func applySettings() {
        setInteractive(Settings.interactive)
        skView.preferredFramesPerSecond = Settings.fps > 0 ? min(Settings.fps, maxFPS) : maxFPS
        skView.showsFPS = Settings.showStats
        skView.showsNodeCount = Settings.showStats
        skView.showsDrawCount = Settings.showStats
        (skView.scene as? PondScene)?.apply(.current)
    }

    /// Non-interactive: below desktop icons, clicks pass through to Finder.
    /// Interactive: just above desktop icons (still below app windows), takes clicks.
    func setInteractive(_ on: Bool) {
        let base = CGWindowLevelForKey(on ? .desktopIconWindow : .desktopWindow)
        level = NSWindow.Level(Int(base) + (on ? 1 : 0))
        ignoresMouseEvents = !on
    }

    /// KOLAM_ALWAYS_RUN=1 ignores occlusion, for measuring cost while windows cover the desktop.
    var isVisibleOnScreen: Bool {
        occlusionState.contains(.visible) || ProcessInfo.processInfo.environment["KOLAM_ALWAYS_RUN"] != nil
    }

    /// The pond alone, rendered straight from SpriteKit: no desktop icons, windows or
    /// menu bar, and no screen-recording permission needed.
    func pondPNG() -> Data? {
        guard let scene = skView.scene, let image = skView.texture(from: scene)?.cgImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    func tearDown() {
        skView.presentScene(nil)
        orderOut(nil)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// Survives reboots and replugging, unlike the display ID; used for saved settings.
    var displayUUID: String? {
        guard let id = displayID, let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    var pondEnabled: Bool {
        displayUUID.map { !Settings.disabledDisplays.contains($0) } ?? true
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var windows: [WallpaperWindow] = []
    private var statusItem: NSStatusItem!
    private var asleep = false
    private var settingsPending = false
    private var recorder: PondRecorder?
    private var screenSync: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "fish", accessibilityDescription: "Kolam")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        CaptureNotifier.shared.setUp()
        observe()
        rebuildWindows()
        scheduleSnapshot()
        scheduleSettingsSnapshot()
        scheduleRecordingTest()
    }

    /// KOLAM_RECORD=<seconds> records the first display, prints the file path and quits.
    /// Used for checking video capture without clicking the menu.
    private func scheduleRecordingTest() {
        guard let value = ProcessInfo.processInfo.environment["KOLAM_RECORD"], let seconds = Double(value) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in
            startRecording(seconds: seconds) { url in
                print(url?.path ?? "recording failed")
                NSApp.terminate(nil)
            }
        }
    }

    /// KOLAM_SETTINGS_SNAPSHOT=/dir opens the settings window, renders each page to
    /// <dir>/<page>.png and quits. Used for checking the layout without screen recording.
    private func scheduleSettingsSnapshot() {
        guard let dir = ProcessInfo.processInfo.environment["KOLAM_SETTINGS_SNAPSHOT"] else { return }
        SettingsWindow.shared.show()
        let pages = SettingsPage.allCases
        func shoot(_ k: Int) {
            guard k < pages.count else { NSApp.terminate(nil); return }
            UserDefaults.standard.set(pages[k].rawValue, forKey: "settingsPage")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if let view = SettingsWindow.shared.window?.contentView,
                   let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?
                        .write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(pages[k].rawValue).png"))
                }
                shoot(k + 1)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { shoot(0) }
    }

    /// KOLAM_SNAPSHOT=/path.png renders the first display's scene to a PNG after a few
    /// seconds and quits. Used for checking the look without screen-recording permission.
    private func scheduleSnapshot() {
        guard let path = ProcessInfo.processInfo.environment["KOLAM_SNAPSHOT"], let window = windows.first else { return }
        // KOLAM_SPLASH=1 drops a test splash in the middle shortly before the snapshot.
        if ProcessInfo.processInfo.environment["KOLAM_SPLASH"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.2) {
                let size = window.skView.bounds.size
                let p = CGPoint(x: size.width * 0.25, y: size.height * 0.25); Wave.splash(at: p, strength: 9 * Wave.unit * 2); (window.skView.scene as? PondScene)?.dropFood(at: p)
            }
        }
        // KOLAM_FEED=1 drops food in the middle a few seconds before the snapshot.
        if ProcessInfo.processInfo.environment["KOLAM_FEED"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                let size = window.skView.bounds.size
                (window.skView.scene as? PondScene)?.dropFood(at: CGPoint(x: size.width / 2, y: size.height / 2))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            try? window.pondPNG()?.write(to: URL(fileURLWithPath: path))
            NSApp.terminate(nil)
        }
    }

    private func observe() {
        let nc = NotificationCenter.default
        // Fires in bursts (plugging a display, Space switches, Dock and menu bar changes),
        // so wait for it to settle, then sync windows to displays instead of rebuilding.
        nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) {
            [weak self] _ in self?.scheduleScreenSync()
        }
        // Coalesced: a preset writes dozens of keys, but the scene should rebuild once.
        nc.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, !self.settingsPending else { return }
            self.settingsPending = true
            DispatchQueue.main.async {
                self.settingsPending = false
                self.windows.forEach { $0.applySettings() }
            }
        }
        nc.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main) {
            [weak self] n in if n.object is WallpaperWindow { self?.updatePlayback() }
        }

        let ws = NSWorkspace.shared.notificationCenter
        let sleepEvents: [(Notification.Name, Bool)] = [
            (NSWorkspace.screensDidSleepNotification, true),
            (NSWorkspace.willSleepNotification, true),
            (NSWorkspace.sessionDidResignActiveNotification, true),
            (NSWorkspace.screensDidWakeNotification, false),
            (NSWorkspace.didWakeNotification, false),
            (NSWorkspace.sessionDidBecomeActiveNotification, false),
        ]
        for (name, sleeping) in sleepEvents {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.asleep = sleeping
                self?.updatePlayback()
            }
        }
    }

    private func scheduleScreenSync() {
        screenSync?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.rebuildWindows() }
        screenSync = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// Keeps one window per enabled display, matched by display ID. A display that stays
    /// keeps its window and pond (only resized if its frame moved); new or re-enabled
    /// displays get a fresh window, removed or disabled ones are torn down. Windows stay
    /// in NSScreen.screens order so `windows.first` is the main display when it's enabled.
    private func rebuildWindows() {
        var existing = Dictionary(windows.compactMap { w in w.displayID.map { ($0, w) } },
                                  uniquingKeysWith: { a, _ in a })
        windows = NSScreen.screens.filter(\.pondEnabled).map { screen in
            if let id = screen.displayID, let window = existing.removeValue(forKey: id) {
                window.fit(to: screen)
                return window
            }
            return WallpaperWindow(screen: screen)
        }
        existing.values.forEach { $0.tearDown() }
        updatePlayback()
    }

    private func updatePlayback() {
        let allowed = !Settings.paused && !asleep
        for window in windows {
            // The display being recorded keeps running even while paused or covered.
            let recording = recorder != nil && window === windows.first
            window.skView.isPaused = !(recording || (allowed && window.isVisibleOnScreen))
        }
        statusItem?.button?.appearsDisabled = Settings.paused && recorder == nil
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let running = windows.contains { !$0.skView.isPaused }
        let status = NSMenuItem(
            title: Settings.paused ? "Paused" : (running ? "Running" : "Idle — wallpaper hidden"),
            action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        menu.addItem(item(Settings.paused ? "Resume" : "Pause", #selector(togglePause)))
        let settings = item("Settings…", #selector(openSettings))
        settings.keyEquivalent = ","
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(item("Take Screenshot", #selector(takeScreenshot)))
        if let recorder {
            let left = Int(recorder.remaining.rounded(.up))
            menu.addItem(item(String(format: "Stop Recording (%d:%02d left)", left / 60, left % 60), #selector(stopRecording)))
        } else {
            let record = NSMenuItem(title: "Record Video", action: nil, keyEquivalent: "")
            let durations = NSMenu()
            for (title, seconds) in [("15 seconds", 15), ("30 seconds", 30), ("45 seconds", 45), ("1 minute", 60)] {
                let i = item(title, #selector(recordVideo(_:)))
                i.tag = seconds
                durations.addItem(i)
            }
            record.submenu = durations
            menu.addItem(record)
        }
        menu.addItem(.separator())
        menu.addItem(item("Interactive (hides desktop icons)", #selector(toggleInteractive), on: Settings.interactive))
        // Also shown with one display if it's off, so it can be turned back on.
        if NSScreen.screens.count > 1 || NSScreen.screens.contains(where: { !$0.pondEnabled }) {
            let displays = NSMenuItem(title: "Displays", action: nil, keyEquivalent: "")
            let list = NSMenu()
            for screen in NSScreen.screens {
                let i = item(screen.localizedName, #selector(toggleDisplay(_:)), on: screen.pondEnabled)
                i.representedObject = screen.displayUUID
                i.isEnabled = screen.displayUUID != nil
                list.addItem(i)
            }
            displays.submenu = list
            menu.addItem(displays)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Kolam", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func item(_ title: String, _ action: Selector, on: Bool? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        if let on { i.state = on ? .on : .off }
        return i
    }

    @objc private func togglePause() {
        Settings.paused.toggle()
        updatePlayback()
    }

    /// Settings writes trigger UserDefaults.didChangeNotification, which applies them.
    @objc private func toggleInteractive() { Settings.interactive.toggle() }

    @objc private func toggleDisplay(_ sender: NSMenuItem) {
        guard let uuid = sender.representedObject as? String else { return }
        var off = Settings.disabledDisplays
        if off.contains(uuid) { off.remove(uuid) } else { off.insert(uuid) }
        Settings.disabledDisplays = off
        rebuildWindows()
    }

    @objc private func openSettings() { SettingsWindow.shared.show() }

    @objc private func takeScreenshot() { _ = Screenshot.take(windows) }

    @objc private func recordVideo(_ sender: NSMenuItem) {
        startRecording(seconds: TimeInterval(sender.tag)) { url in
            if let url {
                CaptureNotifier.shared.saved([url], kind: .video)
            } else {
                CaptureNotifier.shared.failed("The video couldn't be written to \((CaptureFolder.url.path as NSString).abbreviatingWithTildeInPath).")
            }
        }
    }

    @objc private func stopRecording() { recorder?.stop() }

    /// Records the main display (the one with the menu bar), or the first enabled one if it's off.
    private func startRecording(seconds: TimeInterval, done: @escaping (URL?) -> Void) {
        guard recorder == nil, let window = windows.first,
              let r = PondRecorder(view: window.skView, duration: seconds) else { done(nil); return }
        recorder = r
        r.onFinish = { [weak self] url in
            self?.recorder = nil
            self?.setRecordingIcon(false)
            self?.updatePlayback()
            done(url)
        }
        updatePlayback()
        setRecordingIcon(true)
        r.begin()
    }

    private func setRecordingIcon(_ on: Bool) {
        statusItem?.button?.image = NSImage(systemSymbolName: on ? "record.circle" : "fish",
                                            accessibilityDescription: on ? "Kolam — recording" : "Kolam")
        statusItem?.button?.contentTintColor = on ? .systemRed : nil
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
Settings.registerDefaults()
app.run()
