package com.eatfair.app.ui.theme

import androidx.compose.ui.graphics.Color

/**
 * Dollor.ai Unified Theme System
 *
 * SOURCE OF TRUTH for all platform colors.
 * Must match exactly across:
 * - iOS: eatfair-ios-shared/Sources/EatFairShared/Theme.swift
 * - Web: apps/web/p2p-platform/frontend/src/app/theme/colors.ts
 *
 * Usage: Import DollorTheme and access colors like DollorTheme.Brand.green
 */
object DollorTheme {

    /**
     * Brand Colors - Primary identity colors
     */
    object Brand {
        val green = Color(0xFFFF7A1A)       // Primary - buttons, highlights

        val orange = Color(0xFFF2994A)      // Secondary - accents, welcome

        val blue = Color(0xFF3B82F6)        // Ride/info elements


        val purple = Color(0xFF8B5CF6)      // AI features, special actions
    }

    /**
     * Background Colors
     */
    object Background {
        val primary = Color(0xFF0B0B0D)     // Main background (grey)
        val secondary = Color(0xFF17171A)   // Cards, surfaces
        val tertiary = Color(0xFF202024)    // Subtle backgrounds
        val dark = Color(0xFF1D1B1E)        // Dark mode background
    }

    /**
     * Text Colors
     */
    object Text {
        val primary = Color(0xFFFFFFFF)     // Main text (black)
        val secondary = Color(0xFFA1A1AA)   // Subtle text (grey)
        val tertiary = Color(0xFF6E6E78)    // Disabled/placeholder
        val link = Brand.green              // Clickable text
    }

    /**
     * Status Colors - For feedback and states
     */
    object Status {
        val success = Color(0xFF30D158)     // Same as brand green

        val error = Color(0xFFFF453A)       // Red

        val warning = Color(0xFFFF9800)     // Orange/amber

        val info = Color(0xFF2196F3)        // Blue

        val pending = Color(0xFFFF9800)     // Same as warning
    }

    /**
     * Order Status Colors
     */
    object OrderStatus {
        // Placed
        val placedBg = Color(0xFFE3F2FD)
        val placedText = Color(0xFF1976D2)

        // Accepted
        val acceptedBg = Color(0xFFF3E5F5)
        val acceptedText = Color(0xFF7B1FA2)

        // Preparing
        val preparingBg = Color(0xFFFFF3E0)
        val preparingText = Color(0xFFE65100)

        // Ready for Pickup
        val readyBg = Color(0xFFE8F5E9)
        val readyText = Color(0xFF388E3C)

        // Picked Up / On the Way
        val onWayBg = Color(0xFFE8F5E9)
        val onWayText = Brand.green

        // Delivered
        val deliveredBg = Color(0xFFE8F5E9)
        val deliveredText = Color(0xFF2E7D32)

        // Cancelled
        val cancelledBg = Color(0xFFFFEBEE)
        val cancelledText = Color(0xFFD32F2F)

        // Default
        val defaultBg = Color(0xFFF5F5F5)
        val defaultText = Color.Gray

        fun getColors(status: String): Pair<Color, Color> = when (status) {
            "Placed" -> placedBg to placedText
            "Accepted" -> acceptedBg to acceptedText
            "Preparing" -> preparingBg to preparingText
            "Ready" -> readyBg to readyText
            "PickedUp", "OnTheWay" -> onWayBg to onWayText
            "Delivered" -> deliveredBg to deliveredText
            "Cancelled" -> cancelledBg to cancelledText
            else -> defaultBg to defaultText
        }
    }

    /**
     * Payment Status Colors
     */
    object PaymentStatus {
        val completed = Color(0xFF4CAF50)
        val processing = Color(0xFFFF9800)
        val failed = Color(0xFFF44336)
        val initiated = Color(0xFF2196F3)
        val refunded = Color(0xFF4CAF50)

        fun getColor(status: String): Color = when (status.lowercase()) {
            "completed", "refunded" -> completed
            "processing", "pending" -> processing
            "failed", "denied" -> failed
            "initiated" -> initiated
            else -> Color.Gray
        }
    }

    /**
     * Deal/Promo Card Gradient Colors
     */
    object Deals {
        val percentage = listOf(Color(0xFFA855F7), Color(0xFFEC4899))  // Purple to pink
        val bogo = listOf(Color(0xFFF97316), Color(0xFFEF4444))        // Orange to red
        val freeDelivery = listOf(Brand.green, Color(0xFF14B8A6))      // Green to teal
        val flatAmount = listOf(Color(0xFF3B82F6), Color(0xFF6366F1))  // Blue to indigo

        fun getGradient(type: String): List<Color> = when (type) {
            "percentage" -> percentage
            "bogo" -> bogo
            "free_delivery" -> freeDelivery
            "flat_amount" -> flatAmount
            else -> listOf(Color(0xFF6B7280), Color(0xFF9CA3AF))
        }

        fun getBadgeColor(type: String): Color = when (type) {
            "percentage" -> Color(0xFFA855F7)
            "bogo" -> Color(0xFFF97316)
            "free_delivery" -> Brand.green
            "flat_amount" -> Color(0xFF3B82F6)
            else -> Color(0xFF6B7280)
        }
    }

    /**
     * Action Colors - For buttons and interactions
     */
    object Action {
        val primary = Brand.green           // Primary buttons
        val secondary = Brand.orange        // Secondary buttons
        val danger = Color(0xFFEF4444)      // Delete, cancel

        val disabled = Color(0xFF2A2A2E)    // Disabled buttons
    }

    /**
     * Rating Colors
     */
    object Rating {
        val star = Color(0xFFFFD700)        // Star yellow
        val excellent = Color(0xFF4CAF50)   // 4.5+
        val good = Color(0xFF8BC34A)        // 3.5-4.5
        val average = Color(0xFFFF9800)     // 2.5-3.5
        val poor = Color(0xFFF44336)        // Below 2.5

        fun getColor(rating: Float): Color = when {
            rating >= 4.5f -> excellent
            rating >= 3.5f -> good
            rating >= 2.5f -> average
            else -> poor
        }
    }

    /**
     * AI/Special Features
     */
    object AI {
        val purple = Color(0xFF9C27B0)
        val pink = Color(0xFFE91E63)
        val gradient = listOf(purple, pink)
    }

    /**
     * Border Colors
     */
    object Border {
        val light = Color(0xFFE5E5E5)
        val medium = Color(0xFFD1D5DB)
        val dark = Color(0xFF9CA3AF)
        val focus = Brand.green
    }

    /**
     * Shadow/Elevation
     */
    object Shadow {
        val light = Color(0x1A000000)       // 10% black
        val medium = Color(0x33000000)      // 20% black
        val dark = Color(0x4D000000)        // 30% black
    }
}
