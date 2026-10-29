package com.eatfair.shared.notifications

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.RingtoneManager
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import com.eatfair.shared.R
import com.eatfair.shared.data.local.SecureStorage
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject

/**
 * Firebase Cloud Messaging Service for Dollor.ai
 *
 * Handles incoming push notifications for:
 * - Order updates (new order, accepted, ready, out for delivery, delivered)
 * - Ride updates (driver accepted, arriving, ride started, completed)
 * - Driver notifications (new delivery/ride available, earnings updated)
 * - Restaurant notifications (new order, driver assigned)
 *
 * To use in each app, extend this class and register in AndroidManifest.xml:
 *
 * <service
 *     android:name=".YourFirebaseMessagingService"
 *     android:exported="false">
 *     <intent-filter>
 *         <action android:name="com.google.firebase.MESSAGING_EVENT" />
 *     </intent-filter>
 * </service>
 */
@AndroidEntryPoint
abstract class DollorFirebaseMessagingService : FirebaseMessagingService() {

    @Inject
    lateinit var secureStorage: SecureStorage

    companion object {
        private const val TAG = "DollorFCM"

        // Notification Channel IDs
        const val CHANNEL_ORDERS = "dollor_orders"
        const val CHANNEL_RIDES = "dollor_rides"
        const val CHANNEL_DELIVERIES = "dollor_deliveries"
        const val CHANNEL_GENERAL = "dollor_general"
        const val CHANNEL_PROMOTIONS = "dollor_promotions"

        // Notification types from backend
        const val TYPE_ORDER_PLACED = "ORDER_PLACED"
        const val TYPE_ORDER_CONFIRMED = "ORDER_CONFIRMED"
        const val TYPE_ORDER_PREPARING = "ORDER_PREPARING"
        const val TYPE_ORDER_READY = "ORDER_READY"
        const val TYPE_ORDER_PICKED_UP = "ORDER_PICKED_UP"
        const val TYPE_ORDER_DELIVERED = "ORDER_DELIVERED"
        const val TYPE_ORDER_CANCELLED = "ORDER_CANCELLED"

        const val TYPE_RIDE_REQUESTED = "RIDE_REQUESTED"
        const val TYPE_RIDE_ACCEPTED = "RIDE_ACCEPTED"
        const val TYPE_DRIVER_ARRIVING = "DRIVER_ARRIVING"
        const val TYPE_RIDE_STARTED = "RIDE_STARTED"
        const val TYPE_RIDE_COMPLETED = "RIDE_COMPLETED"
        const val TYPE_RIDE_CANCELLED = "RIDE_CANCELLED"

        const val TYPE_NEW_DELIVERY = "NEW_DELIVERY_AVAILABLE"
        const val TYPE_NEW_RIDE_REQUEST = "NEW_RIDE_REQUEST"
        const val TYPE_EARNINGS_UPDATED = "EARNINGS_UPDATED"

        const val TYPE_NEW_ORDER = "NEW_ORDER"
        const val TYPE_DRIVER_ASSIGNED = "ORDER_ACCEPTED_BY_DRIVER"

        const val TYPE_PROMOTION = "PROMOTION"
        const val TYPE_GENERAL = "GENERAL"
    }

    /**
     * Called when FCM token is refreshed
     * Override to send token to your backend
     */
    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.d(TAG, "FCM Token refreshed: ${token.take(20)}...")

        // Save token locally
        saveFcmToken(token)

        // Send to backend if user is logged in
        sendTokenToServer(token)
    }

    /**
     * Called when a message is received
     */
    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        super.onMessageReceived(remoteMessage)

        Log.d(TAG, "Message received from: ${remoteMessage.from}")

        // Check if message contains data payload
        remoteMessage.data.isNotEmpty().let {
            Log.d(TAG, "Message data payload: ${remoteMessage.data}")
            handleDataMessage(remoteMessage.data)
        }

        // Check if message contains notification payload
        remoteMessage.notification?.let {
            Log.d(TAG, "Message notification body: ${it.body}")
            showNotification(it.title ?: "Dollor.ai", it.body ?: "")
        }
    }

    /**
     * Handle data messages from backend
     */
    private fun handleDataMessage(data: Map<String, String>) {
        val type = data["type"] ?: TYPE_GENERAL
        val title = data["title"] ?: "Dollor.ai"
        val body = data["body"] ?: data["message"] ?: ""
        val orderId = data["order_id"]
        val rideId = data["ride_id"]
        val deliveryId = data["delivery_id"]

        val channelId = when (type) {
            TYPE_ORDER_PLACED, TYPE_ORDER_CONFIRMED, TYPE_ORDER_PREPARING,
            TYPE_ORDER_READY, TYPE_ORDER_PICKED_UP, TYPE_ORDER_DELIVERED,
            TYPE_ORDER_CANCELLED, TYPE_NEW_ORDER, TYPE_DRIVER_ASSIGNED -> CHANNEL_ORDERS

            TYPE_RIDE_REQUESTED, TYPE_RIDE_ACCEPTED, TYPE_DRIVER_ARRIVING,
            TYPE_RIDE_STARTED, TYPE_RIDE_COMPLETED, TYPE_RIDE_CANCELLED -> CHANNEL_RIDES

            TYPE_NEW_DELIVERY, TYPE_NEW_RIDE_REQUEST, TYPE_EARNINGS_UPDATED -> CHANNEL_DELIVERIES

            TYPE_PROMOTION -> CHANNEL_PROMOTIONS

            else -> CHANNEL_GENERAL
        }

        showNotification(
            title = title,
            body = body,
            channelId = channelId,
            data = data
        )

        // Call app-specific handler
        onNotificationReceived(type, data)
    }

    /**
     * Override this method to handle notifications in your app
     */
    abstract fun onNotificationReceived(type: String, data: Map<String, String>)

    /**
     * Override this method to get the intent for notification tap
     */
    abstract fun getNotificationIntent(data: Map<String, String>): Intent

    /**
     * Show notification to user
     */
    protected fun showNotification(
        title: String,
        body: String,
        channelId: String = CHANNEL_GENERAL,
        data: Map<String, String> = emptyMap()
    ) {
        val intent = getNotificationIntent(data)
        intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)

        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
        )

        val defaultSoundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)

        val notificationBuilder = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.drawable.ic_notification) // You need to create this
            .setContentTitle(title)
            .setContentText(body)
            .setAutoCancel(true)
            .setSound(defaultSoundUri)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_HIGH)

        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // Create notification channel for Android O+
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            createNotificationChannels(notificationManager)
        }

        // Use unique notification ID based on timestamp
        val notificationId = System.currentTimeMillis().toInt()
        notificationManager.notify(notificationId, notificationBuilder.build())
    }

    /**
     * Create notification channels for Android O+
     */
    private fun createNotificationChannels(notificationManager: NotificationManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channels = listOf(
                NotificationChannel(
                    CHANNEL_ORDERS,
                    "Booking Updates",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Updates about your bookings"
                },
                NotificationChannel(
                    CHANNEL_RIDES,
                    "Ride Updates",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Updates about your rides"
                },
                NotificationChannel(
                    CHANNEL_DELIVERIES,
                    "Ride Requests",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "New ride requests for drivers"
                },
                NotificationChannel(
                    CHANNEL_PROMOTIONS,
                    "Promotions",
                    NotificationManager.IMPORTANCE_DEFAULT
                ).apply {
                    description = "Announcements and offers"
                },
                NotificationChannel(
                    CHANNEL_GENERAL,
                    "General",
                    NotificationManager.IMPORTANCE_DEFAULT
                ).apply {
                    description = "General notifications"
                }
            )

            channels.forEach { channel ->
                notificationManager.createNotificationChannel(channel)
            }
        }
    }

    /**
     * Save FCM token locally
     */
    private fun saveFcmToken(token: String) {
        secureStorage.fcmToken = token
    }

    /**
     * Send FCM token to backend
     * Override this method to implement token registration with your API
     */
    protected open fun sendTokenToServer(token: String) {
        // Default implementation - override in app-specific service
        Log.d(TAG, "sendTokenToServer should be overridden to send token to backend")
    }
}

/**
 * Extension property to store FCM token in SecureStorage
 */
var SecureStorage.fcmToken: String?
    get() = getString("fcm_token")
    set(value) = saveString("fcm_token", value ?: "")

private fun SecureStorage.getString(key: String): String? {
    // Implementation depends on your SecureStorage class
    return null
}

private fun SecureStorage.saveString(key: String, value: String) {
    // Implementation depends on your SecureStorage class
}
