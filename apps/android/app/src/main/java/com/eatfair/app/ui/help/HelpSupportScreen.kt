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
                "You can track your ride from the Ride screen while your trip is active. Real-time tracking shows your driver's location and estimated arrival time.",
                "Rides"
            ),
            FAQItem(
                "2",
                "What payment methods are accepted?",
                "We accept all major credit and debit cards. Add one under Profile > Payment Methods.",
                "Payments"
            ),
            FAQItem(
                "3",
                "How do I cancel my ride?",
                "You can cancel before the ride starts with no cancellation fee, and your card authorization is released. You cannot cancel once the trip is in progress. If the driver has arrived and waited at least 5 minutes and you do not show up, your saved card is charged a $5.00 no-show fee.",
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
                "Dollor.ai charges a flat connection fee by fare:\n" + AppConfig.Rideshare.tierLines.joinToString("\n") { "• $it" } + "\n\nA $0.05 CPUC Access for All charge also applies. Drivers pay the same fee tier separately. 100% of tips go directly to drivers.",
                "Payments"
            ),
            FAQItem(
                "6",
                "How do I contact my driver?",
                "Once your ride is matched, you can call or message your driver through the ride tracking screen.",
                "Drivers"
            ),
            FAQItem(
                "7",
                "What if I have an issue with my ride?",
                "Email support@dollor.ai with your trip ID and we will review the issue.",
                "Rides"
            ),
            FAQItem(
                "8",
                "How do I delete my account?",
                "Go to Profile → Settings → Delete Account. This permanently deletes your account. You can delete your account at any time.",
                "Account"
            ),
            FAQItem(
                "9",
                "Are drivers employees of Dollor.ai?",
                "No, all drivers are independent contractors. Dollor.ai is a peer-to-peer rideshare marketplace operated by Zietra Technologies Inc.; riders post an offer and independent drivers bid on it.",
                "Drivers"
            ),
            FAQItem(
                "10",
                "How do refunds work?",
                "For refund or charge questions, email support@dollor.ai with your trip ID.",
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

    val support = AppConfig.Rideshare.support
    val supportOptions = listOfNotNull(
        SupportOption(
            "chat", "Chat with Us",
            support.responseMinutes?.let { "Average response time: $it mins" } ?: "Message our team",
            Icons.Default.Chat, onChatWithUs
        ),
        SupportOption("email", "Email Support", support.email, Icons.Default.Email, onContactSupport),
        support.phone?.let { phone ->
            SupportOption("call", "Call Support", support.hoursText ?: phone, Icons.Default.Phone, onCallSupport)
        }
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
                            text = "Chat with us or send an email and we'll reply as soon as we can",
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
