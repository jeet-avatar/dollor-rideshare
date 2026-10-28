import SwiftUI
import MapKit
import EatFairShared

/// SubmitBidSheet - Submit a competitive bid on a ride request
/// Matches web app RideBidding.tsx bid submission modal
struct SubmitBidSheet: View {
    private static func percentText(_ factor: Double) -> String {
        "\(Int((factor * 100).rounded()))%"
    }

    let request: RideRequestForBidding
    @ObservedObject var viewModel: RideBiddingViewModel
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var proposedPrice: String = ""
    @State private var estimatedArrival: Int = 5
    @State private var message: String = ""
    @FocusState private var isPriceFocused: Bool

    private var platformFee: Double {
        viewModel.getPlatformFee(for: proposedAmount)
    }

    private var suggestedPrice: Double {
        request.suggested_price ?? 0
    }

    private var proposedAmount: Double {
        proposedPrice.parsedDecimal ?? 0
    }

    private var driverEarnings: Double {
        viewModel.calculateEarnings(proposedPrice: proposedAmount)
    }

    private var isValidBid: Bool {
        proposedAmount > platformFee
    }

    private var suggestedBids: (quickAccept: Double, fairPrice: Double, premium: Double) {
        viewModel.calculateSuggestedBids(baseFare: suggestedPrice)
    }

    private var earningsPerMile: Double? {
        viewModel.calculateEarningsPerMile(proposedPrice: proposedAmount, distanceKm: request.estimated_distance_km)
    }

    private var earningsPerHour: Double? {
        viewModel.calculateEarningsPerHour(proposedPrice: proposedAmount, durationMinutes: request.estimated_duration_minutes)
    }

    private var keepPercentage: Double {
        viewModel.calculateDriverKeepPercentage(proposedPrice: proposedAmount)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Map Preview
                    mapPreview
                        .frame(height: 180)
                        .cornerRadius(Lx.Radius.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: Lx.Radius.card)
                                .stroke(Theme.lxHairline, lineWidth: 1)
                        )
                        .padding(.horizontal)

                    // Route Summary
                    routeSummary
                        .padding(.horizontal)

                    // Price Section
                    priceSection
                        .padding(.horizontal)

                    // Arrival Time
                    arrivalSection
                        .padding(.horizontal)

                    // Optional Message
                    messageSection
                        .padding(.horizontal)

                    // Platform Fee Info
                    platformFeeInfo
                        .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .background(Theme.lxBg.ignoresSafeArea())
            .navigationTitle("Submit Your Bid")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                        onDismiss()
                    }
                    .foregroundColor(Theme.lxOrange)
                }
            }
            .safeAreaInset(edge: .bottom) {
                submitButton
            }
            .onAppear {
                // Pre-fill with suggested price
                proposedPrice = String(format: "%.2f", suggestedPrice)
            }
            .onChange(of: viewModel.showSuccess) { _, success in
                // Dismiss sheet when bid is successfully submitted
                if success {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        dismiss()
                        onDismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Map Preview

    private var mapPreview: some View {
        Map {
            // Pickup
            Annotation("Pickup", coordinate: CLLocationCoordinate2D(
                latitude: request.pickup.latitude,
                longitude: request.pickup.longitude
            )) {
                Image(systemName: "person.fill")
                    .foregroundColor(Lx.Palette.onAccent)
                    .padding(8)
                    .background(Theme.lxSuccess)
                    .clipShape(Circle())
            }

            // Dropoff
            Annotation("Dropoff", coordinate: CLLocationCoordinate2D(
                latitude: request.dropoff.latitude,
                longitude: request.dropoff.longitude
            )) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundColor(Lx.Palette.onAccent)
                    .padding(8)
                    .background(Lx.Palette.dropoff)
                    .clipShape(Circle())
            }
        }
        .mapStyle(.standard)
    }

    // MARK: - Route Summary

    private var routeSummary: some View {
        VStack(spacing: 12) {
            // Pickup
            HStack(spacing: 12) {
                Circle()
                    .fill(Theme.lxSuccess)
                    .frame(width: 12, height: 12)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Pickup")
                        .font(.caption)
                        .foregroundColor(Theme.lxTextSecondary)
                    Text(request.pickup.address)
                        .font(.subheadline)
                        .foregroundColor(Theme.lxText)
                        .lineLimit(1)
                }

                Spacer()
            }

            // Connector
            HStack {
                Rectangle()
                    .fill(Theme.lxOrange.opacity(0.4))
                    .frame(width: 2, height: 20)
                    .padding(.leading, 5)
                Spacer()
            }

            // Dropoff
            HStack(spacing: 12) {
                Circle()
                    .fill(Lx.Palette.dropoff)
                    .frame(width: 12, height: 12)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Drop-off")
                        .font(.caption)
                        .foregroundColor(Theme.lxTextSecondary)
                    Text(request.dropoff.address)
                        .font(.subheadline)
                        .foregroundColor(Theme.lxText)
                        .lineLimit(1)
                }

                Spacer()
            }

            // TNC-12: Accessibility notice
            if request.accessibility_requested == true {
                HStack(spacing: 8) {
                    Image(systemName: "figure.roll")
                        .foregroundColor(Theme.lxOrange)
                    Text("Passenger needs accessible vehicle")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(Theme.lxOrange)
                    Spacer()
                }
                .padding(10)
                .background(Theme.lxOrange.opacity(0.12))
                .cornerRadius(Lx.Radius.chip)
            }

            // Trip Stats
            HStack(spacing: 20) {
                if let distance = request.estimated_distance_km {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left.and.right")
                            .font(.caption)
                        Text(String(format: "%.1f mi", distance * 0.621371))
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(Theme.lxOrange)
                }

                if let duration = request.estimated_duration_minutes {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.caption)
                        Text("\(duration) min")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(Theme.lxOrange)
                }
            }
            .padding(.top, 8)
        }
        .padding()
        .background(Theme.lxSurface)
        .cornerRadius(Lx.Radius.card)
        .overlay(
            RoundedRectangle(cornerRadius: Lx.Radius.card)
                .stroke(Theme.lxHairline, lineWidth: 1)
        )
    }

    // MARK: - Price Section

    private var priceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Your Bid Price")
                    .font(.headline)
                    .foregroundColor(Theme.lxText)

                Spacer()

                Text("Suggested: $\(String(format: "%.2f", suggestedPrice))")
                    .font(.subheadline)
                    .foregroundColor(Theme.lxOrange)
            }

            // Suggested Bid Options - Quick Accept 92%, Fair Price 100%, Premium 108%
            VStack(spacing: 8) {
                Text("Suggested Bids")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.lxTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    // Quick Accept - 92% (8% discount to win fast)
                    BidOptionButton(
                        title: "Quick Accept",
                        subtitle: Self.percentText(AppConfig.shared.bidQuickAcceptFactor),
                        amount: suggestedBids.quickAccept,
                        earnings: viewModel.calculateEarnings(proposedPrice: suggestedBids.quickAccept),
                        color: Theme.lxOrange,
                        isSelected: abs(proposedAmount - suggestedBids.quickAccept) < 0.005,
                        action: {
                            proposedPrice = String(format: "%.2f", suggestedBids.quickAccept)
                        }
                    )

                    // Fair Price - 100% (market rate)
                    BidOptionButton(
                        title: "Fair Price",
                        subtitle: Self.percentText(AppConfig.shared.bidFairFactor),
                        amount: suggestedBids.fairPrice,
                        earnings: viewModel.calculateEarnings(proposedPrice: suggestedBids.fairPrice),
                        color: Theme.lxOrangeBright,
                        isSelected: abs(proposedAmount - suggestedBids.fairPrice) < 0.005,
                        action: {
                            proposedPrice = String(format: "%.2f", suggestedBids.fairPrice)
                        }
                    )

                    // Premium - 108% (8% premium for guaranteed higher earnings)
                    BidOptionButton(
                        title: "Premium",
                        subtitle: Self.percentText(AppConfig.shared.bidPremiumFactor),
                        amount: suggestedBids.premium,
                        earnings: viewModel.calculateEarnings(proposedPrice: suggestedBids.premium),
                        color: Theme.lxSuccess,
                        isSelected: abs(proposedAmount - suggestedBids.premium) < 0.005,
                        action: {
                            proposedPrice = String(format: "%.2f", suggestedBids.premium)
                        }
                    )
                }
            }

            // Price Input - Custom bid
            VStack(alignment: .leading, spacing: 8) {
                Text("Custom Bid")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.lxTextSecondary)

                HStack {
                    Text("$")
                        .font(Lx.Typography.largeTitle.weight(.bold))
                        .foregroundColor(Theme.lxTextSecondary)

                    TextField("0", text: $proposedPrice)
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
            }

            // Earnings Breakdown
            if proposedAmount > 0 {
                VStack(spacing: 12) {
                    // Keep percentage messaging
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Theme.lxSuccess)
                        Text("You keep the fare minus a flat fee")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.lxSuccess)
                        Spacer()
                    }

                    Divider()
                        .overlay(Theme.lxHairline)

                    // Driver earnings
                    HStack {
                        Text("You earn:")
                            .font(.subheadline)
                            .foregroundColor(Theme.lxTextSecondary)
                        Spacer()
                        Text("$\(String(format: "%.2f", driverEarnings))")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.lxSuccess)
                    }

                    // Earnings per mile
                    if let perMile = earningsPerMile {
                        HStack {
                            Image(systemName: "arrow.left.and.right")
                                .font(.caption)
                                .foregroundColor(Theme.lxTextSecondary)
                            Text("Per mile:")
                                .font(.subheadline)
                                .foregroundColor(Theme.lxTextSecondary)
                            Spacer()
                            Text("$\(String(format: "%.2f", perMile))")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(Theme.lxText)
                        }
                    }

                    // Earnings per hour
                    if let perHour = earningsPerHour {
                        HStack {
                            Image(systemName: "clock.fill")
                                .font(.caption)
                                .foregroundColor(Theme.lxTextSecondary)
                            Text("Per hour:")
                                .font(.subheadline)
                                .foregroundColor(Theme.lxTextSecondary)
                            Spacer()
                            Text("$\(String(format: "%.2f", perHour))")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(Theme.lxText)
                        }
                    }

                    Divider()
                        .overlay(Theme.lxHairline)

                    // Platform fee transparency
                    HStack {
                        Text("Platform fee:")
                            .font(.caption)
                            .foregroundColor(Theme.lxTextSecondary)
                        Spacer()
                        Text("\(Lx.Money.text(platformFee))")
                            .font(.caption)
                            .foregroundColor(Theme.lxTextSecondary)
                    }

                    HStack {
                        Text("CPUC Access for All:")
                            .font(.caption)
                            .foregroundColor(Theme.lxTextSecondary)
                        Spacer()
                        Text("\(Lx.Money.text(AppConfig.shared.rideshareDriverRegulatoryShare))")
                            .font(.caption)
                            .foregroundColor(Theme.lxTextSecondary)
                    }
                }
                .padding()
                .background(Theme.lxSuccess.opacity(0.1))
                .cornerRadius(Lx.Radius.button)
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

    // MARK: - Arrival Section

    private var arrivalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Estimated Arrival")
                .font(.headline)
                .foregroundColor(Theme.lxText)

            HStack(spacing: 8) {
                ForEach(AppConfig.shared.etaOptionsMinutes, id: \.self) { minutes in
                    Button(action: { estimatedArrival = minutes }) {
                        Text("\(minutes) min")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(estimatedArrival == minutes ? .white : Theme.lxOrange)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(estimatedArrival == minutes ? Theme.lxOrange : Theme.lxOrange.opacity(0.12))
                            .cornerRadius(Lx.Radius.chip)
                    }
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

    // MARK: - Message Section

    private var messageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Message to Rider")
                    .font(.headline)
                    .foregroundColor(Theme.lxText)
                Text("(Optional)")
                    .font(.caption)
                    .foregroundColor(Theme.lxTextSecondary)
            }

            TextField("e.g., I'm nearby and can pick you up quickly!", text: $message, axis: .vertical)
                .lineLimit(2...4)
                .foregroundColor(Theme.lxText)
                .padding()
                .background(Theme.lxSurface2)
                .cornerRadius(Lx.Radius.button)
                .overlay(
                    RoundedRectangle(cornerRadius: Lx.Radius.button)
                        .stroke(Theme.lxHairline, lineWidth: 1)
                )
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
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(Theme.lxSuccess)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 4) {
                    Text("You keep the fare minus a flat fee")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.lxSuccess)

                    Text("\(AppConfig.shared.rideshareFeeRangeText) flat fee, NOT a percentage")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.lxSuccess)
                }

                Spacer()
            }

            Divider()
                .overlay(Theme.lxHairline)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Platform Fee Structure:")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.lxText)
                    Spacer()
                }

                ForEach(AppConfig.shared.rideshareTierRows, id: \.label) { row in
                    HStack {
                        Circle()
                            .fill(Lx.Palette.success)
                            .frame(width: 6, height: 6)
                        Text(row.label + ":")
                            .font(Lx.Typography.caption)
                            .foregroundColor(Lx.Palette.textSecondary)
                        Spacer()
                        Text(row.fee)
                            .font(Lx.Typography.caption.weight(.semibold))
                            .foregroundColor(Lx.Palette.success)
                    }
                }
            }

            Text("You control your earnings. No percentage commissions!")
                .font(.caption)
                .foregroundColor(Theme.lxTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Theme.lxSuccess.opacity(0.1))
        .cornerRadius(Lx.Radius.button)
    }

    // MARK: - Submit Button

    private var submitButton: some View {
        VStack(spacing: 12) {
            SwipeToConfirmButton(
                label: "Slide to Submit Bid $\(String(format: "%.2f", proposedAmount))",
                accentColor: Theme.lxOrange,
                isDisabled: !isValidBid || viewModel.isSubmittingBid,
                onConfirm: submitBid
            )
            .padding(.horizontal, 24)
            .padding(.vertical, 8)

            if !isValidBid && proposedAmount > 0 {
                Text("Price must be greater than \(Lx.Money.text(platformFee)) platform fee")
                    .font(.caption)
                    .foregroundColor(Theme.lxError)
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

    // MARK: - Submit Bid Action

    private func submitBid() {
        isPriceFocused = false

        viewModel.submitBid(
            requestId: request.id,
            proposedPrice: proposedAmount,
            estimatedArrivalMinutes: estimatedArrival,
            message: message.isEmpty ? nil : message
        )
    }
}

// MARK: - Bid Option Button Component

struct BidOptionButton: View {
    let title: String
    let subtitle: String
    let amount: Double
    let earnings: Double
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(color)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(color.opacity(0.8))

                Text("$\(String(format: "%.2f", amount))")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(Lx.Palette.text)

                Text("Earn $\(String(format: "%.2f", earnings))")
                    .font(.caption2)
                    .foregroundColor(Lx.Palette.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 4)
            .background(color.opacity(isSelected ? 0.28 : 0.10))
            .cornerRadius(Lx.Radius.button)
            .overlay(
                RoundedRectangle(cornerRadius: Lx.Radius.button)
                    .stroke(color, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#if DEBUG
struct SubmitBidSheet_Previews: PreviewProvider {
    static var previews: some View {
        Text("Preview")
    }
}
#endif
