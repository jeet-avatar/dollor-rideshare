package com.eatfair.shared.network

import android.content.Context
import android.content.pm.ApplicationInfo
import android.util.Log
import okhttp3.Interceptor
import okhttp3.Response

/**
 * Debug-only API timing log: one line per call ("METHOD /path -> status 123ms"), tag `ApiTiming`.
 * Never logs headers or bodies (those contain tokens and passwords), and does nothing in release builds.
 */
object ApiTiming : Interceptor {
    @Volatile
    var enabled: Boolean = false

    /** Call once from `Application.onCreate`. */
    fun init(context: Context) {
        enabled = (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
    }

    override fun intercept(chain: Interceptor.Chain): Response {
        if (!enabled) return chain.proceed(chain.request())
        val request = chain.request()
        val started = System.nanoTime()
        return try {
            val response = chain.proceed(request)
            log(request.method, request.url.encodedPath, response.code.toString(), started)
            response
        } catch (e: Exception) {
            log(request.method, request.url.encodedPath, "ERR ${e.javaClass.simpleName}", started)
            throw e
        }
    }

    private fun log(method: String, path: String, outcome: String, startedNanos: Long) {
        val ms = (System.nanoTime() - startedNanos) / 1_000_000
        Log.d("ApiTiming", "$method $path -> $outcome ${ms}ms")
    }
}
