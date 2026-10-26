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
