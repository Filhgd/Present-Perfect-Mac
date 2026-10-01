import Foundation
import CoreAudio

/// A device that can play sound.
struct AudioOutput: Identifiable, Equatable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let transport: UInt32

    var isBuiltIn: Bool { transport == kAudioDeviceTransportTypeBuiltIn }
    /// Sound through the screen's cable (HDMI or DisplayPort, also via USB-C).
    var isScreen: Bool { transport == kAudioDeviceTransportTypeHDMI || transport == kAudioDeviceTransportTypeDisplayPort }
    var isClickShare: Bool { name.localizedCaseInsensitiveContains("clickshare") }
    /// Virtual devices from Teams, Zoom and similar apps: not something you choose to listen on.
    var isVirtual: Bool {
        transport == kAudioDeviceTransportTypeVirtual || transport == kAudioDeviceTransportTypeAggregate
            || transport == kAudioDeviceTransportTypeAutoAggregate
    }
}

/// A device as listed in the diagnostics.
struct AudioDeviceSummary {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let transport: UInt32
    let hasInput: Bool
    let hasOutput: Bool
}

enum Audio {
    private static let system = AudioObjectID(kAudioObjectSystemObject)

    private static func address(_ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func deviceIDs() -> [AudioDeviceID] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func hasStreams(_ id: AudioDeviceID, _ scope: AudioObjectPropertyScope) -> Bool {
        var addr = address(kAudioDevicePropertyStreams, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr else { return false }
        return size > 0
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func uint32(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var addr = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static func outputs() -> [AudioOutput] {
        deviceIDs().compactMap { id in
            guard hasStreams(id, kAudioObjectPropertyScopeOutput),
                  let uid = string(id, kAudioDevicePropertyDeviceUID) else { return nil }
            return AudioOutput(id: id, uid: uid,
                               name: string(id, kAudioObjectPropertyName) ?? uid,
                               transport: uint32(id, kAudioDevicePropertyTransportType) ?? 0)
        }
    }

    static func allDevices() -> [AudioDeviceSummary] {
        deviceIDs().map { id in
            AudioDeviceSummary(id: id,
                               uid: string(id, kAudioDevicePropertyDeviceUID) ?? "?",
                               name: string(id, kAudioObjectPropertyName) ?? "?",
                               transport: uint32(id, kAudioDevicePropertyTransportType) ?? 0,
                               hasInput: hasStreams(id, kAudioObjectPropertyScopeInput),
                               hasOutput: hasStreams(id, kAudioObjectPropertyScopeOutput))
        }
    }

    static var defaultOutput: AudioDeviceID? { uint32(system, kAudioHardwarePropertyDefaultOutputDevice) }
    static var defaultInput: AudioDeviceID? { uint32(system, kAudioHardwarePropertyDefaultInputDevice) }

    @discardableResult
    static func setDefaultOutput(_ id: AudioDeviceID) -> Bool {
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        var device = id
        return AudioObjectSetPropertyData(system, &addr, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &device) == noErr
    }

    /// Calls `block` on the main queue when devices come or go, or the default output changes.
    static func observe(_ block: @escaping () -> Void) {
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice] {
            var addr = address(selector)
            AudioObjectAddPropertyListenerBlock(system, &addr, DispatchQueue.main) { _, _ in block() }
        }
    }

    /// 'hdmi', 'bltn', 'bluetooth' etc. as readable text.
    static func fourCC(_ value: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: value >> UInt32($0)) }
        let text = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        return text.isEmpty ? String(value) : text
    }
}
