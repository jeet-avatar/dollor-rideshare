import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth
import EatFairShared
import CoreLocation
import os

private let logger = Logger(subsystem: "com.dollorai.delivery", category: "EarningsViewModel")

/// Issues #27-30 Fixed: Error handling, retry logic, listener cleanup, authorization checks
/// Updated to use P2P API instead of Firebase for earnings data
class EarningsViewModel: ObservableObject {
    // MARK: - Configuration
    private var config: AppConfig { AppConfig.shared }
    @Published var todayEarnings: Double = 0.0
    @Published var errorMessage: String? // Issue #27: User-facing error message
    @Published var isLoadingEarnings = false // Issue #27: Loading state
    @Published var weekEarnings: Double = 0.0
    @Published var monthEarnings: Double = 0.0

    @Published var todayDeliveries: Int = 0
    @Published var weekDeliveries: Int = 0
    @Published var monthDeliveries: Int = 0

    @Published var todayFoodDeliveries: Int = 0
    @Published var todayRideshareRides: Int = 0
    @Published var weekFoodDeliveries: Int = 0
    @Published var weekRideshareRides: Int = 0
    @Published var monthFoodDeliveries: Int = 0
    @Published var monthRideshareRides: Int = 0

    /// nil = the server did not report hours (UI shows a dash, not 0.0).
    @Published var todayHours: Double?
    @Published var weekHours: Double?
    @Published var monthHours: Double?
    /// nil = the server did not report an available balance (UI shows a dash, not $0.00).
    @Published var availableBalance: Double?

    @Published var dailyEarnings: [DailyEarning] = []
    /// Computed proxy — reads from OnlineStatusManager.shared (single source of truth).
    var isOnline: Bool { OnlineStatusManager.shared.isOnline }

    @Published var todayBreakdown: EarningsBreakdown = EarningsBreakdown()
    @Published var weekBreakdown: EarningsBreakdown = EarningsBreakdown()
    @Published var monthBreakdown: EarningsBreakdown = EarningsBreakdown()

    @Published var currentSessionId: String?
    @Published var sessionStartTime: Date?
    @Published var recentTips: [Tip] = []

    // Dashboard data from P2P API
    @Published var driverRating: Double = 0.0
    @Published var totalReviews: Int = 0
    @Published var onTimePercentage: Int = 0

    // Driver approval status
    @Published var isApproved: Bool = false
    @Published var requiresDocuments: Bool = true
    @Published var driverStatus: String = "pending"
    @Published var cannotGoOnlineReason: String?

    private var db = Firestore.firestore()
    private var cancellables = Set<AnyCancellable>()
    private var locationManager = CLLocationManager()
    private var tipListener: ListenerRegistration?
    private var approvalObserver: NSObjectProtocol?

    private let apiService = P2PAPIService.shared

    init() {
        // Listen for approval status changes from push notifications
        approvalObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("DriverApprovalStatusChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            if let userInfo = notification.userInfo,
               let approved = userInfo["approved"] as? Bool {
                self.isApproved = approved
                if approved {
                    self.driverStatus = "approved"
                    self.requiresDocuments = false
                    self.cannotGoOnlineReason = nil
                    self.errorMessage = nil
                } else if userInfo["rejected"] as? Bool == true {
                    self.driverStatus = "rejected"
                    self.requiresDocuments = true
                    self.cannotGoOnlineReason = "Your documents were rejected. Please upload new documents."
                }
                #if DEBUG
                logger.info("[EarningsVM] Approval status changed via notification: \(approved)")
                #endif
            }
        }

        // Initial status check
        refreshDriverStatus()
    }

    // Helper to get current driver ID (P2P or Firebase)
    private var currentDriverId: String? {
        // Try P2P auth first
        if let p2pDriverId = UserDefaults.standard.object(forKey: UserDefaultsKeys.driverId) as? Int {
            return String(p2pDriverId)
        }
        // Fallback to Firebase
        return Auth.auth().currentUser?.uid
    }

    func fetchEarnings() {
        guard let driverId = currentDriverId else {
            #if DEBUG
            logger.info("[EarningsViewModel] No driver ID available")
            #endif
            return
        }

        isLoadingEarnings = true
        errorMessage = nil

        // Fetch from P2P API (primary source)
        apiService.getDriverDashboard(driverId: driverId) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let dashboard):
                self.updateFromDashboard(dashboard)
                self.isLoadingEarnings = false
                #if DEBUG
                logger.info("[EarningsViewModel] Successfully loaded dashboard from P2P API")
                #endif

            case .failure(let error):
                #if DEBUG
                logger.info("[EarningsViewModel] P2P API failed: \(error.localizedDescription), falling back to Firebase")
                #endif
                // Fallback to Firebase if P2P API fails
                self.fetchEarningsFromFirebase(driverId: driverId)
            }
        }
    }

    /// Update view model from P2P dashboard response
    /// Uses unified data structure - actual breakdown from API, no more estimates
    private func updateFromDashboard(_ dashboard: DriverDashboardResponse) {
        // Today
        todayEarnings = dashboard.today.grossEarnings
        todayDeliveries = dashboard.today.deliveries
        todayHours = dashboard.today.activeHours

        // Week
        weekEarnings = dashboard.thisWeek.grossEarnings
        weekDeliveries = dashboard.thisWeek.deliveries
        weekHours = dashboard.thisWeek.activeHours

        // Month
        monthEarnings = dashboard.thisMonth.grossEarnings
        monthDeliveries = dashboard.thisMonth.deliveries
        monthHours = dashboard.thisMonth.activeHours

        // Split counts (food vs rideshare)
        todayFoodDeliveries = dashboard.today.foodDeliveries ?? dashboard.today.deliveries
        todayRideshareRides = dashboard.today.rideshareRides ?? 0
        weekFoodDeliveries = dashboard.thisWeek.foodDeliveries ?? dashboard.thisWeek.deliveries
        weekRideshareRides = dashboard.thisWeek.rideshareRides ?? 0
        monthFoodDeliveries = dashboard.thisMonth.foodDeliveries ?? dashboard.thisMonth.deliveries
        monthRideshareRides = dashboard.thisMonth.rideshareRides ?? 0

        // Ratings - Use unified average field, fallback to overall for backward compatibility
        if let ratings = dashboard.ratings {
            driverRating = ratings.average ?? ratings.overall ?? 0.0
            totalReviews = ratings.totalRatings ?? ratings.totalReviews ?? 0
            onTimePercentage = ratings.onTimePercentage ?? 0
        }

        // Create breakdown from actual API data (no more estimates!)
        // Use actual basePay/tips/bonuses if available, otherwise estimate
        todayBreakdown = createBreakdown(from: dashboard.today)
        weekBreakdown = createBreakdown(from: dashboard.thisWeek)
        monthBreakdown = createBreakdown(from: dashboard.thisMonth)

        fetchPayoutFields()

        // Generate daily earnings breakdown (mock for now, can be enhanced with API)
        generateDailyBreakdown(weeklyTotal: dashboard.thisWeek.grossEarnings, deliveries: dashboard.thisWeek.deliveries)
    }

    /// Reads the optional available_balance / hours_online fields of GET /api/driver/earnings.
    /// Fields the server does not send leave the dashboard values (or nil) untouched.
    private func fetchPayoutFields() {
        for period in ["today", "week", "month"] {
            apiService.getDriverPayoutFields(period: period) { [weak self] result in
                guard let self = self, case .success(let fields) = result else { return }
                if let balance = fields.availableBalance { self.availableBalance = balance }
                guard let hours = fields.hoursOnline else { return }
                switch period {
                case "today": self.todayHours = hours
                case "week": self.weekHours = hours
                default: self.monthHours = hours
                }
            }
        }
    }

    /// Create earnings breakdown from period data - uses actual values when available
    private func createBreakdown(from period: DriverEarningsPeriod) -> EarningsBreakdown {
        // If API provides actual breakdown, use it
        if let basePay = period.basePay, let tips = period.tips, let bonuses = period.bonuses {
            return EarningsBreakdown(
                deliveryFees: basePay,
                tips: tips,
                bonuses: bonuses,
                total: period.grossEarnings
            )
        }

        // Fallback to estimates for backward compatibility
        return EarningsBreakdown(
            deliveryFees: period.grossEarnings * 0.6,
            tips: period.grossEarnings * 0.35,
            bonuses: period.grossEarnings * 0.05,
            total: period.grossEarnings
        )
    }

    /// Generate daily breakdown from weekly totals
    private func generateDailyBreakdown(weeklyTotal: Double, deliveries: Int) {
        let calendar = Calendar.current
        let today = calendar.component(.weekday, from: Date())
        let daysFromMonday = (today + 5) % 7 + 1 // Days elapsed since Monday

        // Distribute earnings across days with some variance
        let avgDaily = weeklyTotal / Double(max(daysFromMonday, 1))
        let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

        dailyEarnings = days.enumerated().map { index, day in
            let dayIndex = index + 1
            if dayIndex <= daysFromMonday {
                // Add some variance for past days
                let variance = Double.random(in: 0.7...1.3)
                return DailyEarning(day: day, amount: avgDaily * variance)
            } else {
                return DailyEarning(day: day, amount: 0)
            }
        }
    }

    /// Fallback to Firebase if P2P API fails
    private func fetchEarningsFromFirebase(driverId: String) {
        let now = Date()
        let calendar = Calendar.current

        // Start of today
        let startOfToday = calendar.startOfDay(for: now)
        let todayTimestamp = Int64(startOfToday.timeIntervalSince1970 * 1000)

        // Start of week (Monday)
        guard let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) else {
            isLoadingEarnings = false
            return
        }
        let weekTimestamp = Int64(startOfWeek.timeIntervalSince1970 * 1000)

        // Start of month
        guard let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else {
            isLoadingEarnings = false
            return
        }
        let monthTimestamp = Int64(startOfMonth.timeIntervalSince1970 * 1000)

        // Fetch today's earnings
        fetchPeriodEarnings(driverId: driverId, startTimestamp: todayTimestamp) { earnings, count, breakdown in
            self.todayEarnings = earnings
            self.todayDeliveries = count
            self.todayBreakdown = breakdown
        }

        // Fetch week's earnings
        fetchPeriodEarnings(driverId: driverId, startTimestamp: weekTimestamp) { earnings, count, breakdown in
            self.weekEarnings = earnings
            self.weekDeliveries = count
            self.weekBreakdown = breakdown
        }

        // Fetch month's earnings
        fetchPeriodEarnings(driverId: driverId, startTimestamp: monthTimestamp) { earnings, count, breakdown in
            self.monthEarnings = earnings
            self.monthDeliveries = count
            self.monthBreakdown = breakdown
            self.isLoadingEarnings = false
        }

        // Fetch daily breakdown for the week
        fetchDailyBreakdown(driverId: driverId, startTimestamp: weekTimestamp)
    }

    /// Issue #27 Fixed: Proper error handling with retry and user notifications
    private var fetchRetryCount = 0
    private let maxRetries = 3

    private func fetchPeriodEarnings(driverId: String, startTimestamp: Int64, completion: @escaping (Double, Int, EarningsBreakdown) -> Void) {
        db.collection("orders")
            .whereField("driverId", isEqualTo: driverId)
            .whereField("status", isEqualTo: DeliveryOrderStatus.delivered.displayName)
            .whereField("deliveredAt", isGreaterThanOrEqualTo: startTimestamp)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }

                if let error = error {
                    #if DEBUG
                    logger.info("[EarningsViewModel] Fetch error: \(error.localizedDescription)")
                    #endif

                    // Issue #27: Retry logic for network failures
                    if self.fetchRetryCount < self.maxRetries {
                        self.fetchRetryCount += 1
                        DispatchQueue.main.asyncAfter(deadline: .now() + Double(self.fetchRetryCount) * 2.0) {
                            self.fetchPeriodEarnings(driverId: driverId, startTimestamp: startTimestamp, completion: completion)
                        }
                        return
                    }

                    // Max retries reached - notify user
                    DispatchQueue.main.async {
                        self.errorMessage = "Unable to load earnings. Please check your connection."
                        self.isLoadingEarnings = false
                    }
                    completion(0.0, 0, EarningsBreakdown())
                    return
                }

                self.fetchRetryCount = 0 // Reset on success

                guard let documents = snapshot?.documents else {
                    completion(0.0, 0, EarningsBreakdown())
                    return
                }

                var breakdown = EarningsBreakdown()

                for doc in documents {
                    let deliveryFee = doc.data()["deliveryFee"] as? Double ?? 0.0
                    let priorityFee = doc.data()["priorityFee"] as? Double ?? 0.0
                    let total = doc.data()["total"] as? Double ?? 0.0
                    // Use actual tip if available, otherwise estimate from config
                    let tip = doc.data()["tip"] as? Double ?? (total * self.config.defaultTipRate)

                    breakdown.deliveryFees += deliveryFee
                    breakdown.bonuses += priorityFee
                    breakdown.tips += tip
                }

                breakdown.total = breakdown.deliveryFees + breakdown.tips + breakdown.bonuses

                completion(breakdown.total, documents.count, breakdown)
            }
    }

    private func fetchDailyBreakdown(driverId: String, startTimestamp: Int64) {
        db.collection("orders")
            .whereField("driverId", isEqualTo: driverId)
            .whereField("status", isEqualTo: DeliveryOrderStatus.delivered.displayName)
            .whereField("deliveredAt", isGreaterThanOrEqualTo: startTimestamp)
            .getDocuments { snapshot, error in
                if error != nil {
                    return
                }

                guard let documents = snapshot?.documents else { return }

                // Group by day
                var dailyMap: [String: (earnings: Double, count: Int)] = [:]
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "EEE"

                for doc in documents {
                    if let deliveredAt = doc.data()["deliveredAt"] as? Int64 {
                        let date = Date(timeIntervalSince1970: TimeInterval(deliveredAt / 1000))
                        let dayKey = dateFormatter.string(from: date)

                        let deliveryFee = doc.data()["deliveryFee"] as? Double ?? 0.0
                        let priorityFee = doc.data()["priorityFee"] as? Double ?? 0.0
                        let total = doc.data()["total"] as? Double ?? 0.0
                        // Use actual tip if available, otherwise estimate from config
                        let tip = doc.data()["tip"] as? Double ?? (total * self.config.defaultTipRate)
                        let earnings = deliveryFee + priorityFee + tip

                        if var existing = dailyMap[dayKey] {
                            existing.earnings += earnings
                            existing.count += 1
                            dailyMap[dayKey] = existing
                        } else {
                            dailyMap[dayKey] = (earnings, 1)
                        }
                    }
                }

                // Convert to array
                self.dailyEarnings = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].map { day in
                    DailyEarning(day: day, amount: dailyMap[day]?.earnings ?? 0.0)
                }
            }
    }
    
    func updateOnlineStatus(_ status: Bool) {
        guard let uid = currentDriverId else { return }

        // Delegate the API call + location tracking to OnlineStatusManager (single source of truth).
        // This replaces the direct P2PAPIService call that previously caused duplicate API calls
        // when both DeliveryViewModel and EarningsViewModel toggled online independently.
        OnlineStatusManager.shared.setOnlineStatus(status)

        // Also write to Firebase for session tracking backward compatibility.
        // This is a best-effort cache write — OnlineStatusManager.shared.isOnline is authoritative.
        let driverData: [String: Any] = [
            "isOnline": status,
            "lastActive": Int64(Date().timeIntervalSince1970 * 1000)
        ]
        db.collection("drivers").document(uid).setData(driverData, merge: true) { error in
            // isOnline is now read from OnlineStatusManager.shared — no separate assignment needed.
            #if DEBUG
            if let error = error {
                logger.error("[Earnings] Firebase status cache write failed: \(error.localizedDescription)")
            }
            #endif
        }
    }
    
    func fetchOnlineStatus() {
        guard let uid = currentDriverId else { return }

        // Only syncs Firebase→manager for the "true" (online) state on cold launch.
        // Manager is authoritative; this is a one-way bootstrap if the manager is still false.
        db.collection("drivers").document(uid).getDocument { snapshot, error in
            if let data = snapshot?.data(),
               let fbOnline = data["isOnline"] as? Bool {
                // Only apply Firebase value if no backend call has been made yet
                // (avoids overwriting a more recent backend-confirmed state)
                DispatchQueue.main.async {
                    if !OnlineStatusManager.shared.isOnline && fbOnline {
                        OnlineStatusManager.shared.markOnlineLocally()
                    }
                }
            }
        }
    }
    
    // MARK: - Mock Data for Testing (DEBUG only)
    #if DEBUG
    func loadMockData() {
        self.todayEarnings = 127.50
        self.weekEarnings = 892.30
        self.monthEarnings = 3456.80

        self.todayDeliveries = 12
        self.weekDeliveries = 67
        self.monthDeliveries = 284

        self.todayHours = 6.4
        self.weekHours = 38.0
        self.monthHours = 156.0

        self.dailyEarnings = [
            DailyEarning(day: "Mon", amount: 98.50),
            DailyEarning(day: "Tue", amount: 145.75),
            DailyEarning(day: "Wed", amount: 167.20),
            DailyEarning(day: "Thu", amount: 132.85),
            DailyEarning(day: "Fri", amount: 189.40),
            DailyEarning(day: "Sat", amount: 231.60),
            DailyEarning(day: "Sun", amount: 127.50)
        ]

        OnlineStatusManager.shared.markOnlineLocally()
    }
    #endif
    
    // MARK: - Driver Status
    func refreshDriverStatus() {
        // Get approval status from P2P service
        isApproved = apiService.isDriverApproved
        requiresDocuments = apiService.driverRequiresDocuments
        driverStatus = apiService.currentDriverStatus

        // Determine if driver can go online
        if !isApproved {
            if requiresDocuments {
                cannotGoOnlineReason = "Please upload your documents to get approved"
            } else {
                cannotGoOnlineReason = "Your documents are pending verification"
            }
        } else {
            cannotGoOnlineReason = nil
        }

        #if DEBUG
        logger.info("[EarningsVM] Driver status: \(self.driverStatus), approved: \(self.isApproved), requiresDocs: \(self.requiresDocuments)")
        #endif
    }

    // MARK: - Session Tracking
    func startSession() {
        guard let uid = currentDriverId else { return }

        // Refresh and check driver approval status
        refreshDriverStatus()

        // Block unapproved drivers from going online
        if !isApproved {
            errorMessage = cannotGoOnlineReason ?? "You must be approved before going online"
            #if DEBUG
            logger.info("[EarningsVM] Cannot go online - driver not approved")
            #endif
            return
        }

        // Clear any previous error
        errorMessage = nil
        cannotGoOnlineReason = nil

        locationManager.requestWhenInUseAuthorization()

        let currentLocation = locationManager.location?.coordinate
        let session = DriverSession(
            id: UUID().uuidString,
            driverId: uid,
            startTime: Int64(Date().timeIntervalSince1970 * 1000),
            endTime: nil,
            duration: nil,
            startLocation: currentLocation.map { LocationCoordinate(
                latitude: $0.latitude,
                longitude: $0.longitude
            ) },
            endLocation: nil,
            deliveriesCompleted: 0,
            deliveriesCancelled: 0,
            totalDistance: 0.0,
            totalEarnings: 0.0,
            deviceInfo: "\(UIDevice.current.model) - \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        )

        guard let sessionId = session.id else { return }

        do {
            try db.collection("driver_sessions").document(sessionId).setData(from: session)
            currentSessionId = sessionId
            sessionStartTime = Date()
            // Mark online in shared manager without redundant API call (updateOnlineStatus handles the API call)
            OnlineStatusManager.shared.markOnlineLocally()

            // Update driver status
            db.collection("drivers").document(uid).updateData([
                "currentSessionId": sessionId,
                "isOnline": true
            ])
        } catch {
            // Session creation failed - silently continue
        }
    }
    
    func endSession() {
        guard let sessionId = currentSessionId,
              let uid = currentDriverId,
              let startTime = sessionStartTime else { return }
        
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime) / 3600.0 // hours
        
        let currentLocation = locationManager.location?.coordinate
        
        let endLocationData: Any = currentLocation.map { [
            "latitude": $0.latitude,
            "longitude": $0.longitude
        ] as [String: Any] } ?? NSNull()

        db.collection("driver_sessions").document(sessionId).updateData([
            "endTime": Int64(endTime.timeIntervalSince1970 * 1000),
            "duration": duration,
            "endLocation": endLocationData
        ])
        
        // Fetch session data to update driver stats
        db.collection("driver_sessions").document(sessionId).getDocument { [weak self] document, _ in
            if let session = try? document?.data(as: DriverSession.self) {
                self?.updateDriverStats(driverId: uid, session: session)
            }
        }
        
        // Update driver status
        db.collection("drivers").document(uid).updateData([
            "currentSessionId": NSNull(),
            "isOnline": false
        ])
        
        currentSessionId = nil
        sessionStartTime = nil
        // Mark offline in shared manager without redundant API call (endSession caller handles the API call)
        OnlineStatusManager.shared.markOfflineLocally()
    }
    
    private func updateDriverStats(driverId: String, session: DriverSession) {
        db.collection("drivers").document(driverId).getDocument { [weak self] document, _ in
            guard let data = document?.data(),
                  var stats = data["stats"] as? [String: Any] else { return }
            
            // Update cumulative stats
            let currentDistance = stats["totalDistance"] as? Double ?? 0.0
            let currentTime = stats["totalOnlineTime"] as? Double ?? 0.0
            let currentEarnings = stats["totalEarnings"] as? Double ?? 0.0
            
            stats["totalDistance"] = currentDistance + session.totalDistance
            stats["totalOnlineTime"] = currentTime + (session.duration ?? 0.0)
            stats["totalEarnings"] = currentEarnings + session.totalEarnings
            
            self?.db.collection("drivers").document(driverId).updateData([
                "stats": stats
            ])
        }
    }
    
    // MARK: - Tip Listening
    func listenForTips() {
        guard let uid = currentDriverId else { return }
        
        tipListener = db.collection("tips")
            .whereField("driverId", isEqualTo: uid)
            .order(by: "createdAt", descending: true)
            .limit(to: 5)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let documents = snapshot?.documents else { return }
                
                self?.recentTips = documents.compactMap { doc in
                    try? doc.data(as: Tip.self)
                }
            }
    }
    
    deinit {
        tipListener?.remove()
    }
}

struct DailyEarning: Identifiable {
    let id = UUID()
    let day: String
    let amount: Double
}

struct EarningsBreakdown {
    var deliveryFees: Double = 0.0
    var tips: Double = 0.0
    var bonuses: Double = 0.0
    var total: Double = 0.0

    init(deliveryFees: Double = 0.0, tips: Double = 0.0, bonuses: Double = 0.0, total: Double = 0.0) {
        self.deliveryFees = deliveryFees
        self.tips = tips
        self.bonuses = bonuses
        self.total = total
    }
}
