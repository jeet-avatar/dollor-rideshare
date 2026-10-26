package com.eatfair.driver.ui.home

import com.eatfair.shared.ui.Lx
import com.eatfair.driver.R
import com.google.android.gms.maps.model.MapStyleOptions
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.eatfair.driver.ui.theme.DollorDriverColors
import com.eatfair.shared.model.rideshare.RideChatMessage
import com.eatfair.shared.model.rideshare.RideLocation
import com.eatfair.shared.model.rideshare.RideRequestForBidding
import com.google.android.gms.maps.model.CameraPosition
import com.google.android.gms.maps.model.LatLng
import com.google.android.gms.maps.model.LatLngBounds
import com.google.maps.android.compose.GoogleMap
import com.google.maps.android.compose.MapProperties
import com.google.maps.android.compose.MapUiSettings
import com.google.maps.android.compose.Marker
import com.google.maps.android.compose.MarkerState
import com.google.maps.android.compose.rememberCameraPositionState
import com.google.android.gms.maps.CameraUpdateFactory
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneOffset

private const val NO_SHOW_WAIT_SECONDS = 300L

private val CANCEL_REASONS_BEFORE_ARRIVAL = listOf(
    "Rider asked me to cancel",
    "Can't reach pickup location",
    "Vehicle issue",
    "Safety concern",
    "Other"
)
private val CANCEL_REASONS_AFTER_ARRIVAL = listOf(
    "Rider not at pickup",
    "Wrong pickup address",
    "Too many passengers",
    "Safety concern",
    "Other"
)

private fun money(v: Double?): String = v?.let { "$" + String.format("%.2f", it) } ?: "--"

/** Turn-by-turn navigation: pickup until the trip starts, then dropoff (iOS parity). */
fun launchNavigation(context: Context, target: RideLocation) {
    val nav = Intent(Intent.ACTION_VIEW, Uri.parse("google.navigation:q=${target.latitude},${target.longitude}"))
        .setPackage("com.google.android.apps.maps")
    val fallback = Intent(
        Intent.ACTION_VIEW,
        Uri.parse("https://www.google.com/maps/dir/?api=1&destination=${target.latitude},${target.longitude}&travelmode=driving")
    )
    runCatching { context.startActivity(nav) }.onFailure { context.startActivity(fallback) }
}

private fun dial(context: Context, number: String) {
    context.startActivity(Intent(Intent.ACTION_DIAL, Uri.parse("tel:$number")))
}

private fun secondsSince(iso: String?): Long? {
    iso ?: return null
    return runCatching {
        val t = runCatching { Instant.parse(iso) }.getOrElse { LocalDateTime.parse(iso).toInstant(ZoneOffset.UTC) }
        (System.currentTimeMillis() - t.toEpochMilli()) / 1000
    }.getOrNull()
}

@Composable
fun ActiveRidePanel(
    ride: RideRequestForBidding,
    isBusy: Boolean,
    onArrived: () -> Unit,
    onStart: () -> Unit,
    onComplete: () -> Unit,
    onCancel: (String) -> Unit,
    onNoShow: () -> Unit,
    onChat: () -> Unit
) {
    val context = LocalContext.current
    var showCancel by remember { mutableStateOf(false) }
    var showSos by remember { mutableStateOf(false) }

    // Re-evaluate the no-show wait every second once arrived.
    var waited by remember(ride.driverArrivedAt) { mutableStateOf(secondsSince(ride.driverArrivedAt) ?: 0L) }
    LaunchedEffect(ride.driverArrivedAt) {
        while (ride.driverArrivedAt != null) {
            waited = secondsSince(ride.driverArrivedAt) ?: 0L
            kotlinx.coroutines.delay(1000)
        }
    }

    val pickup = LatLng(ride.pickup.latitude, ride.pickup.longitude)
    val dropoff = LatLng(ride.dropoff.latitude, ride.dropoff.longitude)
    val camera = rememberCameraPositionState { position = CameraPosition.fromLatLngZoom(pickup, 13f) }
    LaunchedEffect(ride.id) {
        runCatching {
            camera.move(CameraUpdateFactory.newLatLngBounds(LatLngBounds.builder().include(pickup).include(dropoff).build(), 80))
        }
    }

    val (stageTitle, stageColor) = when {
        ride.isInProgress -> "Trip in progress" to DollorDriverColors.Green
        ride.hasArrived -> "Waiting for rider" to DollorDriverColors.Orange
        else -> "Heading to pickup" to DollorDriverColors.Blue
    }

    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(Lx.Radius.card),
        colors = CardDefaults.cardColors(containerColor = Lx.Surface)
    ) {
        GoogleMap(
            modifier = Modifier.fillMaxWidth().height(200.dp),
            cameraPositionState = camera,
            properties = MapProperties(
                isMyLocationEnabled = false,
                mapStyleOptions = rememberDarkMapStyle()
            ),
            uiSettings = MapUiSettings(zoomControlsEnabled = false, mapToolbarEnabled = false)
        ) {
            Marker(state = MarkerState(pickup), title = "Pickup", snippet = ride.pickup.address)
            Marker(state = MarkerState(dropoff), title = "Dropoff", snippet = ride.dropoff.address)
        }

        Column(modifier = Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(stageTitle, color = stageColor, fontWeight = FontWeight.SemiBold)
                    Text(
                        ride.customerName ?: "Rider",
                        style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold),
                        color = DollorDriverColors.Gray900
                    )
                }
                Column(horizontalAlignment = Alignment.End) {
                    Text("Fare", style = MaterialTheme.typography.bodySmall, color = DollorDriverColors.Gray500)
                    Text(
                        money(ride.finalPrice ?: ride.riderOffer),
                        style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold),
                        color = DollorDriverColors.Green
                    )
                }
            }

            AddressLine(Icons.Default.TripOrigin, DollorDriverColors.Blue, "Pickup", ride.pickup.address)
            AddressLine(Icons.Default.LocationOn, DollorDriverColors.Orange, "Dropoff", ride.dropoff.address)
            Text(
                "Trip ${ride.formattedTripDistance} · ${ride.formattedDuration}",
                style = MaterialTheme.typography.bodySmall,
                color = DollorDriverColors.Gray500
            )

            ride.accessibilitySummary?.let { summary ->
                AccessibilityNeedBadge(summary)
            }

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                RideIconButton(Icons.Default.Navigation, "Navigate", Modifier.weight(1f)) {
                    launchNavigation(context, if (ride.isInProgress) ride.dropoff else ride.pickup)
                }
                RideIconButton(Icons.Default.Chat, "Chat", Modifier.weight(1f), onClick = onChat)
                RideIconButton(Icons.Default.Phone, "Call", Modifier.weight(1f)) {
                    val phone = ride.customerPhone
                    if (phone.isNullOrBlank()) {
                        Toast.makeText(context, "Rider's number isn't available — use Chat", Toast.LENGTH_SHORT).show()
                    } else dial(context, phone)
                }
                RideIconButton(Icons.Default.Sos, "SOS", Modifier.weight(1f), tint = Lx.Error) { showSos = true }
            }

            when {
                ride.isInProgress -> PrimaryAction("Complete Trip", DollorDriverColors.Green, isBusy, onComplete)
                ride.hasArrived -> PrimaryAction("Start Trip", DollorDriverColors.Blue, isBusy, onStart)
                else -> PrimaryAction("I've Arrived", DollorDriverColors.Blue, isBusy, onArrived)
            }

            if (ride.hasArrived && !ride.isInProgress) {
                val remaining = (NO_SHOW_WAIT_SECONDS - waited).coerceAtLeast(0)
                OutlinedButton(
                    onClick = onNoShow,
                    enabled = !isBusy && remaining == 0L,
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(Lx.Radius.button)
                ) {
                    Text(
                        if (remaining > 0) "No-show available in ${remaining / 60}:${String.format("%02d", remaining % 60)}"
                        else "Rider didn't show — mark no-show"
                    )
                }
            }

            if (!ride.isInProgress) {
                TextButton(onClick = { showCancel = true }, enabled = !isBusy, modifier = Modifier.fillMaxWidth()) {
                    Text("Cancel ride", color = Lx.Error)
                }
            }
        }
    }

    if (showCancel) {
        val reasons = if (ride.hasArrived) CANCEL_REASONS_AFTER_ARRIVAL else CANCEL_REASONS_BEFORE_ARRIVAL
        AlertDialog(
            onDismissRequest = { showCancel = false },
            title = { Text("Why are you cancelling?") },
            text = {
                Column {
                    reasons.forEach { reason ->
                        TextButton(onClick = {
                            showCancel = false
                            if (reason == "Safety concern") showSos = true
                            onCancel(reason)
                        }, modifier = Modifier.fillMaxWidth()) { Text(reason, modifier = Modifier.fillMaxWidth()) }
                    }
                }
            },
            confirmButton = {},
            dismissButton = { TextButton(onClick = { showCancel = false }) { Text("Keep ride") } }
        )
    }

    if (showSos) {
        AlertDialog(
            onDismissRequest = { showSos = false },
            icon = { Icon(Icons.Default.Sos, contentDescription = null, tint = Lx.Error) },
            title = { Text("Emergency") },
            text = { Text("If you or your rider are in danger, call 911 now.") },
            confirmButton = {
                TextButton(onClick = { showSos = false; dial(context, "911") }) {
                    Text("Call 911", color = Lx.Error, fontWeight = FontWeight.Bold)
                }
            },
            dismissButton = { TextButton(onClick = { showSos = false }) { Text("Close") } }
        )
    }
}

@Composable
private fun AddressLine(icon: androidx.compose.ui.graphics.vector.ImageVector, tint: Color, label: String, address: String) {
    Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(20.dp))
        Column {
            Text(label, style = MaterialTheme.typography.bodySmall, color = DollorDriverColors.Gray500)
            Text(address, style = MaterialTheme.typography.bodyMedium, color = DollorDriverColors.Gray900)
        }
    }
}

@Composable
private fun RideIconButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    modifier: Modifier,
    tint: Color = DollorDriverColors.Blue,
    onClick: () -> Unit
) {
    OutlinedButton(onClick = onClick, modifier = modifier, contentPadding = PaddingValues(vertical = 8.dp), shape = RoundedCornerShape(Lx.Radius.button)) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(icon, contentDescription = label, tint = tint, modifier = Modifier.size(20.dp))
            Text(label, style = MaterialTheme.typography.labelSmall, color = DollorDriverColors.Gray700)
        }
    }
}

@Composable
private fun PrimaryAction(label: String, color: Color, busy: Boolean, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        enabled = !busy,
        modifier = Modifier.fillMaxWidth().height(52.dp),
        shape = RoundedCornerShape(Lx.Radius.button),
        colors = ButtonDefaults.buttonColors(containerColor = color)
    ) {
        if (busy) CircularProgressIndicator(modifier = Modifier.size(20.dp), color = Color.White, strokeWidth = 2.dp)
        else Text(label, fontWeight = FontWeight.Bold)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RideChatSheet(
    riderName: String?,
    messages: List<RideChatMessage>,
    onSend: (String) -> Unit,
    onDismiss: () -> Unit
) {
    var draft by remember { mutableStateOf("") }
    val listState = rememberLazyListState()
    LaunchedEffect(messages.size) { if (messages.isNotEmpty()) listState.animateScrollToItem(messages.lastIndex) }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ) {
        Column(modifier = Modifier.fillMaxWidth().fillMaxHeight(0.75f).padding(horizontal = 16.dp)) {
            Text(
                "Chat with ${riderName ?: "rider"}",
                style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold)
            )
            Spacer(Modifier.height(8.dp))
            LazyColumn(state = listState, modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                if (messages.isEmpty()) {
                    item { Text("No messages yet. Say hi!", color = DollorDriverColors.Gray500) }
                }
                items(messages, key = { it.id }) { msg ->
                    val mine = msg.senderType == "driver"
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = if (mine) Arrangement.End else Arrangement.Start) {
                        Text(
                            msg.message,
                            color = if (mine) Color.White else DollorDriverColors.Gray900,
                            modifier = Modifier
                                .background(
                                    if (mine) DollorDriverColors.Blue else DollorDriverColors.Gray300.copy(alpha = 0.5f),
                                    RoundedCornerShape(Lx.Radius.button)
                                )
                                .padding(horizontal = 12.dp, vertical = 8.dp)
                                .widthIn(max = 260.dp)
                        )
                    }
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(vertical = 12.dp)) {
                OutlinedTextField(
                    value = draft,
                    onValueChange = { draft = it },
                    placeholder = { Text("Message") },
                    modifier = Modifier.weight(1f),
                    maxLines = 3
                )
                IconButton(onClick = { onSend(draft); draft = "" }, enabled = draft.isNotBlank()) {
                    Icon(Icons.AutoMirrored.Filled.Send, contentDescription = "Send", tint = DollorDriverColors.Blue)
                }
            }
        }
    }
}

@Composable
fun TripSummaryDialog(ride: RideRequestForBidding, onRate: (Int, String?) -> Unit, onSkip: () -> Unit) {
    var stars by remember { mutableIntStateOf(5) }
    var comment by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onSkip,
        title = { Text("Trip complete") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                SummaryRow("Fare", money(ride.finalPrice))
                ride.platformFee?.let { SummaryRow("Connection fee", "-" + money(it)) }
                val fare = ride.finalPrice
                val fee = ride.platformFee
                val payout = ride.driverPayout
                if (fare != null && fee != null && payout != null) {
                    val accessForAll = fare + (ride.tipAmount ?: 0.0) - fee - payout
                    if (accessForAll > 0.004) SummaryRow("CPUC Access for All", "-" + money(accessForAll))
                }
                ride.tipAmount?.takeIf { it > 0 }?.let { SummaryRow("Tip", money(it)) }
                ride.driverPayout?.let { SummaryRow("You earn", money(it), bold = true) }
                Spacer(Modifier.height(8.dp))
                Text("Rate ${ride.customerName ?: "your rider"}", fontWeight = FontWeight.SemiBold)
                Row {
                    (1..5).forEach { i ->
                        IconButton(onClick = { stars = i }) {
                            Icon(
                                if (i <= stars) Icons.Default.Star else Icons.Default.StarBorder,
                                contentDescription = "$i stars",
                                tint = Lx.Gold
                            )
                        }
                    }
                }
                OutlinedTextField(value = comment, onValueChange = { comment = it }, placeholder = { Text("Comment (optional)") })
            }
        },
        confirmButton = { TextButton(onClick = { onRate(stars, comment) }) { Text("Submit") } },
        dismissButton = { TextButton(onClick = onSkip) { Text("Skip") } }
    )
}

@Composable
private fun SummaryRow(label: String, value: String, bold: Boolean = false) {
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, color = DollorDriverColors.Gray600)
        Text(value, fontWeight = if (bold) FontWeight.Bold else FontWeight.Normal, color = DollorDriverColors.Gray900)
    }
}

@androidx.compose.runtime.Composable
private fun rememberDarkMapStyle(): MapStyleOptions {
    val context = LocalContext.current
    return androidx.compose.runtime.remember { MapStyleOptions.loadRawResourceStyle(context, R.raw.map_dark) }
}

@Composable
internal fun AccessibilityNeedBadge(summary: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(Lx.OrangeTint, RoundedCornerShape(Lx.Radius.chip))
            .padding(10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Icon(
            imageVector = Icons.Default.Accessible,
            contentDescription = "Accessibility request",
            tint = Lx.Orange,
            modifier = Modifier.size(18.dp)
        )
        Text(
            text = summary,
            style = MaterialTheme.typography.bodySmall,
            color = Lx.Text
        )
    }
}
