import AppKit
import CoreAudio
import SwiftUI

/// Renders the panel and the notes in several states, light and dark, to PNG files.
/// Used on the build server to review the design without a screen.
func renderSnapshots(to dir: URL) {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    Look.solidBackground = true
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    let outputs = [
        AudioOutput(id: 11, uid: "hdmi", name: "EPSON PJ", transport: kAudioDeviceTransportTypeHDMI),
        AudioOutput(id: 12, uid: "mac", name: "MacBook Pro Speakers", transport: kAudioDeviceTransportTypeBuiltIn),
        AudioOutput(id: 13, uid: "pods", name: "AirPods Pro", transport: kAudioDeviceTransportTypeBluetooth),
    ]
    let store = Store(defaults: UserDefaults(suiteName: "be.haegdorens.presentperfect.snapshots") ?? .standard)

    func controller(_ configure: (Controller) -> Void) -> Controller {
        let c = Controller(store: store)
        c.outputs = outputs
        c.currentOutput = 12
        c.hasScreen = true
        c.title = L("New screen connected")
        c.subtitle = "EPSON PJ · " + L("%@ is open", "Keynote")
        c.name = "EPSON PJ"
        c.pictureLabel = "1920 × 1080 · 60 Hz"
        configure(c)
        return c
    }

    let panels: [(String, Controller)] = [
        ("1-new-projector", controller { $0.suggested = .present }),
        ("2-present", controller { c in
            c.choice = .present
            c.currentOutput = 11
            c.name = L("Room 2.14")
        }),
        ("3-desk", controller { c in
            c.title = L("New screen connected")
            c.subtitle = "DELL U2723QE"
            c.choice = .desk
            c.name = L("My desk")
        }),
        ("11-resolution-keep", controller { c in
            c.choice = .present
            c.currentOutput = 11
            c.picture = .larger
            c.pictureLabel = "1920 × 1080 · 30 Hz"
            c.keepCountdown = 12
        }),
        ("12-resolution-safe", controller { c in
            c.choice = .mirror
            c.picture = .safe
        }),
        ("13-resolution-other", controller { c in
            c.choice = .present
            c.picture = .other
            c.otherModes = [ModeChoice(id: "1280x720/1280x720@60", label: "1280 × 720", short: "1280 × 720")]
            c.otherKey = "1280x720/1280x720@60"
            c.pictureLabel = "1280 × 720 · 60 Hz"
            c.pictureMessage = L("No answer, so the previous resolution is back.")
        }),
        ("4-no-screen", controller { c in
            c.hasScreen = false
            c.title = L("No screen connected")
            c.subtitle = L("Sound and the shortcut still work")
        }),
    ]
    for (name, c) in panels {
        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            render(PanelView(c: c), appearance: appearance, to: dir.appendingPathComponent("\(name)-\(suffix).png"))
        }
    }

    let notes: [(String, Note, Bool)] = [
        ("5-note-known-room",
         Note(title: L("Room 2.14"),
              lines: [L("Present: %@ is a separate screen", "EPSON PJ"), L("Resolution: %@", L("Safe") + ", 1920 × 1080"),
                      L("Sound on %@", "EPSON PJ"), L("Mac stays awake")],
              actionTitle: L("Change")), true),
        ("6-note-desk", Note(title: L("%@ remembered", L("My desk")), lines: [L("Present Perfect stays quiet at this screen.")]), false),
        ("7-note-unplugged", Note(title: L("Screen disconnected"), lines: [L("Sound plays on %@", L("This Mac"))]), false),
    ]
    for (name, note, hasAction) in notes {
        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            render(NoteView(note: note, action: hasAction ? {} : nil), appearance: appearance,
                   to: dir.appendingPathComponent("\(name)-\(suffix).png"))
        }
    }
    for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
        render(WelcomeView(openAtLogin: true) { _ in }, appearance: appearance, to: dir.appendingPathComponent("0-welcome-\(suffix).png"))
    }
    store["1-1-1"] = Remembered(name: L("Room 2.14"), choice: .present, soundUID: "hdmi", picture: .safe)
    store["2-2-2"] = Remembered(name: L("My desk"), choice: .desk, soundUID: nil)
    store["3-3-3"] = Remembered(name: "Aula Max", choice: .mirror, soundUID: "gone", picture: .other,
                                pictureMode: SavedMode(width: 1280, height: 720, pixelWidth: 1280, pixelHeight: 720, refresh: 60))
    let settingsController = controller { $0.connectedKeys = ["2-2-2"] }
    for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
        render(SettingsView(c: settingsController, store: store, updateAutomatically: .constant(true),
                            onCheckForUpdates: {}, onRestart: {}),
               appearance: appearance, to: dir.appendingPathComponent("10-settings-\(suffix).png"))
    }
    render(AudienceView().frame(width: 960, height: 540), appearance: .darkAqua, to: dir.appendingPathComponent("8-audience-screen.png"))
    render(CurtainView().frame(width: 960, height: 540), appearance: .darkAqua, to: dir.appendingPathComponent("9-curtain.png"))
}

private func render<V: View>(_ view: V, appearance: NSAppearance.Name, to url: URL) {
    let hosting = NSHostingView(rootView: view.padding(24).background(Color(nsColor: .underPageBackgroundColor)))
    let size = hosting.fittingSize
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: appearance)
    window.contentView = hosting
    hosting.frame = NSRect(origin: .zero, size: size)
    window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
    window.orderFrontRegardless()
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    hosting.layoutSubtreeIfNeeded()
    let bounds = hosting.bounds
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 2), pixelsHigh: Int(bounds.height * 2),
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
    rep.size = bounds.size
    hosting.cacheDisplay(in: bounds, to: rep)
    if let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: url)
    }
    window.orderOut(nil)
}
