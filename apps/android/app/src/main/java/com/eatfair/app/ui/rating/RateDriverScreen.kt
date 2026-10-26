package com.eatfair.app.ui.rating

import com.eatfair.shared.ui.Lx
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

data class RatingTag(
    val id: String,
    val label: String,
    val isPositive: Boolean = true
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RateDriverScreen(
    driverName: String,
    driverPhoto: String?,
    orderId: String,
    onBackClick: () -> Unit,
    onSubmitRating: (Int, List<String>, String, Double?) -> Unit
) {
    var rating by remember { mutableStateOf(0) }
    var selectedTags by remember { mutableStateOf(setOf<String>()) }
    var comment by remember { mutableStateOf("") }
    var tipAmount by remember { mutableStateOf<Double?>(null) }
    var showTipSection by remember { mutableStateOf(false) }

    val positiveTags = listOf(
        RatingTag("fast", "Fast Driver"),
        RatingTag("friendly", "Friendly"),
        RatingTag("professional", "Professional"),
        RatingTag("safe", "Safe Driver"),
        RatingTag("communication", "Great Communication"),
        RatingTag("on_time", "On Time")
    )

    val negativeTags = listOf(
        RatingTag("slow", "Slow Driver", false),
        RatingTag("unfriendly", "Unfriendly", false),
        RatingTag("unsafe", "Unsafe Driving", false),
        RatingTag("late", "Late", false),
        RatingTag("poor_communication", "Poor Communication", false)
    )

    val displayTags = if (rating >= 4) positiveTags else if (rating in 1..3) negativeTags else emptyList()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Rate Your Driver") },
                navigationIcon = {
                    IconButton(onClick = onBackClick) {
                        Icon(Icons.Default.Close, contentDescription = "Close")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = Lx.Surface,
                    titleContentColor = Lx.Text
                )
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .background(Lx.Surface)
        ) {
            Column(
                modifier = Modifier
                    .weight(1f)
                    .padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                // Driver Avatar
                Box(
                    modifier = Modifier
                        .size(100.dp)
                        .clip(CircleShape)
                        .background(Lx.Orange.copy(alpha = 0.1f)),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = driverName.firstOrNull()?.toString() ?: "D",
                        fontSize = 36.sp,
                        fontWeight = FontWeight.Bold,
                        color = Lx.Orange
                    )
                }

                Spacer(modifier = Modifier.height(16.dp))

                Text(
                    text = "How was your ride with $driverName?",
                    fontSize = Lx.FontSize.title,
                    fontWeight = FontWeight.SemiBold,
                    textAlign = TextAlign.Center
                )

                Text(
                    text = "Ride #${orderId.takeLast(6)}",
                    fontSize = Lx.FontSize.footnote,
                    color = Lx.TextSecondary
                )

                Spacer(modifier = Modifier.height(24.dp))

                // Star Rating
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    (1..5).forEach { star ->
                        IconButton(
                            onClick = { rating = star },
                            modifier = Modifier.size(48.dp)
                        ) {
                            Icon(
                                if (star <= rating) Icons.Default.Star else Icons.Default.StarBorder,
                                contentDescription = "Rate $star stars",
                                tint = Lx.Gold,
                                modifier = Modifier.size(40.dp)
                            )
                        }
                    }
                }

                // Rating Label
                Text(
                    text = when (rating) {
                        1 -> "Poor"
                        2 -> "Fair"
                        3 -> "Good"
                        4 -> "Great"
                        5 -> "Excellent!"
                        else -> "Tap to rate"
                    },
                    fontSize = Lx.FontSize.callout,
                    fontWeight = FontWeight.Medium,
                    color = if (rating > 0) Lx.Orange else Lx.TextSecondary
                )

                // Tags Section
                if (displayTags.isNotEmpty()) {
                    Spacer(modifier = Modifier.height(24.dp))

                    Text(
                        text = if (rating >= 4) "What did you like?" else "What went wrong?",
                        fontSize = Lx.FontSize.footnote,
                        color = Lx.TextSecondary
                    )

                    Spacer(modifier = Modifier.height(12.dp))

                    LazyRow(
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        items(displayTags) { tag ->
                            FilterChip(
                                selected = selectedTags.contains(tag.id),
                                onClick = {
                                    selectedTags = if (selectedTags.contains(tag.id)) {
                                        selectedTags - tag.id
                                    } else {
                                        selectedTags + tag.id
                                    }
                                },
                                label = { Text(tag.label, fontSize = Lx.FontSize.caption) },
                                colors = FilterChipDefaults.filterChipColors(
                                    selectedContainerColor = if (tag.isPositive)
                                        Lx.Success.copy(alpha = 0.1f)
                                    else
                                        Lx.Error.copy(alpha = 0.1f),
                                    selectedLabelColor = if (tag.isPositive)
                                        Lx.Success
                                    else
                                        Lx.Error
                                )
                            )
                        }
                    }
                }

                // Comment Field
                if (rating > 0) {
                    Spacer(modifier = Modifier.height(24.dp))

                    OutlinedTextField(
                        value = comment,
                        onValueChange = { comment = it },
                        modifier = Modifier.fillMaxWidth(),
                        placeholder = { Text("Add a comment (optional)") },
                        minLines = 3,
                        maxLines = 5,
                        shape = RoundedCornerShape(Lx.Radius.button),
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedBorderColor = Lx.Orange,
                            unfocusedBorderColor = Lx.Hairline
                        )
                    )
                }

                // Tip Section (for good ratings)
                if (rating >= 4 && !showTipSection) {
                    Spacer(modifier = Modifier.height(16.dp))

                    TextButton(onClick = { showTipSection = true }) {
                        Icon(
                            Icons.Default.AttachMoney,
                            contentDescription = null,
                            tint = Lx.Orange
                        )
                        Spacer(modifier = Modifier.width(4.dp))
                        Text("Add a tip for $driverName", color = Lx.Orange)
                    }
                }

                if (showTipSection && rating >= 4) {
                    Spacer(modifier = Modifier.height(16.dp))

                    Card(
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(Lx.Radius.button),
                        colors = CardDefaults.cardColors(
                            containerColor = Lx.Orange.copy(alpha = 0.05f)
                        )
                    ) {
                        Column(
                            modifier = Modifier.padding(16.dp),
                            horizontalAlignment = Alignment.CenterHorizontally
                        ) {
                            Text(
                                text = "Add a Tip",
                                fontWeight = FontWeight.SemiBold,
                                color = Lx.Orange
                            )

                            Spacer(modifier = Modifier.height(12.dp))

                            Row(
                                horizontalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                listOf(2.0, 3.0, 5.0, 0.0).forEach { tip ->
                                    val isSelected = tipAmount == tip
                                    Surface(
                                        modifier = Modifier
                                            .weight(1f)
                                            .clickable {
                                                tipAmount = if (tip == 0.0) null else tip
                                            },
                                        shape = RoundedCornerShape(Lx.Radius.chip),
                                        color = if (isSelected) Lx.Orange else Lx.Surface2,
                                        border = ButtonDefaults.outlinedButtonBorder
                                    ) {
                                        Text(
                                            text = if (tip == 0.0) "None" else "$${"%.0f".format(tip)}",
                                            modifier = Modifier.padding(vertical = 12.dp),
                                            textAlign = TextAlign.Center,
                                            fontWeight = FontWeight.Medium,
                                            color = if (isSelected) Color.White else Lx.Text
                                        )
                                    }
                                }
                            }

                            Spacer(modifier = Modifier.height(8.dp))

                            Text(
                                text = "100% goes to your driver",
                                fontSize = Lx.FontSize.caption,
                                color = Lx.TextSecondary
                            )
                        }
                    }
                }
            }

            // Submit Button
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shadowElevation = 8.dp
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(Lx.Surface)
                        .padding(16.dp)
                ) {
                    Button(
                        onClick = {
                            onSubmitRating(
                                rating,
                                selectedTags.toList(),
                                comment,
                                tipAmount
                            )
                        },
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(52.dp),
                        enabled = rating > 0,
                        shape = RoundedCornerShape(Lx.Radius.button),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = Lx.Orange
                        )
                    ) {
                        val currentTip = tipAmount
                        if (currentTip != null && currentTip > 0) {
                            Text(
                                "Submit Rating & $${"%.2f".format(currentTip)} Tip",
                                fontWeight = FontWeight.SemiBold
                            )
                        } else {
                            Text("Submit Rating", fontWeight = FontWeight.SemiBold)
                        }
                    }

                    TextButton(
                        onClick = onBackClick,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text("Skip for now", color = Lx.TextSecondary)
                    }
                }
            }
        }
    }
}
