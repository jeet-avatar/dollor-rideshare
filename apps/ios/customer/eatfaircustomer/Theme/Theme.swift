import SwiftUI
import EatFairShared

/**
 * Dollor.ai Brand Colors - SYNCED WITH SHARED THEME
 *
 * Source of Truth: eatfair-ios-shared/Sources/EatFairShared/Theme.swift
 *
 * MUST MATCH:
 * - Android: app/src/main/java/com/eatfair/app/ui/theme/Color.kt
 * - Web: apps/web/p2p-platform/frontend/src/app/theme/colors.ts
 */
struct Theme {
    // Primary Brand Color - Green
    static let brandGreen = Lx.Palette.orange  // #06C167 - PRIMARY

    // Secondary/Accent Color - Orange
    static let brandOrange = Lx.Palette.orangeBright  // #F2994A

    // Background Colors
    static let brandGrey = Lx.Palette.bg  // #F5F5F5

    // Text Colors
    static let brandBlack = Lx.Palette.text  // #101010
    static let textGrey = Lx.Palette.textMuted
    static let brandWhite = Color.white

    // Gold for $ logo and premium accents
    static let gold = Color(hex: "FFD700")  // #FFD700

    // Blue for ride/info elements
    static let brandBlue = Lx.Palette.orange  // #3B82F6

    // Status Colors
    static let success = Lx.Palette.success
    static let error = Lx.Palette.error  // #EF4444
    static let warning = Lx.Palette.warning  // #F59E0B
    static let info = brandBlue  // Same as brandBlue

    // Gradients

    // MARK: - Luxury Theme (black + orange) — the app-wide redesign palette
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

    // Primary CTA gradient (orange)
    static let lxButtonGradient = Lx.Palette.buttonGradient
}

// Note: Color.init(hex:) extension is provided by EatFairShared module
// Do NOT duplicate it here to avoid "ambiguous use of init(hex:)" error

// MARK: - Corner Radius
extension Theme {
}

// MARK: - Spacing
extension Theme {
}

// MARK: - Shadows
extension Theme {
}
