import Foundation
import Combine

@MainActor
final class PreferencesStore: ObservableObject {
    static let shared = PreferencesStore(defaults: .standard, key: "preferences")

    @Published var preferences: Preferences {
        didSet { save() }
    }

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults, key: String) {
        self.defaults = defaults
        self.key = key
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(Preferences.self, from: data) {
            preferences = decoded.normalized()
        } else {
            preferences = Preferences()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(preferences.normalized()) {
            defaults.set(data, forKey: key)
        }
    }
}
