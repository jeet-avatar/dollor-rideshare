import SwiftUI
import EatFairShared

/// CounterOfferResponseSheet - Respond to customer counter-offers
/// Matches web app RideBidding.tsx counter-offer handling
struct CounterOfferResponseSheet: View {
    let bid: RideBid
    @ObservedObject var viewModel: RideBiddingViewModel
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showNewCounterInput = false
    @State private var newCounterPrice: String = ""
    @FocusState private var isPriceFocused: Bool

    private var platformFee: Double { AppConfig.shared.calculateRidesharePlatformFee(fareAmount: customerCounterPrice) }

    private var customerCounterPrice: Double {
        bid.customer_counter_price ?? 0
    }

    private var originalPrice: Double {
        bid.proposed_price
    }

    private var priceDifference: Double {
        customerCounterPrice - originalPrice
    }

    private var driverEarningsIfAccept: Double {
        max(0, customerCounterPrice - platformFee)
    }

    private var newCounterAmount: Double {
        newCounterPrice.parsedDecimal ?? 0
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header Icon
                    headerIcon

                    // Price Comparison
                    priceComparison

                    // Route Info
                    if let request = bid.ride_request {
                        routeInfo(request: request)
                    }

                    // New Counter Offer Input (if shown)
                    if showNewCounterInput {
                        newCounterOfferSection
                    }

                    // Platform Fee Info
                    platformFeeInfo
                }
                .padding()
            }
            .background(Theme.lxBg.ignoresSafeArea())
            .navigationTitle("Counter-Offer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                        onDismiss()
                    }
                    .foregroundColor(Theme.lxOrange)
                }
            }
            .safeAreaInset(edge: .bottom) {
                actionButtons
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "An error occurred")
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header Icon

    private var headerIcon: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.lxOrange.opacity(0.15))
                    .frame(width: 100, height: 100)

                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(Lx.Typography.icon)
                    .foregroundColor(Theme.lxOrange)
            }

            Text("Customer Counter-Offer")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(Theme.lxText)

            Text("The customer has made a counter-offer on your bid")
                .font(.subheadline)
                .foregroundColor(Theme.lxTextSecondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Price Comparison

    private var priceComparison: some View {
        VStack(spacing: 16) {
            // Your Original Bid
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your Bid")
                        .font(.caption)
                        .foregroundColor(Theme.lxTextSecondary)
                    Text("\(Lx.Money.text(originalPrice))")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.lxText)
                }

                Spacer()

                // Arrow
                Image(systemName: "arrow.right")
                    .font(.title2)
                    .foregroundColor(Theme.lxTextMuted)

                Spacer()

                // Customer Counter
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Their Offer")
                        .font(.caption)
                        .foregroundColor(Theme.lxTextSecondary)
                    Text("\(Lx.Money.text(customerCounterPrice))")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.lxOrange)
                }
            }
            .padding()
            .background(Theme.lxOrange.opacity(0.08))
            .cornerRadius(Lx.Radius.button)

            // Difference Badge
            HStack {
                if priceDifference > 0 {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundColor(Theme.lxSuccess)
                    Text("+\(Lx.Money.text(priceDifference)) more than your bid")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.lxSuccess)
                } else if priceDifference < 0 {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(Theme.lxOrange)
                    Text("\(Lx.Money.text(abs(priceDifference))) less than your bid")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.lxOrange)
                } else {
                    Image(systemName: "equal.circle.fill")
                        .foregroundColor(Theme.lxOrange)
                    Text("Same as your bid")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.lxOrange)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(priceDifference >= 0 ? Theme.lxSuccess.opacity(0.12) : Theme.lxOrange.opacity(0.12))
            .cornerRadius(Lx.Radius.chip)

            // Earnings Preview
            HStack {
                Text("If you accept:")
                    .font(.subheadline)
                    .foregroundColor(Theme.lxTextSecondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("$\(String(format: "%.2f", driverEarningsIfAccept))")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.lxSuccess)
                    Text("after \(Lx.Money.text(platformFee)) fee")
                        .font(.caption2)
                        .foregroundColor(Theme.lxTextSecondary)
                }
            }
        }
        .padding()
        .background(Theme.lxSurface)
        .cornerRadius(Lx.Radius.card)
        .overlay(
            RoundedRectangle(cornerRadius: Lx.Radius.card)
                .stroke(Theme.lxHairline, lineWidth: 1)
        )
    }

    // MARK: - Route Info

    private func routeInfo(request: RideRequestForBidding) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("Trip Details")
                    .font(.headline)
                    .foregroundColor(Theme.lxText)
                Spacer()
            }

            // Pickup
            HStack(spacing: 12) {
                Circle()
                    .fill(Theme.lxSuccess)
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pickup")
                        .font(.caption)
                        .foregroundColor(Theme.lxTextSecondary)
                    Text(request.pickup.address)
                        .font(.subheadline)
                        .foregroundColor(Theme.lxText)
                        .lineLimit(2)
                }
                Spacer()
            }

            // Dropoff
            HStack(spacing: 12) {
                Circle()
                    .fill(Theme.lxError)
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Drop-off")
                        .font(.caption)
                        .foregroundColor(Theme.lxTextSecondary)
                    Text(request.dropoff.address)
                        .font(.subheadline)
                        .foregroundColor(Theme.lxText)
                        .lineLimit(2)
                }
                Spacer()
            }

            // Stats
            HStack(spacing: 16) {
                if let distance = request.estimated_distance_km {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left.and.right")
                            .font(.caption2)
                        Text(String(format: "%.1f mi", distance * 0.621371))
                            .font(.caption)
                    }
                    .foregroundColor(Theme.lxOrange)
                }

                if let duration = request.estimated_duration_minutes {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.caption2)
                        Text("\(duration) min")
                            .font(.caption)
                    }
                    .foregroundColor(Theme.lxOrange)
                }
            }
        }
        .padding()
        .background(Theme.lxSurface)
        .cornerRadius(Lx.Radius.card)
        .overlay(
            RoundedRectangle(cornerRadius: Lx.Radius.card)
                .stroke(Theme.lxHairline, lineWidth: 1)
        )
    }

    // MARK: - New Counter Offer Section

    private var newCounterOfferSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your New Price")
                .font(.headline)
                .foregroundColor(Theme.lxText)

            HStack {
                Text("$")
                    .font(Lx.Typography.largeTitle.weight(.bold))
                    .foregroundColor(Theme.lxTextSecondary)

                TextField("0", text: $newCounterPrice)
                    .font(Lx.Typography.largeTitle.weight(.bold))
                    .keyboardType(.decimalPad)
                    .foregroundColor(Theme.lxText)
                    .focused($isPriceFocused)
            }
            .padding()
            .background(Theme.lxSurface2)
            .cornerRadius(Lx.Radius.button)
            .overlay(
                RoundedRectangle(cornerRadius: Lx.Radius.button)
                    .stroke(Theme.lxOrange, lineWidth: 2)
            )

            // Quick adjustments
            HStack(spacing: 8) {
                Button(action: {
                    newCounterPrice = String(format: "%.2f", customerCounterPrice)
                }) {
                    Text("Match Offer")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.lxOrange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.lxOrange.opacity(0.12))
                        .cornerRadius(Lx.Radius.chip)
                }

                Button(action: {
                    let middle = (originalPrice + customerCounterPrice) / 2
                    newCounterPrice = String(format: "%.2f", middle)
                }) {
                    Text("Split Difference")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.lxOrange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.lxOrange.opacity(0.12))
                        .cornerRadius(Lx.Radius.chip)
                }
            }

            if newCounterAmount > 0 {
                let newCounterFee = AppConfig.shared.calculateRidesharePlatformFee(fareAmount: newCounterAmount)
                HStack {
                    Text("You'll receive:")
                        .font(.subheadline)
                        .foregroundColor(Theme.lxTextSecondary)
                    Spacer()
                    Text("$\(String(format: "%.2f", max(0, newCounterAmount - newCounterFee)))")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.lxSuccess)
                }
            }
        }
        .padding()
        .background(Theme.lxSurface)
        .cornerRadius(Lx.Radius.card)
        .overlay(
            RoundedRectangle(cornerRadius: Lx.Radius.card)
                .stroke(Theme.lxHairline, lineWidth: 1)
        )
    }

    // MARK: - Platform Fee Info

    private var platformFeeInfo: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(Theme.lxSuccess)

            Text("Only \(Lx.Money.text(platformFee)) connection fee deducted from your earnings")
                .font(.caption)
                .foregroundColor(Theme.lxTextSecondary)
        }
        .padding()
        .background(Theme.lxSuccess.opacity(0.1))
        .cornerRadius(Lx.Radius.button)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            if showNewCounterInput {
                // Send New Counter
                SwipeToConfirmButton(
                    label: "Slide to Send \(Lx.Money.text(newCounterAmount)) Offer",
                    accentColor: Theme.lxOrange,
                    isDisabled: newCounterAmount <= 0 || viewModel.isLoading,
                    onConfirm: {
                        isPriceFocused = false
                        viewModel.submitNewCounterOffer(bid, newPrice: newCounterAmount)
                    }
                )
                .padding(.horizontal, 24)
                .padding(.vertical, 8)

                // Cancel Counter
                Button(action: {
                    withAnimation {
                        showNewCounterInput = false
                        newCounterPrice = ""
                    }
                }) {
                    Text("Cancel")
                        .font(.headline)
                        .foregroundColor(Theme.lxTextSecondary)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            } else {
                // Accept Counter-Offer
                SwipeToConfirmButton(
                    label: "Slide to Accept \(Lx.Money.text(customerCounterPrice))",
                    accentColor: Theme.lxSuccess,
                    isDisabled: viewModel.isLoading,
                    onConfirm: { viewModel.acceptCounterOffer(bid) }
                )
                .padding(.horizontal, 24)
                .padding(.vertical, 8)

                // Counter with New Price
                Button(action: {
                    withAnimation {
                        showNewCounterInput = true
                        newCounterPrice = String(format: "%.2f", originalPrice)
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Counter with Different Price")
                    }
                    .font(.headline)
                    .foregroundColor(Theme.lxOrange)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.lxOrange.opacity(0.12))
                    .cornerRadius(Lx.Radius.card)
                }

                // Reject
                Button(action: {
                    viewModel.rejectCounterOffer(bid)
                }) {
                    Text("Reject Offer")
                        .font(.headline)
                        .foregroundColor(Theme.lxError)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
        }
        .padding()
        .background(Theme.lxSurface)
        .overlay(
            Rectangle()
                .fill(Theme.lxHairline)
                .frame(height: 1),
            alignment: .top
        )
    }
}

// MARK: - Preview

#if DEBUG
struct CounterOfferResponseSheet_Previews: PreviewProvider {
    static var previews: some View {
        Text("Preview")
    }
}
#endif
