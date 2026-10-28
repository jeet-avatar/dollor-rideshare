package com.eatfair.driver.ui.theme

import android.app.Activity
import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat

private val LightColorScheme = lightColorScheme(
    primary = DollorDriverColors.Blue,
    onPrimary = DollorDriverColors.White,
    primaryContainer = DollorDriverColors.BlueLight,
    onPrimaryContainer = DollorDriverColors.BlueDark,
    secondary = DollorDriverColors.Green,
    onSecondary = DollorDriverColors.White,
    secondaryContainer = DollorDriverColors.GreenLight,
    onSecondaryContainer = DollorDriverColors.GreenDark,
    tertiary = DollorDriverColors.Orange,
    onTertiary = DollorDriverColors.White,
    tertiaryContainer = DollorDriverColors.Orange.copy(alpha = 0.2f),
    onTertiaryContainer = DollorDriverColors.OrangeDark,
    error = DollorDriverColors.Error,
    onError = DollorDriverColors.White,
    errorContainer = DollorDriverColors.Error.copy(alpha = 0.1f),
    onErrorContainer = DollorDriverColors.Error,
    background = DollorDriverColors.Background,
    onBackground = DollorDriverColors.Gray900,
    surface = DollorDriverColors.Surface,
    onSurface = DollorDriverColors.Gray900,
    surfaceVariant = DollorDriverColors.SurfaceVariant,
    onSurfaceVariant = DollorDriverColors.Gray600,
    outline = DollorDriverColors.Gray300,
    outlineVariant = DollorDriverColors.Gray200
)

private val DarkColorScheme = darkColorScheme(
    primary = Color(0xFFFF7A1A),
    onPrimary = Color(0xFF0B0B0D),
    primaryContainer = Color(0xFF3A2208),
    onPrimaryContainer = Color(0xFFFF9A3D),
    secondary = Color(0xFFFF9A3D),
    onSecondary = Color(0xFF0B0B0D),
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

@Composable
fun DollorDriverTheme(
    darkTheme: Boolean = true,
    dynamicColor: Boolean = false,
    content: @Composable () -> Unit
) {
    val colorScheme = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }
        else -> DarkColorScheme
    }

    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as Activity).window
            WindowCompat.getInsetsController(window, view).isAppearanceLightStatusBars = false
        }
    }

    MaterialTheme(
        colorScheme = colorScheme,
        content = content
    )
}
