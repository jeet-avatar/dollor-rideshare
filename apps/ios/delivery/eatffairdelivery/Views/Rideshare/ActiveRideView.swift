import SwiftUI
import MapKit
import Combine
import EatFairShared

/// ActiveRideView - Track and manage an active matched ride
/// Matches web app ActiveDelivery.tsx for rideshare
struct ActiveRideView: View {
    let bid: RideBid
    @ObservedObject var viewModel: RideBiddingViewModel
    /// Called when the driver has fully finished with this ride (done after rating,
    /// cancelled, or no-show). Triggers dismissal of the full-screen cover.
    var onRideDone: () -> Void = {}
    @StateObject private var locationManager = LocationManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showChat = false
    @State private var rideStatus: RideStatus = .matched
    @State private var showCompleteAlert = false
    @State private var showCancelSheet = false
    @State private var selectedCancelReason: String?
    @State private var showNoShowAlert = false
    @State private var noShowTimerSeconds = AppConfig.shared.noShowWaitSeconds
    @State private var noShowTimerActive = false
    @State private var position: MapCameraPosition = .automatic
    @State private var driverRoute: MKRoute?
    @State private var etaMinutes: Int?
    @State private var timerCancellable: AnyCancellable?
    @State private var passengerRating: Int = 0
    @State private var passengerComment: String = ""
    @State private var hasSubmittedRating = false
    @State private var showSOSAlert = false
    @State private var showWaybill = false

    /// Cancel reasons filtered by the current ride stage.
    /// "Passenger not at pickup" only makes sense after the driver has arrived.
    /// "Wrong pickup location" only makes sense before arriving (driver is en route).
    private var cancelReasons: [String] {
        switch rideStatus {
        case .matched, .enRouteToPickup:
            return ["Safety concern", "Vehicle issue", "Personal emergency", "Wrong pickup location", "Other"]
        case .arrivedAtPickup:
            return ["Passenger not at pickup", "Safety concern", "Vehicle issue", "Personal emergency", "Other"]
        default:
            return []
        }
    }

    /// After a "Safety concern" cancel, we reuse the SOS alert to prompt 911.
    /// This flag changes the alert text and causes it to call onRideDone() on dismiss.
    @State private var dismissAfterSOSAlert = false

    enum RideStatus: String {
        case matched = "Matched"
        case enRouteToPickup = "En Route"
        case arrivedAtPickup = "Arrived"
        case inProgress = "In Progress"
        case completed = "Completed"

        var color: Color {
            switch self {
            case .matched: return Theme.lxOrange
            case .enRouteToPickup: return Theme.lxOrangeBright
            case .arrivedAtPickup: return Theme.lxSuccess
            case .inProgress: return Theme.lxOrangeDeep
            case .completed: return Theme.lxSuccess
            }
        }

        var icon: String {
            switch self {
            case .matched: return "checkmark.circle.fill"
            case .enRouteToPickup: return "car.fill"
            case .arrivedAtPickup: return "mappin.circle.fill"
            case .inProgress: return "arrow.right.circle.fill"
            case .completed: return "flag.checkered"
            }
        }
    }

    private var request: RideRequestForBidding? {
        bid.ride_request
    }

    /// The settled fare from the server once the ride is completed; before that, the bid's current price.
    private var finalPrice: Double {
        viewModel.completionData?.final_price ?? bid.customer_counter_price ?? bid.proposed_price
    }

    private var driverEarnings: Double {
        viewModel.completionData?.driver_payout
            ?? max(0, finalPrice - AppConfig.shared.calculateRidesharePlatformFee(fareAmount: finalPrice))
    }

    private var hasRiderPhone: Bool {
        guard let phone = request?.customer_phone, !phone.isEmpty else { return false }
        return true
    }

    var body: some View {
        ZStack {
            // Full-screen Map
            mapView
                .ignoresSafeArea()

            // Overlay Content
            VStack {
                // Top Card - Status
                statusCard
                    .padding(.horizontal)
                    .padding(.top, 8)

                Spacer()

                // Bottom Card - Actions
                actionCard
            }
        }
        .navigationTitle("Active Ride")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if rideStatus == .matched || rideStatus == .enRouteToPickup || rideStatus == .arrivedAtPickup {
                    Button(action: { showCancelSheet = true }) {
                        Text("Cancel")
                            .font(.subheadline)
                            .foregroundColor(Theme.lxError)
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    Button(action: { showChat = true }) {
                        Image(systemName: "message.fill")
                            .foregroundColor(Theme.lxOrange)
                    }

                    // TNC-15: Waybill
                    Button(action: { showWaybill = true }) {
                        Image(systemName: "doc.text")
                            .foregroundColor(Theme.lxOrange)
                    }
                    .accessibilityLabel("Trip Information")

                    Button(action: { showSOSAlert = true }) {
                        Text("SOS")
                            .font(.caption2)
                            .fontWeight(.heavy)
                            .foregroundColor(Lx.Palette.onAccent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Theme.lxError)
                            .cornerRadius(Lx.Radius.chip)
                    }
                    .accessibilityLabel("Emergency SOS")
                    .accessibilityHint("Calls 911 emergency services")
                }
            }
        }
        .sheet(isPresented: $showChat) {
            if let request = request {
                RiderChatView(
                    rideRequestId: request.id,
                    riderName: request.customer_name ?? "Rider",
                    riderPhone: request.customer_phone
                )
            }
        }
        .sheet(isPresented: $showWaybill) {
            if let request = request {
                WaybillSheet(rideRequestId: request.id)
            }
        }
        .alert("Complete Ride?", isPresented: $showCompleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Complete") {
                completeRide()
            }
        } message: {
            Text("Confirm that you have dropped off the passenger at their destination.")
        }
        .confirmationDialog("Cancel Ride", isPresented: $showCancelSheet, titleVisibility: .visible) {
            ForEach(cancelReasons, id: \.self) { reason in
                Button(reason, role: reason == "Safety concern" ? nil : .destructive) {
                    selectedCancelReason = reason
                    viewModel.driverCancelRide(bid, reason: reason) { success in
                        guard success else { return }
                        if reason == "Safety concern" {
                            // Show SOS prompt before dismissing; onRideDone() fires from the alert.
                            dismissAfterSOSAlert = true
                            showSOSAlert = true
                        } else {
                            onRideDone()
                        }
                    }
                }
            }
            Button("Keep Ride", role: .cancel) {}
        } message: {
            Text("Select a reason for cancelling. The ride will be re-opened for other drivers.")
        }
        .alert("Mark as No-Show?", isPresented: $showNoShowAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Confirm No-Show", role: .destructive) {
                viewModel.markPassengerNoShow(bid) { success in
                    if success { onRideDone() }
                }
            }
        } message: {
            Text("The passenger will be charged a \(Lx.Money.text(AppConfig.shared.noShowFee)) cancellation fee. You will receive \(Lx.Money.text(AppConfig.shared.noShowFee * AppConfig.shared.noShowDriverShare)) for your wait time.")
        }
        .alert(
            dismissAfterSOSAlert ? "Ride Cancelled — Safety" : "Emergency SOS",
            isPresented: $showSOSAlert
        ) {
            Button("Call 911", role: .destructive) {
                if let url = URL(string: "tel://911") {
                    UIApplication.shared.open(url)
                }
                if dismissAfterSOSAlert {
                    dismissAfterSOSAlert = false
                    onRideDone()
                }
            }
            Button(dismissAfterSOSAlert ? "I'm OK" : "Cancel", role: .cancel) {
                if dismissAfterSOSAlert {
                    dismissAfterSOSAlert = false
                    onRideDone()
                }
            }
        } message: {
            Text(dismissAfterSOSAlert
                ? "Your ride has been cancelled. Do you need emergency assistance?"
                : "This will call emergency services (911). Only use in a real emergency.")
        }
        .onChange(of: rideStatus) { _, newStatus in
            if newStatus == .arrivedAtPickup {
                startNoShowTimer()
            }
        }
        .onAppear {
            // Initialize rideStatus from backend ride/bid status
            if let rideRequest = bid.ride_request {
                switch rideRequest.status {
                case "in_progress":
                    rideStatus = .inProgress
                case "completed":
                    rideStatus = .completed
                default:
                    // "matched", "open", "bidding" — check if driver already arrived
                    if rideRequest.driver_arrived_at != nil {
                        rideStatus = .arrivedAtPickup
                    } else {
                        rideStatus = .matched
                    }
                }
            }
            updateMapPosition()
            if rideStatus == .arrivedAtPickup {
                startNoShowTimer()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Map View

    private var mapView: some View {
        Map(position: $position) {
            // Driver location
            if let coordinate = locationManager.currentCoordinate, coordinate.isValid {
                Annotation("You", coordinate: coordinate) {
                    ZStack {
                        Circle()
                            .fill(Theme.lxOrange.opacity(0.2))
                            .frame(width: 60, height: 60)

                        Image(systemName: "car.fill")
                            .font(.title2)
                            .foregroundColor(Lx.Palette.onAccent)
                            .padding(12)
                            .background(Theme.lxOrange)
                            .clipShape(Circle())
                            .shadow(color: Theme.lxOrange.opacity(0.5), radius: 6)
                    }
                }
            }

            // Pickup
            if let request = request {
                Annotation("Pickup", coordinate: CLLocationCoordinate2D(
                    latitude: request.pickup.latitude,
                    longitude: request.pickup.longitude
                )) {
                    VStack(spacing: 2) {
                        Image(systemName: "person.fill")
                            .foregroundColor(Lx.Palette.onAccent)
                            .padding(10)
                            .background(Theme.lxSuccess)
                            .clipShape(Circle())
                            .shadow(color: Theme.lxSuccess.opacity(0.5), radius: 4)

                        Image(systemName: "arrowtriangle.down.fill")
                            .font(Lx.Typography.caption)
                            .foregroundColor(Theme.lxSuccess)
                            .offset(y: -4)
                    }
                }

                // Dropoff
                Annotation("Dropoff", coordinate: CLLocationCoordinate2D(
                    latitude: request.dropoff.latitude,
                    longitude: request.dropoff.longitude
                )) {
                    VStack(spacing: 2) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundColor(Lx.Palette.onAccent)
                            .padding(10)
                            .background(Lx.Palette.dropoff)
                            .clipShape(Circle())
                            .shadow(color: Lx.Palette.dropoff.opacity(0.5), radius: 4)

                        Image(systemName: "arrowtriangle.down.fill")
                            .font(Lx.Typography.caption)
                            .foregroundColor(Lx.Palette.dropoff)
                            .offset(y: -4)
                    }
                }
            }

            // Route polyline
            if let driverRoute = driverRoute {
                MapPolyline(driverRoute.polyline)
                    .stroke(Theme.lxOrange, lineWidth: 5)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .onAppear { calculateDriverRoute() }
        .onChange(of: rideStatus) { _, _ in calculateDriverRoute() }
    }

    // MARK: - Status Card

    private var statusCard: some View {
        VStack(spacing: 12) {
            // Status Badge
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: rideStatus.icon)
                        .font(.headline)
                    Text(rideStatus.rawValue)
                        .font(.headline)
                        .fontWeight(.bold)
                }
                .foregroundColor(rideStatus.color)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(rideStatus.color.opacity(0.15))
                .cornerRadius(Lx.Radius.button)

                Spacer()

                // ETA
                if let eta = etaMinutes, rideStatus != .completed {
                    VStack(spacing: 2) {
                        Text("\(eta)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.lxOrange)
                        Text(rideStatus == .inProgress ? "min left" : "min away")
                            .font(.caption2)
                            .foregroundColor(Theme.lxOrange)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.lxOrange.opacity(0.12))
                    .cornerRadius(Lx.Radius.chip)
                }

                // Earnings
                VStack(alignment: .trailing, spacing: 2) {
                    Text("$\(String(format: "%.2f", driverEarnings))")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.lxSuccess)
                    Text("earnings")
                        .font(.caption2)
                        .foregroundColor(Theme.lxTextSecondary)
                }
            }

            // Rider Info
            if let request = request {
                HStack(spacing: 12) {
                    // Rider Avatar
                    ZStack {
                        Circle()
                            .fill(Theme.lxOrange.opacity(0.15))
                            .frame(width: 50, height: 50)
                        Text(String((request.customer_name ?? "R").prefix(1)))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.lxOrange)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(request.customer_name ?? "Rider")
                            .font(.headline)
                            .foregroundColor(Theme.lxText)
                        if request.accessibility_requested == true {
                            HStack(spacing: 4) {
                                Image(systemName: "figure.roll")
                                    .font(.caption2)
                                Text("Accessibility requested")
                                    .font(.caption)
                            }
                            .foregroundColor(Theme.lxOrange)
                        } else {
                            Text("Passenger")
                                .font(.caption)
                                .foregroundColor(Theme.lxTextSecondary)
                        }
                    }

                    Spacer()

                    // Quick Actions
                    HStack(spacing: 12) {
                        Button(action: { showChat = true }) {
                            Image(systemName: "message.fill")
                                .font(.title3)
                                .foregroundColor(Theme.lxOrange)
                                .frame(width: 44, height: 44)
                                .background(Theme.lxOrange.opacity(0.12))
                                .cornerRadius(Lx.Radius.button)
                        }

                        Button(action: callRider) {
                            Image(systemName: "phone.fill")
                                .font(.title3)
                                .foregroundColor(hasRiderPhone ? Theme.lxSuccess : Theme.lxTextMuted)
                                .frame(width: 44, height: 44)
                                .background(hasRiderPhone ? Theme.lxSuccess.opacity(0.12) : Theme.lxTextMuted.opacity(0.12))
                                .cornerRadius(Lx.Radius.button)
                        }
                        .disabled(!hasRiderPhone)
                    }
                }
            }
        }
        .padding()
        .background(Theme.lxSurface)
        .cornerRadius(Lx.Radius.sheet)
        .overlay(
            RoundedRectangle(cornerRadius: Lx.Radius.sheet)
                .stroke(Theme.lxHairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 5)
    }

    // MARK: - Action Card

    private var actionCard: some View {
        VStack(spacing: 0) {
            // Route Info
            if let request = request {
                VStack(spacing: 12) {
                    // Current Destination
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(rideStatus == .inProgress ? Lx.Palette.dropoff : Lx.Palette.pickup)
                                .frame(width: 40, height: 40)
                            Image(systemName: rideStatus == .inProgress ? "mappin.circle.fill" : "person.fill")
                                .foregroundColor(Lx.Palette.onAccent)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(rideStatus == .inProgress ? "DROP-OFF" : "PICKUP")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(Theme.lxTextSecondary)

                            Text(rideStatus == .inProgress ? request.dropoff.address : request.pickup.address)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(Theme.lxText)
                                .lineLimit(2)
                        }

                        Spacer()

                        // Navigate Button
                        Button(action: openNavigation) {
                            Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                                .font(.title)
                                .foregroundColor(Theme.lxOrange)
                        }
                    }
                }
                .padding()
            }

            Divider()
                .overlay(Theme.lxHairline)

            // Action Button
            actionButton
                .padding()
        }
        .background(Theme.lxSurface)
        .cornerRadius(Lx.Radius.sheet, corners: [.topLeft, .topRight])
        .overlay(
            RoundedCorner(radius: 20, corners: [.topLeft, .topRight])
                .stroke(Theme.lxHairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: -5)
    }

    // MARK: - Action Button

    @ViewBuilder
    private var actionButton: some View {
        switch rideStatus {
        case .matched, .enRouteToPickup:
            SwipeToConfirmButton(
                label: "Slide — I've Arrived",
                accentColor: Theme.lxSuccess,
                isDisabled: viewModel.isLoading,
                onConfirm: {
                    rideStatus = .arrivedAtPickup
                    viewModel.driverArrived(bid) { success in
                        if !success {
                            rideStatus = .matched
                        }
                    }
                }
            )
            .padding(.horizontal, 24)
            .padding(.vertical, 8)

        case .arrivedAtPickup:
            VStack(spacing: 10) {
                // No-show timer
                if noShowTimerActive {
                    HStack {
                        Image(systemName: "clock")
                            .foregroundColor(noShowTimerSeconds <= 0 ? Theme.lxError : Theme.lxOrange)
                        if noShowTimerSeconds > 0 {
                            Text("Waiting: \(noShowTimerSeconds / 60):\(String(format: "%02d", noShowTimerSeconds % 60))")
                                .font(.subheadline)
                                .foregroundColor(Theme.lxOrange)
                        } else {
                            Text("Wait time exceeded")
                                .font(.subheadline)
                                .foregroundColor(Theme.lxError)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 4)
                }

                SwipeToConfirmButton(
                    label: "Slide to Start Ride",
                    accentColor: Theme.lxOrange,
                    isDisabled: viewModel.isLoading,
                    onConfirm: startRide
                )
                .padding(.horizontal, 24)
                .padding(.vertical, 8)

                // No-show button appears after timer expires
                if noShowTimerSeconds <= 0 {
                    Button(action: { showNoShowAlert = true }) {
                        HStack {
                            Image(systemName: "person.slash")
                            Text("Mark as No-Show")
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(Theme.lxError)
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(Theme.lxError.opacity(0.15))
                        .cornerRadius(Lx.Radius.button)
                    }
                }
            }

        case .inProgress:
            VStack(spacing: 10) {
                Button(action: openNavigation) {
                    HStack {
                        Image(systemName: "map.fill")
                        Text("Navigate to Dropoff")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(Theme.lxOrange)
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(Theme.lxOrange.opacity(0.12))
                    .cornerRadius(Lx.Radius.button)
                }

                SwipeToConfirmButton(
                    label: "Slide to Complete Ride",
                    accentColor: Theme.lxOrange,
                    isDisabled: viewModel.isLoading,
                    onConfirm: completeRide
                )
                .padding(.horizontal, 0)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)

        case .completed:
            rideCompletionSummary
                .frame(maxWidth: .infinity)
                .padding()
        }
    }

    // MARK: - Ride Completion Summary

    private var rideCompletionSummary: some View {
        let completion = viewModel.completionData
        let fare = completion?.final_price ?? finalPrice
        let fee = completion?.platform_fee ?? AppConfig.shared.calculateRidesharePlatformFee(fareAmount: fare)
        let payout = completion?.driver_payout ?? max(0, fare - fee)
        let tip = completion?.tip_amount ?? 0

        return VStack(spacing: 16) {
            // Header
            Image(systemName: "checkmark.circle.fill")
                .font(Lx.Typography.icon)
                .foregroundColor(Theme.lxSuccess)
            Text("Ride Completed!")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(Theme.lxSuccess)

            Divider()
                .overlay(Theme.lxHairline)

            // Route summary
            if let pickup = completion?.pickup?.address ?? request?.pickup.address,
               let dropoff = completion?.dropoff?.address ?? request?.dropoff.address {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Circle().fill(Theme.lxSuccess).frame(width: 8, height: 8)
                        Text(pickup).font(.caption).foregroundColor(Theme.lxTextSecondary).lineLimit(1)
                    }
                    HStack(spacing: 8) {
                        Circle().fill(Theme.lxError).frame(width: 8, height: 8)
                        Text(dropoff).font(.caption).foregroundColor(Theme.lxTextSecondary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Distance & duration
            if let distance = completion?.estimated_distance_km, let duration = completion?.estimated_duration_minutes {
                let miles = distance * 0.621371
                HStack {
                    Label(String(format: "%.1f mi", miles), systemImage: "road.lanes")
                    Spacer()
                    Label("\(duration) min", systemImage: "clock")
                }
                .font(.caption)
                .foregroundColor(Theme.lxTextSecondary)
            }

            Divider()
                .overlay(Theme.lxHairline)

            // Earnings breakdown
            VStack(spacing: 8) {
                earningsRow(label: "Ride Fare", amount: fare)
                earningsRow(label: "Platform Fee", amount: -fee, color: Theme.lxError)
                if tip > 0 {
                    earningsRow(label: "Tip", amount: tip, color: Theme.lxSuccess)
                }

                Divider()
                    .overlay(Theme.lxHairline)

                HStack {
                    Text("Your Earnings")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.lxText)
                    Spacer()
                    Text("$\(String(format: "%.2f", payout + tip))")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.lxSuccess)
                }
            }

            // Passenger name
            if let name = completion?.customer_name ?? request?.customer_name {
                HStack(spacing: 6) {
                    Image(systemName: "person.circle.fill")
                        .foregroundColor(Theme.lxOrange)
                    Text("Passenger: \(name)")
                        .font(.caption)
                        .foregroundColor(Theme.lxTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
                .overlay(Theme.lxHairline)

            // Rate Passenger
            if hasSubmittedRating {
                VStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Theme.lxSuccess)
                        Text("Passenger rated \(passengerRating)/5")
                            .font(.subheadline)
                            .foregroundColor(Theme.lxTextSecondary)
                    }
                    // Dismiss the full-screen cover — onRideDone() clears the
                    // presentedActiveBid in the parent, collapsing the cover.
                    SwipeToConfirmButton(
                        label: "Slide to Done",
                        accentColor: Theme.lxTextMuted,
                        isDisabled: false,
                        onConfirm: { onRideDone() }
                    )
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                }
            } else {
                VStack(spacing: 12) {
                    Text("Rate Passenger")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.lxText)

                    HStack(spacing: 12) {
                        ForEach(1...5, id: \.self) { star in
                            Button(action: { passengerRating = star }) {
                                Image(systemName: star <= passengerRating ? "star.fill" : "star")
                                    .font(.title2)
                                    .foregroundColor(star <= passengerRating ? Theme.lxOrange : Theme.lxTextMuted)
                            }
                        }
                    }

                    TextField("Comment (optional)", text: $passengerComment)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .foregroundColor(Theme.lxText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Theme.lxSurface2)
                        .cornerRadius(Lx.Radius.chip)
                        .overlay(
                            RoundedRectangle(cornerRadius: Lx.Radius.chip)
                                .stroke(Theme.lxHairline, lineWidth: 1)
                        )

                    SwipeToConfirmButton(
                        label: "Slide to Submit Rating",
                        accentColor: Theme.lxOrange,
                        isDisabled: passengerRating == 0,
                        onConfirm: submitPassengerRating
                    )
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private func submitPassengerRating() {
        viewModel.ratePassenger(bid, rating: passengerRating, comment: passengerComment.isEmpty ? nil : passengerComment)
        hasSubmittedRating = true
    }

    private func earningsRow(label: String, amount: Double, color: Color = Theme.lxText) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(Theme.lxTextSecondary)
            Spacer()
            Text(amount >= 0 ? "$\(String(format: "%.2f", amount))" : "-$\(String(format: "%.2f", abs(amount)))")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(color)
        }
    }

    // MARK: - Actions

    private func startNoShowTimer() {
        guard !noShowTimerActive else { return }
        noShowTimerActive = true

        // Resume from the actual elapsed wait time using the backend timestamp.
        // If the driver arrived 3 minutes ago they only need to wait 2 more minutes.
        // Fall back to the full configured wait window when the timestamp is unavailable.
        let noShowWindowSeconds = AppConfig.shared.noShowWaitSeconds
        let elapsed = elapsedSecondsSinceArrival()
        noShowTimerSeconds = max(0, noShowWindowSeconds - elapsed)

        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [self] _ in
                if noShowTimerSeconds > 0 {
                    noShowTimerSeconds -= 1
                } else {
                    timerCancellable?.cancel()
                }
            }
    }

    private func elapsedSecondsSinceArrival() -> Int {
        guard let arrivedAt = bid.ride_request?.driver_arrived_at else { return 0 }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: arrivedAt) else { return 0 }
        return max(0, Int(Date().timeIntervalSince(date)))
    }

    private func startRide() {
        timerCancellable?.cancel()
        noShowTimerActive = false
        rideStatus = .inProgress
        viewModel.startRide(bid) { success in
            if !success {
                rideStatus = .arrivedAtPickup
                noShowTimerActive = true
            }
        }
    }

    private func completeRide() {
        rideStatus = .completed
        viewModel.completeRide(bid) { success in
            if !success {
                rideStatus = .inProgress
            }
        }
    }

    private func callRider() {
        guard let request = request,
              let phone = request.customer_phone,
              !phone.isEmpty else {
            // Phone not available - show alert
            return
        }
        let cleanPhone = phone.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        guard let url = URL(string: "tel://\(cleanPhone)") else { return }
        UIApplication.shared.open(url)
    }

    private func openNavigation() {
        guard let request = request else { return }

        let destination = rideStatus == .inProgress ? request.dropoff : request.pickup
        let coordinate = CLLocationCoordinate2D(
            latitude: destination.latitude,
            longitude: destination.longitude
        )

        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = destination.address
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }

    private func calculateDriverRoute() {
        guard let request = request,
              let currentCoord = locationManager.currentCoordinate else { return }

        // Destination: dropoff if in progress, pickup otherwise
        let destCoord: CLLocationCoordinate2D
        if rideStatus == .inProgress {
            destCoord = CLLocationCoordinate2D(latitude: request.dropoff.latitude, longitude: request.dropoff.longitude)
        } else {
            destCoord = CLLocationCoordinate2D(latitude: request.pickup.latitude, longitude: request.pickup.longitude)
        }

        let dirRequest = MKDirections.Request()
        dirRequest.source = MKMapItem(placemark: MKPlacemark(coordinate: currentCoord))
        dirRequest.destination = MKMapItem(placemark: MKPlacemark(coordinate: destCoord))
        dirRequest.transportType = .automobile

        MKDirections(request: dirRequest).calculate { response, _ in
            if let route = response?.routes.first {
                DispatchQueue.main.async {
                    self.driverRoute = route
                    self.etaMinutes = max(1, Int(route.expectedTravelTime / 60))
                }
            }
        }
    }

    private func updateMapPosition() {
        guard let request = request else { return }

        // Center map between driver, pickup, and dropoff
        let coordinates = [
            locationManager.currentCoordinate ?? CLLocationCoordinate2D(
                latitude: request.pickup.latitude,
                longitude: request.pickup.longitude
            ),
            CLLocationCoordinate2D(
                latitude: request.pickup.latitude,
                longitude: request.pickup.longitude
            ),
            CLLocationCoordinate2D(
                latitude: request.dropoff.latitude,
                longitude: request.dropoff.longitude
            )
        ]

        let validCoordinates = coordinates.filter { $0.isValid }
        guard !validCoordinates.isEmpty else { return }

        let minLat = validCoordinates.map { $0.latitude }.min() ?? 0
        let maxLat = validCoordinates.map { $0.latitude }.max() ?? 0
        let minLng = validCoordinates.map { $0.longitude }.min() ?? 0
        let maxLng = validCoordinates.map { $0.longitude }.max() ?? 0

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )

        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) * 1.5 + 0.01,
            longitudeDelta: (maxLng - minLng) * 1.5 + 0.01
        )

        position = .region(MKCoordinateRegion(center: center, span: span))
    }
}

// MARK: - Corner Radius Extension
// Note: cornerRadius(_:corners:) and RoundedCorner are defined in ViewHelpers.swift

// MARK: - Preview

#if DEBUG
struct ActiveRideView_Previews: PreviewProvider {
    static var previews: some View {
        Text("Preview")
    }
}
#endif
