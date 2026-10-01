import AppKit
import CoreAudio
import IOKit

/// Plain-text report of what this Mac sees: screens, sound devices, USB devices and
/// related apps. Copied from the menu, so it can be sent to the developer from a meeting room.
enum Diagnostics {
    static let relatedApps = ["clickshare", "barco", "teams", "zoom", "keynote", "powerpoint", "webex", "airplay"]

    static func report(store: Store? = nil) -> String {
        var out: [String] = []
        out.append("\(appName) \(Build.versionString)")
        out.append("macOS \(ProcessInfo.processInfo.operatingSystemVersionString), \(hardwareModel())")
        out.append("Date: \(ISO8601DateFormatter().string(from: Date()))")

        out.append("")
        out.append("SCREENS")
        for d in Displays.online() {
            var line = "- id \(d.id): \(d.name ?? "(mirrored, no name)")"
            line += d.isBuiltin ? ", built-in" : ", external"
            line += ", key \(d.key)"
            line += ", \(Int(d.bounds.width))x\(Int(d.bounds.height)) at \(Int(d.bounds.minX)),\(Int(d.bounds.minY))"
            if d.isMirroring { line += ", mirrors \(d.mirrorOf)" }
            if CGDisplayIsMain(d.id) != 0 { line += ", main" }
            out.append(line)
        }

        out.append("")
        out.append("PICTURE MODES")
        let externals = Displays.online().filter { !$0.isBuiltin }
        if externals.isEmpty { out.append("- no external screen") }
        for d in externals {
            let modes = Displays.modes(of: d.id)
            let current = Displays.currentMode(of: d.id)
            out.append("- id \(d.id): \(modes.count) usable of \(Displays.allModes(of: d.id).count) modes"
                + (d.isGeneric ? ", no screen information (generic)" : ""))
            let native = PicturePlan.native(modes)
            let larger = current.flatMap { PicturePlan.larger(modes, from: $0) }
            let safe = PicturePlan.safe(modes, generic: d.isGeneric)
            out.append("  current: " + (current.map(PicturePlan.describe) ?? "unknown"))
            out.append("  native: " + (native.map(PicturePlan.describe) ?? "unknown"))
            out.append("  larger text: " + (larger.map(PicturePlan.describe) ?? "none"))
            out.append("  safe: " + (safe.map(PicturePlan.describe) ?? "none"))
            let sorted = modes.sorted { a, b in (a.width, a.height, a.pixelWidth, a.refresh) > (b.width, b.height, b.pixelWidth, b.refresh) }
            for m in sorted {
                out.append("  - " + PicturePlan.describe(m))
            }
        }

        out.append("")
        out.append("SOUND DEVICES")
        let defaultOut = Audio.defaultOutput, defaultIn = Audio.defaultInput
        for dev in Audio.allDevices() {
            var flags: [String] = []
            if dev.hasOutput { flags.append("output") }
            if dev.hasInput { flags.append("input") }
            if dev.id == defaultOut { flags.append("DEFAULT OUTPUT") }
            if dev.id == defaultIn { flags.append("DEFAULT INPUT") }
            out.append("- \(dev.name) [\(Audio.fourCC(dev.transport))] \(flags.joined(separator: ", ")), uid \(dev.uid)")
        }

        out.append("")
        out.append("USB DEVICES")
        let usb = usbDevices()
        out.append(contentsOf: usb.isEmpty ? ["- none found"] : usb.map { "- " + $0 })

        out.append("")
        out.append("RELATED APPS RUNNING")
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> String? in
            guard let id = app.bundleIdentifier?.lowercased(),
                  relatedApps.contains(where: { id.contains($0) || (app.localizedName ?? "").lowercased().contains($0) }) else { return nil }
            return "- \(app.localizedName ?? "?") (\(app.bundleIdentifier ?? "?"))"
        }
        out.append(contentsOf: apps.isEmpty ? ["- none"] : apps)

        if let store {
            out.append("")
            out.append("REMEMBERED SCREENS")
            let lines = store.screens.sorted { $0.key < $1.key }.map { entry -> String in
                let key = entry.key, r = entry.value
                let picture = (r.picture ?? .automatic).rawValue + (r.pictureMode.map { " " + $0.label } ?? "")
                return "- \(key): \(r.name), \(r.choice.rawValue), sound \(r.soundUID ?? "not set"), picture \(picture)"
            }
            out.append(contentsOf: lines.isEmpty ? ["- none"] : lines)
        }
        return out.joined(separator: "\n")
    }

    private static func hardwareModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "unknown model" }
        var chars = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &chars, &size, nil, 0)
        return String(cString: chars)
    }

    private static func usbDevices() -> [String] {
        var result: [String] = []
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            let product = property(service, "USB Product Name") as? String ?? "?"
            let vendor = property(service, "USB Vendor Name") as? String ?? ""
            let vid = (property(service, "idVendor") as? NSNumber)?.intValue ?? 0
            let pid = (property(service, "idProduct") as? NSNumber)?.intValue ?? 0
            result.append("\(vendor) \(product) (vendor 0x\(String(vid, radix: 16)), product 0x\(String(pid, radix: 16)))"
                .trimmingCharacters(in: .whitespaces))
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return result
    }

    private static func property(_ service: io_object_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
