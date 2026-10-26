package com.eatfair.shared.di

import android.content.Context
import com.eatfair.shared.config.AppConfig
import com.eatfair.shared.data.local.SecureStorage
import com.eatfair.shared.data.remote.DollorApiService
import com.eatfair.shared.data.repository.DollorRepository
import com.eatfair.shared.network.TokenRefreshInterceptor
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.ktx.auth
import com.google.firebase.ktx.Firebase
import com.google.firebase.storage.FirebaseStorage
import com.google.firebase.storage.ktx.storage
import com.google.gson.GsonBuilder
import android.content.pm.ApplicationInfo
import com.eatfair.shared.network.ApiTiming
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import java.util.concurrent.TimeUnit
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object SharedModule {

    @Provides
    @Singleton
    fun provideFirebaseAuth(): FirebaseAuth = Firebase.auth

    // REMOVED: provideFirebaseFirestore() - Using API-only (PostgreSQL backend)
    // Firestore was causing dual-database confusion. All data now flows through P2P API.
    // Kept: Firebase Auth (for Google Sign-In), Firebase Storage (for document uploads), FCM (for push notifications)

    @Provides
    @Singleton
    fun provideFirebaseStorage(): FirebaseStorage = Firebase.storage

    @Provides
    @Singleton
    fun provideTokenRefreshInterceptor(secureStorage: SecureStorage): TokenRefreshInterceptor {
        return TokenRefreshInterceptor(secureStorage)
    }

    @Provides
    @Singleton
    fun provideOkHttpClient(
        tokenRefreshInterceptor: TokenRefreshInterceptor,
        @ApplicationContext context: Context
    ): OkHttpClient {
        // Bodies contain passwords and auth tokens, so they are logged only in debuggable builds.
        val debuggable = (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        val loggingInterceptor = HttpLoggingInterceptor().apply {
            level = if (debuggable) HttpLoggingInterceptor.Level.BASIC else HttpLoggingInterceptor.Level.NONE
        }

        // PRODUCTION - Certificate pinning can be added for api.dollor.ai if needed

        return OkHttpClient.Builder()
            .addInterceptor(ApiTiming)
            .addInterceptor(loggingInterceptor)
            .addInterceptor(tokenRefreshInterceptor) // Handle 401 token expiration
            .connectTimeout(AppConfig.API_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .readTimeout(AppConfig.API_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .writeTimeout(AppConfig.API_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .build()
    }

    @Provides
    @Singleton
    fun provideRetrofit(okHttpClient: OkHttpClient): Retrofit {
        val gson = GsonBuilder()
            .setLenient()
            .create()

        // API_BASE_URL is set via AppConfig.initialize() called from Application class
        // Production: https://api.dollor.ai/api
        return Retrofit.Builder()
            .baseUrl(AppConfig.API_BASE_URL + "/")
            .client(okHttpClient)
            .addConverterFactory(GsonConverterFactory.create(gson))
            .build()
    }

    @Provides
    @Singleton
    fun provideDollorApiService(retrofit: Retrofit): DollorApiService {
        return retrofit.create(DollorApiService::class.java)
    }

    @Provides
    @Singleton
    fun provideSecureStorage(@ApplicationContext context: Context): SecureStorage {
        return SecureStorage(context)
    }

    @Provides
    @Singleton
    fun provideDollorRepository(
        apiService: DollorApiService,
        secureStorage: SecureStorage
    ): DollorRepository {
        return DollorRepository(apiService, secureStorage)
    }
}
