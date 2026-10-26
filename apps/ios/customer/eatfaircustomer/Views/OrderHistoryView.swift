import SwiftUI
import Combine
import EatFairShared

struct OrderHistoryView: View {
    var body: some View {
        ZStack {
            Theme.lxBg.ignoresSafeArea()

            RideHistorySection()
        }
        .navigationTitle("Your Rides")
        .preferredColorScheme(.dark)
    }
}

// MARK: - Ride History Section
struct RideHistorySection: View {
    @State private var rides: [RideHistoryItem] = []
    @State private var isLoading = false
    @State private var hasMore = false
    @State private var currentOffset = 0
    private let pageSize = 20

    var body: some View {
        Group {
            if isLoading && rides.isEmpty {
                VStack {
                    Spacer()
                    ProgressView("Loading rides...")
                        .tint(Theme.lxOrange)
                        .foregroundColor(Theme.lxTextSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.lxBg)
            } else if rides.isEmpty {
                rideEmptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(rides) { ride in
                            RideHistoryCard(ride: ride)
                        }

                        if hasMore {
                            Button(action: loadMoreRides) {
                                if isLoading {
                                    ProgressView()
                                        .tint(Theme.lxOrange)
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                } else {
                                    Text("Load More")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(Theme.lxOrange)
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .onAppear { loadRides() }
    }

    private var rideEmptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "car.fill")
                .font(Lx.Typography.iconHero)
                .foregroundColor(Theme.lxOrange)
            Text("No rides yet")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(Theme.lxText)
            Text("Your ride history will appear here after your first trip.")
                .font(.subheadline)
                .foregroundColor(Theme.lxTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.lxBg)
    }

    private func loadRides() {
        isLoading = true
        currentOffset = 0
        P2PAPIService.shared.getCustomerRideHistory(limit: pageSize, offset: 0) { result in
            isLoading = false
            switch result {
            case .success(let response):
                rides = response.rides
                hasMore = response.has_more
                currentOffset = response.rides.count
            case .failure:
                rides = []
                hasMore = false
            }
        }
    }

    private func loadMoreRides() {
        isLoading = true
        P2PAPIService.shared.getCustomerRideHistory(limit: pageSize, offset: currentOffset) { result in
            isLoading = false
            switch result {
            case .success(let response):
                rides.append(contentsOf: response.rides)
                hasMore = response.has_more
                currentOffset += response.rides.count
            case .failure:
                break
            }
        }
    }
}

// MARK: - Ride History Card
struct RideHistoryCard: View {
    let ride: RideHistoryItem
    @State private var showReceipt = false

    private var statusColor: Color {
        switch ride.status {
        case "completed": return Theme.lxSuccess
        case "cancelled": return Theme.lxError
        case "in_progress": return Theme.lxOrange
        case "matched": return Theme.lxOrange
        default: return Theme.lxOrange
        }
    }

    private var statusLabel: String {
        switch ride.status {
        case "completed": return "Completed"
        case "cancelled": return "Cancelled"
        case "in_progress": return "In Progress"
        case "matched": return "Matched"
        case "open": return "Open"
        case "bidding": return "Bidding"
        default: return ride.status?.capitalized ?? "Unknown"
        }
    }

    /// The server's total matches the receipt; the sum is only a fallback for an older server.
    private var totalPaid: Double {
        ride.total ?? ((ride.fare ?? 0) + (ride.platform_fee ?? 0) + (ride.tip ?? 0))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Date + Status
            HStack {
                if let date = ride.date {
                    Text(date)
                        .font(.caption)
                        .foregroundColor(Theme.lxTextMuted)
                }
                Spacer()
                Text(statusLabel)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.15))
                    .cornerRadius(Lx.Radius.chip)
            }

            // Pickup → Dropoff
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Lx.Palette.pickup)
                        .frame(width: 8, height: 8)
                    Text(ride.pickup ?? "Pickup")
                        .font(.subheadline)
                        .foregroundColor(Theme.lxText)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    Circle()
                        .fill(Lx.Palette.dropoff)
                        .frame(width: 8, height: 8)
                    Text(ride.dropoff ?? "Dropoff")
                        .font(.subheadline)
                        .foregroundColor(Theme.lxText)
                        .lineLimit(1)
                }
            }

            Divider()
                .background(Theme.lxHairline)

            // Footer: Driver + Fare
            HStack {
                if let driverName = ride.driver_name {
                    HStack(spacing: 6) {
                        Image(systemName: "person.circle.fill")
                            .foregroundColor(Theme.lxOrange)
                        Text(driverName)
                            .font(.caption)
                            .foregroundColor(Theme.lxTextSecondary)
                    }
                }
                Spacer()

                // Fare breakdown
                VStack(alignment: .trailing, spacing: 2) {
                    Text("$\(String(format: "%.2f", totalPaid))")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.lxText)
                    if let tip = ride.tip, tip > 0 {
                        Text("incl. $\(String(format: "%.2f", tip)) tip")
                            .font(.caption2)
                            .foregroundColor(Theme.lxTextMuted)
                    }
                }
            }

            // View Receipt button for completed rides
            if ride.status == "completed" {
                Button(action: { showReceipt = true }) {
                    HStack {
                        Image(systemName: "doc.text")
                        Text("View Receipt")
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(Theme.lxOrange)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Theme.lxOrange.opacity(0.15))
                    .cornerRadius(Lx.Radius.chip)
                }
            }
        }
        .padding(16)
        .background(Theme.lxSurface)
        .cornerRadius(Lx.Radius.button)
        .overlay(
            RoundedRectangle(cornerRadius: Lx.Radius.button)
                .stroke(Theme.lxHairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
        .sheet(isPresented: $showReceipt) {
            RideReceiptView(rideId: ride.id)
        }
    }
}
