package com.eatfair.app.ui.profile

import com.eatfair.shared.ui.LxButtonRole
import com.eatfair.shared.ui.LxButton
import com.eatfair.shared.config.AppConfig
import com.eatfair.shared.ui.Lx
import android.Manifest
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Help
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.CardGiftcard
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Security
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import coil.compose.AsyncImage
import com.eatfair.app.R
import com.eatfair.app.ui.common.EFTopAppBar
import com.eatfair.app.ui.theme.DollorTheme
import com.google.accompanist.permissions.ExperimentalPermissionsApi
import com.google.accompanist.permissions.isGranted
import com.google.accompanist.permissions.rememberPermissionState
import java.io.File

/**
 * ProfileScreen - Matches iOS ProfileView exactly
 * Features:
 * - Gray background (Theme.brandGrey)
 * - Grouped sections: ACCOUNT, APP SETTINGS, PRIVACY & SAFETY
 * - Orange icons like iOS
 * - Separate Log Out button (black)
 * - Delete Account button (red)
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalPermissionsApi::class)
@Composable
fun ProfileScreen(
    profileViewModel: ProfileViewModel,
    onBackClick: () -> Unit = {},
    onSavedAddressClick: () -> Unit = {},
    onEditProfileClick: () -> Unit = {},
    onPaymentMethodClick: () -> Unit = {},
    onOrderHistoryClick: () -> Unit = {},
    onNotificationsClick: () -> Unit = {},
    onReferAndEarnClick: () -> Unit = {},
    onSettingsClick: () -> Unit = {},
    onHelpSupportClick: () -> Unit = {},
    onWhatDriversSeeClick: () -> Unit = {},
    onYourPrivacyClick: () -> Unit = {},
    onSafetyFeaturesClick: () -> Unit = {},
    onDeleteAccountClick: (onError: (String) -> Unit) -> Unit = {},
    onLogoutClick: () -> Unit = {}
) {
    val profileImageUri by profileViewModel.profileImageUri.collectAsState()
    val userName by profileViewModel.userNameFlow.collectAsState(initial = "")
    val userEmail by profileViewModel.userEmailFlow.collectAsState(initial = "")

    // Delete account dialog states
    var showDeleteAccountDialog by remember { mutableStateOf(false) }
    var showDeleteConfirmation by remember { mutableStateOf(false) }
    var isDeletingAccount by remember { mutableStateOf(false) }
    var deleteAccountError by remember { mutableStateOf<String?>(null) }

    var tempCameraUri by remember { mutableStateOf<Uri?>(null) }
    val context = LocalContext.current

    // Launcher for picking from gallery
    val photoPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.PickVisualMedia(),
        onResult = { uri -> profileViewModel.onProfileImageChange(uri) }
    )

    // Launcher for taking a picture
    val cameraLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.TakePicture(),
        onResult = { success ->
            if (success) {
                profileViewModel.onProfileImageChange(tempCameraUri)
            }
        }
    )

    // Permission state for Camera
    val cameraPermissionState = rememberPermissionState(Manifest.permission.CAMERA)

    fun getTempUri(): Uri {
        val file = File.createTempFile("profile_image_", ".jpg", context.cacheDir)
        return FileProvider.getUriForFile(context, "${context.packageName}.provider", file)
    }

    var showImageSourceDialog by remember { mutableStateOf(false) }

    // Image source dialog
    if (showImageSourceDialog) {
        AlertDialog(
            onDismissRequest = { showImageSourceDialog = false },
            title = { Text("Change Profile Photo") },
            text = { Text("Choose a source for your new profile picture.") },
            confirmButton = {
                TextButton(onClick = {
                    if (cameraPermissionState.status.isGranted) {
                        tempCameraUri = getTempUri()
                        tempCameraUri?.let { uri -> cameraLauncher.launch(uri) }
                    } else {
                        cameraPermissionState.launchPermissionRequest()
                    }
                    showImageSourceDialog = false
                }) {
                    Text("Camera")
                }
            },
            dismissButton = {
                TextButton(onClick = {
                    photoPickerLauncher.launch(
                        PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)
                    )
                    showImageSourceDialog = false
                }) {
                    Text("Gallery")
                }
            }
        )
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(DollorTheme.Background.primary)  // iOS: Theme.brandGrey
    ) {
        EFTopAppBar("Profile", true, onBackClick)

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
        ) {
            Spacer(modifier = Modifier.height(30.dp))

            // Profile Header - Matches iOS exactly
            ProfileHeader(
                userName = userName ?: "",
                userEmail = userEmail ?: "",
                profileImageUri = profileImageUri,
                onEditClick = { showImageSourceDialog = true }
            )

            Spacer(modifier = Modifier.height(25.dp))

            // ACCOUNT Section - Matches iOS
            SectionHeader("ACCOUNT")
            ProfileMenuCard {
                ProfileMenuRow(
                    icon = Icons.Default.Person,
                    title = "Edit Profile",
                    onClick = onEditProfileClick
                )
                MenuDivider()
                ProfileMenuRow(
                    icon = Icons.Default.LocationOn,
                    title = "Manage Addresses",
                    onClick = onSavedAddressClick
                )
                MenuDivider()
                ProfileMenuRow(
                    icon = Icons.Default.CreditCard,
                    title = "Payment Methods",
                    onClick = onPaymentMethodClick
                )
            }

            Spacer(modifier = Modifier.height(25.dp))

            // APP SETTINGS Section - Matches iOS
            SectionHeader("APP SETTINGS")
            ProfileMenuCard {
                ProfileMenuRow(
                    icon = Icons.Default.Settings,
                    title = "Settings",
                    onClick = onSettingsClick
                )
                MenuDivider()
                ProfileMenuRow(
                    icon = Icons.Default.Notifications,
                    title = "Notifications",
                    onClick = onNotificationsClick
                )
                MenuDivider()
                // Shown only once the backend configures a referral reward (REFERRAL_REWARD_TEXT)
                if (AppConfig.Rideshare.referralRewardText != null) {
                    ProfileMenuRow(
                        icon = Icons.Default.CardGiftcard,
                        title = "Refer & Earn",
                        onClick = onReferAndEarnClick
                    )
                    MenuDivider()
                }
                ProfileMenuRow(
                    icon = Icons.AutoMirrored.Filled.Help,
                    title = "Help & Support",
                    onClick = onHelpSupportClick
                )
            }

            Spacer(modifier = Modifier.height(25.dp))

            // PRIVACY & SAFETY Section - Matches iOS
            SectionHeader("PRIVACY & SAFETY")
            ProfileMenuCard {
                ProfileMenuRow(
                    icon = Icons.Default.Visibility,
                    title = "What Drivers See",
                    onClick = onWhatDriversSeeClick
                )
                MenuDivider()
                ProfileMenuRow(
                    icon = Icons.Default.Lock,
                    title = "Your Privacy",
                    onClick = onYourPrivacyClick
                )
                MenuDivider()
                ProfileMenuRow(
                    icon = Icons.Default.Security,
                    title = "Safety Features",
                    onClick = onSafetyFeaturesClick
                )
            }

            Spacer(modifier = Modifier.height(25.dp))

            LxButton(
                text = "Log Out",
                onClick = onLogoutClick,
                role = LxButtonRole.Secondary
            )

            Spacer(modifier = Modifier.height(16.dp))

            // Delete Account Button - Matches iOS (red text, light red background)
            Button(
                onClick = { showDeleteAccountDialog = true },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(50.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = Lx.Error.copy(alpha = 0.1f)
                ),
                shape = RoundedCornerShape(Lx.Radius.button),
                enabled = !isDeletingAccount
            ) {
                if (isDeletingAccount) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(20.dp),
                        color = Lx.Error,
                        strokeWidth = 2.dp
                    )
                } else {
                    Text(
                        text = "Delete Account",
                        fontSize = Lx.FontSize.callout,
                        fontWeight = FontWeight.SemiBold,
                        color = Lx.Error
                    )
                }
            }

            Spacer(modifier = Modifier.height(30.dp))

            // Delete Account Dialogs
            if (showDeleteAccountDialog) {
                AlertDialog(
                    onDismissRequest = { showDeleteAccountDialog = false },
                    title = {
                        Text(
                            text = "Delete Account?",
                            fontWeight = FontWeight.Bold,
                            color = Lx.Error
                        )
                    },
                    text = {
                        Text("This will permanently delete your account, including all your order history, saved addresses, and payment methods. This action cannot be undone.")
                    },
                    confirmButton = {
                        TextButton(onClick = {
                            showDeleteAccountDialog = false
                            showDeleteConfirmation = true
                        }) {
                            Text("Continue", color = Lx.Error)
                        }
                    },
                    dismissButton = {
                        TextButton(onClick = { showDeleteAccountDialog = false }) {
                            Text("Cancel")
                        }
                    }
                )
            }

            if (showDeleteConfirmation) {
                AlertDialog(
                    onDismissRequest = { showDeleteConfirmation = false },
                    title = {
                        Text(
                            text = "Final Confirmation",
                            fontWeight = FontWeight.Bold,
                            color = Lx.Error
                        )
                    },
                    text = {
                        Text("Are you absolutely sure? Your account and all associated data will be permanently deleted.")
                    },
                    confirmButton = {
                        Button(
                            onClick = {
                                showDeleteConfirmation = false
                                isDeletingAccount = true
                                onDeleteAccountClick { error ->
                                    isDeletingAccount = false
                                    deleteAccountError = error
                                }
                            },
                            colors = ButtonDefaults.buttonColors(containerColor = Lx.Error)
                        ) {
                            Text("Delete Forever", color = Color.White)
                        }
                    },
                    dismissButton = {
                        TextButton(onClick = { showDeleteConfirmation = false }) {
                            Text("Cancel")
                        }
                    }
                )
            }

            deleteAccountError?.let { error ->
                AlertDialog(
                    onDismissRequest = { deleteAccountError = null },
                    title = { Text("Couldn't Delete Account", fontWeight = FontWeight.Bold) },
                    text = { Text(error) },
                    confirmButton = {
                        TextButton(onClick = { deleteAccountError = null }) {
                            Text("OK")
                        }
                    }
                )
            }

            Spacer(modifier = Modifier.height(80.dp))
        }
    }
}

/**
 * Profile Header - Matches iOS ProfileView header
 */
@Composable
fun ProfileHeader(
    userName: String,
    userEmail: String,
    profileImageUri: Uri?,
    onEditClick: () -> Unit
) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        // Profile Image with Edit Badge - Matches iOS
        Box(contentAlignment = Alignment.BottomEnd) {
            // Green circle with initial/image - 100x100 like iOS
            Box(
                modifier = Modifier
                    .size(100.dp)
                    .shadow(elevation = 5.dp, shape = CircleShape)
                    .clip(CircleShape)
                    .background(DollorTheme.Brand.green),
                contentAlignment = Alignment.Center
            ) {
                if (profileImageUri != null) {
                    AsyncImage(
                        model = profileImageUri,
                        contentDescription = "Profile Image",
                        modifier = Modifier.fillMaxSize(),
                        contentScale = ContentScale.Crop,
                        error = painterResource(id = R.drawable.ic_person_placeholder),
                        placeholder = painterResource(id = R.drawable.ic_person_placeholder)
                    )
                } else {
                    // Show first initial like iOS
                    Text(
                        text = userName.take(1).uppercase(),
                        fontSize = 40.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    )
                }
            }

            // Edit Badge - Orange pencil on white circle like iOS
            Box(
                modifier = Modifier
                    .size(32.dp)
                    .clip(CircleShape)
                    .background(Lx.Surface)
                    .clickable(onClick = onEditClick),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Default.Edit,
                    contentDescription = "Edit Profile",
                    modifier = Modifier.size(20.dp),
                    tint = DollorTheme.Brand.orange
                )
            }
        }

        Spacer(modifier = Modifier.height(15.dp))

        // User Name - title2, bold like iOS
        Text(
            text = userName,
            fontSize = Lx.FontSize.title,
            fontWeight = FontWeight.Bold,
            color = Lx.Text
        )

        Spacer(modifier = Modifier.height(5.dp))

        // User Email - subheadline, gray like iOS
        Text(
            text = userEmail,
            fontSize = Lx.FontSize.subheadline,
            color = Lx.TextSecondary
        )
    }
}

/**
 * Section Header - Matches iOS section headers
 */
@Composable
fun SectionHeader(title: String) {
    Text(
        text = title,
        fontSize = Lx.FontSize.caption,
        fontWeight = FontWeight.Bold,
        color = Lx.TextSecondary,
        modifier = Modifier.padding(start = 4.dp, bottom = 10.dp)
    )
}

/**
 * Profile Menu Card - White card with shadow like iOS
 */
@Composable
fun ProfileMenuCard(content: @Composable () -> Unit) {
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
        Column {
            content()
        }
    }
}

/**
 * Profile Menu Row - Matches iOS ProfileOptionRow
 */
@Composable
fun ProfileMenuRow(
    icon: ImageVector,
    title: String,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Orange icon like iOS
        Icon(
            imageVector = icon,
            contentDescription = title,
            modifier = Modifier.size(22.dp),
            tint = DollorTheme.Brand.orange
        )

        Spacer(modifier = Modifier.width(12.dp))

        Text(
            text = title,
            fontSize = Lx.FontSize.callout,
            color = Lx.Text,
            modifier = Modifier.weight(1f)
        )

        Icon(
            imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = "Navigate",
            tint = Lx.TextSecondary,
            modifier = Modifier.size(16.dp)
        )
    }
}

/**
 * Menu Divider
 */
@Composable
fun MenuDivider() {
    HorizontalDivider(
        modifier = Modifier.padding(start = 50.dp),
        color = Lx.Hairline.copy(alpha = 0.5f)
    )
}
