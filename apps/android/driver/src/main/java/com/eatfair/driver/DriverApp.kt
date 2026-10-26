package com.eatfair.driver

import android.app.Application
import android.util.Log
import com.eatfair.shared.config.AppConfig
import dagger.hilt.android.HiltAndroidApp

@HiltAndroidApp
class DriverApp : Application() {
    override fun onCreate() {
        super.onCreate()
        com.eatfair.shared.network.ApiTiming.init(this)

        // Initialize AppConfig with production settings
        AppConfig.initialize(
            apiBaseUrl = BuildConfig.API_BASE_URL,
            isProduction = BuildConfig.IS_PRODUCTION
        )
        Log.d("DriverApp", "Driver App initialized - PRODUCTION")
        Log.d("DriverApp", "API_BASE_URL: ${BuildConfig.API_BASE_URL}")
    }
}
