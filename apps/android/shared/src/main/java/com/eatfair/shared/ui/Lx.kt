package com.eatfair.shared.ui

import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Design tokens matching the iOS "luxury" theme (Theme.swift lx* values). */
object Lx {
    val Bg = Color(0xFF0B0B0D)
    val Surface = Color(0xFF17171A)
    val Surface2 = Color(0xFF202024)
    val Hairline = Color(0xFF2A2A2E)
    val Orange = Color(0xFFFF7A1A)
    val OrangeBright = Color(0xFFFF9A3D)
    val OrangeDeep = Color(0xFFE85D04)
    val Text = Color.White
    val TextSecondary = Color(0xFFA1A1AA)
    val TextMuted = Color(0xFF6E6E78)
    val Success = Color(0xFF30D158)
    val Error = Color(0xFFFF453A)
    val Warning = Color(0xFFFFB020)
    val Gold = Color(0xFFFFC107)
    val OrangeTint = Color(0xFF3A2208)
    val SuccessTint = Color(0xFF12301B)
    val ErrorTint = Color(0xFF3A1614)
    /** Third-party brand color (Google sign-in button); not part of our palette. */
    val GoogleRed = Color(0xFFDB4437)
    /** Dark label colour for text on orange/green fills (white on #FF7A1A is only 2.6:1). */
    val OnAccent = Color(0xFF0B0B0D)
    val OnSuccess = Color.Black
    /** Route markers: origin is green, destination is orange (same on iOS). */
    val Pickup = Success
    val Dropoff = Orange
    val ButtonGradient = Brush.verticalGradient(listOf(OrangeBright, Orange))

    /** Same radii as iOS `Lx.Radius`. */
    object Radius {
        val chip = 10.dp
        val button = 14.dp
        val card = 16.dp
        val sheet = 24.dp
    }

    /** Same type scale as iOS `Lx.Typography` (iOS text-style point sizes). */
    object FontSize {
        val caption = 12.sp
        val footnote = 13.sp
        val subheadline = 15.sp
        val callout = 16.sp
        val body = 17.sp
        val title = 22.sp
        val largeTitle = 34.sp
    }

    object Spacing {
        val xs = 4.dp
        val s = 8.dp
        val m = 12.dp
        val l = 16.dp
        val xl = 24.dp
    }

    object Size {
        val buttonHeight = 52.dp
        val buttonHeightCompact = 44.dp
    }
}
