package com.eatfair.app.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color

/**
 * Rider app theme: always dark (black + orange), matching the iOS "luxury" theme.
 * Design tokens live in `com.eatfair.shared.ui.Lx` (single source of truth; mirrors iOS `Lx`).
 * Do not add new colors here; add them to `Lx`.
 */

private val LxDarkScheme = darkColorScheme(
    primary = Color(0xFFFF7A1A),
    onPrimary = Color.White,
    primaryContainer = Color(0xFF3A2208),
    onPrimaryContainer = Color(0xFFFF9A3D),
    secondary = Color(0xFFFF9A3D),
    onSecondary = Color.White,
    secondaryContainer = Color(0xFF202024),
    onSecondaryContainer = Color.White,
    tertiary = Color(0xFF30D158),
    onTertiary = Color.Black,
    error = Color(0xFFFF453A),
    onError = Color.White,
    errorContainer = Color(0xFF3A1614),
    onErrorContainer = Color(0xFFFF453A),
    background = Color(0xFF0B0B0D),
    onBackground = Color.White,
    surface = Color(0xFF17171A),
    onSurface = Color.White,
    surfaceVariant = Color(0xFF202024),
    onSurfaceVariant = Color(0xFFA1A1AA),
    outline = Color(0xFF2A2A2E),
    outlineVariant = Color(0xFF2A2A2E),
    surfaceDim = Color(0xFF0B0B0D),
    surfaceBright = Color(0xFF202024),
    surfaceContainerLowest = Color(0xFF0B0B0D),
    surfaceContainerLow = Color(0xFF131316),
    surfaceContainer = Color(0xFF17171A),
    surfaceContainerHigh = Color(0xFF202024),
    surfaceContainerHighest = Color(0xFF2A2A2E),
)

/** Always dark, matching the iOS "luxury" theme. */
@Composable
fun DollorTheme(
    darkTheme: Boolean = true,
    dynamicColor: Boolean = false,
    content: @Composable () -> Unit
) {
    MaterialTheme(
        colorScheme = LxDarkScheme,
        typography = Typography,
        content = content
    )
}

/**
 * Primary vertical gradient - for backwards compatibility
 */
@Composable
fun primaryVerticalGradient(): Brush {
    return Brush.verticalGradient(listOf(Color(0xFF0B0B0D), Color(0xFF0B0B0D)))
}

@Composable
fun pinkVerticalGradient(): Brush {
    return Brush.verticalGradient(listOf(Color(0xFF0B0B0D), Color(0xFF0B0B0D)))
}

