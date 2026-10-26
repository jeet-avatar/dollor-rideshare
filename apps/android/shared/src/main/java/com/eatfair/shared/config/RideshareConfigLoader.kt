package com.eatfair.shared.config

import android.content.Context
import android.util.Log
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

/**
 * Loads fees, bidding presets and support details from GET /api/config/rideshare so a policy change
 * reaches every app without a release. The last good response is cached on the device and applied
 * immediately on the next launch, so the app also works offline.
 */
object RideshareConfigLoader {
    private const val TAG = "RideshareConfig"
    private const val PREFS = "rideshare_config"
    private const val KEY_JSON = "json"

    private val client = OkHttpClient.Builder()
        .callTimeout(10, TimeUnit.SECONDS)
        .build()

    fun load(context: Context) {
        val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.getString(KEY_JSON, null)?.let { applyJson(it) }

        thread(name = "rideshare-config") {
            runCatching {
                val request = Request.Builder().url("${AppConfig.apiBaseUrl}/config/rideshare").build()
                client.newCall(request).execute().use { response ->
                    check(response.isSuccessful) { "HTTP ${response.code}" }
                    val body = response.body?.string().orEmpty()
                    applyJson(body)
                    prefs.edit().putString(KEY_JSON, body).apply()
                }
            }.onFailure { Log.w(TAG, "Using cached/default rideshare config: ${it.message}") }
        }
    }

    private fun applyJson(text: String) {
        runCatching { AppConfig.Rideshare.apply(JSONObject(text)) }
            .onFailure { Log.w(TAG, "Ignoring unreadable rideshare config: ${it.message}") }
    }
}
