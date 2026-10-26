package com.eatfair.driver.ui.profile

import com.eatfair.shared.ui.Lx
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import android.content.Intent
import android.net.Uri
import android.widget.Toast
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavHostController
import com.eatfair.driver.ui.earnings.EarningsViewModel
import com.eatfair.driver.ui.theme.DollorDriverColors

/**
 * Driver Profile Screen - Aligned with iOS DriverProfileView.swift and Web Profile.tsx
 *
 * Features matched:
 * - Profile header with avatar, name, email, phone
 * - Earnings summary (Today, This Week, Total)
 * - Menu items (Earnings History, Vehicle Info, Documents, Settings, Help)
 * - Logout button
 * - Delete Account with two-step confirmation (Apple App Store Guideline 5.1.1)
 */

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileScreen(
    driverName: String,
    driverEmail: String,
    driverPhone: String,
    onLogout: () -> Unit,
    onDeleteAccount: (onSuccess: () -> Unit, onError: (String) -> Unit) -> Unit,
    navController: NavHostController,
    earningsViewModel: EarningsViewModel = hiltViewModel(),
    accessibilityViewModel: AccessibilityViewModel = hiltViewModel()
) {
    var showLogoutDialog by remember { mutableStateOf(false) }
    var showDeleteAccountDialog by remember { mutableStateOf(false) }
    var showDeleteConfirmDialog by remember { mutableStateOf(false) }
    var isDeleting by remember { mutableStateOf(false) }
    var deleteError by remember { mutableStateOf<String?>(null) }

    val context = LocalContext.current
    val earningsState by earningsViewModel.uiState.collectAsState()
    val earnings = earningsState.earnings

    val displayName = driverName.ifBlank { "Driver" }
    val initial = displayName.first().uppercase()

    fun openSupportEmail() {
        val intent = Intent(Intent.ACTION_SENDTO).apply {
            data = Uri.parse("mailto:support@dollor.ai")
            putExtra(Intent.EXTRA_SUBJECT, "Dollor Driver Support")
        }
        if (intent.resolveActivity(context.packageManager) != null) {
            context.startActivity(intent)
        } else {
            Toast.makeText(context, "support@dollor.ai", Toast.LENGTH_LONG).show()
        }
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(DollorDriverColors.Background),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // Profile Header Card
        item {
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(Lx.Radius.sheet),
                colors = CardDefaults.cardColors(containerColor = Lx.Surface)
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    // Avatar
                    Box(
                        modifier = Modifier
                            .size(100.dp)
                            .clip(CircleShape)
                            .background(
                                brush = Brush.linearGradient(
                                    colors = listOf(
                                        DollorDriverColors.Blue,
                                        DollorDriverColors.BlueDark
                                    )
                                )
                            ),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = initial,
                            style = MaterialTheme.typography.displaySmall.copy(
                                fontWeight = FontWeight.Bold
                            ),
                            color = DollorDriverColors.White
                        )
                    }

                    Spacer(modifier = Modifier.height(16.dp))

                    // Name
                    Text(
                        text = displayName,
                        style = MaterialTheme.typography.headlineSmall.copy(
                            fontWeight = FontWeight.Bold
                        ),
                        color = DollorDriverColors.Gray900
                    )

                    // Email
                    if (driverEmail.isNotBlank()) {
                        Text(
                            text = driverEmail,
                            style = MaterialTheme.typography.bodyMedium,
                            color = DollorDriverColors.Gray500
                        )
                    }

                    // Phone
                    if (driverPhone.isNotBlank()) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(4.dp),
                            modifier = Modifier.padding(top = 4.dp)
                        ) {
                            Icon(
                                imageVector = Icons.Default.Phone,
                                contentDescription = null,
                                tint = DollorDriverColors.Blue,
                                modifier = Modifier.size(16.dp)
                            )
                            Text(
                                text = driverPhone,
                                style = MaterialTheme.typography.bodyMedium,
                                color = DollorDriverColors.Gray600
                            )
                        }
                    }
                }
            }
        }

        // Earnings Summary
        item {
            Text(
                text = "EARNINGS",
                style = MaterialTheme.typography.labelMedium.copy(
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 1.sp
                ),
                color = DollorDriverColors.Gray500
            )
        }

        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                EarningsSummaryCard(
                    modifier = Modifier.weight(1f),
                    label = "Today",
                    value = "$" + String.format("%.2f", earnings?.today?.grossEarnings ?: 0.0),
                    color = DollorDriverColors.Green
                )
                EarningsSummaryCard(
                    modifier = Modifier.weight(1f),
                    label = "This Week",
                    value = "$" + String.format("%.2f", earnings?.thisWeek?.grossEarnings ?: 0.0),
                    color = DollorDriverColors.Blue
                )
                EarningsSummaryCard(
                    modifier = Modifier.weight(1f),
                    label = "This Month",
                    value = "$" + String.format("%.2f", earnings?.thisMonth?.grossEarnings ?: 0.0),
                    color = DollorDriverColors.Orange
                )
            }
        }

        // Menu Section
        item {
            Text(
                text = "ACCOUNT",
                style = MaterialTheme.typography.labelMedium.copy(
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 1.sp
                ),
                color = DollorDriverColors.Gray500,
                modifier = Modifier.padding(top = 8.dp)
            )
        }

        item {
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(Lx.Radius.card),
                colors = CardDefaults.cardColors(containerColor = Lx.Surface)
            ) {
                Column {
                    // Earnings History -> Earnings tab (exists). Vehicle Information
                    // and Documents screens don't exist in the driver app yet, so
                    // those rows are intentionally omitted rather than left dead.
                    ProfileMenuItem(
                        icon = Icons.Outlined.AttachMoney,
                        title = "Earnings History",
                        subtitle = "View detailed earnings",
                        onClick = { navController.navigate("earnings") }
                    )
                    ProfileMenuItem(
                        icon = Icons.Outlined.WorkspacePremium,
                        title = "Founding Member",
                        subtitle = "Lock in your rate for life - $100",
                        onClick = { navController.navigate("founding") }
                    )
                }
            }
        }

        // Support Section
        item {
            Text(
                text = "SUPPORT",
                style = MaterialTheme.typography.labelMedium.copy(
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 1.sp
                ),
                color = DollorDriverColors.Gray500,
                modifier = Modifier.padding(top = 8.dp)
            )
        }

        item {
            AccessibilityCapabilityCard(accessibilityViewModel)
        }

        item {
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(Lx.Radius.card),
                colors = CardDefaults.cardColors(containerColor = Lx.Surface)
            ) {
                Column {
                    // Settings and Notifications screens don't exist yet in the
                    // driver app, so those rows are omitted. Help & Support opens
                    // a support email, a destination that does exist.
                    ProfileMenuItem(
                        icon = Icons.Outlined.Help,
                        title = "Help & Support",
                        subtitle = "Contact support@dollor.ai",
                        onClick = { openSupportEmail() }
                    )
                }
            }
        }

        // Logout Button
        item {
            Button(
                onClick = { showLogoutDialog = true },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(56.dp),
                shape = RoundedCornerShape(Lx.Radius.card),
                colors = ButtonDefaults.buttonColors(
                    containerColor = Lx.Surface2
                )
            ) {
                Icon(
                    imageVector = Icons.Default.Logout,
                    contentDescription = null,
                    modifier = Modifier.size(20.dp)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = "Log Out",
                    style = MaterialTheme.typography.titleMedium.copy(
                        fontWeight = FontWeight.Bold
                    )
                )
            }
        }

        // Delete Account Button (Apple App Store Guideline 5.1.1 / Google Play policy)
        item {
            OutlinedButton(
                onClick = { showDeleteAccountDialog = true },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(56.dp),
                shape = RoundedCornerShape(Lx.Radius.card),
                colors = ButtonDefaults.outlinedButtonColors(
                    contentColor = DollorDriverColors.Error
                ),
                border = ButtonDefaults.outlinedButtonBorder.copy(
                    brush = Brush.linearGradient(
                        colors = listOf(DollorDriverColors.Error, DollorDriverColors.Error)
                    )
                )
            ) {
                Icon(
                    imageVector = Icons.Default.DeleteForever,
                    contentDescription = null,
                    modifier = Modifier.size(20.dp)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = "Delete Account",
                    style = MaterialTheme.typography.titleMedium.copy(
                        fontWeight = FontWeight.Bold
                    )
                )
            }
        }

        // Footer
        item {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 16.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(
                    text = "Dollor Driver App v${com.eatfair.driver.BuildConfig.VERSION_NAME}",
                    style = MaterialTheme.typography.bodySmall,
                    color = DollorDriverColors.Gray400
                )
            }
        }

        item {
            Spacer(modifier = Modifier.height(80.dp))
        }
    }

    // Logout Confirmation Dialog
    if (showLogoutDialog) {
        AlertDialog(
            onDismissRequest = { showLogoutDialog = false },
            title = { Text("Log Out?") },
            text = { Text("Are you sure you want to log out of your account?") },
            confirmButton = {
                TextButton(
                    onClick = {
                        showLogoutDialog = false
                        onLogout()
                    }
                ) {
                    Text("Log Out", color = DollorDriverColors.Error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showLogoutDialog = false }) {
                    Text("Cancel")
                }
            }
        )
    }

    // Delete Account First Dialog
    if (showDeleteAccountDialog) {
        AlertDialog(
            onDismissRequest = { showDeleteAccountDialog = false },
            icon = {
                Icon(
                    imageVector = Icons.Default.Warning,
                    contentDescription = null,
                    tint = DollorDriverColors.Error,
                    modifier = Modifier.size(48.dp)
                )
            },
            title = {
                Text(
                    "Delete Account?",
                    textAlign = TextAlign.Center
                )
            },
            text = {
                Text(
                    "This will permanently delete your account, including all your earnings history, documents, and personal data. This action cannot be undone.",
                    textAlign = TextAlign.Center
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        showDeleteAccountDialog = false
                        showDeleteConfirmDialog = true
                    }
                ) {
                    Text("Continue", color = DollorDriverColors.Error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteAccountDialog = false }) {
                    Text("Cancel")
                }
            }
        )
    }

    // Delete Account Final Confirmation Dialog
    if (showDeleteConfirmDialog) {
        AlertDialog(
            onDismissRequest = {
                if (!isDeleting) showDeleteConfirmDialog = false
            },
            icon = {
                Icon(
                    imageVector = Icons.Default.DeleteForever,
                    contentDescription = null,
                    tint = DollorDriverColors.Error,
                    modifier = Modifier.size(48.dp)
                )
            },
            title = {
                Text(
                    "Final Confirmation",
                    textAlign = TextAlign.Center,
                    color = DollorDriverColors.Error
                )
            },
            text = {
                Column {
                    Text(
                        "Are you absolutely sure? Your account and all associated data will be permanently deleted.",
                        textAlign = TextAlign.Center
                    )
                    deleteError?.let { error ->
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(
                            text = error,
                            color = DollorDriverColors.Error,
                            style = MaterialTheme.typography.bodySmall,
                            textAlign = TextAlign.Center
                        )
                    }
                }
            },
            confirmButton = {
                Button(
                    onClick = {
                        isDeleting = true
                        deleteError = null
                        onDeleteAccount(
                            {
                                // onSuccess - ViewModel resets state to Idle which triggers login screen
                                isDeleting = false
                                showDeleteConfirmDialog = false
                            },
                            { error ->
                                isDeleting = false
                                deleteError = error
                            }
                        )
                    },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = DollorDriverColors.Error
                    ),
                    enabled = !isDeleting
                ) {
                    if (isDeleting) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(20.dp),
                            color = DollorDriverColors.White,
                            strokeWidth = 2.dp
                        )
                    } else {
                        Text("Delete Forever")
                    }
                }
            },
            dismissButton = {
                TextButton(
                    onClick = { showDeleteConfirmDialog = false },
                    enabled = !isDeleting
                ) {
                    Text("Cancel")
                }
            }
        )
    }
}

@Composable
private fun EarningsSummaryCard(
    modifier: Modifier = Modifier,
    label: String,
    value: String,
    color: androidx.compose.ui.graphics.Color
) {
    Card(
        modifier = modifier,
        shape = RoundedCornerShape(Lx.Radius.card),
        colors = CardDefaults.cardColors(containerColor = Lx.Surface)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = value,
                style = MaterialTheme.typography.titleMedium.copy(
                    fontWeight = FontWeight.Bold
                ),
                color = color
            )
            Text(
                text = label,
                style = MaterialTheme.typography.bodySmall,
                color = DollorDriverColors.Gray500
            )
        }
    }
}

@Composable
private fun ProfileMenuItem(
    icon: ImageVector,
    title: String,
    subtitle: String,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onClick() }
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(40.dp)
                .clip(RoundedCornerShape(Lx.Radius.chip))
                .background(DollorDriverColors.Blue.copy(alpha = 0.1f)),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = DollorDriverColors.Blue,
                modifier = Modifier.size(20.dp)
            )
        }
        Spacer(modifier = Modifier.width(16.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = title,
                style = MaterialTheme.typography.bodyLarge.copy(
                    fontWeight = FontWeight.Medium
                ),
                color = DollorDriverColors.Gray900
            )
            Text(
                text = subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = DollorDriverColors.Gray500
            )
        }
        Icon(
            imageVector = Icons.Default.ChevronRight,
            contentDescription = null,
            tint = DollorDriverColors.Gray300
        )
    }
}

@Composable
private fun AccessibilityCapabilityCard(viewModel: AccessibilityViewModel) {
    val state by viewModel.state.collectAsState()
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(Lx.Radius.card),
        colors = CardDefaults.cardColors(containerColor = Lx.Surface)
    ) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Default.Accessible, contentDescription = null, tint = Lx.Orange)
                Text(
                    "Accessibility Capability",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = Lx.Text
                )
            }
            AccessibilitySwitchRow("My vehicle is wheelchair accessible", state.capable, viewModel::setCapable)
            if (state.capable) {
                AccessibilitySwitchRow("Wheelchair ramp/lift", state.wheelchair, viewModel::setWheelchair)
                AccessibilitySwitchRow("Service animal friendly", state.serviceAnimal, viewModel::setServiceAnimal)
                AccessibilitySwitchRow("Extra trunk space for mobility aids", state.mobilityStorage, viewModel::setMobilityStorage)
            }
            if (state.isSaving) {
                Text("Saving...", style = MaterialTheme.typography.bodySmall, color = Lx.TextSecondary)
            }
            state.error?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = Lx.Error)
            }
        }
    }
}

@Composable
private fun AccessibilitySwitchRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(label, style = MaterialTheme.typography.bodyMedium, color = Lx.Text, modifier = Modifier.weight(1f))
        Switch(
            checked = checked,
            onCheckedChange = onChange,
            colors = SwitchDefaults.colors(checkedThumbColor = Lx.Text, checkedTrackColor = Lx.Orange)
        )
    }
}
