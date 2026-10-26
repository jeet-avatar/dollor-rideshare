package com.eatfair.app.ui.auth

import com.eatfair.shared.ui.Lx
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckBox
import androidx.compose.material.icons.filled.CheckBoxOutlineBlank
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Description
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.eatfair.app.ui.theme.BrandGreen
import com.eatfair.app.ui.theme.BrandGrey
import com.eatfair.app.ui.theme.BrandOrange
import com.eatfair.app.ui.theme.BrandBlack
import com.eatfair.app.ui.theme.TextGrey

/**
 * LegalAcceptanceScreen - Terms and Privacy acceptance screen
 * Matches iOS LegalAcceptanceView for platform parity
 * Required for App Store/Play Store compliance
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LegalAcceptanceScreen(
    onAccept: () -> Unit
) {
    var acceptedTerms by remember { mutableStateOf(false) }
    var acceptedPrivacy by remember { mutableStateOf(false) }
    var showTermsSheet by remember { mutableStateOf(false) }
    var showPrivacySheet by remember { mutableStateOf(false) }

    val canContinue = acceptedTerms && acceptedPrivacy

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(BrandGrey)
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Spacer(modifier = Modifier.weight(0.5f))

            // Header
            Column(
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Icon(
                    imageVector = Icons.Default.Description,
                    contentDescription = "Legal Documents",
                    modifier = Modifier.size(60.dp),
                    tint = BrandOrange
                )

                Spacer(modifier = Modifier.height(15.dp))

                Text(
                    text = "Almost There!",
                    fontSize = Lx.FontSize.largeTitle,
                    fontWeight = FontWeight.Bold,
                    color = BrandBlack
                )

                Spacer(modifier = Modifier.height(10.dp))

                Text(
                    text = "Please review and accept our terms to continue",
                    fontSize = Lx.FontSize.footnote,
                    color = TextGrey,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(horizontal = 40.dp)
                )
            }

            Spacer(modifier = Modifier.weight(0.5f))

            // Acceptance Cards
            Column(
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                AcceptanceCard(
                    title = "Terms of Service",
                    description = "Rules for using Dollor.ai platform",
                    isAccepted = acceptedTerms,
                    onToggle = { acceptedTerms = !acceptedTerms },
                    onReadMore = { showTermsSheet = true }
                )

                AcceptanceCard(
                    title = "Privacy Policy",
                    description = "How we handle your data",
                    isAccepted = acceptedPrivacy,
                    onToggle = { acceptedPrivacy = !acceptedPrivacy },
                    onReadMore = { showPrivacySheet = true }
                )
            }

            Spacer(modifier = Modifier.weight(0.5f))

            // Continue Button
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier.padding(bottom = 40.dp)
            ) {
                Button(
                    onClick = onAccept,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(52.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = if (canContinue) BrandOrange else Lx.TextSecondary,
                        disabledContainerColor = Lx.TextSecondary
                    ),
                    shape = RoundedCornerShape(Lx.Radius.button),
                    enabled = canContinue
                ) {
                    Text(
                        text = "Continue",
                        fontSize = Lx.FontSize.callout,
                        fontWeight = FontWeight.Bold
                    )
                }

                Spacer(modifier = Modifier.height(12.dp))

                Text(
                    text = "By continuing, you agree to our terms and privacy policy",
                    fontSize = Lx.FontSize.caption,
                    color = TextGrey,
                    textAlign = TextAlign.Center
                )
            }
        }
    }

    // Terms Sheet
    if (showTermsSheet) {
        LegalDocumentSheet(
            title = "Terms of Service",
            content = termsContent,
            onDismiss = { showTermsSheet = false },
            onAccept = {
                acceptedTerms = true
                showTermsSheet = false
            }
        )
    }

    // Privacy Sheet
    if (showPrivacySheet) {
        LegalDocumentSheet(
            title = "Privacy Policy",
            content = privacyContent,
            onDismiss = { showPrivacySheet = false },
            onAccept = {
                acceptedPrivacy = true
                showPrivacySheet = false
            }
        )
    }
}

@Composable
private fun AcceptanceCard(
    title: String,
    description: String,
    isAccepted: Boolean,
    onToggle: () -> Unit,
    onReadMore: () -> Unit
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .shadow(
                elevation = 2.dp,
                shape = RoundedCornerShape(Lx.Radius.button),
                ambientColor = Color.Black.copy(alpha = 0.05f)
            ),
        shape = RoundedCornerShape(Lx.Radius.button),
        colors = CardDefaults.cardColors(containerColor = Lx.Surface)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Checkbox
            IconButton(
                onClick = onToggle,
                modifier = Modifier.size(32.dp)
            ) {
                Icon(
                    imageVector = if (isAccepted) Icons.Default.CheckBox else Icons.Default.CheckBoxOutlineBlank,
                    contentDescription = if (isAccepted) "Accepted" else "Not accepted",
                    tint = if (isAccepted) BrandOrange else TextGrey,
                    modifier = Modifier.size(28.dp)
                )
            }

            Spacer(modifier = Modifier.width(12.dp))

            // Content
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = title,
                    fontSize = Lx.FontSize.callout,
                    fontWeight = FontWeight.SemiBold,
                    color = BrandBlack
                )
                Text(
                    text = description,
                    fontSize = Lx.FontSize.caption,
                    color = TextGrey
                )
            }

            // Read More Button
            Surface(
                modifier = Modifier.clickable { onReadMore() },
                shape = RoundedCornerShape(Lx.Radius.chip),
                color = BrandOrange.copy(alpha = 0.1f)
            ) {
                Text(
                    text = "Read",
                    fontSize = Lx.FontSize.caption,
                    fontWeight = FontWeight.SemiBold,
                    color = BrandOrange,
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp)
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun LegalDocumentSheet(
    title: String,
    content: String,
    onDismiss: () -> Unit,
    onAccept: () -> Unit
) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = Lx.Surface
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp)
                .padding(bottom = 32.dp)
        ) {
            // Header
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(onClick = onDismiss) {
                    Icon(
                        imageVector = Icons.Default.Close,
                        contentDescription = "Close",
                        tint = TextGrey
                    )
                }

                Text(
                    text = title,
                    fontSize = Lx.FontSize.body,
                    fontWeight = FontWeight.Bold,
                    color = BrandBlack
                )

                TextButton(onClick = onAccept) {
                    Text(
                        text = "Accept",
                        fontWeight = FontWeight.Bold,
                        color = BrandOrange
                    )
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Content
            Column(
                modifier = Modifier
                    .weight(1f)
                    .verticalScroll(rememberScrollState())
            ) {
                Text(
                    text = content,
                    fontSize = Lx.FontSize.footnote,
                    color = BrandBlack,
                    lineHeight = 22.sp
                )
            }
        }
    }
}

// Terms Content - US Compliant
private val termsContent = """
TERMS OF SERVICE

Effective Date: January 1, 2025
Last Updated: December 2024

PLEASE READ THESE TERMS CAREFULLY BEFORE USING DOLLOR.AI

1. ACCEPTANCE OF TERMS
By downloading, accessing, or using the Dollor.ai mobile application ("App") or website ("Platform"), you agree to be bound by these Terms of Service ("Terms"). If you do not agree to these Terms, do not use our services.

2. ELIGIBILITY
You must be at least 18 years of age to use Dollor.ai. By using our services, you represent and warrant that you are at least 18 years old and have the legal capacity to enter into this agreement.

3. PLATFORM DESCRIPTION
Dollor.ai operates as a technology platform that facilitates connections between:
• Customers seeking rideshare transportation
• Independent rideshare drivers

Dollor.ai is NOT a transportation company or taxi service. We provide technology that enables connections between riders and drivers.

4. TRANSPARENT PRICING MODEL
Dollor.ai charges transparent, flat platform fees:

RIDESHARE:
• Tier 1 (fares up to ${'$'}35): ${'$'}1.00 platform fee
• Tier 2 (fares ${'$'}35.01-${'$'}70): ${'$'}2.00 platform fee
• Tier 3 (fares over ${'$'}70): ${'$'}3.00 platform fee

100% of customer tips go directly to drivers. We do not take any percentage of tips.

5. INDEPENDENT CONTRACTOR RELATIONSHIP
All drivers using Dollor.ai are independent contractors, NOT employees of Dollor.ai. The Platform does not:
• Control when, where, or how long drivers work
• Provide vehicles or equipment
• Set driver schedules or routes
• Supervise driver activities

6. USER ACCOUNTS AND RESPONSIBILITIES
You agree to:
• Provide accurate, current, and complete information
• Maintain the confidentiality of your account credentials
• Accept responsibility for all activities under your account
• Notify us immediately of any unauthorized use
• Comply with all applicable laws and regulations

7. PAYMENT TERMS
• All payments are processed securely via Stripe
• You authorize charges to your selected payment method
• Prices include applicable taxes unless stated otherwise
• Refunds are processed per our Refund Policy (see Section 11)

8. PROHIBITED CONDUCT
You agree NOT to:
• Use the Platform for any unlawful purpose
• Harass, threaten, or discriminate against any user
• Provide false or misleading information
• Interfere with Platform operations
• Attempt to gain unauthorized access
• Use automated systems without permission

9. INTELLECTUAL PROPERTY
All content, trademarks, and intellectual property on the Platform are owned by Dollor.ai or its licensors. You may not copy, modify, or distribute any content without written permission.

10. LIMITATION OF LIABILITY
TO THE MAXIMUM EXTENT PERMITTED BY LAW:
• Dollor.ai provides the Platform "AS IS" without warranties
• We are not liable for actions of independent contractors
• We are not responsible for delays caused by traffic or road conditions
• Our total liability shall not exceed the amount paid for the specific transaction

11. REFUND POLICY
• Rides may be cancelled before a driver is matched
• Refund requests for disputed charges are reviewed case-by-case
• Approved refunds are processed within 3-5 business days
• Contact support@dollor.ai for refund requests

12. DISPUTE RESOLUTION
Any disputes arising from these Terms shall be resolved through binding arbitration in accordance with the American Arbitration Association rules, except where prohibited by law. Class action waiver applies to the extent permitted by law.

13. PRIVACY
Your use of the Platform is subject to our Privacy Policy, which is incorporated herein by reference.

14. MODIFICATIONS
We reserve the right to modify these Terms at any time. Material changes will be communicated via email or in-app notification. Continued use after changes constitutes acceptance.

15. TERMINATION
We may suspend or terminate your account for violation of these Terms. Upon termination, your right to use the Platform ceases immediately.

16. GOVERNING LAW
These Terms are governed by the laws of the State of California, United States, without regard to conflict of law principles.

17. SEVERABILITY
If any provision is found unenforceable, the remaining provisions shall continue in full force.

18. CONTACT INFORMATION
Dollor.ai, Inc.
San Francisco, CA, United States
Email: support@dollor.ai
Website: https://dollor.ai

BY USING DOLLOR.AI, YOU ACKNOWLEDGE THAT YOU HAVE READ, UNDERSTOOD, AND AGREE TO BE BOUND BY THESE TERMS.
""".trimIndent()

// Privacy Content - US Compliant (CCPA, State Laws)
private val privacyContent = """
PRIVACY POLICY

Effective Date: January 1, 2025
Last Updated: December 2024

This Privacy Policy describes how Dollor.ai, Inc. ("Dollor.ai," "we," "us," or "our") collects, uses, and shares your personal information when you use our mobile application and services.

1. INFORMATION WE COLLECT

Information You Provide:
• Account Information: Name, email address, phone number, profile photo
• Payment Information: Credit/debit card details (processed securely via Stripe)
• Trip Information: Pickup and destination addresses, ride instructions, location data
• Communications: Messages with support, feedback, and reviews

Information Collected Automatically:
• Device Information: Device type, operating system, unique device identifiers
• Usage Data: App interactions, features used, time spent
• Location Data: GPS location when using rideshare features
• Log Data: IP address, browser type, access times

2. HOW WE USE YOUR INFORMATION

We use your information to:
• Process and fulfill ride requests
• Connect you with drivers
• Process payments securely
• Send ride updates and notifications
• Provide customer support
• Improve and personalize our services
• Detect and prevent fraud
• Comply with legal obligations

3. INFORMATION SHARING

We share information with:
• Service Providers: Drivers (trip details), payment processors (Stripe)
• Business Partners: Analytics providers (in anonymized form)
• Legal Requirements: When required by law, court order, or government request
• Safety: To protect rights, safety, and property of users and the public

WE DO NOT SELL YOUR PERSONAL INFORMATION.

4. DATA SECURITY

We implement industry-standard security measures:
• TLS/SSL encryption for all data transmission
• PCI-DSS compliant payment processing via Stripe
• Regular security audits and penetration testing
• Access controls and authentication requirements
• Secure data storage with encryption at rest

5. YOUR PRIVACY RIGHTS

California Residents (CCPA Rights):
• Right to Know: Request what personal information we collect
• Right to Delete: Request deletion of your personal information
• Right to Opt-Out: Opt out of sale of personal information (we don't sell data)
• Right to Non-Discrimination: Equal service regardless of privacy choices

All Users Have Rights To:
• Access your personal information
• Correct inaccurate information
• Delete your account and data
• Opt out of marketing communications
• Data portability (receive your data in portable format)

To exercise these rights, email privacy@dollor.ai or use Settings > Delete Account.

6. DATA RETENTION

We retain your information:
• While your account is active
• As needed to provide services
• As required by law (typically 7 years for financial records)
• Until you request deletion

7. CHILDREN'S PRIVACY

Dollor.ai is not intended for users under 18 years of age. We do not knowingly collect information from children under 18. If we learn we have collected such information, we will delete it promptly.

8. COOKIES AND TRACKING

We use cookies and similar technologies to:
• Remember your preferences
• Analyze app usage
• Improve performance

You can control cookies through your device settings.

9. THIRD-PARTY LINKS

Our app may contain links to third-party websites or services. We are not responsible for their privacy practices.

10. INTERNATIONAL DATA TRANSFERS

Your information may be transferred to and processed in the United States. By using our services, you consent to this transfer.

11. CHANGES TO THIS POLICY

We may update this Privacy Policy periodically. Material changes will be communicated via email or in-app notification. Continued use after changes constitutes acceptance.

12. CONTACT US

For privacy questions or to exercise your rights:

Dollor.ai, Inc.
San Francisco, CA, United States
Email: privacy@dollor.ai
Website: https://dollor.ai

For California residents, you may also contact the California Attorney General at oag.ca.gov.

BY USING DOLLOR.AI, YOU ACKNOWLEDGE THAT YOU HAVE READ AND UNDERSTOOD THIS PRIVACY POLICY.
""".trimIndent()

@Preview(showBackground = true)
@Composable
fun LegalAcceptanceScreenPreview() {
    LegalAcceptanceScreen(onAccept = {})
}
