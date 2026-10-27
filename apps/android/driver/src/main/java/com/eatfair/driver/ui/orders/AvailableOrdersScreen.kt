package com.eatfair.driver.ui.orders

import com.eatfair.shared.config.AppConfig
import com.eatfair.driver.ui.home.AccessibilityNeedBadge
import com.eatfair.shared.ui.Lx
import com.eatfair.shared.ui.LxButton
import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavHostController
import com.eatfair.driver.ui.theme.DollorDriverColors
import com.eatfair.shared.model.rideshare.DriverOwnBid
import com.eatfair.shared.model.rideshare.RideRequestForBidding

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AvailableOrdersScreen(
    navController: NavHostController,
    viewModel: AvailableRidesViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val context = LocalContext.current

    LaunchedEffect(uiState.error) {
        uiState.error?.let {
            Toast.makeText(context, it, Toast.LENGTH_LONG).show()
            viewModel.clearError()
        }
    }
    LaunchedEffect(uiState.matchedRideId) {
        if (uiState.matchedRideId != null) {
            Toast.makeText(context, "Rider accepted — your ride is on Home", Toast.LENGTH_LONG).show()
            viewModel.onMatchedRideShown()
            navController.navigate("home") { launchSingleTop = true }
        }
    }
    LaunchedEffect(uiState.message) {
        uiState.message?.let {
            Toast.makeText(context, it, Toast.LENGTH_SHORT).show()
            viewModel.clearMessage()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = "Available Rides",
                        style = MaterialTheme.typography.titleLarge.copy(
                            fontWeight = FontWeight.Bold
                        )
                    )
                },
                actions = {
                    IconButton(onClick = { viewModel.load() }) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = Lx.Surface,
                    titleContentColor = DollorDriverColors.Gray900
                )
            )
        }
    ) { innerPadding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .background(DollorDriverColors.Background)
        ) {
            when {
                uiState.isLoading -> {
                    CircularProgressIndicator(
                        modifier = Modifier.align(Alignment.Center),
                        color = DollorDriverColors.Blue
                    )
                }

                uiState.rides.isEmpty() && uiState.myBids.isEmpty() && uiState.closedBids.isEmpty() -> {
                    EmptyRidesState(modifier = Modifier.align(Alignment.Center))
                }

                else -> {
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(16.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        if (uiState.myBids.isNotEmpty()) {
                            item { SectionTitle("Your offers") }
                            items(uiState.myBids, key = { "bid-${it.id}" }) { bid ->
                                MyBidCard(
                                    bid = bid,
                                    isBusy = uiState.busyId == bid.id,
                                    onAcceptCounter = { viewModel.acceptCounter(bid) },
                                    onRejectCounter = { viewModel.rejectCounter(bid) },
                                    onWithdraw = { viewModel.withdraw(bid) },
                                    onFinalCounter = { price -> viewModel.finalCounter(bid, price) }
                                )
                            }
                        }
                        if (uiState.rides.isNotEmpty()) {
                            item { SectionTitle("New requests") }
                            items(uiState.rides, key = { it.id }) { ride ->
                                RideRequestCard(
                                    ride = ride,
                                    isAccepting = uiState.busyId == ride.id,
                                    onSubmitBid = { price, eta, message -> viewModel.submitBid(ride, price, eta, message) }
                                )
                            }
                        }
                        if (uiState.closedBids.isNotEmpty()) {
                            item { SectionTitle("Recent") }
                            items(uiState.closedBids, key = { "closed-${it.id}" }) { bid -> ClosedBidCard(bid) }
                        }
                        item { Spacer(modifier = Modifier.height(80.dp)) }
                    }
                }
            }
        }
    }
}

@Composable
private fun EmptyRidesState(modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.padding(32.dp),
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
            text = "No ride requests right now",
            style = MaterialTheme.typography.bodyLarge,
            color = DollorDriverColors.Gray500
        )
        Text(
            text = "Make sure you're online. New requests appear here.",
            style = MaterialTheme.typography.bodySmall,
            color = DollorDriverColors.Gray400
        )
    }
}

@Composable
private fun SectionTitle(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.SemiBold),
        color = DollorDriverColors.Gray600
    )
}

private fun money(value: Double): String = "$" + String.format("%.2f", value)

@Composable
private fun PriceDialog(
    title: String,
    initial: Double?,
    confirmText: String,
    riderCounter: Double? = null,
    onConfirm: (Double) -> Unit,
    onDismiss: () -> Unit
) {
    var text by remember { mutableStateOf(initial?.let { String.format("%.2f", it) } ?: "") }
    val price = text.toDoubleOrNull()
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            OutlinedTextField(
                value = text,
                onValueChange = { v -> text = v.filter { it.isDigit() || it == '.' } },
                prefix = { Text("$") },
                singleLine = true,
                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                    keyboardType = androidx.compose.ui.text.input.KeyboardType.Decimal
                ),
                supportingText = {
                    val fee = money(AppConfig.Rideshare.calculatePlatformFee(price ?: 0.0))
                    Text(
                        if (riderCounter != null) "Must be more than the rider's ${money(riderCounter)} counter and the $fee platform fee"
                        else "Must be more than the $fee platform fee"
                    )
                }
            )
        },
        confirmButton = {
            TextButton(
                onClick = { price?.let(onConfirm) },
                enabled = price != null && price > AppConfig.Rideshare.calculatePlatformFee(price) && price > (riderCounter ?: 0.0)
            ) { Text(confirmText) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } }
    )
}

@Composable
private fun MyBidCard(
    bid: DriverOwnBid,
    isBusy: Boolean,
    onAcceptCounter: () -> Unit,
    onRejectCounter: () -> Unit,
    onWithdraw: () -> Unit,
    onFinalCounter: (Double) -> Unit
) {
    var showCounter by remember { mutableStateOf(false) }
    val ride = bid.rideRequest
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(Lx.Radius.card),
        colors = CardDefaults.cardColors(containerColor = Lx.Surface)
    ) {
        Column(modifier = Modifier.fillMaxWidth().padding(16.dp)) {
            Text(
                text = ride?.let { "${it.pickup.address} → ${it.dropoff.address}" } ?: "Ride #${bid.rideRequestId}",
                style = MaterialTheme.typography.bodyMedium,
                color = DollorDriverColors.Gray900
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "Your offer: ${money(bid.proposedPrice)}",
                style = MaterialTheme.typography.bodySmall,
                color = DollorDriverColors.Gray500
            )
            if (bid.isCountered) {
                Text(
                    text = "Rider countered: ${money(bid.customerCounterPrice!!)}",
                    style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold),
                    color = DollorDriverColors.Orange
                )
                Spacer(modifier = Modifier.height(12.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = onRejectCounter, enabled = !isBusy, modifier = Modifier.weight(1f)) {
                        Text("Decline")
                    }
                    OutlinedButton(onClick = { showCounter = true }, enabled = !isBusy, modifier = Modifier.weight(1f)) {
                        Text("Counter")
                    }
                    Button(
                        onClick = onAcceptCounter,
                        enabled = !isBusy,
                        modifier = Modifier.weight(1f),
                        colors = ButtonDefaults.buttonColors(containerColor = DollorDriverColors.Blue)
                    ) { Text("Accept") }
                }
            } else {
                Text(
                    text = "Waiting for the rider to respond…",
                    style = MaterialTheme.typography.bodySmall,
                    color = DollorDriverColors.Blue
                )
                TextButton(onClick = onWithdraw, enabled = !isBusy) { Text("Withdraw offer") }
            }
        }
    }
    if (showCounter) {
        PriceDialog(
            title = "Final counter-offer",
            initial = bid.proposedPrice,
            confirmText = "Send",
            riderCounter = bid.customerCounterPrice,
            onConfirm = { showCounter = false; onFinalCounter(it) },
            onDismiss = { showCounter = false }
        )
    }
}

@Composable
fun RideRequestCard(
    ride: RideRequestForBidding,
    isAccepting: Boolean,
    onSubmitBid: (price: Double, etaMinutes: Int, message: String?) -> Unit
) {
    var showBidSheet by remember { mutableStateOf(false) }
    if (showBidSheet) {
        SubmitBidSheet(
            ride = ride,
            isBusy = isAccepting,
            onSubmit = { price, eta, message -> showBidSheet = false; onSubmitBid(price, eta, message) },
            onDismiss = { showBidSheet = false }
        )
    }
    val fare = ride.riderOffer
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(Lx.Radius.card),
        colors = CardDefaults.cardColors(containerColor = Lx.Surface)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
        ) {
            // Header with customer + fare
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Icon(
                        imageVector = Icons.Default.Person,
                        contentDescription = null,
                        tint = DollorDriverColors.Blue
                    )
                    Text(
                        text = ride.customerName ?: "Rider",
                        style = MaterialTheme.typography.titleMedium.copy(
                            fontWeight = FontWeight.Medium
                        ),
                        color = DollorDriverColors.Gray900
                    )
                }
                Column(horizontalAlignment = Alignment.End) {
                    Text(
                        text = "Rider offers",
                        style = MaterialTheme.typography.bodySmall,
                        color = DollorDriverColors.Gray500
                    )
                    Text(
                        text = fare?.let(::money) ?: "--",
                        style = MaterialTheme.typography.titleLarge.copy(
                            fontWeight = FontWeight.Bold
                        ),
                        color = DollorDriverColors.Green
                    )
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Pickup
            Row(
                verticalAlignment = Alignment.Top,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Icon(
                    imageVector = Icons.Default.TripOrigin,
                    contentDescription = null,
                    tint = DollorDriverColors.Blue,
                    modifier = Modifier.size(20.dp)
                )
                Column {
                    Text("Pickup", style = MaterialTheme.typography.bodySmall, color = DollorDriverColors.Gray500)
                    Text(
                        text = ride.pickup.address,
                        style = MaterialTheme.typography.bodyMedium,
                        color = DollorDriverColors.Gray900
                    )
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            // Dropoff
            Row(
                verticalAlignment = Alignment.Top,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Icon(
                    imageVector = Icons.Default.LocationOn,
                    contentDescription = null,
                    tint = DollorDriverColors.Orange,
                    modifier = Modifier.size(20.dp)
                )
                Column {
                    Text("Dropoff", style = MaterialTheme.typography.bodySmall, color = DollorDriverColors.Gray500)
                    Text(
                        text = ride.dropoff.address,
                        style = MaterialTheme.typography.bodyMedium,
                        color = DollorDriverColors.Gray900
                    )
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            // Distances
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Icon(
                        imageVector = Icons.Default.Route,
                        contentDescription = null,
                        tint = DollorDriverColors.Gray400,
                        modifier = Modifier.size(16.dp)
                    )
                    Text(
                        text = "Trip ${ride.formattedTripDistance}",
                        style = MaterialTheme.typography.bodySmall,
                        color = DollorDriverColors.Gray500
                    )
                }
                if (ride.distanceToPickupKm != null) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Default.NearMe,
                            contentDescription = null,
                            tint = DollorDriverColors.Gray400,
                            modifier = Modifier.size(16.dp)
                        )
                        Text(
                            text = "${ride.formattedPickupDistance} away",
                            style = MaterialTheme.typography.bodySmall,
                            color = DollorDriverColors.Gray500
                        )
                    }
                }
            }

            ride.accessibilitySummary?.let { summary ->
                Spacer(modifier = Modifier.height(10.dp))
                AccessibilityNeedBadge(summary)
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Single primary action, like iOS: opens the bid sheet
            LxButton(
                text = "Submit Bid",
                onClick = { showBidSheet = true },
                enabled = !isAccepting,
                leading = { Icon(Icons.Default.PanTool, contentDescription = null, modifier = Modifier.size(18.dp)) }
            )
        }
    }
}

/** A bid that is no longer live, with the reason (e.g. "Accepted by another driver"). */
@Composable
private fun ClosedBidCard(bid: DriverOwnBid) {
    val ride = bid.rideRequest
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(Lx.Radius.card),
        colors = CardDefaults.cardColors(containerColor = Lx.Surface)
    ) {
        Column(modifier = Modifier.fillMaxWidth().padding(Lx.Spacing.l), verticalArrangement = Arrangement.spacedBy(Lx.Spacing.xs)) {
            Text(
                text = ride?.let { "${it.pickup.address} → ${it.dropoff.address}" } ?: "Ride #${bid.rideRequestId}",
                fontSize = Lx.FontSize.subheadline,
                color = Lx.TextSecondary
            )
            Text(
                text = bid.closedReason.orEmpty(),
                fontSize = Lx.FontSize.subheadline,
                fontWeight = FontWeight.SemiBold,
                color = Lx.Orange
            )
            Text(text = "Your offer: ${money(bid.proposedPrice)}", fontSize = Lx.FontSize.caption, color = Lx.TextMuted)
        }
    }
}
