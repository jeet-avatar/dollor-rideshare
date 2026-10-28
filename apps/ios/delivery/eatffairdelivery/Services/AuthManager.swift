import Foundation
import Combine
import EatFairShared
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "eatffairdelivery", category: "AuthManager")

/// AuthManager for P2P-based driver authentication
/// Manages driver login state using P2P API tokens stored in SecureStorage (Keychain)
/// Note: Tokens are stored in SecureStorage, other info (driverId, name, email) in UserDefaults
class AuthManager: ObservableObject {
    @Published var isLoggedIn: Bool = false
    @Published var driverName: String = ""
    @Published var driverEmail: String = ""

    /// Whether the driver has been approved (status APPROVED/ACTIVE). Drives the
    /// dashboard-vs-onboarding gate in eatffairdeliveryApp. A newly-registered
    /// driver is NOT approved and must complete the onboarding flow first.
    @Published var isApproved: Bool = false

    private let p2pService = P2PAPIService.shared
    private var approvalObserver: NSObjectProtocol?
    private var sessionExpiredObserver: NSObjectProtocol?

    /// Set when the server rejected the token and it could not be refreshed; the login screen shows it once.
    @Published var sessionExpiredMessage: String?

    init() {
        #if DEBUG
        // UITest screenshot bypass: inject pre-obtained driver token to skip SSL-pinned login
        if let token = ProcessInfo.processInfo.environment["UITEST_DRIVER_TOKEN"] {
            SecureStorage.shared.driverAccessToken = token
            UserDefaults.standard.set(48, forKey: UserDefaultsKeys.driverId)
            UserDefaults.standard.set("Marcus Johnson", forKey: UserDefaultsKeys.driverName)
            UserDefaults.standard.set("demo.driver@dollor.ai", forKey: UserDefaultsKeys.driverEmail)
            UserDefaults.standard.set(true, forKey: UserDefaultsKeys.driverTermsAccepted)
            self.isLoggedIn = true
            self.isApproved = true
            self.driverName = "Marcus Johnson"
            self.driverEmail = "demo.driver@dollor.ai"
            return
        }
        #endif
        // Check if driver is already logged in
        checkLoginState()

        // A driver API call hit an unrefreshable 401: sign out and tell the driver why.
        sessionExpiredObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("DriverTokenExpired"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.isLoggedIn else { return }
            self.sessionExpiredMessage = "Session expired, please sign in again."
            self.logout()
        }

        // React to approval changes pushed from the backend (driverApproved/driverRejected).
        approvalObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("DriverApprovalStatusChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            if let approved = notification.userInfo?["approved"] as? Bool {
                self.isApproved = approved
            }
        }
    }

    deinit {
        if let approvalObserver = approvalObserver {
            NotificationCenter.default.removeObserver(approvalObserver)
        }
        if let sessionExpiredObserver = sessionExpiredObserver {
            NotificationCenter.default.removeObserver(sessionExpiredObserver)
        }
    }

    private func checkLoginState() {
        // Check for token in SecureStorage (Keychain) - this is where P2PAPIService stores it
        let hasToken = SecureStorage.shared.driverAccessToken != nil
        let hasDriverId = UserDefaults.standard.object(forKey: UserDefaultsKeys.driverId) != nil

        guard hasToken else {
            isLoggedIn = false
            #if DEBUG
            logger.info("[AuthManager] Not logged in - no token")
            #endif
            return
        }

        // A token alone is enough to consider the driver logged in — don't additionally
        // require `hasDriverId` to already be in UserDefaults. A delete+reinstall wipes
        // UserDefaults but can leave a Keychain-backed token behind (Keychain items commonly
        // survive app deletion); requiring both locally would wrongly bounce an already-
        // registered driver back to the login screen. Log in optimistically from the token,
        // then confirm + repopulate everything from the backend in the background.
        isLoggedIn = true
        driverName = UserDefaults.standard.string(forKey: UserDefaultsKeys.driverName) ?? ""
        driverEmail = UserDefaults.standard.string(forKey: UserDefaultsKeys.driverEmail) ?? ""
        isApproved = p2pService.isDriverApproved

        #if DEBUG
        logger.info("[AuthManager] Driver logged in (token present, hasDriverId=\(hasDriverId)) - validating with backend")
        #endif

        validateAndRestoreSession()
    }

    /// Confirms the token is still accepted by the server and repopulates any missing
    /// UserDefaults (driverId/name/email/status) from the authoritative `/auth/driver/me`
    /// response. Only logs the driver out on a definitive 401/403 — any other failure
    /// (network blip, 5xx) leaves the optimistic logged-in state alone rather than
    /// bouncing the driver to the login screen over a transient error.
    private func validateAndRestoreSession() {
        p2pService.getDriverMe { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let json):
                // The doc comment above promises this repopulates driverId too — it didn't:
                // a delete+reinstall wipes UserDefaults but leaves the Keychain token behind,
                // so UserDefaultsKeys.driverId silently fell back to 0 everywhere it's read
                // (DriverOnboardingView, updateDriverProfile, document uploads, ...), which
                // the backend's ownership check (`driver.id != driver_id`) then rejects as
                // 403 "Access denied" the moment the driver tries to save anything.
                if let driverId = json["id"] as? Int {
                    UserDefaults.standard.set(driverId, forKey: UserDefaultsKeys.driverId)
                }
                if let name = json["name"] as? String, !name.isEmpty {
                    self.driverName = name
                }
                if let email = json["email"] as? String, !email.isEmpty {
                    self.driverEmail = email
                }
                let status = (json["status"] as? String ?? "").lowercased()
                self.isApproved = ["approved", "active", "online"].contains(status)
            case .failure(let error):
                if case P2PAPIError.unauthorized = error {
                    #if DEBUG
                    logger.info("[AuthManager] Session validation rejected by server — logging out")
                    #endif
                    self.sessionExpiredMessage = "Session expired, please sign in again."
                    self.logout()
                }
                // Any other error: leave the optimistic logged-in state as-is.
            }
        }
    }

    func logout() {
        // Clear token from SecureStorage (Keychain)
        SecureStorage.shared.clearAuthTokens(type: .driver)

        // Clear all stored driver data from UserDefaults
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.driverId)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.driverCode)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.driverName)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.driverEmail)

        DispatchQueue.main.async {
            self.isLoggedIn = false
            self.driverName = ""
            self.driverEmail = ""
            self.isApproved = false
        }

        #if DEBUG
        logger.info("[AuthManager] Logged out - cleared all driver data")
        #endif
    }

    func refreshLoginState() {
        checkLoginState()
    }

    /// Poll the backend for the live driver status and update `isApproved`.
    /// Used by the onboarding flow's "pending approval" step. getDriverMe
    /// persists status + approval flag to UserDefaults before this completes.
    func refreshApprovalStatus(completion: ((Bool) -> Void)? = nil) {
        p2pService.getDriverMe { [weak self] result in
            guard let self = self else { return }
            let approved: Bool
            switch result {
            case .success(let json):
                let status = (json["status"] as? String ?? "").lowercased()
                approved = ["approved", "active", "online"].contains(status)
            case .failure:
                approved = self.p2pService.isDriverApproved
            }
            self.isApproved = approved
            completion?(approved)
        }
    }

    /// Flip the gate to the dashboard once onboarding confirms approval.
    func markApproved() {
        isApproved = true
    }
}
