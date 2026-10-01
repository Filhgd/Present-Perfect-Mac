import AppKit
import CoreGraphics

/// "Not mirroring": CoreGraphics uses display ID 0 for no display.
let noDisplay: CGDirectDisplayID = 0

/// One screen as macOS sees it. `key` identifies the same physical screen again later.
struct DisplayInfo: Equatable {
    let id: CGDirectDisplayID
    let isBuiltin: Bool
    let vendor: UInt32
    let model: UInt32
    let serial: UInt32
    let name: String?          // nil while mirrored: macOS then shows one screen for the pair
    let mirrorOf: CGDirectDisplayID
    let bounds: CGRect

    var key: String { "\(vendor)-\(model)-\(serial)" }
    var isMirroring: Bool { mirrorOf != noDisplay }
}

enum Displays {
    /// All connected screens, including mirrored ones.
    static func online() -> [DisplayInfo] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        let names = screenNames()
        return ids.prefix(Int(count)).map { id in
            DisplayInfo(id: id,
                        isBuiltin: CGDisplayIsBuiltin(id) != 0,
                        vendor: CGDisplayVendorNumber(id),
                        model: CGDisplayModelNumber(id),
                        serial: CGDisplaySerialNumber(id),
                        name: names[id],
                        mirrorOf: CGDisplayMirrorsDisplay(id),
                        bounds: CGDisplayBounds(id))
        }
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }

    static func screen(for id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { displayID(of: $0) == id }
    }

    /// The Mac's own screen if it is on, otherwise the screen with the menu bar.
    static func homeScreen() -> NSScreen? {
        NSScreen.screens.first { displayID(of: $0).map { CGDisplayIsBuiltin($0) != 0 } ?? false } ?? NSScreen.screens.first
    }

    private static func screenNames() -> [CGDirectDisplayID: String] {
        var result: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            if let id = displayID(of: screen) { result[id] = screen.localizedName }
        }
        return result
    }

    /// Extended desktop: no screen mirrors another.
    @discardableResult
    static func unmirrorAll() -> Bool {
        let all = online()
        guard all.contains(where: \.isMirroring) else { return true }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return false }
        for d in all where d.isMirroring {
            if CGConfigureDisplayMirrorOfDisplay(config, d.id, noDisplay) != .success {
                CGCancelDisplayConfiguration(config)
                return false
            }
        }
        return CGCompleteDisplayConfiguration(config, .permanently) == .success
    }

    /// Mirror: every external screen shows the Mac's own screen.
    @discardableResult
    static func mirror(externals: [CGDirectDisplayID], onto master: CGDirectDisplayID) -> Bool {
        guard !externals.isEmpty else { return false }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return false }
        if CGConfigureDisplayMirrorOfDisplay(config, master, noDisplay) != .success {
            CGCancelDisplayConfiguration(config)
            return false
        }
        for id in externals where id != master {
            if CGConfigureDisplayMirrorOfDisplay(config, id, master) != .success {
                CGCancelDisplayConfiguration(config)
                return false
            }
        }
        return CGCompleteDisplayConfiguration(config, .permanently) == .success
    }
}
