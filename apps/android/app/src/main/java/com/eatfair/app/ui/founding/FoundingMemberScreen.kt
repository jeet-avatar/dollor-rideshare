package com.eatfair.app.ui.founding

import com.eatfair.shared.ui.Lx
import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
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
import androidx.hilt.navigation.compose.hiltViewModel

private val Brand = Lx.Orange
private val Gold = Lx.Gold

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FoundingMemberScreen(
    onBackClick: () -> Unit,
    viewModel: FoundingViewModel = hiltViewModel()
) {
    val context = LocalContext.current
    val state by viewModel.uiState.collectAsState()

    LaunchedEffect(state.message) {
        state.message?.let {
            Toast.makeText(context, it, Toast.LENGTH_LONG).show()
            viewModel.clearMessage()
        }
    }
    LaunchedEffect(state.error) {
        state.error?.let {
            Toast.makeText(context, it, Toast.LENGTH_LONG).show()
            viewModel.clearError()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Founding Member", fontWeight = FontWeight.SemiBold) },
                navigationIcon = {
                    IconButton(onClick = onBackClick) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                    }
                }
            )
        }
    ) { padding ->
        if (state.isLoading) {
            Box(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentAlignment = Alignment.Center
            ) { CircularProgressIndicator() }
            return@Scaffold
        }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Box(
                modifier = Modifier
                    .size(96.dp)
                    .clip(CircleShape)
                    .background(Gold.copy(alpha = 0.15f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    Icons.Default.WorkspacePremium,
                    contentDescription = null,
                    tint = Gold,
                    modifier = Modifier.size(52.dp)
                )
            }

            Spacer(Modifier.height(16.dp))
            Text(
                text = "Dollor Founding Member",
                fontSize = Lx.FontSize.title,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center
            )
            Spacer(Modifier.height(6.dp))
            Text(
                text = "Lock in your rates for life. Join the first members who power Dollor.",
                fontSize = Lx.FontSize.footnote,
                color = Lx.TextSecondary,
                textAlign = TextAlign.Center
            )

            Spacer(Modifier.height(24.dp))

            if (state.isFounder) {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(Lx.Radius.card),
                    colors = CardDefaults.cardColors(containerColor = Brand.copy(alpha = 0.08f))
                ) {
                    Row(
                        modifier = Modifier.padding(20.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(Icons.Default.CheckCircle, null, tint = Brand, modifier = Modifier.size(28.dp))
                        Spacer(Modifier.width(12.dp))
                        Column {
                            Text("You're a Founding Member", fontWeight = FontWeight.Bold)
                            Text(
                                "Your lifetime fee-lock is active" + (state.founderState?.let { " in $it." } ?: "."),
                                fontSize = Lx.FontSize.footnote,
                                color = Lx.TextSecondary
                            )
                        }
                    }
                }
            } else {
                BenefitsCard(state)

                Spacer(Modifier.height(16.dp))
                com.eatfair.shared.ui.UsStatePicker(
                    selected = state.selectedState,
                    onSelected = viewModel::selectState,
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(Modifier.height(8.dp))
                state.slotsRemaining?.let {
                    Text(
                        "$it founding spots left in ${state.selectedState}",
                        fontSize = Lx.FontSize.footnote,
                        color = Brand,
                        fontWeight = FontWeight.Medium
                    )
                }
                Spacer(Modifier.height(16.dp))

                val canJoin = state.eligible && (state.slotsRemaining ?: 1) > 0
                Button(
                    onClick = { viewModel.onJoinClicked() },
                    enabled = canJoin && !state.isJoining,
                    modifier = Modifier.fillMaxWidth().height(54.dp),
                    shape = RoundedCornerShape(Lx.Radius.button),
                    colors = ButtonDefaults.buttonColors(containerColor = Brand)
                ) {
                    if (state.isJoining) {
                        CircularProgressIndicator(modifier = Modifier.size(20.dp), color = Color.White, strokeWidth = 2.dp)
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
                        color = Lx.TextSecondary,
                        textAlign = TextAlign.Center
                    )
                }

                if (state.isDemo) {
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "Demo account - payment is bypassed.",
                        fontSize = Lx.FontSize.caption,
                        color = Lx.TextSecondary
                    )
                }
            }
        }
    }

    state.confirmCard?.let { card ->
        AlertDialog(
            onDismissRequest = viewModel::cancelCharge,
            title = { Text("Confirm founding payment") },
            text = {
                Text(
                    "Your ${card.brand?.replaceFirstChar { it.uppercase() } ?: "card"} ending in ${card.last4} will be charged " +
                        "$${"%.0f".format(state.deposit)} once. This payment is non-refundable."
                )
            },
            confirmButton = { TextButton(onClick = viewModel::confirmCharge) { Text("Pay $${"%.0f".format(state.deposit)}") } },
            dismissButton = { TextButton(onClick = viewModel::cancelCharge) { Text("Cancel") } }
        )
    }
}

@Composable
private fun BenefitsCard(state: FoundingViewModel.UiState) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(Lx.Radius.card),
        colors = CardDefaults.cardColors(containerColor = Lx.Surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
    ) {
        Column(modifier = Modifier.padding(20.dp)) {
            Text("Member Benefits", fontWeight = FontWeight.Bold, fontSize = Lx.FontSize.callout)
            Spacer(Modifier.height(12.dp))
            Benefit(state.benefit ?: "Lock today's platform fee for life. Government fees still apply.")
            Benefit("One-time $${"%.0f".format(state.deposit)}, non-refundable - no recurring charges")
        }
    }
}

@Composable
private fun Benefit(text: String) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(Icons.Default.CheckCircle, null, tint = Lx.Success, modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(10.dp))
        Text(text, fontSize = Lx.FontSize.footnote, color = Lx.TextSecondary)
    }
}
