package com.eatfair.app.ui.trips

import com.eatfair.shared.ui.Lx
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.eatfair.app.data.CustomerRideshareApiService
import com.eatfair.app.data.RideHistoryItem
import com.eatfair.app.data.RideReceipt
import com.eatfair.app.ui.rideshare.RideReceiptScreen
import com.eatfair.app.ui.theme.BrandGreen
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** Requests that expired or were cancelled before any driver matched aren't trips. */
private fun isRealTrip(t: RideHistoryItem): Boolean = t.status == "completed" || t.driverName != null

/** Trips tab: ride history with receipts (iOS OrderHistoryView parity). */
class TripsViewModel : ViewModel() {
    data class UiState(
        val isLoading: Boolean = true,
        val trips: List<RideHistoryItem> = emptyList(),
        val hasMore: Boolean = false,
        val error: String? = null,
        val receipt: RideReceipt? = null,
        val receiptOpen: Boolean = false,
        val receiptLoading: Boolean = false
    )

    private val _state = MutableStateFlow(UiState())
    val state: StateFlow<UiState> = _state.asStateFlow()

    init {
        refresh()
    }

    fun refresh() {
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true, error = null) }
            CustomerRideshareApiService.getRideHistory()
                .onSuccess { r -> _state.update { it.copy(isLoading = false, trips = r.rides.filter(::isRealTrip), hasMore = r.hasMore) } }
                .onFailure { e -> _state.update { it.copy(isLoading = false, error = e.message) } }
        }
    }

    fun loadMore() {
        val s = _state.value
        if (!s.hasMore || s.isLoading) return
        viewModelScope.launch {
            CustomerRideshareApiService.getRideHistory(offset = s.trips.size).onSuccess { r ->
                _state.update { it.copy(trips = it.trips + r.rides.filter(::isRealTrip), hasMore = r.hasMore) }
            }
        }
    }

    fun openReceipt(rideId: Int) {
        _state.update { it.copy(receiptOpen = true, receiptLoading = true, receipt = null) }
        viewModelScope.launch {
            val receipt = CustomerRideshareApiService.getRideReceipt(rideId).getOrNull()
            _state.update { it.copy(receiptLoading = false, receipt = receipt) }
        }
    }

    fun closeReceipt() {
        _state.update { it.copy(receiptOpen = false, receipt = null) }
    }
}

@Composable
fun TripsScreen(viewModel: TripsViewModel = viewModel()) {
    val state by viewModel.state.collectAsState()

    if (state.receiptOpen) {
        RideReceiptScreen(receipt = state.receipt, isLoading = state.receiptLoading, onClose = viewModel::closeReceipt)
        return
    }

    Column(modifier = Modifier.fillMaxSize().background(Lx.Surface2)) {
        Text(
            "Your Trips",
            fontSize = Lx.FontSize.title,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(start = 16.dp, top = 24.dp, bottom = 8.dp)
        )
        when {
            state.isLoading && state.trips.isEmpty() -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = BrandGreen)
            }
            state.error != null && state.trips.isEmpty() -> Column(
                Modifier.fillMaxSize(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
            ) {
                Text(state.error ?: "", color = Lx.TextSecondary)
                TextButton(onClick = viewModel::refresh) { Text("Try again") }
            }
            state.trips.isEmpty() -> Column(
                Modifier.fillMaxSize(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
            ) {
                Icon(Icons.Default.DirectionsCar, null, tint = Lx.Hairline, modifier = Modifier.size(56.dp))
                Text("No trips yet", fontWeight = FontWeight.SemiBold)
                Text("Your completed rides will appear here.", color = Lx.TextSecondary)
            }
            else -> LazyColumn(
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                items(state.trips, key = { it.id }) { trip ->
                    TripRow(trip) { viewModel.openReceipt(trip.id) }
                }
                if (state.hasMore) {
                    item {
                        LaunchedEffect(state.trips.size) { viewModel.loadMore() }
                        Box(Modifier.fillMaxWidth().padding(8.dp), contentAlignment = Alignment.Center) {
                            CircularProgressIndicator(modifier = Modifier.size(24.dp), color = BrandGreen)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun TripRow(trip: RideHistoryItem, onClick: () -> Unit) {
    val status = trip.status?.replace('_', ' ')?.replaceFirstChar { it.uppercase() } ?: ""
    val completed = trip.status == "completed"
    Card(
        modifier = Modifier.fillMaxWidth().clickable(enabled = completed, onClick = onClick),
        shape = RoundedCornerShape(Lx.Radius.button),
        colors = CardDefaults.cardColors(containerColor = Lx.Surface)
    ) {
        Row(modifier = Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(modifier = Modifier.weight(1f)) {
                Text(trip.dropoff ?: "Trip", fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text("From ${trip.pickup ?: "--"}", color = Lx.TextSecondary, fontSize = Lx.FontSize.footnote, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(
                    listOfNotNull(trip.date, trip.driverName, status.takeIf { !completed }).joinToString(" · "),
                    color = Lx.TextSecondary,
                    fontSize = Lx.FontSize.caption
                )
            }
            if (completed) {
                Text((trip.total ?: trip.fare)?.let { "$" + String.format("%.2f", it) } ?: "--", fontWeight = FontWeight.Bold)
            } else {
                Text(status, color = Lx.TextSecondary, fontSize = Lx.FontSize.footnote)
            }
        }
    }
}
