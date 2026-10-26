import os

private let logger = Logger(subsystem: "com.dollorai.customer", category: "RideRequestViewModel")

import SwiftUI
import Combine
import EatFairShared
import CoreLocation

/// ViewModel for P2P rideshare matchmaking
/// Dollor.ai connects riders with independent drivers - NOT a TNC service
/// $1 connection fee for using our matchmaking platform
class RideRequestViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var pickupAddress: RideAddressInput?
    @Published var dropoffAddress: RideAddressInput?
    @Published var notes: String = ""
    @Published var accessibilityRequested: Bool = false
    @Published var accessibilityNotes: String = ""
    @Published var selectedAccessibilityOptions: Set<AccessibilityOption> = []

    func toggleAccessibilityOption(_ option: AccessibilityOption) {
        if selectedAccessibilityOptions.contains(option) {
            selectedAccessibilityOptions.remove(option)
        } else {
            selectedAccessibilityOptions.insert(option)
        }
    }

    var structuredAccessibilityNotes: String? {
        guard accessibilityRequested else { return nil }
        var dict: [String: Any] = [:]
        for option in AccessibilityOption.allCases {
            dict[option.rawValue] = selectedAccessibilityOptions.contains(option)
        }
        let freeText = accessibilityNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !freeText.isEmpty { dict["notes"] = freeText }
        if let data = try? JSONSerialization.data(withJSONObject: dict),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return accessibilityNotes.isEmpty ? nil : accessibilityNotes
    }

    @Published var isLoading = false
    @Published var isEstimatingFare = false
    @Published var fareEstimateReceived = false
    @Published var errorMessage: String?
    @Published var showError = false

    // Suggested Offer Calculation (for matchmaking)
    @Published var estimatedDistance: Double = 0.0  // miles
    @Published var estimatedDuration: Double = 0.0  // minutes
    @Published var baseFare: Double = AppConfig.shared.rideBaseFare
    @Published var distanceFee: Double = 0.0
    @Published var timeFee: Double = 0.0
    @Published var surgeMultiplier: Double = 1.0  // Demand multiplier from backend
    @Published var surgeLabel: String = "Standard"  // Demand label from backend
    @Published var backendTotal: Double?       // Backend's calculated total (includes time_adjustment, long_distance_discount)
    @Published var backendSubtotal: Double?    // Backend's calculated subtotal (pre-tax)

    // Active ride tracking
    @Published var activeRide: RideRequestResponse?
    @Published var rideTracking: RideTrackingInfo?
    @Published var isRideActive = false

    // Fare Negotiation ($1+$1 platform fee model)
    @Published var isNegotiating = false
    @Published var driverOfferAmount: Double?
    @Published var showNegotiationSheet = false
    @Published var negotiationMessage: String?
    @Published var initialFareOffer: Double? = nil  // Customer's initial offer before request

    // Ride Cancellation
    @Published var showCancelSheet = false
    @Published var cancellationFee: Double = 0.0
    @Published var cancellationReason: String = ""

    // P2P Driver Bids (incoming bids from drivers)
    @Published var incomingBids: [RideBid] = []
    @Published var selectedBid: RideBid?
    @Published var showBidsSheet = false
    @Published var acceptedDriver: AcceptedDriverInfo?
    @Published var driverETA: Int?  // Estimated arrival in minutes
    @Published var driverHasArrived = false  // True when driver taps "I've Arrived"

    // Payment
    @Published var paymentIntentClientSecret: String?
    @Published var showPaymentSheet = false
    // Gates bid acceptance on having a saved payment method — the backend now
    // requires one (charges the customer's default payment method at accept time)
    // and fails the whole match fast rather than silently authorizing nothing.
    @Published var showPaymentMethodsSheet = false
    private var bidPendingPaymentSetup: RideBid?

    // UI State
    @Published var currentStep: RideRequestStep = .selectPickup

    enum RideRequestStep {
        case selectPickup
        case selectDropoff
        case confirmRide
        case waitingForDriver
        case driverEnRoute
        case rideInProgress
        case completed
    }

    // Connection Status (for polling failure detection)
    @Published var showConnectionWarning = false

    // MARK: - Private Properties
    private let p2pService = P2PAPIService.shared
    private let wsManager = WebSocketManager.shared
    private var trackingTimer: Timer?
    private var negotiationTimer: Timer?
    private var bidPollingTimer: Timer?
    private var trackingFailureCount = 0
    private var negotiationFailureCount = 0
    private let maxFailuresBeforeWarning = 3

    // MARK: - Pricing Constants (from AppConfig - matches backend pricing_config.py)
    // All pricing values come from centralized AppConfig - no hardcodes!
    private let config = AppConfig.shared

    // MARK: - Computed Properties (from AppConfig)
    // Platform fee is FARE-BASED (tiered by fare value):
    //   Fares ≤$35: $1, $35-$70: $2, >$70: $3
    //   Both rider AND driver pay this same fee

    /// Estimated fare for tier calculation (driver portion before platform fee)
    private var fareForTierCalculation: Double {
        let driverPortion = (baseFare + distanceFee + timeFee) * surgeMultiplier
        return max(driverPortion, minimumFare)
    }

    var platformFee: Double {
        // Calculate platform fee based on FARE (not distance)
        return config.calculateRidesharePlatformFee(fareAmount: fareForTierCalculation)
    }

    /// Platform fee description for UI display (fare-based)
    var platformFeeTierDescription: String {
        return config.getRideshareFeeDescription(fareAmount: fareForTierCalculation)
    }

    /// Driver's platform fee (same as rider)
    var driverPlatformFee: Double {
        return platformFee
    }

    var baseFareConst: Double { config.rideBaseFare }
    var perMileRate: Double { config.ridePerMileRate }
    var perMinuteRate: Double { config.ridePerMinuteRate }
    var minimumFare: Double { config.rideMinFare }
    var cancellationFeeAmount: Double { config.rideCancellationFee }

    /// Tax rate based on pickup state (from centralized StateTaxRates)
    var taxRate: Double {
        guard let state = pickupAddress?.state else { return 0.0 }
        let stateCode = StateTaxRates.stateCode(from: state)
        return StateTaxRates.rate(for: stateCode)
    }

    /// Tax amount on the fare
    var taxAmount: Double {
        fareBeforeTax * taxRate
    }

    /// The ride fare only (driver's portion, BEFORE platform fee / regulatory fee / tax).
    /// Uses the backend subtotal when available (includes time_adjustment + long_distance_discount).
    /// Falls back to local recalculation only when the API is unavailable.
    var fareBeforeTax: Double {
        if let backendSubtotal = backendSubtotal {
            return backendSubtotal
        }
        // Fallback for local calculation only (fare only — fees are added separately)
        let driverPortion = (baseFare + distanceFee + timeFee) * surgeMultiplier
        return max(driverPortion, minimumFare)
    }

    /// Regulatory fee (e.g. CPUC "Access for All" customer share) = whatever the backend
    /// total includes beyond the fare + platform fee. Zero on the local fallback path.
    var regulatoryFee: Double {
        guard let total = backendTotal else { return 0 }
        let remainder = total - fareBeforeTax - platformFee
        return remainder > 0.005 ? remainder : 0
    }

    /// What driver receives (fare - driver's platform fee). Tip is added post-ride.
    var driverEarnings: Double {
        let driverPortion = (baseFare + distanceFee + timeFee) * surgeMultiplier
        let fare = max(driverPortion, minimumFare)
        return fare - driverPlatformFee
    }

    /// Connection fee for matchmaking service (tiered: $1-$3 based on fare)
    var platformEarnings: Double {
        platformFee
    }

    /// Customer total before tip (fare + platform fee + regulatory fee + tax).
    /// Equals the backend total when available so it matches what is actually charged.
    var subtotal: Double {
        estimatedFare
    }

    /// Total amount the customer pays (fare + platform fee + regulatory fee). Tip is added post-ride.
    var totalAmount: Double {
        estimatedFare
    }

    /// Estimated fare (used in UI before tip)
    /// Uses backend total when available for exact match with server-side calculation.
    var estimatedFare: Double {
        if let total = backendTotal {
            return total
        }
        // Local fallback: fare + platform fee + tax (no backend regulatory fee available)
        return fareBeforeTax + platformFee + taxAmount
    }

    var canRequestRide: Bool {
        pickupAddress != nil && dropoffAddress != nil
    }

    /// Formatted estimated time
    var estimatedTimeText: String {
        if estimatedDuration > 0 {
            return "\(Int(estimatedDuration)) min"
        }
        return "--"
    }

    /// Formatted estimated distance
    var estimatedDistanceText: String {
        if estimatedDistance > 0 {
            return String(format: "%.1f mi", estimatedDistance)
        }
        return "--"
    }

    // MARK: - Initialization
    init() {}

    deinit {
        trackingTimer?.invalidate()
        negotiationTimer?.invalidate()
        bidPollingTimer?.invalidate()
        wsManager.disconnect()
    }

    // MARK: - Set Pickup Location
    func setPickupLocation(street: String, city: String, state: String, zip: String, lat: Double, lng: Double) {
        pickupAddress = RideAddressInput(
            street: street,
            city: city,
            state: state,
            zip: zip,
            lat: lat,
            lng: lng
        )
        currentStep = .selectDropoff
    }

    // MARK: - Set Dropoff Location
    func setDropoffLocation(street: String, city: String, state: String, zip: String, lat: Double, lng: Double) {
        dropoffAddress = RideAddressInput(
            street: street,
            city: city,
            state: state,
            zip: zip,
            lat: lat,
            lng: lng
        )
        currentStep = .confirmRide

        // Calculate fare estimate
        estimateFare()
    }

    // MARK: - Fare Estimation (from Production API - consistent with Android)
    /// Fetches fare estimate from production API instead of local calculation
    /// This ensures consistent pricing between iOS and Android platforms
    private func estimateFare() {
        guard let pickup = pickupAddress, let dropoff = dropoffAddress else { return }

        // Reset state for new estimation
        fareEstimateReceived = false
        isEstimatingFare = true
        backendTotal = nil
        backendSubtotal = nil

        // Get state code for tax calculation
        let stateCode = StateTaxRates.stateCode(from: pickup.state)

        // Call production API for fare estimate (same endpoint as Android)
        p2pService.estimateRideFare(
            pickupLat: pickup.lat,
            pickupLng: pickup.lng,
            dropoffLat: dropoff.lat,
            dropoffLng: dropoff.lng,
            stateCode: stateCode
        ) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let response):
                let estimate = response.estimate
                // Update published properties from API response
                self.estimatedDistance = estimate.distanceMiles
                self.estimatedDuration = estimate.durationMinutes
                self.baseFare = estimate.breakdown.baseFare
                self.distanceFee = estimate.breakdown.distanceCost
                self.timeFee = estimate.breakdown.timeCost

                // Store backend totals for direct display (includes time_adjustment, long_distance_discount)
                self.backendTotal = estimate.total
                self.backendSubtotal = estimate.subtotal

                // Apply surge/demand multiplier from backend
                if let surge = estimate.surgeMultiplier {
                    self.surgeMultiplier = surge
                }
                if let label = estimate.surgeLabel {
                    self.surgeLabel = label
                }

                self.fareEstimateReceived = true
                self.isEstimatingFare = false

                #if DEBUG
                logger.info("[RideRequestViewModel] Fare estimate from production API:")
                logger.debug("  Distance: \(estimate.distanceMiles) miles")
                logger.debug("  Duration: \(estimate.durationMinutes) min")
                logger.debug("  Total: $\(estimate.total)")
                logger.debug("  Platform fee: $\(estimate.platformFee)")
                if let surge = estimate.surgeMultiplier, surge > 1.0 {
                    logger.debug("  Surge: \(surge)x (\(estimate.surgeLabel ?? ""))")
                }
                #endif

            case .failure(let error):
                #if DEBUG
                logger.info("[RideRequestViewModel] Fare estimate API error: \(error)")
                #endif
                // Fallback to local calculation if API fails
                self.estimateFareLocally()
                self.fareEstimateReceived = true
                self.isEstimatingFare = false
            }
        }
    }

    /// Fallback local calculation if API is unavailable
    private func estimateFareLocally() {
        guard let pickup = pickupAddress, let dropoff = dropoffAddress else { return }

        // Calculate distance using Haversine formula
        let distance = haversineDistance(
            lat1: pickup.lat, lon1: pickup.lng,
            lat2: dropoff.lat, lon2: dropoff.lng
        )

        // Estimate duration (25 mph average urban speed + 20% buffer)
        let duration = (distance / 25.0) * 60 * 1.2

        // Update published properties
        estimatedDistance = distance
        estimatedDuration = duration
        distanceFee = distance * perMileRate
        timeFee = duration * perMinuteRate

        #if DEBUG
        logger.info("[RideRequestViewModel] Using local fallback calculation")
        #endif
    }

    /// Haversine formula to calculate distance between two coordinates
    private func haversineDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let R = 3959.0 // Earth's radius in miles

        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180

        let a = sin(dLat/2) * sin(dLat/2) +
                cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) *
                sin(dLon/2) * sin(dLon/2)

        let c = 2 * atan2(sqrt(a), sqrt(1-a))

        return R * c
    }

    // MARK: - Request Ride
    func requestRide(customerName: String, customerEmail: String, customerPhone: String) {
        guard let pickup = pickupAddress, let dropoff = dropoffAddress else {
            showErrorMessage("Please select pickup and dropoff locations")
            return
        }

        // Get customer ID from UserDefaults (set during login)
        let customerId = UserDefaults.standard.integer(forKey: "p2p_customer_id")
        guard customerId > 0 else {
            showErrorMessage("Please login to request a ride")
            return
        }

        // Check for a saved payment method. Only block booking if we definitively know
        // the customer has none — on any API failure we proceed and let the backend handle it.
        isLoading = true
        p2pService.fetchSavedCards(customerId: customerId) { [weak self] cardsResult in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch cardsResult {
                case .success(let cards) where cards.isEmpty:
                    // Confirmed no card — ask them to add one first
                    self.isLoading = false
                    self.showPaymentMethodsSheet = true
                default:
                    // Has card, or API errored — proceed with booking
                    self.doRequestRide(customerId: customerId, customerName: customerName,
                                       customerEmail: customerEmail, customerPhone: customerPhone,
                                       pickup: pickup, dropoff: dropoff)
                }
            }
        }
    }

    /// Called when the payment sheet is dismissed — retries booking only if a card is now saved.
    func retryRequestRide() {
        showPaymentMethodsSheet = false
        guard let pickup = pickupAddress, let dropoff = dropoffAddress else { return }
        let customerId = UserDefaults.standard.integer(forKey: "p2p_customer_id")
        guard customerId > 0 else { return }
        isLoading = true
        p2pService.fetchSavedCards(customerId: customerId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let cards) where cards.isEmpty:
                    self.isLoading = false
                    self.showErrorMessage("Please add a payment method to book a ride.")
                default:
                    self.doRequestRide(customerId: customerId, customerName: "", customerEmail: "", customerPhone: "",
                                       pickup: pickup, dropoff: dropoff)
                }
            }
        }
    }

    private func doRequestRide(customerId: Int, customerName: String, customerEmail: String,
                               customerPhone: String, pickup: RideAddressInput, dropoff: RideAddressInput) {
        p2pService.requestRide(
            customerId: customerId,
            pickupAddress: pickup,
            dropoffAddress: dropoff,
            notes: notes.isEmpty ? nil : notes,
            preferredPrice: initialFareOffer,
            accessibilityRequested: accessibilityRequested,
            accessibilityNotes: structuredAccessibilityNotes
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }

                switch result {
                case .success(let response):
                    self.activeRide = response
                    self.isRideActive = true
                    self.currentStep = .waitingForDriver
                    self.startTrackingRide()

                    // Start polling for driver bids (P2P bidding flow)
                    self.startBidPolling()

                    // If customer set an initial fare offer, submit it automatically
                    if let initialOffer = self.initialFareOffer, let rideId = response.rideId {
                        self.submitInitialFareOffer(rideId: rideId, offer: initialOffer)
                    } else {
                        self.isLoading = false
                    }

                case .failure(let error):
                    self.isLoading = false
                    let errorMsg = error.localizedDescription.lowercased()
                    if errorMsg.contains("network") || errorMsg.contains("connection") {
                        self.showErrorMessage("Unable to connect. Please check your internet connection.")
                    } else if errorMsg.contains("busy") || errorMsg.contains("unavailable") {
                        self.showErrorMessage("No drivers available in your area. Please try again later.")
                    } else if errorMsg.contains("unpaid balance") {
                        self.showErrorMessage("You have an outstanding balance from a previous ride. Please contact support to resolve it before requesting again.")
                    } else if errorMsg.contains("already have 3") || errorMsg.contains("open ride requests") {
                        self.showErrorMessage("You have open ride requests pending. Please wait or cancel them before requesting a new ride.")
                    } else if errorMsg.contains("pre-authorized") || errorMsg.contains("card could not") {
                        self.showErrorMessage("Your payment method could not be authorized. Please update your card in Settings.")
                    } else if errorMsg.contains("http error: 401") || errorMsg.contains("invalid or expired token") {
                        self.showErrorMessage("Your session has expired. Please log in again.")
                    } else {
                        self.showErrorMessage("Unable to request ride. Please try again.")
                    }
                    logger.error("Ride request error: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Submit initial fare offer after ride creation (for pre-request negotiation)
    private func submitInitialFareOffer(rideId: Int, offer: Double) {
        p2pService.customerSubmitFareOffer(rideId: rideId, proposedFare: offer) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false

                switch result {
                case .success(let response):
                    self.isNegotiating = true
                    self.negotiationMessage = "Your offer of $\(String(format: "%.2f", offer)) sent to drivers"

                    if response.status == "accepted" {
                        self.negotiationMessage = "Fare accepted! Driver is on the way."
                        self.isNegotiating = false
                    } else {
                        // Start polling for driver response
                        self.startNegotiationPolling()
                    }

                case .failure(let error):
                    // Negotiation failed but ride is still active
                    self.negotiationMessage = "Unable to send your offer. Your ride request is still active."
                    logger.error("Initial fare offer error: \(error.localizedDescription)")
                }

                // Clear the initial offer
                self.initialFareOffer = nil
            }
        }
    }

    // MARK: - P2P Bid Polling (fetch incoming driver bids)

    /// Start polling for incoming driver bids
    private func startBidPolling() {
        guard let requestId = activeRide?.rideId else {
            logger.warning("Cannot start bid polling - no active ride request ID")
            return
        }

        logger.info("Starting bid polling for request \(requestId)")

        // Connect WebSocket for real-time bid updates
        connectWebSocket(rideId: requestId)

        // Fetch immediately, then poll (slower if WS connected)
        fetchIncomingBids(requestId: requestId)

        bidPollingTimer?.invalidate()
        bidPollingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            // Stop polling once a driver is accepted
            if self.acceptedDriver != nil || self.currentStep == .driverEnRoute || self.currentStep == .rideInProgress {
                self.stopBidPolling()
                return
            }
            // Always poll as fallback; WebSocket triggers immediate fetches on top of this
            self.fetchIncomingBids(requestId: requestId)
        }
    }

    /// Stop bid polling
    private func stopBidPolling() {
        logger.info("Stopping bid polling")
        bidPollingTimer?.invalidate()
        bidPollingTimer = nil
    }

    /// Connect WebSocket for real-time bid and ride status updates
    private func connectWebSocket(rideId: Int) {
        guard let customerId = p2pService.currentCustomerId else { return }

        wsManager.onNewBid = { [weak self] data in
            guard let self = self,
                  let bidRideId = data["ride_request_id"] as? Int,
                  bidRideId == rideId else { return }
            logger.info("[WS] New bid received for ride \(rideId)")
            self.fetchIncomingBids(requestId: rideId)
        }

        wsManager.onRideStatusUpdate = { [weak self] data in
            guard let self = self else { return }
            if let status = data["status"] as? String {
                logger.info("[WS] Ride status update: \(status)")
                if status == "driver_arrived" {
                    DispatchQueue.main.async { self.driverHasArrived = true }
                }
            }
        }

        wsManager.onDriverLocation = { [weak self] data in
            guard let self = self else { return }
            if let eta = data["eta_minutes"] as? Int {
                DispatchQueue.main.async { self.driverETA = eta }
            }
        }

        wsManager.onETAUpdate = { [weak self] data in
            guard let self = self else { return }
            if let eta = data["eta_pickup_minutes"] as? Int {
                DispatchQueue.main.async { self.driverETA = eta }
            }
        }

        wsManager.connect(clientType: "customer", entityId: customerId, token: SecureStorage.shared.customerAccessToken)
        wsManager.subscribe(topic: "ride:\(rideId)")
        wsManager.subscribe(topic: "customer:\(customerId)")
    }

    /// Fetch incoming bids for the current ride request
    private func fetchIncomingBids(requestId: Int) {
        p2pService.fetchRideRequestBids(requestId: requestId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }

                switch result {
                case .success(let response):
                    // The driver may have accepted the rider's counter-offer: the match then happens
                    // server-side and no bid stays actionable, so detect it here or the rider would
                    // wait on "Waiting for drivers…" forever.
                    if self.acceptedDriver == nil,
                       let accepted = response.bids.first(where: { $0.status == "accepted" }) {
                        self.completeMatch(with: accepted)
                        return
                    }

                    // Show bids the customer can act on:
                    // - "pending" = driver just bid, awaiting customer response
                    // - "countered" where last_offer_by == "driver" = driver countered back,
                    //   awaiting customer accept/reject (bid.status goes to "pending" after
                    //   driver-counter in the current backend, but include countered defensively)
                    let newBids = response.bids.filter {
                        $0.status == "pending" ||
                        ($0.status == "countered" && ($0.last_offer_by ?? "") == "driver")
                    }
                    if newBids.count != self.incomingBids.count {
                        logger.info("Received \(newBids.count) actionable bids")
                    }
                    self.incomingBids = newBids

                    // Auto-show bids sheet when first bid arrives
                    if !newBids.isEmpty && !self.showBidsSheet && self.acceptedDriver == nil {
                        self.showBidsSheet = true
                    }

                case .failure(let error):
                    logger.error("Failed to fetch bids: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Moves the rider into the matched state for a bid the driver accepted (counter-offer path).
    private func completeMatch(with bid: RideBid) {
        stopBidPolling()
        showBidsSheet = false
        incomingBids = []
        isNegotiating = false
        let vehicleParts = (bid.driver_vehicle ?? "").split(separator: " ")
        acceptedDriver = AcceptedDriverInfo(
            id: bid.driver_id,
            name: bid.driver_name,
            phone: nil,
            rating: bid.driver_rating,
            photo_url: bid.driver_photo_url,
            vehicle_make: vehicleParts.first.map(String.init),
            vehicle_model: vehicleParts.count >= 2 ? vehicleParts.dropFirst().joined(separator: " ") : nil,
            vehicle_color: nil,
            vehicle_year: nil,
            license_plate: nil,
            vehicle_photo_url: nil
        )
        driverETA = bid.estimated_arrival_minutes
        currentStep = .driverEnRoute
        negotiationMessage = nil
    }

    // MARK: - Accept/Reject Driver Bids

    /// Accept a driver's bid
    func acceptBid(_ bid: RideBid) {
        // Prevent double-tap race condition
        guard !isLoading else { return }

        // The backend now charges the customer's saved default payment method at
        // accept time and fails the match if there isn't one — check first so the
        // customer sees "add a payment method" instead of a failed-match surprise
        // after they've already committed to a driver.
        guard let customerId = p2pService.currentCustomerId else { return }
        isLoading = true
        p2pService.fetchSavedCards(customerId: customerId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                let hasCard = (try? result.get())?.isEmpty == false
                if hasCard {
                    self.performAcceptBid(bid)
                } else {
                    self.bidPendingPaymentSetup = bid
                    self.showPaymentMethodsSheet = true
                }
            }
        }
    }

    /// Called after the payment-methods sheet confirms a card/Apple Pay was added.
    func retryAcceptBidAfterPaymentSetup() {
        showPaymentMethodsSheet = false
        if let bid = bidPendingPaymentSetup {
            // Sheet was triggered by bid acceptance — retry the accept
            bidPendingPaymentSetup = nil
            performAcceptBid(bid)
        } else if pickupAddress != nil {
            // Sheet was triggered by initial booking — retry the ride request
            retryRequestRide()
        }
    }

    private func performAcceptBid(_ bid: RideBid) {
        isLoading = true
        selectedBid = bid

        // Clear any stale negotiation state to prevent race conditions
        isNegotiating = false
        driverOfferAmount = nil
        showCounterSheet = false
        selectedBidForCounter = nil

        p2pService.acceptDriverBid(bidId: bid.id) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false

                switch result {
                case .success(let response):
                    logger.info("Bid accepted: \(response.message)")

                    // Stop polling for more bids
                    self.stopBidPolling()
                    self.showBidsSheet = false
                    self.incomingBids = []

                    // Store driver info from the bid
                    self.acceptedDriver = AcceptedDriverInfo(
                        id: bid.driver_id,
                        name: bid.driver_name,
                        phone: nil,
                        rating: bid.driver_rating,
                        photo_url: bid.driver_photo_url,
                        vehicle_make: nil,
                        vehicle_model: nil,
                        vehicle_color: nil,
                        vehicle_year: nil,
                        license_plate: nil,
                        vehicle_photo_url: nil
                    )

                    // Parse vehicle info from driver_vehicle string (e.g., "Toyota Camry")
                    if let vehicle = bid.driver_vehicle {
                        let parts = vehicle.split(separator: " ")
                        if parts.count >= 2 {
                            self.acceptedDriver = AcceptedDriverInfo(
                                id: bid.driver_id,
                                name: bid.driver_name,
                                phone: nil,
                                rating: bid.driver_rating,
                                photo_url: bid.driver_photo_url,
                                vehicle_make: String(parts[0]),
                                vehicle_model: parts.dropFirst().joined(separator: " "),
                                vehicle_color: nil,
                                vehicle_year: nil,
                                license_plate: nil,
                                vehicle_photo_url: nil
                            )
                        }
                    }

                    // Use the driver's response if available
                    if let driver = response.driver {
                        self.acceptedDriver = driver
                    }

                    self.driverETA = bid.estimated_arrival_minutes ?? response.estimated_arrival_minutes

                    // Transition to driver en route step
                    self.currentStep = .driverEnRoute
                    self.negotiationMessage = nil  // Status bar already shows "Driver accepted"

                case .failure(let error):
                    let errorMsg = error.localizedDescription.lowercased()
                    if errorMsg.contains("expired") || errorMsg.contains("no longer") {
                        self.showErrorMessage("This bid has expired. Please select another driver.")
                    } else if errorMsg.contains("accepted") || errorMsg.contains("unavailable") {
                        self.showErrorMessage("This driver is no longer available. Please select another.")
                    } else {
                        self.showErrorMessage("Unable to accept this bid. Please try again.")
                    }
                    logger.error("Accept bid error: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Reject a driver's bid
    func rejectBid(_ bid: RideBid) {
        p2pService.rejectDriverBid(bidId: bid.id) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }

                switch result {
                case .success:
                    // Remove the rejected bid from the list
                    self.incomingBids.removeAll { $0.id == bid.id }
                    logger.info("Bid rejected successfully")

                case .failure(let error):
                    logger.error("Failed to reject bid: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Counter a driver's bid with a new price
    /// Uses /rides/bid/{id}/respond with action="counter"
    @Published var counterOfferWarning: String?
    @Published var customerCountersRemaining: Int = 3
    @Published var currentNegotiationRound: Int = 1
    @Published var showCounterSheet = false
    @Published var selectedBidForCounter: RideBid?

    func counterBid(_ bid: RideBid, counterPrice: Double, message: String? = nil) {
        // Prevent double-tap and counter while already accepted
        guard !isLoading else { return }
        guard acceptedDriver == nil else {
            showErrorMessage("You've already accepted a driver.")
            return
        }

        isLoading = true
        selectedBidForCounter = bid

        p2pService.counterDriverBid(bidId: bid.id, counterPrice: counterPrice, message: message) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false

                switch result {
                case .success(let response):
                    if response.success {
                        logger.info("Counter-offer sent: \(response.message ?? "")")

                        // Update negotiation state
                        self.customerCountersRemaining = response.customer_counters_remaining ?? (self.customerCountersRemaining - 1)
                        self.currentNegotiationRound = response.negotiation_round ?? self.currentNegotiationRound
                        self.counterOfferWarning = response.warning

                        // Show warning if present
                        if let warning = response.warning {
                            self.negotiationMessage = warning
                        } else {
                            self.negotiationMessage = "Counter-offer of $\(String(format: "%.2f", counterPrice)) sent. Waiting for driver..."
                        }

                        // Update the bid in the list with new status
                        if let updatedBid = response.bid {
                            if let index = self.incomingBids.firstIndex(where: { $0.id == bid.id }) {
                                self.incomingBids[index] = updatedBid
                            }
                        }

                        // Close the counter sheet
                        self.showCounterSheet = false
                        self.isNegotiating = true

                        // Start polling for driver's response
                        self.startNegotiationPolling()
                    } else {
                        self.showErrorMessage(response.message ?? "Failed to send counter-offer")
                    }

                case .failure(let error):
                    let errorMsg = error.localizedDescription.lowercased()
                    if errorMsg.contains("expired") {
                        self.showErrorMessage("This bid has expired. Please select another driver.")
                    } else if errorMsg.contains("limit") || errorMsg.contains("maximum") {
                        self.showErrorMessage("You've reached the maximum counter-offers for this bid.")
                    } else {
                        self.showErrorMessage("Unable to send counter-offer. Please try again.")
                    }
                    logger.error("Counter-offer failed: \(error)")
                }
            }
        }
    }

    /// Open counter-offer sheet for a bid
    func showCounterOffer(for bid: RideBid) {
        selectedBidForCounter = bid
        showCounterSheet = true
    }

    // MARK: - Track Ride
    private func startTrackingRide() {
        trackingTimer?.invalidate()
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.fetchRideStatus()
        }
        // Fetch immediately
        fetchRideStatus()
    }

    private func fetchRideStatus() {
        guard let rideId = activeRide?.rideId else { return }

        p2pService.trackMyRide(rideId: rideId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let tracking):
                    self.rideTracking = tracking
                    self.updateRideStep(from: tracking.status)
                    self.trackingFailureCount = 0  // Reset on success
                    self.showConnectionWarning = false
                    // Detect driver arrived at pickup
                    if tracking.driverArrivedAt != nil && !self.driverHasArrived {
                        self.driverHasArrived = true
                    }
                    // Populate the matched driver's phone from the track response so the
                    // "Call driver" action works. RideBid carries no phone, so acceptedDriver
                    // was created with phone=nil; backfill it here once available.
                    if let phone = tracking.driverPhone, !phone.isEmpty,
                       let existing = self.acceptedDriver, (existing.phone ?? "").isEmpty {
                        self.acceptedDriver = AcceptedDriverInfo(
                            id: existing.id,
                            name: existing.name,
                            phone: phone,
                            rating: existing.rating,
                            photo_url: existing.photo_url,
                            vehicle_make: existing.vehicle_make,
                            vehicle_model: existing.vehicle_model,
                            vehicle_color: existing.vehicle_color,
                            vehicle_year: existing.vehicle_year,
                            license_plate: existing.license_plate,
                            vehicle_photo_url: existing.vehicle_photo_url
                        )
                    }

                case .failure(let error):
                    self.trackingFailureCount += 1
                    logger.debug("Tracking poll failed (\(self.trackingFailureCount)): \(error.localizedDescription)")
                    if self.trackingFailureCount >= self.maxFailuresBeforeWarning {
                        self.showConnectionWarning = true
                    }
                }
            }
        }
    }

    /// Replaces the pre-negotiation estimate with the server's final numbers
    /// (accepted bid + connection fee + regulatory fee) so the summary matches the receipt.
    private func refreshCompletedFare() {
        guard let rideId = activeRide?.rideId else { return }
        p2pService.fetchRideReceipt(rideId: rideId) { [weak self] result in
            guard case .success(let json) = result,
                  let receipt = json["receipt"] as? [String: Any],
                  let breakdown = receipt["fare_breakdown"] as? [String: Any],
                  let baseFare = breakdown["base_fare"] as? Double,
                  let total = breakdown["total"] as? Double else { return }
            self?.backendSubtotal = baseFare
            self?.backendTotal = total
        }
    }

    private func updateRideStep(from status: String) {
        switch status.lowercased() {
        case "open", "bidding", "preparing", "waiting_for_driver":
            currentStep = .waitingForDriver
        case "matched", "accepted", "driver_assigned", "driver_arrived":
            currentStep = .driverEnRoute
        case "picked_up", "in_progress":
            currentStep = .rideInProgress
        case "delivered", "completed":
            currentStep = .completed
            stopTracking()
            refreshCompletedFare()
        case "expired":
            stopTracking()
            NotificationCenter.default.post(name: NSNotification.Name("RideRequestExpired"), object: nil)
        case "cancelled":
            stopTracking()
            showErrorMessage("Your ride was cancelled.")
        default:
            break
        }
    }

    private func stopTracking() {
        trackingTimer?.invalidate()
        trackingTimer = nil
        stopNegotiationPolling()
        stopBidPolling()
    }

    // MARK: - Negotiation Status Polling

    /// Start polling for negotiation status updates (driver counter-offers)
    private func startNegotiationPolling() {
        negotiationTimer?.invalidate()
        negotiationTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.fetchNegotiationStatus()
        }
        // Fetch immediately
        fetchNegotiationStatus()
    }

    /// Stop negotiation polling
    private func stopNegotiationPolling() {
        negotiationTimer?.invalidate()
        negotiationTimer = nil
    }

    /// Fetch current negotiation status from backend
    private func fetchNegotiationStatus() {
        guard let rideId = activeRide?.rideId, isNegotiating else { return }

        p2pService.getRideNegotiationStatus(rideId: rideId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let status):
                    self.handleNegotiationStatusUpdate(status)
                    self.negotiationFailureCount = 0  // Reset on success
                    self.showConnectionWarning = false

                case .failure(let error):
                    self.negotiationFailureCount += 1
                    logger.debug("Negotiation poll failed (\(self.negotiationFailureCount)): \(error.localizedDescription)")
                    if self.negotiationFailureCount >= self.maxFailuresBeforeWarning {
                        self.showConnectionWarning = true
                    }
                }
            }
        }
    }

    /// Handle negotiation status update from backend
    private func handleNegotiationStatusUpdate(_ status: RideNegotiationStatus) {
        switch status.negotiationStatus.lowercased() {
        case "driver_countered":
            // Driver has submitted a counter-offer
            if let driverOffer = status.driverOffer, driverOffer != driverOfferAmount {
                driverOfferAmount = driverOffer
                negotiationMessage = "Driver counter-offered $\(String(format: "%.2f", driverOffer))"
                showNegotiationSheet = true
            }

        case "accepted":
            // Negotiation accepted - fare agreed!
            isNegotiating = false
            stopNegotiationPolling()
            if let agreedFare = status.agreedFare {
                negotiationMessage = "Fare agreed at $\(String(format: "%.2f", agreedFare))! Driver is on the way."
            } else {
                negotiationMessage = "Fare accepted! Driver is on the way."
            }
            showNegotiationSheet = false

        case "rejected":
            // Negotiation rejected
            isNegotiating = false
            stopNegotiationPolling()
            negotiationMessage = status.message ?? "Negotiation was not accepted"
            driverOfferAmount = nil

        case "customer_offered":
            // Waiting for driver response
            negotiationMessage = "Waiting for driver's response..."

        case "none":
            // No active negotiation
            break

        default:
            break
        }
    }

    // MARK: - Reset
    func resetRide() {
        stopTracking()
        // Disconnect WebSocket FIRST, then clear handlers
        wsManager.disconnect()
        wsManager.onNewBid = nil
        wsManager.onRideStatusUpdate = nil
        wsManager.onDriverLocation = nil
        wsManager.onETAUpdate = nil

        pickupAddress = nil
        dropoffAddress = nil
        notes = ""
        activeRide = nil
        rideTracking = nil
        isRideActive = false
        currentStep = .selectPickup

        // Fare estimate state
        estimatedDistance = 0.0
        estimatedDuration = 0.0
        baseFare = AppConfig.shared.rideBaseFare
        distanceFee = 0.0
        timeFee = 0.0
        surgeMultiplier = 1.0
        surgeLabel = "Standard"

        // Bid/driver state
        incomingBids = []
        selectedBid = nil
        acceptedDriver = nil
        driverETA = nil
        driverHasArrived = false

        // Negotiation state
        isNegotiating = false
        driverOfferAmount = nil
        showNegotiationSheet = false
        negotiationMessage = nil
        initialFareOffer = nil
        counterOfferWarning = nil
        customerCountersRemaining = 3
        currentNegotiationRound = 1
        showCounterSheet = false
        selectedBidForCounter = nil

        // Payment state
        paymentIntentClientSecret = nil
        showPaymentSheet = false

        // Sheet visibility — must be cleared so stale state from a prior ride
        // doesn't block sheets on the next request (e.g. showBidsSheet staying
        // true after expiry causes SwiftUI sheet conflict with showPaymentMethodsSheet)
        showBidsSheet = false
        showPaymentMethodsSheet = false

        // Cancellation state
        showCancelSheet = false
        cancellationFee = 0.0
        cancellationReason = ""

        // Connection state
        showConnectionWarning = false
        trackingFailureCount = 0
        negotiationFailureCount = 0
    }

    // MARK: - Helpers
    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }

    // MARK: - Ride Cancellation

    /// Cancel ride with calculated fee
    func cancelRide(reason: String?) {
        guard let rideId = activeRide?.rideId else {
            showErrorMessage("No active ride to cancel")
            return
        }

        isLoading = true
        cancellationReason = reason ?? ""

        p2pService.cancelRide(rideId: rideId, reason: reason) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false

                switch result {
                case .success(let response):
                    let fee = response.cancellationFee ?? 0
                    self?.cancellationFee = fee
                    if fee > 0 {
                        self?.negotiationMessage = "Cancelled with $\(String(format: "%.2f", fee)) fee"
                    }
                    self?.resetRide()

                case .failure(let error):
                    let errorMsg = error.localizedDescription.lowercased()
                    if errorMsg.contains("already") || errorMsg.contains("completed") {
                        self?.showErrorMessage("This ride cannot be cancelled as it's already in progress.")
                    } else {
                        self?.showErrorMessage("Unable to cancel ride. Please try again or contact support.")
                    }
                    logger.error("Cancel ride error: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Get estimated cancellation fee based on ride status (from AppConfig)
    var estimatedCancellationFee: Double {
        // Fee structure from centralized config
        switch currentStep {
        case .waitingForDriver:
            return 0.0  // Free cancellation
        case .driverEnRoute:
            return config.rideCancellationFeeDriverEnRoute  // Driver assigned
        case .rideInProgress:
            return config.rideCancellationFeeInProgress  // Ride in progress
        default:
            return 0.0
        }
    }

    // MARK: - Fare Negotiation ($1+$1 Platform Fee Model)

    /// Submit counter-offer for fare
    func submitFareOffer(proposedFare: Double) {
        guard let rideId = activeRide?.rideId else {
            showErrorMessage("No active ride to negotiate")
            return
        }

        isLoading = true
        isNegotiating = true

        p2pService.customerSubmitFareOffer(rideId: rideId, proposedFare: proposedFare) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false

                switch result {
                case .success(let response):
                    if response.status == "accepted" {
                        self?.negotiationMessage = "Fare accepted! Driver is on the way."
                        self?.isNegotiating = false
                        self?.showNegotiationSheet = false
                        self?.stopNegotiationPolling()
                    } else {
                        self?.driverOfferAmount = response.driverOffer
                        self?.negotiationMessage = response.message ?? "Waiting for driver response..."
                        // Start polling for driver's counter-offer
                        self?.startNegotiationPolling()
                    }

                case .failure(let error):
                    self?.isNegotiating = false
                    self?.showErrorMessage(error.localizedDescription.isEmpty
                        ? "Unable to send your fare offer. Please try again."
                        : error.localizedDescription)
                    logger.error("Fare negotiation error: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Accept driver's counter-offer
    func acceptDriverOffer() {
        guard let rideId = activeRide?.rideId,
              let driverOffer = driverOfferAmount else {
            showErrorMessage("No driver offer to accept")
            return
        }

        isLoading = true

        p2pService.customerAcceptDriverFare(rideId: rideId, acceptedFare: driverOffer) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false

                switch result {
                case .success:
                    self?.isNegotiating = false
                    self?.showNegotiationSheet = false
                    self?.stopNegotiationPolling()
                    self?.negotiationMessage = "Fare agreed at $\(String(format: "%.2f", driverOffer))! Driver is on the way."
                    self?.driverOfferAmount = nil

                case .failure(let error):
                    self?.showErrorMessage("Unable to accept the driver's offer. Please try again.")
                    logger.error("Accept driver offer error: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Decline driver's offer and optionally submit counter
    func declineDriverOffer() {
        driverOfferAmount = nil
        negotiationMessage = "Offer declined. Submit a new counter-offer."
    }

    // MARK: - Stripe Payment

    /// Create payment intent for ride
    func createPaymentIntent() {
        guard let rideId = activeRide?.rideId else {
            showErrorMessage("No active ride for payment")
            return
        }

        isLoading = true

        p2pService.createRidePaymentIntent(rideId: rideId, amount: totalAmount) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false

                switch result {
                case .success(let response):
                    // Check for demo mode (App Store review) - skip payment sheet
                    if response.clientSecret.hasPrefix("demo_") {
                        logger.info("[RidePayment] Demo account detected - bypassing Stripe payment")
                        // Directly confirm payment with demo payment intent
                        self?.confirmPayment(paymentIntentId: response.paymentIntentId)
                        return
                    }

                    self?.paymentIntentClientSecret = response.clientSecret
                    self?.showPaymentSheet = true

                case .failure(let error):
                    self?.showErrorMessage("Unable to set up payment. Please check your payment method and try again.")
                    logger.error("Payment setup error: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Confirm payment completed
    func confirmPayment(paymentIntentId: String) {
        guard let rideId = activeRide?.rideId else { return }

        isLoading = true

        p2pService.confirmRidePayment(rideId: rideId, paymentIntentId: paymentIntentId) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false

                switch result {
                case .success(let confirmation):
                    self?.negotiationMessage = confirmation.message ?? "Payment successful!"

                case .failure(let error):
                    self?.showErrorMessage("Payment could not be confirmed. Please contact support if you were charged.")
                    logger.error("Payment confirmation error: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - Accessibility Options (TNC-12)
enum AccessibilityOption: String, CaseIterable {
    case wheelchair = "wheelchair"
    case serviceAnimal = "service_animal"
    case mobilityStorage = "mobility_storage"
    case audioVisual = "audio_visual"

    var label: String {
        switch self {
        case .wheelchair: return "Wheelchair accessible vehicle"
        case .serviceAnimal: return "Service animal"
        case .mobilityStorage: return "Mobility aid storage"
        case .audioVisual: return "Audio/visual assistance"
        }
    }
}
