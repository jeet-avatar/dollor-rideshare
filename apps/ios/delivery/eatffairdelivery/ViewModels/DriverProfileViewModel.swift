import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import EatFairShared
import os

private let logger = Logger(subsystem: "com.dollorai.delivery", category: "DriverProfileViewModel")

/// Issues #31-33 Fixed: Profile save error handling, input validation, document upload retry
@MainActor
class DriverProfileViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var driver: Driver?
    @Published var isLoading = false
    @Published var isEditing = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var isLoadingStripeLink = false
    /// Web page shown in the in-app browser sheet (payout setup, terms, privacy)
    @Published var webURL: URL?

    // MARK: - Personal Info
    @Published var name = ""
    @Published var email = ""
    @Published var phone = ""
    @Published var dateOfBirth: Date?

    // MARK: - Address
    @Published var street = ""
    @Published var city = ""
    @Published var state = ""
    @Published var zipCode = ""

    // MARK: - Driver's License
    @Published var licenseNumber = ""
    @Published var licenseState = ""
    @Published var licenseClass = "C"
    @Published var licenseExpiration: Date?
    @Published var licenseFrontUrl: String?
    @Published var licenseBackUrl: String?

    // MARK: - Vehicle
    @Published var vehicleMake = ""
    @Published var vehicleModel = ""
    @Published var vehicleYear = Calendar.current.component(.year, from: Date())
    @Published var vehicleColor = ""
    @Published var vehicleType = "Sedan"
    @Published var licensePlate = ""
    @Published var vehiclePhotoUrl: String?

    // MARK: - Insurance
    @Published var insuranceProvider = ""
    @Published var insurancePolicyNumber = ""
    @Published var insuranceExpiration: Date?
    @Published var insuranceCardUrl: String?

    // MARK: - Bank Account
    @Published var bankName = ""
    @Published var accountHolderName = ""
    @Published var accountType = "checking"

    // MARK: - Preferences
    @Published var notificationsEnabled = true
    @Published var soundEnabled = true
    @Published var maxDeliveryDistance: Double = AppConfig.shared.maxDeliveryDistanceMiles

    // MARK: - Expiration Alerts
    @Published var expirationAlerts: [ExpirationAlert] = []

    // MARK: - Documents from P2P API
    @Published var documentsResponse: DriverDocumentsResponse?
    /// Document type currently being uploaded from the profile (nil when idle)
    @Published var uploadingDocumentType: String?
    @Published var documentUploadNotice: String?
    @Published var isLoadingDocuments = false

    struct ExpirationAlert: Identifiable {
        let id = UUID()
        let type: DocumentType
        let documentName: String
        let expirationDate: Date
        let daysRemaining: Int
        let isExpired: Bool
        let isUrgent: Bool // < 30 days

        var icon: String {
            switch type {
            case .license: return "car.fill"
            case .insurance: return "shield.fill"
            case .registration: return "doc.text.fill"
            }
        }

        var color: Color {
            if isExpired { return .red }
            if isUrgent { return .orange }
            return .yellow
        }

        var message: String {
            if isExpired {
                return "\(documentName) has expired"
            } else if daysRemaining <= 7 {
                return "\(documentName) expires in \(daysRemaining) day\(daysRemaining == 1 ? "" : "s")"
            } else {
                return "\(documentName) expires in \(daysRemaining) days"
            }
        }
    }

    enum DocumentType {
        case license, insurance, registration
    }

    // MARK: - Private Properties
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    private let p2pService = P2PAPIService.shared

    // Issue #33: Retry configuration for document uploads
    private let maxUploadRetries = 3
    private var uploadRetryCount = 0

    // MARK: - Issue #32: Input Validation

    /// Validates phone number format (E.164 or US format)
    var isPhoneValid: Bool {
        guard !phone.isEmpty else { return true } // Empty is valid (optional)
        let digitsOnly = phone.filter { $0.isNumber }
        return digitsOnly.count >= 10 && digitsOnly.count <= 15
    }

    /// Returns validation error messages
    var validationErrors: [String] {
        var errors: [String] = []
        if !phone.isEmpty && !isPhoneValid {
            errors.append("Phone number must be 10-15 digits")
        }
        return errors
    }

    /// Check if all inputs are valid before saving
    var canSaveProfile: Bool {
        return isPhoneValid
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

    // MARK: - Fetch Profile
    func fetchProfile() {
        // Use P2P API - this is the only backend we use
        guard let driverId = UserDefaults.standard.object(forKey: UserDefaultsKeys.driverId) as? Int else {
            errorMessage = "Not logged in. Please login again."
            showError = true
            return
        }

        fetchP2PProfile(driverId: driverId)
        fetchDriverDocuments(driverId: driverId)
    }

    // MARK: - Fetch Driver Documents
    func fetchDriverDocuments(driverId: Int) {
        isLoadingDocuments = true

        p2pService.getDriverDocuments(driverId: driverId) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoadingDocuments = false

                switch result {
                case .success(let response):
                    self?.documentsResponse = response
                    // Update expiration alerts from document data
                    self?.checkDocumentExpirationsFromAPI(documents: response.documents)
                case .failure(let error):
                    #if DEBUG
                    logger.info("[DriverProfileViewModel] Failed to fetch documents: \(error.localizedDescription)")
                    #endif
                    // Don't show error - documents may not be uploaded yet
                }
            }
        }
    }

    /// Check document expirations using data from P2P API
    private func checkDocumentExpirationsFromAPI(documents: [DriverDocument]) {
        var alerts: [ExpirationAlert] = []
        let now = Date()
        let alertThreshold = 60 // days

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]

        for doc in documents {
            guard let expiryString = doc.expiryDate,
                  let expiryDate = dateFormatter.date(from: expiryString) else {
                continue
            }

            let daysRemaining = Calendar.current.dateComponents([.day], from: now, to: expiryDate).day ?? 0

            if daysRemaining <= alertThreshold {
                let docType: DocumentType
                switch doc.documentType {
                case "license_front", "license_back", "drivers_license":
                    docType = .license
                case "insurance", "insurance_card":
                    docType = .insurance
                default:
                    docType = .registration
                }

                alerts.append(ExpirationAlert(
                    type: docType,
                    documentName: DriverDocumentType(rawValue: doc.documentType)?.displayName ?? doc.documentType,
                    expirationDate: expiryDate,
                    daysRemaining: max(0, daysRemaining),
                    isExpired: daysRemaining <= 0,
                    isUrgent: daysRemaining <= 30
                ))
            }
        }

        // Sort by urgency (expired first, then by days remaining)
        expirationAlerts = alerts.sorted { first, second in
            if first.isExpired && !second.isExpired { return true }
            if !first.isExpired && second.isExpired { return false }
            return first.daysRemaining < second.daysRemaining
        }
    }

    /// Get document by type from API response
    func document(ofType type: String) -> DriverDocument? {
        return documentsResponse?.documents.first { $0.documentType == type }
    }

    /// Check if specific document is verified
    func isDocumentVerified(_ type: String) -> Bool {
        return document(ofType: type)?.verified ?? false
    }

    /// Get verification status for document type
    func documentStatus(_ type: String) -> String {
        return document(ofType: type)?.status ?? "not_uploaded"
    }

    // MARK: - Fetch P2P Profile
    private func fetchP2PProfile(driverId: Int) {
        isLoading = true

        p2pService.getDriverProfile(driverId: driverId) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false

                switch result {
                case .success(let driverData):
                    self?.parseP2PDriverData(driverData)
                case .failure(let error):
                    let errorMsg = error.localizedDescription.lowercased()
                    if errorMsg.contains("network") || errorMsg.contains("connection") {
                        self?.errorMessage = "Unable to connect. Please check your internet connection."
                    } else if errorMsg.contains("unauthorized") || errorMsg.contains("token") {
                        self?.errorMessage = "Session expired. Please log in again."
                    } else {
                        self?.errorMessage = "Unable to load profile. Please try again."
                    }
                    self?.showError = true
                    logger.error("Fetch profile error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func parseP2PDriverData(_ data: [String: Any]) {
        // Personal Info from P2P response
        name = data["name"] as? String ?? data["full_name"] as? String ?? ""
        email = data["email"] as? String ?? ""
        phone = data["phone"] as? String ?? data["phone_number"] as? String ?? ""

        // Date of birth
        if let dobString = data["date_of_birth"] as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
            dateOfBirth = formatter.date(from: dobString)
        }

        // Address fields
        street = data["street"] as? String ?? ""
        city = data["city"] as? String ?? ""
        state = data["state"] as? String ?? ""
        zipCode = data["zip_code"] as? String ?? ""

        // Vehicle fields
        vehicleType = data["vehicle_type"] as? String ?? "Car"
        vehicleMake = data["vehicle_make"] as? String ?? ""
        vehicleModel = data["vehicle_model"] as? String ?? ""
        vehicleYear = data["vehicle_year"] as? Int ?? Calendar.current.component(.year, from: Date())
        vehicleColor = data["vehicle_color"] as? String ?? ""
        licensePlate = data["license_plate"] as? String ?? ""

        // License & Insurance
        licenseNumber = data["license_number"] as? String ?? ""
        if let licExpStr = data["drivers_license_expiry"] as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
            licenseExpiration = formatter.date(from: licExpStr)
        }
        if let insExpStr = data["insurance_expiry"] as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
            insuranceExpiration = formatter.date(from: insExpStr)
        }

        // Approval status
        let approvalStatus = data["status"] as? String ?? data["approval_status"] as? String ?? "pending"
        let isApproved = approvalStatus == "approved" || approvalStatus == "active"

        // Build a basic driver object for P2P data
        driver = Driver(
            id: String(data["id"] as? Int ?? 0),
            name: name,
            email: email,
            phone: phone,
            profileImageUrl: data["profile_image"] as? String,
            dateOfBirth: nil,
            address: nil,
            driversLicense: nil,
            vehicle: nil,
            vehicleType: data["vehicle_type"] as? String ?? "Car",
            licensePlate: data["license_plate"] as? String ?? "",
            insurance: nil,
            bankAccount: nil,
            isOnline: data["is_online"] as? Bool ?? false,
            isApproved: isApproved,
            approvalStatus: approvalStatus,
            currentLatitude: data["latitude"] as? Double ?? 0.0,
            currentLongitude: data["longitude"] as? Double ?? 0.0,
            stats: DriverStats(
                rating: data["rating"] as? Double ?? 5.0,
                totalDeliveries: data["total_deliveries"] as? Int ?? 0,
                completedDeliveries: data["completed_deliveries"] as? Int ?? 0,
                cancelledDeliveries: 0,
                totalEarnings: data["total_earnings"] as? Double ?? 0.0,
                totalDistance: 0.0,
                totalOnlineTime: 0.0,
                acceptanceRate: 100.0,
                completionRate: 100.0,
                onTimeRate: 100.0,
                weeklyDeliveries: 0,
                weeklyEarnings: 0.0,
                weeklyHours: 0.0,
                weeklyDistance: 0.0
            )
        )
    }

    private func parseDriverData(_ data: [String: Any]) {
        // Personal Info
        name = data["name"] as? String ?? ""
        email = data["email"] as? String ?? Auth.auth().currentUser?.email ?? ""
        phone = data["phone"] as? String ?? ""

        if let dobTimestamp = data["dateOfBirth"] as? Int64 {
            dateOfBirth = Date(timeIntervalSince1970: TimeInterval(dobTimestamp / 1000))
        }

        // Address
        if let addressData = data["address"] as? [String: Any] {
            street = addressData["street"] as? String ?? ""
            city = addressData["city"] as? String ?? ""
            state = addressData["state"] as? String ?? ""
            zipCode = addressData["zipCode"] as? String ?? ""
        }

        // Driver's License
        if let licenseData = data["driversLicense"] as? [String: Any] {
            licenseNumber = licenseData["licenseNumber"] as? String ?? ""
            licenseState = licenseData["state"] as? String ?? ""
            licenseClass = licenseData["licenseClass"] as? String ?? "C"
            licenseFrontUrl = licenseData["frontImageUrl"] as? String
            licenseBackUrl = licenseData["backImageUrl"] as? String

            if let expTimestamp = licenseData["expirationDate"] as? Int64 {
                licenseExpiration = Date(timeIntervalSince1970: TimeInterval(expTimestamp / 1000))
            }
        }

        // Vehicle Info
        if let vehicleData = data["vehicle"] as? [String: Any] {
            vehicleMake = vehicleData["make"] as? String ?? ""
            vehicleModel = vehicleData["model"] as? String ?? ""
            vehicleYear = vehicleData["year"] as? Int ?? Calendar.current.component(.year, from: Date())
            vehicleColor = vehicleData["color"] as? String ?? ""
            vehicleType = vehicleData["vehicleType"] as? String ?? "Sedan"
            licensePlate = vehicleData["licensePlate"] as? String ?? ""
            vehiclePhotoUrl = vehicleData["vehiclePhotoUrl"] as? String
        } else {
            // Fallback to top-level fields for backward compatibility
            vehicleType = data["vehicleType"] as? String ?? "Car"
            licensePlate = data["licensePlate"] as? String ?? ""
        }

        // Insurance
        if let insuranceData = data["insurance"] as? [String: Any] {
            insuranceProvider = insuranceData["provider"] as? String ?? ""
            insurancePolicyNumber = insuranceData["policyNumber"] as? String ?? ""
            insuranceCardUrl = insuranceData["insuranceCardImageUrl"] as? String

            if let expTimestamp = insuranceData["expirationDate"] as? Int64 {
                insuranceExpiration = Date(timeIntervalSince1970: TimeInterval(expTimestamp / 1000))
            }
        }

        // Bank Account — try profile response first, fall back to login cache in UserDefaults
        if let bankData = data["bankAccount"] as? [String: Any] {
            bankName = bankData["bankName"] as? String ?? ""
            accountHolderName = bankData["accountHolderName"] as? String ?? ""
            accountType = bankData["accountType"] as? String ?? "checking"
        } else {
            // Fallback: login response stored bank data in UserDefaults
            let cached = UserDefaults.standard.string(forKey: "driver_bank_name") ?? ""
            if !cached.isEmpty {
                bankName = cached
                accountHolderName = UserDefaults.standard.string(forKey: "driver_bank_holder") ?? ""
                accountType = "checking"
            }
        }

        // Preferences
        if let prefsData = data["preferences"] as? [String: Any] {
            notificationsEnabled = prefsData["notificationsEnabled"] as? Bool ?? true
            soundEnabled = prefsData["soundEnabled"] as? Bool ?? true
            maxDeliveryDistance = prefsData["maxDeliveryDistance"] as? Double ?? AppConfig.shared.maxDeliveryDistanceMiles
        }

        // Build Driver object for display
        buildDriverObject(from: data)

        // Check for expiring documents
        checkDocumentExpirations()
    }

    // MARK: - Expiration Check

    func checkDocumentExpirations() {
        var alerts: [ExpirationAlert] = []
        let now = Date()
        let alertThreshold = 60 // days - warn if expiring within 60 days

        // Check Driver's License
        if let licenseExp = licenseExpiration {
            let daysRemaining = Calendar.current.dateComponents([.day], from: now, to: licenseExp).day ?? 0
            if daysRemaining <= alertThreshold {
                alerts.append(ExpirationAlert(
                    type: .license,
                    documentName: "Driver's License",
                    expirationDate: licenseExp,
                    daysRemaining: max(0, daysRemaining),
                    isExpired: daysRemaining <= 0,
                    isUrgent: daysRemaining <= 30
                ))
            }
        }

        // Check Insurance
        if let insuranceExp = insuranceExpiration {
            let daysRemaining = Calendar.current.dateComponents([.day], from: now, to: insuranceExp).day ?? 0
            if daysRemaining <= alertThreshold {
                alerts.append(ExpirationAlert(
                    type: .insurance,
                    documentName: "Insurance",
                    expirationDate: insuranceExp,
                    daysRemaining: max(0, daysRemaining),
                    isExpired: daysRemaining <= 0,
                    isUrgent: daysRemaining <= 30
                ))
            }
        }

        // Sort by urgency (expired first, then by days remaining)
        expirationAlerts = alerts.sorted { first, second in
            if first.isExpired && !second.isExpired { return true }
            if !first.isExpired && second.isExpired { return false }
            return first.daysRemaining < second.daysRemaining
        }
    }

    private func buildDriverObject(from data: [String: Any]) {
        var statsObj: DriverStats?
        if let statsData = data["stats"] as? [String: Any] {
            statsObj = DriverStats(
                rating: statsData["rating"] as? Double ?? 5.0,
                totalDeliveries: statsData["totalDeliveries"] as? Int ?? 0,
                completedDeliveries: statsData["completedDeliveries"] as? Int ?? 0,
                cancelledDeliveries: statsData["cancelledDeliveries"] as? Int ?? 0,
                totalEarnings: statsData["totalEarnings"] as? Double ?? 0.0,
                totalDistance: statsData["totalDistance"] as? Double ?? 0.0,
                totalOnlineTime: statsData["totalOnlineTime"] as? Double ?? 0.0,
                acceptanceRate: statsData["acceptanceRate"] as? Double ?? 100.0,
                completionRate: statsData["completionRate"] as? Double ?? 100.0,
                onTimeRate: statsData["onTimeRate"] as? Double ?? 100.0,
                weeklyDeliveries: statsData["weeklyDeliveries"] as? Int ?? 0,
                weeklyEarnings: statsData["weeklyEarnings"] as? Double ?? 0.0,
                weeklyHours: statsData["weeklyHours"] as? Double ?? 0.0,
                weeklyDistance: statsData["weeklyDistance"] as? Double ?? 0.0
            )
        }

        driver = Driver(
            id: Auth.auth().currentUser?.uid,
            name: name,
            email: email,
            phone: phone,
            profileImageUrl: data["profileImageUrl"] as? String,
            dateOfBirth: data["dateOfBirth"] as? Int64,
            address: DriverAddress(
                street: street,
                city: city,
                state: state,
                zipCode: zipCode
            ),
            driversLicense: DriversLicense(
                licenseNumber: licenseNumber,
                state: licenseState,
                licenseClass: licenseClass,
                frontImageUrl: licenseFrontUrl,
                backImageUrl: licenseBackUrl,
                isVerified: (data["driversLicense"] as? [String: Any])?["isVerified"] as? Bool ?? false
            ),
            vehicle: VehicleInfo(
                make: vehicleMake,
                model: vehicleModel,
                year: vehicleYear,
                color: vehicleColor,
                licensePlate: licensePlate,
                vehicleType: vehicleType,
                vehiclePhotoUrl: vehiclePhotoUrl,
                isVerified: (data["vehicle"] as? [String: Any])?["isVerified"] as? Bool ?? false
            ),
            vehicleType: vehicleType,
            licensePlate: licensePlate,
            insurance: InsuranceInfo(
                provider: insuranceProvider,
                policyNumber: insurancePolicyNumber,
                insuranceCardImageUrl: insuranceCardUrl,
                isVerified: (data["insurance"] as? [String: Any])?["isVerified"] as? Bool ?? false
            ),
            bankAccount: BankAccountInfo(
                bankName: bankName,
                accountHolderName: accountHolderName,
                accountType: accountType,
                accountNumberLast4: (data["bankAccount"] as? [String: Any])?["accountNumberLast4"] as? String
                    ?? UserDefaults.standard.string(forKey: "driver_bank_last4") ?? "",
                isVerified: (data["bankAccount"] as? [String: Any])?["isVerified"] as? Bool
                    ?? UserDefaults.standard.bool(forKey: "driver_bank_verified")
            ),
            isOnline: data["isOnline"] as? Bool ?? false,
            isApproved: data["isApproved"] as? Bool ?? false,
            approvalStatus: data["approvalStatus"] as? String ?? "pending",
            currentLatitude: data["currentLatitude"] as? Double ?? 0.0,
            currentLongitude: data["currentLongitude"] as? Double ?? 0.0,
            stats: statsObj
        )
    }

    private func createNewProfile(uid: String) {
        let initialData: [String: Any] = [
            "name": Auth.auth().currentUser?.displayName ?? "",
            "email": Auth.auth().currentUser?.email ?? "",
            "phone": Auth.auth().currentUser?.phoneNumber ?? "",
            "isOnline": false,
            "isApproved": false,
            "approvalStatus": "pending",
            "currentLatitude": 0.0,
            "currentLongitude": 0.0,
            "createdAt": Int64(Date().timeIntervalSince1970 * 1000),
            "stats": [
                "rating": 5.0,
                "totalDeliveries": 0,
                "completedDeliveries": 0,
                "cancelledDeliveries": 0,
                "totalEarnings": 0.0,
                "totalDistance": 0.0,
                "totalOnlineTime": 0.0,
                "acceptanceRate": 100.0,
                "completionRate": 100.0,
                "onTimeRate": 100.0,
                "weeklyDeliveries": 0,
                "weeklyEarnings": 0.0,
                "weeklyHours": 0.0,
                "weeklyDistance": 0.0
            ] as [String: Any]
        ]

        db.collection("drivers").document(uid).setData(initialData) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = "Unable to create your profile. Please try again."
                    self.showError = true
                    logger.error("Create profile error: \(error.localizedDescription)")
                }
            } else {
                DispatchQueue.main.async {
                    self.fetchProfile()
                }
            }
        }
    }

    // MARK: - Save Profile
    /// Issue #31 Fixed: Enhanced error handling with validation
    /// Issue #44 Fixed: Added completion handler for callers to react to save result
    func saveProfile(completion: ((Result<Void, Error>) -> Void)? = nil) {
        // Issue #32: Validate inputs before saving
        guard canSaveProfile else {
            errorMessage = validationErrors.joined(separator: "\n")
            showError = true
            completion?(.failure(NSError(
                domain: "DriverProfile",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: validationErrors.joined(separator: "\n")]
            )))
            return
        }

        // Use P2P API - this is the only backend we use
        guard let driverId = UserDefaults.standard.object(forKey: UserDefaultsKeys.driverId) as? Int else {
            errorMessage = "Not logged in. Please login again."
            showError = true
            completion?(.failure(NSError(
                domain: "DriverProfile",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Not logged in. Please login again."]
            )))
            return
        }

        saveProfileViaP2P(driverId: driverId, completion: completion)
    }

    /// Save profile via P2P API (Dollor.ai backend)
    /// Issue #44 Fixed: Added completion handler
    private func saveProfileViaP2P(driverId: Int, completion: ((Result<Void, Error>) -> Void)? = nil) {
        isLoading = true

        // Parse name into first/last name
        let nameParts = name.split(separator: " ")
        let firstName = nameParts.first.map(String.init) ?? name
        let lastName = nameParts.dropFirst().joined(separator: " ")

        p2pService.updateDriverProfile(
            driverId: driverId,
            firstName: firstName.isEmpty ? nil : firstName,
            lastName: lastName.isEmpty ? nil : lastName,
            phone: phone.isEmpty ? nil : phone,
            street: street.isEmpty ? nil : street,
            city: city.isEmpty ? nil : city,
            state: state.isEmpty ? nil : state,
            zipCode: zipCode.isEmpty ? nil : zipCode,
            vehicleType: vehicleType.isEmpty ? nil : vehicleType,
            vehicleMake: vehicleMake.isEmpty ? nil : vehicleMake,
            vehicleModel: vehicleModel.isEmpty ? nil : vehicleModel,
            vehicleYear: vehicleYear > 0 ? vehicleYear : nil,
            vehicleColor: vehicleColor.isEmpty ? nil : vehicleColor,
            licensePlate: licensePlate.isEmpty ? nil : licensePlate,
            licenseExpiry: licenseExpiration,
            insuranceExpiry: insuranceExpiration
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false

                switch result {
                case .success:
                    self?.isEditing = false
                    self?.fetchProfile() // Refresh data
                    completion?(.success(()))

                case .failure(let error):
                    let errorMsg = error.localizedDescription.lowercased()
                    if errorMsg.contains("network") || errorMsg.contains("connection") {
                        self?.errorMessage = "Unable to save. Please check your internet connection."
                    } else {
                        self?.errorMessage = "Unable to save your profile. Please try again."
                    }
                    self?.showError = true
                    completion?(.failure(error))
                    logger.error("Save profile error: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Upload Profile Image
    func uploadProfileImage(_ data: Data) async {
        // Use P2P API - this is the only backend we use
        guard let driverId = UserDefaults.standard.object(forKey: UserDefaultsKeys.driverId) as? Int else {
            await MainActor.run {
                self.errorMessage = "Not logged in. Please login again."
                self.showError = true
            }
            return
        }

        await uploadProfileImageViaP2P(data: data, driverId: driverId)
    }

    /// Upload profile image via P2P API
    private func uploadProfileImageViaP2P(data: Data, driverId: Int) async {
        await MainActor.run { self.isLoading = true }

        P2PAPIService.shared.uploadDriverDocument(
            driverId: driverId,
            documentType: .profilePhoto,
            imageData: data
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false

                switch result {
                case .success(let response):
                    // Update local state with the returned URL
                    if let fileUrl = response.fileUrl {
                        self?.driver?.profileImageUrl = fileUrl
                    }

                case .failure(let error):
                    self?.errorMessage = "Unable to upload your photo. Please try again."
                    self?.showError = true
                    logger.error("Upload profile image error: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Upload Verification Document (native, POST /api/auth/driver/documents)
    func uploadVerificationDocument(documentType: String, imageData: Data) {
        guard uploadingDocumentType == nil else { return }
        uploadingDocumentType = documentType
        documentUploadNotice = nil
        p2pService.uploadDriverDocument(documentType: documentType, imageData: imageData) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.uploadingDocumentType = nil
                switch result {
                case .success:
                    self.documentUploadNotice = "Document uploaded. We'll review it shortly."
                    self.fetchProfile()
                case .failure(let error):
                    self.errorMessage = "Upload failed: \(error.localizedDescription)"
                    self.showError = true
                }
            }
        }
    }

    // MARK: - Upload Document
    func uploadDocument(_ data: Data, type: String) async {
        // Use P2P API - this is the only backend we use
        guard let driverId = UserDefaults.standard.object(forKey: UserDefaultsKeys.driverId) as? Int else {
            #if DEBUG
            logger.info("[DriverProfileViewModel] uploadDocument failed - driverId not found in UserDefaults")
            logger.info("[DriverProfileViewModel] UserDefaults.driverId key: \(UserDefaultsKeys.driverId)")
            logger.info("[DriverProfileViewModel] Token available: \(SecureStorage.shared.driverAccessToken != nil)")
            #endif
            await MainActor.run {
                self.errorMessage = "Not logged in. Please login again."
                self.showError = true
            }
            return
        }

        #if DEBUG
        logger.info("[DriverProfileViewModel] uploadDocument starting - driverId: \(driverId), type: \(type), dataSize: \(data.count) bytes")
        #endif

        await uploadDocumentViaP2P(data: data, type: type, driverId: driverId)
    }

    // MARK: - Upload Document via P2P API (with AI Verification)
    /// Issue #33 Fixed: Retry logic for document upload failures
    private func uploadDocumentViaP2P(data: Data, type: String, driverId: Int, retryCount: Int = 0) async {
        await MainActor.run { isLoading = true }

        // Map document type to P2P API document type
        let documentType: DriverDocumentType
        var expiryDate: Date? = nil

        switch type {
        case "license_front":
            documentType = .licenseFront
            expiryDate = self.licenseExpiration
        case "license_back":
            documentType = .licenseBack
            expiryDate = self.licenseExpiration
        case "insurance_card":
            documentType = .insuranceCard
            expiryDate = self.insuranceExpiration
        case "vehicle_front":
            documentType = .vehicleFront
        case "vehicle_side":
            documentType = .vehicleSide
        case "vehicle_back":
            documentType = .vehicleBack
        default:
            documentType = .driversLicense
        }

        P2PAPIService.shared.uploadDriverDocument(
            driverId: driverId,
            documentType: documentType,
            imageData: data,
            expiryDate: expiryDate
        ) { [weak self] result in
            guard let self = self else { return }

            Task { @MainActor in
                switch result {
                case .success(let response):
                    self.isLoading = false
                    // Update local state with the returned URL
                    if let fileUrl = response.fileUrl {
                        switch type {
                        case "license_front":
                            self.licenseFrontUrl = fileUrl
                        case "license_back":
                            self.licenseBackUrl = fileUrl
                        case "insurance_card":
                            self.insuranceCardUrl = fileUrl
                        case "vehicle_photo":
                            self.vehiclePhotoUrl = fileUrl
                        default:
                            break
                        }
                    }

                    // If the document was auto-verified, refresh profile to get updated status
                    if response.verificationStatus == "verified" {
                        self.fetchProfile()
                    }

                case .failure(let error):
                    // Issue #33: Retry logic for transient failures
                    if retryCount < self.maxUploadRetries {
                        #if DEBUG
                        logger.info("[DriverProfileViewModel] Upload failed, retrying (\(retryCount + 1)/\(self.maxUploadRetries)): \(error.localizedDescription)")
                        #endif

                        // Exponential backoff: 1s, 2s, 4s
                        let delay = Double(1 << retryCount)
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

                        await self.uploadDocumentViaP2P(data: data, type: type, driverId: driverId, retryCount: retryCount + 1)
                    } else {
                        self.isLoading = false
                        self.errorMessage = "Failed to upload document after \(self.maxUploadRetries) attempts. Please try again later."
                        self.showError = true
                        #if DEBUG
                        logger.info("[DriverProfileViewModel] Upload failed after max retries: \(error.localizedDescription)")
                        #endif
                    }
                }
            }
        }
    }

    /// Fetch a fresh Stripe-hosted onboarding/account-management link and open it in
    /// the system browser. Not gating driving — a driver can be APPROVED and online
    /// with no Stripe account at all; this is purely the (previously missing) entry
    /// point for them to set payouts up whenever they choose.
    func openStripePayoutSetup() {
        guard let driverId = UserDefaults.standard.object(forKey: UserDefaultsKeys.driverId) as? Int else {
            errorMessage = "Please log in again to set up payouts."
            showError = true
            return
        }
        isLoadingStripeLink = true
        p2pService.getStripeOnboardingLink(driverId: driverId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoadingStripeLink = false
                switch result {
                case .success(let urlString):
                    self.webURL = URL(string: urlString)
                case .failure(let error):
                    self.errorMessage = "Could not open payout setup: \(error.localizedDescription)"
                    self.showError = true
                }
            }
        }
    }
}
