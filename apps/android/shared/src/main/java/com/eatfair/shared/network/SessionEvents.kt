package com.eatfair.shared.network

import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow

/**
 * Fired when the server rejected the stored token and it could not be refreshed, so the
 * stored session was cleared. Each app collects this to show a message and route to login.
 */
object SessionEvents {
    const val MESSAGE = "Session expired, please sign in again."

    private val _expired = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    val expired: SharedFlow<Unit> = _expired.asSharedFlow()

    fun notifyExpired() {
        _expired.tryEmit(Unit)
    }
}
