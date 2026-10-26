package com.eatfair.app.ui.payment

import com.eatfair.shared.ui.Lx
import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.eatfair.app.BuildConfig
import com.eatfair.app.data.CustomerRideshareApiService
import com.eatfair.app.data.SavedCard
import com.eatfair.app.ui.theme.BrandGreen
import com.stripe.android.PaymentConfiguration
import com.stripe.android.paymentsheet.PaymentSheet
import com.stripe.android.paymentsheet.PaymentSheetResult
import com.stripe.android.paymentsheet.rememberPaymentSheet
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * Saved cards from GET /api/customers/{id}/cards. Adding a card confirms a Stripe
 * SetupIntent in PaymentSheet (nothing is charged), then the list is refreshed —
 * the same SetupIntent flow iOS PaymentMethodsView uses.
 */
class PaymentMethodsViewModel : ViewModel() {
    data class UiState(
        val isLoading: Boolean = true,
        val cards: List<SavedCard> = emptyList(),
        val busy: Boolean = false,
        val setupClientSecret: String? = null,
        val message: String? = null
    )

    private val _state = MutableStateFlow(UiState())
    val state: StateFlow<UiState> = _state.asStateFlow()

    init {
        refresh()
    }

    fun refresh(selectNewestAsDefaultIfFirst: Boolean = false) {
        viewModelScope.launch {
            val before = _state.value.cards.size
            CustomerRideshareApiService.getSavedCards()
                .onSuccess { cards ->
                    _state.update { it.copy(isLoading = false, cards = cards) }
                    if (selectNewestAsDefaultIfFirst && before == 0 && cards.isNotEmpty() && cards.none { it.isDefault }) {
                        setDefault(cards.last())
                    }
                }
                .onFailure { e -> _state.update { it.copy(isLoading = false, message = e.message) } }
        }
    }

    fun startAddCard(onKey: (String) -> Unit) {
        viewModelScope.launch {
            _state.update { it.copy(busy = true) }
            CustomerRideshareApiService.createSetupIntent()
                .onSuccess { setup ->
                    onKey(setup.publishableKey?.takeIf { it.isNotBlank() } ?: BuildConfig.STRIPE_PUBLISHABLE_KEY)
                    _state.update { it.copy(busy = false, setupClientSecret = setup.clientSecret) }
                }
                .onFailure { e -> _state.update { it.copy(busy = false, message = e.message) } }
        }
    }

    fun onSheetResult(result: PaymentSheetResult) {
        _state.update { it.copy(setupClientSecret = null) }
        when (result) {
            is PaymentSheetResult.Completed -> {
                _state.update { it.copy(message = "Card saved") }
                refresh(selectNewestAsDefaultIfFirst = true)
            }
            is PaymentSheetResult.Failed -> _state.update { it.copy(message = result.error.localizedMessage) }
            is PaymentSheetResult.Canceled -> Unit
        }
    }

    fun setDefault(card: SavedCard) = mutate("Default card updated") { CustomerRideshareApiService.setDefaultCard(card.id) }

    fun delete(card: SavedCard) = mutate("Card removed") { CustomerRideshareApiService.deleteCard(card.id) }

    private fun mutate(success: String, call: suspend () -> Result<Unit>) {
        viewModelScope.launch {
            _state.update { it.copy(busy = true) }
            call()
                .onSuccess { _state.update { it.copy(busy = false, message = success) }; refresh() }
                .onFailure { e -> _state.update { it.copy(busy = false, message = e.message) } }
        }
    }

    fun clearMessage() = _state.update { it.copy(message = null) }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PaymentMethodsScreen(
    onBackClick: () -> Unit,
    viewModel: PaymentMethodsViewModel = viewModel()
) {
    val context = LocalContext.current
    val state by viewModel.state.collectAsState()
    var pendingDelete by remember { mutableStateOf<SavedCard?>(null) }
    val paymentSheet = rememberPaymentSheet(viewModel::onSheetResult)

    LaunchedEffect(state.message) {
        state.message?.let {
            Toast.makeText(context, it, Toast.LENGTH_SHORT).show()
            viewModel.clearMessage()
        }
    }
    LaunchedEffect(state.setupClientSecret) {
        state.setupClientSecret?.let { secret ->
            paymentSheet.presentWithSetupIntent(
                secret,
                PaymentSheet.Configuration(merchantDisplayName = "Dollor.ai")
            )
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Payment Methods", fontWeight = FontWeight.Bold) },
                navigationIcon = {
                    IconButton(onClick = onBackClick) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") }
                }
            )
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding).background(Lx.Surface2),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item {
                Card(
                    modifier = Modifier.fillMaxWidth().clickable(enabled = !state.busy) {
                        viewModel.startAddCard { key -> PaymentConfiguration.init(context, key) }
                    },
                    shape = RoundedCornerShape(Lx.Radius.card),
                    colors = CardDefaults.cardColors(containerColor = Lx.Surface)
                ) {
                    Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.Add, null, tint = BrandGreen)
                        Spacer(Modifier.width(12.dp))
                        Text("Add payment method", fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                        if (state.busy) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = BrandGreen)
                    }
                }
            }
            item {
                Text(
                    "Cards are stored securely by Stripe. Dollor.ai never sees your full card number.",
                    color = Lx.TextSecondary,
                    fontSize = Lx.FontSize.caption
                )
            }
            when {
                state.isLoading -> item {
                    Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(color = BrandGreen)
                    }
                }
                state.cards.isEmpty() -> item {
                    Text(
                        "No saved cards yet. Add a card to request rides.",
                        color = Lx.TextSecondary,
                        modifier = Modifier.padding(vertical = 24.dp)
                    )
                }
                else -> items(state.cards, key = { it.id }) { card ->
                    CardRow(
                        card = card,
                        onMakeDefault = { viewModel.setDefault(card) },
                        onDelete = { pendingDelete = card }
                    )
                }
            }
        }
    }

    pendingDelete?.let { card ->
        AlertDialog(
            onDismissRequest = { pendingDelete = null },
            title = { Text("Remove card?") },
            text = { Text("${brandName(card.brand)} ending in ${card.last4} will be removed from your account.") },
            confirmButton = {
                TextButton(onClick = { viewModel.delete(card); pendingDelete = null }) {
                    Text("Remove", color = Lx.Error)
                }
            },
            dismissButton = { TextButton(onClick = { pendingDelete = null }) { Text("Cancel") } }
        )
    }
}

private fun brandName(brand: String?): String =
    brand?.replaceFirstChar { it.uppercase() }?.replace("Amex", "American Express") ?: "Card"

@Composable
private fun CardRow(card: SavedCard, onMakeDefault: () -> Unit, onDelete: () -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(Lx.Radius.card),
        colors = CardDefaults.cardColors(containerColor = Lx.Surface)
    ) {
        Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Default.CreditCard, null, tint = Lx.TextSecondary)
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text("${brandName(card.brand)} •••• ${card.last4 ?: ""}", fontWeight = FontWeight.SemiBold)
                val exp = if (card.expMonth != null && card.expYear != null)
                    "Expires ${String.format("%02d", card.expMonth)}/${card.expYear % 100}" else ""
                Text(exp, color = Lx.TextSecondary, fontSize = Lx.FontSize.footnote)
                if (card.isDefault) {
                    Text("Default", color = BrandGreen, fontSize = Lx.FontSize.caption, fontWeight = FontWeight.SemiBold)
                } else {
                    TextButton(onClick = onMakeDefault, contentPadding = PaddingValues(0.dp)) { Text("Make default") }
                }
            }
            IconButton(onClick = onDelete) { Icon(Icons.Default.Delete, "Remove card", tint = Lx.TextSecondary) }
        }
    }
}
