package com.eatfair.app.ui.theme

import androidx.compose.ui.graphics.Color

/**
 * Dollor.ai Brand Colors - MUST MATCH iOS Theme.swift EXACTLY
 *
 * iOS Reference (Source of Truth):
 * - Theme.brandGreen = #06C167 (Primary brand color)
 * - Theme.brandOrange = #F2994A (Secondary/accent color)
 * - Theme.brandGrey = #F5F5F5 (Background)
 * - Theme.textGrey = Gray (Text secondary)
 * - Theme.brandBlack = #101010 (Text primary)
 *
 * IMPORTANT: These values are synced with:
 * - iOS: eatfair-ios-shared/Sources/EatFairShared/Theme.swift
 * - Web: apps/web/p2p-platform/frontend (CSS variables)
 */

// Brand Colors - Match iOS Theme.swift exactly
val BrandGreen = Color(0xFFFF7A1A)  // iOS: Theme.brandGreen - PRIMARY BRAND COLOR
val BrandOrange = Color(0xFFF2994A)  // iOS: Theme.brandOrange - ACCENT COLOR
val BrandGrey = Color(0xFF0B0B0D)  // iOS: Theme.brandGrey - BACKGROUND
val TextGrey = Color(0xFF757575)  // iOS: Theme.textGrey - SECONDARY TEXT
val BrandBlack = Color(0xFFFFFFFF)  // iOS: Theme.brandBlack - PRIMARY TEXT
val BrandWhite = Color(0xFF17171A)  // iOS: Theme.brandWhite

// Primary color scheme - Green is primary (like iOS)
val primary = BrandGreen
val secondary = BrandOrange

// Light Theme Colors

// Dark Theme Colors

// Legacy color names for compatibility
val black = BrandBlack
val white = BrandWhite
val pink = Color(0xFFFEB7C8)

// Status colors
val success = BrandGreen
val error = Color(0xFFF44336)
val warning = Color(0xFFFFC107)
val info = Color(0xFF2196F3)

// Order Status Colors (consistent with iOS)
object OrderStatusColors {
    // Placed
    val placedBg = Color(0xFFE3F2FD)
    val placedText = Color(0xFF1976D2)
    // Accepted
    val acceptedBg = Color(0xFFF3E5F5)
    val acceptedText = Color(0xFF7B1FA2)
    // Preparing
    val preparingBg = Color(0xFFFFF3E0)
    val preparingText = Color(0xFFE65100)
    // Ready
    val readyBg = Color(0xFFE8F5E9)
    val readyText = Color(0xFF388E3C)
    // Delivered
    val deliveredBg = Color(0xFFE8F5E9)
    val deliveredText = Color(0xFF2E7D32)
    // Cancelled
    val cancelledBg = Color(0xFFFFEBEE)
    val cancelledText = Color(0xFFD32F2F)
    // Default
    val defaultBg = Color(0xFFF5F5F5)
    val defaultText = Color.Gray
}

// Payment Status Colors
object PaymentStatusColors {
    val completed = Color(0xFF4CAF50)
    val processing = Color(0xFFFF9800)
    val failed = Color(0xFFF44336)
    val initiated = Color(0xFF2196F3)
}

// Purple accent (for AI features, special buttons)

// Warning/Refund background colors

// Danger/Delete background colors

// AI Banner Colors - Match iOS

// Deal Card Gradient Colors - Match iOS

// Multi-Restaurant Promo Colors

// Rating Colors
