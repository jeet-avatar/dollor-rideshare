import SwiftUI
import EatFairShared

struct NotificationsView: View {
    @AppStorage("notifications_ride_updates") private var rideUpdates = true
    @AppStorage("notifications_promotions") private var promotions = false
    @AppStorage("notifications_driver_arrived") private var driverArrived = true
    @AppStorage("notifications_special_offers") private var specialOffers = false
    @State private var showPermissionAlert = false

    var body: some View {
        Form {
            Section(header: Text("Ride Notifications")) {
                Toggle("Ride Status Updates", isOn: $rideUpdates)
                Toggle("Driver Arrived", isOn: $driverArrived)
            }

            Section(header: Text("Marketing")) {
                Toggle("Promotions & Offers", isOn: $promotions)
                Toggle("Special Deals", isOn: $specialOffers)
            }

            Section {
                Button(action: openNotificationSettings) {
                    HStack {
                        Image(systemName: "gear")
                        Text("System Notification Settings")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundColor(Lx.Palette.textSecondary)
                    }
                }
            }

            Section(footer: Text("Your preferences are saved automatically and synced across devices.")) {
                EmptyView()
            }
        }
        .navigationTitle("Notifications")
        .onAppear {
            checkNotificationPermission()
        }
        .alert("Notifications Disabled", isPresented: $showPermissionAlert) {
            Button("Settings") { openNotificationSettings() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Please enable notifications in Settings to receive ride updates.")
        }
    }

    private func checkNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .denied {
                DispatchQueue.main.async {
                    showPermissionAlert = true
                }
            }
        }
    }

    private func openNotificationSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// Note: Main HelpSupportView is now in HelpSupportView.swift
struct LegacyHelpSupportView: View {
    private var config: AppConfig { AppConfig.shared }

    var body: some View {
        List {
            Section(header: Text("Common Questions")) {
                NavigationLink("How do I request a ride?", destination: FAQDetailView(
                    title: "How do I request a ride?",
                    content: "1. Open the Ride tab\n2. Enter your pickup and dropoff locations\n3. Review the fare estimate\n4. Tap 'Find Driver' to send your request\n5. Nearby drivers will bid — accept the offer that works for you!"
                ))
                NavigationLink("Where is my driver?", destination: FAQDetailView(
                    title: "Where is my driver?",
                    content: "Once a driver accepts your ride, you'll see their live location on the map in the Ride tab. You'll also receive push notifications when the driver is on the way and when they arrive."
                ))
                NavigationLink("How does pricing work?", destination: FAQDetailView(
                    title: "How does pricing work?",
                    content: "Dollor uses peer-to-peer bidding. Drivers set their own rates and you can accept, decline, or counter any offer.\n\nA small platform fee ($1–$3) is charged for using the matchmaking service. The driver receives the rest of the fare directly."
                ))
                NavigationLink("Payment issues", destination: FAQDetailView(
                    title: "Payment Issues",
                    content: "If you're experiencing payment issues:\n\n1. Make sure your card details are correct\n2. Check if your card has sufficient funds\n3. Try a different payment method (Apple Pay, etc.)\n\nIf the issue persists, please contact our support team."
                ))
                NavigationLink("Cancellation policy", destination: FAQDetailView(
                    title: "Cancellation Policy",
                    content: "You can cancel a ride request at any time before a driver is matched at no charge.\n\nIf you cancel after a driver has been assigned, a small cancellation fee may apply depending on how far the driver has traveled."
                ))
                NavigationLink("Safety & support", destination: FAQDetailView(
                    title: "Safety & Support",
                    content: "Your safety is our priority.\n\n• All drivers are background-checked\n• Share your trip with trusted contacts\n• In-app chat and call masking protects your privacy\n\nIf you have an emergency, always call 911 first. For app issues, contact our support team."
                ))
            }

            Section(header: Text("Contact Us")) {
                Button(action: {
                    if let url = URL(string: "mailto:\(config.supportEmail)") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack {
                        Image(systemName: "envelope.fill")
                            .foregroundColor(Lx.Palette.orange)
                        Text(config.supportEmail)
                            .foregroundColor(Lx.Palette.text)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundColor(Lx.Palette.textSecondary)
                    }
                }

                Button(action: {
                    let phone = config.supportPhone.replacingOccurrences(of: "-", with: "")
                    if let url = URL(string: "tel:\(phone)") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack {
                        Image(systemName: "phone.fill")
                            .foregroundColor(Lx.Palette.success)
                        Text(config.supportPhone)
                            .foregroundColor(Lx.Palette.text)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundColor(Lx.Palette.textSecondary)
                    }
                }

                Button(action: {
                    if let url = URL(string: config.supportUrl) {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack {
                        Image(systemName: "globe")
                            .foregroundColor(Lx.Palette.orange)
                        Text("Visit Help Center")
                            .foregroundColor(Lx.Palette.text)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundColor(Lx.Palette.textSecondary)
                    }
                }
            }

            Section(header: Text("Legal")) {
                Button(action: {
                    if let url = URL(string: config.termsOfServiceUrl) {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack {
                        Image(systemName: "doc.text.fill")
                            .foregroundColor(Lx.Palette.textMuted)
                        Text("Terms of Service")
                            .foregroundColor(Lx.Palette.text)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundColor(Lx.Palette.textSecondary)
                    }
                }

                Button(action: {
                    if let url = URL(string: config.privacyPolicyUrl) {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack {
                        Image(systemName: "hand.raised.fill")
                            .foregroundColor(Lx.Palette.textMuted)
                        Text("Privacy Policy")
                            .foregroundColor(Lx.Palette.text)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundColor(Lx.Palette.textSecondary)
                    }
                }
            }
        }
        .navigationTitle("Help & Support")
    }
}

// MARK: - FAQ Detail View
struct FAQDetailView: View {
    let title: String
    let content: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(content)
                    .font(.body)
                    .foregroundColor(Lx.Palette.text)

                Spacer()

                // Contact support card
                VStack(alignment: .leading, spacing: 8) {
                    Text("Still need help?")
                        .font(.headline)

                    Text("Contact our support team and we'll get back to you within 24 hours.")
                        .font(.subheadline)
                        .foregroundColor(Lx.Palette.textSecondary)

                    Button(action: {
                        if let url = URL(string: "mailto:\(AppConfig.shared.supportEmail)") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        HStack {
                            Image(systemName: "envelope.fill")
                            Text("Contact Support")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Lx.Palette.orange)
                        .foregroundColor(Lx.Palette.onAccent)
                        .cornerRadius(Lx.Radius.chip)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(Lx.Radius.button)
            }
            .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
