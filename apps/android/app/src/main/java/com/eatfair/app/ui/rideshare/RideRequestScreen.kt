package com.eatfair.app.ui.rideshare

import com.eatfair.app.R
import com.google.android.gms.maps.model.MapStyleOptions
import com.eatfair.shared.ui.Lx
import com.eatfair.shared.ui.LxButton
import com.eatfair.shared.ui.LxButtonRole
import android.Manifest
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import com.eatfair.app.ui.theme.DollorTheme
import com.eatfair.shared.config.AppConfig
import com.eatfair.shared.model.rideshare.DriverBidForCustomer
import com.google.accompanist.permissions.ExperimentalPermissionsApi
import com.google.accompanist.permissions.isGranted
import com.google.accompanist.permissions.rememberPermissionState
import com.google.android.gms.maps.CameraUpdateFactory
import com.google.android.gms.maps.model.CameraPosition
import com.google.android.gms.maps.model.LatLng
import com.google.android.gms.maps.model.LatLngBounds
import com.google.maps.android.compose.*

/**
 * RideRequestScreen - Matches iOS RideRequestView exactly
 * Uber-style design with:
 * - Full-screen Google Maps background
 * - Bottom sheet overlay for ride details
 * - Custom map markers for pickup/dropoff
 * - P2P fare negotiation UI
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalPermissionsApi::class)
@Composable
fun RideRequestScreen(
    viewModel: RideRequestViewModel = hiltViewModel(),
    onBackClick: () -> Unit,
    onNavigateToActiveRide: (Int) -> Unit = {},
    onNavigateToChat: (Int, String) -> Unit = { _, _ -> }
) {
    val context = LocalContext.current

    // Initialize ViewModel
    LaunchedEffect(Unit) {
        viewModel.initialize(context)
    }

    // Collect states
    val currentStep by viewModel.currentStep.collectAsState()
    val pickupLocation by viewModel.pickupLocation.collectAsState()
    val dropoffLocation by viewModel.dropoffLocation.collectAsState()
    val currentLocation by viewModel.currentLocation.collectAsState()
    val estimatedFare by viewModel.estimatedFare.collectAsState()
    val suggestedPrice by viewModel.suggestedPrice.collectAsState()
    val incomingBids by viewModel.incomingBids.collectAsState()
    val ratingSubmitted by viewModel.ratingSubmitted.collectAsState()
    val activeRideForCountdown by viewModel.activeRideRequest.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val showError by viewModel.showError.collectAsState()
    val errorMessage by viewModel.errorMessage.collectAsState()
    val messageTitle by viewModel.messageTitle.collectAsState()
    val riderFirstName by viewModel.riderFirstName.collectAsState(initial = "")
    val selectedBid by viewModel.selectedBid.collectAsState()
    val rideTracking by viewModel.rideTracking.collectAsState()
    val platformFee by viewModel.platformFee.collectAsState()

    // Local states
    var showPickupSearch by remember { mutableStateOf(false) }
    var showDropoffSearch by remember { mutableStateOf(false) }
    var showNegotiateSheet by remember { mutableStateOf(false) }
    var selectedTip by remember { mutableStateOf(0.0) }
    var showRating by remember { mutableStateOf(false) }
    var showReceipt by remember { mutableStateOf(false) }
    val rideReceipt by viewModel.rideReceipt.collectAsState()
    val isLoadingReceipt by viewModel.isLoadingReceipt.collectAsState()

    // Location permission
    val locationPermission = rememberPermissionState(Manifest.permission.ACCESS_FINE_LOCATION)

    LaunchedEffect(Unit) {
        if (!locationPermission.status.isGranted) {
            locationPermission.launchPermissionRequest()
        }
    }

    // Re-initialize ViewModel when permission is granted to get current location
    LaunchedEffect(locationPermission.status.isGranted) {
        if (locationPermission.status.isGranted) {
            viewModel.initialize(context)
        }
    }

    // Map camera state - centers on user's current location
    val defaultLocation = LatLng(AppConfig.Location.FALLBACK_LATITUDE, AppConfig.Location.FALLBACK_LONGITUDE)
    val cameraPositionState = rememberCameraPositionState {
        position = CameraPosition.fromLatLngZoom(defaultLocation, 14f)
    }

    // Center on user's current location when available
    LaunchedEffect(currentLocation) {
        currentLocation?.let { location ->
            cameraPositionState.animate(
                CameraUpdateFactory.newLatLngZoom(
                    LatLng(location.latitude, location.longitude), 15f
                )
            )
        }
    }

    // Update map when pickup/dropoff locations change
    LaunchedEffect(pickupLocation, dropoffLocation) {
        val pickup = pickupLocation
        val dropoff = dropoffLocation

        if (pickup != null && dropoff != null) {
            // Show both pickup and dropoff with padding
            val bounds = LatLngBounds.Builder()
                .include(LatLng(pickup.latitude, pickup.longitude))
                .include(LatLng(dropoff.latitude, dropoff.longitude))
                .build()
            cameraPositionState.animate(CameraUpdateFactory.newLatLngBounds(bounds, 100))
        } else if (pickup != null) {
            // Center on pickup location
            cameraPositionState.animate(
                CameraUpdateFactory.newLatLngZoom(
                    LatLng(pickup.latitude, pickup.longitude), 15f
                )
            )
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        // Full-screen Map Background - Matches iOS
        GoogleMap(
            modifier = Modifier.fillMaxSize(),
            cameraPositionState = cameraPositionState,
            properties = MapProperties(
                isMyLocationEnabled = locationPermission.status.isGranted,
                mapStyleOptions = rememberDarkMapStyle()
            ),
            uiSettings = MapUiSettings(
                zoomControlsEnabled = false,
                myLocationButtonEnabled = true,
                mapToolbarEnabled = false
            )
        ) {
            // Pickup Marker - Blue circle with wave figure
            pickupLocation?.let { pickup ->
                Marker(
                    state = MarkerState(position = LatLng(pickup.latitude, pickup.longitude)),
                    title = "Pickup",
                    snippet = pickup.address
                )
            }

            // Dropoff Marker - Green circle with flag
            dropoffLocation?.let { dropoff ->
                Marker(
                    state = MarkerState(position = LatLng(dropoff.latitude, dropoff.longitude)),
                    title = "Dropoff",
                    snippet = dropoff.address
                )
            }

            // Driver location marker (when tracking)
            rideTracking?.let { tracking ->
                tracking.driver?.let { driver ->
                    driver.latitude?.let { lat ->
                        driver.longitude?.let { lng ->
                            Marker(
                                state = MarkerState(position = LatLng(lat, lng)),
                                title = "Driver",
                                snippet = driver.name
                            )
                        }
                    }
                }
            }
        }

        // Loading Overlay - Matches iOS
        if (isLoading && currentStep == RideRequestViewModel.RideStep.WAITING_FOR_BIDS) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black.copy(alpha = 0.3f)),
                contentAlignment = Alignment.Center
            ) {
                Card(
                    shape = RoundedCornerShape(Lx.Radius.button),
                    colors = CardDefaults.cardColors(containerColor = Lx.Surface)
                ) {
                    Column(
                        modifier = Modifier.padding(24.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        CircularProgressIndicator(color = DollorTheme.Brand.green)
                        Spacer(modifier = Modifier.height(12.dp))
                        Text(
                            text = "Requesting ride...",
                            fontWeight = FontWeight.Medium
                        )
                    }
                }
            }
        }

        // Bottom Sheet - Matches iOS RideBottomSheet
        Column(
            modifier = Modifier.fillMaxSize(),
            verticalArrangement = Arrangement.Bottom
        ) {
            when (currentStep) {
                RideRequestViewModel.RideStep.SELECT_PICKUP,
                RideRequestViewModel.RideStep.SELECT_DROPOFF,
                RideRequestViewModel.RideStep.CONFIRM_RIDE -> {
                    RideBottomSheet(
                        viewModel = viewModel,
                        pickupLocation = pickupLocation,
                        dropoffLocation = dropoffLocation,
                        estimatedFare = estimatedFare,
                        suggestedPrice = suggestedPrice,
                        platformFee = platformFee,
                        selectedTip = selectedTip,
                        onTipSelected = {
                            selectedTip = it
                            // Persist to the ViewModel so the tip can be posted to the
                            // driver after the ride completes (local state isn't visible
                            // to the ViewModel's submitTip()).
                            viewModel.setTipAmount(it)
                        },
                        onPickupClick = { showPickupSearch = true },
                        onDropoffClick = { showDropoffSearch = true },
                        onRequestRide = {
                            viewModel.createRideRequest()
                        },
                        onMakeOffer = { showNegotiateSheet = true },
                        onDismiss = onBackClick,
                        isLoading = isLoading
                    )
                }

                RideRequestViewModel.RideStep.WAITING_FOR_BIDS -> {
                    WaitingForBidsSheet(
                        biddingEndsAtMillis = activeRideForCountdown?.biddingExpiresAtMillis,
                        onCancel = { viewModel.cancelRide() }
                    )
                }

                RideRequestViewModel.RideStep.VIEW_BIDS -> {
                    ViewBidsSheet(
                        bids = incomingBids,
                        biddingEndsAtMillis = activeRideForCountdown?.biddingExpiresAtMillis,
                        onAcceptBid = { viewModel.acceptBid(it) },
                        onRejectBid = { viewModel.rejectBid(it) },
                        onCounterBid = { bid, price -> viewModel.counterBid(bid, price, null) },
                        onCancel = { viewModel.cancelRide() }
                    )
                }

                RideRequestViewModel.RideStep.MATCHED,
                RideRequestViewModel.RideStep.DRIVER_EN_ROUTE,
                RideRequestViewModel.RideStep.RIDE_IN_PROGRESS -> {
                    RideStatusSheet(
                        riderFirstName = riderFirstName,
                        selectedBid = selectedBid,
                        rideTracking = rideTracking,
                        currentStep = currentStep,
                        onChatClick = {
                            rideTracking?.let { tracking ->
                                onNavigateToChat(
                                    tracking.rideRequestId,
                                    tracking.driver?.name ?: "Driver"
                                )
                            }
                        },
                        onCancelRide = { viewModel.cancelRide() }
                    )
                }

                RideRequestViewModel.RideStep.COMPLETED -> {
                    RideCompletedSheet(
                        selectedBid = selectedBid,
                        ratingSubmitted = ratingSubmitted,
                        onRateDriver = { showRating = true },
                        onViewReceipt = {
                            viewModel.loadReceipt()
                            showReceipt = true
                        },
                        onDone = {
                            viewModel.resetRide()
                            onBackClick()
                        }
                    )
                }
            }
        }

        // Rate-your-driver overlay (ride-complete → rate → POST /rides/{id}/rate)
        if (showRating) {
            val driverName = rideTracking?.driver?.name ?: selectedBid?.driverName ?: "your driver"
            com.eatfair.app.ui.rating.RateDriverScreen(
                driverName = driverName,
                driverPhoto = rideTracking?.driver?.photoUrl ?: selectedBid?.driverPhotoUrl,
                orderId = (rideTracking?.rideRequestId ?: selectedBid?.id ?: 0).toString(),
                onBackClick = { showRating = false },
                onSubmitRating = { rating, tags, comment, _ ->
                    // Tip is collected during the ride and posted on completion, so
                    // only the rating/tags/comment are submitted here.
                    viewModel.rateDriver(rating, tags, comment)
                    showRating = false
                }
            )
        }

        // Itemized receipt overlay
        if (showReceipt) {
            RideReceiptScreen(
                receipt = rideReceipt,
                isLoading = isLoadingReceipt,
                onClose = { showReceipt = false }
            )
        }
    }

    // Location Search Sheet - Pickup
    if (showPickupSearch) {
        RideLocationSearchSheet(
            title = "Pickup Location",
            onDismiss = { showPickupSearch = false },
            onLocationSelected = { address, city, state, zip, lat, lng ->
                viewModel.setPickupLocation(address, city, state, zip, lat, lng)
                showPickupSearch = false
            },
            onUseCurrentLocation = {
                // Use geocoded current GPS location
                viewModel.useCurrentLocationForPickup()
                showPickupSearch = false
            }
        )
    }

    // Location Search Sheet - Dropoff
    if (showDropoffSearch) {
        RideLocationSearchSheet(
            title = "Dropoff Location",
            onDismiss = { showDropoffSearch = false },
            onLocationSelected = { address, city, state, zip, lat, lng ->
                viewModel.setDropoffLocation(address, city, state, zip, lat, lng)
                showDropoffSearch = false
            },
            onUseCurrentLocation = null
        )
    }

    // Negotiate Sheet
    if (showNegotiateSheet) {
        PreRequestNegotiationSheet(
            estimatedFare = estimatedFare,
            platformFee = platformFee,
            onDismiss = { showNegotiateSheet = false },
            onRequestWithOffer = { offer ->
                viewModel.setSuggestedPrice(offer)
                showNegotiateSheet = false
            }
        )
    }

    // Error Dialog
    if (showError) {
        AlertDialog(
            onDismissRequest = { viewModel.dismissError() },
            title = { Text(messageTitle) },
            text = { Text(errorMessage ?: "An error occurred") },
            confirmButton = {
                TextButton(onClick = { viewModel.dismissError() }) {
                    Text("OK")
                }
            }
        )
    }
}

/**
 * Ride Bottom Sheet - Matches iOS RideBottomSheet exactly
 */
@Composable
fun RideBottomSheet(
    viewModel: RideRequestViewModel,
    pickupLocation: com.eatfair.shared.model.rideshare.RideLocation?,
    dropoffLocation: com.eatfair.shared.model.rideshare.RideLocation?,
    estimatedFare: Double,
    suggestedPrice: Double?,
    platformFee: Double,
    selectedTip: Double,
    onTipSelected: (Double) -> Unit,
    onPickupClick: () -> Unit,
    onDropoffClick: () -> Unit,
    onRequestRide: () -> Unit,
    onMakeOffer: () -> Unit,
    onDismiss: () -> Unit,
    isLoading: Boolean
) {
    val canRequestRide = pickupLocation != null && dropoffLocation != null
    val fareLines by viewModel.fareLines.collectAsState()
    val regulatoryFee by viewModel.regulatoryFee.collectAsState()
    val estimateRideFare by viewModel.estimateRideFare.collectAsState()
    val estimateConnectionFee by viewModel.estimateConnectionFee.collectAsState()
    val currentFare = suggestedPrice ?: estimatedFare
    val totalAmount = currentFare + selectedTip
    val driverEarnings = (currentFare - AppConfig.Rideshare.calculatePlatformFee(currentFare)).coerceAtLeast(0.0) + selectedTip // fare minus flat fee, plus 100% of tip

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .shadow(elevation = 10.dp, shape = RoundedCornerShape(topStart = Lx.Radius.sheet, topEnd = Lx.Radius.sheet))
            .background(
                color = Lx.Surface,
                shape = RoundedCornerShape(topStart = Lx.Radius.sheet, topEnd = Lx.Radius.sheet)
            )
    ) {
        // Handle - Matches iOS
        Box(
            modifier = Modifier
                .padding(top = 10.dp)
                .align(Alignment.CenterHorizontally)
                .width(40.dp)
                .height(5.dp)
                .clip(RoundedCornerShape(3.dp))
                .background(Lx.TextSecondary.copy(alpha = 0.3f))
        )

        // Header - Matches iOS
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = onDismiss) {
                Icon(
                    imageVector = Icons.Default.Close,
                    contentDescription = "Close",
                    tint = Lx.TextSecondary
                )
            }

            Spacer(modifier = Modifier.weight(1f))

            Text(
                text = "Find a Driver",
                fontWeight = FontWeight.SemiBold,
                fontSize = Lx.FontSize.body
            )

            Spacer(modifier = Modifier.weight(1f))

            // Invisible placeholder for balance
            Icon(
                imageVector = Icons.Default.Close,
                contentDescription = null,
                tint = Color.Transparent
            )
        }

        HorizontalDivider(color = Lx.Hairline.copy(alpha = 0.5f))

        // Location Inputs - Matches iOS
        Column(modifier = Modifier.padding(horizontal = 16.dp)) {
            // Pickup Row
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(onClick = onPickupClick)
                    .padding(vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Pickup marker (green) - Matches iOS
                Box(
                    modifier = Modifier
                        .size(36.dp)
                        .clip(CircleShape)
                        .background(Lx.Pickup.copy(alpha = 0.15f)),
                    contentAlignment = Alignment.Center
                ) {
                    Box(
                        modifier = Modifier
                            .size(12.dp)
                            .clip(CircleShape)
                            .background(Lx.Pickup)
                    )
                }

                Spacer(modifier = Modifier.width(12.dp))

                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "PICKUP",
                        fontSize = Lx.FontSize.caption,
                        fontWeight = FontWeight.SemiBold,
                        color = Lx.Pickup
                    )
                    Text(
                        text = pickupLocation?.fullAddress ?: "Select pickup location",
                        fontSize = Lx.FontSize.footnote,
                        color = if (pickupLocation != null) Lx.Text else Lx.TextSecondary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }

                Icon(
                    imageVector = Icons.Default.ChevronRight,
                    contentDescription = null,
                    tint = Lx.TextSecondary,
                    modifier = Modifier.size(16.dp)
                )
            }

            // Connector Line - Matches iOS
            Row {
                Box(
                    modifier = Modifier
                        .padding(start = 17.dp)
                        .width(2.dp)
                        .height(24.dp)
                        .background(Lx.TextSecondary.copy(alpha = 0.3f))
                )
                Spacer(modifier = Modifier.weight(1f))
            }

            // Dropoff Row
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(onClick = onDropoffClick)
                    .padding(vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Green circle indicator - Matches iOS
                Box(
                    modifier = Modifier
                        .size(36.dp)
                        .clip(CircleShape)
                        .background(Lx.Dropoff.copy(alpha = 0.15f)),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = Icons.Default.LocationOn,
                        contentDescription = null,
                        tint = Lx.Dropoff,
                        modifier = Modifier.size(14.dp)
                    )
                }

                Spacer(modifier = Modifier.width(12.dp))

                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "DROPOFF",
                        fontSize = Lx.FontSize.caption,
                        fontWeight = FontWeight.SemiBold,
                        color = Lx.Dropoff
                    )
                    Text(
                        text = dropoffLocation?.fullAddress ?: "Select dropoff location",
                        fontSize = Lx.FontSize.footnote,
                        color = if (dropoffLocation != null) Lx.Text else Lx.TextSecondary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }

                Icon(
                    imageVector = Icons.Default.ChevronRight,
                    contentDescription = null,
                    tint = Lx.TextSecondary,
                    modifier = Modifier.size(16.dp)
                )
            }
        }

        HorizontalDivider(color = Lx.Hairline.copy(alpha = 0.5f))

        // Price Summary - Matches iOS World Class Fare Breakdown
        if (canRequestRide) {
            LazyColumn(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 280.dp)
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                // TNC-12: accessible vehicle request (matches iOS toggle + options)
                item {
                    AccessibilityRequestSection(viewModel = viewModel)
                }

                // Trip Estimate Header
                item {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column {
                            Text(
                                text = "SUGGESTED OFFER",
                                fontSize = Lx.FontSize.caption,
                                fontWeight = FontWeight.SemiBold,
                                color = Lx.TextSecondary
                            )
                            Row(
                                horizontalArrangement = Arrangement.spacedBy(12.dp)
                            ) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Icon(
                                        Icons.Default.Route,
                                        contentDescription = null,
                                        modifier = Modifier.size(14.dp),
                                        tint = Lx.TextSecondary
                                    )
                                    Text(
                                        text = " ${viewModel.formattedDistance}",
                                        fontSize = Lx.FontSize.footnote
                                    )
                                }
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Icon(
                                        Icons.Default.Schedule,
                                        contentDescription = null,
                                        modifier = Modifier.size(14.dp),
                                        tint = Lx.TextSecondary
                                    )
                                    Text(
                                        text = " ${viewModel.formattedDuration}",
                                        fontSize = Lx.FontSize.footnote
                                    )
                                }
                            }
                        }
                    }
                }

                item { HorizontalDivider() }

                // Fare Breakdown: server lines that add up to the ride fare, then the fees, then the total
                if (fareLines.isNotEmpty()) {
                    items(fareLines.size) { index ->
                        FareLineItem(fareLines[index].label, fareLines[index].amount)
                    }
                    item { HorizontalDivider() }
                    item { FareLineItem("Ride fare", estimateRideFare) }
                } else {
                    item {
                        FareLineItem("Base Fare", AppConfig.Rideshare.BASE_FARE)
                    }
                    item {
                        FareLineItem("Distance (${viewModel.formattedDistance})", viewModel.distanceFee)
                    }
                    item {
                        FareLineItem("Time (${viewModel.formattedDuration})", viewModel.timeFee)
                    }
                    item { HorizontalDivider() }
                }

                // Platform Fee with tier
                item {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Column {
                            Text("Connection Fee", fontSize = Lx.FontSize.footnote, color = Lx.TextSecondary)
                            Text(
                                text = viewModel.platformFeeTierDescription,
                                fontSize = Lx.FontSize.caption,
                                color = DollorTheme.Brand.orange
                            )
                        }
                        Text(
                            text = "$${String.format("%.2f", if (fareLines.isNotEmpty()) estimateConnectionFee else platformFee)}",
                            fontSize = Lx.FontSize.footnote,
                            fontWeight = FontWeight.Medium
                        )
                    }
                }
                if (regulatoryFee > 0.004) {
                    item { FareLineItem("CPUC Access for All fee", regulatoryFee) }
                }
                if (fareLines.isNotEmpty()) {
                    item { HorizontalDivider() }
                    item {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Text("Total", fontSize = Lx.FontSize.footnote, fontWeight = FontWeight.SemiBold)
                            Text(
                                text = "$${String.format("%.2f", estimateRideFare + estimateConnectionFee + regulatoryFee)}",
                                fontSize = Lx.FontSize.footnote,
                                fontWeight = FontWeight.SemiBold
                            )
                        }
                    }
                }

                item { HorizontalDivider() }

                // Driver-keeps-fare message (matches iOS)
                item {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(
                            imageVector = Icons.Default.CheckCircle,
                            contentDescription = null,
                            tint = DollorTheme.Brand.green,
                            modifier = Modifier.size(16.dp)
                        )
                        Text(
                            text = "Drivers keep the fare minus the flat connection fee",
                            fontSize = Lx.FontSize.footnote,
                            fontWeight = FontWeight.SemiBold,
                            color = DollorTheme.Brand.green
                        )
                    }
                }

                item { HorizontalDivider() }

                // Tip Options - Matches iOS
                item {
                    Column {
                        Text(
                            text = "Add Extra for Driver (Optional)",
                            fontSize = Lx.FontSize.footnote,
                            color = Lx.TextSecondary
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            listOf(0.0, 2.0, 3.0, 5.0).forEach { tipAmount ->
                                Box(
                                    modifier = Modifier
                                        .weight(1f)
                                        .clip(RoundedCornerShape(Lx.Radius.chip))
                                        .background(
                                            if (selectedTip == tipAmount)
                                                Lx.Orange
                                            else
                                                Lx.TextSecondary.copy(alpha = 0.1f)
                                        )
                                        .clickable { onTipSelected(tipAmount) }
                                        .padding(vertical = 10.dp),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Text(
                                        text = if (tipAmount == 0.0) "None" else "$${tipAmount.toInt()}",
                                        fontSize = Lx.FontSize.footnote,
                                        fontWeight = FontWeight.Medium,
                                        color = if (selectedTip == tipAmount) Color.White else Lx.Text
                                    )
                                }
                            }
                        }
                    }
                }

                item { HorizontalDivider() }

                // Your Offer Summary - Matches iOS
                item {
                    Column {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                text = "Your Offer",
                                fontSize = Lx.FontSize.body,
                                fontWeight = FontWeight.SemiBold
                            )
                            Text(
                                text = "$${String.format("%.2f", totalAmount)}",
                                fontSize = Lx.FontSize.title,
                                fontWeight = FontWeight.Bold,
                                color = Lx.Orange
                            )
                        }

                        Spacer(modifier = Modifier.height(4.dp))

                        // Driver receives info
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(
                                Icons.Default.PersonPin,
                                contentDescription = null,
                                tint = DollorTheme.Brand.green,
                                modifier = Modifier.size(14.dp)
                            )
                            Text(
                                text = " Driver receives: $${String.format("%.2f", driverEarnings)}",
                                fontSize = Lx.FontSize.caption,
                                color = DollorTheme.Brand.green
                            )
                            Text(
                                text = " (You pay driver directly)",
                                fontSize = Lx.FontSize.caption,
                                color = Lx.TextSecondary
                            )
                        }
                    }
                }

                item { HorizontalDivider() }

                // P2P Disclosure - Matches iOS
                item {
                    Column {
                        Text(
                            text = "PEER-TO-PEER RIDESHARE",
                            fontSize = Lx.FontSize.caption,
                            fontWeight = FontWeight.SemiBold,
                            color = Lx.TextSecondary
                        )
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(
                            text = "Dollor.ai connects riders with independent drivers. Drivers set their own rates and may accept, decline, or counter your offer. The connection fee is for using our matchmaking service. Transportation is provided directly by the driver, not Dollor.ai. By using this service, you agree to our Terms of Service.",
                            fontSize = Lx.FontSize.caption,
                            color = Lx.TextSecondary,
                            lineHeight = 14.sp
                        )
                        Spacer(modifier = Modifier.height(4.dp))
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(
                                Icons.Default.Info,
                                contentDescription = null,
                                tint = Lx.TextSecondary,
                                modifier = Modifier.size(12.dp)
                            )
                            Text(
                                text = " Connection fee: $${String.format("%.2f", platformFee)} (tiered ${AppConfig.Rideshare.feeRangeText}) • Driver sets final price",
                                fontSize = Lx.FontSize.caption,
                                color = Lx.TextSecondary
                            )
                        }
                    }
                }
            }

            // Action Buttons - Matches iOS
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                // Find Driver Button - Green with magnifying glass
                Button(
                    onClick = onRequestRide,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(52.dp),
                    enabled = !isLoading,
                    shape = RoundedCornerShape(Lx.Radius.button),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = DollorTheme.Brand.green
                    )
                ) {
                    if (isLoading) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(20.dp),
                            color = Color.White,
                            strokeWidth = 2.dp
                        )
                    } else {
                        Icon(
                            Icons.Default.Search,
                            contentDescription = null,
                            modifier = Modifier.size(18.dp)
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(
                            text = "Find Driver • Offer $${String.format("%.2f", currentFare)}",
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                }

                // Make Different Offer Button - Orange outlined
                OutlinedButton(
                    onClick = onMakeOffer,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(48.dp),
                    enabled = !isLoading,
                    shape = RoundedCornerShape(Lx.Radius.button),
                    colors = ButtonDefaults.outlinedButtonColors(
                        contentColor = DollorTheme.Brand.orange
                    ),
                    border = androidx.compose.foundation.BorderStroke(
                        1.dp,
                        DollorTheme.Brand.orange.copy(alpha = 0.3f)
                    )
                ) {
                    Icon(
                        Icons.Default.CurrencyExchange,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp)
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = "Make a Different Offer",
                        fontWeight = FontWeight.Medium
                    )
                }

                // Info text - Matches iOS
                Row(
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Icon(
                        Icons.Default.Info,
                        contentDescription = null,
                        tint = DollorTheme.Brand.green,
                        modifier = Modifier.size(12.dp)
                    )
                    Text(
                        text = " ${AppConfig.Rideshare.feeRangeText} tiered connection fee • Drivers are independent",
                        fontSize = Lx.FontSize.caption,
                        color = Lx.TextSecondary
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(16.dp))
    }
}

/**
 * Fare Line Item - Matches iOS FareLineItem
 */
@Composable
fun FareLineItem(label: String, amount: Double) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(text = label, fontSize = Lx.FontSize.footnote, color = Lx.TextSecondary)
        Text(
            text = (if (amount < 0) "-$" else "$") + String.format("%.2f", kotlin.math.abs(amount)),
            fontSize = Lx.FontSize.footnote
        )
    }
}

/**
 * Waiting for Bids Sheet
 */
@Composable
fun WaitingForBidsSheet(biddingEndsAtMillis: Long?, onCancel: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .shadow(elevation = 10.dp, shape = RoundedCornerShape(topStart = Lx.Radius.sheet, topEnd = Lx.Radius.sheet))
            .background(Lx.Surface, RoundedCornerShape(topStart = Lx.Radius.sheet, topEnd = Lx.Radius.sheet))
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        // Handle
        Box(
            modifier = Modifier
                .width(40.dp)
                .height(5.dp)
                .clip(RoundedCornerShape(3.dp))
                .background(Lx.TextSecondary.copy(alpha = 0.3f))
        )

        Spacer(modifier = Modifier.height(24.dp))

        // Status indicator
        Box(
            modifier = Modifier
                .size(50.dp)
                .clip(CircleShape)
                .background(Lx.Orange.copy(alpha = 0.1f)),
            contentAlignment = Alignment.Center
        ) {
            CircularProgressIndicator(
                modifier = Modifier.size(30.dp),
                color = Lx.Orange,
                strokeWidth = 3.dp
            )
        }

        Spacer(modifier = Modifier.height(16.dp))

        Text(
            text = "Finding available drivers...",
            fontSize = Lx.FontSize.body,
            fontWeight = FontWeight.SemiBold
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = "Drivers are reviewing your ride request.\nYou'll see bids soon!",
            fontSize = Lx.FontSize.footnote,
            color = Lx.TextSecondary,
            textAlign = TextAlign.Center
        )
        BiddingCountdown(biddingEndsAtMillis)

        Spacer(modifier = Modifier.height(24.dp))

        TextButton(onClick = onCancel) {
            Text("Cancel Request", color = Lx.Error)
        }
    }
}

/**
 * View Bids Sheet
 */
@Composable
fun ViewBidsSheet(
    bids: List<DriverBidForCustomer>,
    biddingEndsAtMillis: Long?,
    onAcceptBid: (DriverBidForCustomer) -> Unit,
    onRejectBid: (DriverBidForCustomer) -> Unit,
    onCounterBid: (DriverBidForCustomer, Double) -> Unit,
    onCancel: () -> Unit
) {
    var selectedBidForAction by remember { mutableStateOf<DriverBidForCustomer?>(null) }
    var showBidActionSheet by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .fillMaxHeight(0.6f)
            .shadow(elevation = 10.dp, shape = RoundedCornerShape(topStart = Lx.Radius.sheet, topEnd = Lx.Radius.sheet))
            .background(Lx.Surface, RoundedCornerShape(topStart = Lx.Radius.sheet, topEnd = Lx.Radius.sheet))
    ) {
        // Handle
        Box(
            modifier = Modifier
                .padding(top = 10.dp)
                .align(Alignment.CenterHorizontally)
                .width(40.dp)
                .height(5.dp)
                .clip(RoundedCornerShape(3.dp))
                .background(Lx.TextSecondary.copy(alpha = 0.3f))
        )

        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                text = "${bids.size} driver${if (bids.size != 1) "s" else ""} interested",
                fontSize = Lx.FontSize.body,
                fontWeight = FontWeight.SemiBold
            )
            BiddingCountdown(biddingEndsAtMillis)
        }

        LazyColumn(
            modifier = Modifier.weight(1f),
            contentPadding = PaddingValues(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            items(bids) { bid ->
                DriverBidCard(
                    bid = bid,
                    onAccept = { onAcceptBid(bid) },
                    onReject = { onRejectBid(bid) },
                    onClick = {
                        selectedBidForAction = bid
                        showBidActionSheet = true
                    }
                )
            }
        }

        TextButton(
            onClick = onCancel,
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
        ) {
            Text("Cancel Request", color = Lx.Error)
        }
    }

    // Bid Action Sheet
    if (showBidActionSheet && selectedBidForAction != null) {
        BidActionBottomSheet(
            bid = selectedBidForAction!!,
            onDismiss = {
                showBidActionSheet = false
                selectedBidForAction = null
            },
            onAccept = {
                onAcceptBid(selectedBidForAction!!)
                showBidActionSheet = false
            },
            onReject = {
                onRejectBid(selectedBidForAction!!)
                showBidActionSheet = false
            },
            onCounter = { price ->
                onCounterBid(selectedBidForAction!!, price)
                showBidActionSheet = false
            }
        )
    }
}

/**
 * Driver Bid Card
 */
@Composable
fun DriverBidCard(
    bid: DriverBidForCustomer,
    onAccept: () -> Unit,
    onReject: () -> Unit,
    onClick: () -> Unit
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = bid.status != "countered", onClick = onClick),
        shape = RoundedCornerShape(Lx.Radius.card),
        colors = CardDefaults.cardColors(containerColor = Lx.Surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Driver Avatar
                Box(
                    modifier = Modifier
                        .size(50.dp)
                        .clip(CircleShape)
                        .background(Lx.Orange.copy(alpha = 0.1f)),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = (bid.driverName ?: "D").take(1).uppercase(),
                        fontSize = Lx.FontSize.title,
                        fontWeight = FontWeight.Bold,
                        color = Lx.Orange
                    )
                }

                Spacer(modifier = Modifier.width(12.dp))

                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = bid.driverName ?: "Driver",
                        fontWeight = FontWeight.SemiBold,
                        fontSize = Lx.FontSize.callout
                    )
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            Icons.Default.Star,
                            contentDescription = null,
                            tint = Lx.Gold,
                            modifier = Modifier.size(14.dp)
                        )
                        Text(
                            text = " ${bid.formattedRating} • ${bid.formattedTrips} trips",
                            fontSize = Lx.FontSize.caption,
                            color = Lx.TextSecondary
                        )
                    }
                    val vehicle = listOfNotNull(bid.vehicleColor, bid.vehicleMake, bid.vehicleModel).joinToString(" ")
                    if (vehicle.isNotBlank() || !bid.vehiclePlate.isNullOrBlank()) {
                        Text(
                            text = listOfNotNull(vehicle.takeIf { it.isNotBlank() }, bid.vehiclePlate).joinToString(" · "),
                            fontSize = Lx.FontSize.caption,
                            color = Lx.TextSecondary
                        )
                    }
                }

                Column(horizontalAlignment = Alignment.End) {
                    Text(
                        text = "$${String.format("%.2f", bid.proposedPrice)}",
                        fontWeight = FontWeight.Bold,
                        fontSize = Lx.FontSize.body,
                        color = DollorTheme.Brand.green
                    )
                    if (bid.estimatedArrivalMinutes != null) {
                        Text(
                            text = "${bid.formattedArrival} away",
                            fontSize = Lx.FontSize.caption,
                            color = Lx.TextSecondary
                        )
                    }
                }
            }

            if (!bid.message.isNullOrBlank()) {
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = "\"${bid.message}\"",
                    fontSize = Lx.FontSize.footnote,
                    color = Lx.TextSecondary,
                    fontStyle = androidx.compose.ui.text.font.FontStyle.Italic
                )
            }

            Spacer(modifier = Modifier.height(12.dp))

            if (bid.status == "countered") {
                Text(
                    text = "Your counter: $${String.format("%.2f", bid.customerCounterPrice ?: 0.0)} · waiting for ${bid.driverName ?: "the driver"} to respond…",
                    fontSize = Lx.FontSize.footnote,
                    color = DollorTheme.Brand.orange
                )
                return@Column
            }

            // Quick action buttons
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Button(
                    onClick = onAccept,
                    modifier = Modifier.weight(1f),
                    colors = ButtonDefaults.buttonColors(containerColor = DollorTheme.Brand.green),
                    shape = RoundedCornerShape(Lx.Radius.chip)
                ) {
                    Icon(Icons.Default.Check, contentDescription = null, modifier = Modifier.size(16.dp))
                    Spacer(modifier = Modifier.width(4.dp))
                    Text("Accept", fontSize = Lx.FontSize.footnote)
                }

                OutlinedButton(
                    onClick = onClick,
                    modifier = Modifier.weight(1f),
                    shape = RoundedCornerShape(Lx.Radius.chip)
                ) {
                    Icon(Icons.Default.SwapHoriz, contentDescription = null, modifier = Modifier.size(16.dp))
                    Spacer(modifier = Modifier.width(4.dp))
                    Text("Counter", fontSize = Lx.FontSize.footnote)
                }
            }
        }
    }
}

/**
 * Ride Status Sheet - For active rides
 */
@Composable
fun RideStatusSheet(
    riderFirstName: String,
    selectedBid: DriverBidForCustomer?,
    rideTracking: com.eatfair.shared.model.rideshare.CustomerRideTracking?,
    currentStep: RideRequestViewModel.RideStep,
    onChatClick: () -> Unit,
    onCancelRide: () -> Unit
) {
    val context = LocalContext.current
    val driverPhone = rideTracking?.driver?.phone
    var showSos by remember { mutableStateOf(false) }

    val driverArrived = rideTracking?.hasDriverArrived == true &&
        currentStep != RideRequestViewModel.RideStep.RIDE_IN_PROGRESS
    val statusText = when {
        driverArrived -> "Driver has arrived!"
        currentStep == RideRequestViewModel.RideStep.MATCHED -> "Driver matched!"
        currentStep == RideRequestViewModel.RideStep.DRIVER_EN_ROUTE -> "Driver is on the way"
        currentStep == RideRequestViewModel.RideStep.RIDE_IN_PROGRESS -> "Ride in progress"
        else -> "Processing..."
    }

    val statusIcon = if (driverArrived) Icons.Default.CheckCircle else when (currentStep) {
        RideRequestViewModel.RideStep.MATCHED -> Icons.Default.CheckCircle
        RideRequestViewModel.RideStep.DRIVER_EN_ROUTE -> Icons.Default.DirectionsCar
        RideRequestViewModel.RideStep.RIDE_IN_PROGRESS -> Icons.Default.Navigation
        else -> Icons.Default.Schedule
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .shadow(elevation = 10.dp, shape = RoundedCornerShape(topStart = Lx.Radius.sheet, topEnd = Lx.Radius.sheet))
            .background(Lx.Surface, RoundedCornerShape(topStart = Lx.Radius.sheet, topEnd = Lx.Radius.sheet))
            .padding(16.dp)
    ) {
        // Handle
        Box(
            modifier = Modifier
                .align(Alignment.CenterHorizontally)
                .width(40.dp)
                .height(5.dp)
                .clip(RoundedCornerShape(3.dp))
                .background(Lx.TextSecondary.copy(alpha = 0.3f))
        )

        Spacer(modifier = Modifier.height(16.dp))

        // Status Row
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier
                    .size(50.dp)
                    .clip(CircleShape)
                    .background(Lx.Orange.copy(alpha = 0.1f)),
                contentAlignment = Alignment.Center
            ) {
                if (currentStep == RideRequestViewModel.RideStep.MATCHED && !driverArrived) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(24.dp),
                        strokeWidth = 2.dp,
                        color = Lx.Orange
                    )
                } else {
                    Icon(
                        imageVector = statusIcon,
                        contentDescription = null,
                        tint = Lx.Orange
                    )
                }
            }

            Spacer(modifier = Modifier.width(12.dp))

            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = statusText,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = Lx.FontSize.body
                )
                if (riderFirstName.isNotBlank()) {
                    Text(
                        text = "Hi $riderFirstName",
                        fontSize = Lx.FontSize.caption,
                        color = Lx.TextSecondary
                    )
                }
            }

            // Live tracking only: needs a current driver position (the server ETA comes from it).
            rideTracking?.etaMinutes?.takeIf { !driverArrived && rideTracking.driverLocation != null }?.let { eta ->
                Text(
                    text = "$eta min",
                    fontWeight = FontWeight.Bold,
                    fontSize = Lx.FontSize.callout,
                    color = Lx.Orange
                )
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Driver Info
        val driverName = rideTracking?.driver?.name ?: selectedBid?.driverName ?: "Driver"
        val vehicleInfo = rideTracking?.driver?.vehicleInfo ?: selectedBid?.vehicleInfo ?: ""

        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(containerColor = Lx.Surface2),
            shape = RoundedCornerShape(Lx.Radius.button)
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box(
                    modifier = Modifier
                        .size(50.dp)
                        .clip(CircleShape)
                        .background(Lx.TextSecondary.copy(alpha = 0.2f)),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = driverName.take(1).uppercase(),
                        fontSize = Lx.FontSize.title,
                        fontWeight = FontWeight.Bold,
                        color = Lx.TextSecondary
                    )
                }

                Spacer(modifier = Modifier.width(12.dp))

                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = driverName,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = vehicleInfo,
                        fontSize = Lx.FontSize.caption,
                        color = Lx.TextSecondary
                    )
                    val rating = rideTracking?.driver?.rating ?: selectedBid?.driverRating
                    val plate = rideTracking?.driver?.vehiclePlate ?: selectedBid?.vehiclePlate
                    if (rating != null || !plate.isNullOrBlank()) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(Lx.Spacing.s),
                            modifier = Modifier.padding(top = Lx.Spacing.xs)
                        ) {
                            if (rating != null) {
                                Icon(Icons.Default.Star, null, tint = Lx.Gold, modifier = Modifier.size(14.dp))
                                Text(String.format("%.1f", rating), fontSize = Lx.FontSize.caption, color = Lx.TextSecondary)
                            }
                            if (!plate.isNullOrBlank()) {
                                Text(
                                    text = plate,
                                    fontSize = Lx.FontSize.subheadline,
                                    fontWeight = FontWeight.Bold,
                                    color = Lx.Text,
                                    modifier = Modifier
                                        .clip(RoundedCornerShape(Lx.Radius.chip))
                                        .background(Lx.Gold.copy(alpha = 0.25f))
                                        .padding(horizontal = Lx.Spacing.s, vertical = Lx.Spacing.xs)
                                )
                            }
                        }
                    }
                }

                IconButton(onClick = onChatClick) {
                    Icon(
                        Icons.Default.Chat,
                        contentDescription = "Chat",
                        tint = Lx.Orange
                    )
                }

                IconButton(onClick = { showSos = true }) {
                    Icon(
                        Icons.Default.Sos,
                        contentDescription = "SOS",
                        tint = Lx.Error
                    )
                }

                // Only show the Call button when we actually have the driver's phone.
                if (!driverPhone.isNullOrBlank()) {
                    IconButton(onClick = {
                        val dialIntent = android.content.Intent(
                            android.content.Intent.ACTION_DIAL,
                            android.net.Uri.parse("tel:$driverPhone")
                        )
                        context.startActivity(dialIntent)
                    }) {
                        Icon(
                            Icons.Default.Phone,
                            contentDescription = "Call",
                            tint = Lx.Success
                        )
                    }
                }
            }
        }

        // Agreed price and route
        val agreedPrice = rideTracking?.finalPrice ?: selectedBid?.proposedPrice
        val pickupAddress = rideTracking?.pickup?.address
        val dropoffAddress = rideTracking?.dropoff?.address
        if (agreedPrice != null || !pickupAddress.isNullOrBlank()) {
            Spacer(modifier = Modifier.height(12.dp))
            if (agreedPrice != null) {
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("Agreed price", fontSize = Lx.FontSize.caption, color = Lx.TextSecondary)
                    Text(String.format("$%.2f", agreedPrice), fontWeight = FontWeight.Bold, color = Lx.Orange)
                }
            }
            if (!pickupAddress.isNullOrBlank() && !dropoffAddress.isNullOrBlank()) {
                Text(
                    text = "$pickupAddress \u2192 $dropoffAddress",
                    fontSize = Lx.FontSize.caption,
                    color = Lx.TextSecondary,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }

        if (showSos) {
            AlertDialog(
                onDismissRequest = { showSos = false },
                containerColor = Lx.Surface,
                title = { Text("Emergency SOS", color = Lx.Text) },
                text = {
                    Text(
                        "This will call emergency services (911). Only use in a real emergency.",
                        color = Lx.TextSecondary
                    )
                },
                confirmButton = {
                    TextButton(onClick = {
                        showSos = false
                        context.startActivity(
                            android.content.Intent(android.content.Intent.ACTION_DIAL, android.net.Uri.parse("tel:911"))
                        )
                    }) { Text("Call 911", color = Lx.Error, fontWeight = FontWeight.Bold) }
                },
                dismissButton = {
                    TextButton(onClick = { showSos = false }) { Text("Cancel", color = Lx.Orange) }
                }
            )
        }

        // Cancel button (only if not in progress)
        if (currentStep != RideRequestViewModel.RideStep.RIDE_IN_PROGRESS) {
            Spacer(modifier = Modifier.height(16.dp))
            var showCancelConfirm by remember { mutableStateOf(false) }
            TextButton(
                onClick = { showCancelConfirm = true },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("Cancel Ride", color = Lx.Error)
            }
            if (showCancelConfirm) {
                AlertDialog(
                    onDismissRequest = { showCancelConfirm = false },
                    containerColor = Lx.Surface,
                    title = { Text("Cancel Ride?", color = Lx.Text) },
                    text = {
                        Text(
                            "Your driver has already accepted this ride. Cancelling frees them for another rider.",
                            color = Lx.TextSecondary
                        )
                    },
                    confirmButton = {
                        TextButton(onClick = { showCancelConfirm = false; onCancelRide() }) {
                            Text("Cancel Ride", color = Lx.Error)
                        }
                    },
                    dismissButton = {
                        TextButton(onClick = { showCancelConfirm = false }) {
                            Text("Keep Ride", color = Lx.Orange)
                        }
                    }
                )
            }
        }

        Spacer(modifier = Modifier.height(16.dp))
    }
}

/**
 * Ride Completed Sheet
 */
@Composable
fun RideCompletedSheet(
    selectedBid: DriverBidForCustomer?,
    ratingSubmitted: Boolean = false,
    onRateDriver: () -> Unit = {},
    onViewReceipt: () -> Unit = {},
    onDone: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .shadow(elevation = 10.dp, shape = RoundedCornerShape(topStart = Lx.Radius.sheet, topEnd = Lx.Radius.sheet))
            .background(Lx.Surface, RoundedCornerShape(topStart = Lx.Radius.sheet, topEnd = Lx.Radius.sheet))
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Icon(
            Icons.Default.CheckCircle,
            contentDescription = null,
            modifier = Modifier.size(80.dp),
            tint = DollorTheme.Brand.green
        )

        Spacer(modifier = Modifier.height(16.dp))

        Text(
            text = "Ride Completed!",
            fontSize = Lx.FontSize.title,
            fontWeight = FontWeight.Bold
        )

        selectedBid?.let { bid ->
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "Fare: $${String.format("%.2f", bid.proposedPrice)} · see receipt for fees",
                fontSize = Lx.FontSize.body,
                color = Lx.TextSecondary
            )
        }

        Spacer(modifier = Modifier.height(24.dp))

        // Rate your driver (primary post-ride action), replaced by a confirmation once rated
        if (ratingSubmitted) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Lx.Spacing.s)
            ) {
                Icon(Icons.Default.CheckCircle, contentDescription = null, tint = Lx.Success)
                Text("Thanks for rating your driver", color = Lx.TextSecondary, fontSize = Lx.FontSize.subheadline)
            }
        } else {
            LxButton(
                text = "Rate your driver",
                onClick = onRateDriver,
                leading = { Icon(Icons.Default.Star, contentDescription = null, modifier = Modifier.size(20.dp)) }
            )
        }

        Spacer(modifier = Modifier.height(10.dp))

        LxButton(
            text = "View receipt",
            onClick = onViewReceipt,
            role = LxButtonRole.Secondary,
            leading = { Icon(Icons.Default.Receipt, contentDescription = null, modifier = Modifier.size(20.dp)) }
        )

        Spacer(modifier = Modifier.height(6.dp))

        TextButton(
            onClick = onDone,
            modifier = Modifier.fillMaxWidth()
        ) {
            Text("Done", color = Lx.TextSecondary)
        }
    }
}

/**
 * Location Search Sheet - Matches iOS RideLocationSearchView
 * Uses Android Geocoder for real address search (like iOS MKLocalSearch)
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RideLocationSearchSheet(
    title: String,
    onDismiss: () -> Unit,
    onLocationSelected: (String, String, String, String, Double, Double) -> Unit,
    onUseCurrentLocation: (() -> Unit)?
) {
    val context = LocalContext.current
    var searchText by remember { mutableStateOf("") }
    var searchResults by remember { mutableStateOf<List<AddressSearchResult>>(emptyList()) }
    var isSearching by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    // Search addresses when text changes (like iOS onChange)
    LaunchedEffect(searchText) {
        if (searchText.length > 2) {
            isSearching = true
            kotlinx.coroutines.delay(300) // Debounce
            searchResults = searchAddresses(context, searchText)
            isSearching = false
        } else {
            searchResults = emptyList()
        }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = Lx.Surface
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
        ) {
            Text(
                text = title,
                fontSize = Lx.FontSize.title,
                fontWeight = FontWeight.Bold
            )

            Spacer(modifier = Modifier.height(16.dp))

            // Search Bar - Matches iOS
            OutlinedTextField(
                value = searchText,
                onValueChange = { searchText = it },
                modifier = Modifier.fillMaxWidth(),
                placeholder = { Text("Search address...") },
                leadingIcon = {
                    Icon(Icons.Default.Search, contentDescription = null, tint = Lx.TextSecondary)
                },
                trailingIcon = {
                    if (searchText.isNotEmpty()) {
                        IconButton(onClick = { searchText = "" }) {
                            Icon(Icons.Default.Close, contentDescription = "Clear", tint = Lx.TextSecondary)
                        }
                    }
                },
                shape = RoundedCornerShape(Lx.Radius.button),
                singleLine = true
            )

            Spacer(modifier = Modifier.height(16.dp))

            // Current Location Option - Matches iOS
            onUseCurrentLocation?.let { onUse ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable(onClick = onUse)
                        .padding(vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Box(
                        modifier = Modifier
                            .size(44.dp)
                            .clip(CircleShape)
                            .background(Lx.Orange.copy(alpha = 0.1f)),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            Icons.Default.MyLocation,
                            contentDescription = null,
                            tint = Lx.Orange
                        )
                    }

                    Spacer(modifier = Modifier.width(12.dp))

                    Column {
                        Text(
                            text = "Use Current Location",
                            fontWeight = FontWeight.Medium
                        )
                        Text(
                            text = "Based on your GPS",
                            fontSize = Lx.FontSize.caption,
                            color = Lx.TextSecondary
                        )
                    }

                    Spacer(modifier = Modifier.weight(1f))

                    Icon(
                        Icons.Default.ChevronRight,
                        contentDescription = null,
                        tint = Lx.TextSecondary,
                        modifier = Modifier.size(16.dp)
                    )
                }

                HorizontalDivider()
            }

            // Search Results - Matches iOS ScrollView with LazyVStack
            if (isSearching) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(24.dp),
                    contentAlignment = Alignment.Center
                ) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(24.dp),
                        strokeWidth = 2.dp
                    )
                }
            } else {
                LazyColumn(
                    modifier = Modifier.heightIn(max = 300.dp)
                ) {
                    items(searchResults) { result ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable {
                                    onLocationSelected(
                                        result.street,
                                        result.city,
                                        result.state,
                                        result.zip,
                                        result.lat,
                                        result.lng
                                    )
                                }
                                .padding(vertical = 12.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(
                                Icons.Default.LocationOn,
                                contentDescription = null,
                                tint = Lx.TextSecondary,
                                modifier = Modifier.size(24.dp)
                            )

                            Spacer(modifier = Modifier.width(12.dp))

                            Column {
                                Text(
                                    text = result.name,
                                    fontWeight = FontWeight.Medium
                                )
                                Text(
                                    text = result.fullAddress,
                                    fontSize = Lx.FontSize.caption,
                                    color = Lx.TextSecondary,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }
                        }
                        HorizontalDivider(modifier = Modifier.padding(start = 36.dp))
                    }
                }
            }

            // Empty state when no results
            if (searchText.length > 2 && searchResults.isEmpty() && !isSearching) {
                Text(
                    text = "No addresses found",
                    color = Lx.TextSecondary,
                    modifier = Modifier.padding(16.dp)
                )
            }

            Spacer(modifier = Modifier.height(32.dp))
        }
    }
}

/**
 * Address search result - Matches iOS SearchResult
 */
data class AddressSearchResult(
    val name: String,
    val street: String,
    val city: String,
    val state: String,
    val zip: String,
    val lat: Double,
    val lng: Double
) {
    val fullAddress: String
        get() = listOfNotNull(street, city, state).joinToString(", ")
}

/**
 * Search addresses using Android Geocoder - Matches iOS MKLocalSearch
 */
private suspend fun searchAddresses(context: android.content.Context, query: String): List<AddressSearchResult> {
    return kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
        try {
            val geocoder = android.location.Geocoder(context, java.util.Locale.getDefault())
            val addresses = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                kotlinx.coroutines.suspendCancellableCoroutine { cont ->
                    geocoder.getFromLocationName(query, 5) { list ->
                        cont.resume(list) {}
                    }
                }
            } else {
                @Suppress("DEPRECATION")
                geocoder.getFromLocationName(query, 5)
            }

            addresses?.mapNotNull { address ->
                val street = listOfNotNull(
                    address.subThoroughfare,
                    address.thoroughfare
                ).joinToString(" ").ifEmpty {
                    address.getAddressLine(0)?.split(",")?.firstOrNull()?.trim() ?: return@mapNotNull null
                }

                AddressSearchResult(
                    name = address.featureName ?: street,
                    street = street,
                    city = address.locality ?: address.subLocality ?: "",
                    state = address.adminArea ?: "",
                    zip = address.postalCode ?: "",
                    lat = address.latitude,
                    lng = address.longitude
                )
            } ?: emptyList()
        } catch (e: Exception) {
            emptyList()
        }
    }
}

/**
 * Pre-Request Negotiation Sheet - Matches iOS PreRequestNegotiationSheet
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PreRequestNegotiationSheet(
    estimatedFare: Double,
    platformFee: Double,
    onDismiss: () -> Unit,
    onRequestWithOffer: (Double) -> Unit
) {
    var customOffer by remember { mutableStateOf("") }
    var selectedQuickOffer by remember { mutableStateOf<Double?>(null) }

    val minFare = AppConfig.Rideshare.MINIMUM_FARE
    val quickOfferOptions = listOf(
        maxOf(minFare, estimatedFare * 0.6),
        maxOf(minFare, estimatedFare * 0.7),
        maxOf(minFare, estimatedFare * 0.8),
        maxOf(minFare, estimatedFare * 0.9)
    )

    val currentOffer = selectedQuickOffer ?: customOffer.toDoubleOrNull()

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = Lx.Surface
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            // Header - Matches iOS
            Box(
                modifier = Modifier
                    .size(80.dp)
                    .clip(CircleShape)
                    .background(DollorTheme.Brand.orange.copy(alpha = 0.15f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    Icons.Default.CurrencyExchange,
                    contentDescription = null,
                    modifier = Modifier.size(36.dp),
                    tint = DollorTheme.Brand.orange
                )
            }

            Spacer(modifier = Modifier.height(16.dp))

            Text(
                text = "Make Your Offer",
                fontSize = Lx.FontSize.title,
                fontWeight = FontWeight.Bold
            )

            Text(
                text = "Independent drivers can accept, decline, or counter",
                fontSize = Lx.FontSize.footnote,
                color = Lx.TextSecondary
            )

            Spacer(modifier = Modifier.height(24.dp))

            // Suggested vs Your Offer comparison
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .clip(RoundedCornerShape(Lx.Radius.button))
                        .background(Lx.TextSecondary.copy(alpha = 0.1f))
                        .padding(16.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text("Suggested", fontSize = Lx.FontSize.caption, color = Lx.TextSecondary)
                    Text(
                        "$${String.format("%.2f", estimatedFare)}",
                        fontSize = Lx.FontSize.title,
                        fontWeight = FontWeight.SemiBold,
                        color = Lx.TextSecondary
                    )
                }

                Column(
                    modifier = Modifier
                        .weight(1f)
                        .clip(RoundedCornerShape(Lx.Radius.button))
                        .background(DollorTheme.Brand.orange.copy(alpha = 0.1f))
                        .padding(16.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text("Your Offer", fontSize = Lx.FontSize.caption, color = DollorTheme.Brand.orange)
                    Text(
                        if (currentOffer != null) "$${String.format("%.2f", currentOffer)}" else "--",
                        fontSize = Lx.FontSize.title,
                        fontWeight = FontWeight.Bold,
                        color = DollorTheme.Brand.orange
                    )
                }
            }

            Spacer(modifier = Modifier.height(24.dp))

            // Quick Offers
            Text(
                text = "Quick Offers",
                modifier = Modifier.align(Alignment.Start),
                fontWeight = FontWeight.Medium
            )

            Spacer(modifier = Modifier.height(8.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                quickOfferOptions.forEach { amount ->
                    val savings = estimatedFare - amount
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .clip(RoundedCornerShape(Lx.Radius.button))
                            .background(
                                if (selectedQuickOffer == amount)
                                    DollorTheme.Brand.orange
                                else
                                    Lx.TextSecondary.copy(alpha = 0.1f)
                            )
                            .clickable {
                                selectedQuickOffer = amount
                                customOffer = ""
                            }
                            .padding(vertical = 12.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(
                                "$${String.format("%.2f", amount)}",
                                fontWeight = FontWeight.SemiBold,
                                color = if (selectedQuickOffer == amount) Color.White else Lx.Text
                            )
                            if (savings > 0) {
                                Text(
                                    "Save $${String.format("%.2f", savings)}",
                                    fontSize = Lx.FontSize.caption,
                                    color = if (selectedQuickOffer == amount) Color.White.copy(alpha = 0.8f) else DollorTheme.Brand.green
                                )
                            }
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Custom Amount
            Text(
                text = "Or enter custom amount",
                modifier = Modifier.align(Alignment.Start),
                fontWeight = FontWeight.Medium
            )

            Spacer(modifier = Modifier.height(8.dp))

            OutlinedTextField(
                value = customOffer,
                onValueChange = {
                    customOffer = it
                    selectedQuickOffer = null
                },
                modifier = Modifier.fillMaxWidth(),
                placeholder = { Text("0.00") },
                prefix = { Text("$", fontSize = Lx.FontSize.body) },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                singleLine = true,
                shape = RoundedCornerShape(Lx.Radius.button)
            )

            Text(
                text = "Minimum fare: $${String.format("%.2f", minFare)}",
                modifier = Modifier
                    .align(Alignment.Start)
                    .padding(top = 4.dp),
                fontSize = Lx.FontSize.caption,
                color = Lx.TextSecondary
            )

            Spacer(modifier = Modifier.height(24.dp))

            // Submit Button
            Button(
                onClick = { currentOffer?.let { onRequestWithOffer(it) } },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(52.dp),
                enabled = currentOffer != null && currentOffer >= minFare,
                shape = RoundedCornerShape(Lx.Radius.button),
                colors = ButtonDefaults.buttonColors(containerColor = DollorTheme.Brand.orange)
            ) {
                Icon(Icons.Default.Send, contentDescription = null)
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = if (currentOffer != null) "Request with $${String.format("%.2f", currentOffer)} Offer" else "Enter an Amount",
                    fontWeight = FontWeight.SemiBold
                )
            }

            Spacer(modifier = Modifier.height(32.dp))
        }
    }
}

/**
 * Bid Action Bottom Sheet
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BidActionBottomSheet(
    bid: DriverBidForCustomer,
    onDismiss: () -> Unit,
    onAccept: () -> Unit,
    onReject: () -> Unit,
    onCounter: (Double) -> Unit
) {
    var counterPrice by remember { mutableStateOf(bid.proposedPrice.toString()) }
    var showCounter by remember { mutableStateOf(false) }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = Lx.Surface
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
        ) {
            Text(
                text = "Respond to ${bid.driverName ?: "Driver"}'s Offer",
                fontWeight = FontWeight.Bold,
                fontSize = Lx.FontSize.title
            )

            Spacer(modifier = Modifier.height(16.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text("Driver's Offer", color = Lx.TextSecondary)
                Text(
                    "$${String.format("%.2f", bid.proposedPrice)}",
                    fontWeight = FontWeight.Bold,
                    color = DollorTheme.Brand.green
                )
            }

            Spacer(modifier = Modifier.height(24.dp))

            if (!showCounter) {
                Button(
                    onClick = onAccept,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(52.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = DollorTheme.Brand.green),
                    shape = RoundedCornerShape(Lx.Radius.button)
                ) {
                    Icon(Icons.Default.Check, contentDescription = null)
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Accept Offer", fontWeight = FontWeight.SemiBold)
                }

                Spacer(modifier = Modifier.height(12.dp))

                OutlinedButton(
                    onClick = { showCounter = true },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(52.dp),
                    shape = RoundedCornerShape(Lx.Radius.button)
                ) {
                    Icon(Icons.Default.SwapHoriz, contentDescription = null)
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Counter Offer")
                }

                Spacer(modifier = Modifier.height(12.dp))

                TextButton(
                    onClick = onReject,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("Decline", color = Lx.Error)
                }
            } else {
                OutlinedTextField(
                    value = counterPrice,
                    onValueChange = { counterPrice = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Your Counter Price") },
                    prefix = { Text("$") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    singleLine = true
                )

                Spacer(modifier = Modifier.height(16.dp))

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    OutlinedButton(
                        onClick = { showCounter = false },
                        modifier = Modifier.weight(1f)
                    ) {
                        Text("Cancel")
                    }
                    Button(
                        onClick = { counterPrice.toDoubleOrNull()?.let { onCounter(it) } },
                        modifier = Modifier.weight(1f),
                        colors = ButtonDefaults.buttonColors(containerColor = Lx.Orange)
                    ) {
                        Text("Send Counter")
                    }
                }
            }

            Spacer(modifier = Modifier.height(32.dp))
        }
    }
}

@androidx.compose.runtime.Composable
private fun rememberDarkMapStyle(): MapStyleOptions {
    val context = LocalContext.current
    return androidx.compose.runtime.remember { MapStyleOptions.loadRawResourceStyle(context, R.raw.map_dark) }
}

@Composable
private fun AccessibilityRequestSection(viewModel: RideRequestViewModel) {
    val requested by viewModel.accessibilityRequested.collectAsState()
    val selected by viewModel.accessibilityOptions.collectAsState()
    val notes by viewModel.accessibilityNotes.collectAsState()
    val optionLabels = listOf(
        "wheelchair" to "Wheelchair accessible vehicle",
        "service_animal" to "Service animal",
        "mobility_storage" to "Mobility aid storage",
        "audio_visual" to "Audio/visual assistance"
    )

    Column(modifier = Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = Icons.Default.Accessible,
                contentDescription = null,
                tint = Lx.Orange,
                modifier = Modifier.size(20.dp)
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text(
                text = "I need an accessible vehicle",
                fontSize = Lx.FontSize.footnote,
                fontWeight = FontWeight.Medium,
                color = Lx.Text,
                modifier = Modifier.weight(1f)
            )
            Switch(
                checked = requested,
                onCheckedChange = { viewModel.setAccessibilityRequested(it) },
                colors = SwitchDefaults.colors(
                    checkedThumbColor = Lx.Text,
                    checkedTrackColor = Lx.Orange,
                    uncheckedThumbColor = Lx.TextSecondary,
                    uncheckedTrackColor = Lx.Surface2,
                    uncheckedBorderColor = Lx.Hairline
                )
            )
        }
        if (requested) {
            Text("Select your needs:", fontSize = Lx.FontSize.caption, color = Lx.TextSecondary)
            optionLabels.forEach { (key, label) ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { viewModel.toggleAccessibilityOption(key) },
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Checkbox(
                        checked = key in selected,
                        onCheckedChange = { viewModel.toggleAccessibilityOption(key) },
                        colors = CheckboxDefaults.colors(checkedColor = Lx.Orange)
                    )
                    Text(label, fontSize = Lx.FontSize.footnote, color = Lx.Text)
                }
            }
            OutlinedTextField(
                value = notes,
                onValueChange = { viewModel.setAccessibilityNotes(it) },
                placeholder = { Text("Additional accessibility notes (optional)", fontSize = Lx.FontSize.footnote) },
                modifier = Modifier.fillMaxWidth(),
                maxLines = 3,
                colors = OutlinedTextFieldDefaults.colors(
                    focusedTextColor = Lx.Text,
                    unfocusedTextColor = Lx.Text,
                    focusedBorderColor = Lx.Orange,
                    unfocusedBorderColor = Lx.Hairline
                )
            )
        }
    }
}

/** "Bidding closes in m:ss" — ticks every second; hidden when the expiry is unknown. */
@Composable
fun BiddingCountdown(endsAtMillis: Long?) {
    if (endsAtMillis == null) return
    var remaining by remember(endsAtMillis) { mutableStateOf(endsAtMillis - System.currentTimeMillis()) }
    LaunchedEffect(endsAtMillis) {
        while (true) {
            remaining = endsAtMillis - System.currentTimeMillis()
            kotlinx.coroutines.delay(1_000)
        }
    }
    val text = if (remaining > 0) {
        val total = (remaining / 1000).toInt()
        "Bidding closes in %d:%02d".format(total / 60, total % 60)
    } else {
        "Bidding closed"
    }
    Text(
        text = text,
        fontSize = Lx.FontSize.caption,
        fontWeight = FontWeight.SemiBold,
        color = if (remaining in 1..59_999) Lx.Error else Lx.Orange,
        modifier = Modifier.padding(top = Lx.Spacing.s)
    )
}
