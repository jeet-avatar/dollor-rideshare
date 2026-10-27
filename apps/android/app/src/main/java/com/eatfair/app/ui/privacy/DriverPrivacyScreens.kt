package com.eatfair.app.ui.privacy

import com.eatfair.shared.ui.Lx
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

// Brand Colors
private val PrimaryGreen = Lx.Orange
private val BackgroundGrey = Lx.Surface2
private val CardBackground = Lx.Surface
private val TextPrimary = Lx.Text
private val TextSecondary = Lx.TextSecondary
private val ProtectedGreen = Lx.Success
private val SafetyBlue = Lx.Orange

/**
 * Screen 1: What Drivers See
 * Shows customers exactly what information delivery drivers can access
 * Similar to Uber Eats privacy transparency
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WhatDriversSeePage(
    onBackClick: () -> Unit
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("What Drivers See", fontWeight = FontWeight.SemiBold) },
                navigationIcon = {
                    IconButton(onClick = onBackClick) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = CardBackground
                )
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(BackgroundGrey)
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            // Header illustration
            Box(
                modifier = Modifier
                    .size(80.dp)
                    .clip(CircleShape)
                    .background(PrimaryGreen.copy(alpha = 0.1f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Default.Visibility,
                    contentDescription = null,
                    modifier = Modifier.size(40.dp),
                    tint = PrimaryGreen
                )
            }

            Spacer(modifier = Modifier.height(16.dp))

            Text(
                text = "Your privacy is protected",
                fontSize = Lx.FontSize.title,
                fontWeight = FontWeight.Bold,
                color = TextPrimary
            )

            Text(
                text = "Drivers only see limited information needed for your ride",
                fontSize = Lx.FontSize.footnote,
                color = TextSecondary,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(horizontal = 32.dp, vertical = 8.dp)
            )

            Spacer(modifier = Modifier.height(24.dp))

            // What drivers CAN see
            PrivacySection(
                title = "What drivers can see",
                icon = Icons.Default.Check,
                iconTint = ProtectedGreen,
                items = listOf(
                    PrivacyItem(
                        icon = Icons.Default.Person,
                        title = "Your first name only",
                        description = "Last name is never shown to drivers"
                    ),
                    PrivacyItem(
                        icon = Icons.Default.Phone,
                        title = "Masked phone number",
                        description = "Calls go through our secure relay system"
                    ),
                    PrivacyItem(
                        icon = Icons.Default.LocationOn,
                        title = "Destination address",
                        description = "Only visible during active ride"
                    ),
                    PrivacyItem(
                        icon = Icons.Default.Receipt,
                        title = "Ride details",
                        description = "Route and any special instructions"
                    ),
                    PrivacyItem(
                        icon = Icons.Default.Notes,
                        title = "Pickup instructions",
                        description = "Gate codes, building info you provide"
                    )
                )
            )

            Spacer(modifier = Modifier.height(20.dp))

            // What drivers CANNOT see
            PrivacySection(
                title = "What drivers cannot see",
                icon = Icons.Default.Block,
                iconTint = Lx.Error,
                items = listOf(
                    PrivacyItem(
                        icon = Icons.Default.Badge,
                        title = "Your full name",
                        description = "Only your first name is shared"
                    ),
                    PrivacyItem(
                        icon = Icons.Default.Phone,
                        title = "Your real phone number",
                        description = "All calls are anonymized"
                    ),
                    PrivacyItem(
                        icon = Icons.Default.Email,
                        title = "Your email address",
                        description = "Never shared with drivers"
                    ),
                    PrivacyItem(
                        icon = Icons.Default.CreditCard,
                        title = "Payment information",
                        description = "Card details are never visible"
                    ),
                    PrivacyItem(
                        icon = Icons.Default.History,
                        title = "Your ride history",
                        description = "Past rides are private"
                    )
                )
            )

            Spacer(modifier = Modifier.height(24.dp))

            // Info footer
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(Lx.Radius.button),
                colors = CardDefaults.cardColors(containerColor = PrimaryGreen.copy(alpha = 0.1f))
            ) {
                Row(
                    modifier = Modifier.padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        imageVector = Icons.Default.Shield,
                        contentDescription = null,
                        tint = PrimaryGreen,
                        modifier = Modifier.size(24.dp)
                    )
                    Spacer(modifier = Modifier.width(12.dp))
                    Text(
                        text = "Your information is automatically hidden after your ride is complete",
                        fontSize = Lx.FontSize.footnote,
                        color = TextPrimary,
                        lineHeight = 18.sp
                    )
                }
            }

            Spacer(modifier = Modifier.height(32.dp))
        }
    }
}

/**
 * Screen 2: Your Privacy Protection
 * Explains how Dollor.ai protects customer data
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun YourPrivacyPage(
    onBackClick: () -> Unit
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Your Privacy", fontWeight = FontWeight.SemiBold) },
                navigationIcon = {
                    IconButton(onClick = onBackClick) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = CardBackground
                )
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(BackgroundGrey)
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            // Header
            Box(
                modifier = Modifier
                    .size(80.dp)
                    .clip(CircleShape)
                    .background(ProtectedGreen.copy(alpha = 0.1f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Default.Lock,
                    contentDescription = null,
                    modifier = Modifier.size(40.dp),
                    tint = ProtectedGreen
                )
            }

            Spacer(modifier = Modifier.height(16.dp))

            Text(
                text = "How We Protect You",
                fontSize = Lx.FontSize.title,
                fontWeight = FontWeight.Bold,
                color = TextPrimary
            )

            Text(
                text = "Industry-leading privacy and security measures",
                fontSize = Lx.FontSize.footnote,
                color = TextSecondary,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(vertical = 8.dp)
            )

            Spacer(modifier = Modifier.height(24.dp))

            // Privacy Protection Features
            ProtectionCard(
                icon = Icons.Default.PhoneAndroid,
                title = "Anonymous Phone Relay",
                description = "When drivers call, your real number stays hidden. All communication goes through our secure relay system that masks your actual phone number.",
                color = PrimaryGreen
            )

            Spacer(modifier = Modifier.height(12.dp))

            ProtectionCard(
                icon = Icons.Default.LocationOff,
                title = "Address Protection",
                description = "Your destination is only visible to drivers during an active ride. Once complete, it's automatically removed from their view.",
                color = SafetyBlue
            )

            Spacer(modifier = Modifier.height(12.dp))

            ProtectionCard(
                icon = Icons.Default.Star,
                title = "Anonymous Ratings",
                description = "Drivers cannot see who rated them or left feedback. Your ratings and comments remain completely anonymous.",
                color = Lx.Warning
            )

            Spacer(modifier = Modifier.height(12.dp))

            ProtectionCard(
                icon = Icons.Default.Security,
                title = "Encrypted Data",
                description = "All personal information is encrypted using industry-standard TLS/SSL. Payment data is processed through PCI-compliant Stripe.",
                color = Lx.Orange
            )

            Spacer(modifier = Modifier.height(12.dp))

            ProtectionCard(
                icon = Icons.Default.DeleteForever,
                title = "Data Deletion Rights",
                description = "You can request complete deletion of your data at any time through Settings. We comply with CCPA and privacy regulations.",
                color = Lx.Error
            )

            Spacer(modifier = Modifier.height(24.dp))

            // Commitment banner
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(Lx.Radius.button),
                colors = CardDefaults.cardColors(containerColor = CardBackground)
            ) {
                Column(
                    modifier = Modifier.padding(20.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text(
                        text = "Our Commitment",
                        fontSize = Lx.FontSize.callout,
                        fontWeight = FontWeight.Bold,
                        color = TextPrimary
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = "We never sell your personal information to third parties. Your data is used only to provide and improve our services.",
                        fontSize = Lx.FontSize.footnote,
                        color = TextSecondary,
                        textAlign = TextAlign.Center,
                        lineHeight = 20.sp
                    )
                }
            }

            Spacer(modifier = Modifier.height(32.dp))
        }
    }
}

/**
 * Screen 3: Safety Features
 * Shows safety measures in place for customers
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SafetyFeaturesPage(
    onBackClick: () -> Unit
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Safety Features", fontWeight = FontWeight.SemiBold) },
                navigationIcon = {
                    IconButton(onClick = onBackClick) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = CardBackground
                )
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(BackgroundGrey)
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            // Header
            Box(
                modifier = Modifier
                    .size(80.dp)
                    .clip(CircleShape)
                    .background(SafetyBlue.copy(alpha = 0.1f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Default.Shield,
                    contentDescription = null,
                    modifier = Modifier.size(40.dp),
                    tint = SafetyBlue
                )
            }

            Spacer(modifier = Modifier.height(16.dp))

            Text(
                text = "Your Safety Matters",
                fontSize = Lx.FontSize.title,
                fontWeight = FontWeight.Bold,
                color = TextPrimary
            )

            Text(
                text = "Built-in features to keep you safe",
                fontSize = Lx.FontSize.footnote,
                color = TextSecondary,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(vertical = 8.dp)
            )

            Spacer(modifier = Modifier.height(24.dp))

            // Safety Features
            SafetyFeatureCard(
                icon = Icons.Default.VerifiedUser,
                title = "Verified Drivers",
                description = "All drivers undergo background checks and identity verification before they can accept deliveries or rides.",
                features = listOf(
                    "Background check required",
                    "ID verification",
                    "Vehicle inspection (rideshare)",
                    "Continuous monitoring"
                )
            )

            Spacer(modifier = Modifier.height(16.dp))

            SafetyFeatureCard(
                icon = Icons.Default.GpsFixed,
                title = "Real-Time Tracking",
                description = "Track your ride in real-time from pickup to arrival.",
                features = listOf(
                    "Live GPS tracking",
                    "Estimated arrival time",
                    "Route visibility",
                    "Status notifications"
                )
            )

            Spacer(modifier = Modifier.height(16.dp))

            SafetyFeatureCard(
                icon = Icons.Default.Support,
                title = "Support",
                description = "Our support team can help with any safety concerns.",
                features = listOf(
                    "In-app help center",
                    "Email support"
                )
            )

            Spacer(modifier = Modifier.height(24.dp))

            // Emergency contact
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(Lx.Radius.button),
                colors = CardDefaults.cardColors(containerColor = Lx.Error.copy(alpha = 0.1f))
            ) {
                Row(
                    modifier = Modifier.padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        imageVector = Icons.Default.Emergency,
                        contentDescription = null,
                        tint = Lx.Error,
                        modifier = Modifier.size(28.dp)
                    )
                    Spacer(modifier = Modifier.width(12.dp))
                    Column {
                        Text(
                            text = "Emergency?",
                            fontSize = Lx.FontSize.footnote,
                            fontWeight = FontWeight.Bold,
                            color = Lx.Error
                        )
                        Text(
                            text = "Call 911 for immediate emergencies. Use in-app support for non-emergency issues.",
                            fontSize = Lx.FontSize.caption,
                            color = TextSecondary,
                            lineHeight = 16.sp
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(32.dp))
        }
    }
}

// Helper Components

@Composable
private fun PrivacySection(
    title: String,
    icon: ImageVector,
    iconTint: Color,
    items: List<PrivacyItem>
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(Lx.Radius.card),
        colors = CardDefaults.cardColors(containerColor = CardBackground)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    tint = iconTint,
                    modifier = Modifier.size(20.dp)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = title,
                    fontSize = Lx.FontSize.callout,
                    fontWeight = FontWeight.SemiBold,
                    color = TextPrimary
                )
            }

            Spacer(modifier = Modifier.height(16.dp))

            items.forEach { item ->
                Row(
                    modifier = Modifier.padding(vertical = 8.dp),
                    verticalAlignment = Alignment.Top
                ) {
                    Box(
                        modifier = Modifier
                            .size(36.dp)
                            .clip(RoundedCornerShape(Lx.Radius.chip))
                            .background(BackgroundGrey),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = item.icon,
                            contentDescription = null,
                            tint = TextSecondary,
                            modifier = Modifier.size(18.dp)
                        )
                    }
                    Spacer(modifier = Modifier.width(12.dp))
                    Column {
                        Text(
                            text = item.title,
                            fontSize = Lx.FontSize.footnote,
                            fontWeight = FontWeight.Medium,
                            color = TextPrimary
                        )
                        Text(
                            text = item.description,
                            fontSize = Lx.FontSize.caption,
                            color = TextSecondary
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ProtectionCard(
    icon: ImageVector,
    title: String,
    description: String,
    color: Color
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(Lx.Radius.button),
        colors = CardDefaults.cardColors(containerColor = CardBackground)
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            verticalAlignment = Alignment.Top
        ) {
            Box(
                modifier = Modifier
                    .size(44.dp)
                    .clip(RoundedCornerShape(Lx.Radius.chip))
                    .background(color.copy(alpha = 0.1f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    tint = color,
                    modifier = Modifier.size(24.dp)
                )
            }
            Spacer(modifier = Modifier.width(14.dp))
            Column {
                Text(
                    text = title,
                    fontSize = Lx.FontSize.subheadline,
                    fontWeight = FontWeight.SemiBold,
                    color = TextPrimary
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = description,
                    fontSize = Lx.FontSize.footnote,
                    color = TextSecondary,
                    lineHeight = 18.sp
                )
            }
        }
    }
}

@Composable
private fun SafetyFeatureCard(
    icon: ImageVector,
    title: String,
    description: String,
    features: List<String>
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(Lx.Radius.button),
        colors = CardDefaults.cardColors(containerColor = CardBackground)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    modifier = Modifier
                        .size(44.dp)
                        .clip(RoundedCornerShape(Lx.Radius.chip))
                        .background(SafetyBlue.copy(alpha = 0.1f)),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = icon,
                        contentDescription = null,
                        tint = SafetyBlue,
                        modifier = Modifier.size(24.dp)
                    )
                }
                Spacer(modifier = Modifier.width(14.dp))
                Column {
                    Text(
                        text = title,
                        fontSize = Lx.FontSize.subheadline,
                        fontWeight = FontWeight.SemiBold,
                        color = TextPrimary
                    )
                    Spacer(modifier = Modifier.height(2.dp))
                    Text(
                        text = description,
                        fontSize = Lx.FontSize.footnote,
                        color = TextSecondary,
                        lineHeight = 18.sp
                    )
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            features.forEach { feature ->
                Row(
                    modifier = Modifier.padding(vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        imageVector = Icons.Default.CheckCircle,
                        contentDescription = null,
                        tint = ProtectedGreen,
                        modifier = Modifier.size(16.dp)
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = feature,
                        fontSize = Lx.FontSize.footnote,
                        color = TextSecondary
                    )
                }
            }
        }
    }
}

private data class PrivacyItem(
    val icon: ImageVector,
    val title: String,
    val description: String
)
