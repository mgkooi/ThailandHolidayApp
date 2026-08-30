import SwiftUI
import UIKit

enum ReizzColors {
    static let primaryDark = Color(red: 0.0, green: 48.0 / 255.0, blue: 73.0 / 255.0)
    static let primaryLight = Color(red: 102.0 / 255.0, green: 155.0 / 255.0, blue: 188.0 / 255.0)
    static let accent = Color(red: 251.0 / 255.0, green: 139.0 / 255.0, blue: 36.0 / 255.0)

    static let background = dynamic(light: .white, dark: .black)
    static let surface = dynamic(
        light: UIColor(red: 247.0 / 255.0, green: 248.0 / 255.0, blue: 249.0 / 255.0, alpha: 1),
        dark: UIColor(red: 24.0 / 255.0, green: 24.0 / 255.0, blue: 26.0 / 255.0, alpha: 1)
    )
    static let primaryText = dynamic(
        light: UIColor(red: 0, green: 48.0 / 255.0, blue: 73.0 / 255.0, alpha: 1),
        dark: .label
    )
    static let brandForeground = dynamic(
        light: UIColor(red: 0, green: 48.0 / 255.0, blue: 73.0 / 255.0, alpha: 1),
        dark: UIColor(red: 102.0 / 255.0, green: 155.0 / 255.0, blue: 188.0 / 255.0, alpha: 1)
    )
    static let secondaryText = Color(uiColor: .secondaryLabel)
    static let divider = Color(uiColor: .separator)
    static let cardBackground = surface

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in traits.userInterfaceStyle == .dark ? dark : light })
    }
}

extension Color {
    static let reizzPrimaryDark = ReizzColors.primaryDark
    static let reizzPrimaryLight = ReizzColors.primaryLight
    static let reizzAccent = ReizzColors.accent
    static let reizzBackground = ReizzColors.background
    static let reizzSurface = ReizzColors.surface
    static let reizzPrimaryText = ReizzColors.primaryText
    static let reizzBrandForeground = ReizzColors.brandForeground
    static let reizzSecondaryText = ReizzColors.secondaryText
    static let reizzDivider = ReizzColors.divider
    static let reizzCardBackground = ReizzColors.cardBackground
}
