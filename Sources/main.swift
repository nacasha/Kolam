// PondWall — a native koi pond wallpaper for macOS, drawn with SpriteKit.
//
// One borderless desktop-level window per display, each hosting an SKView.
// SpriteKit renders on Metal and syncs to the display's refresh rate.
// A view is paused whenever nobody can see it (covered, locked, asleep).

import AppKit
import ServiceManagement
import SpriteKit

// MARK: - Settings

enum Settings {
    private static let d = UserDefaults.standard

    static var paused: Bool {
        get { d.bool(forKey: "paused") }
        set { d.set(newValue, forKey: "paused") }
    }

    static var showStats: Bool {
        get { d.bool(forKey: "showStats") }
        set { d.set(newValue, forKey: "showStats") }
    }
}

// MARK: - Wallpaper window

final class WallpaperWindow: NSWindow {
    let skView: SKView

    init(screen: NSScreen) {
        skView = SKView(frame: NSRect(origin: .zero, size: screen.frame.size))
        skView.autoresizingMask = [.width, .height]
        skView.preferredFramesPerSecond = screen.maximumFramesPerSecond
        skView.ignoresSiblingOrder = true
        skView.shouldCullNonVisibleNodes = true

        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        ignoresMouseEvents = true
        isOpaque = true
        hasShadow = false
        backgroundColor = .black
        isReleasedWhenClosed = false
        animationBehavior = .none
        contentView = skView
        setFrame(screen.frame, display: false)

        skView.presentScene(PondScene(size: screen.frame.size))
        applyStats()
        orderFrontRegardless()
    }

    /// PONDWALL_ALWAYS_RUN=1 ignores occlusion, for measuring cost while windows cover the desktop.
    var isVisibleOnScreen: Bool {
        occlusionState.contains(.visible) || ProcessInfo.processInfo.environment["PONDWALL_ALWAYS_RUN"] != nil
    }

    func applyStats() {
        skView.showsFPS = Settings.showStats
        skView.showsNodeCount = Settings.showStats
        skView.showsDrawCount = Settings.showStats
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "fish", accessibilityDescription: "PondWall")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        observe()
        rebuildWindows()
    }

    private func observe() {
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) {
            [weak self] _ in self?.rebuildWindows()
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
        menu.addItem(item("Show FPS", #selector(toggleStats), on: Settings.showStats))
        menu.addItem(item("Start at Login", #selector(toggleLogin), on: SMAppService.mainApp.status == .enabled))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit PondWall", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
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

    @objc private func toggleStats() {
        Settings.showStats.toggle()
        windows.forEach { $0.applyStats() }
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn't change Start at Login"
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
