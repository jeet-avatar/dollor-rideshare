package com.eatfair.app.ui.components

import com.eatfair.shared.ui.Lx
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

// Brand Colors - Enterprise Orange Theme
object DollorBrandColors {
    val PrimaryOrange = Color(0xFFFF6B00)  // Vibrant orange
    val DarkOrange = Color(0xFFE55A00)     // Darker orange for accents
    val LightOrange = Color(0xFFFF8C33)    // Lighter orange
    val GoldAccent = Lx.Gold     // Gold for premium feel
    val BackgroundOrange = Lx.OrangeTint  // Light orange background
}

/**
 * Dollor.ai Logo - Smiley face with $$ eyes
 * Matches the iOS app icon design
 */
@Composable
fun DollorLogo(
    modifier: Modifier = Modifier,
    size: Dp = 80.dp,
    backgroundColor: Color = DollorBrandColors.PrimaryOrange,
    contentColor: Color = Color.White
) {
    Box(
        modifier = modifier
            .size(size)
            .clip(CircleShape)
            .background(backgroundColor),
        contentAlignment = Alignment.Center
    ) {
        Canvas(
            modifier = Modifier.size(size * 0.7f)
        ) {
            val canvasSize = this.size.minDimension
            val centerX = this.size.width / 2
            val centerY = this.size.height / 2

            // Left eye - $ sign
            val eyeOffsetX = canvasSize * 0.22f
            val eyeY = centerY - canvasSize * 0.1f

            // Draw $ eyes as circles with $ inside (simplified)
            drawCircle(
                color = contentColor,
                radius = canvasSize * 0.12f,
                center = Offset(centerX - eyeOffsetX, eyeY)
            )
            drawCircle(
                color = contentColor,
                radius = canvasSize * 0.12f,
                center = Offset(centerX + eyeOffsetX, eyeY)
            )

            // Smile arc
            drawArc(
                color = contentColor,
                startAngle = 20f,
                sweepAngle = 140f,
                useCenter = false,
                topLeft = Offset(centerX - canvasSize * 0.3f, centerY - canvasSize * 0.1f),
                size = androidx.compose.ui.geometry.Size(canvasSize * 0.6f, canvasSize * 0.5f),
                style = Stroke(width = canvasSize * 0.08f, cap = StrokeCap.Round)
            )
        }

        // $ signs in eyes
        Row(
            modifier = Modifier
                .offset(y = (-size * 0.05f)),
            horizontalArrangement = Arrangement.spacedBy(size * 0.18f)
        ) {
            Text(
                text = "$",
                fontSize = (size.value * 0.18f).sp,
                fontWeight = FontWeight.Bold,
                color = backgroundColor
            )
            Text(
                text = "$",
                fontSize = (size.value * 0.18f).sp,
                fontWeight = FontWeight.Bold,
                color = backgroundColor
            )
        }
    }
}

/**
 * Simple circular logo with $ symbol
 * For smaller displays
 */
@Composable
fun DollorLogoSimple(
    modifier: Modifier = Modifier,
    size: Dp = 48.dp,
    backgroundColor: Color = DollorBrandColors.PrimaryOrange,
    contentColor: Color = Color.White
) {
    Box(
        modifier = modifier
            .size(size)
            .clip(CircleShape)
            .background(backgroundColor),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = "$",
            fontSize = (size.value * 0.5f).sp,
            fontWeight = FontWeight.Bold,
            color = contentColor
        )
    }
}

@Preview(showBackground = true)
@Composable
fun DollorLogoPreview() {
    Column(
        modifier = Modifier.padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        DollorLogo(size = 120.dp)
        DollorLogo(size = 80.dp)
        DollorLogoSimple(size = 48.dp)
    }
}
