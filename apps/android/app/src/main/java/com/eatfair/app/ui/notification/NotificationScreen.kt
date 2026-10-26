package com.eatfair.app.ui.notification

import com.eatfair.shared.ui.Lx
import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.eatfair.shared.model.notification.NotificationItem
import com.eatfair.app.ui.common.EFTopAppBar
import com.eatfair.app.ui.theme.primaryVerticalGradient
import kotlin.collections.forEach

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NotificationScreen(
    notifications: List<NotificationItem> = emptyList(),
    onBackClick: () -> Unit = {},
    onNotificationClick: (NotificationItem) -> Unit = {},
    onClearAllClick: () -> Unit = {}
) {

    val context = LocalContext.current

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(primaryVerticalGradient())
    ) {
        // Top App Bar
        EFTopAppBar("Notifications", true, onBackClick, actions = {
            if (notifications.isNotEmpty()) {
                TextButton(onClick = onClearAllClick) {
                    Text(
                        text = "Clear All",
                        color = Lx.Orange,
                        fontSize = Lx.FontSize.footnote
                    )
                }
            } else {
                Spacer(modifier = Modifier.width(48.dp))
            }
        })
//        TopAppBar(
//            title = {
//                Text(
//                    text = "Notifications",
//                    fontSize = Lx.FontSize.body,
//                    fontWeight = FontWeight.SemiBold,
//                    color = Lx.Text,
//                    modifier = Modifier.fillMaxWidth(),
//                    textAlign = TextAlign.Center
//                )
//            },
//            navigationIcon = {
//                IconButton(onClick = onBackClick) {
//                    Icon(
//                        imageVector = Icons.AutoMirrored.Filled.ArrowBack,
//                        contentDescription = "Back",
//                        tint = Lx.Text
//                    )
//                }
//            },
//            actions = {
//
//            },
//            colors = TopAppBarDefaults.topAppBarColors(
//                containerColor = Lx.Surface2
//            )
//        )

        if (notifications.isEmpty()) {
            // Empty State
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(32.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
            ) {
                Text(
                    text = "🔔",
                    fontSize = 80.sp
                )
                Spacer(modifier = Modifier.height(16.dp))
                Text(
                    text = "No Notifications Yet",
                    fontSize = Lx.FontSize.title,
                    fontWeight = FontWeight.Bold,
                    color = Lx.Text
                )
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = "When you get notifications, they'll show up here",
                    fontSize = Lx.FontSize.footnote,
                    color = Lx.TextSecondary,
                    textAlign = TextAlign.Center
                )
            }
        } else {
            // Notification List
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 20.dp)
            ) {
                Spacer(modifier = Modifier.height(16.dp))

                notifications.forEach { notification ->
                    NotificationCard(
                        notification = notification,
                        onClick = {
                            Toast.makeText(context, "Notification clicked", Toast.LENGTH_SHORT)
                                .show()
//                            onNotificationClick(notification)
                        }
                    )
                    Spacer(modifier = Modifier.height(12.dp))
                }

                Spacer(modifier = Modifier.height(100.dp))
            }
        }
    }
}

@Composable
fun NotificationCard(
    notification: NotificationItem,
    onClick: () -> Unit
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        colors = CardDefaults.cardColors(
            containerColor = if (notification.isRead) Lx.Surface else Lx.OrangeTint
        ),
        shape = RoundedCornerShape(Lx.Radius.button)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
        ) {
            // Notification Icon
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .background(Lx.Orange, CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = "🍕",
                    fontSize = Lx.FontSize.title
                )
            }

            Spacer(modifier = Modifier.width(12.dp))

            Column(
                modifier = Modifier.weight(1f)
            ) {
                Text(
                    text = notification.title,
                    fontSize = Lx.FontSize.subheadline,
                    fontWeight = FontWeight.SemiBold,
                    color = Lx.Text
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = notification.message,
                    fontSize = Lx.FontSize.footnote,
                    color = Lx.TextSecondary,
                    maxLines = 2
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = notification.time,
                    fontSize = Lx.FontSize.caption,
                    color = Lx.TextSecondary
                )
            }
        }
    }
}

// Sample data removed - NotificationScreen shows proper empty state
// when notifications list is empty (which is current production behavior
// until backend /api/notifications endpoint is implemented)