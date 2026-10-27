import Foundation
import Combine
import EatFairShared
import os

private let logger = Logger(subsystem: "com.dollorai.delivery", category: "OnlineStatusManager")

/// Single source of truth for driver online/offline status.
///
/// Replaces three independent isOnline states that previously lived in
/// DeliveryViewModel, RideBiddingViewModel, and EarningsViewModel.
///
/// Responsibilities:
/// - Call PUT /api/auth/driver/online exactly once per toggle
/// - Start/stop LocationManager.shared tracking
/// - Revert isOnline on API failure
/// - Publish isOnline so all ViewModels observe the same value
///
/// Usage: Read OnlineStatusManager.shared.isOnline from any ViewModel.
/// Toggle: call OnlineStatusManager.shared.setOnlineStatus(_:)
final class OnlineStatusManager: ObservableObject {

    static let shared = OnlineStatusManager()

    @Published private(set) var isOnline: Bool = false

    /// Last reason the driver could not go online (e.g. 403 background-check gate).
    /// Views observe this to show the server-provided reason; cleared on a new attempt/success.
    @Published var statusError: String?

    private let p2pService = P2PAPIService.shared
    private var isRequestInFlight = false
    /// How many times we've retried the current in-flight request after a network error.
    private var retryCount = 0
    /// True while a go-online retry is waiting; the server still reports offline then, so syncing must not undo the toggle.
    private var isRetryPending = false
    /// Incremented on every toggle so a slow server read cannot overwrite a newer choice.
    private var toggleGeneration = 0

    private init() {}

    /// Toggle driver online/offline. Calls backend once; retries once on network failure.
    /// On a 403 gate error: reverts immediately (driver not allowed online).
    /// On a network error: keeps optimistic state and retries after 5 s.
    /// Safe to call from any ViewModel — in-flight guard prevents duplicate calls.
    func setOnlineStatus(_ online: Bool) {
        guard !isRequestInFlight else {
            #if DEBUG
            logger.warning("[OnlineStatusManager] setOnlineStatus(\(online)) ignored — request already in flight")
            #endif
            return
        }

        retryCount = 0
        toggleGeneration += 1
        sendOnlineStatusRequest(online: online)
    }

    private func sendOnlineStatusRequest(online: Bool) {
        // Optimistic update (idempotent — safe to re-apply on retry)
        isOnline = online
        isRequestInFlight = true
        statusError = nil

        if online {
            LocationManager.shared.startTracking()
        } else {
            LocationManager.shared.stopTracking()
        }

        p2pService.setDriverOnlineStatus(isOnline: online) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isRequestInFlight = false

                switch result {
                case .success:
                    self.retryCount = 0
                    #if DEBUG
                    logger.info("[OnlineStatusManager] Status confirmed by backend: isOnline=\(online)")
                    #endif
                    if online {
                        VoiceAssistantManager.shared.speak("You are now online and receiving ride requests")
                    } else {
                        VoiceAssistantManager.shared.speak("You are now offline")
                    }

                case .failure(let error):
                    // Distinguish a compliance gate (403 / gateError) from a network failure.
                    // A gate error means the driver genuinely cannot go online — revert immediately.
                    // A network error is transient — retry once without reverting the optimistic state.
                    let isGateError: Bool = {
                        if let p2p = error as? P2PAPIError, case .gateError = p2p { return true }
                        return false
                    }()

                    if isGateError || !online {
                        // Gate error or go-offline failure: revert and surface reason.
                        self.isOnline = !online
                        if !online { LocationManager.shared.startTracking() }
                        else { LocationManager.shared.stopTracking() }
                        if online { self.statusError = error.localizedDescription }
                        logger.error("[OnlineStatusManager] setOnlineStatus hard-failed: \(error.localizedDescription)")
                    } else if self.retryCount < 1 {
                        // Network error on go-online: keep optimistic state, retry after 5 s.
                        self.retryCount += 1
                        self.isRetryPending = true
                        logger.warning("[OnlineStatusManager] go-online failed (network) — retry \(self.retryCount) in 5 s")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                            guard let self = self else { return }
                            self.isRetryPending = false
                            guard self.isOnline else { return }
                            self.sendOnlineStatusRequest(online: online)
                        }
                    } else {
                        // Two consecutive network failures — give up and revert.
                        self.retryCount = 0
                        self.isOnline = false
                        LocationManager.shared.stopTracking()
                        self.statusError = "Could not connect to server. Please check your connection and try again."
                        logger.error("[OnlineStatusManager] go-online failed after retry: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    /// Adopts the server's online flag (relaunch, or the driver went online from another device)
    /// so the toggle never contradicts what riders see. Never overrides an in-flight toggle.
    func syncFromServer() {
        guard !isRequestInFlight, !isRetryPending else { return }
        let generation = toggleGeneration
        p2pService.getDriverMe { [weak self] result in
            DispatchQueue.main.async {
                self?.applyServerStatus(result, generation: generation)
            }
        }
    }

    private func applyServerStatus(_ result: Result<[String: Any], Error>, generation: Int) {
        guard !isRequestInFlight, !isRetryPending, generation == toggleGeneration else { return }
        guard case .success(let json) = result,
              let serverOnline = json["is_online"] as? Bool,
              serverOnline != isOnline else { return }
        isOnline = serverOnline
        if serverOnline {
            LocationManager.shared.startTracking()
        } else {
            LocationManager.shared.stopTracking()
        }
    }

    /// Called by EarningsViewModel.startSession() when session is written to Firebase.
    /// Sets isOnline=true WITHOUT calling the backend (session flow already handles this
    /// via updateOnlineStatus which calls backend separately).
    func markOnlineLocally() {
        isOnline = true
        LocationManager.shared.startTracking()
    }

    /// Called by EarningsViewModel.endSession() when session ends.
    /// Sets isOnline=false WITHOUT calling the backend (endSession calls updateOnlineStatus separately).
    func markOfflineLocally() {
        isOnline = false
        LocationManager.shared.stopTracking()
    }
}
