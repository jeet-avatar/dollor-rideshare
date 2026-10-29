import SwiftUI
import MapKit
import EatFairShared

/// RideshareDashboardView - Main rideshare screen with tabs
/// Matches web app RideBidding.tsx with Available Requests and My Bids tabs
struct RideshareDashboardView: View {
    @StateObject private var viewModel = RideBiddingViewModel()
    @ObservedObject private var onlineManager = OnlineStatusManager.shared
    @State private var selectedTab: RideshareTab = .available
    /// The one sheet shown above the dashboard. Every sheet (bid, counter-offer, payouts) is presented from
    /// here, never from inside a tab page: presenting from the pages of the paged TabView left UIKit with
    /// a dead presenter once the page was recycled, after which later sheets/covers silently never opened.
    @State private var sheet: DashboardSheet?
    /// The bid currently presented full-screen. Set when an active ride appears;
    /// cleared only when the driver explicitly finishes (done/cancel/no-show).
    /// Using local state prevents the poll-driven activeRides update from
    /// force-dismissing the screen mid-flow.
    @State private var presentedActiveBid: RideBid?

    enum DashboardSheet: Identifiable {
        case bid(RideRequestForBidding)
        case counter(RideBid)
        case payouts

        var id: String {
            switch self {
            case .bid(let request): return "bid-\(request.id)"
            case .counter(let bid): return "counter-\(bid.id)"
            case .payouts: return "payouts"
            }
        }
    }

    enum RideshareTab: String, CaseIterable {
        case available = "Available"
        case myBids = "My Bids"
        case active = "Active"

        var icon: String {
            switch self {
            case .available: return "car.2.fill"
            case .myBids: return "hand.raised.fill"
            case .active: return "location.fill"
            }
        }

        var color: Color {
            switch self {
            case .available: return Theme.lxOrange
            case .myBids: return Theme.lxOrangeBright
            case .active: return Theme.lxSuccess
            }
        }
    }

    var body: some View {
        mainNavigationContent
            .alert("Can't go online yet", isPresented: Binding(
                get: { onlineManager.statusError != nil },
                set: { if !$0 { onlineManager.statusError = nil } }
            )) {
                Button("OK", role: .cancel) { onlineManager.statusError = nil }
            } message: {
                Text(onlineManager.statusError ?? "")
            }
    }

    private var mainNavigationContent: some View {
        NavigationView {
            ZStack {
                Theme.lxBg.ignoresSafeArea()
                VStack(spacing: 0) {
                    onlineToggleBar
                    tabSelector
                    // A plain switch, not a paged TabView: pages are recycled by a UIPageViewController, and
                    // swipe-paging fights the swipe cards.
                    switch selectedTab {
                    case .available:
                        AvailableRequestsContent(viewModel: viewModel, onSelect: { sheet = .bid($0) })
                    case .myBids:
                        MyBidsContent(viewModel: viewModel, onRespond: { sheet = .counter($0) })
                    case .active:
                        ActiveRidesContent(viewModel: viewModel, presentedActiveBid: $presentedActiveBid)
                    }
                }
            }
            .rideshareBanner(viewModel)
            .navigationTitle("Rideshare")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Button(action: { sheet = .payouts }) {
                            Image(systemName: "dollarsign.circle")
                                .foregroundColor(Theme.lxSuccess)
                        }
                        .accessibilityLabel("View payout history")
                        Button(action: { viewModel.refreshData() }) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(Theme.lxOrange)
                        }
                        .accessibilityLabel("Refresh rideshare data")
                    }
                }
            }
            .sheet(item: $sheet) { current in
                switch current {
                case .bid(let request):
                    SubmitBidSheet(request: request, viewModel: viewModel) {
                        sheet = nil
                        selectedTab = .myBids
                    }
                case .counter(let bid):
                    CounterOfferResponseSheet(bid: bid, viewModel: viewModel) {
                        sheet = nil
                    }
                case .payouts:
                    PayoutDashboardView()
                }
            }
            // Full-screen active ride cover. Driven by presentedActiveBid (not
            // activeRides directly) so that a poll-driven activeRides update cannot
            // force-dismiss the screen while the driver is mid-flow (rating, etc.).
            // The cover is set by the .onChange below when a ride first appears,
            // and cleared only when the driver explicitly finishes via onRideDone.
            .fullScreenCover(item: $presentedActiveBid) { activeBid in
                NavigationStack {
                    ActiveRideView(
                        bid: activeBid,
                        viewModel: viewModel,
                        onRideDone: {
                            viewModel.clearActiveRide(activeBid)
                            presentedActiveBid = nil
                            viewModel.refreshData()
                        }
                    )
                }
                .interactiveDismissDisabled(true)
            }
            .onAppear { viewModel.refreshData() }
            // Returning to the app: re-sync with the server so state changed elsewhere never looks stale.
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                viewModel.refreshData()
            }
            .onChange(of: viewModel.counteredBids) { _, bids in
                // The bid is no longer a live counter-offer (matched, withdrawn, expired): close its sheet so
                // it cannot collide with the full-screen ride presentation.
                if case .counter(let current)? = sheet, !bids.contains(where: { $0.id == current.id }) {
                    sheet = nil
                }
            }
            .onChange(of: viewModel.showCounterOfferSheet) { _, isShowing in
                guard isShowing else { return }
                if let offer = viewModel.selectedCounterOffer, presentedActiveBid == nil, sheet == nil {
                    sheet = .counter(offer)
                }
                viewModel.showCounterOfferSheet = false
            }
            .onChange(of: viewModel.myBids) { _, bids in
                // The rider (or support) cancelled the ride we are showing: close the screen instead of leaving a dead ride.
                if let current = presentedActiveBid,
                   let latest = bids.first(where: { $0.id == current.id }),
                   latest.ride_request?.status == "cancelled" {
                    presentedActiveBid = nil
                }
            }
            .onChange(of: presentedActiveBid?.id) { _, _ in
                // Settlement data belongs to one ride: drop it whenever the screen closes or shows another ride.
                if let data = viewModel.completionData, data.id != presentedActiveBid.map({ $0.ride_request?.id ?? $0.ride_request_id }) {
                    viewModel.completionData = nil
                }
            }
            .onChange(of: viewModel.activeRides) { _, newRides in
                // The server no longer lists the ride we show (and it is not in the completion/rating
                // step): close the screen instead of leaving a ghost active ride.
                if let current = presentedActiveBid,
                   !newRides.contains(where: { $0.id == current.id }),
                   viewModel.completion(for: current) == nil {
                    presentedActiveBid = nil
                }
                if presentedActiveBid == nil, let first = newRides.first {
                    presentActiveRide(first)
                }
            }

        }
        .preferredColorScheme(.dark)
    }

    /// Shows the ride cover once no sheet is on screen. UIKit drops a presentation requested while another
    /// one is animating out, and SwiftUI would then believe the cover is up, so wait until the sheet is gone.
    private func presentActiveRide(_ bid: RideBid, attempt: Int = 0) {
        if sheet != nil {
            sheet = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard presentedActiveBid == nil,
                  viewModel.activeRides.contains(where: { $0.id == bid.id }) else { return }
            if sheet != nil, attempt < 5 {
                presentActiveRide(bid, attempt: attempt + 1)
                return
            }
            presentedActiveBid = bid
        }
    }

    private var onlineToggleBar: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(viewModel.isOnline ? Theme.lxSuccess : Theme.lxError)
                .frame(width: 12, height: 12)
            Text(viewModel.isOnline ? "Online" : "Offline")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(viewModel.isOnline ? Theme.lxSuccess : Theme.lxError)
            Spacer()
            Toggle("", isOn: Binding(
                get: { viewModel.isOnline },
                set: { viewModel.setOnlineStatus($0) }
            ))
            .labelsHidden()
            .tint(Theme.lxSuccess)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(viewModel.isOnline ? Theme.lxSuccess.opacity(0.15) : Theme.lxError.opacity(0.15))
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(RideshareTab.allCases, id: \.self) { tab in
                Button(action: {
                    withAnimation(.spring(response: 0.3)) {
                        selectedTab = tab
                    }
                }) {
                    VStack(spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.subheadline)
                            Text(tab.rawValue)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }

                        // Badge
                        Text("\(countForTab(tab))")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(selectedTab == tab ? .white : tab.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(selectedTab == tab ? tab.color : tab.color.opacity(0.2))
                            .cornerRadius(Lx.Radius.chip)
                    }
                    .foregroundColor(selectedTab == tab ? tab.color : Theme.lxTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        VStack {
                            Spacer()
                            if selectedTab == tab {
                                Rectangle()
                                    .fill(tab.color)
                                    .frame(height: 3)
                            }
                        }
                    )
                }
                .accessibilityLabel("\(tab.rawValue) tab, \(countForTab(tab)) items")
                .accessibilityHint(selectedTab == tab ? "Currently selected" : "Tap to view \(tab.rawValue.lowercased())")
            }
        }
        .background(Theme.lxSurface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.lxHairline)
                .frame(height: 1)
        }
    }

    private func countForTab(_ tab: RideshareTab) -> Int {
        switch tab {
        case .available:
            return viewModel.availableRequests.count
        case .myBids:
            return viewModel.pendingBids.count + viewModel.counteredBids.count
        case .active:
            return viewModel.activeRides.count
        }
    }
}

// MARK: - Available Requests Content

struct AvailableRequestsContent: View {
    @ObservedObject var viewModel: RideBiddingViewModel
    let onSelect: (RideRequestForBidding) -> Void
    @StateObject private var locationManager = LocationManager.shared

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.availableRequests.isEmpty {
                loadingView
            } else if viewModel.availableRequests.isEmpty {
                emptyStateView
            } else {
                requestsList
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
                .tint(Lx.Palette.orange)
            Text("Finding ride requests...")
                .font(.headline)
                .foregroundColor(Theme.textSecondary)
            Spacer()
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Lx.Palette.orange.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: "car.2.fill")
                    .font(Lx.Typography.largeTitle)
                    .foregroundColor(Lx.Palette.orange)
            }

            VStack(spacing: 8) {
                Text("No Ride Requests")
                    .font(Lx.Typography.title)
                    .foregroundColor(Lx.Palette.text)

                Text("Ride requests will appear here.\nSubmit competitive bids to get matched!")
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: { viewModel.fetchAvailableRequests() }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.lxPrimary)
            .padding(.horizontal, Lx.Spacing.xl)
            .accessibilityLabel("Refresh ride requests")
            .accessibilityHint("Check for new available ride requests")

            Spacer()
        }
        .padding()
    }

    private var requestsList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(viewModel.availableRequests) { request in
                    TinderSwipeCard(
                        onAccept: {
                            onSelect(request)
                        },
                        onDecline: { /* skip to next card — no-op */ }
                    ) {
                        RideRequestCard(
                            request: request,
                            locationManager: locationManager,
                            bidCount: viewModel.displayBidCount(for: request),
                            onBid: {
                                onSelect(request)
                            }
                        )
                    }
                }
            }
            .padding()
        }
        .refreshable {
            viewModel.fetchAvailableRequests()
        }
    }
}

// MARK: - My Bids Content

struct MyBidsContent: View {
    @ObservedObject var viewModel: RideBiddingViewModel
    let onRespond: (RideBid) -> Void

    /// True when there are bids worth showing (pending or countered).
    /// Accepted bids live in the Active tab so they don't count here.
    private var hasVisibleBids: Bool {
        !viewModel.pendingBids.isEmpty || !viewModel.counteredBids.isEmpty || !viewModel.closedBids.isEmpty
    }

    var body: some View {
        Group {
            if hasVisibleBids {
                bidsList
            } else {
                emptyStateView
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Lx.Palette.orange.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: "hand.raised.fill")
                    .font(Lx.Typography.iconLarge)
                    .foregroundColor(Lx.Palette.orange)
            }

            VStack(spacing: 8) {
                Text("No Bids Yet")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(Theme.textPrimary)

                Text("Submit bids on ride requests\nto see them here.")
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding()
    }

    private var bidsList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // Counter-offers section
                if !viewModel.counteredBids.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(Lx.Palette.orange)
                            Text("Counter-Offers (\(viewModel.counteredBids.count))")
                                .font(.headline)
                                .foregroundColor(Theme.textPrimary)
                        }

                        ForEach(viewModel.counteredBids) { bid in
                            BidCard(
                                bid: bid,
                                viewModel: viewModel,
                                onCounterOffer: {
                                    onRespond(bid)
                                }
                            )
                        }
                    }
                    .padding(.bottom, 8)
                }

                // Pending bids section
                if !viewModel.pendingBids.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Pending (\(viewModel.pendingBids.count))")
                            .font(.headline)
                            .foregroundColor(Theme.textPrimary)

                        ForEach(viewModel.pendingBids) { bid in
                            BidCard(
                                bid: bid,
                                viewModel: viewModel,
                                onCounterOffer: {}
                            )
                        }
                    }
                }

                // Recent: bids that are no longer live, with the reason
                if !viewModel.closedBids.isEmpty {
                    VStack(alignment: .leading, spacing: Lx.Spacing.m) {
                        Text("Recent")
                            .font(Lx.Typography.headline)
                            .foregroundColor(Lx.Palette.text)

                        ForEach(viewModel.closedBids) { bid in
                            ClosedBidRow(bid: bid)
                        }
                    }
                }
            }
            .padding()
        }
        .refreshable {
            viewModel.fetchMyBids()
        }
    }
}

// MARK: - Closed Bid Row

struct ClosedBidRow: View {
    let bid: RideBid

    var body: some View {
        VStack(alignment: .leading, spacing: Lx.Spacing.xs) {
            if let ride = bid.ride_request {
                Text("\(ride.pickup.address) → \(ride.dropoff.address)")
                    .font(Lx.Typography.subheadline)
                    .foregroundColor(Lx.Palette.textSecondary)
                    .lineLimit(2)
            }
            Text(bid.closedReason ?? "")
                .font(Lx.Typography.subheadline.weight(.semibold))
                .foregroundColor(Lx.Palette.orange)
            Text("Your offer: $\(String(format: "%.2f", bid.proposed_price))")
                .font(Lx.Typography.caption)
                .foregroundColor(Lx.Palette.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Lx.Spacing.l)
        .lxCard()
    }
}

// MARK: - Active Rides Content

struct ActiveRidesContent: View {
    @ObservedObject var viewModel: RideBiddingViewModel
    /// Bound to the parent's presentedActiveBid so tapping a card reopens the
    /// full-screen cover instead of pushing a separate NavigationLink destination
    /// (which would receive no onRideDone callback and be unable to dismiss cleanly).
    @Binding var presentedActiveBid: RideBid?

    var body: some View {
        Group {
            if viewModel.activeRides.isEmpty {
                emptyStateView
            } else {
                ridesList
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Lx.Palette.success.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: "location.fill")
                    .font(Lx.Typography.iconLarge)
                    .foregroundColor(Lx.Palette.success)
            }

            VStack(spacing: 8) {
                Text("No Active Rides")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(Theme.textPrimary)

                Text("When a customer accepts your bid,\nthe ride will appear here.")
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding()
    }

    private var ridesList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(viewModel.activeRides) { bid in
                    // Use a plain button that sets presentedActiveBid, which triggers
                    // the parent's fullScreenCover (with onRideDone wired correctly).
                    // A NavigationLink here gets no onRideDone and can't dismiss the cover.
                    Button {
                        presentedActiveBid = bid
                    } label: {
                        ActiveRideCard(bid: bid)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .refreshable {
            viewModel.fetchMyBids()
        }
    }
}

// MARK: - Active Ride Card

struct ActiveRideCard: View {
    let bid: RideBid

    private var request: RideRequestForBidding? {
        bid.ride_request
    }

    private var finalPrice: Double {
        request?.final_price ?? bid.customer_counter_price ?? bid.proposed_price
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Lx.Palette.success)
                    Text("Matched")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(Lx.Palette.success)
                }

                Spacer()

                Text("\(Lx.Money.text(finalPrice))")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(Theme.textPrimary)
            }
            .padding()

            Divider()
                .padding(.horizontal)

            // Route
            if let request = request {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Lx.Palette.success)
                            .frame(width: 10, height: 10)
                        Text(request.pickup.address)
                            .font(.caption)
                            .foregroundColor(Theme.textPrimary)
                            .lineLimit(1)
                        Spacer()
                    }

                    HStack(spacing: 8) {
                        Circle()
                            .fill(Lx.Palette.error)
                            .frame(width: 10, height: 10)
                        Text(request.dropoff.address)
                            .font(.caption)
                            .foregroundColor(Theme.textPrimary)
                            .lineLimit(1)
                        Spacer()
                    }
                }
                .padding()
            }

            // Go to Ride Button
            HStack {
                Image(systemName: "car.fill")
                Text("View Ride")
            }
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundColor(Lx.Palette.onAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Lx.Palette.success)
            .cornerRadius(Lx.Radius.button)
            .padding()
        }
        .background(Theme.cardBackground)
        .cornerRadius(Lx.Radius.card)
        .shadow(color: Lx.Palette.shadow.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Ride Request Card

struct RideRequestCard: View {
    let request: RideRequestForBidding
    let locationManager: LocationManager
    let bidCount: Int
    let onBid: () -> Void

    private var distanceToPickup: String {
        if let km = request.distance_to_pickup_km {
            let miles = km * 0.621371
            return String(format: "%.1f mi", miles)
        }
        return "--"
    }

    /// What the rider is offering to pay; falls back to the suggested fare (same rule as Android).
    private var riderOffer: Double {
        request.customer_preferred_price ?? request.suggested_price ?? 0
    }

    private var tripDistance: String {
        if let km = request.estimated_distance_km {
            let miles = km * 0.621371
            return String(format: "%.1f mi", miles)
        }
        return "--"
    }

    private var tripDuration: String {
        if let minutes = request.estimated_duration_minutes {
            return "\(minutes) min"
        }
        return "--"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header - Price & Distance
            HStack {
                VStack(alignment: .leading, spacing: Lx.Spacing.xs) {
                    Text("$\(String(format: "%.2f", riderOffer))")
                        .font(Lx.Typography.priceSmall)
                        .foregroundColor(Lx.Palette.success)
                    Text(request.customer_preferred_price != nil ? "Rider offers" : "Suggested")
                        .font(Lx.Typography.caption)
                        .foregroundColor(Lx.Palette.textSecondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: Lx.Spacing.xs) {
                    HStack(spacing: Lx.Spacing.xs) {
                        Image(systemName: "location.fill")
                            .font(Lx.Typography.caption)
                        Text("\(distanceToPickup) away")
                            .font(Lx.Typography.caption.weight(.medium))
                    }
                    .foregroundColor(Lx.Palette.textSecondary)

                    if bidCount > 0 {
                        HStack(spacing: Lx.Spacing.xs) {
                            Image(systemName: "person.3.fill")
                                .font(Lx.Typography.caption)
                            Text("\(bidCount) bid\(bidCount == 1 ? "" : "s")")
                                .font(Lx.Typography.caption.weight(.bold))
                        }
                        .foregroundColor(Lx.Palette.orange)
                        .padding(.horizontal, Lx.Spacing.s)
                        .padding(.vertical, Lx.Spacing.xs)
                        .background(Lx.Palette.orange.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: Lx.Radius.chip, style: .continuous))
                    }
                }
            }
            .padding(Lx.Spacing.l)

            Divider().overlay(Lx.Palette.hairline)

            // Pickup
            RideRouteRow(
                icon: "person.fill",
                tint: Lx.Palette.pickup,
                title: "PICKUP",
                address: request.pickup.address
            )
            .padding(.horizontal, Lx.Spacing.l)
            .padding(.top, Lx.Spacing.m)

            HStack {
                Rectangle()
                    .fill(Lx.Palette.hairline)
                    .frame(width: 2, height: 24)
                    .padding(.leading, Lx.Spacing.l + 19)
                Spacer()
            }

            // Drop-off
            RideRouteRow(
                icon: "mappin.circle.fill",
                tint: Lx.Palette.dropoff,
                title: "DROP-OFF",
                address: request.dropoff.address
            )
            .padding(.horizontal, Lx.Spacing.l)
            .padding(.bottom, Lx.Spacing.m)

            // Trip stats
            HStack(spacing: Lx.Spacing.m) {
                TripStatBadge(icon: "arrow.left.and.right", text: tripDistance, label: "Trip")
                TripStatBadge(icon: "clock.fill", text: tripDuration, label: "Duration")

                if let specialRequests = request.special_requests, !specialRequests.isEmpty {
                    TripStatBadge(icon: "note.text", text: "Notes", label: "Special")
                }

                if request.accessibility_requested == true {
                    TripStatBadge(icon: "figure.roll", text: "Access", label: "Needed")
                }
            }
            .padding(.horizontal, Lx.Spacing.l)
            .padding(.bottom, Lx.Spacing.m)

            Divider().overlay(Lx.Palette.hairline)

            Button(action: onBid) {
                Label("Submit Bid", systemImage: "hand.raised.fill")
            }
            .buttonStyle(.lxPrimary)
            .accessibilityLabel("Submit bid for this ride")
            .accessibilityHint("Place your bid to pick up this rider")
            .padding(Lx.Spacing.l)
        }
        .lxCard()
    }
}

// MARK: - Route Row

struct RideRouteRow: View {
    let icon: String
    let tint: Color
    let title: String
    let address: String

    var body: some View {
        HStack(spacing: Lx.Spacing.m) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .foregroundColor(tint)
            }

            VStack(alignment: .leading, spacing: Lx.Spacing.xs) {
                Text(title)
                    .font(Lx.Typography.caption.weight(.semibold))
                    .foregroundColor(Lx.Palette.textSecondary)
                Text(address)
                    .font(Lx.Typography.subheadline)
                    .foregroundColor(Lx.Palette.text)
                    .lineLimit(2)
            }

            Spacer()
        }
    }
}

// MARK: - Trip Stat Badge

struct TripStatBadge: View {
    let icon: String
    let text: String
    let label: String

    var body: some View {
        VStack(spacing: Lx.Spacing.xs) {
            HStack(spacing: Lx.Spacing.xs) {
                Image(systemName: icon)
                    .font(Lx.Typography.caption)
                Text(text)
                    .font(Lx.Typography.caption.weight(.semibold))
            }
            .foregroundColor(Lx.Palette.orange)

            Text(label)
                .font(Lx.Typography.caption)
                .foregroundColor(Lx.Palette.textSecondary)
        }
        .padding(.horizontal, Lx.Spacing.m)
        .padding(.vertical, Lx.Spacing.s)
        .background(Lx.Palette.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: Lx.Radius.chip, style: .continuous))
    }
}

// MARK: - Preview

#if DEBUG
struct RideshareDashboardView_Previews: PreviewProvider {
    static var previews: some View {
        RideshareDashboardView()
    }
}
#endif

// MARK: - Transient banner

private struct RideshareBannerModifier: ViewModifier {
    @ObservedObject var viewModel: RideBiddingViewModel

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let banner = viewModel.banner {
                Text(banner.text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(banner.isError ? Theme.lxError : Theme.lxSuccess.opacity(0.95))
                    .cornerRadius(12)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .shadow(radius: 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { viewModel.banner = nil }
                    .accessibilityAddTraits(.isStaticText)
                    .task(id: banner.id) {
                        try? await Task.sleep(nanoseconds: banner.isError ? 6_000_000_000 : 4_000_000_000)
                        if viewModel.banner?.id == banner.id { viewModel.banner = nil }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.banner)
    }
}

extension View {
    func rideshareBanner(_ viewModel: RideBiddingViewModel) -> some View {
        modifier(RideshareBannerModifier(viewModel: viewModel))
    }
}
