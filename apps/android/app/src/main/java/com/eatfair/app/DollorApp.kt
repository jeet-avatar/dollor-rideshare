package com.eatfair.app

import android.app.Application
import android.util.Log
import com.eatfair.app.data.CustomerRideshareApiService
import com.eatfair.shared.config.AppConfig
import com.eatfair.shared.data.local.SecureStorage
import dagger.hilt.android.HiltAndroidApp
import dagger.hilt.android.EntryPointAccessors
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

/**
 * Dollor.ai Customer Application
 *
 * Main application class that initializes:
 * - Hilt dependency injection
 * - AppConfig with environment settings
 * - CustomerRideshareApiService with SecureStorage (matches iOS P2PAPIService.init pattern)
 */
@HiltAndroidApp
class DollorApp : Application() {

    /**
     * Entry point for accessing SecureStorage in Application
     * Matches iOS pattern where SecureStorage.shared is available globally
     */
    @EntryPoint
    @InstallIn(SingletonComponent::class)
    interface SecureStorageEntryPoint {
        fun secureStorage(): SecureStorage
    }

    override fun onCreate() {
        super.onCreate()
        com.eatfair.shared.network.ApiTiming.init(this)

        // Initialize AppConfig with BuildConfig values
        // Production build only - no staging
        AppConfig.initialize(
            apiBaseUrl = BuildConfig.API_BASE_URL,
            isProduction = BuildConfig.IS_PRODUCTION
        )

        com.eatfair.shared.config.RideshareConfigLoader.load(this)

        // Initialize CustomerRideshareApiService with SecureStorage
        // Matches iOS pattern: P2PAPIService.shared.init() accesses SecureStorage.shared
        val entryPoint = EntryPointAccessors.fromApplication(this, SecureStorageEntryPoint::class.java)
        CustomerRideshareApiService.initialize(entryPoint.secureStorage())

        Log.d("DollorApp", "Environment: PRODUCTION")
        Log.d("DollorApp", "API_BASE_URL: ${BuildConfig.API_BASE_URL}")
        Log.d("DollorApp", "CustomerRideshareApiService initialized with SecureStorage")
    }
}
