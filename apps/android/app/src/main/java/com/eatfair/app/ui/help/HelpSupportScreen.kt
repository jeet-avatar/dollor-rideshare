package com.eatfair.app.ui.help

import com.eatfair.shared.config.AppConfig
import com.eatfair.shared.ui.Lx
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Help & Support Screen
 * Matches iOS HelpSupportView for platform parity
 * Provides FAQ, contact options, and support resources
 */

data class FAQItem(
    val id: String,
    val question: String,
    val answer: String,
    val category: String
)

data class SupportOption(
    val id: String,
    val title: String,
    val subtitle: String,
    val icon: ImageVector,
    val action: () -> Unit
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HelpSupportScreen(
    onBackClick: () -> Unit,
    onContactSupport: () -> Unit,
    onChatWithUs: () -> Unit,
    onCallSupport: () -> Unit
) {
    var selectedCategory by remember { mutableStateOf("All") }
    var expandedFaqId by remember { mutableStateOf<String?>(null) }
    var searchQuery by remember { mutableStateOf("") }

    val categories = listOf("All", "Rides", "Payments", "Account", "Drivers")

    val faqItems = remember {
        listOf(
            FAQItem(
                "1",
                "How do I track my ride?",
                "You can track your ride by going to the Rides tab and selecting your active ride. Real-time tracking shows your driver's location and estimated arrival time.",
                "Rides"
            ),
            FAQItem(
                "2",
                "What payment methods are accepted?",
                "We accept all major credit/debit cards, Apple Pay, Google Pay, and ACH bank transfers. ACH payments receive a discount on platform fees.",
                "Payments"
            ),
            FAQItem(
                "3",
                "How do I cancel my ride?",
                "Rides can be cancelled before a driver is matched. Go to Rides → Select Ride → Cancel. Full refunds are issued for eligible cancellations.",
                "Rides"
            ),
            FAQItem(
                "4",
                "How do I update my saved addresses?",
                "Go to Profile → Manage Addresses to add, edit, or delete addresses. You can also enter a new address when booking a ride.",
                "Account"
            ),
            FAQItem(
                "5",
                "What are platform fees?",
                "Dollor.ai charges transparent, low platform fees:\n" + AppConfig.Rideshare.tierLines.joinToString("\n") { "• $it" } + "\n\n100% of tips go directly to drivers.",
                "Payments"
            ),
            FAQItem(
                "6",
                "How do I contact my driver?",
                "Once your ride is matched, you can call or message your driver through the ride tracking screen. Your phone number is masked for privacy.",
                "Drivers"
            ),
            FAQItem(
                "7",
                "What if I have an issue with my ride?",
                "Contact support immediately through the app. We'll review the issue and provide appropriate assistance.",
                "Rides"
            ),
            FAQItem(
                "8",
                "How do I delete my account?",
                "Go to Profile → Settings → Delete Account. This permanently removes all your data. Per Apple/Google requirements, you can delete your account at any time.",
                "Account"
            ),
            FAQItem(
                "9",
                "Are drivers employees of Dollor.ai?",
                "No, all drivers are independent contractors. Dollor.ai is a matchmaking platform that connects riders with independent drivers.",
                "Drivers"
            ),
            FAQItem(
                "10",
                "How do refunds work?",
                "Refunds are processed to your original payment method within 5-7 business days. For disputed charges, contact support for assistance.",
                "Payments"
            )
        )
    }

    val filteredFaqs = faqItems.filter { faq ->
        (selectedCategory == "All" || faq.category == selectedCategory) &&
                (searchQuery.isEmpty() ||
                        faq.question.contains(searchQuery, ignoreCase = true) ||
                        faq.answer.contains(searchQuery, ignoreCase = true))
    }

    val supportOptions = listOf(
        SupportOption("chat", "Chat with Us", "Average response time: 2 mins", Icons.Default.Chat, onChatWithUs),
        SupportOption("email", "Email Support", "support@dollor.ai", Icons.Default.Email, onContactSupport),
        SupportOption("call", "Call Support", "Available 9AM - 9PM", Icons.Default.Phone, onCallSupport)
    )

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Help & Support") },
                navigationIcon = {
                    IconButton(onClick = onBackClick) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = Lx.Surface,
                    titleContentColor = Lx.Text
                )
            )
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .background(Lx.Surface2),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            // Search Bar
            item {
                OutlinedTextField(
                    value = searchQuery,
                    onValueChange = { searchQuery = it },
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text("Search help articles...") },
                    leadingIcon = {
                        Icon(Icons.Default.Search, contentDescription = null, tint = Lx.TextSecondary)
                    },
                    trailingIcon = {
                        if (searchQuery.isNotEmpty()) {
                            IconButton(onClick = { searchQuery = "" }) {
                                Icon(Icons.Default.Clear, contentDescription = "Clear")
                            }
                        }
                    },
                    shape = RoundedCornerShape(Lx.Radius.button),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = Lx.Orange,
                        unfocusedBorderColor = Lx.Hairline,
                        unfocusedContainerColor = Lx.Surface,
                        focusedContainerColor = Lx.Surface
                    ),
                    singleLine = true
                )
            }

            // Contact Support Section
            item {
                Text(
                    text = "Contact Us",
                    fontSize = Lx.FontSize.body,
                    fontWeight = FontWeight.SemiBold,
                    color = Lx.Text
                )

                Spacer(modifier = Modifier.height(8.dp))

                Card(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(Lx.Radius.button),
                    colors = CardDefaults.cardColors(containerColor = Lx.Surface)
                ) {
                    Column {
                        supportOptions.forEachIndexed { index, option ->
                            SupportOptionRow(option = option)
                            if (index < supportOptions.lastIndex) {
                                HorizontalDivider(
                                    modifier = Modifier.padding(start = 60.dp),
                                    color = Lx.Hairline
                                )
                            }
                        }
                    }
                }
            }

            // FAQ Section
            item {
                Text(
                    text = "Frequently Asked Questions",
                    fontSize = Lx.FontSize.body,
                    fontWeight = FontWeight.SemiBold,
                    color = Lx.Text
                )

                Spacer(modifier = Modifier.height(8.dp))

                // Category Chips
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(bottom = 8.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    categories.forEach { category ->
                        FilterChip(
                            selected = selectedCategory == category,
                            onClick = { selectedCategory = category },
                            label = { Text(category, fontSize = Lx.FontSize.caption) },
                            colors = FilterChipDefaults.filterChipColors(
                                selectedContainerColor = Lx.Orange,
                                selectedLabelColor = Color.White
                            )
                        )
                    }
                }
            }

            // FAQ Items
            items(filteredFaqs) { faq ->
                FAQItemCard(
                    faq = faq,
                    isExpanded = expandedFaqId == faq.id,
                    onToggle = {
                        expandedFaqId = if (expandedFaqId == faq.id) null else faq.id
                    }
                )
            }

            // Still Need Help
            item {
                Spacer(modifier = Modifier.height(16.dp))

                Card(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(Lx.Radius.button),
                    colors = CardDefaults.cardColors(
                        containerColor = Lx.Orange.copy(alpha = 0.1f)
                    )
                ) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(20.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Icon(
                            Icons.Default.SupportAgent,
                            contentDescription = null,
                            modifier = Modifier.size(48.dp),
                            tint = Lx.Orange
                        )

                        Spacer(modifier = Modifier.height(12.dp))

                        Text(
                            text = "Still need help?",
                            fontSize = Lx.FontSize.body,
                            fontWeight = FontWeight.SemiBold,
                            color = Lx.Text
                        )

                        Text(
                            text = "Our support team is available 24/7",
                            fontSize = Lx.FontSize.footnote,
                            color = Lx.TextSecondary
                        )

                        Spacer(modifier = Modifier.height(16.dp))

                        Button(
                            onClick = onChatWithUs,
                            shape = RoundedCornerShape(Lx.Radius.chip),
                            colors = ButtonDefaults.buttonColors(
                                containerColor = Lx.Orange
                            )
                        ) {
                            Icon(
                                Icons.Default.Chat,
                                contentDescription = null,
                                modifier = Modifier.size(18.dp)
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            Text("Start a Conversation")
                        }
                    }
                }

                Spacer(modifier = Modifier.height(32.dp))
            }
        }
    }
}

@Composable
fun SupportOptionRow(option: SupportOption) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { option.action() }
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Box(
            modifier = Modifier
                .size(44.dp)
                .clip(CircleShape)
                .background(Lx.Orange.copy(alpha = 0.1f)),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                option.icon,
                contentDescription = null,
                tint = Lx.Orange,
                modifier = Modifier.size(24.dp)
            )
        }

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = option.title,
                fontSize = Lx.FontSize.callout,
                fontWeight = FontWeight.Medium,
                color = Lx.Text
            )
            Text(
                text = option.subtitle,
                fontSize = Lx.FontSize.caption,
                color = Lx.TextSecondary
            )
        }

        Icon(
            Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = Lx.TextSecondary
        )
    }
}

@Composable
fun FAQItemCard(
    faq: FAQItem,
    isExpanded: Boolean,
    onToggle: () -> Unit
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onToggle() },
        shape = RoundedCornerShape(Lx.Radius.button),
        colors = CardDefaults.cardColors(containerColor = Lx.Surface)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = faq.question,
                    fontSize = Lx.FontSize.footnote,
                    fontWeight = FontWeight.Medium,
                    color = Lx.Text,
                    modifier = Modifier.weight(1f)
                )

                Icon(
                    if (isExpanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                    contentDescription = if (isExpanded) "Collapse" else "Expand",
                    tint = Lx.Orange
                )
            }

            AnimatedVisibility(
                visible = isExpanded,
                enter = expandVertically(),
                exit = shrinkVertically()
            ) {
                Column {
                    Spacer(modifier = Modifier.height(12.dp))
                    HorizontalDivider(color = Lx.Hairline)
                    Spacer(modifier = Modifier.height(12.dp))
                    Text(
                        text = faq.answer,
                        fontSize = Lx.FontSize.footnote,
                        color = Lx.TextSecondary,
                        lineHeight = 20.sp
                    )

                    Spacer(modifier = Modifier.height(8.dp))

                    // Category badge
                    Surface(
                        shape = RoundedCornerShape(4.dp),
                        color = Lx.Orange.copy(alpha = 0.1f)
                    ) {
                        Text(
                            text = faq.category,
                            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                            fontSize = Lx.FontSize.caption,
                            color = Lx.Orange,
                            fontWeight = FontWeight.Medium
                        )
                    }
                }
            }
        }
    }
}
