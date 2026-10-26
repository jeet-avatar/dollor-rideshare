package com.eatfair.app.ui.auth

import com.eatfair.shared.config.AppConfig
import com.eatfair.shared.ui.Lx
import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.AttachMoney
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.eatfair.app.ui.components.DollorLogo
import com.eatfair.app.ui.components.DollorBrandColors

@Preview(showBackground = true)
@Composable
fun WelcomeScreenPreview() {
    WelcomeScreen(
        onLoginClick = {},
        onJoinClick = {}
    )
}

@Composable
fun WelcomeScreen(
    onLoginClick: () -> Unit,
    onJoinClick: () -> Unit
) {
    var animateWelcome by remember { mutableStateOf(false) }

    // Animation values
    val logoScale by animateFloatAsState(
        targetValue = if (animateWelcome) 1f else 0.5f,
        animationSpec = spring(dampingRatio = 0.6f, stiffness = 300f),
        label = "logoScale"
    )
    val contentAlpha by animateFloatAsState(
        targetValue = if (animateWelcome) 1f else 0f,
        animationSpec = tween(600),
        label = "contentAlpha"
    )

    LaunchedEffect(Unit) {
        animateWelcome = true
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.linearGradient(
                    colors = listOf(
                        DollorBrandColors.PrimaryOrange,
                        DollorBrandColors.DarkOrange,
                        Lx.OrangeDeep
                    )
                )
            )
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Spacer(modifier = Modifier.weight(0.5f))

            // Logo and App Name
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier.scale(logoScale)
            ) {
                // Use the new DollorLogo (smiley with $$ eyes)
                DollorLogo(
                    size = 100.dp,
                    backgroundColor = Lx.Surface,
                    contentColor = DollorBrandColors.PrimaryOrange
                )

                Spacer(modifier = Modifier.height(20.dp))

                Text(
                    text = "Dollor.ai",
                    fontSize = 48.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White,
                    textAlign = TextAlign.Center
                )

                Spacer(modifier = Modifier.height(8.dp))

                Text(
                    text = "Your Local Rideshare Marketplace",
                    fontSize = Lx.FontSize.callout,
                    color = Color.White.copy(alpha = 0.9f),
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(horizontal = 40.dp)
                )
            }

            Spacer(modifier = Modifier.weight(0.5f))

            // Features List
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp),
                verticalArrangement = Arrangement.spacedBy(20.dp)
            ) {
                FeatureRow(
                    icon = Icons.Default.DirectionsCar,
                    title = "Rideshare",
                    subtitle = "Request a ride — drivers bid for your trip"
                )
                FeatureRow(
                    icon = Icons.Default.LocationOn,
                    title = "Real-Time Tracking",
                    subtitle = "Track your driver live on the map"
                )
                FeatureRow(
                    icon = Icons.Default.AttachMoney,
                    title = "Fair Prices",
                    subtitle = "Transparent ${AppConfig.Rideshare.feeRangeText} platform fees"
                )
            }

            Spacer(modifier = Modifier.weight(0.5f))

            // Action Buttons
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 6.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Button(
                    onClick = onJoinClick,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(56.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = Lx.Surface
                    ),
                    shape = RoundedCornerShape(Lx.Radius.button),
                    elevation = ButtonDefaults.buttonElevation(
                        defaultElevation = 8.dp
                    )
                ) {
                    Text(
                        text = "Get Started",
                        fontSize = Lx.FontSize.body,
                        fontWeight = FontWeight.Bold,
                        color = DollorBrandColors.PrimaryOrange
                    )
                }

                Spacer(modifier = Modifier.height(16.dp))

                TextButton(onClick = onLoginClick) {
                    Text(
                        text = "I already have an account",
                        fontSize = Lx.FontSize.footnote,
                        color = Color.White
                    )
                }
            }

            Spacer(modifier = Modifier.height(50.dp))
        }
    }
}

@Composable
private fun FeatureRow(
    icon: ImageVector,
    title: String,
    subtitle: String
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth()
    ) {
        Box(
            modifier = Modifier
                .size(40.dp)
                .background(
                    Lx.Surface.copy(alpha = 0.2f),
                    RoundedCornerShape(Lx.Radius.chip)
                ),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = icon,
                contentDescription = title,
                tint = Color.White,
                modifier = Modifier.size(24.dp)
            )
        }

        Spacer(modifier = Modifier.width(16.dp))

        Column {
            Text(
                text = title,
                fontSize = Lx.FontSize.callout,
                fontWeight = FontWeight.SemiBold,
                color = Color.White
            )
            Text(
                text = subtitle,
                fontSize = Lx.FontSize.caption,
                color = Color.White.copy(alpha = 0.8f)
            )
        }
    }
}
