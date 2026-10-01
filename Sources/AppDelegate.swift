import AppKit
import Carbon
import SwiftUI

/// Panel that takes keyboard input without pulling the app (and Keynote's focus) to the front.
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Lets a click on a note's button work even though the app is in the background.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    let controller = Controller()
    private var panel: KeyPanel?
    private var notePanel: NSPanel?
    private var noteTimer: Timer?
    private var noteDeadline = Date()
    private var noteRemaining: TimeInterval = 0
    private var keyMonitor: Any?
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var overlays: [CGDirectDisplayID: (window: NSWindow, curtain: Bool)] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.onShowPanel = { [weak self] in self?.showPanel() }
        controller.onHidePanel = { [weak self] in self?.hidePanel() }
        controller.onShowNote = { [weak self] note, action in self?.showNote(note, action: action) }
        controller.onOverlays = { [weak self] in self?.updateOverlays() }

        setUpStatusItem()
        hotKey = HotKey(keyCode: kVK_ANSI_P, modifiers: controlKey | optionKey, id: 1) { [weak self] in
            self?.controller.togglePanel()
        }
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "loginItemOffered") {
            defaults.set(true, forKey: "loginItemOffered")
            controller.setOpenAtLogin(true)
        }
        controller.start()
    }

    /// Opening the app again from Spotlight, Finder or Launchpad shows the panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller.openPanel()
        return false
    }

    // MARK: Panel

    private func makePanel() -> KeyPanel {
        let host = NSHostingController(rootView: PanelView(c: controller))
        host.sizingOptions = [.preferredContentSize]
        let p = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 470, height: 320),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.contentViewController = host
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isMovableByWindowBackground = true
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = false
        p.isReleasedWhenClosed = false
        p.delegate = self
        return p
    }

    private func showPanel() {
        let p = panel ?? makePanel()
        panel = p
        p.layoutIfNeeded()
        if let screen = Displays.homeScreen() {
            let f = screen.visibleFrame
            let size = p.frame.size
            p.setFrameOrigin(NSPoint(x: (f.midX - size.width / 2).rounded(), y: (f.midY - size.height / 2 + f.height * 0.08).rounded()))
        }
        p.makeKeyAndOrderFront(nil)
        p.makeFirstResponder(nil)
        DispatchQueue.main.async { p.makeFirstResponder(nil); p.invalidateShadow() }
        installKeyMonitor()
    }

    private func hidePanel() {
        panel?.orderOut(nil)
    }

    /// Clicking somewhere else closes the panel, except right after a change of screens
    /// (macOS may take the focus away while it rearranges the screens).
    func windowDidResignKey(_ notification: Notification) {
        guard (notification.object as? NSWindow) === panel, controller.panelVisible else { return }
        if Date().timeIntervalSince(controller.lastApplied) < 3 {
            DispatchQueue.main.async { [weak self] in self?.panel?.makeKey() }
            return
        }
        controller.hidePanel()
    }

    func windowDidResize(_ notification: Notification) {
        guard let p = notification.object as? NSWindow, p === panel else { return }
        p.invalidateShadow()
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let p = self.panel, p.isVisible, event.window === p else { return event }
            switch event.keyCode {
            case UInt16(kVK_Return), UInt16(kVK_ANSI_KeypadEnter):
                self.controller.done()
                return nil
            case UInt16(kVK_Escape):
                self.controller.hidePanel()
                return nil
            default:
                break
            }
            let editing = p.firstResponder is NSTextView
            if editing || !event.modifierFlags.intersection([.command, .control, .option]).isEmpty { return event }
            switch event.charactersIgnoringModifiers?.lowercased() ?? "" {
            case "1": self.controller.choose(.present)
            case "2": self.controller.choose(.mirror)
            case "3": self.controller.choose(.desk)
            case "c": self.controller.toggleCurtain()
            case "t": self.controller.testSound()
            default: return event
            }
            return nil
        }
    }

    // MARK: Notes

    private func makeNotePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 80),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        return p
    }

    private func showNote(_ note: Note, action: (() -> Void)?) {
        let wrapped: (() -> Void)? = action.map { act in
            { [weak self] in
                self?.hideNote()
                act()
            }
        }
        let view = NoteView(note: note, action: wrapped)
            .onHover { [weak self] inside in self?.noteHover(inside) }
        let host = FirstClickHostingView(rootView: AnyView(view))
        let p = notePanel ?? makeNotePanel()
        notePanel = p
        p.contentView = host
        let size = host.fittingSize
        if let screen = Displays.homeScreen() {
            let f = screen.visibleFrame
            p.setFrame(NSRect(x: f.maxX - size.width - 16, y: f.maxY - size.height - 12, width: size.width, height: size.height),
                       display: true)
        }
        p.orderFrontRegardless()
        p.invalidateShadow()
        scheduleNoteHide(after: 8)
    }

    private func scheduleNoteHide(after seconds: TimeInterval) {
        noteTimer?.invalidate()
        noteDeadline = Date().addingTimeInterval(seconds)
        noteTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in self?.hideNote() }
    }

    /// Hovering keeps the note; leaving gives it the rest of its time (at least 2 seconds).
    private func noteHover(_ inside: Bool) {
        if inside {
            noteRemaining = max(2, noteDeadline.timeIntervalSinceNow)
            noteTimer?.invalidate()
        } else {
            scheduleNoteHide(after: noteRemaining)
        }
    }

    private func hideNote() {
        noteTimer?.invalidate()
        notePanel?.orderOut(nil)
    }

    // MARK: Curtain and audience label on the other screens

    private func updateOverlays() {
        let home = Displays.homeScreen().flatMap(Displays.displayID(of:))
        var wanted: [CGDirectDisplayID: Bool] = [:]   // display -> curtain (true) or audience label (false)
        for d in controller.externals where !d.isMirroring && d.id != home {
            if controller.curtain {
                wanted[d.id] = true
            } else if controller.showsAudienceLabel {
                wanted[d.id] = false
            }
        }
        for (id, overlay) in overlays where wanted[id] != overlay.curtain {
            overlay.window.orderOut(nil)
            overlays[id] = nil
        }
        for (id, curtain) in wanted {
            guard let screen = Displays.screen(for: id) else { continue }
            let window = overlays[id]?.window ?? makeOverlay(curtain: curtain)
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            overlays[id] = (window, curtain)
        }
    }

    private func makeOverlay(curtain: Bool) -> NSWindow {
        let w = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // The curtain must also cover a running slideshow.
        w.level = curtain ? NSWindow.Level(rawValue: Int(CGShieldingWindowLevel())) : .statusBar
        w.contentView = curtain ? NSHostingView(rootView: AnyView(CurtainView())) : NSHostingView(rootView: AnyView(AudienceView()))
        return w
    }

    // MARK: Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "display.2", accessibilityDescription: appName) {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "PP"
            }
            button.toolTip = appName
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        let show = item(L("Show Panel"), #selector(showPanelFromMenu))
        show.keyEquivalent = "p"
        show.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(show)
        menu.addItem(.separator())
        let login = item(L("Open at Login"), #selector(toggleLogin))
        login.state = controller.openAtLogin ? .on : .off
        menu.addItem(login)
        menu.addItem(item(L("Copy Diagnostics"), #selector(copyDiagnostics)))
        menu.addItem(.separator())
        menu.addItem(item(L("Buy Me a Coffee…"), #selector(buyCoffee)))
        menu.addItem(item(L("About Present Perfect"), #selector(about)))
        menu.addItem(item(L("Quit Present Perfect"), #selector(quit)))
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        return i
    }

    @objc private func showPanelFromMenu() { controller.openPanel() }
    @objc private func toggleLogin() { controller.setOpenAtLogin(!controller.openAtLogin) }
    @objc private func copyDiagnostics() { controller.copyDiagnostics() }
    @objc private func buyCoffee() { NSWorkspace.shared.open(supportURL) }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func about() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}
