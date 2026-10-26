package com.eatfair.app.ui.help

import com.eatfair.shared.ui.Lx
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.eatfair.app.data.CustomerRideshareApiService
import com.eatfair.app.ui.theme.BrandGreen
import kotlinx.coroutines.launch

private data class SupportMessage(val id: Long, val text: String, val fromUser: Boolean)

private val SUGGESTIONS = listOf(
    "How do I cancel a ride?",
    "How does pricing work?",
    "I was charged incorrectly",
    "I left something in the car"
)

/** Live support chat (iOS LiveChatView parity) backed by POST /api/support/chat. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SupportChatScreen(onBackClick: () -> Unit) {
    var messages by remember {
        mutableStateOf(
            listOf(SupportMessage(0, "Hi! I'm the Dollor.ai support assistant. How can I help you today?", false))
        )
    }
    var draft by remember { mutableStateOf("") }
    var sending by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()
    LaunchedEffect(messages.size) { listState.animateScrollToItem(messages.lastIndex) }

    fun send(text: String) {
        val trimmed = text.trim()
        if (trimmed.isEmpty() || sending) return
        messages = messages + SupportMessage(System.nanoTime(), trimmed, true)
        draft = ""
        sending = true
        scope.launch {
            val reply = CustomerRideshareApiService.sendSupportChat(trimmed)
                .getOrElse { "Sorry, I couldn't process that. Please try again, or email support@dollor.ai." }
            messages = messages + SupportMessage(System.nanoTime(), reply, false)
            sending = false
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Live Support", fontWeight = FontWeight.SemiBold) },
                navigationIcon = {
                    IconButton(onClick = onBackClick) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") }
                }
            )
        }
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding).imePadding()) {
            LazyColumn(
                state = listState,
                modifier = Modifier.weight(1f).fillMaxWidth(),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                items(messages, key = { it.id }) { m ->
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = if (m.fromUser) Arrangement.End else Arrangement.Start) {
                        Text(
                            m.text,
                            color = if (m.fromUser) Color.White else Lx.Text,
                            modifier = Modifier
                                .widthIn(max = 280.dp)
                                .background(
                                    if (m.fromUser) Lx.Orange else Lx.Surface2,
                                    RoundedCornerShape(Lx.Radius.card)
                                )
                                .padding(horizontal = 14.dp, vertical = 10.dp)
                        )
                    }
                }
                if (sending) item { Text("Typing…", color = Lx.TextSecondary) }
            }
            if (messages.size == 1) {
                Row(
                    Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 12.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    SUGGESTIONS.forEach { s -> SuggestionChip(onClick = { send(s) }, label = { Text(s) }) }
                }
            }
            Row(Modifier.fillMaxWidth().padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                OutlinedTextField(
                    value = draft,
                    onValueChange = { draft = it },
                    placeholder = { Text("Type your question…") },
                    modifier = Modifier.weight(1f),
                    shape = RoundedCornerShape(Lx.Radius.sheet),
                    maxLines = 3
                )
                IconButton(onClick = { send(draft) }, enabled = draft.isNotBlank() && !sending) {
                    Icon(Icons.AutoMirrored.Filled.Send, "Send", tint = BrandGreen)
                }
            }
        }
    }
}
