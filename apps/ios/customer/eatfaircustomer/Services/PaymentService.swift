import Foundation
import UIKit
import EatFairShared
import PassKit
import Stripe

// MARK: - Stripe Apple Pay Handler
/// Handles Stripe's Apple Pay integration using STPApplePayContext
/// Thread-safe implementation to prevent race conditions in concurrent payment attempts
class StripeApplePayHandler: NSObject {
    static let shared = StripeApplePayHandler()

    private static let merchantIdentifier = "merchant.com.dolloraiai"

    /// Whether this device/account can actually present Apple Pay (has a usable
    /// card in Wallet). Callers should hide the Apple Pay entry point otherwise
    /// rather than present a sheet that immediately fails.
    static var canMakeApplePayPayments: Bool {
        PKPaymentAuthorizationController.canMakePayments(usingNetworks: [.visa, .masterCard, .amex, .discover])
    }

    /// Builds a PKPaymentRequest for confirming a PaymentIntent/SetupIntent via Apple
    /// Pay. `amount` defaults to 0 for save-a-card (SetupIntent) flows — PassKit
    /// requires a non-negative summary item even when nothing is charged yet.
    static func makePaymentRequest(summaryItemLabel: String, amount: Decimal = 0) -> PKPaymentRequest {
        let request = PKPaymentRequest()
        request.merchantIdentifier = merchantIdentifier
        request.supportedNetworks = [.visa, .masterCard, .amex, .discover]
        request.merchantCapabilities = .threeDSecure
        request.countryCode = "US"
        request.currencyCode = "USD"
        request.paymentSummaryItems = [
            PKPaymentSummaryItem(label: summaryItemLabel, amount: NSDecimalNumber(decimal: amount))
        ]
        return request
    }

    /// Lock for thread-safe access to payment state
    private let paymentLock = NSLock()
    private var completionHandler: ((Bool, Error?) -> Void)?
    private var clientSecret: String?
    private var isPaymentInProgress = false

    /// Present Apple Pay sheet and handle payment through Stripe
    /// Thread-safe - prevents concurrent payment attempts
    func handleApplePay(
        request: PKPaymentRequest,
        clientSecret: String,
        completion: @escaping (Bool, Error?) -> Void
    ) {
        paymentLock.lock()

        // Prevent concurrent payment attempts
        guard !isPaymentInProgress else {
            paymentLock.unlock()
            completion(false, NSError(domain: "ApplePay", code: -3, userInfo: [NSLocalizedDescriptionKey: "Payment already in progress. Please wait."]))
            return
        }

        isPaymentInProgress = true
        self.completionHandler = completion
        self.clientSecret = clientSecret
        paymentLock.unlock()

        // Create Stripe Apple Pay context
        guard let applePayContext = STPApplePayContext(paymentRequest: request, delegate: self) else {
            resetPaymentState()
            completion(false, NSError(domain: "ApplePay", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create Apple Pay context. Please ensure Apple Pay is properly configured."]))
            return
        }

        // Present the Apple Pay sheet using the newer API
        DispatchQueue.main.async {
            applePayContext.presentApplePay()
        }
    }

    /// Reset payment state after completion or cancellation
    private func resetPaymentState() {
        paymentLock.lock()
        isPaymentInProgress = false
        completionHandler = nil
        clientSecret = nil
        paymentLock.unlock()
    }
}

// MARK: - STPApplePayContextDelegate
extension StripeApplePayHandler: STPApplePayContextDelegate {
    func applePayContext(
        _ context: STPApplePayContext,
        didCreatePaymentMethod paymentMethod: STPPaymentMethod,
        paymentInformation: PKPayment,
        completion: @escaping STPIntentClientSecretCompletionBlock
    ) {
        // Return the client secret to Stripe to complete the payment
        guard let clientSecret = self.clientSecret else {
            completion(nil, NSError(domain: "ApplePay", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing client secret"]))
            return
        }
        completion(clientSecret, nil)
    }

    func applePayContext(
        _ context: STPApplePayContext,
        didCompleteWith status: STPPaymentStatus,
        error: Error?
    ) {
        // Capture completion handler before resetting state
        let handler = completionHandler

        switch status {
        case .success:
            resetPaymentState()
            handler?(true, nil)
        case .error:
            // Create a more descriptive error if the original is unclear
            let displayError = error ?? NSError(
                domain: "ApplePay",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Payment failed. Please try again or use a different payment method."]
            )
            resetPaymentState()
            handler?(false, displayError)
        case .userCancellation:
            resetPaymentState()
            handler?(false, nil)
        @unknown default:
            resetPaymentState()
            handler?(false, NSError(
                domain: "ApplePay",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "An unexpected error occurred with Apple Pay."]
            ))
        }
    }
}
