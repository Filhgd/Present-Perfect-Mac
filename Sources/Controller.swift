import AppKit
import CoreAudio
import IOKit.pwr_mgt
import ServiceManagement

/// A short message in the top-right corner that disappears by itself.
struct Note: Equatable {
    var title: String
    var lines: [String]
    var actionTitle: String? = nil
}

/// One resolution in the "Other…" list.
struct ModeChoice: Identifiable, Equatable {
    let id: String     // PictureMode.key
    let label: String  // in the menu
    let short: String  // on the button
}

/// Decides what happens when screens come and go, and holds the panel's state.
final class Controller: ObservableObject {
    // Panel state
    @Published var title = ""
    @Published var subtitle = ""
    @Published var hasScreen = false
    @Published var canMirror = true
    @Published var choice: Choice?
    @Published var suggested: Choice?
    @Published var curtain = false
    @Published var outputs: [AudioOutput] = []
    @Published var currentOutput: AudioDeviceID?
    @Published var remember = true
    @Published var name = ""
    @Published var playing = false
    @Published var isRemembered = false
    @Published var openAtLogin = false
    // Resolution of the external screen
    @Published var picture: Picture = .automatic
    @Published var otherKey: String?
    @Published var pictureLabel = ""
    @Published var otherModes: [ModeChoice] = []
    @Published var keepCountdown: Int?
    @Published var pictureMessage: String?

    let store: Store

    // Set by the app delegate.
    var onShowPanel: () -> Void = {}
    var onHidePanel: () -> Void = {}
    var onShowNote: (Note, (() -> Void)?) -> Void = { _, _ in }
    var onOverlays: () -> Void = {}
    var onShowWelcome: () -> Void = {}
    var onCheckForUpdates: () -> Void = {}
    var onShowSettings: () -> Void = {}

    private(set) var externals: [DisplayInfo] = []
    private(set) var panelVisible = false
    private(set) var lastApplied = Date.distantPast
    @Published var connectedKeys: Set<String> = []
    private var panelKeys: [String] = []
    private var lastNames: [String: String] = [:]
    private var outputBeforePanel: AudioDeviceID?
    private var autoSwitchedTo: AudioDeviceID?   // the output the app chose itself in this panel
    private var deskSession = false
    private var awake: IOPMAssertionID = 0
    private var pendingScreens: DispatchWorkItem?
    private var started = false
    private var originalModes: [CGDirectDisplayID: CGDisplayMode] = [:]   // before the app changed the resolution
    private var undoModes: [CGDirectDisplayID: CGDisplayMode]?            // while asking "Keep this resolution?"
    private var undoChoice: (picture: Picture, otherKey: String?) = (.automatic, nil)
    private var keepTimer: Timer?

    init(store: Store = Store()) {
        self.store = store
    }

    func start(checkScreensNow: Bool = true) {
        guard !started else { return }
        started = true
        reloadOutputs()
        Audio.observe { [weak self] in self?.reloadOutputs() }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.screensChangedSoon() }
        openAtLogin = SMAppService.mainApp.status == .enabled
        // Screens that are already connected at launch are handled like new connections.
        if checkScreensNow {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.screensChanged() }
        }
    }

    // MARK: Screens

    /// macOS sends several changes in a row; wait until things settle.
    private func screensChangedSoon() {
        pendingScreens?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.screensChanged() }
        pendingScreens = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    func screensChanged() {
        let all = Displays.online()
        let ext = all.filter { !$0.isBuiltin }
        for d in ext { if let n = d.name { lastNames[d.key] = n } }
        let keys = Set(ext.map(\.key))
        let added = ext.filter { !connectedKeys.contains($0.key) }
        let lostAll = !connectedKeys.isEmpty && keys.isEmpty
        externals = ext
        connectedKeys = keys
        canMirror = all.contains(where: \.isBuiltin) && !ext.isEmpty
        hasScreen = !ext.isEmpty

        if !added.isEmpty {
            connected(added)
        } else if lostAll {
            disconnected()
        } else {
            refreshTitles()
            refreshPicture()
            onOverlays()
        }
    }

    private func connected(_ added: [DisplayInfo]) {
        let first = added[0]
        resetPicture(restore: false)
        if let r = store[first.key] {
            deskSession = externals.allSatisfy { store[$0.key]?.choice == .desk }
            guard r.choice != .desk else { return }   // Desk: leave everything to macOS.
            apply(r.choice)
            let pictureLine = applyRememberedPicture(r, display: first)
            let screenName = displayName(first)
            routeSound(preferredUID: r.soundUID, display: first) { [weak self] output in
                guard let self else { return }
                var lines = [r.choice == .mirror ? L("Mirror: same picture on both screens") : L("Present: %@ is a separate screen", screenName)]
                if let pictureLine { lines.append(pictureLine) }
                lines.append(output.map { L("Sound on %@", self.label(for: $0)) } ?? L("Sound stays on %@", self.currentOutputLabel))
                lines.append(L("Mac stays awake"))
                self.onShowNote(Note(title: r.name, lines: lines, actionTitle: L("Change")), { [weak self] in self?.openPanel() })
            }
            return
        }
        deskSession = false
        preparePanel(for: added, isNew: true)
        presentPanel()
    }

    private func disconnected() {
        let quiet = deskSession
        deskSession = false
        curtain = false
        allowSleep()
        resetPicture(restore: false)
        if panelVisible { hidePanel() }
        onOverlays()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            self.reloadOutputs()
            // macOS usually switches back by itself. Make sure sound does not stay on the screen's device.
            if let current = self.currentOutputDevice, current.isScreen || current.isClickShare,
               let mac = self.outputs.first(where: \.isBuiltIn) {
                self.selectOutput(mac.id)
            }
            if !quiet {
                self.onShowNote(Note(title: L("Screen disconnected"), lines: [L("Sound plays on %@", self.currentOutputLabel)]), nil)
            }
        }
    }

    func displayName(_ display: DisplayInfo) -> String {
        display.name ?? lastNames[display.key] ?? store[display.key]?.name ?? L("External screen")
    }

    private var isMirrored: Bool { externals.contains(where: \.isMirroring) }

    // MARK: Panel

    /// Shortcut, menu or "Change": show the panel for the screens that are connected now.
    func openPanel() {
        preparePanel(for: externals, isNew: false)
        presentPanel()
    }

    private func preparePanel(for screens: [DisplayInfo], isNew: Bool) {
        var keys: [String] = []
        for s in screens where !keys.contains(s.key) { keys.append(s.key) }
        panelKeys = keys
        let remembered = screens.first.flatMap { store[$0.key] }
        isRemembered = remembered != nil
        if isNew {
            choice = nil
        } else {
            choice = remembered?.choice ?? (isMirrored ? .mirror : nil)
        }
        suggested = runningPresentationApp() != nil ? .present : nil
        name = remembered?.name ?? screens.first.map { displayName($0) } ?? ""
        remember = true
        hasScreen = !externals.isEmpty
        pictureMessage = nil
        refreshTitles()
        refreshPicture()
    }

    private func refreshTitles() {
        guard let first = externals.first(where: { panelKeys.contains($0.key) }) ?? externals.first else {
            title = L("No screen connected")
            subtitle = L("Sound and the shortcut still work")
            return
        }
        title = store[first.key]?.name ?? L("New screen connected")
        var parts = [displayName(first)]
        if externals.count > 1 { parts.append(L("%@ screens", String(externals.count))) }
        if let app = runningPresentationApp() { parts.append(L("%@ is open", app)) }
        subtitle = parts.joined(separator: " · ")
    }

    private func presentPanel() {
        reloadOutputs()
        outputBeforePanel = currentOutput
        autoSwitchedTo = nil
        panelVisible = true
        onShowPanel()
        onOverlays()
    }

    func hidePanel() {
        guard panelVisible else { return }
        if keepCountdown != nil { undoPicture() }   // closed without Keep: go back
        panelVisible = false
        onHidePanel()
        onOverlays()
    }

    func togglePanel() {
        panelVisible ? hidePanel() : openPanel()
    }

    /// Updates wait while this is true: the panel is open, the curtain is on,
    /// or a screen other than your desk is connected.
    var isPresenting: Bool { panelVisible || curtain || (!externals.isEmpty && !deskSession) }

    /// While the panel is open in Present, the other screen says "Audience screen".
    var showsAudienceLabel: Bool { panelVisible && choice == .present && !curtain }

    func choose(_ c: Choice) {
        guard hasScreen, !(c == .mirror && !canMirror) else { return }
        if c != choice { resetPicture(restore: true) }   // macOS arranges the screens with its own resolution
        choice = c
        apply(c)
        if c == .desk {
            // Undo only the switch the app made itself in this panel; a choice of the user stays.
            if let auto = autoSwitchedTo, auto == currentOutput, let before = outputBeforePanel,
               outputs.contains(where: { $0.id == before }) {
                selectOutput(before)
            }
            autoSwitchedTo = nil
        } else if let first = externals.first, currentOutputDevice?.isBuiltIn ?? true, let screenOut = screenAudio(for: first) {
            selectOutput(screenOut.id)   // Sound follows the screen.
            autoSwitchedTo = screenOut.id
        }
        if name.isEmpty || name == L("My desk") || externals.contains(where: { name == self.displayName($0) }) {
            if c == .desk { name = L("My desk") } else if let first = externals.first { name = displayName(first) }
        }
    }

    private func apply(_ c: Choice) {
        lastApplied = Date()
        switch c {
        case .present:
            Displays.unmirrorAll()
        case .mirror:
            if let master = Displays.online().first(where: \.isBuiltin)?.id {
                Displays.mirror(externals: externals.map(\.id), onto: master)
            }
        case .desk:
            break
        }
        if c != .present { curtain = false }
        if c == .desk { allowSleep() } else { keepAwake() }
        onOverlays()
    }

    func toggleCurtain() {
        guard hasScreen, choice == .present else { return }
        curtain.toggle()
        onOverlays()
    }

    func done() {
        if keepCountdown != nil { keepPicture() }
        guard remember, let c = choice, !panelKeys.isEmpty else {
            hidePanel()
            return
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let n = trimmed.isEmpty ? (c == .desk ? L("My desk") : L("External screen")) : trimmed
        var saved: SavedMode?
        if picture == .other, let d = pictureDisplay, let key = otherKey {
            saved = Displays.modes(of: d.id).first { $0.key == key }?.saved
        }
        let keptPicture: Picture? = c == .desk || picture == .automatic || (picture == .other && saved == nil) ? nil : picture
        for k in panelKeys {
            store[k] = Remembered(name: n, choice: c, soundUID: c == .desk ? nil : currentOutputDevice?.uid,
                                  picture: keptPicture, pictureMode: keptPicture == .other ? saved : nil)
        }
        isRemembered = true
        deskSession = c == .desk && externals.allSatisfy { store[$0.key]?.choice == .desk }
        hidePanel()
        if c == .desk {
            onShowNote(Note(title: L("%@ remembered", n), lines: [L("Present Perfect stays quiet at this screen.")]), nil)
        } else {
            onShowNote(Note(title: L("Saved as %@", n), lines: [L("Next time this screen connects, Present Perfect does this for you.")]), nil)
        }
    }

    func forgetScreens() {
        store.forget(externals.map(\.key))
        isRemembered = false
        refreshTitles()
    }

    // MARK: Resolution

    /// The screen whose resolution the panel changes: the first external screen.
    private var pictureDisplay: DisplayInfo? {
        externals.first(where: { panelKeys.contains($0.key) }) ?? externals.first
    }

    var showsPicture: Bool { hasScreen && (choice == .present || choice == .mirror) }

    func refreshPicture() {
        guard let d = pictureDisplay else {
            pictureLabel = ""
            otherModes = []
            return
        }
        pictureLabel = Displays.currentMode(of: d.id)?.label ?? ""
        let list = PicturePlan.others(Displays.modes(of: d.id))
        otherModes = list.map { ModeChoice(id: $0.key, label: PicturePlan.menuLabel($0, in: list), short: $0.size) }
    }

    /// The mode a choice stands for on this screen, or nil when the screen has none.
    private func target(_ p: Picture, key: String?, saved: SavedMode?, display d: DisplayInfo) -> PictureMode? {
        let modes = Displays.modes(of: d.id)
        switch p {
        case .automatic:
            return nil
        case .larger:
            let base = originalModes[d.id].map(PictureMode.init) ?? Displays.currentMode(of: d.id)
            return base.flatMap { PicturePlan.larger(modes, from: $0) }
        case .safe:
            return PicturePlan.safe(modes, generic: d.isGeneric)
        case .other:
            if let key { return modes.first { $0.key == key } }
            return saved.flatMap { PicturePlan.matching($0, in: modes) }
        }
    }

    /// From the panel. Every change asks "Keep this resolution?" and goes back by itself without an answer.
    func choosePicture(_ p: Picture, otherKey key: String? = nil) {
        guard showsPicture, let d = pictureDisplay, p != picture || key != otherKey else { return }
        let before = Displays.currentModes()
        if originalModes.isEmpty { originalModes = before }
        var wanted = originalModes
        if p != .automatic {
            guard let mode = target(p, key: key, saved: nil, display: d)?.mode else {
                pictureMessage = p == .larger ? L("Text is already as large as this screen allows.")
                                              : L("This screen offers no suitable resolution.")
                return
            }
            wanted = [d.id: mode]
        }
        let changes = Displays.changes(to: wanted)
        pictureMessage = nil
        guard !changes.isEmpty else {
            picture = p   // the screen already shows this
            otherKey = key
            return
        }
        guard Displays.setModes(changes) else {
            pictureMessage = L("macOS did not accept this resolution.")
            return
        }
        if undoModes == nil {
            undoModes = before
            undoChoice = (picture, otherKey)
        }
        picture = p
        otherKey = key
        lastApplied = Date()
        startKeepCountdown()
        refreshPicture()
    }

    func keepPicture() {
        stopKeepCountdown()
        undoModes = nil
    }

    func undoPicture(timedOut: Bool = false) {
        stopKeepCountdown()
        guard let modes = undoModes else { return }
        undoModes = nil
        let changes = Displays.changes(to: modes)
        if !changes.isEmpty {
            Displays.setModes(changes)
            lastApplied = Date()
        }
        picture = undoChoice.picture
        otherKey = undoChoice.otherKey
        pictureMessage = timedOut ? L("No answer, so the previous resolution is back.") : nil
        refreshPicture()
    }

    private func startKeepCountdown() {
        keepTimer?.invalidate()
        keepCountdown = 15
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let n = self.keepCountdown else { return }
            if n <= 1 { self.undoPicture(timedOut: true) } else { self.keepCountdown = n - 1 }
        }
        RunLoop.main.add(timer, forMode: .common)   // keeps counting while a menu is open
        keepTimer = timer
    }

    private func stopKeepCountdown() {
        keepTimer?.invalidate()
        keepTimer = nil
        keepCountdown = nil
    }

    /// Another choice, or a new screen: macOS decides the resolution again.
    private func resetPicture(restore: Bool) {
        stopKeepCountdown()
        undoModes = nil
        if restore && !originalModes.isEmpty {
            let changes = Displays.changes(to: originalModes)
            if !changes.isEmpty { Displays.setModes(changes) }
        }
        originalModes = [:]
        picture = .automatic
        otherKey = nil
        pictureMessage = nil
    }

    /// A remembered screen: set its resolution without asking. Returns the line for the note.
    private func applyRememberedPicture(_ r: Remembered, display d: DisplayInfo) -> String? {
        guard let p = r.picture, p != .automatic else { return nil }
        let before = Displays.currentModes()
        guard let m = target(p, key: nil, saved: r.pictureMode, display: d),
              Displays.setModes(Displays.changes(to: [d.id: m.mode])) else {
            return L("Resolution: not available here, left to macOS")
        }
        originalModes = before
        picture = p
        otherKey = p == .other ? m.key : nil
        return L("Resolution: %@", pictureName(p, m))
    }

    func pictureName(_ p: Picture, _ m: PictureMode) -> String {
        switch p {
        case .larger: return L("Larger text") + ", " + m.size
        case .safe: return L("Safe") + ", " + m.size
        default: return m.label
        }
    }

    // MARK: Sound

    func reloadOutputs() {
        let all = Audio.outputs()
        outputs = all.filter { !$0.isVirtual } + all.filter(\.isVirtual)   // software devices last
        currentOutput = Audio.defaultOutput
    }

    var currentOutputDevice: AudioOutput? { outputs.first { $0.id == currentOutput } }

    var currentOutputLabel: String { currentOutputDevice.map(label(for:)) ?? L("This Mac") }

    /// Screen and ClickShare first, then the Mac, then other speakers and headphones, then software devices. At most four.
    var visibleOutputs: [AudioOutput] {
        let screens = outputs.filter { $0.isScreen || $0.isClickShare }
        let mac = outputs.filter { $0.isBuiltIn && !$0.isScreen }
        let rest = outputs.filter { !$0.isScreen && !$0.isClickShare && !$0.isBuiltIn }
        var list = Array((screens + mac + rest).prefix(4))
        if let current = currentOutputDevice, !list.contains(current) { list[list.count - 1] = current }
        return list
    }

    func label(for output: AudioOutput) -> String {
        if output.isBuiltIn && outputs.filter(\.isBuiltIn).count == 1 { return L("This Mac") }
        return output.name
    }

    func selectOutput(_ id: AudioDeviceID) {
        if Audio.setDefaultOutput(id) { currentOutput = id }
    }

    func testSound() {
        guard let sound = NSSound(named: NSSound.Name("Glass"))?.copy() as? NSSound else { return }
        if let uid = currentOutputDevice?.uid {
            sound.playbackDeviceIdentifier = uid
        }
        sound.play()
        playing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.playing = false }
    }

    /// The sound device of a screen: same name, or the only HDMI/DisplayPort device.
    private func screenAudio(for display: DisplayInfo) -> AudioOutput? {
        let candidates = outputs.filter(\.isScreen)
        let screenName = displayName(display).lowercased()
        if let match = candidates.first(where: {
            let n = $0.name.lowercased()
            return n.contains(screenName) || screenName.contains(n)
        }) {
            return match
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    /// The screen's sound device often appears a moment after the picture. Try for a few seconds.
    private func routeSound(preferredUID: String?, display: DisplayInfo, attempt: Int = 0,
                            completion: @escaping (AudioOutput?) -> Void) {
        reloadOutputs()
        let target = preferredUID.flatMap { uid in outputs.first { $0.uid == uid } } ?? screenAudio(for: display)
        if let target {
            selectOutput(target.id)
            completion(target)
        } else if attempt < 8 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.routeSound(preferredUID: preferredUID, display: display, attempt: attempt + 1, completion: completion)
            }
        } else {
            completion(nil)
        }
    }

    // MARK: Other

    private func runningPresentationApp() -> String? {
        let apps = ["com.apple.iWork.Keynote": "Keynote", "com.microsoft.Powerpoint": "PowerPoint"]
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier, let n = apps[id] { return n }
        }
        return nil
    }

    private func keepAwake() {
        guard awake == 0 else { return }
        IOPMAssertionCreateWithName("PreventUserIdleDisplaySleep" as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                    "Presenting with Present Perfect" as CFString, &awake)
    }

    private func allowSleep() {
        guard awake != 0 else { return }
        IOPMAssertionRelease(awake)
        awake = 0
    }

    func setOpenAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Present Perfect: open at login: \(error)")
        }
        openAtLogin = SMAppService.mainApp.status == .enabled
    }

    func showWelcome() {
        hidePanel()
        onShowWelcome()
    }

    func showSettings() {
        hidePanel()
        onShowSettings()
    }

    func checkForUpdates() {
        hidePanel()
        onCheckForUpdates()
    }

    func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Diagnostics.report(store: store), forType: .string)
        onShowNote(Note(title: L("Diagnostics copied"), lines: [L("Paste them in an e-mail to the developer.")]), nil)
    }
}
