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
    private let maxFPS: Int

    init(screen: NSScreen) {
        skView = PondView(frame: NSRect(origin: .zero, size: screen.frame.size))
        skView.autoresizingMask = [.width, .height]
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

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var windows: [WallpaperWindow] = []
    private var statusItem: NSStatusItem!
    private var asleep = false
    private var settingsPending = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "fish", accessibilityDescription: "Kolam")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        observe()
        rebuildWindows()
        scheduleSnapshot()
        scheduleSettingsSnapshot()
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
        nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) {
            [weak self] _ in self?.rebuildWindows()
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

    private func rebuildWindows() {
        windows.forEach { $0.tearDown() }
        windows = NSScreen.screens.map { WallpaperWindow(screen: $0) }
        updatePlayback()
    }

    private func updatePlayback() {
        let allowed = !Settings.paused && !asleep
        for window in windows {
            window.skView.isPaused = !(allowed && window.isVisibleOnScreen)
        }
        statusItem?.button?.appearsDisabled = Settings.paused
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
        menu.addItem(item("Take Screenshot", #selector(takeScreenshot)))
        menu.addItem(.separator())
        menu.addItem(item("Interactive (hides desktop icons)", #selector(toggleInteractive), on: Settings.interactive))
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

    @objc private func openSettings() { SettingsWindow.shared.show() }

    /// Saves each display's pond as a PNG where macOS saves screenshots (Desktop by
    /// default), named like the system's: "Kolam 2026-09-29 at 08.59.12.png".
    @objc private func takeScreenshot() {
        let dir = Self.screenshotFolder()
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let base = "Kolam \(f.string(from: Date()))"
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
        }
    }

    /// The folder set in the Screenshot app's Options, else the Desktop.
    private static func screenshotFolder() -> URL {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        guard let path = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") else { return desktop }
        var isDir: ObjCBool = false
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue ? url : desktop
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
Settings.registerDefaults()
app.run()
