import Combine
import Foundation

enum Choice: String, Codable {
    case present, mirror, desk
}

/// What the app does when a screen it knows connects again.
struct Remembered: Codable, Equatable {
    var name: String
    var choice: Choice
    var soundUID: String?
}

/// Remembered screens, keyed by `DisplayInfo.key`. Kept in the app's preferences.
final class Store: ObservableObject {
    private let defaults: UserDefaults
    private let key = "rememberedScreens"
    @Published private(set) var screens: [String: Remembered] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let saved = try? JSONDecoder().decode([String: Remembered].self, from: data) {
            screens = saved
        }
    }

    subscript(screenKey: String) -> Remembered? {
        get { screens[screenKey] }
        set {
            screens[screenKey] = newValue
            save()
        }
    }

    /// Changes a remembered screen (Settings).
    func update(_ screenKey: String, _ change: (inout Remembered) -> Void) {
        guard var r = screens[screenKey] else { return }
        change(&r)
        self[screenKey] = r
    }

    func forget(_ keys: [String]) {
        for k in keys { screens[k] = nil }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(screens) { defaults.set(data, forKey: key) }
    }
}
