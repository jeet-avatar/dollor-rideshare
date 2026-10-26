package com.eatfair.app.ui.profile

import com.eatfair.shared.config.AppConfig
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
 * Terms & Conditions Screen for Dollor.AI Customer App
 * Required for Google Play Store compliance
 */
@Composable
fun TermsConditionsScreen(
    onBackClick: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(primaryVerticalGradient())
    ) {
        EFTopAppBar("Terms & Conditions", true, onBackClick)

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
                text = "Welcome to Dollor.AI. By using our rideshare services, you agree to these Terms & Conditions. Please read them carefully before booking a ride.",
                style = MaterialTheme.typography.bodyMedium,
                color = Lx.Text,
                lineHeight = 22.sp
            )

            Spacer(modifier = Modifier.height(24.dp))

            // Section 1: Service Description
            SectionTitle("1. Service Description")
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = "Dollor.AI provides a rideshare platform connecting passengers with independent drivers using a flat-fee pricing model:\n\n" +
                        AppConfig.Rideshare.tierLines.joinToString("\n") { "- $it" } + "\n\n" +
                        "Unlike traditional rideshare platforms that take 25-35% commission, our flat-fee model keeps more money with drivers.",
                style = MaterialTheme.typography.bodyMedium,
                color = Lx.TextSecondary,
                lineHeight = 22.sp
            )

            Spacer(modifier = Modifier.height(24.dp))

            // Section 2: Account Requirements
            SectionTitle("2. Account Requirements")
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = "To use Dollor.AI, you must:\n\n" +
                        "- Be at least 18 years of age\n" +
                        "- Provide accurate account information\n" +
                        "- Maintain the security of your login credentials\n" +
                        "- Have a valid payment method\n" +
                        "- Provide accurate pickup and destination addresses\n\n" +
                        "You are responsible for all activity on your account.",
                style = MaterialTheme.typography.bodyMedium,
                color = Lx.TextSecondary,
                lineHeight = 22.sp
            )

            Spacer(modifier = Modifier.height(24.dp))

            // Section 3: Rides and Payments
            SectionTitle("3. Rides and Payments")
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = "When you book a ride:\n\n" +
                        "- Fares are displayed before you accept a driver's bid\n" +
                        "- Platform fee is shown transparently at checkout\n" +
                        "- Payment is processed securely via Stripe\n" +
                        "- Tips to drivers are optional but appreciated\n" +
                        "- 100% of tips go directly to drivers\n\n" +
                        "We reserve the right to cancel rides due to payment issues or other operational reasons.",
                style = MaterialTheme.typography.bodyMedium,
                color = Lx.TextSecondary,
                lineHeight = 22.sp
            )

            Spacer(modifier = Modifier.height(24.dp))

            // Section 4: Ride Terms
            SectionTitle("4. Ride Terms")
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = "Regarding rides:\n\n" +
                        "- Estimated arrival times are approximate\n" +
                        "- Be at your pickup location when the driver arrives\n" +
                        "- Provide accurate pickup and destination details\n" +
                        "- Contact support immediately for ride issues\n" +
                        "- Drivers are independent contractors\n\n" +
                        "We are not responsible for delays caused by traffic or weather conditions.",
                style = MaterialTheme.typography.bodyMedium,
                color = Lx.TextSecondary,
                lineHeight = 22.sp
            )

            Spacer(modifier = Modifier.height(24.dp))

            // Section 5: Refunds and Cancellations
            SectionTitle("5. Refunds and Cancellations")
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = "Our cancellation policy:\n\n" +
                        "- Rides can be cancelled before a driver is matched\n" +
                        "- Cancellations after matching may incur a fee\n" +
                        "- Refunds for disputed charges are reviewed case-by-case\n" +
                        "- Refunds are processed to the original payment method\n" +
                        "- Processing time: 3-5 business days\n\n" +
                        "Contact support@dollor.ai for refund requests.",
                style = MaterialTheme.typography.bodyMedium,
                color = Lx.TextSecondary,
                lineHeight = 22.sp
            )

            Spacer(modifier = Modifier.height(24.dp))

            // Section 6: User Conduct
            SectionTitle("6. User Conduct")
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = "You agree not to:\n\n" +
                        "- Provide false or misleading information\n" +
                        "- Use the service for illegal purposes\n" +
                        "- Harass drivers or other users\n" +
                        "- Attempt to manipulate pricing or promotions\n" +
                        "- Share your account with others\n" +
                        "- Use automated systems to access the platform\n\n" +
                        "Violations may result in account suspension.",
                style = MaterialTheme.typography.bodyMedium,
                color = Lx.TextSecondary,
                lineHeight = 22.sp
            )

            Spacer(modifier = Modifier.height(24.dp))

            // Section 7: Account Termination
            SectionTitle("7. Account Termination")
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = "You may delete your account at any time through Settings. We may suspend or terminate accounts for:\n\n" +
                        "- Violation of these terms\n" +
                        "- Fraudulent activity\n" +
                        "- Abuse of refund policies\n" +
                        "- Inappropriate behavior toward partners\n\n" +
                        "Upon deletion, your data will be removed per our Privacy Policy.",
                style = MaterialTheme.typography.bodyMedium,
                color = Lx.TextSecondary,
                lineHeight = 22.sp
            )

            Spacer(modifier = Modifier.height(24.dp))

            // Section 8: Limitation of Liability
            SectionTitle("8. Limitation of Liability")
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = "Dollor.AI provides the platform \"as is.\" We are not liable for:\n\n" +
                        "- Actions of independent drivers\n" +
                        "- Ride delays beyond our control\n" +
                        "- Indirect or consequential damages\n\n" +
                        "Our liability is limited to the amount you paid for the affected ride.",
                style = MaterialTheme.typography.bodyMedium,
                color = Lx.TextSecondary,
                lineHeight = 22.sp
            )

            Spacer(modifier = Modifier.height(24.dp))

            // Section 9: Changes to Terms
            SectionTitle("9. Changes to Terms")
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = "We may update these Terms & Conditions periodically. Significant changes will be communicated via email or app notification. Continued use of the service after changes constitutes acceptance.",
                style = MaterialTheme.typography.bodyMedium,
                color = Lx.TextSecondary,
                lineHeight = 22.sp
            )

            Spacer(modifier = Modifier.height(24.dp))

            // Contact Section
            SectionTitle("Contact Us")
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = "If you have questions about these Terms & Conditions, contact us at:\n\n" +
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
