import Foundation
import CoreLocation
import Combine
import EatFairShared
import Network
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "eatffairdelivery", category: "LocationManager")

/// LocationManager handles real-time GPS tracking for delivery drivers
/// Publishes location updates and syncs with P2P backend (PostgreSQL)
/// Issues #14-18, #43 Fixed: Timer cleanup, weak self, location permissions, network checks
class LocationManager: NSObject, ObservableObject {
    static let shared = LocationManager()

    // MARK: - Published Properties
    @Published var currentLocation: CLLocation?
    @Published var currentCoordinate: CLLocationCoordinate2D?
    @Published var heading: CLHeading?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isTracking = false
    @Published var locationError: String?
    @Published var speed: CLLocationSpeed = 0 // m/s
    @Published var distanceTraveled: CLLocationDistance = 0
    @Published var isNetworkAvailable = true // Issue #43: Network reachability

    // MARK: - Private Properties
    private let locationManager = CLLocationManager()
    private let p2pService = P2PAPIService.shared
    private var lastLocation: CLLocation?
    private var locationUpdateTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // Issue #43: Network monitor for reachability
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "com.dollor.driver.network")

    // Issue #18: Track consecutive P2P update failures
    private var consecutiveP2PFailures = 0
    private let maxConsecutiveFailures = 5

    /// True between startTracking() and stopTracking(), even while the permission prompt is showing.
    private var wantsTracking = false

    // Current active order ID for location updates
    var activeOrderId: Int?

    // Location retry queue for failed updates
    private var pendingLocationUpdates: [(orderId: Int?, latitude: Double, longitude: Double, timestamp: Date)] = []
    private let maxPendingUpdates = 50 // Prevent memory issues
    private var retryTimer: Timer?

    // MARK: - Configuration (Issue #17: Could be moved to AppConfig)
    private let minimumUpdateDistance: CLLocationDistance = 10 // meters
    private let p2pUpdateInterval: TimeInterval = 5 // seconds (update driver location to P2P backend)

    override init() {
        super.init()
        setupLocationManager()
        setupNetworkMonitor()
    }

    /// Issue #15 Fixed: Guarantee timer invalidation on deinit
    deinit {
        stopP2PUpdates()
        retryTimer?.invalidate()
        retryTimer = nil
        networkMonitor.cancel()
        #if DEBUG
        logger.info("[LocationManager] Deinitialized, timers cancelled")
        #endif
    }

    /// Issue #43: Setup network reachability monitoring
    private func setupNetworkMonitor() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isNetworkAvailable = path.status == .satisfied
                #if DEBUG
                logger.info("[LocationManager] Network status: \(path.status == .satisfied ? "available" : "unavailable")")
                #endif
            }
        }
        networkMonitor.start(queue: networkQueue)
    }

    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = minimumUpdateDistance
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = true
        locationManager.activityType = .automotiveNavigation

        authorizationStatus = locationManager.authorizationStatus
    }

    // MARK: - Public Methods

    /// Request location permissions
    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    /// Asks for "Always" only when a trip actually starts, so riders keep seeing the driver's position if the
    /// driver switches apps or locks the phone mid-trip. Never called at launch or when going online.
    func requestAlwaysPermissionForActiveRide() {
        guard authorizationStatus == .authorizedWhenInUse else { return }
        locationManager.requestAlwaysAuthorization()
    }

    /// Start tracking driver location
    func startTracking() {
        wantsTracking = true
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            // Tracking resumes in locationManagerDidChangeAuthorization once the user answers the prompt.
            requestPermission()
            return
        }

        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
        isTracking = true
        distanceTraveled = 0

        // Start periodic P2P backend updates
        startP2PUpdates()
    }

    /// Stop tracking driver location
    func stopTracking() {
        wantsTracking = false
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        isTracking = false
        stopP2PUpdates()
    }

    /// Issue #16 Fixed: Get current location once with permission check
    func getCurrentLocation() {
        // Check authorization before requesting location
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.requestLocation()
        case .notDetermined:
            requestPermission()
        case .denied, .restricted:
            locationError = "Location access denied. Please enable in Settings."
        @unknown default:
            requestPermission()
        }
    }

    /// Calculate distance from current location to a coordinate
    func distanceTo(latitude: Double, longitude: Double) -> CLLocationDistance? {
        guard let current = currentLocation else { return nil }
        let destination = CLLocation(latitude: latitude, longitude: longitude)
        return current.distance(from: destination)
    }

    /// Calculate ETA to destination based on current speed
    func etaTo(latitude: Double, longitude: Double) -> TimeInterval? {
        guard let distance = distanceTo(latitude: latitude, longitude: longitude) else { return nil }
        let averageSpeed = speed > 0 ? speed : 8.0 // Default 8 m/s (~18 mph) if stationary
        return distance / averageSpeed
    }

    /// Format distance for display
    func formatDistance(_ meters: CLLocationDistance) -> String {
        if meters < 1000 {
            return String(format: "%.0f m", meters)
        } else {
            let miles = meters / 1609.34
            return String(format: "%.1f mi", miles)
        }
    }

    /// Format ETA for display
    func formatETA(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 1 {
            return "< 1 min"
        } else if minutes < 60 {
            return "\(minutes) min"
        } else {
            let hours = minutes / 60
            let remainingMins = minutes % 60
            return "\(hours)h \(remainingMins)m"
        }
    }

    // MARK: - P2P Backend Sync

    private func startP2PUpdates() {
        stopP2PUpdates() // Clear any existing timer
        consecutiveP2PFailures = 0 // Reset failure counter

        // Issue #14 Fixed: Proper weak self handling with guard
        locationUpdateTimer = Timer.scheduledTimer(withTimeInterval: p2pUpdateInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.updateLocationInP2P()
        }
    }

    private func stopP2PUpdates() {
        locationUpdateTimer?.invalidate()
        locationUpdateTimer = nil
    }

    private func updateLocationInP2P() {
        // Issue #43: Check network availability before making API call
        guard isNetworkAvailable else {
            #if DEBUG
            logger.info("[LocationManager] Skipping P2P update - no network")
            #endif
            return
        }

        guard let location = currentLocation else { return }

        // Issue #18 Fixed: Proper error handling for location updates
        p2pService.updateDriverLocation(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        ) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success:
                self.consecutiveP2PFailures = 0
            case .failure(let error):
                self.consecutiveP2PFailures += 1
                #if DEBUG
                logger.info("[LocationManager] P2P location update failed (\(self.consecutiveP2PFailures)/\(self.maxConsecutiveFailures)): \(error.localizedDescription)")
                #endif

                // Notify user after multiple consecutive failures
                if self.consecutiveP2PFailures >= self.maxConsecutiveFailures {
                    DispatchQueue.main.async {
                        self.locationError = "Unable to sync location with server. Please check your connection."
                    }
                }
            }
        }

        // If there's an active order, update that order's driver location
        if let orderId = activeOrderId {
            updateOrderLocationInP2P(orderId: orderId)
        }
    }

    /// Update location for a specific order (for live tracking by customer)
    func updateOrderLocation(orderId: String) {
        guard let orderIdInt = Int(orderId) else { return }
        updateOrderLocationInP2P(orderId: orderIdInt)
    }

    /// Update location for a specific order using P2P API with retry queue
    private func updateOrderLocationInP2P(orderId: Int) {
        guard let location = currentLocation else { return }

        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude

        p2pService.updateDriverLocation(
            orderId: orderId,
            latitude: latitude,
            longitude: longitude
        ) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success:
                // Success - no action needed
                break
            case .failure:
                // Add to retry queue
                self.queueFailedLocationUpdate(orderId: orderId, latitude: latitude, longitude: longitude)
            }
        }
    }

    // MARK: - Location Retry Queue

    /// Add failed location update to retry queue
    private func queueFailedLocationUpdate(orderId: Int?, latitude: Double, longitude: Double) {
        // Prevent queue from growing too large
        if pendingLocationUpdates.count >= maxPendingUpdates {
            pendingLocationUpdates.removeFirst()
        }

        pendingLocationUpdates.append((orderId: orderId, latitude: latitude, longitude: longitude, timestamp: Date()))

        // Start retry timer if not already running
        startRetryTimerIfNeeded()

        #if DEBUG
        logger.info("[LocationManager] Queued failed location update. Queue size: \(self.pendingLocationUpdates.count)")
        #endif
    }

    /// Start retry timer if there are pending updates
    private func startRetryTimerIfNeeded() {
        guard retryTimer == nil, !pendingLocationUpdates.isEmpty else { return }

        retryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.processPendingLocationUpdates()
        }
    }

    /// Process pending location updates when network is available
    private func processPendingLocationUpdates() {
        guard isNetworkAvailable, !pendingLocationUpdates.isEmpty else {
            // Stop timer if no pending updates
            if pendingLocationUpdates.isEmpty {
                retryTimer?.invalidate()
                retryTimer = nil
            }
            return
        }

        #if DEBUG
        logger.info("[LocationManager] Processing \(self.pendingLocationUpdates.count) pending location updates")
        #endif

        // Remove stale updates (older than 5 minutes)
        let fiveMinutesAgo = Date().addingTimeInterval(-300)
        pendingLocationUpdates.removeAll { $0.timestamp < fiveMinutesAgo }

        // Process remaining updates
        let updatesToProcess = pendingLocationUpdates
        pendingLocationUpdates.removeAll()

        for update in updatesToProcess {
            if let orderId = update.orderId {
                p2pService.updateDriverLocation(
                    orderId: orderId,
                    latitude: update.latitude,
                    longitude: update.longitude
                ) { [weak self] result in
                    if case .failure = result {
                        // Re-queue if still failing
                        self?.queueFailedLocationUpdate(orderId: orderId, latitude: update.latitude, longitude: update.longitude)
                    }
                }
            } else {
                p2pService.updateDriverLocation(
                    latitude: update.latitude,
                    longitude: update.longitude
                ) { _ in }
            }
        }

        // Stop timer if queue is empty
        if pendingLocationUpdates.isEmpty {
            retryTimer?.invalidate()
            retryTimer = nil
        }
    }

    /// Start tracking for a specific delivery order
    func startDeliveryTracking(orderId: Int) {
        activeOrderId = orderId
        startTracking()
    }

    /// Stop tracking for delivery (when order is complete)
    func stopDeliveryTracking() {
        activeOrderId = nil
        stopTracking()
    }
}

// MARK: - CLLocationManagerDelegate
extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        // Filter out inaccurate readings
        guard location.horizontalAccuracy >= 0 && location.horizontalAccuracy < 100 else { return }

        // Calculate distance traveled
        if let last = lastLocation {
            let distance = location.distance(from: last)
            if distance > 0 {
                distanceTraveled += distance
            }
        }

        lastLocation = location
        currentLocation = location
        currentCoordinate = location.coordinate
        speed = max(location.speed, 0)

        // Update P2P for active orders
        if isTracking {
            updateLocationInP2P()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        heading = newHeading
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationError = error.localizedDescription
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if isTracking {
                locationManager.startUpdatingLocation()
            } else if wantsTracking {
                startTracking()
            }
        case .denied, .restricted:
            locationError = "Location access denied. Please enable in Settings."
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        authorizationStatus = status
    }
}

// MARK: - Location Extensions
// Retroactive conformance - CLLocationCoordinate2D needs Equatable for SwiftUI's onChange
extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        return lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

extension CLLocationCoordinate2D {
    /// Returns true if coordinates are valid (not 0,0)
    var isValid: Bool {
        return latitude != 0 && longitude != 0
    }

    /// Default fallback coordinates from centralized config
    /// Only use when user location is unavailable
    static var defaultFallback: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: MapConfig.defaultLatitude,
            longitude: MapConfig.defaultLongitude
        )
    }
}
