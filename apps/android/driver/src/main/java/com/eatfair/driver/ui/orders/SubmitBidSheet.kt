package com.eatfair.driver.ui.orders

import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.getValue
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccessTime
import androidx.compose.material.icons.filled.DoubleArrow
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.eatfair.shared.config.AppConfig
import com.eatfair.shared.model.rideshare.RideRequestForBidding
import com.eatfair.shared.ui.Lx
import kotlin.math.roundToInt

/** Bid presets, identical to iOS `SubmitBidSheet` (Quick Accept 92%, Fair Price 100%, Premium 108%). */
private object BidPresets {
    val QUICK_ACCEPT = AppConfig.Rideshare.BID_QUICK_ACCEPT_FACTOR
    val FAIR = AppConfig.Rideshare.BID_FAIR_FACTOR
    val PREMIUM = AppConfig.Rideshare.BID_PREMIUM_FACTOR
    val arrivalMinutes: List<Int> get() = AppConfig.Rideshare.etaOptionsMinutes
}

private fun money(value: Double) = "$" + String.format("%.2f", value)

/** What the driver keeps: fare minus the flat tiered fee (same rule as iOS `calculateEarnings`). */
private fun earnings(price: Double) = (price - AppConfig.Rideshare.calculatePlatformFee(price)).coerceAtLeast(0.0)

/**
 * Bid sheet mirroring the iOS `SubmitBidSheet`: route summary, three price presets, custom amount,
 * estimated arrival, optional message, fee transparency and slide-to-submit.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SubmitBidSheet(
    ride: RideRequestForBidding,
    isBusy: Boolean,
    onSubmit: (price: Double, etaMinutes: Int, message: String?) -> Unit,
    onDismiss: () -> Unit
) {
    val suggested = ride.suggestedPrice ?: ride.riderOffer ?: 0.0
    var priceText by remember { mutableStateOf(String.format(java.util.Locale.US, "%.2f", suggested)) }
    var eta by remember { mutableIntStateOf(5) }
    var message by remember { mutableStateOf("") }
    val price = priceText.replace(',', '.').toDoubleOrNull() ?: 0.0
    val canSubmit = price > AppConfig.Rideshare.calculatePlatformFee(price) && !isBusy

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = Lx.Bg,
        shape = RoundedCornerShape(topStart = Lx.Radius.sheet, topEnd = Lx.Radius.sheet)
    ) {
        Column(modifier = Modifier.fillMaxWidth()) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = Lx.Spacing.l),
                verticalAlignment = Alignment.CenterVertically
            ) {
                TextButton(onClick = onDismiss) {
                    Text("Cancel", color = Lx.Orange, fontSize = Lx.FontSize.body)
                }
                Text(
                    text = "Submit Your Bid",
                    color = Lx.Text,
                    fontSize = Lx.FontSize.body,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.weight(1f),
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center
                )
                Spacer(Modifier.width(64.dp))
            }

            Column(
                modifier = Modifier
                    .weight(1f, fill = false)
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = Lx.Spacing.l),
                verticalArrangement = Arrangement.spacedBy(Lx.Spacing.l)
            ) {
                RouteCard(ride)

                SheetCard {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("Your Bid Price", color = Lx.Text, fontSize = Lx.FontSize.body, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                        Text("Suggested: ${money(suggested)}", color = Lx.Orange, fontSize = Lx.FontSize.subheadline)
                    }
                    Text("Suggested Bids", color = Lx.TextSecondary, fontSize = Lx.FontSize.subheadline, fontWeight = FontWeight.SemiBold)
                    Row(horizontalArrangement = Arrangement.spacedBy(Lx.Spacing.s)) {
                        listOf(
                            Triple("Quick Accept", BidPresets.QUICK_ACCEPT, Lx.Orange),
                            Triple("Fair Price", BidPresets.FAIR, Lx.OrangeBright),
                            Triple("Premium", BidPresets.PREMIUM, Lx.Success)
                        ).forEach { (title, factor, color) ->
                            val amount = Math.round(suggested * factor * 100.0) / 100.0
                            BidOption(
                                modifier = Modifier.weight(1f),
                                title = title,
                                percent = "${(factor * 100).roundToInt()}%",
                                amount = amount,
                                color = color,
                                selected = kotlin.math.abs(price - amount) < 0.005,
                                onClick = { priceText = String.format(java.util.Locale.US, "%.2f", amount) }
                            )
                        }
                    }
                    OutlinedTextField(
                        value = priceText,
                        onValueChange = { v -> priceText = v.filter { it.isDigit() || it == '.' }.take(7) },
                        prefix = { Text("$", color = Lx.TextSecondary) },
                        label = { Text("Custom amount") },
                        singleLine = true,
                        keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(Lx.Radius.button),
                        colors = sheetFieldColors()
                    )
                    Text(
                        text = "You earn ${String.format("%.2f", earnings(price)).let { "$$it" }} after the flat fee",
                        color = Lx.TextSecondary,
                        fontSize = Lx.FontSize.footnote
                    )
                }

                SheetCard {
                    Text("Estimated Arrival", color = Lx.Text, fontSize = Lx.FontSize.body, fontWeight = FontWeight.SemiBold)
                    Row(horizontalArrangement = Arrangement.spacedBy(Lx.Spacing.s)) {
                        BidPresets.arrivalMinutes.forEach { minutes ->
                            val selected = eta == minutes
                            Box(
                                modifier = Modifier
                                    .clip(RoundedCornerShape(Lx.Radius.chip))
                                    .background(if (selected) Lx.Orange else Lx.Orange.copy(alpha = 0.12f))
                                    .clickable { eta = minutes }
                                    .padding(horizontal = Lx.Spacing.l, vertical = 10.dp)
                            ) {
                                Text(
                                    "$minutes min",
                                    color = if (selected) Lx.Text else Lx.Orange,
                                    fontSize = Lx.FontSize.subheadline,
                                    fontWeight = FontWeight.SemiBold
                                )
                            }
                        }
                    }
                }

                SheetCard {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Lx.Spacing.s)) {
                        Text("Message to Rider", color = Lx.Text, fontSize = Lx.FontSize.body, fontWeight = FontWeight.SemiBold)
                        Text("(Optional)", color = Lx.TextSecondary, fontSize = Lx.FontSize.caption)
                    }
                    OutlinedTextField(
                        value = message,
                        onValueChange = { message = it.take(200) },
                        placeholder = { Text("e.g., I'm nearby and can pick you up quickly!", color = Lx.TextMuted) },
                        minLines = 2,
                        maxLines = 4,
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(Lx.Radius.button),
                        colors = sheetFieldColors()
                    )
                }

                FeeInfoCard()
                Spacer(Modifier.height(Lx.Spacing.s))
            }

            Box(modifier = Modifier.fillMaxWidth().background(Lx.Surface).padding(Lx.Spacing.l)) {
                SlideToConfirm(
                    label = "Slide to Submit Bid ${money(price)}",
                    enabled = canSubmit,
                    onConfirmed = { onSubmit(price, eta, message.trim().ifBlank { null }) }
                )
            }
        }
    }
}

@Composable
private fun sheetFieldColors() = OutlinedTextFieldDefaults.colors(
    focusedTextColor = Lx.Text,
    unfocusedTextColor = Lx.Text,
    focusedBorderColor = Lx.Orange,
    unfocusedBorderColor = Lx.Hairline,
    focusedContainerColor = Lx.Surface2,
    unfocusedContainerColor = Lx.Surface2,
    focusedLabelColor = Lx.Orange,
    unfocusedLabelColor = Lx.TextSecondary,
    cursorColor = Lx.Orange
)

@Composable
private fun SheetCard(content: @Composable () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Lx.Radius.card))
            .background(Lx.Surface)
            .border(BorderStroke(1.dp, Lx.Hairline), RoundedCornerShape(Lx.Radius.card))
            .padding(Lx.Spacing.l),
        verticalArrangement = Arrangement.spacedBy(Lx.Spacing.m)
    ) { content() }
}

@Composable
private fun RouteCard(ride: RideRequestForBidding) {
    SheetCard {
        RouteLine(Lx.Pickup, "Pickup", ride.pickup.address)
        RouteLine(Lx.Dropoff, "Drop-off", ride.dropoff.address)
        Row(horizontalArrangement = Arrangement.spacedBy(Lx.Spacing.xl), modifier = Modifier.fillMaxWidth()) {
            Text(ride.formattedTripDistance, color = Lx.Orange, fontSize = Lx.FontSize.caption, fontWeight = FontWeight.SemiBold)
            ride.estimatedDurationMinutes?.let {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Lx.Spacing.xs)) {
                    Icon(Icons.Default.AccessTime, null, tint = Lx.Orange, modifier = Modifier.size(14.dp))
                    Text("$it min", color = Lx.Orange, fontSize = Lx.FontSize.caption, fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }
}

@Composable
private fun RouteLine(color: Color, label: String, address: String?) {
    Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(Lx.Spacing.m)) {
        Box(modifier = Modifier.padding(top = 6.dp).size(10.dp).clip(CircleShape).background(color))
        Column {
            Text(label, color = Lx.TextSecondary, fontSize = Lx.FontSize.caption)
            Text(address ?: "—", color = Lx.Text, fontSize = Lx.FontSize.subheadline)
        }
    }
}

@Composable
private fun BidOption(
    modifier: Modifier,
    title: String,
    percent: String,
    amount: Double,
    color: Color,
    selected: Boolean,
    onClick: () -> Unit
) {
    val shape = RoundedCornerShape(Lx.Radius.button)
    Column(
        modifier = modifier
            .clip(shape)
            .background(color.copy(alpha = if (selected) 0.28f else 0.10f))
            .border(BorderStroke(if (selected) 2.dp else 1.dp, color), shape)
            .clickable(onClick = onClick)
            .padding(vertical = Lx.Spacing.m, horizontal = Lx.Spacing.xs),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Lx.Spacing.xs)
    ) {
        Text(title, color = color, fontSize = Lx.FontSize.footnote, fontWeight = FontWeight.SemiBold)
        Text(percent, color = color.copy(alpha = 0.8f), fontSize = Lx.FontSize.caption)
        Text(money(amount), color = Lx.Text, fontSize = Lx.FontSize.title, fontWeight = FontWeight.Bold)
        Text("Earn ${money(earnings(amount))}", color = Lx.TextSecondary, fontSize = Lx.FontSize.caption)
    }
}

/** Fee transparency. Tier rows come from `AppConfig.Rideshare` so copy can never drift from the real fee. */
@Composable
private fun FeeInfoCard() {
    val t1 = AppConfig.Rideshare.TIER_1_MAX_FARE.roundToInt()
    val t2 = AppConfig.Rideshare.TIER_2_MAX_FARE.roundToInt()
    val rows = listOf(
        "Fares up to $$t1" to AppConfig.Rideshare.TIER_1_FEE,
        "Fares $${t1}-$$t2" to AppConfig.Rideshare.TIER_2_FEE,
        "Fares over $$t2" to AppConfig.Rideshare.TIER_3_FEE
    )
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Lx.Radius.card))
            .background(Lx.Success.copy(alpha = 0.10f))
            .padding(Lx.Spacing.l),
        verticalArrangement = Arrangement.spacedBy(Lx.Spacing.s)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Lx.Spacing.m)) {
            Icon(Icons.Outlined.Info, null, tint = Lx.Success)
            Column {
                Text("You keep the fare minus a flat fee", color = Lx.Success, fontSize = Lx.FontSize.subheadline, fontWeight = FontWeight.Bold)
                Text("Flat fee, NOT a percentage", color = Lx.Success, fontSize = Lx.FontSize.caption, fontWeight = FontWeight.SemiBold)
            }
        }
        Text("Platform Fee Structure:", color = Lx.Text, fontSize = Lx.FontSize.caption, fontWeight = FontWeight.SemiBold)
        rows.forEach { (label, fee) ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(modifier = Modifier.size(6.dp).clip(CircleShape).background(Lx.Success))
                Spacer(Modifier.width(Lx.Spacing.s))
                Text("$label:", color = Lx.TextSecondary, fontSize = Lx.FontSize.caption, modifier = Modifier.weight(1f))
                Text("$${fee.roundToInt()} flat", color = Lx.Success, fontSize = Lx.FontSize.caption, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

/** Slide-to-confirm control, equivalent to the iOS `SlideToConfirmButton`. */
@Composable
fun SlideToConfirm(label: String, enabled: Boolean, onConfirmed: () -> Unit) {
    // The drag handler is started once; always call the latest callback so the price shown is the price submitted
    val latestOnConfirmed by rememberUpdatedState(onConfirmed)
    val handle = 52.dp
    val density = LocalDensity.current
    var trackWidthPx by remember { mutableIntStateOf(0) }
    var offsetPx by remember { mutableFloatStateOf(0f) }
    val handlePx = with(density) { handle.toPx() }
    val maxOffset = (trackWidthPx - handlePx).coerceAtLeast(1f)
    val shape = RoundedCornerShape(Lx.Radius.button)

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(Lx.Size.buttonHeight)
            .clip(shape)
            .background(if (enabled) Lx.Orange.copy(alpha = 0.18f) else Lx.Surface2)
            .border(BorderStroke(1.dp, if (enabled) Lx.Orange.copy(alpha = 0.6f) else Lx.Hairline), shape)
            .onSizeChanged { trackWidthPx = it.width },
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = label,
            color = if (enabled) Lx.Orange else Lx.TextMuted,
            fontSize = Lx.FontSize.body,
            fontWeight = FontWeight.SemiBold
        )
        Box(
            modifier = Modifier
                .align(Alignment.CenterStart)
                .offset { IntOffset(offsetPx.roundToInt(), 0) }
                .padding(2.dp)
                .size(handle - 4.dp)
                .clip(CircleShape)
                .background(Lx.Text)
                .pointerInput(enabled, trackWidthPx) {
                    if (!enabled) return@pointerInput
                    detectHorizontalDragGestures(
                        onDragEnd = {
                            if (offsetPx >= maxOffset * 0.85f) {
                                offsetPx = 0f
                                latestOnConfirmed()
                            } else {
                                offsetPx = 0f
                            }
                        },
                        onDragCancel = { offsetPx = 0f }
                    ) { change, drag ->
                        change.consume()
                        offsetPx = (offsetPx + drag).coerceIn(0f, maxOffset)
                    }
                },
            contentAlignment = Alignment.Center
        ) {
            Icon(Icons.Default.DoubleArrow, contentDescription = "Slide to confirm", tint = Lx.Orange)
        }
    }
}
