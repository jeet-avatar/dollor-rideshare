import Foundation
import UserNotifications
import FirebaseMessaging
import os
#if canImport(UIKit)
import UIKit
#endif

private let notificationLogger = Logger(subsystem: "ai.dollor.shared", category: "NotificationManager")

/// Shared Notification Manager for all EatFair apps
public class NotificationManager: NSObject, ObservableObject {
    public static let shared = NotificationManager()

    @Published public var fcmToken: String?
    @Published public var isAuthorized = false
    @Published public var pendingNotifications: [UNNotification] = []

    public override init() {
        super.init()
    }

    // MARK: - Authorization

    /// Request notification authorization from the user
    public func requestAuthorization(completion: @escaping (Bool) -> Void = { _ in }) {
        let options: UNAuthorizationOptions = [.alert, .badge, .sound]

        UNUserNotificationCenter.current().requestAuthorization(options: options) { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.isAuthorized = granted

                if let error = error {
                    notificationLogger.error("Authorization error: \(error.localizedDescription)")
                }

                if granted {
                    self?.registerForRemoteNotifications()
                }

                completion(granted)
            }
        }
    }

    /// Launch-time hook: never prompts. If the user already granted permission in an earlier session,
    /// re-register with APNs so push keeps working.
    public func registerIfAlreadyAuthorized() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let status = settings.authorizationStatus
            guard status == .authorized || status == .provisional || status == .ephemeral else { return }
            DispatchQueue.main.async {
                self?.isAuthorized = true
                self?.registerForRemoteNotifications()
            }
        }
    }

    /// Contextual prompt (e.g. after the first ride request, or when a driver goes online).
    /// Shows the system dialog only while the status is still undetermined.
    public func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            if settings.authorizationStatus == .notDetermined {
                self?.requestAuthorization()
            } else {
                self?.registerIfAlreadyAuthorized()
            }
        }
    }

    /// Register for remote notifications (call after authorization)
    public func registerForRemoteNotifications() {
        #if canImport(UIKit)
        DispatchQueue.main.async {
            #if !targetEnvironment(simulator)
            UIApplication.shared.registerForRemoteNotifications()
            #endif
        }
        #endif
    }

    /// Check current authorization status
    public func checkAuthorizationStatus(completion: @escaping (UNAuthorizationStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.isAuthorized = settings.authorizationStatus == .authorized
                completion(settings.authorizationStatus)
            }
        }
    }

    // MARK: - FCM Token Management

    /// Update FCM token (called by AppDelegate)
    public func updateFCMToken(_ token: String) {
        self.fcmToken = token
        notificationLogger.debug("FCM Token updated")
    }

    /// Get current FCM token
    public func getFCMToken(completion: @escaping (String?) -> Void) {
        Messaging.messaging().token { token, error in
            if let error = error {
                notificationLogger.error("Error fetching FCM token: \(error.localizedDescription)")
                completion(nil)
            } else {
                self.fcmToken = token
                completion(token)
            }
        }
    }

    // MARK: - Badge Management

    /// Clear badge count
    public func clearBadge() {
        #if canImport(UIKit)
        DispatchQueue.main.async {
            UIApplication.shared.applicationIconBadgeNumber = 0
        }
        #endif
    }

    /// Set badge count
    public func setBadge(_ count: Int) {
        #if canImport(UIKit)
        DispatchQueue.main.async {
            UIApplication.shared.applicationIconBadgeNumber = count
        }
        #endif
    }

    // MARK: - Local Notifications

    /// Schedule a local notification
    public func scheduleLocalNotification(
        title: String,
        body: String,
        identifier: String,
        timeInterval: TimeInterval = 1,
        userInfo: [String: Any] = [:]
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                notificationLogger.error("Failed to schedule notification: \(error.localizedDescription)")
            }
        }
    }

    /// Cancel a scheduled notification
    public func cancelNotification(identifier: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    /// Cancel all pending notifications
    public func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}

// MARK: - Notification Types

public enum NotificationType: String {
    case newOrder = "new_order"
    case orderStatusUpdate = "order_status"
    case orderReady = "order_ready"
    case driverAssigned = "driver_assigned"
    case orderPickedUp = "order_picked_up"
    case orderDelivered = "order_delivered"
    case orderCancelled = "order_cancelled"
    case promotion = "promotion"
    case system = "system"
    // Driver verification notifications
    case driverApproved = "driver_approved"
    case driverRejected = "driver_rejected"
    // Vendor verification notifications
    case vendorVerified = "vendor_verified"
    case vendorRejected = "vendor_rejected"
    // Rideshare notifications
    case driverArrived = "driver_arrived"
    case rideStarted = "ride_started"
    case rideCompleted = "ride_completed"
    case rideCancelled = "ride_cancelled"
    case newRideRequest = "new_ride_request"
    // Rideshare bidding notifications
    case newBid = "new_bid"
    case bidAccepted = "bid_accepted"
    case bidRejected = "bid_rejected"
    case counterOffer = "counter_offer"
    case driverCounter = "driver_counter"
    case counterAccepted = "counter_accepted"
    case driverEnRoute = "driver_en_route"
    case paymentProcessed = "payment_processed"
    case rideExpired = "ride_expired"

    public var soundName: String {
        switch self {
        case .newOrder:
            return "new_order.wav"
        case .orderReady:
            return "order_ready.wav"
        case .driverApproved, .vendorVerified, .rideCompleted:
            return "success.wav"
        case .driverArrived, .rideStarted, .newRideRequest, .driverEnRoute:
            return "new_order.wav"
        case .newBid, .bidAccepted, .counterOffer, .driverCounter, .counterAccepted:
            return "new_order.wav"
        case .paymentProcessed:
            return "success.wav"
        case .bidRejected:
            return "default"
        default:
            return "default"
        }
    }
}

// MARK: - Notification Payload

public struct NotificationPayload {
    public let type: NotificationType
    public let title: String
    public let body: String
    public let orderId: String?
    public let rideRequestId: String?
    public let data: [String: Any]

    public init?(from userInfo: [AnyHashable: Any]) {
        guard let typeString = userInfo["type"] as? String,
              let type = NotificationType(rawValue: typeString) else {
            // Default to system notification if type not specified
            self.type = .system
            self.title = userInfo["title"] as? String ?? "EatFair"
            self.body = userInfo["body"] as? String ?? ""
            self.orderId = userInfo["orderId"] as? String
            self.rideRequestId = userInfo["ride_request_id"] as? String
            self.data = userInfo as? [String: Any] ?? [:]
            return
        }

        self.type = type
        self.title = userInfo["title"] as? String ?? ""
        self.body = userInfo["body"] as? String ?? ""
        self.orderId = userInfo["orderId"] as? String
        self.rideRequestId = userInfo["ride_request_id"] as? String
        self.data = userInfo as? [String: Any] ?? [:]
    }
}

// MARK: - UIApplication Extension for registration
#if canImport(UIKit)
import UIKit

extension UIApplication {
    /// Check if push notifications are enabled
    public static func arePushNotificationsEnabled(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                completion(settings.authorizationStatus == .authorized)
            }
        }
    }
}
#endif
