import os

private let logger = Logger(subsystem: "com.dollorai.customer", category: "MainAppView")

import SwiftUI
import Combine
import EatFairShared

struct MainAppView: View {
    @StateObject private var authViewModel = AuthViewModel()
    @EnvironmentObject var addressViewModel: AddressViewModel

    @State private var selectedTab = 0

    // Notification handling states
    @State private var showCancellationAlert = false
    @State private var cancellationAlertTitle = ""
    @State private var cancellationAlertMessage = ""

    var body: some View {
        Group {
            if authViewModel.isAuthenticated {
                // Main App Flow (rideshare-only)
                TabView(selection: $selectedTab) {
                    NavigationStack {
                        RideRequestView(hideCloseButton: true)
                    }
                    .tabItem {
                        Label("Ride", systemImage: "car.fill")
                    }
                    .tag(0)

                    NavigationStack {
                        OrderHistoryView()
                    }
                    .tabItem {
                        Label("Trips", systemImage: "clock.fill")
                    }
                    .tag(1)

                    NavigationStack {
                        ProfileView()
                    }
                    .tabItem {
                        Label("Profile", systemImage: "person.fill")
                    }
                    .tag(2)
                }
                .accentColor(Lx.Palette.orange)
                // Luxury black+orange theme: the whole app is dark. Every screen uses explicit
                // dark colors (Theme.lx*), so force dark to keep system chrome consistent.
                .preferredColorScheme(.dark)
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OrderCancelled"))) { notification in
                    // Handle order cancellation alert
                    if let title = notification.userInfo?["title"] as? String,
                       let body = notification.userInfo?["body"] as? String {
                        cancellationAlertTitle = title.isEmpty ? "Order Cancelled" : title
                        cancellationAlertMessage = body.isEmpty ? "Your order has been cancelled. A refund will be processed if applicable." : body
                        showCancellationAlert = true
                        selectedTab = 1 // Switch to Trips tab
                    }
                }
                .alert("Order Cancelled", isPresented: $showCancellationAlert) {
                    Button("View Trips") {
                        selectedTab = 1
                    }
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(cancellationAlertMessage)
                }
                .environmentObject(authViewModel)
            } else {
                // Enhanced Auth Flow
                LoginView(authViewModel: authViewModel)
            }
        }
    }
}
