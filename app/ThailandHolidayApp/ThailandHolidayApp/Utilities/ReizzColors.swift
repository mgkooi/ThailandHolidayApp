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

    static let dateNavigationBackground = dynamic(
        light: UIColor(red: 0, green: 48.0 / 255.0, blue: 73.0 / 255.0, alpha: 1),
        dark: UIColor(red: 102.0 / 255.0, green: 155.0 / 255.0, blue: 188.0 / 255.0, alpha: 1)
    )
    static let dateNavigationForeground = dynamic(
        light: .white,
        dark: UIColor(red: 0, green: 48.0 / 255.0, blue: 73.0 / 255.0, alpha: 1)
    )

    // The light value is PrimaryLight mixed halfway toward white, keeping the
    // fallback heroes branded without the previous visual weight.
    static let heroSurface = dynamic(
        light: UIColor(red: 179.0 / 255.0, green: 205.0 / 255.0, blue: 222.0 / 255.0, alpha: 1),
        dark: UIColor(red: 0, green: 48.0 / 255.0, blue: 73.0 / 255.0, alpha: 1)
    )
    static let heroForeground = dynamic(
        light: UIColor(red: 0, green: 48.0 / 255.0, blue: 73.0 / 255.0, alpha: 1),
        dark: .white
    )
    static let heroSecondaryForeground = dynamic(
        light: UIColor(red: 0, green: 48.0 / 255.0, blue: 73.0 / 255.0, alpha: 0.72),
        dark: UIColor(white: 1, alpha: 0.82)
    )

    static let filterSelectedBackground = primaryDark
    static let filterSelectedForeground = Color.white
    static let filterInactiveBackground = primaryLight
    static let filterInactiveForeground = primaryDark

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
    static let reizzDateNavigationBackground = ReizzColors.dateNavigationBackground
    static let reizzDateNavigationForeground = ReizzColors.dateNavigationForeground
    static let reizzHeroSurface = ReizzColors.heroSurface
    static let reizzHeroForeground = ReizzColors.heroForeground
    static let reizzHeroSecondaryForeground = ReizzColors.heroSecondaryForeground
    static let reizzFilterSelectedBackground = ReizzColors.filterSelectedBackground
    static let reizzFilterSelectedForeground = ReizzColors.filterSelectedForeground
    static let reizzFilterInactiveBackground = ReizzColors.filterInactiveBackground
    static let reizzFilterInactiveForeground = ReizzColors.filterInactiveForeground
}
