package com.eatfair.shared.ui

import com.eatfair.shared.ui.Lx
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.OpenInNew
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.eatfair.shared.config.AppConfig

/**
 * Legal Acceptance Screen
 * Shared component for Customer, Driver, and Restaurant apps
 * Must be shown before users can access the main app
 */
@Composable
fun LegalAcceptanceScreen(
    userType: String = "Customer", // "Customer" or "Driver"
    onAccept: () -> Unit
) {
    val context = LocalContext.current
    var termsAccepted by remember { mutableStateOf(false) }
    var privacyAccepted by remember { mutableStateOf(false) }

    val scrollState = rememberScrollState()

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Lx.Surface2)
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(24.dp)
                .verticalScroll(scrollState),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Spacer(modifier = Modifier.height(32.dp))

            // Header
            Text(
                text = "Welcome to Dollor",
                fontSize = Lx.FontSize.largeTitle,
                fontWeight = FontWeight.Bold,
                color = Lx.Text
            )

            Text(
                text = "Before you continue, please review and accept our terms",
                fontSize = Lx.FontSize.footnote,
                color = Lx.TextSecondary,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(top = 8.dp)
            )

            Spacer(modifier = Modifier.height(32.dp))

            // P2P Model Explanation Card
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(Lx.Radius.card),
                colors = CardDefaults.cardColors(containerColor = Lx.Surface)
            ) {
                Column(modifier = Modifier.padding(20.dp)) {
                    Text(
                        text = "How Dollor Works",
                        fontSize = Lx.FontSize.body,
                        fontWeight = FontWeight.Bold,
                        color = Lx.Text
                    )

                    Spacer(modifier = Modifier.height(12.dp))

                    BulletPoint("Dollor is a peer-to-peer rideshare marketplace connecting riders and independent drivers directly")
                    BulletPoint("Payments are processed securely via Stripe")
                    BulletPoint("Dollor charges a flat ${AppConfig.Rideshare.feeRangeText} platform fee per ride")
                    BulletPoint("Drivers keep the rest of the fare plus 100% of tips")
                    BulletPoint("All users are independent - not employees of Dollor")
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Terms of Service Card
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(Lx.Radius.card),
                colors = CardDefaults.cardColors(containerColor = Lx.Surface)
            ) {
                Column(modifier = Modifier.padding(20.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "Terms of Service",
                            fontSize = Lx.FontSize.callout,
                            fontWeight = FontWeight.SemiBold,
                            color = Lx.Text
                        )

                        TextButton(
                            onClick = {
                                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(AppConfig.Legal.TERMS_OF_SERVICE_URL))
                                context.startActivity(intent)
                            }
                        ) {
                            Text("Read Full Terms")
                            Icon(
                                Icons.Default.OpenInNew,
                                contentDescription = null,
                                modifier = Modifier.size(16.dp).padding(start = 4.dp)
                            )
                        }
                    }

                    Spacer(modifier = Modifier.height(8.dp))

                    Text(
                        text = "By using Dollor, you agree to use the platform for legitimate rides, respect other users, and comply with all applicable laws.",
                        fontSize = Lx.FontSize.footnote,
                        color = Lx.TextSecondary
                    )

                    Spacer(modifier = Modifier.height(12.dp))

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Checkbox(
                            checked = termsAccepted,
                            onCheckedChange = { termsAccepted = it },
                            colors = CheckboxDefaults.colors(
                                checkedColor = Lx.Orange
                            )
                        )
                        Text(
                            text = "I have read and agree to the Terms of Service",
                            fontSize = Lx.FontSize.footnote,
                            color = Lx.Text
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Privacy Policy Card
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(Lx.Radius.card),
                colors = CardDefaults.cardColors(containerColor = Lx.Surface)
            ) {
                Column(modifier = Modifier.padding(20.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "Privacy Policy",
                            fontSize = Lx.FontSize.callout,
                            fontWeight = FontWeight.SemiBold,
                            color = Lx.Text
                        )

                        TextButton(
                            onClick = {
                                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(AppConfig.Legal.PRIVACY_POLICY_URL))
                                context.startActivity(intent)
                            }
                        ) {
                            Text("Read Full Policy")
                            Icon(
                                Icons.Default.OpenInNew,
                                contentDescription = null,
                                modifier = Modifier.size(16.dp).padding(start = 4.dp)
                            )
                        }
                    }

                    Spacer(modifier = Modifier.height(8.dp))

                    Text(
                        text = "We collect only essential data needed to provide our services. Your information is never sold to third parties.",
                        fontSize = Lx.FontSize.footnote,
                        color = Lx.TextSecondary
                    )

                    Spacer(modifier = Modifier.height(12.dp))

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Checkbox(
                            checked = privacyAccepted,
                            onCheckedChange = { privacyAccepted = it },
                            colors = CheckboxDefaults.colors(
                                checkedColor = Lx.Orange
                            )
                        )
                        Text(
                            text = "I have read and agree to the Privacy Policy",
                            fontSize = Lx.FontSize.footnote,
                            color = Lx.Text
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(24.dp))

            // User-specific info
            if (userType == "Driver") {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(Lx.Radius.card),
                    colors = CardDefaults.cardColors(containerColor = Color(0xFF12301B))
                ) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Text(
                            text = "Driver Agreement",
                            fontSize = Lx.FontSize.callout,
                            fontWeight = FontWeight.SemiBold,
                            color = Lx.Success
                        )
                        Text(
                            text = "As a driver, you are an independent contractor. You control your schedule, routes, and which rides to accept.",
                            fontSize = Lx.FontSize.footnote,
                            color = Lx.Success,
                            modifier = Modifier.padding(top = 4.dp)
                        )
                    }
                }
                Spacer(modifier = Modifier.height(16.dp))
            }

            // Continue Button
            Button(
                onClick = onAccept,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(56.dp),
                enabled = termsAccepted && privacyAccepted,
                colors = ButtonDefaults.buttonColors(
                    containerColor = Lx.Orange,
                    disabledContainerColor = Lx.TextSecondary.copy(alpha = 0.3f)
                ),
                shape = RoundedCornerShape(Lx.Radius.button)
            ) {
                Icon(
                    Icons.Default.Check,
                    contentDescription = null,
                    modifier = Modifier.size(20.dp)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = "Accept & Continue",
                    fontSize = Lx.FontSize.callout,
                    fontWeight = FontWeight.SemiBold
                )
            }

            Spacer(modifier = Modifier.height(32.dp))
        }
    }
}

@Composable
private fun BulletPoint(text: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        verticalAlignment = Alignment.Top
    ) {
        Text(
            text = "•",
            fontSize = Lx.FontSize.footnote,
            color = Lx.Orange,
            modifier = Modifier.padding(end = 8.dp, top = 2.dp)
        )
        Text(
            text = text,
            fontSize = Lx.FontSize.footnote,
            color = Lx.TextSecondary
        )
    }
}
