package com.eatfair.app.ui.rideshare

import com.eatfair.shared.ui.Lx
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Receipt
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.eatfair.app.data.RideReceipt

private val Brand = Lx.Orange

/**
 * Itemized ride receipt shown after a ride completes (parity with iOS).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RideReceiptScreen(
    receipt: RideReceipt?,
    isLoading: Boolean,
    onClose: () -> Unit
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Receipt", fontWeight = FontWeight.SemiBold) },
                navigationIcon = {
                    IconButton(onClick = onClose) {
                        Icon(Icons.Default.Close, contentDescription = "Close")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Lx.Surface)
            )
        },
        containerColor = Lx.Surface
    ) { padding ->
        when {
            isLoading && receipt == null -> {
                Box(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentAlignment = Alignment.Center
                ) { CircularProgressIndicator() }
            }
            receipt == null -> {
                Box(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentAlignment = Alignment.Center
                ) { Text("Receipt unavailable.", color = Lx.TextSecondary) }
            }
            else -> {
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
                            .size(72.dp)
                            .clip(CircleShape)
                            .background(Brand.copy(alpha = 0.1f)),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(Icons.Default.Receipt, null, tint = Brand, modifier = Modifier.size(36.dp))
                    }

                    Spacer(Modifier.height(12.dp))
                    Text("Ride Receipt", fontSize = Lx.FontSize.title, fontWeight = FontWeight.Bold)
                    (receipt.rideNumber ?: receipt.rideRequestId?.let { "#$it" })?.let {
                        Text(it, fontSize = Lx.FontSize.footnote, color = Lx.TextSecondary)
                    }
                    (receipt.completedAt ?: receipt.date)?.let {
                        Text(it, fontSize = Lx.FontSize.footnote, color = Lx.TextSecondary)
                    }

                    Spacer(Modifier.height(20.dp))

                    Card(
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(Lx.Radius.button),
                        colors = CardDefaults.cardColors(containerColor = Lx.Surface2)
                    ) {
                        Column(modifier = Modifier.padding(16.dp)) {
                            receipt.driverName?.let { Row2("Driver", it) }
                            receipt.vehicle?.let { Row2("Vehicle", it) }
                            receipt.pickupAddress?.let { Row2("From", it) }
                            receipt.dropoffAddress?.let { Row2("To", it) }
                            receipt.distanceMiles?.let { Row2("Distance", String.format("%.1f mi", it)) }
                            receipt.durationMinutes?.let { Row2("Duration", "$it min") }
                            receipt.paymentMethod?.let { Row2("Payment", it) }
                        }
                    }

                    Spacer(Modifier.height(16.dp))

                    Card(
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(Lx.Radius.button),
                        colors = CardDefaults.cardColors(containerColor = Lx.Surface),
                        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
                    ) {
                        Column(modifier = Modifier.padding(16.dp)) {
                            receipt.fare?.let { AmountRow("Fare", it) }
                            receipt.platformFee?.let { AmountRow("Platform fee", it) }
                            receipt.accessForAllFee?.let { if (it > 0) AmountRow("CPUC Access for All fee", it) }
                            receipt.tip?.let { if (it > 0) AmountRow("Tip", it) }
                            if (receipt.total != null) {
                                Divider(modifier = Modifier.padding(vertical = 8.dp))
                                AmountRow("Total", receipt.total, bold = true)
                            }
                        }
                    }

                    if (receipt.zeroTolerancePolicy != null || receipt.cpucPhone != null) {
                        Spacer(Modifier.height(16.dp))
                        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            receipt.zeroTolerancePolicy?.let { Text(it, fontSize = Lx.FontSize.caption, color = Lx.TextSecondary) }
                            Text(
                                "Safety concerns: support@dollor.ai",
                                fontSize = Lx.FontSize.caption,
                                color = Lx.TextSecondary
                            )
                            if (receipt.cpucPhone != null) {
                                Text(
                                    "California Public Utilities Commission complaints: ${receipt.cpucPhone}" +
                                        (receipt.cpucEmail?.let { " · $it" } ?: ""),
                                    fontSize = Lx.FontSize.caption,
                                    color = Lx.TextSecondary
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun Row2(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(label, fontSize = Lx.FontSize.footnote, color = Lx.TextSecondary)
        Text(
            value,
            fontSize = Lx.FontSize.footnote,
            color = Lx.Text,
            fontWeight = FontWeight.Medium,
            modifier = Modifier.padding(start = 16.dp)
        )
    }
}

@Composable
private fun AmountRow(label: String, amount: Double, bold: Boolean = false) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(
            label,
            fontSize = if (bold) 16.sp else 14.sp,
            fontWeight = if (bold) FontWeight.Bold else FontWeight.Normal
        )
        Text(
            "$${String.format("%.2f", amount)}",
            fontSize = if (bold) 16.sp else 14.sp,
            fontWeight = if (bold) FontWeight.Bold else FontWeight.Normal
        )
    }
}
