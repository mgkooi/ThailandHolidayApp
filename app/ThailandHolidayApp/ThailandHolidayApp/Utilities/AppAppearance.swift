import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "app.appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Systeem"
        case .light: "Licht"
        case .dark: "Donker"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    static func stored(in defaults: UserDefaults = .standard) -> AppAppearance {
        defaults.string(forKey: storageKey).flatMap(AppAppearance.init(rawValue:)) ?? .system
    }

    func persist(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.storageKey)
    }
}
