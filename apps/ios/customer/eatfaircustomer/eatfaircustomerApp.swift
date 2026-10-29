//
//  eatfaircustomerApp.swift
//  Dollor Customer App
//
//  Main entry point for the Dollor Customer iOS application.
//
//  ARCHITECTURE OVERVIEW:
//  ----------------------
//  This app uses SwiftUI with MVVM architecture:
//  - Views: UI components in /Views folder
//  - ViewModels: Business logic in /ViewModels folder
//  - Services: API & external integrations in /Services folder
//  - Models: Data models in /Models and EatFairShared package
//
//  KEY DEPENDENCIES:
//  - Firebase: Authentication, Firestore database, Push notifications
//  - Stripe: Payment processing (Apple Pay, Card payments)
//  - Google Maps/Places: Location services and address search
//  - EatFairShared: Shared models and services across all Dollor apps
//
//  ENVIRONMENT OBJECTS (App-wide state):
//  - AddressViewModel: User's saved addresses
//
//  Created by Dollor.ai Team
//  Copyright © 2024-2026 Dollor.ai. All rights reserved.
//

import SwiftUI
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging
import UserNotifications
import EatFairShared
import GoogleMaps
import GooglePlaces
import GoogleSignIn
import os

private let appLogger = Logger(subsystem: "com.dollorai.customer", category: "CustomerApp")

// MARK: - App Delegate
/// Handles app lifecycle events, push notifications, and SDK initialization.
/// Uses UIApplicationDelegateAdaptor to bridge UIKit delegate with SwiftUI App.
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Configure Google Maps SDK
        GMSServices.provideAPIKey(GoogleMapsConfig.currentKey)
        GMSPlacesClient.provideAPIKey(GoogleMapsConfig.currentKey)

        // Configure Firebase
        FirebaseApp.configure()

        // Load app configuration from Firebase
        AppConfig.shared.fetchConfig()

        // Setup push notifications
        setupPushNotifications(application)

        return true
    }

    // MARK: - Push Notification Setup

    private func setupPushNotifications(_ application: UIApplication) {
        // Set delegates
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self

        // No permission prompt at launch: it is requested after the first ride request.
        NotificationManager.shared.registerIfAlreadyAuthorized()
    }

    // MARK: - Remote Notification Registration

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        appLogger.error("Failed to register for remote notifications: \(error.localizedDescription)")
    }

    // MARK: - Google Sign-In URL Handler

    func application(_ app: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        return GIDSignIn.sharedInstance.handle(url)
    }

    // MARK: - UNUserNotificationCenterDelegate

    // Handle notification when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show banner and play sound even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }

    // Handle notification tap
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo

        // Handle notification action based on type
        if let payload = NotificationPayload(from: userInfo) {
            handleNotificationAction(payload)
        }

        completionHandler()
    }

    // MARK: - MessagingDelegate

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        NotificationManager.shared.updateFCMToken(token)

        // Save token to Firestore for the current user
        saveTokenToFirestore(token)
    }

    // MARK: - Notification Handling

    private func handleNotificationAction(_ payload: NotificationPayload) {
        switch payload.type {
        case .driverAssigned:
            // Navigate to order tracking with driver info
            if let orderId = payload.orderId {
                NotificationCenter.default.post(
                    name: NSNotification.Name("NavigateToOrder"),
                    object: nil,
                    userInfo: ["orderId": orderId, "showDriver": true]
                )
            }
        case .promotion:
            // Navigate to promotions/offers
            NotificationCenter.default.post(
                name: NSNotification.Name("NavigateToPromotions"),
                object: nil
            )
        case .driverArrived, .rideStarted, .rideCompleted, .rideCancelled, .driverEnRoute:
            // Navigate to ride tracking
            if let rideRequestId = payload.rideRequestId {
                NotificationCenter.default.post(
                    name: NSNotification.Name("NavigateToRideTracking"),
                    object: nil,
                    userInfo: ["rideRequestId": rideRequestId, "type": payload.type.rawValue]
                )
            }
        case .newBid, .counterOffer:
            // Navigate to ride bids sheet
            if let rideRequestId = payload.rideRequestId {
                NotificationCenter.default.post(
                    name: NSNotification.Name("NavigateToRideBids"),
                    object: nil,
                    userInfo: ["rideRequestId": rideRequestId]
                )
            }
        case .paymentProcessed:
            // Navigate to ride receipt
            if let rideRequestId = payload.rideRequestId {
                NotificationCenter.default.post(
                    name: NSNotification.Name("NavigateToRideReceipt"),
                    object: nil,
                    userInfo: ["rideRequestId": rideRequestId]
                )
            }
        case .rideExpired:
            // Show ride expired — no need to navigate, just post notification for any listening view
            NotificationCenter.default.post(
                name: NSNotification.Name("RideRequestExpired"),
                object: nil,
                userInfo: payload.rideRequestId.map { ["rideRequestId": $0] } ?? [:]
            )
        default:
            break
        }
    }

    private func saveTokenToFirestore(_ token: String) {
        // Save FCM token to user's document for targeted notifications
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let db = Firestore.firestore()
        db.collection("users").document(userId).setData([
            "fcmToken": token,
            "platform": "iOS",
            "lastUpdated": FieldValue.serverTimestamp()
        ], merge: true)

        // Also save to P2P backend for unified notifications
        saveTokenToP2PBackend(token)
    }

    private func saveTokenToP2PBackend(_ token: String) {
        // Get customer ID from UserDefaults (set during login)
        guard let customerIdString = UserDefaults.standard.string(forKey: "p2p_customer_id"),
              let customerId = Int(customerIdString) else {
            appLogger.debug("No customer ID found, skipping P2P FCM registration")
            return
        }

        P2PAPIService.shared.saveCustomerFCMToken(customerId: customerId, token: token) { result in
            switch result {
            case .success:
                appLogger.debug("FCM token saved to P2P backend")
            case .failure(let error):
                appLogger.error("Failed to save FCM token to P2P: \(error.localizedDescription)")
            }
        }
    }
}

@main
struct EatfaircustomerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    @StateObject var addressViewModel = AddressViewModel()
    @State private var showJailbreakWarning = false

    var body: some Scene {
        WindowGroup {
            MainAppView()
                .environmentObject(addressViewModel)
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
                .onOpenURL { url in
                    // Handle Google Sign-In URL callback
                    GIDSignIn.sharedInstance.handle(url)
                }
                .alert("Security Warning", isPresented: $showJailbreakWarning) {
                    Button("I Understand", role: .cancel) { }
                } message: {
                    Text(NetworkSecurity.shared.jailbreakWarningMessage())
                }
        }
    }
}
