package com.eatfair.shared.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import com.eatfair.shared.model.rideshare.RideChatMessage
import com.google.gson.annotations.SerializedName
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * Report / block safeguards for ride chat (Google Play UGC policy, mirrors the iOS ChatSafetyView).
 * One [ChatSafetyState] per chat screen. It owns a single dialog slot (report form OR block
 * confirmation, never both) and shows feedback through a snackbar, so a chat screen never stacks dialogs.
 *
 * API: POST /api/chat/report, POST|DELETE /api/chat/block, GET /api/chat/blocks.
 */
object ChatSafety {
    const val UNAVAILABLE_MESSAGE = "Reporting is temporarily unavailable, email support@dollor.ai"
    private const val GENERIC_ERROR = "Something went wrong. Please try again."

    /** Maps a failed HTTP response to the exception shown to the user (404/405 = older backend). */
    fun httpError(code: Int, errorBody: String?): Throwable {
        if (code == 404 || code == 405) return ChatSafetyUnavailableException()
        val detail = runCatching {
            org.json.JSONObject(errorBody.orEmpty()).optString("detail").ifBlank { null }
        }.getOrNull()
        return Exception(detail ?: GENERIC_ERROR)
    }
}

class ChatSafetyUnavailableException : Exception(ChatSafety.UNAVAILABLE_MESSAGE)

enum class ChatReportReason(val wire: String, val label: String) {
    HARASSMENT("harassment", "Harassment"),
    INAPPROPRIATE("inappropriate", "Inappropriate content"),
    SPAM("spam", "Spam"),
    SAFETY("safety", "Safety concern"),
    OTHER("other", "Other")
}

/** POST /api/chat/report */
data class ChatReportRequest(
    @SerializedName("ride_request_id") val rideRequestId: Int,
    @SerializedName("message_id") val messageId: Int? = null,
    @SerializedName("reason") val reason: String,
    @SerializedName("details") val details: String
)

/** POST|DELETE /api/chat/block */
data class ChatBlockRequest(
    @SerializedName("blocked_user_type") val blockedUserType: String,
    @SerializedName("blocked_user_id") val blockedUserId: Int
)

data class ChatBlockEntry(
    @SerializedName("blocked_user_type") val blockedUserType: String,
    @SerializedName("blocked_user_id") val blockedUserId: Int,
    @SerializedName("created_at") val createdAt: String? = null
)

/** GET /api/chat/blocks */
data class ChatBlocksResponse(
    @SerializedName("blocks") val blocks: List<ChatBlockEntry> = emptyList()
)

/** Network operations for one chat, bound to its ride and the signed-in role by the caller. */
interface ChatSafetyOps {
    suspend fun report(reason: String, details: String): Result<Unit>
    suspend fun setBlocked(block: Boolean, userId: Int): Result<Unit>
    suspend fun fetchBlocks(): Result<List<ChatBlockEntry>>
}

enum class ChatSafetyDialog { REPORT, BLOCK_CONFIRM }

@Stable
class ChatSafetyState(
    private val scope: CoroutineScope,
    private val ops: ChatSafetyOps,
    /** "driver" or "customer": the OTHER participant in this chat. */
    private val otherUserType: String,
    initialUserId: Int?,
    val otherName: String
) {
    val snackbarHostState = SnackbarHostState()
    var dialog by mutableStateOf<ChatSafetyDialog?>(null)
    var isBlocked by mutableStateOf(false)
        private set
    var isWorking by mutableStateOf(false)
        private set
    private var otherUserId: Int? = initialUserId

    /** Fallback when the other user's id was not passed in: learn it from their messages. */
    fun learnOtherUser(messages: List<RideChatMessage>) {
        if (otherUserId != null) return
        val theirs = messages.firstOrNull { it.senderType == otherUserType } ?: return
        otherUserId = theirs.senderId
        refreshBlocks()
    }

    fun refreshBlocks() {
        val id = otherUserId ?: return
        scope.launch {
            ops.fetchBlocks().onSuccess { blocks ->
                isBlocked = blocks.any { it.blockedUserType == otherUserType && it.blockedUserId == id }
            }
        }
    }

    fun submitReport(reason: ChatReportReason, details: String) {
        isWorking = true
        scope.launch {
            val result = ops.report(reason.wire, details.trim())
            isWorking = false
            dialog = null
            result
                .onSuccess { snackbarHostState.showSnackbar("Thanks. Your report was sent and our team will review it.") }
                .onFailure { snackbarHostState.showSnackbar(it.message ?: ChatSafety.UNAVAILABLE_MESSAGE) }
        }
    }

    fun changeBlock(block: Boolean) {
        val id = otherUserId
        if (id == null) {
            dialog = null
            scope.launch { snackbarHostState.showSnackbar("You can block $otherName once they have sent a message.") }
            return
        }
        isWorking = true
        scope.launch {
            val result = ops.setBlocked(block, id)
            isWorking = false
            dialog = null
            result
                .onSuccess {
                    isBlocked = block
                    snackbarHostState.showSnackbar(
                        if (block) "$otherName is blocked. You won't receive their messages." else "$otherName is unblocked."
                    )
                }
                .onFailure { snackbarHostState.showSnackbar(it.message ?: ChatSafety.UNAVAILABLE_MESSAGE) }
        }
    }
}

@Composable
fun rememberChatSafetyState(
    rideRequestId: Int,
    otherUserType: String,
    otherUserId: Int?,
    otherName: String,
    ops: ChatSafetyOps
): ChatSafetyState {
    val scope = rememberCoroutineScope()
    return remember(rideRequestId) { ChatSafetyState(scope, ops, otherUserType, otherUserId, otherName) }
}

/** Overflow (three-dot) menu for a chat top bar. */
@Composable
fun ChatSafetyMenu(state: ChatSafetyState, tint: androidx.compose.ui.graphics.Color = Lx.Orange) {
    var expanded by remember { mutableStateOf(false) }
    IconButton(onClick = { expanded = true }) {
        Icon(Icons.Default.MoreVert, contentDescription = "Chat options", tint = tint)
    }
    DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
        DropdownMenuItem(
            text = { Text("Report") },
            onClick = {
                expanded = false
                state.dialog = ChatSafetyDialog.REPORT
            }
        )
        if (state.isBlocked) {
            DropdownMenuItem(
                text = { Text("Unblock") },
                onClick = {
                    expanded = false
                    state.changeBlock(false)
                }
            )
        } else {
            DropdownMenuItem(
                text = { Text("Block user", color = Lx.Error) },
                onClick = {
                    expanded = false
                    state.dialog = ChatSafetyDialog.BLOCK_CONFIRM
                }
            )
        }
    }
}

/** Replaces the message input while the other person is blocked. */
@Composable
fun ChatBlockedBar(state: ChatSafetyState) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text("You blocked ${state.otherName}.", style = MaterialTheme.typography.bodyMedium)
        TextButton(onClick = { state.changeBlock(false) }, enabled = !state.isWorking) {
            Text("Unblock", color = Lx.Orange)
        }
    }
}

/** Renders the single active report/block dialog. Call once per chat screen. */
@Composable
fun ChatSafetyDialogs(state: ChatSafetyState) {
    when (state.dialog) {
        ChatSafetyDialog.REPORT -> ReportDialog(state)
        ChatSafetyDialog.BLOCK_CONFIRM -> BlockConfirmDialog(state)
        null -> Unit
    }
}

@Composable
private fun ReportDialog(state: ChatSafetyState) {
    var reason by remember { mutableStateOf(ChatReportReason.HARASSMENT) }
    var details by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = { if (!state.isWorking) state.dialog = null },
        title = { Text("Report ${state.otherName}") },
        text = {
            Column {
                Column(Modifier.selectableGroup()) {
                    ChatReportReason.values().forEach { option ->
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .selectable(selected = reason == option, role = Role.RadioButton, onClick = { reason = option }),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            RadioButton(selected = reason == option, onClick = null)
                            Text(option.label, modifier = Modifier.padding(start = 12.dp, top = 8.dp, bottom = 8.dp))
                        }
                    }
                }
                Spacer(Modifier.height(8.dp))
                OutlinedTextField(
                    value = details,
                    onValueChange = { details = it },
                    label = { Text("Details (optional)") },
                    minLines = 2,
                    maxLines = 4,
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(Modifier.height(8.dp))
                Text(
                    "If someone is in immediate danger, call 911.",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        },
        confirmButton = {
            TextButton(onClick = { state.submitReport(reason, details) }, enabled = !state.isWorking) {
                Text(if (state.isWorking) "Sending..." else "Submit", color = Lx.Orange)
            }
        },
        dismissButton = {
            TextButton(onClick = { state.dialog = null }, enabled = !state.isWorking) { Text("Cancel") }
        }
    )
}

@Composable
private fun BlockConfirmDialog(state: ChatSafetyState) {
    AlertDialog(
        onDismissRequest = { if (!state.isWorking) state.dialog = null },
        title = { Text("Block ${state.otherName}?") },
        text = {
            Text("You will no longer receive messages from ${state.otherName}. You can unblock them later from this chat.")
        },
        confirmButton = {
            TextButton(onClick = { state.changeBlock(true) }, enabled = !state.isWorking) {
                Text(if (state.isWorking) "Blocking..." else "Block", color = Lx.Error)
            }
        },
        dismissButton = {
            TextButton(onClick = { state.dialog = null }, enabled = !state.isWorking) { Text("Cancel") }
        }
    )
}
