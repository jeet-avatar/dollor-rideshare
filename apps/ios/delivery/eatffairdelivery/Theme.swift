import SwiftUI
import EatFairShared

struct Theme {
    // Primary Brand Colors - Dollor.ai rideshare (SOURCE OF TRUTH: EatFairShared/Theme.swift)
    static let brandGreen = Lx.Palette.orange  // Brand green
    static let brandOrange = Lx.Palette.orangeBright  // Accent orange
    static let brandBlack = Lx.Palette.text  // Dark text
    static let brandWhite = Color.white

    // Background Colors
    static let cardBackground = Lx.Palette.surface

    // Text Colors
    static let textPrimary = Lx.Palette.text
    static let textSecondary = Lx.Palette.textSecondary
    static let textGrey = Lx.Palette.textMuted
    
    // Status Colors
    static let statusError = Lx.Palette.error  // Red
    static let statusInfo = Lx.Palette.orange  // Blue
    
    // MARK: - Luxury Theme (black + orange) — app-wide redesign palette
    // Orange is the Dollor accent/identity (matches the orange smiley stickers on driver cars).
    static let lxBg           = Lx.Palette.bg  // page canvas (rich black)
    static let lxSurface      = Lx.Palette.surface  // cards / inputs
    static let lxSurface2     = Lx.Palette.surface2  // elevated surfaces
    static let lxHairline     = Lx.Palette.hairline  // borders / dividers
    static let lxOrange       = Lx.Palette.orange  // primary accent
    static let lxOrangeBright = Lx.Palette.orangeBright  // gradient top / highlight
    static let lxOrangeDeep   = Lx.Palette.orangeDeep  // pressed
    static let lxText         = Lx.Palette.text           // primary text
    static let lxTextSecondary = Lx.Palette.textSecondary // secondary text
    static let lxTextMuted    = Lx.Palette.textMuted  // muted / placeholders
    static let lxSuccess      = Lx.Palette.success
    static let lxError        = Lx.Palette.error
    static let lxButtonGradient = Lx.Palette.buttonGradient

    // Gradients
    
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Corner Radius
extension Theme {
    static let cornerRadiusSmall: CGFloat = 8
    static let cornerRadiusMedium: CGFloat = 12
    static let cornerRadiusLarge: CGFloat = 16
}

// MARK: - Spacing
extension Theme {
    static let spacingS: CGFloat = 8
    static let spacingM: CGFloat = 12
    static let spacingL: CGFloat = 16
}

// MARK: - Shadows
extension Theme {
    static let cardShadowRadius: CGFloat = 8
}
