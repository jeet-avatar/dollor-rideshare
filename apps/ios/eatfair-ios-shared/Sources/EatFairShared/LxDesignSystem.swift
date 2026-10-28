import SwiftUI

/// Dollor design system ("luxury": black + orange). SINGLE SOURCE OF TRUTH for both iOS apps.
/// Android mirrors these values in `shared/ui/Lx.kt`. Never hardcode colors, font sizes,
/// radii or button styling in a view — use these tokens.
public enum Lx {

    // MARK: Colors
    public enum Palette {
        public static let bg = Color(hex: "0B0B0D")
        public static let surface = Color(hex: "17171A")
        public static let surface2 = Color(hex: "202024")
        public static let hairline = Color(hex: "2A2A2E")
        public static let orange = Color(hex: "FF7A1A")
        public static let orangeBright = Color(hex: "FF9A3D")
        public static let orangeDeep = Color(hex: "E85D04")
        public static let text = Color.white
        public static let textSecondary = Color(hex: "A1A1AA")
        public static let textMuted = Color(hex: "6E6E78")
        public static let success = Color(hex: "30D158")
        public static let error = Color(hex: "FF453A")
        public static let warning = Color(hex: "FFB020")
        public static let gold = Color(hex: "FFC107")
        /// Third-party brand color (Google sign-in button); not part of our palette.
        public static let googleBlue = Color(hex: "4285F4")
        /// Text/icons drawn on top of orange or other saturated fills.
        public static let onAccent = Color(hex: "0B0B0D")  // white on FF7A1A is only 2.6:1
        /// Text/icons drawn on top of green success fills.
        public static let onSuccess = Color.black
        /// Drop-shadow base color.
        public static let shadow = Color.black
        /// Route markers: origin is green, destination is orange. Same on every screen and platform.
        public static var pickup: Color { success }
        public static var dropoff: Color { orange }
        public static let buttonGradient = LinearGradient(
            colors: [orangeBright, orange],
            startPoint: .top, endPoint: .bottom
        )
    }

    // MARK: Typography (Dynamic Type text styles, so accessibility sizes keep working)
    public enum Typography {
        public static let largeTitle = Font.largeTitle.weight(.bold)
        public static let title = Font.title2.weight(.bold)
        public static let headline = Font.headline
        public static let body = Font.body
        public static let callout = Font.callout
        public static let subheadline = Font.subheadline
        public static let footnote = Font.footnote
        public static let caption = Font.caption
        public static let button = Font.headline.weight(.semibold)
        public static let buttonCompact = Font.subheadline.weight(.semibold)
        /// Decorative symbol sizes for empty states, headers and hero art.
        public static let icon = Font.system(size: 38)
        public static let iconLarge = Font.system(size: 48)
        public static let iconHero = Font.system(size: 60)
        public static let price = Font.system(.largeTitle, design: .rounded).weight(.bold)
        public static let priceSmall = Font.system(.title3, design: .rounded).weight(.bold)
    }

    // MARK: Shape + spacing
    public enum Radius {
        public static let grabber: CGFloat = 3
        public static let chip: CGFloat = 10
        public static let button: CGFloat = 14
        public static let card: CGFloat = 16
        public static let sheet: CGFloat = 24
    }

    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 8
        public static let m: CGFloat = 12
        public static let l: CGFloat = 16
        public static let xl: CGFloat = 24
    }

    public enum Size {
        public static let buttonHeight: CGFloat = 52
        public static let buttonHeightCompact: CGFloat = 44
    }
}

// MARK: - Money

public extension Lx {
    /// Single place every price is formatted: always dollars and cents ("$9.50"), never rounded.
    enum Money {
        public static func text(_ amount: Double) -> String { String(format: "$%.2f", amount) }
    }
}

// MARK: - Button styles

/// Primary call to action: orange gradient, white label.
public struct LxPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Lx.Typography.button)
            .foregroundColor(isEnabled ? Lx.Palette.onAccent : Lx.Palette.textMuted)
            .frame(maxWidth: .infinity, minHeight: Lx.Size.buttonHeight)
            .background(isEnabled ? AnyShapeStyle(Lx.Palette.buttonGradient) : AnyShapeStyle(Lx.Palette.surface2))
            .clipShape(RoundedRectangle(cornerRadius: Lx.Radius.button, style: .continuous))
            .opacity(configuration.isPressed ? 0.88 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// Secondary action: orange label on a tinted surface with a hairline orange border.
public struct LxSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        let tint = isEnabled ? Lx.Palette.orange : Lx.Palette.textMuted
        configuration.label
            .font(Lx.Typography.button)
            .foregroundColor(tint)
            .frame(maxWidth: .infinity, minHeight: Lx.Size.buttonHeight)
            .background(tint.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: Lx.Radius.button, style: .continuous)
                    .stroke(tint.opacity(0.35), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Lx.Radius.button, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Positive confirmation (Accept): green fill.
public struct LxSuccessButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Lx.Typography.button)
            .foregroundColor(Color.black)
            .frame(maxWidth: .infinity, minHeight: Lx.Size.buttonHeight)
            .background(isEnabled ? Lx.Palette.success : Lx.Palette.surface2)
            .clipShape(RoundedRectangle(cornerRadius: Lx.Radius.button, style: .continuous))
            .opacity(configuration.isPressed ? 0.88 : 1)
    }
}

/// Destructive action (Decline / Cancel): red label on a tinted surface.
public struct LxDestructiveButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Lx.Typography.button)
            .foregroundColor(Lx.Palette.error)
            .frame(maxWidth: .infinity, minHeight: Lx.Size.buttonHeight)
            .background(Lx.Palette.error.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: Lx.Radius.button, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Compact variant for rows with several actions side by side (Decline / Counter / Accept).
public struct LxCompactButtonStyle: ButtonStyle {
    public enum Role { case primary, secondary, success, destructive }
    private let role: Role
    public init(_ role: Role) { self.role = role }

    public func makeBody(configuration: Configuration) -> some View {
        let foreground: Color
        let background: AnyShapeStyle
        switch role {
        case .primary:
            foreground = Lx.Palette.onAccent
            background = AnyShapeStyle(Lx.Palette.buttonGradient)
        case .secondary:
            foreground = Lx.Palette.orange
            background = AnyShapeStyle(Lx.Palette.orange.opacity(0.14))
        case .success:
            foreground = Color.black
            background = AnyShapeStyle(Lx.Palette.success)
        case .destructive:
            foreground = Lx.Palette.error
            background = AnyShapeStyle(Lx.Palette.error.opacity(0.14))
        }
        return configuration.label
            .font(Lx.Typography.buttonCompact)
            .foregroundColor(foreground)
            .frame(maxWidth: .infinity, minHeight: Lx.Size.buttonHeightCompact)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: Lx.Radius.button, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

public extension ButtonStyle where Self == LxPrimaryButtonStyle {
    static var lxPrimary: LxPrimaryButtonStyle { LxPrimaryButtonStyle() }
}
public extension ButtonStyle where Self == LxSecondaryButtonStyle {
    static var lxSecondary: LxSecondaryButtonStyle { LxSecondaryButtonStyle() }
}
public extension ButtonStyle where Self == LxSuccessButtonStyle {
    static var lxSuccess: LxSuccessButtonStyle { LxSuccessButtonStyle() }
}
public extension ButtonStyle where Self == LxDestructiveButtonStyle {
    static var lxDestructive: LxDestructiveButtonStyle { LxDestructiveButtonStyle() }
}
public extension ButtonStyle where Self == LxCompactButtonStyle {
    static func lxCompact(_ role: LxCompactButtonStyle.Role) -> LxCompactButtonStyle { LxCompactButtonStyle(role) }
}

// MARK: - Card surface

public extension View {
    /// Standard card: surface fill, hairline border, shared radius.
    func lxCard() -> some View {
        self
            .background(Lx.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Lx.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Lx.Radius.card, style: .continuous)
                    .stroke(Lx.Palette.hairline, lineWidth: 1)
            )
    }
}
