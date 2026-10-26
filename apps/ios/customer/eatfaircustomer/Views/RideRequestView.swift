import os

private let logger = Logger(subsystem: "com.dollorai.customer", category: "RideRequestView")

import SwiftUI
import MapKit
import CoreLocation
import Combine
import FirebaseAuth
import EatFairShared

/// Uber-style Ride Request View for Customers
struct RideRequestView: View {
    /// When true, the bottom-sheet close (X) button is hidden. Used when this
    /// view is embedded as a root tab (rideshare-only build) where there is
    /// nothing to dismiss back to. Defaults to false so the pushed/presented
    /// usage (from the food Home screen) is unchanged.
    var hideCloseButton: Bool = false

    @StateObject private var viewModel = RideRequestViewModel()
    @StateObject private var locationManager = RideLocationManager()
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) var dismiss

    @State private var showPickupSearch = false
    @State private var showDropoffSearch = false
    @State private var mapPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var showRideExpiredBanner: Bool = false

    var body: some View {
        ZStack {
            // Map Background
            RideMapBackground(
                pickupLocation: viewModel.pickupAddress,
                dropoffLocation: viewModel.dropoffAddress,
                mapPosition: $mapPosition
            )
            .ignoresSafeArea(edges: .top)
            .onAppear {
                // Request location permission on appear
                locationManager.requestLocationPermission()
            }

            // Bottom Sheet
            VStack {
                Spacer()

                RideBottomSheet(
                    viewModel: viewModel,
                    showPickupSearch: $showPickupSearch,
                    showDropoffSearch: $showDropoffSearch,
                    hideCloseButton: hideCloseButton,
                    onRequestRide: requestRide,
                    onDismiss: { dismiss() }
                )
            }

            // Fare estimate loading is shown inline in the button — no blocking overlay

            // Ride Request Loading Overlay
            if viewModel.isLoading {
                Lx.Palette.shadow.opacity(0.75)
                    .ignoresSafeArea()
                ProgressView(viewModel.fareEstimateReceived ? "Requesting ride…" : "Getting fare estimate…")
                    .tint(Theme.lxOrange)
                    .foregroundColor(Theme.lxText)
                    .padding()
                    .background(Theme.lxSurface)
                    .cornerRadius(Lx.Radius.button)
                    .overlay(RoundedRectangle(cornerRadius: Lx.Radius.button).stroke(Theme.lxHairline, lineWidth: 1))
            }

            // Ride Expired Banner
            if showRideExpiredBanner {
                VStack {
                    HStack(spacing: 12) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .foregroundColor(Theme.lxOrange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No drivers available")
                                .font(.subheadline).fontWeight(.semibold)
                                .foregroundColor(Theme.lxText)
                            Text("No drivers accepted your request. Try again?")
                                .font(.caption)
                                .foregroundColor(Theme.lxTextSecondary)
                        }
                        Spacer()
                        Button("Try Again") {
                            withAnimation {
                                showRideExpiredBanner = false
                            }
                            viewModel.resetRide()
                        }
                        .font(.caption).fontWeight(.semibold)
                        .foregroundColor(Lx.Palette.onAccent)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Theme.lxOrange)
                        .cornerRadius(Lx.Radius.chip)
                    }
                    .padding()
                    .background(Theme.lxSurface)
                    .cornerRadius(Lx.Radius.button)
                    .overlay(RoundedRectangle(cornerRadius: Lx.Radius.button).stroke(Theme.lxHairline, lineWidth: 1))
                    .shadow(color: .black.opacity(0.4), radius: 8)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.3), value: showRideExpiredBanner)
                .zIndex(100)
            }
        }
        .preferredColorScheme(.dark)
        .navigationBarHidden(true)
        .sheet(isPresented: $showPickupSearch) {
            RideLocationSearchView(
                title: "Pickup Location",
                onSelect: { address in
                    viewModel.setPickupLocation(
                        street: address.street,
                        city: address.city,
                        state: address.state,
                        zip: address.zip,
                        lat: address.lat,
                        lng: address.lng
                    )
                    showPickupSearch = false
                }
            )
        }
        .sheet(isPresented: $showDropoffSearch) {
            RideLocationSearchView(
                title: "Dropoff Location",
                onSelect: { address in
                    viewModel.setDropoffLocation(
                        street: address.street,
                        city: address.city,
                        state: address.state,
                        zip: address.zip,
                        lat: address.lat,
                        lng: address.lng
                    )
                    showDropoffSearch = false
                }
            )
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage ?? "An error occurred")
        }
        .fullScreenCover(isPresented: $viewModel.isRideActive) {
            RideTrackingView(viewModel: viewModel)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RideRequestExpired"))) { _ in
            withAnimation {
                showRideExpiredBanner = true
            }
            // Auto-dismiss after 10 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                withAnimation {
                    showRideExpiredBanner = false
                }
            }
        }
    }

    private func requestRide() {
        // Resolve customer name: viewModel property > UserDefaults > email prefix > last resort
        var name = authViewModel.customerName
        if name.isEmpty {
            name = UserDefaults.standard.string(forKey: "p2p_customer_name") ?? ""
        }
        if name.isEmpty, !authViewModel.customerEmail.isEmpty {
            // Use email prefix (e.g. "john.doe" from "john.doe@example.com")
            name = authViewModel.customerEmail.components(separatedBy: "@").first ?? ""
        }
        if name.isEmpty {
            // Last resort fallback - should rarely occur since login always sets name
            name = "Customer"
        }
        let email = authViewModel.customerEmail

        viewModel.requestRide(
            customerName: name,
            customerEmail: email,
            customerPhone: UserDefaults.standard.string(forKey: "p2p_customer_phone") ?? Auth.auth().currentUser?.phoneNumber ?? ""
        )
    }
}

// MARK: - Ride Map Background
struct RideMapBackground: View {
    let pickupLocation: RideAddressInput?
    let dropoffLocation: RideAddressInput?
    @Binding var mapPosition: MapCameraPosition

    var body: some View {
        Map(position: $mapPosition) {
            // Pickup Marker
            if let pickup = pickupLocation {
                Annotation("Pickup", coordinate: CLLocationCoordinate2D(
                    latitude: pickup.lat,
                    longitude: pickup.lng
                )) {
                    RidePickupMarker()
                }
            }

            // Dropoff Marker
            if let dropoff = dropoffLocation {
                Annotation("Dropoff", coordinate: CLLocationCoordinate2D(
                    latitude: dropoff.lat,
                    longitude: dropoff.lng
                )) {
                    RideDropoffMarker()
                }
            }

            // User location
            UserAnnotation()
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
        }
        .onAppear {
            updateMapRegion()
        }
        .onChange(of: pickupLocation?.lat) { _, _ in updateMapRegion() }
        .onChange(of: dropoffLocation?.lat) { _, _ in updateMapRegion() }
    }

    private func updateMapRegion() {
        var coordinates: [CLLocationCoordinate2D] = []

        if let pickup = pickupLocation {
            coordinates.append(CLLocationCoordinate2D(latitude: pickup.lat, longitude: pickup.lng))
        }

        if let dropoff = dropoffLocation {
            coordinates.append(CLLocationCoordinate2D(latitude: dropoff.lat, longitude: dropoff.lng))
        }

        guard !coordinates.isEmpty else {
            // Default to user's location or a default region
            mapPosition = .userLocation(fallback: .automatic)
            return
        }

        let latitudes = coordinates.map { $0.latitude }
        let longitudes = coordinates.map { $0.longitude }

        guard let minLat = latitudes.min(),
              let maxLat = latitudes.max(),
              let minLon = longitudes.min(),
              let maxLon = longitudes.max() else {
            return
        }

        let centerLat = (minLat + maxLat) / 2
        let centerLon = (minLon + maxLon) / 2
        let spanLat = (maxLat - minLat) * 1.5 + 0.02
        let spanLon = (maxLon - minLon) * 1.5 + 0.02

        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
            span: MKCoordinateSpan(latitudeDelta: max(spanLat, 0.02), longitudeDelta: max(spanLon, 0.02))
        )

        mapPosition = .region(region)
    }
}

// MARK: - Map Markers
struct RidePickupMarker: View {
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(Lx.Palette.orange)
                    .frame(width: 44, height: 44)
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)

                Image(systemName: "figure.wave")
                    .font(Lx.Typography.title)
                    .foregroundColor(Lx.Palette.onAccent)
            }

            Image(systemName: "triangle.fill")
                .font(Lx.Typography.caption)
                .foregroundColor(Lx.Palette.orange)
                .rotationEffect(.degrees(180))
                .offset(y: -4)
        }
    }
}

struct RideDropoffMarker: View {
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(Theme.lxSuccess)
                    .frame(width: 44, height: 44)
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)

                Image(systemName: "flag.checkered")
                    .font(Lx.Typography.title)
                    .foregroundColor(Lx.Palette.onAccent)
            }

            Image(systemName: "triangle.fill")
                .font(Lx.Typography.caption)
                .foregroundColor(Theme.lxSuccess)
                .rotationEffect(.degrees(180))
                .offset(y: -4)
        }
    }
}

// MARK: - Ride Bottom Sheet
struct RideBottomSheet: View {
    @ObservedObject var viewModel: RideRequestViewModel
    @Binding var showPickupSearch: Bool
    @Binding var showDropoffSearch: Bool
    var hideCloseButton: Bool = false
    let onRequestRide: () -> Void
    let onDismiss: () -> Void

    @State private var showNegotiateSheet = false
    @State private var customFareOffer: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Handle
            RoundedRectangle(cornerRadius: Lx.Radius.grabber)
                .fill(Theme.lxHairline)
                .frame(width: 40, height: 5)
                .padding(.top, 10)

            // Header
            HStack {
                if hideCloseButton {
                    // Keep layout symmetry with the trailing placeholder while
                    // omitting the no-op close control on the root rideshare tab.
                    Image(systemName: "xmark")
                        .font(.title3)
                        .foregroundColor(.clear)
                } else {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.title3)
                            .foregroundColor(Theme.lxTextSecondary)
                    }
                    .accessibilityLabel("Close ride request")
                    .accessibilityHint("Returns to the home screen")
                }

                Spacer()

                Text("Find a Driver")
                    .font(.headline)
                    .foregroundColor(Theme.lxText)

                Spacer()

                // Placeholder for balance
                Image(systemName: "xmark")
                    .font(.title3)
                    .foregroundColor(.clear)
            }
            .padding()

            Divider().overlay(Theme.lxHairline)

            // Location Inputs
            VStack(spacing: 0) {
                // Pickup
                Button(action: { showPickupSearch = true }) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Lx.Palette.pickup.opacity(0.15))
                                .frame(width: 36, height: 36)
                            Circle()
                                .fill(Lx.Palette.pickup)
                                .frame(width: 12, height: 12)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("PICKUP")
                                .font(Lx.Typography.caption.weight(.semibold))
                                .foregroundColor(Lx.Palette.pickup)

                            Text(viewModel.pickupAddress?.fullAddress ?? "Select pickup location")
                                .font(.subheadline)
                                .foregroundColor(viewModel.pickupAddress != nil ? Theme.lxText : Theme.lxTextMuted)
                                .lineLimit(1)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundColor(Theme.lxTextMuted)
                            .font(.caption)
                    }
                    .padding()
                }
                .accessibilityLabel("Select pickup location")
                .accessibilityHint("Opens location search to set where to be picked up")

                // Connector
                HStack {
                    Rectangle()
                        .fill(Theme.lxHairline)
                        .frame(width: 2, height: 24)
                        .padding(.leading, 29)
                    Spacer()
                }

                // Dropoff
                Button(action: { showDropoffSearch = true }) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Lx.Palette.dropoff.opacity(0.15))
                                .frame(width: 36, height: 36)
                            Image(systemName: "mappin")
                                .foregroundColor(Lx.Palette.dropoff)
                                .font(Lx.Typography.footnote.weight(.bold))
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("DROPOFF")
                                .font(Lx.Typography.caption.weight(.semibold))
                                .foregroundColor(Lx.Palette.dropoff)

                            Text(viewModel.dropoffAddress?.fullAddress ?? "Select dropoff location")
                                .font(.subheadline)
                                .foregroundColor(viewModel.dropoffAddress != nil ? Theme.lxText : Theme.lxTextMuted)
                                .lineLimit(1)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundColor(Theme.lxTextMuted)
                            .font(.caption)
                    }
                    .padding()
                }
                .accessibilityLabel("Select dropoff location")
                .accessibilityHint("Opens location search to set your destination")
            }

            Divider().overlay(Theme.lxHairline)

            // TNC-12: Accessibility Request
            if viewModel.canRequestRide {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $viewModel.accessibilityRequested) {
                        HStack(spacing: 8) {
                            Image(systemName: "figure.roll")
                                .foregroundColor(Lx.Palette.orange)
                            Text("I need an accessible vehicle")
                                .font(.subheadline.weight(.medium))
                        }
                    }
                    .tint(Lx.Palette.orange)

                    if viewModel.accessibilityRequested {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Select your needs:")
                                .font(.caption)
                                .foregroundColor(Lx.Palette.textSecondary)

                            ForEach(AccessibilityOption.allCases, id: \.self) { option in
                                HStack {
                                    Image(systemName: viewModel.selectedAccessibilityOptions.contains(option) ? "checkmark.square.fill" : "square")
                                        .foregroundColor(viewModel.selectedAccessibilityOptions.contains(option) ? Theme.lxOrange : Theme.lxTextMuted)
                                    Text(option.label)
                                        .font(.subheadline)
                                        .foregroundColor(Theme.lxText)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    viewModel.toggleAccessibilityOption(option)
                                }
                            }

                            TextField("Additional accessibility notes (optional)", text: $viewModel.accessibilityNotes, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(2...4)
                                .font(.subheadline)
                        }
                        .padding(.leading, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.horizontal)
                .animation(.easeInOut(duration: 0.2), value: viewModel.accessibilityRequested)

                Divider().overlay(Theme.lxHairline)
            }

            // Notes (optional)
            if viewModel.canRequestRide {
                HStack(spacing: 12) {
                    Image(systemName: "note.text")
                        .foregroundColor(Theme.lxTextSecondary)

                    TextField("Add notes for driver (optional)", text: $viewModel.notes)
                        .font(.subheadline)
                        .foregroundColor(Theme.lxText)
                }
                .padding()

                Divider().overlay(Theme.lxHairline)
            }

            // Price Summary - World Class Fare Breakdown (Scrollable to ensure buttons visible)
            // Gated on fareEstimateReceived to prevent showing default values before API responds
            if viewModel.canRequestRide && viewModel.fareEstimateReceived {
                ScrollView {
                    VStack(spacing: 12) {
                    // Trip Estimate Header
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("SUGGESTED OFFER")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(Theme.lxTextSecondary)
                            HStack(spacing: 12) {
                                Label(viewModel.estimatedDistanceText, systemImage: "road.lanes")
                                Label(viewModel.estimatedTimeText, systemImage: "clock")
                            }
                            .font(.subheadline)
                            .foregroundColor(Theme.lxText)
                        }
                        Spacer()
                        if viewModel.surgeMultiplier > 1.0 {
                            VStack(spacing: 2) {
                                Text("\(String(format: "%.1f", viewModel.surgeMultiplier))x")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(Lx.Palette.onAccent)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Theme.lxOrange)
                                    .cornerRadius(Lx.Radius.chip)
                                Text(viewModel.surgeLabel)
                                    .font(.caption2)
                                    .foregroundColor(Theme.lxOrange)
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    Divider().overlay(Theme.lxHairline)

                    // Surge info banner
                    if viewModel.surgeMultiplier > 1.0 {
                        HStack(spacing: 6) {
                            Image(systemName: "flame.fill")
                                .foregroundColor(Theme.lxOrange)
                            Text("Prices are \(Int((viewModel.surgeMultiplier - 1) * 100))% higher due to \(viewModel.surgeLabel.lowercased())")
                                .font(.caption)
                                .foregroundColor(Theme.lxOrange)
                            Spacer()
                        }
                        .padding(8)
                        .background(Theme.lxOrange.opacity(0.1))
                        .cornerRadius(Lx.Radius.chip)
                    }

                    // Suggested Payment Breakdown (Driver sets final price)
                    VStack(spacing: 6) {
                        // Ride fare (distance + time, from the backend estimate)
                        FareLineItem(
                            label: "Ride Fare (\(viewModel.estimatedDistanceText) · \(viewModel.estimatedTimeText))",
                            amount: viewModel.fareBeforeTax
                        )

                        Divider().overlay(Theme.lxHairline)

                        // Tiered Connection Fee with tier description
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Connection Fee")
                                    .font(.subheadline)
                                    .foregroundColor(Theme.lxText)
                                Text(viewModel.platformFeeTierDescription)
                                    .font(.caption2)
                                    .foregroundColor(Theme.lxOrange)
                                Text("Driver pays a matching $\(String(format: "%.2f", viewModel.platformFee))")
                                    .font(.caption2)
                                    .foregroundColor(Theme.lxTextMuted)
                            }
                            Spacer()
                            Text("$\(String(format: "%.2f", viewModel.platformFee))")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(Theme.lxText)
                        }

                        if viewModel.regulatoryFee > 0 {
                            FareLineItem(label: "Regulatory Fee (CPUC)", amount: viewModel.regulatoryFee)
                        }

                        if viewModel.backendTotal == nil && viewModel.taxAmount > 0 {
                            FareLineItem(
                                label: "Tax (\(String(format: "%.2f", viewModel.taxRate * 100))%)",
                                amount: viewModel.taxAmount
                            )
                        }

                        Divider().overlay(Theme.lxHairline)

                        // Fee transparency in green (no percentage claim: the flat fee varies by fare)
                        HStack(spacing: Lx.Spacing.s) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Lx.Palette.success)
                                .font(Lx.Typography.subheadline)
                            Text("Drivers keep the fare minus the flat connection fee")
                                .font(Lx.Typography.subheadline.weight(.semibold))
                                .foregroundColor(Lx.Palette.success)
                            Spacer()
                        }
                    }

                    Divider().overlay(Theme.lxHairline)

                    // Your Offer Summary
                    VStack(spacing: 8) {
                        HStack {
                            Text("Your Offer")
                                .font(.headline)
                                .foregroundColor(Theme.lxText)
                            Spacer()
                            Text("$\(String(format: "%.2f", viewModel.totalAmount))")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(Theme.lxOrange)
                        }

                        // Driver receives info
                        HStack {
                            Image(systemName: "person.fill.checkmark")
                                .foregroundColor(Theme.lxSuccess)
                            Text("Driver receives: $\(String(format: "%.2f", viewModel.driverEarnings))")
                                .font(.caption)
                                .foregroundColor(Theme.lxSuccess)
                            Text("(You pay driver directly)")
                                .font(.caption2)
                                .foregroundColor(Theme.lxTextSecondary)
                        }
                    }

                    Divider().overlay(Theme.lxHairline)

                    // Legal Disclosures (P2P Rideshare Matchmaking)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PEER-TO-PEER RIDESHARE")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(Theme.lxTextSecondary)

                        Text("Dollor.ai connects riders with independent drivers. Drivers set their own rates and may accept, decline, or counter your offer. The connection fee is for using our matchmaking service. Transportation is provided directly by the driver, not Dollor.ai. By using this service, you agree to our Terms of Service.")
                            .font(.caption2)
                            .foregroundColor(Theme.lxTextMuted)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 4) {
                            Image(systemName: "info.circle")
                                .font(.caption2)
                            Text("Connection fee: $\(String(format: "%.2f", viewModel.platformFee)) (tiered \(AppConfig.shared.rideshareFeeRangeText)) • Driver sets final price")
                                .font(.caption2)
                        }
                        .foregroundColor(Theme.lxTextMuted)
                        .padding(.top, 2)
                    }
                    .padding(.vertical, 4)
                    }
                    .padding()
                }
                .frame(maxHeight: 320) // Limit height to ensure action buttons remain visible
            }

            // Action Buttons
            VStack(spacing: 12) {
                // Find Driver with Suggested Offer
                Button(action: { if viewModel.canRequestRide && !viewModel.isLoading { onRequestRide() } }) {
                    HStack(spacing: Lx.Spacing.s) {
                        if viewModel.isEstimatingFare || viewModel.isLoading {
                            ProgressView()
                                .tint(Lx.Palette.text)
                                .scaleEffect(0.85)
                        }
                        Text(viewModel.isLoading
                             ? "Checking payment…"
                             : viewModel.isEstimatingFare
                             ? "Estimating fare…"
                             : "Find Driver • $\(String(format: "%.2f", viewModel.estimatedFare))")
                    }
                }
                .buttonStyle(.lxPrimary)
                .disabled(!viewModel.canRequestRide || viewModel.isLoading)
                .padding(.horizontal, 24)
                .padding(.vertical, 8)

                // Make Custom Offer Button
                Button(action: { showNegotiateSheet = true }) {
                    Label("Make a Different Offer", systemImage: "dollarsign.arrow.circlepath")
                }
                .buttonStyle(.lxSecondary)
                .padding(.horizontal, 24)
                .disabled(!viewModel.canRequestRide)
                .accessibilityLabel("Make a different offer")
                .accessibilityHint("Opens negotiation to offer a custom fare amount")

                // Info text - P2P matchmaking disclaimer with tiered pricing
                HStack(spacing: 4) {
                    Image(systemName: "info.circle.fill")
                        .font(Lx.Typography.caption)
                        .foregroundColor(Lx.Palette.success)
                    Text("\(AppConfig.shared.rideshareFeeRangeText) tiered connection fee • Drivers are independent")
                        .font(Lx.Typography.caption)
                        .foregroundColor(Lx.Palette.textSecondary)
                }
            }
            .padding()
        }
        .background(
            RoundedRectangle(cornerRadius: Lx.Radius.sheet)
                .fill(Theme.lxSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: Lx.Radius.sheet)
                        .stroke(Theme.lxHairline, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: -5)
        )
        .sheet(isPresented: $showNegotiateSheet) {
            PreRequestNegotiationSheet(
                viewModel: viewModel,
                isPresented: $showNegotiateSheet,
                onRequestWithOffer: { offer in
                    viewModel.initialFareOffer = offer
                    showNegotiateSheet = false
                    onRequestRide()
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        // Payment method required before booking — shown when customer has no saved card.
        // Must live here (pre-booking state) because RideStatusCard doesn't exist yet.
        .sheet(isPresented: $viewModel.showPaymentMethodsSheet, onDismiss: {
            viewModel.retryAcceptBidAfterPaymentSetup()
        }) {
            PaymentMethodsView()
        }
    }
}

// MARK: - Pre-Request Negotiation Sheet
struct PreRequestNegotiationSheet: View {
    @ObservedObject var viewModel: RideRequestViewModel
    @Binding var isPresented: Bool
    let onRequestWithOffer: (Double) -> Void

    @State private var customOffer: String = ""
    @State private var selectedQuickOffer: Double? = nil

    private var estimatedFare: Double { viewModel.estimatedFare }
    private var platformFee: Double { AppConfig.shared.calculateRidesharePlatformFee(fareAmount: estimatedFare) }

    private var minFare: Double { AppConfig.shared.rideMinFare }

    private var quickOfferOptions: [Double] {
        let base = estimatedFare
        return [
            max(minFare, base * 0.6),  // 40% off
            max(minFare, base * 0.7),  // 30% off
            max(minFare, base * 0.8),  // 20% off
            max(minFare, base * 0.9)   // 10% off
        ].map { round($0 * 100) / 100 }
    }

    private var currentOffer: Double? {
        if let selected = selectedQuickOffer {
            return selected
        }
        if let custom = Double(customOffer), custom >= minFare {
            return custom
        }
        return nil
    }

    private var driverEarnings: Double {
        guard let offer = currentOffer else { return 0 }
        let taxRate = StateTaxRates.rate(for: viewModel.pickupAddress?.state ?? "TX")
        return offer - platformFee - (offer * taxRate)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Theme.lxOrange.opacity(0.15))
                                .frame(width: 80, height: 80)
                            Image(systemName: "dollarsign.arrow.circlepath")
                                .font(Lx.Typography.icon)
                                .foregroundColor(Theme.lxOrange)
                        }

                        Text("Make Your Offer")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.lxText)

                        Text("Independent drivers can accept, decline, or counter")
                            .font(.subheadline)
                            .foregroundColor(Theme.lxTextSecondary)
                    }
                    .padding(.top)

                    // Suggested vs Your Offer
                    HStack(spacing: 20) {
                        VStack(spacing: 4) {
                            Text("Suggested")
                                .font(.caption)
                                .foregroundColor(Theme.lxTextSecondary)
                            Text("$\(String(format: "%.2f", estimatedFare))")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(Theme.lxTextSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Theme.lxSurface)
                        .cornerRadius(Lx.Radius.button)
                        .overlay(RoundedRectangle(cornerRadius: Lx.Radius.button).stroke(Theme.lxHairline, lineWidth: 1))

                        VStack(spacing: 4) {
                            Text("Your Offer")
                                .font(.caption)
                                .foregroundColor(Theme.lxOrange)
                            Text(currentOffer != nil ? "$\(String(format: "%.2f", currentOffer!))" : "--")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(Theme.lxOrange)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Theme.lxOrange.opacity(0.12))
                        .cornerRadius(Lx.Radius.button)
                        .overlay(RoundedRectangle(cornerRadius: Lx.Radius.button).stroke(Theme.lxOrange.opacity(0.35), lineWidth: 1))
                    }
                    .padding(.horizontal)

                    // Quick Offer Buttons
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Quick Offers")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(Theme.lxText)
                            .padding(.horizontal)

                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            ForEach(quickOfferOptions, id: \.self) { amount in
                                Button(action: {
                                    selectedQuickOffer = amount
                                    customOffer = ""
                                }) {
                                    VStack(spacing: 4) {
                                        Text("\(Lx.Money.text(amount))")
                                            .font(.headline)
                                        let savings = estimatedFare - amount
                                        if savings > 0 {
                                            Text("Save \(Lx.Money.text(savings))")
                                                .font(.caption2)
                                                .foregroundColor(selectedQuickOffer == amount ? .white : Theme.lxSuccess)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(selectedQuickOffer == amount ? Theme.lxOrange : Theme.lxSurface2)
                                    .foregroundColor(selectedQuickOffer == amount ? .white : Theme.lxText)
                                    .cornerRadius(Lx.Radius.button)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Custom Amount
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Or enter custom amount")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(Theme.lxText)

                        HStack {
                            Text("$")
                                .font(.title2)
                                .foregroundColor(Theme.lxTextSecondary)
                            TextField("0.00", text: $customOffer)
                                .font(.title2)
                                .foregroundColor(Theme.lxText)
                                .keyboardType(.decimalPad)
                                .onChange(of: customOffer) { _, _ in
                                    selectedQuickOffer = nil
                                }
                        }
                        .padding()
                        .background(Theme.lxSurface2)
                        .cornerRadius(Lx.Radius.button)
                        .overlay(RoundedRectangle(cornerRadius: Lx.Radius.button).stroke(Theme.lxHairline, lineWidth: 1))

                        Text("Minimum fare: $\(String(format: "%.2f", AppConfig.shared.rideMinFare))")
                            .font(.caption)
                            .foregroundColor(Theme.lxTextSecondary)
                    }
                    .padding(.horizontal)

                    // Driver Payment Preview
                    if currentOffer != nil {
                        VStack(spacing: 8) {
                            Divider().overlay(Theme.lxHairline)

                            HStack {
                                Image(systemName: "person.fill.checkmark")
                                    .foregroundColor(Theme.lxSuccess)
                                Text("Driver would receive:")
                                    .font(.subheadline)
                                    .foregroundColor(Theme.lxText)
                                Spacer()
                                Text("$\(String(format: "%.2f", driverEarnings))")
                                    .font(.headline)
                                    .foregroundColor(Theme.lxSuccess)
                            }
                            .padding()
                            .background(Theme.lxSuccess.opacity(0.1))
                            .cornerRadius(Lx.Radius.button)

                            HStack(spacing: 4) {
                                Image(systemName: "info.circle")
                                Text("Connection fee: \(Lx.Money.text(platformFee)) • Driver is independent")
                            }
                            .font(.caption)
                            .foregroundColor(Theme.lxTextSecondary)
                        }
                        .padding(.horizontal)
                    }

                    Spacer(minLength: 20)
                }
            }
            .background(Theme.lxBg)
            .navigationTitle("Make an Offer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .accessibilityLabel("Cancel custom offer")
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    Button(action: {
                        if let offer = currentOffer {
                            onRequestWithOffer(offer)
                        }
                    }) {
                        Text(currentOffer != nil
                             ? "Request with \(Lx.Money.text(currentOffer!)) Offer"
                             : "Enter an amount")
                            .font(Lx.Typography.body.weight(.bold))
                            .foregroundColor(Lx.Palette.onAccent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                currentOffer != nil
                                ? AnyView(LinearGradient(colors: [Lx.Palette.orangeBright, Lx.Palette.orange],
                                                         startPoint: .top, endPoint: .bottom))
                                : AnyView(Lx.Palette.textMuted.opacity(0.4))
                            )
                            .cornerRadius(Lx.Radius.button)
                            .shadow(color: currentOffer != nil ? Lx.Palette.orange.opacity(0.4) : .clear,
                                    radius: 14, y: 6)
                    }
                    .disabled(currentOffer == nil)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                }
                .padding()
                .background(Theme.lxSurface)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Location Search View
struct RideLocationSearchView: View {
    let title: String
    let onSelect: (RideAddressInput) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var searchText = ""
    @State private var searchResults: [SearchResult] = []
    @State private var isSearching = false
    @State private var showResults = false

    // Uber-style map pin picker state
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var centerCoordinate: CLLocationCoordinate2D?
    @State private var resolvedAddress: RideAddressInput?
    @State private var resolvedDisplay: String = ""
    @State private var isGeocoding = false
    @State private var didCenterOnUser = false
    // Debounce handle so dragging the map doesn't hammer the (rate-limited) geocoder.
    @State private var geocodeWorkItem: DispatchWorkItem?

    @StateObject private var locationManager = RideLocationManager()

    struct SearchResult: Identifiable {
        let id = UUID()
        let name: String
        let address: String
        let lat: Double
        let lng: Double
        var street: String = ""
        var city: String = ""
        var state: String = ""
        var zip: String = ""
    }

    // Pickup vs dropoff is driven purely by the title the caller passes in.
    private var isPickup: Bool { title.localizedCaseInsensitiveContains("pickup") }
    private var accentColor: Color { isPickup ? Lx.Palette.pickup : Lx.Palette.dropoff }
    private var confirmTitle: String { isPickup ? "Confirm pickup" : "Confirm dropoff" }
    private var hereLabel: String { isPickup ? "Pickup here" : "Dropoff here" }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                mapLayer
                centerPin
                overlayControls
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel location search")
                }
            }
            .onAppear {
                locationManager.requestLocationPermission()
                centerOnCurrentLocationIfNeeded()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Map

    private var mapLayer: some View {
        Map(position: $cameraPosition) {
            UserAnnotation()
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
        }
        .ignoresSafeArea()
        // Track the center continuously (so Confirm always has a coordinate) and
        // debounce the reverse-geocode so it only fires once the drag settles.
        .onMapCameraChange(frequency: .continuous) { context in
            let center = context.region.center
            centerCoordinate = center
            scheduleReverseGeocode(center)
        }
    }

    /// Fixed pin overlaid at the screen center — it stays put while the map moves
    /// underneath it (this is an overlay, not a map annotation).
    private var centerPin: some View {
        VStack(spacing: 0) {
            Image(systemName: "mappin")
                .font(Lx.Typography.icon.weight(.bold))
                .foregroundColor(accentColor)
                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
            // Small ground shadow sitting at the exact center coordinate.
            Ellipse()
                .fill(Lx.Palette.shadow.opacity(0.25))
                .frame(width: 10, height: 4)
        }
        // Raise the glyph so its point rests on the ground dot (true center).
        .offset(y: -18)
        .allowsHitTesting(false)
    }

    // MARK: - Overlay (search + confirm card)

    private var overlayControls: some View {
        VStack(spacing: 0) {
            searchField

            if showResults {
                resultsList
            }

            Spacer()

            confirmCard
        }
    }

    private var searchField: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Theme.lxTextSecondary)

                TextField("Search address...", text: $searchText)
                    .textFieldStyle(.plain)
                    .foregroundColor(Theme.lxText)
                    .autocorrectionDisabled()

                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        searchResults = []
                        showResults = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Theme.lxTextSecondary)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding()
            .background(Theme.lxSurface)
            .cornerRadius(Lx.Radius.button)
            .overlay(RoundedRectangle(cornerRadius: Lx.Radius.button).stroke(Theme.lxHairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 2)
            .onChange(of: searchText) { _, newValue in
                showResults = !newValue.isEmpty
                searchAddress(newValue)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if isSearching {
                    ProgressView()
                        .padding()
                } else {
                    ForEach(searchResults) { result in
                        Button(action: { recenter(on: result) }) {
                            HStack(spacing: 12) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(Theme.lxOrange)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.name)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(Theme.lxText)
                                    Text(result.address)
                                        .font(.caption)
                                        .foregroundColor(Theme.lxTextSecondary)
                                        .lineLimit(1)
                                }

                                Spacer()
                            }
                            .padding()
                        }

                        Divider().overlay(Theme.lxHairline)
                            .padding(.leading, 56)
                    }
                }
            }
        }
        .frame(maxHeight: 280)
        .background(Theme.lxSurface)
        .cornerRadius(Lx.Radius.button)
        .overlay(RoundedRectangle(cornerRadius: Lx.Radius.button).stroke(Theme.lxHairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 2)
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var confirmCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundColor(accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(hereLabel)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(accentColor)

                    if isGeocoding && resolvedDisplay.isEmpty {
                        Text("Finding address…")
                            .font(.subheadline)
                            .foregroundColor(Theme.lxTextSecondary)
                    } else {
                        Text(resolvedDisplay.isEmpty ? "Move the map to choose a spot" : resolvedDisplay)
                            .font(.subheadline)
                            .foregroundColor(resolvedDisplay.isEmpty ? Theme.lxTextMuted : Theme.lxText)
                            .lineLimit(2)
                    }
                }

                Spacer()

                if isGeocoding {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }

            Button(action: commit) {
                Text(confirmTitle)
                    .font(.headline)
                    .foregroundColor(Lx.Palette.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(centerCoordinate != nil ? accentColor : Lx.Palette.textMuted)
                    .cornerRadius(Lx.Radius.button)
            }
            .disabled(centerCoordinate == nil)
            .accessibilityLabel(confirmTitle)
            .accessibilityHint("Uses the location under the center pin")
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: Lx.Radius.sheet)
                .fill(Theme.lxSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: Lx.Radius.sheet)
                        .stroke(Theme.lxHairline, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: -4)
        )
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - Reverse geocoding (debounced)

    private func scheduleReverseGeocode(_ coordinate: CLLocationCoordinate2D) {
        geocodeWorkItem?.cancel()
        if !isGeocoding { isGeocoding = true }
        let work = DispatchWorkItem { reverseGeocode(coordinate) }
        geocodeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func reverseGeocode(_ coordinate: CLLocationCoordinate2D) {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
            DispatchQueue.main.async {
                isGeocoding = false

                guard let placemark = placemarks?.first else {
                    // Keep the coordinate usable even if the geocoder returns nothing.
                    resolvedAddress = RideAddressInput(
                        street: "Dropped pin",
                        city: "",
                        state: "",
                        zip: "",
                        lat: coordinate.latitude,
                        lng: coordinate.longitude
                    )
                    resolvedDisplay = String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
                    return
                }

                let streetNumber = placemark.subThoroughfare ?? ""
                let streetName = placemark.thoroughfare ?? ""
                let fullStreet = [streetNumber, streetName].filter { !$0.isEmpty }.joined(separator: " ")

                let address = RideAddressInput(
                    street: fullStreet.isEmpty ? (placemark.name ?? "Dropped pin") : fullStreet,
                    city: placemark.locality ?? "",
                    state: placemark.administrativeArea ?? "",
                    zip: placemark.postalCode ?? "",
                    lat: coordinate.latitude,
                    lng: coordinate.longitude
                )
                resolvedAddress = address
                resolvedDisplay = address.fullAddress.isEmpty ? (placemark.name ?? "") : address.fullAddress
            }
        }
    }

    // MARK: - Actions

    /// Recenter the map on a tapped search result; the user still confirms by button.
    private func recenter(on result: SearchResult) {
        let coordinate = CLLocationCoordinate2D(latitude: result.lat, longitude: result.lng)
        centerCoordinate = coordinate
        resolvedAddress = RideAddressInput(
            street: result.street.isEmpty ? result.name : result.street,
            city: result.city,
            state: result.state,
            zip: result.zip,
            lat: result.lat,
            lng: result.lng
        )
        resolvedDisplay = result.address.isEmpty ? result.name : result.address
        withAnimation {
            cameraPosition = .region(MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))
        }
        searchText = ""
        searchResults = []
        showResults = false
    }

    /// On first appearance, recenter the map on the user's current location.
    private func centerOnCurrentLocationIfNeeded() {
        guard !didCenterOnUser else { return }
        locationManager.getCurrentLocation { location in
            guard let location = location else { return }
            didCenterOnUser = true
            DispatchQueue.main.async {
                withAnimation {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: location.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    ))
                }
            }
        }
    }

    /// Single commit point — hand the chosen address back exactly as before.
    private func commit() {
        if let address = resolvedAddress {
            onSelect(address)
        } else if let coordinate = centerCoordinate {
            onSelect(RideAddressInput(
                street: "Dropped pin",
                city: "",
                state: "",
                zip: "",
                lat: coordinate.latitude,
                lng: coordinate.longitude
            ))
        }
    }

    private func searchAddress(_ query: String) {
        guard query.count > 2 else {
            searchResults = []
            return
        }

        isSearching = true

        // Use MKLocalSearch for address lookup (addresses + specific places/landmarks)
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]
        // Bias results to the area the user is currently viewing so matches are
        // specific/local instead of a far-away city centroid.
        if let center = centerCoordinate {
            request.region = MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
            )
        }

        let search = MKLocalSearch(request: request)
        search.start { response, error in
            DispatchQueue.main.async {
                isSearching = false

                guard let response = response else { return }

                searchResults = response.mapItems.prefix(10).map { item in
                    let pm = item.placemark
                    let streetNum = pm.subThoroughfare ?? ""
                    let streetName = pm.thoroughfare ?? ""
                    let street = [streetNum, streetName].filter { !$0.isEmpty }.joined(separator: " ")
                    return SearchResult(
                        name: item.name ?? "Unknown",
                        address: item.placemark.formattedAddress,
                        lat: item.placemark.coordinate.latitude,
                        lng: item.placemark.coordinate.longitude,
                        street: street.isEmpty ? (item.name ?? "") : street,
                        city: pm.locality ?? "",
                        state: pm.administrativeArea ?? "",
                        zip: pm.postalCode ?? ""
                    )
                }
            }
        }
    }

}

// MARK: - Location Manager for Ride Request
class RideLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var locationCompletion: ((CLLocation?) -> Void)?

    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentLocation: CLLocation?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = locationManager.authorizationStatus
    }

    func requestLocationPermission() {
        if authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
    }

    func getCurrentLocation(completion: @escaping (CLLocation?) -> Void) {
        locationCompletion = completion

        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.requestLocation()
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        default:
            completion(nil)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            currentLocation = location
            locationCompletion?(location)
            locationCompletion = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        logger.debug("Location error: \(error.localizedDescription)")
        locationCompletion?(nil)
        locationCompletion = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        // If just authorized, try to get location
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            if locationCompletion != nil {
                locationManager.requestLocation()
            }
        }
    }
}

// MARK: - Fare Line Item
struct FareLineItem: View {
    let label: String
    let amount: Double

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(Theme.lxTextSecondary)
            Spacer()
            Text("$\(String(format: "%.2f", amount))")
                .font(.subheadline)
                .foregroundColor(Theme.lxText)
        }
    }
}

// MARK: - MKPlacemark Extension
extension MKPlacemark {
    var formattedAddress: String {
        let components = [
            thoroughfare,
            locality,
            administrativeArea,
            postalCode
        ].compactMap { $0 }
        return components.joined(separator: ", ")
    }
}

// MARK: - Ride Tracking View
struct RideTrackingView: View {
    @ObservedObject var viewModel: RideRequestViewModel
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var route: MKRoute?
    @State private var showSOSAlert = false
    @State private var showShareSheet = false
    // Live fallback ETA computed from the same MKDirections route used for the polyline
    // (see calculateRoute()). Used only when the backend hasn't supplied currentETAMinutes,
    // so the ETA overlay never silently disappears while a driver location is known.
    @State private var clientETAMinutes: Int?

    var body: some View {
        ZStack {
            // Map
            Map(position: $mapPosition) {
                // Pickup
                if let pickup = viewModel.pickupAddress {
                    Annotation("Pickup", coordinate: CLLocationCoordinate2D(
                        latitude: pickup.lat,
                        longitude: pickup.lng
                    )) {
                        RidePickupMarker()
                    }
                }

                // Dropoff
                if let dropoff = viewModel.dropoffAddress {
                    Annotation("Dropoff", coordinate: CLLocationCoordinate2D(
                        latitude: dropoff.lat,
                        longitude: dropoff.lng
                    )) {
                        RideDropoffMarker()
                    }
                }

                // Driver location
                if let tracking = viewModel.rideTracking,
                   let lat = tracking.driverLatitude,
                   let lng = tracking.driverLongitude {
                    Annotation("Driver", coordinate: CLLocationCoordinate2D(
                        latitude: lat,
                        longitude: lng
                    )) {
                        ZStack {
                            Circle()
                                .fill(Lx.Palette.shadow)
                                .frame(width: 40, height: 40)
                            Image(systemName: "car.fill")
                                .foregroundColor(Lx.Palette.onAccent)
                        }
                    }
                }

                // Route polyline
                if let route = route {
                    MapPolyline(route.polyline)
                        .stroke(Lx.Palette.orange, lineWidth: 5)
                }

                UserAnnotation()
            }
            .ignoresSafeArea(edges: .top)
            .onChange(of: viewModel.rideTracking?.driverLatitude) { _, _ in
                calculateRoute()
            }
            .onAppear { calculateRoute() }

            // ETA Overlay (top-left)
            VStack {
                HStack {
                    if let tracking = viewModel.rideTracking,
                       let eta = tracking.currentETAMinutes ?? clientETAMinutes {
                        VStack(spacing: 2) {
                            Text("\(eta)")
                                .font(Font.system(size: 36, weight: .bold, design: .rounded))
                                .foregroundColor(Lx.Palette.onAccent)
                            Text(tracking.status == "in_progress" ? "min to arrive" : "min away")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.9))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Lx.Palette.shadow.opacity(0.75))
                        .cornerRadius(Lx.Radius.card)
                        .padding(.leading, 16)
                        .padding(.top, 8)
                    }
                    Spacer()
                }
                Spacer()
            }

            // Safety Buttons (top-right)
            VStack {
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
                        Button(action: { showSOSAlert = true }) {
                            Text("SOS")
                                .font(.caption)
                                .fontWeight(.heavy)
                                .foregroundColor(Lx.Palette.onAccent)
                                .frame(width: 50, height: 50)
                                .background(Lx.Palette.error)
                                .clipShape(Circle())
                                .shadow(color: .red.opacity(0.4), radius: 4)
                        }
                        .accessibilityLabel("Emergency SOS")
                        .accessibilityHint("Calls 911 emergency services")

                        Button(action: { showShareSheet = true }) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.callout)
                                .fontWeight(.semibold)
                                .foregroundColor(Lx.Palette.onAccent)
                                .frame(width: 44, height: 44)
                                .background(Lx.Palette.orange)
                                .clipShape(Circle())
                                .shadow(color: Lx.Palette.orange.opacity(0.3), radius: 4)
                        }
                        .accessibilityLabel("Share trip")
                        .accessibilityHint("Share your trip details with someone")
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 60)
                }
                Spacer()
            }

            // Bottom Info Card
            VStack {
                Spacer()

                RideStatusCard(viewModel: viewModel)
            }
        }
        .alert("Emergency SOS", isPresented: $showSOSAlert) {
            Button("Call 911", role: .destructive) {
                if let url = URL(string: "tel://911") {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will call emergency services (911). Only use in a real emergency.")
        }
        .sheet(isPresented: $showShareSheet) {
            ShareTripActivityView(shareText: tripShareText)
        }
        .preferredColorScheme(.dark)
    }

    private var tripShareText: String {
        var text = "I'm on a Dollor ride!"
        if let ride = viewModel.activeRide {
            text += " Ride #\(ride.rideNumber ?? "N/A")"
        }
        if let pickup = viewModel.pickupAddress {
            text += "\nFrom: \(pickup.street)"
        }
        if let dropoff = viewModel.dropoffAddress {
            text += "\nTo: \(dropoff.street)"
        }
        if let driver = viewModel.acceptedDriver {
            text += "\nDriver: \(driver.name ?? "Unknown")"
            if let plate = driver.license_plate {
                text += " (\(plate))"
            }
        }
        text += "\n\nShared via Dollor - dollor.ai"
        return text
    }

    private func calculateRoute() {
        guard let tracking = viewModel.rideTracking,
              let driverLat = tracking.driverLatitude,
              let driverLng = tracking.driverLongitude else { return }

        let driverCoord = CLLocationCoordinate2D(latitude: driverLat, longitude: driverLng)

        // Destination: dropoff if in progress, pickup if en route
        let destCoord: CLLocationCoordinate2D
        if viewModel.currentStep == .rideInProgress, let dropoff = viewModel.dropoffAddress {
            destCoord = CLLocationCoordinate2D(latitude: dropoff.lat, longitude: dropoff.lng)
        } else if let pickup = viewModel.pickupAddress {
            destCoord = CLLocationCoordinate2D(latitude: pickup.lat, longitude: pickup.lng)
        } else {
            return
        }

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: driverCoord))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destCoord))
        request.transportType = .automobile

        MKDirections(request: request).calculate { response, _ in
            if let route = response?.routes.first {
                DispatchQueue.main.async {
                    self.route = route
                    self.clientETAMinutes = max(1, Int((route.expectedTravelTime / 60).rounded()))
                }
            }
        }
    }
}

// MARK: - Ride Status Card
struct RideStatusCard: View {
    @ObservedObject var viewModel: RideRequestViewModel
    @State private var showCancelConfirm = false
    @State private var showNegotiateSheet = false
    @State private var customerOfferAmount: String = ""

    // Completion flow states
    @State private var selectedRating: Int = 0
    @State private var ratingFeedback: String = ""
    @State private var selectedTipAmount: Double = 0
    @State private var customTipAmount: String = ""
    @State private var showCustomTip = false
    @State private var isSubmittingRating = false
    @State private var isSubmittingTip = false
    @State private var ratingSubmitted = false
    @State private var tipSubmitted = false
    @State private var showChatSheet = false
    @State private var showRatingError = false
    @State private var ratingErrorMessage = ""
    @State private var showTipError = false
    @State private var tipErrorMessage = ""

    var statusText: String {
        switch viewModel.currentStep {
        case .waitingForDriver:
            return "Finding available drivers..."
        case .driverEnRoute:
            return "Driver accepted and is on the way!"
        case .rideInProgress:
            if let eta = viewModel.rideTracking?.etaDestinationMinutes {
                return "In transit — arriving in ~\(eta) min"
            }
            return "In transit with driver"
        case .completed:
            return "Trip completed!"
        default:
            return "Processing..."
        }
    }

    var statusIcon: String {
        switch viewModel.currentStep {
        case .waitingForDriver:
            return "magnifyingglass"
        case .driverEnRoute:
            return "car.fill"
        case .rideInProgress:
            return "arrow.right"
        case .completed:
            return "checkmark.circle.fill"
        default:
            return "clock"
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Handle
            RoundedRectangle(cornerRadius: Lx.Radius.grabber)
                .fill(Theme.lxHairline)
                .frame(width: 40, height: 5)
                .padding(.top, 10)

            // Status
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Theme.lxOrange.opacity(0.15))
                        .frame(width: 50, height: 50)

                    if viewModel.currentStep == .waitingForDriver {
                        ProgressView()
                            .tint(Theme.lxOrange)
                    } else {
                        Image(systemName: statusIcon)
                            .font(.title2)
                            .foregroundColor(Theme.lxOrange)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(statusText)
                        .font(.headline)
                        .foregroundColor(Theme.lxText)

                    if let ride = viewModel.activeRide {
                        Text("Ride #\(ride.rideNumber ?? "—")")
                            .font(.caption)
                            .foregroundColor(Theme.lxTextSecondary)
                    }
                }

                Spacer()

                // Cancel button (when cancellation is allowed)
                if viewModel.currentStep != .completed && viewModel.currentStep != .rideInProgress {
                    Button(action: { showCancelConfirm = true }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.red.opacity(0.7))
                    }
                    .accessibilityLabel("Cancel ride")
                    .accessibilityHint("Opens confirmation to cancel your ride request")
                }
            }
            .padding(.horizontal)

            // MARK: - Incoming Driver Bids Section (P2P Bidding)
            if viewModel.currentStep == .waitingForDriver && !viewModel.incomingBids.isEmpty {
                Divider().overlay(Theme.lxHairline)

                VStack(spacing: 12) {
                    HStack {
                        ZStack {
                            Circle()
                                .fill(Theme.lxSuccess.opacity(0.15))
                                .frame(width: 40, height: 40)
                            Image(systemName: "person.3.fill")
                                .foregroundColor(Theme.lxSuccess)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(viewModel.incomingBids.count) Driver\(viewModel.incomingBids.count == 1 ? "" : "s") Available")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(Theme.lxText)
                            Text("Tap to view and select a driver")
                                .font(.caption)
                                .foregroundColor(Theme.lxTextSecondary)
                        }

                        Spacer()

                        Button(action: { viewModel.showBidsSheet = true }) {
                            Text("View Bids")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(Lx.Palette.onAccent)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Theme.lxSuccess)
                                .cornerRadius(Lx.Radius.chip)
                        }
                        .accessibilityLabel("View driver bids")
                        .accessibilityHint("Shows available drivers and their fare offers")
                    }
                }
                .padding(.horizontal)
            }

            // MARK: - Accepted Driver Details Section
            if let driver = viewModel.acceptedDriver {
                Divider().overlay(Theme.lxHairline)

                VStack(spacing: 12) {
                    // Driver Row with Photo, Name, Rating
                    HStack(spacing: 12) {
                        // Driver Photo
                        if let photoUrl = driver.photo_url,
                           let url = URL(string: photoUrl.hasPrefix("http") ? photoUrl : "\(AppConfig.shared.cdnBaseURL)\(photoUrl)") {
                            AsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 60, height: 60)
                                    .clipShape(Circle())
                            } placeholder: {
                                driverPhotoPlaceholder
                            }
                        } else {
                            driverPhotoPlaceholder
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(driver.name ?? "Driver")
                                    .font(.headline)
                                    .foregroundColor(Theme.lxText)
                                if let rating = driver.rating {
                                    HStack(spacing: 2) {
                                        Image(systemName: "star.fill")
                                            .font(.caption2)
                                            .foregroundColor(.yellow)
                                        Text(String(format: "%.1f", rating))
                                            .font(.caption)
                                            .foregroundColor(Theme.lxTextSecondary)
                                    }
                                }
                            }

                            if viewModel.driverHasArrived {
                                HStack(spacing: 4) {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(Theme.lxSuccess)
                                    Text("Driver has arrived!")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(Theme.lxSuccess)
                                }
                            } else if let eta = viewModel.driverETA {
                                HStack(spacing: 4) {
                                    Image(systemName: "clock.fill")
                                        .font(.caption)
                                        .foregroundColor(Lx.Palette.orange)
                                    Text("Arriving in ~\(eta) min")
                                        .font(.subheadline)
                                        .foregroundColor(Lx.Palette.orange)
                                }
                            }
                        }

                        Spacer()

                        // Chat button
                        if viewModel.activeRide?.rideId != nil {
                            Button(action: { showChatSheet = true }) {
                                Image(systemName: "message.fill")
                                    .font(.title3)
                                    .foregroundColor(Lx.Palette.onAccent)
                                    .frame(width: 44, height: 44)
                                    .background(Lx.Palette.orange)
                                    .clipShape(Circle())
                            }
                            .accessibilityLabel("Chat with driver")
                            .accessibilityHint("Opens chat with your driver")
                        }

                        if let phone = driver.phone {
                            Button(action: { callDriver(phone) }) {
                                Image(systemName: "phone.fill")
                                    .font(.title3)
                                    .foregroundColor(Lx.Palette.onAccent)
                                    .frame(width: 44, height: 44)
                                    .background(Theme.lxSuccess)
                                    .clipShape(Circle())
                            }
                            .accessibilityLabel("Call driver")
                            .accessibilityHint("Places a phone call to your driver")
                        }
                    }

                    // Vehicle Info Card
                    if driver.vehicle_make != nil || driver.license_plate != nil {
                        HStack(spacing: 12) {
                            // Vehicle Photo
                            if let vehiclePhotoUrl = driver.vehicle_photo_url,
                               let url = URL(string: vehiclePhotoUrl.hasPrefix("http") ? vehiclePhotoUrl : "\(AppConfig.shared.cdnBaseURL)\(vehiclePhotoUrl)") {
                                AsyncImage(url: url) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 80, height: 60)
                                        .clipShape(RoundedRectangle(cornerRadius: Lx.Radius.chip))
                                } placeholder: {
                                    vehiclePhotoPlaceholder
                                }
                            } else {
                                vehiclePhotoPlaceholder
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                // Vehicle Make/Model with Color
                                HStack(spacing: 4) {
                                    if let color = driver.vehicle_color {
                                        Text(color)
                                            .font(.subheadline)
                                            .foregroundColor(Lx.Palette.textSecondary)
                                    }
                                    if let make = driver.vehicle_make {
                                        Text(make)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                    }
                                    if let model = driver.vehicle_model {
                                        Text(model)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                    }
                                }

                                // License Plate (prominent)
                                if let plate = driver.license_plate {
                                    Text(plate)
                                        .font(.title3)
                                        .fontWeight(.bold)
                                        .foregroundColor(Lx.Palette.text)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.yellow.opacity(0.3))
                                        .cornerRadius(Lx.Radius.grabber)
                                }
                            }

                            Spacer()
                        }
                        .padding(12)
                        .background(Theme.lxSurface2)
                        .cornerRadius(Lx.Radius.button)
                    }
                }
                .padding(.horizontal)
            }

            // Negotiation Status Section ($1+$1 Platform Fee Model)
            if viewModel.isNegotiating {
                Divider().overlay(Theme.lxHairline)

                VStack(spacing: 12) {
                    // Show driver counter-offer if available
                    if let driverOffer = viewModel.driverOfferAmount {
                        // Driver Counter-Offer Card
                        VStack(spacing: 12) {
                            HStack {
                                ZStack {
                                    Circle()
                                        .fill(Theme.lxOrange.opacity(0.15))
                                        .frame(width: 40, height: 40)
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .foregroundColor(Theme.lxOrange)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Driver Counter-Offer")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Text("Platform fee: only \(Lx.Money.text(AppConfig.shared.calculateRidesharePlatformFee(fareAmount: driverOffer)))")
                                        .font(.caption2)
                                        .foregroundColor(Lx.Palette.textSecondary)
                                }

                                Spacer()

                                Text("$\(String(format: "%.2f", driverOffer))")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(Theme.lxOrange)
                            }

                            // Driver earnings transparency
                            HStack {
                                Image(systemName: "person.fill.checkmark")
                                    .font(.caption)
                                    .foregroundColor(Theme.lxSuccess)
                                Text("Driver earns: $\(String(format: "%.2f", driverOffer - AppConfig.shared.calculateRidesharePlatformFee(fareAmount: driverOffer)))")
                                    .font(.caption)
                                    .foregroundColor(Theme.lxSuccess)
                                Spacer()
                            }

                            VStack(spacing: 12) {
                                Button(action: { viewModel.acceptDriverOffer() }) {
                                    Text("Accept Offer")
                                        .font(Lx.Typography.body.weight(.bold))
                                        .foregroundColor(Lx.Palette.onAccent)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 56)
                                        .background(
                                            LinearGradient(colors: [Lx.Palette.orangeBright, Lx.Palette.orange],
                                                           startPoint: .top, endPoint: .bottom)
                                        )
                                        .cornerRadius(Lx.Radius.button)
                                        .shadow(color: Lx.Palette.orange.opacity(0.4), radius: 14, y: 6)
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 8)

                                Button(action: { showNegotiateSheet = true }) {
                                    HStack {
                                        Image(systemName: "arrow.left.arrow.right")
                                        Text("Counter")
                                    }
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(Theme.lxOrange)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Theme.lxOrange.opacity(0.15))
                                    .cornerRadius(Lx.Radius.chip)
                                }
                                .accessibilityLabel("Counter offer")
                                .accessibilityHint("Opens negotiation to make a counter offer")
                            }
                        }
                        .padding()
                        .background(Theme.lxOrange.opacity(0.05))
                        .cornerRadius(Lx.Radius.button)
                        .overlay(
                            RoundedRectangle(cornerRadius: Lx.Radius.button)
                                .stroke(Theme.lxOrange.opacity(0.3), lineWidth: 1)
                        )
                        .padding(.horizontal)

                    } else {
                        // Waiting for driver response
                        HStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(0.8)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Negotiating...")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("Waiting for driver's response")
                                    .font(.caption)
                                    .foregroundColor(Lx.Palette.textSecondary)
                            }

                            Spacer()

                            Button(action: { showNegotiateSheet = true }) {
                                Text("Change Offer")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(Lx.Palette.orange)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Lx.Palette.orange.opacity(0.1))
                                    .cornerRadius(Lx.Radius.chip)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }

            // Driver Info (when assigned). Skipped when the accepted-driver card above already shows this driver.
            if viewModel.acceptedDriver == nil,
               let tracking = viewModel.rideTracking,
               let driverName = tracking.driverName {
                Divider().overlay(Theme.lxHairline)

                VStack(spacing: 12) {
                    // Driver Row
                    HStack(spacing: 12) {
                        // Driver Photo
                        if let photoUrl = tracking.driverPhotoUrl,
                           let url = URL(string: photoUrl) {
                            AsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 50, height: 50)
                                    .clipShape(Circle())
                            } placeholder: {
                                ZStack {
                                    Circle()
                                        .fill(Theme.lxSurface2)
                                        .frame(width: 50, height: 50)
                                    Image(systemName: "person.fill")
                                        .foregroundColor(Lx.Palette.textMuted)
                                }
                            }
                        } else {
                            ZStack {
                                Circle()
                                    .fill(Theme.lxSurface2)
                                    .frame(width: 50, height: 50)
                                Image(systemName: "person.fill")
                                    .foregroundColor(Lx.Palette.textMuted)
                            }
                        }

                        VStack(alignment: .leading) {
                            HStack(spacing: 4) {
                                Text(driverName)
                                    .font(.headline)
                                if let rating = tracking.driverRating {
                                    HStack(spacing: 2) {
                                        Image(systemName: "star.fill")
                                            .font(.caption2)
                                            .foregroundColor(.yellow)
                                        Text(String(format: "%.1f", rating))
                                            .font(.caption)
                                            .foregroundColor(Lx.Palette.textSecondary)
                                    }
                                }
                            }
                            Text("Your driver")
                                .font(.caption)
                                .foregroundColor(Lx.Palette.textMuted)
                        }

                        Spacer()

                        if let phone = tracking.driverPhone {
                            Button(action: { callDriver(phone) }) {
                                Image(systemName: "phone.fill")
                                    .font(.title3)
                                    .foregroundColor(Lx.Palette.onAccent)
                                    .frame(width: 44, height: 44)
                                    .background(Theme.lxSuccess)
                                    .clipShape(Circle())
                            }
                        }
                    }

                    // Vehicle Info Row
                    if tracking.driverVehicle != nil || tracking.driverLicensePlate != nil {
                        HStack(spacing: 12) {
                            // Vehicle Photo
                            if let vehiclePhotoUrl = tracking.driverVehiclePhotoUrl,
                               let url = URL(string: vehiclePhotoUrl) {
                                AsyncImage(url: url) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 80, height: 60)
                                        .clipShape(RoundedRectangle(cornerRadius: Lx.Radius.chip))
                                } placeholder: {
                                    RoundedRectangle(cornerRadius: Lx.Radius.chip)
                                        .fill(Theme.lxSurface2)
                                        .frame(width: 80, height: 60)
                                        .overlay(
                                            Image(systemName: "car.fill")
                                                .foregroundColor(Lx.Palette.textMuted)
                                        )
                                }
                            } else {
                                RoundedRectangle(cornerRadius: Lx.Radius.chip)
                                    .fill(Theme.lxSurface2)
                                    .frame(width: 80, height: 60)
                                    .overlay(
                                        Image(systemName: "car.fill")
                                            .foregroundColor(Lx.Palette.textMuted)
                                    )
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                if let vehicle = tracking.driverVehicle {
                                    HStack(spacing: 4) {
                                        if let color = tracking.driverVehicleColor {
                                            Text(color)
                                                .font(.subheadline)
                                                .foregroundColor(Lx.Palette.textSecondary)
                                        }
                                        Text(vehicle)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                    }
                                }
                                if let plate = tracking.driverLicensePlate {
                                    Text(plate)
                                        .font(.headline)
                                        .fontWeight(.bold)
                                        .foregroundColor(Lx.Palette.text)
                                }
                            }

                            Spacer()
                        }
                        .padding(12)
                        .background(Theme.lxSurface2)
                        .cornerRadius(Lx.Radius.button)
                    }
                }
                .padding(.horizontal)
            }

            // Negotiation Message
            if let message = viewModel.negotiationMessage {
                Text(message)
                    .font(.caption)
                    .foregroundColor(Theme.lxSuccess)
                    .padding(.horizontal)
            }

            // MARK: - Ride Completed Thank You Section
            if viewModel.currentStep == .completed {
                rideCompletedSection
            }

            Spacer().frame(height: 20)
        }
        .background(
            RoundedRectangle(cornerRadius: Lx.Radius.sheet)
                .fill(Theme.lxSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: Lx.Radius.sheet)
                        .stroke(Theme.lxHairline, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: -5)
        )
        // Cancel Confirmation
        .confirmationDialog("Cancel Ride?", isPresented: $showCancelConfirm, titleVisibility: .visible) {
            Button("Cancel Ride\(viewModel.estimatedCancellationFee > 0 ? " (\(Lx.Money.text(viewModel.estimatedCancellationFee)) fee)" : " (Free)")", role: .destructive) {
                viewModel.cancelRide(reason: "Customer cancelled")
            }
            Button("Keep Ride", role: .cancel) { }
        } message: {
            Text(viewModel.estimatedCancellationFee > 0 ?
                 "A \(Lx.Money.text(viewModel.estimatedCancellationFee)) cancellation fee will apply." :
                 "You can cancel for free right now.")
        }
        // Negotiate Sheet
        .sheet(isPresented: $showNegotiateSheet) {
            CustomerNegotiationSheet(
                viewModel: viewModel,
                customerOfferAmount: $customerOfferAmount,
                isPresented: $showNegotiateSheet
            )
        }
        // Incoming Bids Sheet
        .sheet(isPresented: $viewModel.showBidsSheet) {
            DriverBidsSheet(viewModel: viewModel)
        }
        // Payment method required before accepting a bid — added on top of the bids
        // sheet since it's presented on the fly when the customer taps Accept.
        .sheet(isPresented: $viewModel.showPaymentMethodsSheet, onDismiss: {
            viewModel.retryAcceptBidAfterPaymentSetup()
        }) {
            PaymentMethodsView()
        }
        // Chat Sheet
        .sheet(isPresented: $showChatSheet) {
            if let rideId = viewModel.activeRide?.rideId,
               let driver = viewModel.acceptedDriver {
                DriverChatView(
                    rideRequestId: rideId,
                    driverName: driver.name ?? "Driver",
                    driverPhone: driver.phone
                )
            }
        }
    }

    // MARK: - Placeholder Views

    private var driverPhotoPlaceholder: some View {
        ZStack {
            Circle()
                .fill(Theme.lxSurface2)
                .frame(width: 60, height: 60)
            Image(systemName: "person.fill")
                .font(.title2)
                .foregroundColor(Lx.Palette.textMuted)
        }
    }

    private var vehiclePhotoPlaceholder: some View {
        RoundedRectangle(cornerRadius: Lx.Radius.chip)
            .fill(Theme.lxSurface2)
            .frame(width: 80, height: 60)
            .overlay(
                Image(systemName: "car.fill")
                    .font(.title3)
                    .foregroundColor(Lx.Palette.textMuted)
            )
    }

    // MARK: - Ride Completed Section (Thank You Screen)
    private var rideCompletedSection: some View {
        VStack(spacing: 20) {
            Divider().overlay(Theme.lxHairline)

            // Celebration Header
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Theme.lxSuccess.opacity(0.15))
                        .frame(width: 80, height: 80)
                    Image(systemName: "checkmark.circle.fill")
                        .font(Lx.Typography.iconLarge)
                        .foregroundColor(Theme.lxSuccess)
                }

                Text("Ride Complete!")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Thank you for riding with Dollor")
                    .font(.subheadline)
                    .foregroundColor(Lx.Palette.textSecondary)
            }
            .padding(.vertical, 8)

            // Trip Summary Card
            VStack(spacing: 12) {
                HStack {
                    Text("TRIP SUMMARY")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(Lx.Palette.textSecondary)
                    Spacer()
                    if let ride = viewModel.activeRide {
                        Text("Ride #\(ride.rideNumber ?? "—")")
                            .font(.caption)
                            .foregroundColor(Lx.Palette.textSecondary)
                    }
                }

                // Pickup → Dropoff
                HStack(spacing: 12) {
                    VStack(spacing: 4) {
                        Circle()
                            .fill(Lx.Palette.orange)
                            .frame(width: 12, height: 12)
                        Rectangle()
                            .fill(Theme.lxHairline)
                            .frame(width: 2, height: 30)
                        Image(systemName: "mappin.circle.fill")
                            .font(Lx.Typography.footnote)
                            .foregroundColor(Theme.lxSuccess)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pickup")
                                .font(.caption2)
                                .foregroundColor(Lx.Palette.textSecondary)
                            Text(viewModel.pickupAddress?.fullAddress ?? "Unknown")
                                .font(.subheadline)
                                .lineLimit(1)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Dropoff")
                                .font(.caption2)
                                .foregroundColor(Lx.Palette.textSecondary)
                            Text(viewModel.dropoffAddress?.fullAddress ?? "Unknown")
                                .font(.subheadline)
                                .lineLimit(1)
                        }
                    }

                    Spacer()
                }
            }
            .padding()
            .background(Theme.lxSurface)
            .cornerRadius(Lx.Radius.button)
            .padding(.horizontal)

            // Fare Breakdown
            VStack(spacing: 10) {
                HStack {
                    Text("FARE BREAKDOWN")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(Lx.Palette.textSecondary)
                    Spacer()
                }

                FareLineItem(label: "Ride Fare", amount: viewModel.fareBeforeTax)
                FareLineItem(label: "Connection Fee", amount: viewModel.platformFee)
                if viewModel.regulatoryFee > 0 {
                    FareLineItem(label: "Regulatory Fee (CPUC)", amount: viewModel.regulatoryFee)
                }

                Divider().overlay(Theme.lxHairline)

                HStack {
                    Text("Total Paid")
                        .font(.headline)
                    Spacer()
                    Text("$\(String(format: "%.2f", viewModel.totalAmount))")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.lxSuccess)
                }

                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                    Text("Driver earned $\(String(format: "%.2f", max(viewModel.fareBeforeTax - viewModel.platformFee - viewModel.regulatoryFee, 0)))")
                        .font(.caption2)
                }
                .foregroundColor(Lx.Palette.textSecondary)
            }
            .padding()
            .background(Theme.lxSurface)
            .cornerRadius(Lx.Radius.button)
            .padding(.horizontal)

            // Rate Driver Section
            if !ratingSubmitted {
                VStack(spacing: 12) {
                    HStack {
                        Text("RATE YOUR DRIVER")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(Lx.Palette.textSecondary)
                        Spacer()
                    }

                    // Driver info row
                    if let driver = viewModel.acceptedDriver {
                        HStack(spacing: 12) {
                            if let photoUrl = driver.photo_url,
                               let url = URL(string: photoUrl.hasPrefix("http") ? photoUrl : "\(AppConfig.shared.cdnBaseURL)\(photoUrl)") {
                                AsyncImage(url: url) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 50, height: 50)
                                        .clipShape(Circle())
                                } placeholder: {
                                    driverPhotoPlaceholder
                                }
                            } else {
                                driverPhotoPlaceholder
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(driver.name ?? "Your Driver")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                if let vehicle = driver.vehicle_make {
                                    Text("\(driver.vehicle_color ?? "") \(vehicle) \(driver.vehicle_model ?? "")")
                                        .font(.caption)
                                        .foregroundColor(Lx.Palette.textSecondary)
                                }
                            }
                            Spacer()
                        }
                    }

                    // Star Rating
                    HStack(spacing: 8) {
                        ForEach(1...5, id: \.self) { star in
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                    selectedRating = star
                                }
                            }) {
                                Image(systemName: star <= selectedRating ? "star.fill" : "star")
                                    .font(Lx.Typography.icon)
                                    .foregroundColor(star <= selectedRating ? .yellow : .gray.opacity(0.4))
                                    .scaleEffect(star <= selectedRating ? 1.1 : 1.0)
                            }
                            .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
                        }
                    }
                    .padding(.vertical, 8)

                    // Optional feedback
                    if selectedRating > 0 {
                        TextField("Add a comment (optional)", text: $ratingFeedback)
                            .textFieldStyle(.plain)
                            .padding()
                            .background(Theme.lxSurface2)
                            .cornerRadius(Lx.Radius.chip)

                        // Submit Rating Button
                        SwipeToConfirmButton(
                            label: "Slide to Submit \(selectedRating)-Star Rating",
                            accentColor: .yellow,
                            isDisabled: isSubmittingRating,
                            onConfirm: submitRating
                        )
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                    }
                }
                .padding()
                .background(Theme.lxSurface)
                .cornerRadius(Lx.Radius.button)
                .padding(.horizontal)
            } else {
                // Rating submitted confirmation
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Theme.lxSuccess)
                    Text("Thanks for rating \(selectedRating) stars!")
                        .font(.subheadline)
                        .foregroundColor(Theme.lxSuccess)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Theme.lxSuccess.opacity(0.1))
                .cornerRadius(Lx.Radius.button)
                .padding(.horizontal)
            }

            // Add Tip Section
            if !tipSubmitted {
                VStack(spacing: 12) {
                    HStack {
                        Text("ADD A TIP")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(Lx.Palette.textSecondary)
                        Spacer()
                        Text("100% goes to driver")
                            .font(.caption2)
                            .foregroundColor(Theme.lxSuccess)
                    }

                    // Quick Tip Buttons
                    HStack(spacing: 12) {
                        ForEach([2.0, 5.0, 10.0], id: \.self) { amount in
                            Button(action: {
                                withAnimation {
                                    selectedTipAmount = amount
                                    showCustomTip = false
                                }
                            }) {
                                Text("$\(Int(amount))")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(selectedTipAmount == amount ? .white : .primary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(selectedTipAmount == amount ? Theme.lxOrange : Theme.lxSurface2)
                                    .cornerRadius(Lx.Radius.button)
                            }
                            .accessibilityLabel("$\(Int(amount)) tip")
                        }

                        // Custom Amount Button
                        Button(action: {
                            withAnimation {
                                showCustomTip = true
                                selectedTipAmount = 0
                            }
                        }) {
                            Text("Other")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(showCustomTip ? .white : .primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(showCustomTip ? Theme.lxOrange : Theme.lxSurface2)
                                .cornerRadius(Lx.Radius.button)
                        }
                        .accessibilityLabel("Custom tip amount")
                    }

                    // Custom Tip Input
                    if showCustomTip {
                        HStack {
                            Text("$")
                                .font(.title2)
                                .fontWeight(.bold)
                            TextField("Amount", text: $customTipAmount)
                                .keyboardType(.decimalPad)
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                        .padding()
                        .background(Theme.lxSurface2)
                        .cornerRadius(Lx.Radius.chip)
                    }

                    // Submit Tip Button
                    let tipAmount = showCustomTip ? (Double(customTipAmount) ?? 0) : selectedTipAmount
                    if tipAmount > 0 {
                        SwipeToConfirmButton(
                            label: "Slide to Add $\(String(format: "%.2f", tipAmount)) Tip",
                            accentColor: .green,
                            isDisabled: isSubmittingTip,
                            onConfirm: submitTip
                        )
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                    }

                    // Skip Tip — still finalizes the ride (captures card for fare only)
                    Button(action: { finalize(tipAmount: 0) }) {
                        Text(isSubmittingTip ? "Processing..." : "Skip Tip")
                            .font(.caption)
                            .foregroundColor(Lx.Palette.textSecondary)
                    }
                    .disabled(isSubmittingTip)
                    .accessibilityLabel("Skip tip")
                }
                .padding()
                .background(Theme.lxSurface)
                .cornerRadius(Lx.Radius.button)
                .padding(.horizontal)
            } else {
                // Finalized (tip submitted or skipped)
                let tipAmount = showCustomTip ? (Double(customTipAmount) ?? 0) : selectedTipAmount
                HStack(spacing: 8) {
                    Image(systemName: tipAmount > 0 ? "heart.fill" : "checkmark.circle.fill")
                        .foregroundColor(tipAmount > 0 ? Theme.lxOrange : Theme.lxSuccess)
                    Text(tipAmount > 0
                        ? "$\(String(format: "%.2f", tipAmount)) tip sent to your driver!"
                        : "Payment complete. Thanks for riding!")
                        .font(.subheadline)
                        .foregroundColor(tipAmount > 0 ? Theme.lxOrange : Theme.lxSuccess)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background((tipAmount > 0 ? Theme.lxOrange : Theme.lxSuccess).opacity(0.1))
                .cornerRadius(Lx.Radius.button)
                .padding(.horizontal)
            }

            // Done Button
            SwipeToConfirmButton(
                label: "Slide to Done",
                accentColor: .gray,
                onConfirm: { viewModel.resetRide() }
            )
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
        }
        .alert("Rating Failed", isPresented: $showRatingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(ratingErrorMessage)
        }
        .alert("Tip Failed", isPresented: $showTipError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(tipErrorMessage)
        }
    }

    // MARK: - Rating & Tip Actions

    private func submitRating() {
        guard selectedRating > 0 else { return }
        guard let rideId = viewModel.activeRide?.rideId else {
            // No ride ID - skip rating silently
            return
        }

        isSubmittingRating = true

        // Call the backend API to submit rating
        P2PAPIService.shared.submitRideRating(
            rideId: rideId,
            rating: selectedRating,
            comment: ratingFeedback.isEmpty ? nil : ratingFeedback
        ) { result in
            DispatchQueue.main.async {
                isSubmittingRating = false
                switch result {
                case .success:
                    ratingSubmitted = true
                case .failure(let error):
                    ratingErrorMessage = error.localizedDescription
                    showRatingError = true
                }
            }
        }
    }

    private func submitTip() {
        let tipAmount = showCustomTip ? (Double(customTipAmount) ?? 0) : selectedTipAmount
        finalize(tipAmount: tipAmount)
    }

    private func finalize(tipAmount: Double) {
        guard let rideId = viewModel.activeRide?.rideId else {
            tipSubmitted = true
            return
        }

        isSubmittingTip = true

        P2PAPIService.shared.submitRideTip(rideId: rideId, amount: tipAmount) { result in
            DispatchQueue.main.async {
                isSubmittingTip = false
                switch result {
                case .success:
                    tipSubmitted = true
                case .failure(let error):
                    tipErrorMessage = error.localizedDescription
                    showTipError = true
                }
            }
        }
    }

    private func callDriver(_ phone: String) {
        let cleanPhone = phone.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
        if let url = URL(string: "tel://\(cleanPhone)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Customer Negotiation Sheet
struct CustomerNegotiationSheet: View {
    @ObservedObject var viewModel: RideRequestViewModel
    @Binding var customerOfferAmount: String
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "dollarsign.arrow.circlepath")
                        .font(Lx.Typography.iconLarge)
                        .foregroundColor(Theme.lxOrange)

                    Text("Negotiate Fare")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Only $\(String(format: "%.2f", AppConfig.shared.calculateRidesharePlatformFee(fareAmount: viewModel.estimatedFare))) platform fee to you + $\(String(format: "%.2f", AppConfig.shared.calculateRidesharePlatformFee(fareAmount: viewModel.estimatedFare))) to driver")
                        .font(.caption)
                        .foregroundColor(Lx.Palette.textSecondary)
                }
                .padding(.top, 20)

                // Current offers
                if let driverOffer = viewModel.driverOfferAmount {
                    HStack(spacing: 20) {
                        VStack {
                            Text("Driver's Offer")
                                .font(.caption)
                                .foregroundColor(Lx.Palette.textSecondary)
                            Text("$\(String(format: "%.2f", driverOffer))")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(Theme.lxOrange)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Theme.lxOrange.opacity(0.1))
                        .cornerRadius(Lx.Radius.button)

                        VStack {
                            Text("Your Budget")
                                .font(.caption)
                                .foregroundColor(Lx.Palette.textSecondary)
                            Text("$\(String(format: "%.2f", viewModel.totalAmount))")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(Lx.Palette.orange)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Lx.Palette.orange.opacity(0.1))
                        .cornerRadius(Lx.Radius.button)
                    }
                    .padding(.horizontal)
                }

                // Your offer input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Counter-Offer")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    HStack {
                        Text("$")
                            .font(.title)
                            .foregroundColor(Lx.Palette.textSecondary)

                        TextField("0.00", text: $customerOfferAmount)
                            .font(.title)
                            .keyboardType(.decimalPad)
                    }
                    .padding()
                    .background(Theme.lxSurface2)
                    .cornerRadius(Lx.Radius.button)

                    Text("Driver receives your offer minus $\(String(format: "%.2f", AppConfig.shared.calculateRidesharePlatformFee(fareAmount: viewModel.estimatedFare))) platform fee")
                        .font(.caption2)
                        .foregroundColor(Lx.Palette.textSecondary)
                }
                .padding(.horizontal)

                // Quick offer buttons
                HStack(spacing: 12) {
                    ForEach([5, 10, 15, 20], id: \.self) { amount in
                        Button(action: { customerOfferAmount = "\(amount)" }) {
                            Text("$\(amount)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(Lx.Palette.orange)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Lx.Palette.orange.opacity(0.1))
                                .cornerRadius(Lx.Radius.chip)
                        }
                    }
                }
                .padding(.horizontal)

                Spacer()

                // Submit button
                Button(action: submitOffer) {
                    HStack(spacing: 8) {
                        if viewModel.isLoading { ProgressView().tint(Lx.Palette.onAccent) }
                        Text(customerOfferAmount.isEmpty
                             ? "Enter an amount"
                             : (viewModel.isLoading ? "Sending..." : "Send $\(customerOfferAmount) Offer"))
                            .font(Lx.Typography.body.weight(.bold))
                            .foregroundColor(Lx.Palette.onAccent)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        (customerOfferAmount.isEmpty || viewModel.isLoading)
                        ? AnyView(Lx.Palette.textMuted.opacity(0.4))
                        : AnyView(LinearGradient(colors: [Lx.Palette.orangeBright, Lx.Palette.orange],
                                                 startPoint: .top, endPoint: .bottom))
                    )
                    .cornerRadius(Lx.Radius.button)
                    .shadow(color: (customerOfferAmount.isEmpty || viewModel.isLoading) ? .clear : Lx.Palette.orange.opacity(0.4),
                            radius: 14, y: 6)
                }
                .disabled(customerOfferAmount.isEmpty || viewModel.isLoading)
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .padding(.bottom)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.lxBg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }

    private func submitOffer() {
        guard let amount = Double(customerOfferAmount) else { return }
        viewModel.submitFareOffer(proposedFare: amount)
    }
}

// MARK: - Driver Bids Sheet (P2P Bidding)
struct DriverBidsSheet: View {
    @ObservedObject var viewModel: RideRequestViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "person.3.fill")
                        .font(Lx.Typography.icon)
                        .foregroundColor(Theme.lxSuccess)

                    Text("Available Drivers")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Select a driver to accept their offer")
                        .font(.subheadline)
                        .foregroundColor(Lx.Palette.textSecondary)
                }
                .padding(.top, 20)
                .padding(.bottom, 16)

                Divider().overlay(Theme.lxHairline)

                // Bids List
                if viewModel.incomingBids.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Waiting for drivers...")
                            .font(.subheadline)
                            .foregroundColor(Lx.Palette.textSecondary)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.incomingBids, id: \.id) { bid in
                                TinderSwipeCard(
                                    onAccept: {
                                        viewModel.acceptBid(bid)
                                        // Don't dismiss here - let acceptBid handle it
                                    },
                                    onDecline: {
                                        viewModel.rejectBid(bid)
                                    }
                                ) {
                                    DriverBidCard(
                                        bid: bid,
                                        isLoading: viewModel.isLoading,
                                        onAccept: {
                                            viewModel.acceptBid(bid)
                                        },
                                        onCounter: {
                                            viewModel.showCounterOffer(for: bid)
                                        },
                                        onReject: {
                                            viewModel.rejectBid(bid)
                                        }
                                    )
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.lxBg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
        .sheet(isPresented: $viewModel.showCounterSheet) {
            if let bid = viewModel.selectedBidForCounter {
                BidCounterSheet(viewModel: viewModel, bid: bid)
            }
        }
    }
}

// MARK: - Bid Counter Sheet
struct BidCounterSheet: View {
    @ObservedObject var viewModel: RideRequestViewModel
    let bid: RideBid
    @Environment(\.dismiss) private var dismiss
    @State private var counterPrice: String = ""
    @State private var counterMessage: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header info
                    VStack(spacing: 8) {
                        Text("Counter Offer")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Make a counter-offer to \(bid.driver_name ?? "the driver")")
                            .font(.subheadline)
                            .foregroundColor(Lx.Palette.textSecondary)
                    }
                    .padding(.top, 20)

                    // Current price display
                    VStack(spacing: 4) {
                        Text("Driver's offer")
                            .font(.caption)
                            .foregroundColor(Lx.Palette.textSecondary)
                        Text("$\(String(format: "%.2f", bid.proposed_price))")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.lxSuccess)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Theme.lxSuccess.opacity(0.1))
                    .cornerRadius(Lx.Radius.button)

                    // Counter price input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your counter price")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        HStack {
                            Text("$")
                                .font(.title2)
                                .foregroundColor(Lx.Palette.textSecondary)
                            TextField("0.00", text: $counterPrice)
                                .font(.title2)
                                .keyboardType(.decimalPad)
                        }
                        .padding()
                        .background(Theme.lxSurface2)
                        .cornerRadius(Lx.Radius.button)

                        // Show remaining counters
                        Text("\(viewModel.customerCountersRemaining) counter offers remaining")
                            .font(.caption)
                            .foregroundColor(Theme.lxOrange)
                    }

                    // Optional message
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Message (optional)")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        TextField("Add a message for the driver...", text: $counterMessage)
                            .padding()
                            .background(Theme.lxSurface2)
                            .cornerRadius(Lx.Radius.button)
                    }

                    // Warning display
                    if let warning = viewModel.counterOfferWarning {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(Theme.lxOrange)
                            Text(warning)
                                .font(.caption)
                                .foregroundColor(Theme.lxOrange)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Theme.lxOrange.opacity(0.1))
                        .cornerRadius(Lx.Radius.chip)
                    }

                    Spacer(minLength: 20)
                }
                .padding()
            }
            .background(Theme.lxBg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        viewModel.showCounterSheet = false
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    // Submit button — pinned above keyboard/home indicator
                    SwipeToConfirmButton(
                        label: "Slide to Submit Counter",
                        accentColor: .purple,
                        isDisabled: !isValidPrice || viewModel.isLoading,
                        onConfirm: submitCounter
                    )
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                }
                .background(Theme.lxSurface)
            }
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
        .onAppear {
            // Pre-fill with a reasonable counter (e.g., 90% of driver's price)
            let suggestedCounter = bid.proposed_price * 0.9
            counterPrice = String(format: "%.2f", suggestedCounter)
        }
    }

    private var isValidPrice: Bool {
        guard let price = Double(counterPrice), price > 0 else { return false }
        return price < bid.proposed_price
    }

    private func submitCounter() {
        guard let price = Double(counterPrice) else { return }
        viewModel.counterBid(bid, counterPrice: price, message: counterMessage.isEmpty ? nil : counterMessage)
        dismiss()
    }
}

// MARK: - Driver Bid Card
struct DriverBidCard: View {
    let bid: RideBid
    let isLoading: Bool
    let onAccept: () -> Void
    let onCounter: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Driver Info Row
            HStack(spacing: 12) {
                // Driver Photo
                if let photoUrl = bid.driver_photo_url,
                   let url = URL(string: photoUrl.hasPrefix("http") ? photoUrl : "\(AppConfig.shared.cdnBaseURL)\(photoUrl)") {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                    } placeholder: {
                        driverPhotoPlaceholder
                    }
                } else {
                    driverPhotoPlaceholder
                }

                VStack(alignment: .leading, spacing: 4) {
                    // Name and Rating
                    HStack(spacing: 6) {
                        Text(bid.driver_name ?? "Driver")
                            .font(.headline)

                        if let rating = bid.driver_rating {
                            HStack(spacing: 2) {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                    .foregroundColor(.yellow)
                                Text(String(format: "%.1f", rating))
                                    .font(.caption)
                                    .foregroundColor(Lx.Palette.textSecondary)
                            }
                        }
                    }

                    // Vehicle details
                    if let make = bid.driver_vehicle_make, let model = bid.driver_vehicle_model {
                        HStack(spacing: 4) {
                            if let color = bid.driver_vehicle_color {
                                Circle()
                                    .fill(Color.secondary.opacity(0.3))
                                    .frame(width: 10, height: 10)
                                    .overlay(
                                        Circle().stroke(Color.secondary, lineWidth: 0.5)
                                    )
                            }
                            Text([bid.driver_vehicle_year.map { String($0) }, make, model]
                                .compactMap { $0 }.joined(separator: " "))
                                .font(.subheadline)
                                .foregroundColor(Lx.Palette.textSecondary)
                        }
                        if let plate = bid.driver_license_plate {
                            Text(plate)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(Lx.Palette.textSecondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.lxSurface2)
                                .cornerRadius(Lx.Radius.grabber)
                        }
                    } else if let vehicle = bid.driver_vehicle {
                        Text(vehicle)
                            .font(.subheadline)
                            .foregroundColor(Lx.Palette.textSecondary)
                    }

                    // ETA
                    if let eta = bid.estimated_arrival_minutes {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.fill")
                                .font(.caption2)
                                .foregroundColor(Lx.Palette.orange)
                            Text("~\(eta) min away")
                                .font(.caption)
                                .foregroundColor(Lx.Palette.orange)
                        }
                    }
                }

                Spacer()

                // Price and Status
                VStack(alignment: .trailing, spacing: 2) {
                    Text("$\(String(format: "%.2f", bid.proposed_price))")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.lxSuccess)

                    // Show negotiation status
                    if bid.status == "countered" {
                        Text("Countered")
                            .font(.caption2)
                            .foregroundColor(Theme.lxOrange)
                    } else if let round = bid.negotiation_round, round > 1 {
                        Text("Round \(round)/\(AppConfig.shared.maxRoundsPerBid)")
                            .font(.caption2)
                            .foregroundColor(Lx.Palette.orange)
                    } else {
                        Text("Offered")
                            .font(.caption2)
                            .foregroundColor(Lx.Palette.textSecondary)
                    }

                    // Show if this is driver's final offer
                    if bid.is_final_round == true {
                        Text("Final Offer")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(Theme.lxOrange)
                    }
                }
            }

            // Driver Message (if any)
            if let message = bid.message, !message.isEmpty {
                HStack {
                    Image(systemName: "quote.bubble.fill")
                        .font(.caption)
                        .foregroundColor(Lx.Palette.textMuted)
                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(Lx.Palette.textSecondary)
                        .italic()
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .background(Theme.lxSurface2)
                .cornerRadius(Lx.Radius.chip)
            }

            // Customer's counter price (if shown)
            if let counterPrice = bid.customer_counter_price {
                HStack {
                    Text("Your counter:")
                        .font(.caption)
                        .foregroundColor(Lx.Palette.textSecondary)
                    Text("$\(String(format: "%.2f", counterPrice))")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(Lx.Palette.orange)
                    Spacer()
                    if bid.status == "countered" {
                        Text("Waiting for driver...")
                            .font(.caption)
                            .foregroundColor(Theme.lxOrange)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Lx.Palette.orange.opacity(0.1))
                .cornerRadius(Lx.Radius.chip)
            }

            // Action Buttons - show different buttons based on bid status
            if bid.status == "countered" && bid.last_offer_by == "customer" {
                // Waiting for driver response - no actions available
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundColor(Theme.lxOrange)
                    Text("Waiting for driver's response...")
                        .font(.subheadline)
                        .foregroundColor(Theme.lxOrange)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.lxOrange.opacity(0.1))
                .cornerRadius(Lx.Radius.chip)
            } else {
                // Normal action buttons
                HStack(spacing: 8) {
                    Button(action: onReject) {
                        HStack {
                            Image(systemName: "xmark")
                            Text("Decline")
                        }
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(Lx.Palette.error)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Lx.Palette.error.opacity(0.1))
                        .cornerRadius(Lx.Radius.chip)
                    }
                    .disabled(isLoading)
                    .opacity(isLoading ? 0.5 : 1.0)

                    Button(action: onCounter) {
                        HStack {
                            Image(systemName: "arrow.left.arrow.right")
                            Text("Counter")
                        }
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(Theme.lxOrange)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.lxOrange.opacity(0.1))
                        .cornerRadius(Lx.Radius.chip)
                    }
                    .disabled(isLoading)
                    .opacity(isLoading ? 0.5 : 1.0)

                    Button(action: onAccept) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(Lx.Palette.onAccent)
                            } else {
                                Image(systemName: "checkmark")
                            }
                            Text("Accept")
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(Lx.Palette.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(isLoading ? Lx.Palette.textMuted : Theme.lxSuccess)
                        .cornerRadius(Lx.Radius.chip)
                    }
                    .disabled(isLoading)
                }
            }
        }
        .padding()
        .background(Theme.lxSurface)
        .cornerRadius(Lx.Radius.card)
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
    }

    private var driverPhotoPlaceholder: some View {
        ZStack {
            Circle()
                .fill(Theme.lxSurface2)
                .frame(width: 56, height: 56)
            Image(systemName: "person.fill")
                .font(.title3)
                .foregroundColor(Lx.Palette.textMuted)
        }
    }
}

// MARK: - Share Trip Activity View

struct ShareTripActivityView: UIViewControllerRepresentable {
    let shareText: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [shareText], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview
#Preview {
    RideRequestView()
        .environmentObject(AuthViewModel())
}
