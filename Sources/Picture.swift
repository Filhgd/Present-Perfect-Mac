import CoreGraphics
import Foundation

/// What the app does with the resolution of a screen. Automatic leaves it to macOS.
enum Picture: String, Codable {
    case automatic, larger, safe, other
}

/// A resolution as it is stored with a remembered screen (chosen under "Other…").
struct SavedMode: Codable, Equatable {
    var width: Int
    var height: Int
    var pixelWidth: Int
    var pixelHeight: Int
    var refresh: Int
}

// Mode flags from IOGraphicsTypes.h.
private let flagDefault: UInt32 = 0x0000_0004
private let flagInterlaced: UInt32 = 0x0000_0040
private let flagStretched: UInt32 = 0x0000_0800
private let flagNative: UInt32 = 0x0200_0000

/// One picture mode a screen offers: the size it looks like, the size of the signal and the refresh rate.
struct PictureMode {
    let mode: CGDisplayMode
    let width: Int             // looks like
    let height: Int
    let pixelWidth: Int        // drawn at this size; twice the size for HiDPI
    let pixelHeight: Int
    let refresh: Double        // 0 when the screen doesn't say
    let flags: UInt32

    init(_ mode: CGDisplayMode) {
        self.mode = mode
        width = mode.width
        height = mode.height
        pixelWidth = mode.pixelWidth
        pixelHeight = mode.pixelHeight
        refresh = mode.refreshRate
        flags = mode.ioFlags
    }

    var isHiDPI: Bool { pixelWidth > width }
    var isNative: Bool { flags & flagNative != 0 }
    var isDefault: Bool { flags & flagDefault != 0 }
    var isStretched: Bool { flags & flagStretched != 0 }
    var hz: Int { Int(refresh.rounded()) }
    var key: String { "\(width)x\(height)/\(pixelWidth)x\(pixelHeight)@\(hz)" }
    var area: Int { pixelWidth * pixelHeight }
    var aspect: Double { Double(width) / Double(max(height, 1)) }
    var size: String { "\(width) × \(height)" }
    var saved: SavedMode { SavedMode(width: width, height: height, pixelWidth: pixelWidth, pixelHeight: pixelHeight, refresh: hz) }

    /// "1920 × 1080 · 60 Hz", for the panel.
    var label: String { hz > 0 ? "\(size) · \(hz) Hz" : size }
}

extension SavedMode {
    var label: String { refresh > 0 ? "\(width) × \(height) · \(refresh) Hz" : "\(width) × \(height)" }
}

extension DisplayInfo {
    /// macOS could not read the screen's information (often a VGA adapter): the list of modes is a guess.
    var isGeneric: Bool { vendor == 0 || vendor == 0x756E_6B6E }   // 'unkn'
}

extension Displays {
    /// The modes macOS offers for this screen, without interlaced TV modes.
    static func modes(of id: CGDirectDisplayID) -> [PictureMode] {
        allModes(of: id).filter { $0.isUsableForDesktopGUI() && $0.ioFlags & flagInterlaced == 0 }.map(PictureMode.init)
    }

    static func allModes(of id: CGDirectDisplayID) -> [CGDisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        return CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] ?? []
    }

    static func currentMode(of id: CGDirectDisplayID) -> PictureMode? {
        CGDisplayCopyDisplayMode(id).map(PictureMode.init)
    }

    /// The mode of every connected screen, to go back to later.
    static func currentModes() -> [CGDirectDisplayID: CGDisplayMode] {
        var result: [CGDirectDisplayID: CGDisplayMode] = [:]
        for d in online() {
            if let mode = CGDisplayCopyDisplayMode(d.id) { result[d.id] = mode }
        }
        return result
    }

    /// Only the screens that are still connected and show something else now.
    static func changes(to target: [CGDirectDisplayID: CGDisplayMode]) -> [CGDirectDisplayID: CGDisplayMode] {
        let now = currentModes()
        return target.filter { id, mode in now[id].map { PictureMode($0).key != PictureMode(mode).key } ?? false }
    }

    /// Changes resolutions for this login session only. macOS keeps its own settings for the screen.
    @discardableResult
    static func setModes(_ modes: [CGDirectDisplayID: CGDisplayMode]) -> Bool {
        guard !modes.isEmpty else { return true }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return false }
        for (id, mode) in modes {
            if CGConfigureDisplayWithDisplayMode(config, id, mode, nil) != .success {
                CGCancelDisplayConfiguration(config)
                return false
            }
        }
        return CGCompleteDisplayConfiguration(config, .forSession) == .success
    }
}

/// The rules behind Larger text and Safe. They only pick from the modes the screen offers.
enum PicturePlan {
    /// The screen's own resolution: marked native by macOS, otherwise its default, otherwise the largest.
    static func native(_ modes: [PictureMode]) -> PictureMode? {
        let byArea: (PictureMode, PictureMode) -> Bool = { $0.area < $1.area }
        return modes.filter(\.isNative).max(by: byArea)
            ?? modes.filter(\.isDefault).max(by: byArea)
            ?? modes.filter { !$0.isHiDPI }.max(by: byArea)
            ?? modes.max(by: byArea)
    }

    /// Larger text: a mode that looks like a smaller screen, so everything is clearly bigger.
    /// About 1920 wide on a 4K screen, about 1280 wide on a smaller one, and at least a quarter
    /// narrower than now. Same shape as the screen. HiDPI modes first: they stay sharp.
    static func larger(_ modes: [PictureMode], from current: PictureMode) -> PictureMode? {
        guard let native = native(modes) else { return nil }
        let target = min(native.pixelWidth >= 2560 ? 1920 : 1280, current.width * 3 / 4)
        let candidates = modes.filter {
            $0.width < current.width && $0.width >= 1024 && !$0.isStretched && abs($0.aspect - native.aspect) < 0.03
        }
        let hidpi = candidates.filter(\.isHiDPI)
        return (hidpi.isEmpty ? candidates : hidpi).min { a, b in
            let da = abs(a.width - target), db = abs(b.width - target)
            if da != db { return da < db }
            // Drawn at the screen's own resolution is sharper.
            let sharpA = a.pixelWidth == native.pixelWidth, sharpB = b.pixelWidth == native.pixelWidth
            if sharpA != sharpB { return sharpA }
            return a.refresh > b.refresh
        }
    }

    /// Safe: a plain, common mode at 60 Hz that almost every projector, cable and adapter handles.
    /// The screen's own resolution up to 1920 × 1200, otherwise 1920 × 1080, 1280 × 720 or 1024 × 768.
    /// Without screen information (often VGA), 1024 × 768 first.
    static func safe(_ modes: [PictureMode], generic: Bool) -> PictureMode? {
        var plain = modes.filter { !$0.isHiDPI && !$0.isStretched && ($0.hz == 0 || (50...61).contains($0.hz)) }
        if plain.isEmpty { plain = modes.filter { !$0.isHiDPI && !$0.isStretched } }
        func closestTo60(_ w: Int, _ h: Int) -> PictureMode? {
            plain.filter { $0.pixelWidth == w && $0.pixelHeight == h }
                .min { abs(($0.hz == 0 ? 60 : $0.hz) - 60) < abs(($1.hz == 0 ? 60 : $1.hz) - 60) }
        }
        var sizes: [(Int, Int)] = []
        if generic {
            sizes = [(1024, 768), (1280, 720)]
        } else {
            if let n = native(modes), n.pixelWidth <= 1920, n.pixelHeight <= 1200 { sizes.append((n.pixelWidth, n.pixelHeight)) }
            sizes += [(1920, 1080), (1280, 720), (1024, 768)]
        }
        for (w, h) in sizes {
            if let m = closestTo60(w, h) { return m }
        }
        return plain.filter { $0.pixelWidth <= 1920 && $0.pixelHeight <= 1200 }.max { $0.area < $1.area }
    }

    /// The mode stored for a remembered screen, or the same size at the nearest refresh rate.
    static func matching(_ saved: SavedMode, in modes: [PictureMode]) -> PictureMode? {
        let sameSize = modes.filter {
            $0.width == saved.width && $0.height == saved.height && $0.pixelWidth == saved.pixelWidth && $0.pixelHeight == saved.pixelHeight
        }
        return sameSize.first { $0.hz == saved.refresh } ?? sameSize.min { abs($0.hz - saved.refresh) < abs($1.hz - saved.refresh) }
    }

    /// The list under "Other…": plain resolutions, largest first, one per size and refresh rate.
    static func others(_ modes: [PictureMode]) -> [PictureMode] {
        var plain = modes.filter { !$0.isHiDPI && !$0.isStretched }
        if plain.isEmpty { plain = modes }
        var seen = Set<String>()
        return plain
            .sorted { ($0.width, $0.height, $0.refresh) > ($1.width, $1.height, $1.refresh) }
            .filter { seen.insert($0.key).inserted }
    }

    /// Menu text: the size, the refresh rate when there is more than one for that size, and "native".
    static func menuLabel(_ m: PictureMode, in list: [PictureMode]) -> String {
        let rates = Set(list.filter { $0.width == m.width && $0.height == m.height }.map(\.hz))
        let text = rates.count > 1 && m.hz > 0 ? "\(m.size) · \(m.hz) Hz" : m.size
        return m.isNative ? L("%@ (native)", text) : text
    }

    /// One line for the diagnostics.
    static func describe(_ m: PictureMode) -> String {
        var tags: [String] = []
        if m.isNative { tags.append("native") }
        if m.isDefault { tags.append("default") }
        if m.isHiDPI { tags.append("hidpi") }
        if m.isStretched { tags.append("stretched") }
        let rate = m.refresh == 0 ? "? Hz" : String(format: "%.2f Hz", m.refresh)
        return "\(m.width)x\(m.height) (pixels \(m.pixelWidth)x\(m.pixelHeight)) \(rate), flags "
            + String(format: "0x%08X", m.flags) + (tags.isEmpty ? "" : " " + tags.joined(separator: " "))
    }
}

/// Build check: switches the first external screen to another resolution and back.
/// Returns 1 only when macOS accepts a switch but the screen doesn't show it.
func testPictureSwitch() -> Int32 {
    guard let d = Displays.online().first(where: { !$0.isBuiltin }) else {
        print("SKIP no external screen")
        return 0
    }
    let modes = Displays.modes(of: d.id)
    guard let original = CGDisplayCopyDisplayMode(d.id) else {
        print("FAIL the screen reports no current mode")
        return 1
    }
    let originalKey = PictureMode(original).key
    let safe = PicturePlan.safe(modes, generic: d.isGeneric)
    let candidate = (safe?.key != originalKey ? safe : nil) ?? modes.first { $0.key != originalKey }
    guard let target = candidate else {
        print("SKIP the screen offers only \(originalKey)")
        return 0
    }
    func settle() { RunLoop.main.run(until: Date().addingTimeInterval(1)) }
    print("switching \(originalKey) to \(target.key)")
    guard Displays.setModes([d.id: target.mode]) else {
        print("SKIP macOS does not allow switching on this machine")
        return 0
    }
    settle()
    var code: Int32 = 0
    let now = Displays.currentMode(of: d.id)?.key ?? "?"
    if now == target.key {
        print("OK   switched to \(now)")
    } else {
        print("FAIL the screen shows \(now) after switching")
        code = 1
    }
    guard Displays.setModes([d.id: original]) else {
        print("FAIL could not switch back")
        return 1
    }
    settle()
    let back = Displays.currentMode(of: d.id)?.key ?? "?"
    if back == originalKey {
        print("OK   back to \(back)")
    } else {
        print("FAIL the screen shows \(back) after switching back")
        code = 1
    }
    return code
}
