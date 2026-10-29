//
//  eatffairdeliveryApp.swift
//  eatffairdelivery
//
//  Created by Jithesh Manoharan on 11/26/25.
//

import SwiftUI
import FirebaseCore
import FirebaseMessaging
import GoogleSignIn
import UserNotifications
import EatFairShared
import GoogleMaps
import GooglePlaces
import os.log

private let deliveryLogger = Logger(subsystem: "com.dollor.delivery", category: "DeliveryApp")

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Configure Google Maps SDK
        GMSServices.provideAPIKey(GoogleMapsConfig.currentKey)
        GMSPlacesClient.provideAPIKey(GoogleMapsConfig.currentKey)

        // Issue #13 Fixed: Configure Firebase with error handling
        configureFirebase()

        // Load app configuration from Firebase
        AppConfig.shared.fetchConfig()

        // Setup push notifications
        setupPushNotifications(application)

        return true
    }

    /// Issue #13 Fixed: Firebase configuration with proper error handling
    private func configureFirebase() {
        // Check if Firebase is already configured (prevents double configuration crash)
        guard FirebaseApp.app() == nil else {
            deliveryLogger.info("Firebase already configured, skipping")
            return
        }

        // Verify GoogleService-Info.plist exists
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            deliveryLogger.error("GoogleService-Info.plist not found!")
            // App can still function without Firebase (no push notifications)
            return
        }

        // Configure Firebase (doesn't throw - checked via FirebaseApp.app() above)
        FirebaseApp.configure()
        deliveryLogger.info("Firebase configured successfully")
    }

    // MARK: - Push Notification Setup

    private func setupPushNotifications(_ application: UIApplication) {
        // Set delegates
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self

        // No permission prompt at launch: it is requested when the driver first goes online.
        NotificationManager.shared.registerIfAlreadyAuthorized()
    }

    // MARK: - Remote Notification Registration

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        deliveryLogger.info("APNs token received: \(tokenString.prefix(20))...")
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        deliveryLogger.error("Failed to register for remote notifications: \(error.localizedDescription)")
    }

    // MARK: - UNUserNotificationCenterDelegate

    // Handle notification when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        deliveryLogger.info("Received notification in foreground: \(userInfo)")

        // Show banner and play sound even when app is in foreground
        // Delivery app should always show new order notifications prominently
        completionHandler([.banner, .sound, .badge])
    }

    // Handle notification tap
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        deliveryLogger.info("User tapped notification: \(userInfo)")

        // Handle notification action based on type
        if let payload = NotificationPayload(from: userInfo) {
            handleNotificationAction(payload)
        }

        completionHandler()
    }

    // MARK: - MessagingDelegate

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        deliveryLogger.info("FCM registration token: \(token.prefix(20))...")
        NotificationManager.shared.updateFCMToken(token)

        // Save token to P2P backend
        saveFCMTokenToP2P(token)
    }

    // MARK: - Notification Handling

    private func handleNotificationAction(_ payload: NotificationPayload) {
        switch payload.type {
        case .driverApproved:
            // Driver has been approved - refresh status and navigate to dashboard
            deliveryLogger.info("Driver approved notification received")
            // Update UserDefaults to reflect approval
            UserDefaults.standard.set(true, forKey: "p2p_driver_is_approved")
            UserDefaults.standard.set("approved", forKey: "p2p_driver_status")
            UserDefaults.standard.set(false, forKey: "p2p_driver_requires_documents")
            // Post notification to refresh UI
            NotificationCenter.default.post(
                name: NSNotification.Name("DriverApprovalStatusChanged"),
                object: nil,
                userInfo: ["approved": true]
            )
        case .driverRejected:
            // Driver documents were rejected - navigate to profile to re-upload
            deliveryLogger.info("Driver rejected notification received")
            // Update UserDefaults to reflect rejection
            UserDefaults.standard.set(false, forKey: "p2p_driver_is_approved")
            UserDefaults.standard.set("rejected", forKey: "p2p_driver_status")
            // Post notification to refresh UI and prompt re-upload
            NotificationCenter.default.post(
                name: NSNotification.Name("DriverApprovalStatusChanged"),
                object: nil,
                userInfo: ["approved": false, "rejected": true]
            )
        case .newRideRequest:
            // Navigate to available ride requests
            NotificationCenter.default.post(
                name: NSNotification.Name("NavigateToAvailableRides"),
                object: nil
            )
        case .bidAccepted, .driverArrived, .rideStarted:
            // Navigate to active ride
            if let rideRequestId = payload.rideRequestId {
                NotificationCenter.default.post(
                    name: NSNotification.Name("NavigateToActiveRide"),
                    object: nil,
                    userInfo: ["rideRequestId": rideRequestId]
                )
            }
        case .bidRejected, .counterOffer:
            // Navigate to my bids to see updates
            NotificationCenter.default.post(
                name: NSNotification.Name("NavigateToMyBids"),
                object: nil
            )
        case .paymentProcessed:
            // Refresh earnings dashboard
            NotificationCenter.default.post(
                name: NSNotification.Name("RefreshEarnings"),
                object: nil
            )
        default:
            break
        }
    }

    private func saveFCMTokenToP2P(_ token: String) {
        // Save FCM token to P2P driver endpoint
        guard let driverId = UserDefaults.standard.object(forKey: UserDefaultsKeys.driverId) as? Int else { return }

        P2PAPIService.shared.saveDriverFCMToken(driverId: driverId, fcmToken: token) { result in
            switch result {
            case .success:
                deliveryLogger.info("FCM token saved for driver \(driverId)")
            case .failure(let error):
                deliveryLogger.error("Failed to save FCM token: \(error.localizedDescription)")
            }
        }
    }
}

@main
struct EatffairdeliveryApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authManager = AuthManager()
    @State private var showJailbreakWarning = false

    var body: some Scene {
        WindowGroup {
            NavigationView {
                if authManager.isLoggedIn {
                    // Gate: unapproved drivers (newly registered, is_approved == false)
                    // must complete document onboarding before reaching the dashboard.
                    if authManager.isApproved {
                        DriverDashboardView()
                            .environmentObject(authManager)
                    } else {
                        DriverOnboardingView()
                            .environmentObject(authManager)
                    }
                } else {
                    DriverLoginView(isLoggedIn: $authManager.isLoggedIn)
                        .environmentObject(authManager)
                }
            }
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
            // The app is dark-only (luxury black + orange); the shared tint recolors every default control.
            .preferredColorScheme(.dark)
            .tint(Lx.Palette.orange)
            .onAppear {
                // Clear badge on app launch
                NotificationManager.shared.clearBadge()

                // Check for jailbroken device and warn user
                if NetworkSecurity.shared.shouldRestrictFeatures() {
                    showJailbreakWarning = true
                }
            }
            .alert("Security Warning", isPresented: $showJailbreakWarning) {
                Button("I Understand", role: .cancel) { }
            } message: {
                Text(NetworkSecurity.shared.jailbreakWarningMessage())
            }
        }
    }
}
