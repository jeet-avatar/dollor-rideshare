package com.eatfair.driver.ui.earnings

import com.eatfair.shared.ui.Lx
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavHostController
import com.eatfair.driver.ui.theme.DollorDriverColors
import com.eatfair.shared.model.driver.DriverEarningsResponse
import kotlin.math.roundToInt

private val PERIOD_LABELS = listOf("Today" to "today", "This Week" to "week", "This Month" to "month")

private fun money(value: Double): String = "$" + String.format("%.2f", value)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EarningsScreen(
    navController: NavHostController,
    viewModel: EarningsViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val context = LocalContext.current

    LaunchedEffect(uiState.payoutMessage) {
        uiState.payoutMessage?.let {
            Toast.makeText(context, it, Toast.LENGTH_LONG).show()
            viewModel.clearPayoutMessage()
        }
    }

    val earnings = uiState.earnings

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(DollorDriverColors.Background),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // Header
        item {
            Text(
                text = "Earnings",
                style = MaterialTheme.typography.headlineMedium.copy(
                    fontWeight = FontWeight.Bold
                ),
                color = DollorDriverColors.Gray900
            )
        }

        // Period Selector
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                PERIOD_LABELS.forEach { (label, value) ->
                    FilterChip(
                        selected = uiState.selectedPeriod == value,
                        onClick = { viewModel.selectPeriod(value) },
                        label = { Text(label) },
                        colors = FilterChipDefaults.filterChipColors(
                            selectedContainerColor = DollorDriverColors.Blue,
                            selectedLabelColor = DollorDriverColors.White
                        )
                    )
                }
            }
        }

        if (uiState.isLoading && earnings == null) {
            item {
                Box(modifier = Modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = DollorDriverColors.Blue)
                }
            }
        } else if (uiState.error != null && earnings == null) {
            item {
                ErrorCard(message = uiState.error!!, onRetry = { viewModel.loadEarnings() })
            }
        } else {
            val data = earnings ?: DriverEarningsResponse()
            earningsContent(
                data = data,
                isRequestingPayout = uiState.isRequestingPayout,
                onRequestPayout = { viewModel.requestPayout() }
            )
        }
    }
}

@Composable
private fun ErrorCard(message: String, onRetry: () -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(Lx.Radius.card),
        colors = CardDefaults.cardColors(containerColor = Lx.Surface)
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(20.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(message, color = DollorDriverColors.Gray600)
            Spacer(modifier = Modifier.height(12.dp))
            Button(
                onClick = onRetry,
                colors = ButtonDefaults.buttonColors(containerColor = DollorDriverColors.Blue)
            ) { Text("Retry") }
        }
    }
}

private fun androidx.compose.foundation.lazy.LazyListScope.earningsContent(
    data: DriverEarningsResponse,
    isRequestingPayout: Boolean,
    onRequestPayout: () -> Unit
) {
    // Total Earnings Card
    item {
        val deltaPct = if (data.previousPeriod > 0.0) {
            (((data.total - data.previousPeriod) / data.previousPeriod) * 100).roundToInt()
        } else null
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
                            colors = listOf(DollorDriverColors.Green, DollorDriverColors.GreenDark)
                        )
                    )
                    .padding(24.dp)
            ) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(
                        text = "Total Earnings",
                        style = MaterialTheme.typography.bodyLarge,
                        color = DollorDriverColors.White.copy(alpha = 0.8f)
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = money(data.total),
                        style = MaterialTheme.typography.displayMedium.copy(fontWeight = FontWeight.Bold),
                        color = DollorDriverColors.White
                    )
                    if (deltaPct != null) {
                        Spacer(modifier = Modifier.height(4.dp))
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(4.dp)
                        ) {
                            Icon(
                                imageVector = if (deltaPct >= 0) Icons.Default.TrendingUp else Icons.Default.TrendingDown,
                                contentDescription = null,
                                tint = DollorDriverColors.White,
                                modifier = Modifier.size(16.dp)
                            )
                            Text(
                                text = "${if (deltaPct >= 0) "+" else ""}$deltaPct% vs previous period",
                                style = MaterialTheme.typography.bodySmall,
                                color = DollorDriverColors.White.copy(alpha = 0.9f)
                            )
                        }
                    }
                }
            }
        }
    }

    // Stats Row
    item {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            EarningsStatCard(
                modifier = Modifier.weight(1f),
                label = "Rides",
                value = data.deliveries.toString(),
                icon = Icons.Default.DirectionsCar
            )
            EarningsStatCard(
                modifier = Modifier.weight(1f),
                label = "Hours",
                value = data.hoursOnline?.let { String.format("%.1f", it) } ?: "\u2014",
                icon = Icons.Default.AccessTime
            )
            EarningsStatCard(
                modifier = Modifier.weight(1f),
                label = "Tips",
                value = money(data.tips),
                icon = Icons.Default.Paid
            )
        }
    }

    // Earnings Breakdown
    item {
        Text(
            text = "Breakdown",
            style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold),
            color = DollorDriverColors.Gray900,
            modifier = Modifier.padding(top = 8.dp)
        )
    }

    item {
        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(Lx.Radius.card),
            colors = CardDefaults.cardColors(containerColor = Lx.Surface)
        ) {
            Column(modifier = Modifier.fillMaxWidth().padding(16.dp)) {
                EarningsBreakdownRow("Base Pay", money(data.basePay))
                HorizontalDivider(modifier = Modifier.padding(vertical = 12.dp))
                EarningsBreakdownRow("Tips", money(data.tips))
                HorizontalDivider(modifier = Modifier.padding(vertical = 12.dp))
                EarningsBreakdownRow("Bonuses", money(data.bonuses))
                HorizontalDivider(modifier = Modifier.padding(vertical = 12.dp))
                EarningsBreakdownRow("Total", money(data.total), isTotal = true)
            }
        }
    }

    // Available balance + Payout Button
    item {
        Text(
            text = "Available to pay out: ${data.availableBalance?.let { money(it) } ?: "\u2014"}",
            style = MaterialTheme.typography.bodyMedium,
            color = DollorDriverColors.Gray600
        )
    }

    item {
        Button(
            onClick = onRequestPayout,
            enabled = !isRequestingPayout,
            modifier = Modifier
                .fillMaxWidth()
                .height(56.dp),
            shape = RoundedCornerShape(Lx.Radius.card),
            colors = ButtonDefaults.buttonColors(containerColor = DollorDriverColors.Blue)
        ) {
            if (isRequestingPayout) {
                CircularProgressIndicator(
                    modifier = Modifier.size(20.dp),
                    color = DollorDriverColors.White,
                    strokeWidth = 2.dp
                )
            } else {
                Icon(
                    imageVector = Icons.Default.AccountBalance,
                    contentDescription = null,
                    modifier = Modifier.size(20.dp)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = "Request Payout",
                    style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold)
                )
            }
        }
    }

    item { Spacer(modifier = Modifier.height(80.dp)) }
}

@Composable
fun EarningsStatCard(
    modifier: Modifier = Modifier,
    label: String,
    value: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector
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
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = value,
                style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold),
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
fun EarningsBreakdownRow(
    label: String,
    value: String,
    isNegative: Boolean = false,
    isTotal: Boolean = false
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = label,
            style = if (isTotal) {
                MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold)
            } else {
                MaterialTheme.typography.bodyMedium
            },
            color = if (isTotal) DollorDriverColors.Gray900 else DollorDriverColors.Gray600
        )
        Text(
            text = value,
            style = if (isTotal) {
                MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold)
            } else {
                MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Medium)
            },
            color = when {
                isTotal -> DollorDriverColors.Green
                isNegative -> DollorDriverColors.Error
                else -> DollorDriverColors.Gray900
            }
        )
    }
}
