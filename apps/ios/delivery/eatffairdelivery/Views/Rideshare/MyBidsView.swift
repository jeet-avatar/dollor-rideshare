import SwiftUI
import EatFairShared

// MARK: - Bid Card

struct BidCard: View {
    let bid: RideBid
    @ObservedObject var viewModel: RideBiddingViewModel
    let onCounterOffer: () -> Void

    @State private var showWithdrawAlert = false

    private var statusColor: Color {
        switch bid.status {
        case "pending": return Theme.lxOrange
        case "countered": return Theme.lxOrangeBright
        case "accepted": return Theme.lxSuccess
        case "rejected": return Theme.lxError
        default: return Theme.lxTextMuted
        }
    }

    private var statusIcon: String {
        switch bid.status {
        case "pending": return "clock.fill"
        case "countered": return "arrow.triangle.2.circlepath"
        case "accepted": return "checkmark.circle.fill"
        case "rejected": return "xmark.circle.fill"
        default: return "questionmark.circle"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                // Status Badge
                HStack(spacing: 6) {
                    Image(systemName: statusIcon)
                        .font(.caption)
                    Text(bid.status.capitalized)
                        .font(.caption)
                        .fontWeight(.bold)
                }
                .foregroundColor(statusColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(statusColor.opacity(0.15))
                .cornerRadius(Lx.Radius.chip)

                Spacer()

                // Your Bid Amount
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Lx.Money.text(bid.proposed_price))")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.lxText)
                    Text("your bid")
                        .font(.caption2)
                        .foregroundColor(Theme.lxTextSecondary)
                }
            }
            .padding()

            Divider()
                .overlay(Theme.lxHairline)
                .padding(.horizontal)

            // Route Info
            if let request = bid.ride_request {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Lx.Palette.pickup)
                            .frame(width: 10, height: 10)
                        Text(request.pickup.address)
                            .font(.caption)
                            .foregroundColor(Theme.lxText)
                            .lineLimit(1)
                        Spacer()
                    }

                    HStack(spacing: 8) {
                        Circle()
                            .fill(Lx.Palette.dropoff)
                            .frame(width: 10, height: 10)
                        Text(request.dropoff.address)
                            .font(.caption)
                            .foregroundColor(Theme.lxText)
                            .lineLimit(1)
                        Spacer()
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }

            // Counter-Offer Section (if countered)
            if bid.status == "countered", let counterPrice = bid.customer_counter_price {
                Divider()
                    .overlay(Theme.lxHairline)
                    .padding(.horizontal)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Customer Counter-Offer")
                            .font(.caption)
                            .foregroundColor(Theme.lxTextSecondary)
                        HStack(spacing: 4) {
                            Text("\(Lx.Money.text(counterPrice))")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(Theme.lxOrange)
                            if counterPrice > bid.proposed_price {
                                Image(systemName: "arrow.up.circle.fill")
                                    .foregroundColor(Theme.lxSuccess)
                            } else {
                                Image(systemName: "arrow.down.circle.fill")
                                    .foregroundColor(Theme.lxOrange)
                            }
                        }
                    }

                    Spacer()

                    // Respond Button
                    Button(action: onCounterOffer) {
                        Text("Respond")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(Lx.Palette.onAccent)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Theme.lxButtonGradient)
                            .cornerRadius(Lx.Radius.chip)
                    }
                }
                .padding()
                .background(Theme.lxOrange.opacity(0.1))
            }

            // Expiry Warning
            if viewModel.isBidExpiringSoon(bid) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Theme.lxOrange)
                    Text("Expiring soon!")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.lxOrange)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Theme.lxOrange.opacity(0.15))
            }

            // Actions
            if bid.status == "pending" {
                Divider()
                    .overlay(Theme.lxHairline)
                    .padding(.horizontal)

                HStack(spacing: 12) {
                    Button(action: { showWithdrawAlert = true }) {
                        HStack {
                            Image(systemName: "xmark.circle")
                            Text("Withdraw")
                        }
                        .font(.subheadline)
                        .foregroundColor(Theme.lxError)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.lxError.opacity(0.15))
                        .cornerRadius(Lx.Radius.chip)
                    }
                }
                .padding()
            }

            // Accepted - Show Active Ride Button
            if bid.status == "accepted" {
                Divider()
                    .overlay(Theme.lxHairline)
                    .padding(.horizontal)

                NavigationLink(destination: ActiveRideView(bid: bid, viewModel: viewModel)) {
                    HStack {
                        Image(systemName: "car.fill")
                        Text("View Active Ride")
                    }
                    .font(.headline)
                    .foregroundColor(Lx.Palette.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.lxButtonGradient)
                    .cornerRadius(Lx.Radius.button)
                    .shadow(color: Theme.lxOrange.opacity(0.4), radius: 10, x: 0, y: 4)
                }
                .padding()
            }
        }
        .background(Theme.lxSurface)
        .cornerRadius(Lx.Radius.card)
        .overlay(
            RoundedRectangle(cornerRadius: Lx.Radius.card)
                .stroke(Theme.lxHairline, lineWidth: 1)
        )
        .shadow(color: Lx.Palette.shadow.opacity(0.25), radius: 8, x: 0, y: 4)
        .alert("Withdraw Bid?", isPresented: $showWithdrawAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Withdraw", role: .destructive) {
                viewModel.withdrawBid(bid)
            }
        } message: {
            Text("Are you sure you want to withdraw this bid? This action cannot be undone.")
        }
    }
}
