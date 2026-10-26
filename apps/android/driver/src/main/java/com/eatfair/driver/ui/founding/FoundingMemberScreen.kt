package com.eatfair.driver.ui.founding

import com.eatfair.shared.ui.Lx
import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.hilt.navigation.compose.hiltViewModel
import com.eatfair.driver.ui.theme.DollorDriverColors
import com.eatfair.shared.ui.UsStatePicker
import com.stripe.android.ApiResultCallback
import com.stripe.android.Stripe
import com.stripe.android.model.PaymentMethod
import com.stripe.android.view.CardInputWidget

private val Gold = Lx.Gold

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FoundingMemberScreen(
    onBackClick: () -> Unit,
    viewModel: FoundingViewModel = hiltViewModel()
) {
    val context = LocalContext.current
    val state by viewModel.uiState.collectAsState()
    var cardWidget by remember { mutableStateOf<CardInputWidget?>(null) }
    var confirm by remember { mutableStateOf(false) }

    LaunchedEffect(state.message) {
        state.message?.let { Toast.makeText(context, it, Toast.LENGTH_LONG).show(); viewModel.clearMessage() }
    }
    LaunchedEffect(state.error) {
        state.error?.let { Toast.makeText(context, it, Toast.LENGTH_LONG).show(); viewModel.clearError() }
    }

    fun payAndJoin() {
        val params = cardWidget?.paymentMethodCreateParams
        val key = state.publishableKey
        if (params == null) {
            viewModel.onTokenizeFailed("Enter a valid card")
            return
        }
        if (key.isNullOrBlank()) {
            viewModel.onTokenizeFailed("Payments are unavailable right now")
            return
        }
        viewModel.onTokenizing()
        Stripe(context, key).createPaymentMethod(params, callback = object : ApiResultCallback<PaymentMethod> {
            override fun onSuccess(result: PaymentMethod) = viewModel.join(result.id)
            override fun onError(e: Exception) = viewModel.onTokenizeFailed(e.localizedMessage)
        })
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Founding Driver", fontWeight = FontWeight.SemiBold) },
                navigationIcon = {
                    IconButton(onClick = onBackClick) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Lx.Surface)
            )
        }
    ) { padding ->
        if (state.isLoading) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            return@Scaffold
        }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(DollorDriverColors.Gray50)
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Box(
                Modifier.size(96.dp).clip(CircleShape).background(Gold.copy(alpha = 0.15f)),
                contentAlignment = Alignment.Center
            ) { Icon(Icons.Default.WorkspacePremium, null, tint = Gold, modifier = Modifier.size(52.dp)) }

            Spacer(Modifier.height(16.dp))
            Text("Become a Founding Driver", fontSize = Lx.FontSize.title, fontWeight = FontWeight.Bold, color = DollorDriverColors.Gray900, textAlign = TextAlign.Center)
            Spacer(Modifier.height(6.dp))
            Text(
                "A one-time $${"%.0f".format(state.deposit)} joins you as a Dollor.ai founding driver and locks your fees for life.",
                fontSize = Lx.FontSize.footnote,
                color = DollorDriverColors.Gray500,
                textAlign = TextAlign.Center
            )
            Spacer(Modifier.height(24.dp))

            if (state.isFounder) {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(Lx.Radius.card),
                    colors = CardDefaults.cardColors(containerColor = DollorDriverColors.Green.copy(alpha = 0.1f))
                ) {
                    Row(Modifier.padding(20.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.CheckCircle, null, tint = DollorDriverColors.Green, modifier = Modifier.size(28.dp))
                        Spacer(Modifier.width(12.dp))
                        Column {
                            Text("You're a Founding Driver", fontWeight = FontWeight.Bold, color = DollorDriverColors.Gray900)
                            Text(
                                "Your lifetime fee-lock is active" + (state.founderState?.let { " in $it." } ?: "."),
                                fontSize = Lx.FontSize.footnote,
                                color = DollorDriverColors.Gray500
                            )
                        }
                    }
                }
                return@Column
            }

            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(Lx.Radius.card),
                colors = CardDefaults.cardColors(containerColor = Lx.Surface)
            ) {
                Column(Modifier.padding(20.dp)) {
                    Text("Lifetime fee lock", fontWeight = FontWeight.Bold, fontSize = Lx.FontSize.callout, color = DollorDriverColors.Gray900)
                    Spacer(Modifier.height(12.dp))
                    Benefit(state.benefit ?: "Lock today's platform fee for life. Government fees still apply.")
                    Benefit("One-time $${"%.0f".format(state.deposit)}, non-refundable - no recurring charges")
                }
            }

            Spacer(Modifier.height(16.dp))
            UsStatePicker(selected = state.selectedState, onSelected = viewModel::selectState, modifier = Modifier.fillMaxWidth())
            state.slotsRemaining?.let {
                Spacer(Modifier.height(8.dp))
                Text("$it founding spots left in ${state.selectedState}", fontSize = Lx.FontSize.footnote, color = DollorDriverColors.Blue)
            }

            val canJoin = state.eligible && (state.slotsRemaining ?: 1) > 0
            if (canJoin && !state.isDemo) {
                Spacer(Modifier.height(16.dp))
                AndroidView(
                    factory = { ctx -> CardInputWidget(ctx).also { cardWidget = it } },
                    modifier = Modifier.fillMaxWidth().background(Lx.Surface, RoundedCornerShape(Lx.Radius.button)).padding(12.dp)
                )
            }

            Spacer(Modifier.height(16.dp))
            Button(
                onClick = { if (state.isDemo) viewModel.join(null) else confirm = true },
                enabled = canJoin && !state.isJoining,
                modifier = Modifier.fillMaxWidth().height(54.dp),
                shape = RoundedCornerShape(Lx.Radius.button),
                colors = ButtonDefaults.buttonColors(containerColor = DollorDriverColors.Blue)
            ) {
                if (state.isJoining) {
                    CircularProgressIndicator(Modifier.size(20.dp), color = DollorDriverColors.White, strokeWidth = 2.dp)
                    Spacer(Modifier.width(8.dp))
                }
                Text("Join for $${"%.0f".format(state.deposit)}", fontWeight = FontWeight.SemiBold)
            }

            if (!canJoin) {
                Spacer(Modifier.height(8.dp))
                Text(
                    text = when {
                        state.slotsRemaining == 0 -> "All founding spots in ${state.selectedState} have been claimed."
                        state.ridesTaken >= state.claimWindowRides ->
                            "The founding offer is only available within your first ${state.claimWindowRides} rides."
                        else -> "Founding membership isn't available for your account right now."
                    },
                    fontSize = Lx.FontSize.caption,
                    color = DollorDriverColors.Gray500,
                    textAlign = TextAlign.Center
                )
            }
        }
    }

    if (confirm) {
        AlertDialog(
            onDismissRequest = { confirm = false },
            title = { Text("Confirm founding payment") },
            text = { Text("Your card will be charged $${"%.0f".format(state.deposit)} once. This payment is non-refundable.") },
            confirmButton = { TextButton(onClick = { confirm = false; payAndJoin() }) { Text("Pay $${"%.0f".format(state.deposit)}") } },
            dismissButton = { TextButton(onClick = { confirm = false }) { Text("Cancel") } }
        )
    }
}

@Composable
private fun Benefit(text: String) {
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Default.CheckCircle, null, tint = DollorDriverColors.Green, modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(10.dp))
        Text(text, fontSize = Lx.FontSize.footnote, color = DollorDriverColors.Gray700)
    }
}
