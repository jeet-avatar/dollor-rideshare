package com.eatfair.app.ui.profile

import com.eatfair.shared.config.AppConfig
import com.eatfair.shared.ui.Lx
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.DeleteForever
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.PrivacyTip
import androidx.compose.material.icons.filled.Security
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.eatfair.app.ui.common.EFTopAppBar
import com.eatfair.app.ui.theme.primaryVerticalGradient

/**
 * Settings Screen for Customer App
 * Required for Google Play Store compliance - includes account deletion
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    onBackClick: () -> Unit,
    onPrivacyPolicyClick: () -> Unit,
    onTermsClick: () -> Unit,
    onCaliforniaPrivacyClick: () -> Unit = {},
    onEmailVerificationClick: () -> Unit = {},
    isEmailVerified: Boolean = false,
    onDeleteAccount: (onSuccess: () -> Unit, onError: (String) -> Unit) -> Unit,
    onAccountDeleted: () -> Unit
) {
    val context = LocalContext.current
    var showDeleteDialog by remember { mutableStateOf(false) }
    var isDeleting by remember { mutableStateOf(false) }
    var deleteError by remember { mutableStateOf<String?>(null) }

    // Delete Account Confirmation Dialog
    if (showDeleteDialog) {
        DeleteAccountDialog(
            isDeleting = isDeleting,
            error = deleteError,
            onDismiss = {
                showDeleteDialog = false
                deleteError = null
            },
            onConfirm = {
                isDeleting = true
                deleteError = null
                onDeleteAccount(
                    {
                        isDeleting = false
                        showDeleteDialog = false
                        onAccountDeleted()
                    },
                    { error ->
                        isDeleting = false
                        deleteError = error
                    }
                )
            }
        )
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(primaryVerticalGradient())
    ) {
        EFTopAppBar("Settings", true, onBackClick)

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
        ) {
            Spacer(modifier = Modifier.height(20.dp))

            Text(
                text = "Manage your preferences and account settings",
                style = MaterialTheme.typography.bodyMedium,
                color = Lx.TextSecondary
            )

            Spacer(modifier = Modifier.height(24.dp))

            // NOTE: "Language" selector and "Push Notifications" toggle were removed —
            // neither was backed by any persistence/endpoint, so they were dead controls.
            // Re-add once a language setting and a notification-preference endpoint exist.

            // Account Security Section
            Text(
                text = "Account Security",
                fontSize = Lx.FontSize.callout,
                fontWeight = FontWeight.SemiBold,
                color = Lx.Text
            )

            Spacer(modifier = Modifier.height(12.dp))

            // Email Verification
            SettingsMenuItem(
                icon = Icons.Default.Email,
                title = "Email Verification",
                subtitle = if (isEmailVerified) "Verified" else "Not verified - Tap to verify",
                onClick = onEmailVerificationClick,
                showBadge = !isEmailVerified
            )

            Spacer(modifier = Modifier.height(24.dp))

            // Legal Section
            Text(
                text = "Legal",
                fontSize = Lx.FontSize.callout,
                fontWeight = FontWeight.SemiBold,
                color = Lx.Text
            )

            Spacer(modifier = Modifier.height(12.dp))

            // Privacy Policy
            SettingsMenuItem(
                icon = Icons.Default.Security,
                title = "Privacy Policy",
                onClick = onPrivacyPolicyClick
            )

            // Terms & Conditions
            SettingsMenuItem(
                icon = Icons.Default.Description,
                title = "Terms & Conditions",
                onClick = onTermsClick
            )

            // California Privacy Rights (CCPA/CPRA)
            SettingsMenuItem(
                icon = Icons.Default.PrivacyTip,
                title = "California Privacy Rights",
                subtitle = "CCPA/CPRA Consumer Rights",
                onClick = onCaliforniaPrivacyClick
            )

            Spacer(modifier = Modifier.height(24.dp))

            // Support Section
            Text(
                text = "Support",
                fontSize = Lx.FontSize.callout,
                fontWeight = FontWeight.SemiBold,
                color = Lx.Text
            )

            Spacer(modifier = Modifier.height(12.dp))

            // Contact Support - opens the device email client to the configured support address
            SettingsMenuItem(
                icon = Icons.Default.Email,
                title = "Contact Support",
                subtitle = AppConfig.Rideshare.support.email,
                onClick = {
                    val emailIntent = android.content.Intent(
                        android.content.Intent.ACTION_SENDTO,
                        android.net.Uri.parse("mailto:${AppConfig.Rideshare.support.email}")
                    ).apply {
                        putExtra(android.content.Intent.EXTRA_SUBJECT, "Dollor.ai Support Request")
                    }
                    try {
                        context.startActivity(emailIntent)
                    } catch (e: android.content.ActivityNotFoundException) {
                        android.widget.Toast.makeText(
                            context,
                            "No email app found. Contact ${AppConfig.Rideshare.support.email}",
                            android.widget.Toast.LENGTH_LONG
                        ).show()
                    }
                }
            )

            Spacer(modifier = Modifier.height(32.dp))

            // Delete Account Section - Required by Google Play Store
            Text(
                text = "Account",
                fontSize = Lx.FontSize.callout,
                fontWeight = FontWeight.SemiBold,
                color = Lx.Text
            )

            Spacer(modifier = Modifier.height(12.dp))

            DeleteAccountButton(onClick = { showDeleteDialog = true })

            Spacer(modifier = Modifier.height(100.dp))
        }
    }
}

@Composable
fun SettingsMenuItem(
    icon: ImageVector,
    title: String,
    subtitle: String? = null,
    onClick: () -> Unit,
    showBadge: Boolean = false
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp)
            .clip(RoundedCornerShape(Lx.Radius.button))
            .clickable(onClick = onClick),
        colors = CardDefaults.cardColors(containerColor = Lx.Surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box {
                    Icon(
                        imageVector = icon,
                        contentDescription = title,
                        modifier = Modifier.size(24.dp),
                        tint = Lx.TextSecondary
                    )
                    if (showBadge) {
                        Box(
                            modifier = Modifier
                                .size(8.dp)
                                .align(Alignment.TopEnd)
                                .background(Lx.Warning, RoundedCornerShape(4.dp))
                        )
                    }
                }
                Spacer(modifier = Modifier.width(16.dp))
                Column {
                    Text(
                        text = title,
                        fontSize = Lx.FontSize.subheadline,
                        color = Lx.Text
                    )
                    if (subtitle != null) {
                        Text(
                            text = subtitle,
                            fontSize = Lx.FontSize.footnote,
                            color = if (showBadge) Lx.Warning else Lx.TextMuted
                        )
                    }
                }
            }
            Icon(
                imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = "Navigate",
                tint = Lx.TextMuted,
                modifier = Modifier.size(24.dp)
            )
        }
    }
}

/**
 * Delete Account Button - Required by Google Play Store policy
 */
@Composable
fun DeleteAccountButton(onClick: () -> Unit) {
    OutlinedButton(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        colors = ButtonDefaults.outlinedButtonColors(
            contentColor = Lx.Error
        ),
        shape = RoundedCornerShape(Lx.Radius.button)
    ) {
        Icon(
            imageVector = Icons.Default.DeleteForever,
            contentDescription = null,
            tint = Lx.Error
        )
        Spacer(modifier = Modifier.width(8.dp))
        Text(
            text = "Delete Account",
            fontWeight = FontWeight.Medium
        )
    }
}

/**
 * Delete Account Confirmation Dialog
 * Shows warning about permanent deletion and requires confirmation
 */
@Composable
fun DeleteAccountDialog(
    isDeleting: Boolean,
    error: String?,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit
) {
    AlertDialog(
        onDismissRequest = { if (!isDeleting) onDismiss() },
        icon = {
            Icon(
                imageVector = Icons.Default.Warning,
                contentDescription = null,
                tint = Lx.Error
            )
        },
        title = {
            Text(
                text = "Delete Account?",
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center
            )
        },
        text = {
            Column {
                Text(
                    text = "This action cannot be undone. Deleting your account will:",
                    style = MaterialTheme.typography.bodyMedium,
                    color = Lx.TextSecondary
                )
                Spacer(modifier = Modifier.height(12.dp))
                Text(
                    text = "- Remove all your personal information\n" +
                            "- Delete your order history\n" +
                            "- Remove saved addresses and payment methods\n" +
                            "- Cancel any active orders",
                    style = MaterialTheme.typography.bodySmall,
                    color = Lx.TextMuted
                )

                if (error != null) {
                    Spacer(modifier = Modifier.height(16.dp))
                    Text(
                        text = error,
                        style = MaterialTheme.typography.bodySmall,
                        color = Lx.Error
                    )
                }
            }
        },
        confirmButton = {
            Button(
                onClick = onConfirm,
                enabled = !isDeleting,
                colors = ButtonDefaults.buttonColors(
                    containerColor = Lx.Error
                )
            ) {
                if (isDeleting) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(20.dp),
                        color = Color.White,
                        strokeWidth = 2.dp
                    )
                } else {
                    Text("Delete My Account")
                }
            }
        },
        dismissButton = {
            TextButton(
                onClick = onDismiss,
                enabled = !isDeleting
            ) {
                Text("Cancel", color = Lx.TextSecondary)
            }
        }
    )
}
