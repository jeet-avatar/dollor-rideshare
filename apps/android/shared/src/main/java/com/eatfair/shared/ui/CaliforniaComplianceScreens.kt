package com.eatfair.shared.ui

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.Balance
import androidx.compose.material.icons.filled.Block
import androidx.compose.material.icons.filled.DeleteForever
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.PrivacyTip
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * California Privacy Compliance Screen
 * CCPA/CPRA Privacy Rights - Applies to all California businesses
 *
 * As a P2P matchmaking platform, Dollor is subject to CCPA/CPRA privacy requirements.
 */

private val PrimaryBlue = Lx.Orange
private val PrimaryGreen = Lx.Orange
private val ErrorRed = Lx.Error
private val BackgroundGray = Lx.Surface2
private val CardWhite = Color.White
private val TextPrimary = Lx.Text
private val TextSecondary = Lx.TextSecondary

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CCPAPrivacyRightsScreen(
    onBackClick: () -> Unit,
    onDoNotSellClick: () -> Unit = {},
    onDeleteDataClick: () -> Unit = {},
    onAccessDataClick: () -> Unit = {},
    onCorrectDataClick: () -> Unit = {}
) {
    val context = LocalContext.current

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("California Privacy Rights", fontWeight = FontWeight.SemiBold) },
                navigationIcon = {
                    IconButton(onClick = onBackClick) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = CardWhite)
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(BackgroundGray)
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(80.dp)
                    .clip(CircleShape)
                    .background(PrimaryBlue.copy(alpha = 0.1f))
                    .align(Alignment.CenterHorizontally),
                contentAlignment = Alignment.Center
            ) {
                Icon(Icons.Default.PrivacyTip, null, modifier = Modifier.size(40.dp), tint = PrimaryBlue)
            }

            Spacer(modifier = Modifier.height(16.dp))

            Text(
                text = "Your California Privacy Rights",
                fontSize = Lx.FontSize.title,
                fontWeight = FontWeight.Bold,
                color = TextPrimary,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth()
            )

            Text(
                text = "CCPA & CPRA Consumer Rights",
                fontSize = Lx.FontSize.footnote,
                color = TextSecondary,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth()
            )

            Spacer(modifier = Modifier.height(24.dp))

            Card(
                modifier = Modifier.fillMaxWidth().clickable { onDoNotSellClick() },
                shape = RoundedCornerShape(Lx.Radius.button),
                colors = CardDefaults.cardColors(containerColor = ErrorRed.copy(alpha = 0.05f))
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Box(
                        modifier = Modifier.size(48.dp).clip(RoundedCornerShape(Lx.Radius.chip)).background(ErrorRed.copy(alpha = 0.1f)),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(Icons.Default.Block, null, tint = ErrorRed, modifier = Modifier.size(24.dp))
                    }
                    Spacer(modifier = Modifier.width(12.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text("Do Not Sell or Share My Personal Information", fontSize = Lx.FontSize.subheadline, fontWeight = FontWeight.SemiBold, color = TextPrimary)
                        Spacer(modifier = Modifier.height(2.dp))
                        Text("Opt out of the sale or sharing of your data", fontSize = Lx.FontSize.footnote, color = TextSecondary)
                    }
                    Icon(Icons.AutoMirrored.Filled.OpenInNew, null, tint = TextSecondary, modifier = Modifier.size(20.dp))
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(Lx.Radius.button),
                colors = CardDefaults.cardColors(containerColor = PrimaryGreen.copy(alpha = 0.1f))
            ) {
                Row(modifier = Modifier.padding(16.dp), verticalAlignment = Alignment.Top) {
                    Icon(Icons.Default.Verified, null, tint = PrimaryGreen, modifier = Modifier.size(24.dp))
                    Spacer(modifier = Modifier.width(12.dp))
                    Column {
                        Text("Dollor's Commitment", fontWeight = FontWeight.Bold, color = TextPrimary)
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(
                            "We do NOT sell your personal information to third parties. We also do not share your information for cross-context behavioral advertising.",
                            fontSize = Lx.FontSize.footnote, color = TextSecondary, lineHeight = 18.sp
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            Text("Your CCPA/CPRA Rights", fontSize = Lx.FontSize.callout, fontWeight = FontWeight.Bold, color = TextPrimary)

            Spacer(modifier = Modifier.height(12.dp))

            PrivacyRightCard(Icons.Default.Visibility, "Right to Know & Access", "Request a copy of the personal information we've collected about you in the past 12 months.", "Request My Data", onAccessDataClick)
            Spacer(modifier = Modifier.height(8.dp))

            PrivacyRightCard(Icons.Default.DeleteForever, "Right to Delete", "Request deletion of your personal information. Some data may be retained for legal or business purposes.", "Delete My Data", onDeleteDataClick)
            Spacer(modifier = Modifier.height(8.dp))

            PrivacyRightCard(Icons.Default.Edit, "Right to Correct", "Request correction of inaccurate personal information we have about you.", "Correct My Data", onCorrectDataClick)
            Spacer(modifier = Modifier.height(8.dp))

            PrivacyRightCard(Icons.Default.Lock, "Right to Limit Sensitive Data Use", "Limit our use and disclosure of your sensitive personal information to what is necessary for services.", "Manage Preferences") { }

            Spacer(modifier = Modifier.height(16.dp))

            Card(modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(Lx.Radius.button), colors = CardDefaults.cardColors(containerColor = CardWhite)) {
                Row(modifier = Modifier.padding(16.dp), verticalAlignment = Alignment.Top) {
                    Icon(Icons.Default.Schedule, null, tint = PrimaryBlue, modifier = Modifier.size(24.dp))
                    Spacer(modifier = Modifier.width(12.dp))
                    Column {
                        Text("Response Timeframe", fontWeight = FontWeight.Bold, color = TextPrimary)
                        Spacer(modifier = Modifier.height(4.dp))
                        Text("We will respond to your request within 45 days. If additional time is needed, we will notify you of the extension (up to 45 additional days).", fontSize = Lx.FontSize.footnote, color = TextSecondary, lineHeight = 18.sp)
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            Card(modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(Lx.Radius.button), colors = CardDefaults.cardColors(containerColor = CardWhite)) {
                Row(modifier = Modifier.padding(16.dp), verticalAlignment = Alignment.Top) {
                    Icon(Icons.Default.Balance, null, tint = PrimaryGreen, modifier = Modifier.size(24.dp))
                    Spacer(modifier = Modifier.width(12.dp))
                    Column {
                        Text("No Discrimination", fontWeight = FontWeight.Bold, color = TextPrimary)
                        Spacer(modifier = Modifier.height(4.dp))
                        Text("You will not be discriminated against for exercising your privacy rights. We will not deny services, charge different prices, or provide different quality based on your privacy choices.", fontSize = Lx.FontSize.footnote, color = TextSecondary, lineHeight = 18.sp)
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            Card(modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(Lx.Radius.button), colors = CardDefaults.cardColors(containerColor = PrimaryBlue.copy(alpha = 0.1f))) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text("Questions About Your Privacy Rights?", fontWeight = FontWeight.Bold, color = TextPrimary)
                    Spacer(modifier = Modifier.height(8.dp))
                    Text("Contact our Privacy Team:", fontSize = Lx.FontSize.footnote, color = TextSecondary)
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = "privacy@dollor.ai",
                        fontSize = Lx.FontSize.footnote,
                        fontWeight = FontWeight.Medium,
                        color = PrimaryBlue,
                        textDecoration = TextDecoration.Underline,
                        modifier = Modifier.clickable {
                            context.startActivity(Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:privacy@dollor.ai")))
                        }
                    )
                }
            }

            Spacer(modifier = Modifier.height(32.dp))
        }
    }
}

@Composable
private fun PrivacyRightCard(icon: ImageVector, title: String, description: String, actionText: String, onClick: () -> Unit) {
    Card(modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(Lx.Radius.button), colors = CardDefaults.cardColors(containerColor = CardWhite)) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    modifier = Modifier.size(40.dp).clip(RoundedCornerShape(Lx.Radius.chip)).background(PrimaryBlue.copy(alpha = 0.1f)),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(icon, null, tint = PrimaryBlue, modifier = Modifier.size(20.dp))
                }
                Spacer(modifier = Modifier.width(12.dp))
                Text(title, fontSize = Lx.FontSize.subheadline, fontWeight = FontWeight.SemiBold, color = TextPrimary)
            }
            Spacer(modifier = Modifier.height(8.dp))
            Text(description, fontSize = Lx.FontSize.footnote, color = TextSecondary, lineHeight = 18.sp)
            Spacer(modifier = Modifier.height(12.dp))
            OutlinedButton(onClick = onClick, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(Lx.Radius.chip)) {
                Text(actionText)
            }
        }
    }
}
