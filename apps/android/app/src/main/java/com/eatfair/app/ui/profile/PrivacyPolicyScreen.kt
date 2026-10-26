package com.eatfair.app.ui.profile

import com.eatfair.shared.ui.Lx
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.eatfair.app.ui.common.EFTopAppBar
import com.eatfair.app.ui.theme.primaryVerticalGradient

/**
 * Privacy Policy Screen for Dollor.AI Customer App
 * Required for Google Play Store compliance
 */
@Composable
fun PrivacyPolicyScreen(
    onBackClick: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(primaryVerticalGradient())
    ) {
        EFTopAppBar("Privacy Policy", true, onBackClick)

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(20.dp)
        ) {
            Text(
                text = "Effective Date: January 1, 2025",
                style = MaterialTheme.typography.bodyMedium,
                color = Lx.TextMuted
            )
            Spacer(modifier = Modifier.height(16.dp))

            Text(
                text = "This Privacy Policy explains how Dollor.AI collects, uses, and protects your personal information when you use our rideshare services. We are committed to protecting your privacy and ensuring the security of your data.",
                style = MaterialTheme.typography.bodyMedium,
                color = Lx.Text,
                lineHeight = 22.sp
            )

            Spacer(modifier = Modifier.height(24.dp))

            // Information We Collect
            SectionTitle("Information We Collect")
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = "We collect information you provide directly:\n\n" +
                        "- Account information (name, email, phone number)\n" +
                        "- Pickup and destination addresses and location data\n" +
                        "- Payment information (processed securely via Stripe)\n" +
                        "- Ride history and preferences\n" +
                        "- Communications with support\n\n" +
                        "We also collect information automatically:\n\n" +
                        "- Device information and identifiers\n" +
                        "- App usage and analytics data\n" +
                        "- Location data (when app is in use)",
                style = MaterialTheme.typography.bodyMedium,
                color = Lx.TextSecondary,
                lineHeight = 22.sp
            )

            Spacer(modifier = Modifier.height(24.dp))

            // How We Use Your Information
            SectionTitle("How We Use Your Information")
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = "We use your information to:\n\n" +
                        "- Process and match your ride requests\n" +
                        "- Provide customer support\n" +
                        "- Send ride updates and notifications\n" +
                        "- Improve our services and app experience\n" +
                        "- Prevent fraud and ensure security\n" +
                        "- Comply with legal obligations",
                style = MaterialTheme.typography.bodyMedium,
                color = Lx.TextSecondary,
                lineHeight = 22.sp
            )

            Spacer(modifier = Modifier.height(24.dp))

            // Data Security
            SectionTitle("Data Security")
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = "We implement industry-standard security measures to protect your personal information:\n\n" +
                        "- All data is encrypted during transmission (TLS/SSL)\n" +
                        "- Payment data is processed via PCI-compliant Stripe\n" +
                        "- Access to personal data is restricted to authorized personnel\n" +
                        "- Regular security audits and vulnerability assessments\n\n" +
                        "We comply with CCPA (California Consumer Privacy Act) and other applicable US data protection regulations.",
                style = MaterialTheme.typography.bodyMedium,
                color = Lx.TextSecondary,
                lineHeight = 22.sp
            )

            Spacer(modifier = Modifier.height(24.dp))

            // Your Rights
            SectionTitle("Your Rights")
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = "You have the right to:\n\n" +
                        "- Access your personal information\n" +
                        "- Request correction of inaccurate data\n" +
                        "- Request deletion of your account and data\n" +
                        "- Opt-out of marketing communications\n" +
                        "- Receive a copy of your data in portable format\n" +
                        "- Withdraw consent at any time\n\n" +
                        "To exercise these rights, visit Settings > Delete Account or contact support@dollor.ai",
                style = MaterialTheme.typography.bodyMedium,
                color = Lx.TextSecondary,
                lineHeight = 22.sp
            )

            Spacer(modifier = Modifier.height(24.dp))

            // Third-Party Sharing
            SectionTitle("Third-Party Sharing")
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = "We may share your information with:\n\n" +
                        "- Drivers (limited to trip information)\n" +
                        "- Payment processors (Stripe) for secure transactions\n" +
                        "- Analytics providers (in anonymized form)\n" +
                        "- Law enforcement (when required by law)\n\n" +
                        "We do NOT sell your personal information to third parties.",
                style = MaterialTheme.typography.bodyMedium,
                color = Lx.TextSecondary,
                lineHeight = 22.sp
            )

            Spacer(modifier = Modifier.height(24.dp))

            // Contact Us
            SectionTitle("Contact Us")
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = "If you have questions about this Privacy Policy or wish to exercise your rights, contact us at:\n\n" +
                        "Email: support@dollor.ai\n" +
                        "Website: https://dollor.ai\n" +
                        "Address: San Francisco, CA, United States",
                style = MaterialTheme.typography.bodyMedium,
                color = Lx.TextSecondary,
                lineHeight = 22.sp
            )

            Spacer(modifier = Modifier.height(32.dp))
        }
    }
}

@Composable
private fun SectionTitle(title: String) {
    Text(
        text = title,
        style = MaterialTheme.typography.titleMedium,
        fontWeight = FontWeight.Bold,
        color = Lx.Text
    )
}
