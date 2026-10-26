package com.eatfair.shared.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/**
 * Buttons that mirror the iOS `Lx*ButtonStyle`s (LxDesignSystem.swift). Use these instead of
 * styling Material buttons per screen so every button has the same height, radius, font and colors.
 */
enum class LxButtonRole { Primary, Secondary, Success, Destructive }

@Composable
fun LxButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    role: LxButtonRole = LxButtonRole.Primary,
    compact: Boolean = false,
    enabled: Boolean = true,
    leading: (@Composable () -> Unit)? = null
) {
    val height = if (compact) Lx.Size.buttonHeightCompact else Lx.Size.buttonHeight
    val fontSize = if (compact) Lx.FontSize.subheadline else Lx.FontSize.body
    val shape = RoundedCornerShape(Lx.Radius.button)

    val (container, content, border) = when {
        !enabled -> Triple(Lx.Surface2, Lx.TextMuted, null)
        role == LxButtonRole.Primary -> Triple(Color.Transparent, Lx.Text, null)
        role == LxButtonRole.Secondary -> Triple(Lx.Orange.copy(alpha = 0.12f), Lx.Orange, BorderStroke(1.dp, Lx.Orange.copy(alpha = 0.35f)))
        role == LxButtonRole.Success -> Triple(Lx.Success, Color.Black, null)
        else -> Triple(Lx.Error.copy(alpha = 0.12f), Lx.Error, null)
    }

    val backgroundModifier = if (enabled && role == LxButtonRole.Primary) {
        Modifier.background(Lx.ButtonGradient, shape)
    } else {
        Modifier
    }

    Button(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = height)
            .clip(shape)
            .then(backgroundModifier),
        shape = shape,
        border = border,
        colors = ButtonDefaults.buttonColors(
            containerColor = container,
            contentColor = content,
            disabledContainerColor = Lx.Surface2,
            disabledContentColor = Lx.TextMuted
        )
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Lx.Spacing.s)
        ) {
            leading?.invoke()
            Text(text = text, fontSize = fontSize, fontWeight = FontWeight.SemiBold, color = content)
        }
    }
}
