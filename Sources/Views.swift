import AppKit
import SwiftUI

// MARK: - Building blocks

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Rounded, translucent card: the panel and the notes.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background {
                if Look.solidBackground {
                    Color(nsColor: .windowBackgroundColor)
                } else {
                    VisualEffect()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
    }
}

struct KeyCap: View {
    let text: String
    var inverted = false

    init(_ text: String, inverted: Bool = false) {
        self.text = text
        self.inverted = inverted
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .foregroundStyle(inverted ? Color.white.opacity(0.9) : Color.secondary)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(inverted ? Color.white.opacity(0.6) : Color.primary.opacity(0.2)))
    }
}

struct ScreenIcon: View {
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: "display.2")
            .font(.system(size: size * 0.5, weight: .medium))
            .foregroundStyle(Color.accentColor)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).fill(Color.accentColor.opacity(0.14)))
    }
}

struct PillStyle: ButtonStyle {
    var on = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(on ? Color.white : Color.primary)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(on ? Color.black : Color.primary.opacity(configuration.isPressed ? 0.14 : 0.07)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
            .contentShape(Rectangle())
    }
}

/// Blue button that looks the same whether or not the app is in front.
struct ProminentStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .foregroundStyle(Color.white)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor.opacity(configuration.isPressed ? 0.8 : 1)))
            .contentShape(Rectangle())
    }
}

struct NoteBox: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}

/// Small level meter that moves while the test sound plays.
struct Meter: View {
    let active: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08, paused: !active)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.green.opacity(active ? 1 : 0.45))
                        .frame(width: 3, height: barHeight(i, t))
                }
            }
            .frame(height: 12, alignment: .bottom)
        }
    }

    private func barHeight(_ bar: Int, _ time: Double) -> CGFloat {
        guard active else { return 3 }
        return CGFloat(3 + 9 * abs(sin(time * 7 + Double(bar) * 1.3)))
    }
}

// MARK: - Choice tile

struct Tile: View {
    let symbol: String
    let title: String
    let detail: String
    let key: String
    let selected: Bool
    let suggested: Bool
    let enabled: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top) {
                    Image(systemName: symbol).font(.system(size: 21))
                    Spacer()
                    KeyCap(key, inverted: selected)
                }
                .padding(.bottom, 4)
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .opacity(selected ? 0.9 : 0.65)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? Color.accentColor : Color.primary.opacity(hover ? 0.10 : 0.06)))
            .overlay(alignment: .topLeading) {
                if suggested {
                    Text(L("Suggested"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.green))
                        .offset(x: 10, y: -8)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .onHover { hover = $0 }
    }
}

// MARK: - Panel

struct PanelView: View {
    @ObservedObject var c: Controller

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                header
                if c.hasScreen {
                    tiles
                } else {
                    NoteBox(text: L("No projector or TV connected. Plug in a cable to choose how to show your screen."))
                }
                if c.choice == .desk {
                    NoteBox(text: L("Present Perfect leaves this screen and its sound to macOS. When you connect a projector or TV, it asks again."))
                } else {
                    sound
                }
                footer
            }
            .padding(14)
            .frame(width: 470)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ScreenIcon()
            VStack(alignment: .leading, spacing: 1) {
                Text(c.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(c.subtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 6)
            if c.hasScreen && c.choice == .present {
                Button(action: c.toggleCurtain) {
                    HStack(spacing: 5) {
                        Image(systemName: c.curtain ? "eye.slash.fill" : "eye.slash")
                        Text(L("Curtain"))
                        KeyCap("C", inverted: c.curtain)
                    }
                }
                .buttonStyle(PillStyle(on: c.curtain))
                .help(L("Make the audience screen black"))
            } else {
                KeyCap("⌃⌥P")
            }
            moreMenu
        }
    }

    private var moreMenu: some View {
        Menu {
            if c.isRemembered {
                Button(L("Forget This Screen")) { c.forgetScreens() }
            }
            Toggle(L("Open at Login"), isOn: Binding(get: { c.openAtLogin }, set: { c.setOpenAtLogin($0) }))
            Divider()
            Button(L("Copy Diagnostics")) { c.copyDiagnostics() }
            Button(L("Settings…")) { c.showSettings() }
            Button(L("Check for Updates…")) { c.checkForUpdates() }
            Button(L("How It Works…")) { c.showWelcome() }
            Button(L("Buy Me a Coffee…")) { NSWorkspace.shared.open(supportURL) }
            Divider()
            Button(L("Quit Present Perfect")) { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "ellipsis.circle").font(.system(size: 15))
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var tiles: some View {
        HStack(spacing: 8) {
            Tile(symbol: "play.rectangle", title: L("Present"), detail: L("Your notes stay on the Mac"), key: "1",
                 selected: c.choice == .present, suggested: c.suggested == .present && c.choice == nil, enabled: true) {
                c.choose(.present)
            }
            Tile(symbol: "rectangle.on.rectangle", title: L("Mirror"), detail: L("Same picture on both"), key: "2",
                 selected: c.choice == .mirror, suggested: false, enabled: c.canMirror) {
                c.choose(.mirror)
            }
            Tile(symbol: "display", title: L("Desk"), detail: L("Normal monitor, the app stays quiet"), key: "3",
                 selected: c.choice == .desk, suggested: false, enabled: true) {
                c.choose(.desk)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var sound: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L("Sound plays on")).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button(action: c.testSound) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill").font(.system(size: 9))
                        Text(L("Test"))
                        Meter(active: c.playing)
                    }
                }
                .buttonStyle(PillStyle())
                .help(L("Play a short sound on the selected output (T)"))
            }
            if c.visibleOutputs.isEmpty {
                NoteBox(text: L("No sound devices found."))
            } else {
                HStack(spacing: 0) {
                    ForEach(c.visibleOutputs) { output in
                        outputButton(output)
                    }
                }
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.05)))
            }
            if let current = c.currentOutputDevice, current.isScreen {
                Text(L("The volume of a projector or TV is often set with its own remote."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func outputButton(_ output: AudioOutput) -> some View {
        let on = c.currentOutput == output.id
        return Button { c.selectOutput(output.id) } label: {
            Text(c.label(for: output))
                .font(.system(size: 12.5, weight: on ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .padding(.horizontal, 4)
                .foregroundStyle(on ? Color.accentColor : Color.primary)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(on ? Color.accentColor.opacity(0.15) : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(on ? Color.accentColor : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if c.hasScreen && c.choice != nil {
                Toggle(L("Remember as"), isOn: $c.remember)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12.5))
                    .fixedSize()
                TextField(L("Name"), text: $c.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12.5))
                    .disabled(!c.remember)
            } else {
                Text(c.hasScreen ? L("Press 1, 2 or 3 to choose.") : "")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Button(action: c.done) {
                HStack(spacing: 6) {
                    Text(L("Done"))
                    KeyCap("↩", inverted: true)
                }
            }
            .buttonStyle(ProminentStyle())
        }
        .padding(.top, 10)
        .overlay(alignment: .top) { Divider() }
    }
}

// MARK: - Note

struct NoteView: View {
    let note: Note
    let action: (() -> Void)?

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 10) {
                ScreenIcon(size: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(note.title).font(.system(size: 13, weight: .semibold))
                    ForEach(note.lines, id: \.self) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.green)
                            Text(line)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Spacer(minLength: 4)
                if let title = note.actionTitle, let action {
                    Button(title, action: action).controlSize(.small)
                }
            }
            .padding(12)
            .frame(width: 390)
        }
    }
}

// MARK: - Overlays on the other screen

struct CurtainView: View {
    var body: some View {
        ZStack {
            Color.black
            Text(L("We'll start in a moment"))
                .font(.system(size: 22))
                .foregroundStyle(Color.white.opacity(0.35))
        }
    }
}

struct AudienceView: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
            VStack(spacing: 10) {
                Text(L("Audience screen")).font(.system(size: 64, weight: .bold))
                Text(L("The room sees this screen")).font(.system(size: 24))
            }
            .foregroundStyle(Color.white)
        }
    }
}

// MARK: - Welcome (first launch, and "How It Works…")

struct WelcomeStep: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.accentColor.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(text).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct WelcomeView: View {
    let onFinish: (Bool) -> Void
    @State private var openAtLogin: Bool

    init(openAtLogin: Bool, onFinish: @escaping (Bool) -> Void) {
        self.onFinish = onFinish
        _openAtLogin = State(initialValue: openAtLogin)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("Welcome to Present Perfect")).font(.system(size: 20, weight: .bold))
                    Text(L("Connect to a projector or TV and be ready in two key presses."))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                WelcomeStep(symbol: "cable.connector", title: L("Plug in a screen"),
                            text: L("A panel appears. Press 1 to present, 2 to mirror, or 3 for a normal monitor at your desk."))
                WelcomeStep(symbol: "speaker.wave.2", title: L("Choose the sound"),
                            text: L("Pick the projector or TV, your Mac or your headphones. T plays a test sound."))
                WelcomeStep(symbol: "checkmark.circle", title: L("Press Return to remember"),
                            text: L("Next time, that screen is set up by itself. A short note tells you what was done."))
                WelcomeStep(symbol: "keyboard", title: L("Control-Option-P"),
                            text: L("Opens the panel at any moment, also when the menu bar icon is hidden."))
            }
            Toggle(L("Open Present Perfect at login (recommended)"), isOn: $openAtLogin)
                .toggleStyle(.checkbox)
                .font(.system(size: 12.5))
            Divider()
            HStack(spacing: 6) {
                Text(L("Present Perfect is free.")).font(.system(size: 12)).foregroundStyle(.secondary)
                Button(L("Buy me a coffee")) { NSWorkspace.shared.open(supportURL) }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                Spacer()
                Button(L("Get Started")) { onFinish(openAtLogin) }
                    .buttonStyle(ProminentStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}

// MARK: - Settings

/// The app's own language choice. "system" follows the Mac.
struct LanguageOption: Identifiable {
    let id: String     // language code
    let name: String   // in its own language
}

enum Languages {
    static let options = [LanguageOption(id: "en", name: "English"),
                          LanguageOption(id: "nl", name: "Nederlands"),
                          LanguageOption(id: "fr", name: "Français")]

    static var current: String {
        let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? [:]
        guard let first = (domain["AppleLanguages"] as? [String])?.first else { return "system" }
        let code = String(first.prefix(2))
        return options.contains(where: { $0.id == code }) ? code : "system"
    }

    /// Takes effect the next time the app starts.
    static func set(_ code: String) {
        if code == "system" {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        }
    }
}

struct SettingsView: View {
    @ObservedObject var c: Controller
    @ObservedObject var store: Store
    @Binding var updateAutomatically: Bool
    let onCheckForUpdates: () -> Void
    let onRestart: () -> Void
    @State private var language: String
    @State private var languageChanged = false

    init(c: Controller, store: Store, updateAutomatically: Binding<Bool>,
         onCheckForUpdates: @escaping () -> Void, onRestart: @escaping () -> Void) {
        self.c = c
        self.store = store
        _updateAutomatically = updateAutomatically
        self.onCheckForUpdates = onCheckForUpdates
        self.onRestart = onRestart
        _language = State(initialValue: Languages.current)
    }

    private var keys: [String] {
        store.screens.keys.sorted { (store.screens[$0]?.name ?? "").localizedCaseInsensitiveCompare(store.screens[$1]?.name ?? "") == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Remembered screens")).font(.system(size: 13, weight: .semibold))
            if store.screens.isEmpty {
                NoteBox(text: L("No screens remembered yet. Connect a screen, choose what to do and press Return."))
            } else {
                VStack(spacing: 0) {
                    ForEach(keys, id: \.self) { key in
                        row(key)
                        if key != keys.last { Divider().padding(.leading, 44) }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
                Text(L("Changes apply the next time the screen connects."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Text(L("General")).font(.system(size: 13, weight: .semibold)).padding(.top, 8)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L("Language")).font(.system(size: 12.5))
                    Spacer()
                    Picker("", selection: Binding(get: { language }, set: { code in
                        language = code
                        Languages.set(code)
                        languageChanged = true
                    })) {
                        Text(L("Same as Mac")).tag("system")
                        ForEach(Languages.options) { option in
                            Text(option.name).tag(option.id)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                if languageChanged {
                    HStack {
                        Text(L("Restart Present Perfect to use the new language."))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(L("Restart Now"), action: onRestart)
                    }
                }
                Toggle(L("Open at Login"), isOn: Binding(get: { c.openAtLogin }, set: { c.setOpenAtLogin($0) }))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12.5))
                HStack {
                    Toggle(L("Update Automatically"), isOn: $updateAutomatically)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12.5))
                    Spacer()
                    Button(L("Check for Updates…"), action: onCheckForUpdates)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))

            Divider().padding(.top, 4)
            HStack(spacing: 6) {
                Text(L("Version %@", Build.versionString)).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Text(L("Present Perfect is free.")).font(.system(size: 11)).foregroundStyle(.secondary)
                Button(L("Buy me a coffee")) { NSWorkspace.shared.open(supportURL) }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
            }
        }
        .padding(20)
        .frame(width: 580)
    }

    private func row(_ key: String) -> some View {
        let r = store.screens[key]
        return HStack(spacing: 10) {
            Image(systemName: r?.choice == .desk ? "display" : r?.choice == .mirror ? "rectangle.on.rectangle" : "play.rectangle")
                .font(.system(size: 15))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    TextField(L("Name"), text: Binding(get: { store.screens[key]?.name ?? "" },
                                                       set: { value in store.update(key) { $0.name = value } }))
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                    if c.connectedKeys.contains(key) {
                        Text(L("Connected"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.green))
                            .fixedSize()
                    }
                }
                Text(soundText(r)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Picker("", selection: Binding(get: { store.screens[key]?.choice ?? .present },
                                          set: { value in store.update(key) { item in
                                              item.choice = value
                                              if value == .desk { item.soundUID = nil }
                                          } })) {
                Text(L("Present")).tag(Choice.present)
                Text(L("Mirror")).tag(Choice.mirror)
                Text(L("Desk")).tag(Choice.desk)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Button { store.forget([key]) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help(L("Forget"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func soundText(_ r: Remembered?) -> String {
        guard let r else { return "" }
        if r.choice == .desk { return L("Sound: left to macOS") }
        guard let uid = r.soundUID else { return L("Sound: chosen automatically") }
        if let output = c.outputs.first(where: { $0.uid == uid }) { return L("Sound: %@", c.label(for: output)) }
        return L("Sound: a device that is not connected now")
    }
}
