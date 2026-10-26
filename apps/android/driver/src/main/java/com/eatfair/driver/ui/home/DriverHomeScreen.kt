package com.eatfair.driver.ui.home

import com.eatfair.shared.config.AppConfig
import com.eatfair.shared.ui.Lx
import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import android.net.Uri
import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavHostController
import com.eatfair.driver.ui.theme.DollorDriverColors

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DriverHomeScreen(
    navController: NavHostController,
    driverName: String? = null,
    viewModel: DriverHomeViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val context = LocalContext.current

    // Surface server messages / errors (e.g. "Background check not passed...").
    LaunchedEffect(uiState.error) {
        uiState.error?.let {
            Toast.makeText(context, it, Toast.LENGTH_LONG).show()
            viewModel.clearError()
        }
    }
    LaunchedEffect(uiState.message) {
        uiState.message?.let {
            Toast.makeText(context, it, Toast.LENGTH_SHORT).show()
            viewModel.clearMessage()
        }
    }

    val isOnline = uiState.isOnline

    fun hasLocation() = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) ==
        PackageManager.PERMISSION_GRANTED
    var showLocationRationale by remember { mutableStateOf(false) }
    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { granted ->
        if (granted[Manifest.permission.ACCESS_FINE_LOCATION] == true ||
            granted[Manifest.permission.ACCESS_COARSE_LOCATION] == true
        ) {
            viewModel.setOnline(true)
        } else {
            Toast.makeText(context, "Location is required to receive nearby ride requests", Toast.LENGTH_LONG).show()
        }
    }
    fun requestGoOnline() {
        if (hasLocation()) viewModel.setOnline(true) else showLocationRationale = true
    }
    LaunchedEffect(isOnline) {
        if (isOnline && hasLocation()) viewModel.onLocationPermissionGranted()
    }

    if (showLocationRationale) {
        AlertDialog(
            onDismissRequest = { showLocationRationale = false },
            title = { Text("Share your location while online") },
            text = {
                Text(
                    "Dollor Driver uses your location while you're online and the app is open to show " +
                        "nearby ride requests, your distance to pickup, and your live position to your rider. " +
                        "Location is not collected when you're offline."
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    showLocationRationale = false
                    val perms = mutableListOf(
                        Manifest.permission.ACCESS_FINE_LOCATION,
                        Manifest.permission.ACCESS_COARSE_LOCATION
                    )
                    if (Build.VERSION.SDK_INT >= 33) perms += Manifest.permission.POST_NOTIFICATIONS
                    permissionLauncher.launch(perms.toTypedArray())
                }) { Text("Continue") }
            },
            dismissButton = { TextButton(onClick = { showLocationRationale = false }) { Text("Not now") } }
        )
    }

    uiState.completedRide?.let { done ->
        TripSummaryDialog(ride = done, onRate = { r, c -> viewModel.rateRider(r, c) }, onSkip = { viewModel.dismissSummary() })
    }
    val chatRide = uiState.activeRide
    if (uiState.chatOpen && chatRide != null) {
        RideChatSheet(
            riderName = chatRide.customerName,
            messages = uiState.chatMessages,
            onSend = { viewModel.sendChat(it) },
            onDismiss = { viewModel.closeChat() }
        )
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(DollorDriverColors.Background),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // Header
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text(
                        text = "Welcome back,",
                        style = MaterialTheme.typography.bodyMedium,
                        color = DollorDriverColors.Gray500
                    )
                    Text(
                        text = driverName?.ifBlank { null } ?: "Driver",
                        style = MaterialTheme.typography.headlineMedium.copy(
                            fontWeight = FontWeight.Bold
                        ),
                        color = DollorDriverColors.Gray900
                    )
                }

                // Online/Offline Toggle (real: PUT /api/auth/driver/online)
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    if (uiState.isToggling) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(18.dp),
                            strokeWidth = 2.dp,
                            color = DollorDriverColors.Blue
                        )
                    }
                    Text(
                        text = if (isOnline) "Online" else "Offline",
                        style = MaterialTheme.typography.bodyMedium.copy(
                            fontWeight = FontWeight.Medium
                        ),
                        color = if (isOnline) DollorDriverColors.Green else DollorDriverColors.Gray500
                    )
                    Switch(
                        checked = isOnline,
                        onCheckedChange = { target -> if (target) requestGoOnline() else viewModel.setOnline(false) },
                        enabled = !uiState.isToggling,
                        colors = SwitchDefaults.colors(
                            checkedThumbColor = DollorDriverColors.White,
                            checkedTrackColor = DollorDriverColors.Green,
                            uncheckedThumbColor = DollorDriverColors.White,
                            uncheckedTrackColor = DollorDriverColors.Gray300
                        )
                    )
                }
            }
        }

        uiState.activeRide?.let { ride ->
            item(key = "active-ride") {
                ActiveRidePanel(
                    ride = ride,
                    isBusy = uiState.isRideActionInProgress,
                    onArrived = { viewModel.markArrived() },
                    onStart = { viewModel.startRide() },
                    onComplete = { viewModel.completeRide() },
                    onCancel = { viewModel.cancelRide(it) },
                    onNoShow = { viewModel.markNoShow() },
                    onChat = { viewModel.openChat() }
                )
            }
        }

        if (uiState.activeRide == null) item(key = "status-card") {
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(Lx.Radius.sheet),
                colors = CardDefaults.cardColors(containerColor = Lx.Surface)
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(
                            brush = Brush.horizontalGradient(
                                colors = listOf(
                                    DollorDriverColors.Blue,
                                    DollorDriverColors.BlueDark
                                )
                            )
                        )
                        .padding(24.dp)
                ) {
                    Column {
                        Text(
                            text = if (isOnline) "You're Online" else "You're Offline",
                            style = MaterialTheme.typography.headlineSmall.copy(
                                fontWeight = FontWeight.Bold
                            ),
                            color = DollorDriverColors.White
                        )
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(
                            text = if (isOnline) "Waiting for ride requests..." else "Go online to receive requests",
                            style = MaterialTheme.typography.bodyMedium,
                            color = DollorDriverColors.White.copy(alpha = 0.8f)
                        )
                    }
                }
            }
        }

        // Today's Stats
        item {
            Text(
                text = "Today's Stats",
                style = MaterialTheme.typography.titleMedium.copy(
                    fontWeight = FontWeight.Bold
                ),
                color = DollorDriverColors.Gray900
            )
        }

        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                StatCard(
                    modifier = Modifier.weight(1f),
                    icon = Icons.Default.AttachMoney,
                    value = "$" + String.format("%.2f", uiState.todayEarnings),
                    label = "Earnings",
                    color = DollorDriverColors.Green
                )
                StatCard(
                    modifier = Modifier.weight(1f),
                    icon = Icons.Default.DirectionsCar,
                    value = uiState.todayRides.toString(),
                    label = "Rides",
                    color = DollorDriverColors.Blue
                )
                StatCard(
                    modifier = Modifier.weight(1f),
                    icon = Icons.Default.AccessTime,
                    value = String.format("%.1fh", uiState.todayHours),
                    label = "Online",
                    color = DollorDriverColors.Orange
                )
            }
        }

        // Quick Actions
        item {
            Text(
                text = "Quick Actions",
                style = MaterialTheme.typography.titleMedium.copy(
                    fontWeight = FontWeight.Bold
                ),
                color = DollorDriverColors.Gray900,
                modifier = Modifier.padding(top = 8.dp)
            )
        }

        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                QuickActionCard(
                    modifier = Modifier.weight(1f),
                    icon = Icons.Default.Map,
                    title = "Navigate",
                    onClick = {
                        val ride = uiState.activeRide
                        if (ride != null) {
                            launchNavigation(context, if (ride.isInProgress) ride.dropoff else ride.pickup)
                        } else {
                            Toast.makeText(context, "No active ride to navigate", Toast.LENGTH_SHORT).show()
                        }
                    }
                )
                QuickActionCard(
                    modifier = Modifier.weight(1f),
                    icon = Icons.Default.History,
                    title = "History",
                    onClick = {
                        // Same navigation as the bottom tab, so the Home tab is not left showing Earnings
                        navController.navigate("earnings") {
                            popUpTo(navController.graph.startDestinationId) { saveState = true }
                            launchSingleTop = true
                            restoreState = true
                        }
                    }
                )
                QuickActionCard(
                    modifier = Modifier.weight(1f),
                    icon = Icons.Default.Support,
                    title = "Support",
                    onClick = {
                        val intent = Intent(Intent.ACTION_SENDTO).apply {
                            data = Uri.parse("mailto:${AppConfig.Rideshare.support.email}")
                            putExtra(Intent.EXTRA_SUBJECT, "Dollor Driver Support")
                        }
                        if (intent.resolveActivity(context.packageManager) != null) {
                            context.startActivity(intent)
                        } else {
                            Toast.makeText(context, AppConfig.Rideshare.support.email, Toast.LENGTH_LONG).show()
                        }
                    }
                )
            }
        }

        // Recent activity (the active ride, when present, is pinned to the top)
        if (uiState.activeRide == null) item {
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "Recent Activity",
                style = MaterialTheme.typography.titleMedium.copy(
                    fontWeight = FontWeight.Bold
                ),
                color = DollorDriverColors.Gray900
            )
        }

        if (uiState.activeRide == null) item {
            run {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(Lx.Radius.card),
                    colors = CardDefaults.cardColors(containerColor = Lx.Surface)
                ) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(20.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Icon(
                            imageVector = Icons.Default.DirectionsCar,
                            contentDescription = null,
                            modifier = Modifier.size(48.dp),
                            tint = DollorDriverColors.Gray300
                        )
                        Spacer(modifier = Modifier.height(12.dp))
                        Text(
                            text = "No active ride",
                            style = MaterialTheme.typography.bodyLarge,
                            color = DollorDriverColors.Gray500
                        )
                        Text(
                            text = if (isOnline) "You'll see your matched ride here" else "Go online to receive requests",
                            style = MaterialTheme.typography.bodySmall,
                            color = DollorDriverColors.Gray400
                        )
                    }
                }
            }
        }
    }
}

@Composable
fun StatCard(
    modifier: Modifier = Modifier,
    icon: ImageVector,
    value: String,
    label: String,
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
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(CircleShape)
                    .background(color.copy(alpha = 0.1f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    tint = color,
                    modifier = Modifier.size(20.dp)
                )
            }
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = value,
                style = MaterialTheme.typography.titleLarge.copy(
                    fontWeight = FontWeight.Bold
                ),
                color = DollorDriverColors.Gray900
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
fun QuickActionCard(
    modifier: Modifier = Modifier,
    icon: ImageVector,
    title: String,
    onClick: () -> Unit
) {
    Card(
        modifier = modifier,
        shape = RoundedCornerShape(Lx.Radius.card),
        colors = CardDefaults.cardColors(containerColor = Lx.Surface),
        onClick = onClick
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Box(
                modifier = Modifier
                    .size(48.dp)
                    .clip(CircleShape)
                    .background(DollorDriverColors.Blue.copy(alpha = 0.1f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    tint = DollorDriverColors.Blue,
                    modifier = Modifier.size(24.dp)
                )
            }
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = title,
                style = MaterialTheme.typography.bodyMedium.copy(
                    fontWeight = FontWeight.Medium
                ),
                color = DollorDriverColors.Gray700
            )
        }
    }
}
