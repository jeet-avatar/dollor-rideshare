package com.eatfair.app.ui.rating

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
                    containerColor = Color.White,
                    titleContentColor = Color.Black
                )
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .background(Color.White)
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
                        .background(Color(0xFF6C63FF).copy(alpha = 0.1f)),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = driverName.firstOrNull()?.toString() ?: "D",
                        fontSize = 36.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color(0xFF6C63FF)
                    )
                }

                Spacer(modifier = Modifier.height(16.dp))

                Text(
                    text = "How was your ride with $driverName?",
                    fontSize = 20.sp,
                    fontWeight = FontWeight.SemiBold,
                    textAlign = TextAlign.Center
                )

                Text(
                    text = "Ride #${orderId.takeLast(6)}",
                    fontSize = 14.sp,
                    color = Color.Gray
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
                                tint = Color(0xFFFFC107),
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
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Medium,
                    color = if (rating > 0) Color(0xFF6C63FF) else Color.Gray
                )

                // Tags Section
                if (displayTags.isNotEmpty()) {
                    Spacer(modifier = Modifier.height(24.dp))

                    Text(
                        text = if (rating >= 4) "What did you like?" else "What went wrong?",
                        fontSize = 14.sp,
                        color = Color.Gray
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
                                label = { Text(tag.label, fontSize = 12.sp) },
                                colors = FilterChipDefaults.filterChipColors(
                                    selectedContainerColor = if (tag.isPositive)
                                        Color(0xFF4CAF50).copy(alpha = 0.1f)
                                    else
                                        Color(0xFFF44336).copy(alpha = 0.1f),
                                    selectedLabelColor = if (tag.isPositive)
                                        Color(0xFF4CAF50)
                                    else
                                        Color(0xFFF44336)
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
                        shape = RoundedCornerShape(12.dp),
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedBorderColor = Color(0xFF6C63FF),
                            unfocusedBorderColor = Color(0xFFE0E0E0)
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
                            tint = Color(0xFF6C63FF)
                        )
                        Spacer(modifier = Modifier.width(4.dp))
                        Text("Add a tip for $driverName", color = Color(0xFF6C63FF))
                    }
                }

                if (showTipSection && rating >= 4) {
                    Spacer(modifier = Modifier.height(16.dp))

                    Card(
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(12.dp),
                        colors = CardDefaults.cardColors(
                            containerColor = Color(0xFF6C63FF).copy(alpha = 0.05f)
                        )
                    ) {
                        Column(
                            modifier = Modifier.padding(16.dp),
                            horizontalAlignment = Alignment.CenterHorizontally
                        ) {
                            Text(
                                text = "Add a Tip",
                                fontWeight = FontWeight.SemiBold,
                                color = Color(0xFF6C63FF)
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
                                        shape = RoundedCornerShape(8.dp),
                                        color = if (isSelected) Color(0xFF6C63FF) else Color.White,
                                        border = ButtonDefaults.outlinedButtonBorder
                                    ) {
                                        Text(
                                            text = if (tip == 0.0) "None" else "$${"%.0f".format(tip)}",
                                            modifier = Modifier.padding(vertical = 12.dp),
                                            textAlign = TextAlign.Center,
                                            fontWeight = FontWeight.Medium,
                                            color = if (isSelected) Color.White else Color.Black
                                        )
                                    }
                                }
                            }

                            Spacer(modifier = Modifier.height(8.dp))

                            Text(
                                text = "100% goes to your driver",
                                fontSize = 12.sp,
                                color = Color.Gray
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
                        .background(Color.White)
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
                        shape = RoundedCornerShape(12.dp),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = Color(0xFF6C63FF)
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
                        Text("Skip for now", color = Color.Gray)
                    }
                }
            }
        }
    }
}
