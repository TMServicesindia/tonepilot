import SwiftUI
import UIKit

/// TonePilot design tokens — the SwiftUI side of `design/tokens/tonepilot.tokens.json` (platform-neutral;
/// an Android Compose theme is generated from the same file). Screens use these roles only: no raw
/// colours, font sizes, spacing or radii. Direction: a calm instrument companion — restrained dark,
/// one warm accent (TonePilot amber), colour only where it carries meaning.
enum DS {
    // MARK: Colour (semantic roles; light values ready, the app currently runs dark)

    enum Palette {
        static let canvas = dynamic(dark: 0x0B0B0D, light: 0xF4F4F6)
        static let surface = dynamic(dark: 0x151518, light: 0xFFFFFF)
        static let elevated = dynamic(dark: 0x202024, light: 0xECECF0)
        static let border = dynamic(dark: 0x2C2C32, light: 0xD9D9DF, highContrastDark: 0x4A4A52)
        static let divider = dynamic(dark: 0x242429, light: 0xE3E3E8)
        static let textPrimary = dynamic(dark: 0xF5F5F7, light: 0x111114)
        static let textSecondary = dynamic(dark: 0xA3A3AB, light: 0x5C5C66, highContrastDark: 0xC9C9D0)
        static let textTertiary = dynamic(dark: 0x707078, light: 0x8C8C96)
        static let accent = dynamic(dark: 0xFA9E33, light: 0xD9770A)
        static let onAccent = dynamic(dark: 0x121212, light: 0xFFFFFF)
        static let accentMuted = accent.opacity(0.16)
        static let success = dynamic(dark: 0x3DD27A, light: 0x1E9E52)
        static let warning = dynamic(dark: 0xFFD24D, light: 0xB88400)
        static let error = dynamic(dark: 0xFF5A4F, light: 0xD7261B)
        static let info = dynamic(dark: 0x6CC8FF, light: 0x0A74C9)
        static let disabled = dynamic(dark: 0x4A4A50, light: 0xC2C2C8)

        /// Section colours (by repetition group): repeats share a colour.
        static let section: [Color] = [0xF0A04B, 0x4FC1B4, 0xA98BF5, 0xF07AA8, 0xE8D25B, 0x7FD99A, 0x7E8CF0, 0x5CC8E8].map { Color(hex: $0) }

        /// Separated parts: a small marker colour each, never a whole tinted card.
        static func part(_ id: String) -> Color {
            switch id {
            case "vocals": return Color(hex: 0xF07AA8)
            case "drums": return Color(hex: 0xF0A04B)
            case "bass": return Color(hex: 0xA98BF5)
            case "other", "music": return Color(hex: 0x4FC1B4)
            case "lead": return Color(hex: 0x5CC8E8)
            case "backing": return Color(hex: 0x7FD99A)
            case "piano": return Color(hex: 0xE8D25B)
            case "guitar": return Color(hex: 0x7E8CF0)
            default: return textSecondary
            }
        }

        private static func dynamic(dark: UInt32, light: UInt32, highContrastDark: UInt32? = nil) -> Color {
            Color(UIColor { t in
                if t.userInterfaceStyle == .light { return UIColor(hex: light) }
                if t.accessibilityContrast == .high, let h = highContrastDark { return UIColor(hex: h) }
                return UIColor(hex: dark)
            })
        }
    }

    // MARK: Spacing (4-point grid)

    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let screenMargin: CGFloat = 16
        static let sectionGap: CGFloat = 24
        static let componentPadding: CGFloat = 16
        static let inline: CGFloat = 8
    }

    // MARK: Radius

    enum Radius {
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
    }

    // MARK: Sizes

    enum Size {
        /// Apple HIG minimum hit area.
        static let touchTarget: CGFloat = 44
        static let primaryButton: CGFloat = 50
        static let transportPlay: CGFloat = 64
        static let segmentedHeight: CGFloat = 40
        static let artwork: CGFloat = 44
    }

    // MARK: Type (roles → text styles, so Dynamic Type always applies)

    enum Text {
        static let largeTitle = Font.largeTitle.weight(.bold)
        static let screenTitle = Font.title2.weight(.bold)
        static let section = Font.headline
        static let subsection = Font.subheadline.weight(.semibold)
        static let body = Font.body
        static let bodySecondary = Font.subheadline
        static let label = Font.subheadline.weight(.semibold)
        static let caption = Font.footnote
        static let metadata = Font.caption
        static let button = Font.headline
        static let numeric = Font.body.monospacedDigit()
        static let numericSmall = Font.caption.monospacedDigit()
        /// Large readouts on the performance view (chord now / next), legible at arm's length.
        static let display = Font.system(.title, design: .rounded).weight(.bold)
    }

    // MARK: Motion

    enum Motion {
        static let quick: Double = 0.15
        static let standard: Double = 0.25
        /// The standard animation, or none when Reduce Motion is on.
        static func standard(reduceMotion: Bool) -> Animation? { reduceMotion ? nil : .easeInOut(duration: standard) }
    }
}

extension Color {
    init(hex: UInt32) { self.init(UIColor(hex: hex)) }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
