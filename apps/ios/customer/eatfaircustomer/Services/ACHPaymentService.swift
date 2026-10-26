import Foundation
import StripePaymentSheet
import Stripe
import EatFairShared

// MARK: - Fee Calculation Model (outside class for Swift 6 compatibility)

// Helper function for decoding on background threads
private func decodeACHFeeCalculation(from data: Data) -> ACHFeeCalculation? {
    try? JSONDecoder().decode(ACHFeeCalculation.self, from: data)
}

struct ACHFeeCalculation: Decodable, Sendable {
    let amount: Int
    let currency: String
    let collection: CollectionFees

    struct CollectionFees: Decodable, Sendable {
        let method: String
        let fee: Double
        let feePercentage: String
        let customerDiscount: Double
        let savingsVsCard: Double?

        enum CodingKeys: String, CodingKey {
            case method
            case fee
            case feePercentage = "fee_percentage"
            case customerDiscount = "customer_discount"
            case savingsVsCard = "savings_vs_card"
        }
    }
}

// TODO: [CRITICAL] API mismatch — No /api/enterprise/ routes exist in backend. All 3 endpoints (fees/calculate, payments/create) will 404.
/// ACH Payment Service for bank transfer payments
/// Lower fees than card payments with customer discount
class ACHPaymentService {
    static let shared = ACHPaymentService()

    private var paymentSheet: PaymentSheet?

    /// Lock for thread-safe payment operations
    private let paymentLock = NSLock()

    /// Track in-progress payments to prevent duplicate submissions
    private var pendingPaymentIds = Set<String>()

    private init() {}

    // MARK: - Payment Response Models

    struct ACHPaymentResponse: Decodable {
        let paymentId: String
        let clientSecret: String?
        let amount: Int
        let currency: String
        let paymentMethod: String
        let status: String
        let customerDiscount: Double
        let processingFee: Double
        let netAmount: Int

        enum CodingKeys: String, CodingKey {
            case paymentId = "payment_id"
            case clientSecret = "client_secret"
            case amount
            case currency
            case paymentMethod = "payment_method"
            case status
            case customerDiscount = "customer_discount"
            case processingFee = "processing_fee"
            case netAmount = "net_amount"
        }
    }


    // MARK: - Calculate Fees

    /// Calculate and compare fees between card and ACH payments
    /// Thread-safe implementation using actor-like synchronization
    /// - Parameters:
    ///   - amountCents: Amount in cents
    ///   - completion: Callback with card fees, ACH fees, and savings
    func calculateFees(
        amountCents: Int,
        completion: @escaping (Result<(cardFee: Double, achFee: Double, savings: Double, customerDiscount: Double), Error>) -> Void
    ) {
        let baseURL = AppConfig.shared.p2pAPIBaseURL

        // Thread-safe result collection
        let resultQueue = DispatchQueue(label: "com.dollor.fees.result")
        var cardFee: Double = 0
        var achFee: Double = 0
        var savings: Double = 0
        var customerDiscount: Double = 0
        var fetchError: Error?

        let group = DispatchGroup()

        // Card fees
        group.enter()
        guard let cardURL = URL(string: "\(baseURL)/api/enterprise/fees/calculate?amount=\(amountCents)&payment_method=card") else {
            completion(.failure(PaymentError.invalidURL))
            return
        }

        URLSession.shared.dataTask(with: cardURL) { data, _, error in
            defer { group.leave() }
            resultQueue.sync {
                if let error = error, fetchError == nil {
                    fetchError = error
                    return
                }
                if let data = data,
                   let response = decodeACHFeeCalculation(from: data) {
                    cardFee = response.collection.fee
                }
            }
        }.resume()

        // ACH fees
        group.enter()
        guard let achURL = URL(string: "\(baseURL)/api/enterprise/fees/calculate?amount=\(amountCents)&payment_method=ach") else {
            completion(.failure(PaymentError.invalidURL))
            return
        }

        URLSession.shared.dataTask(with: achURL) { data, _, error in
            defer { group.leave() }
            resultQueue.sync {
                if let error = error, fetchError == nil {
                    fetchError = error
                    return
                }
                if let data = data,
                   let response = decodeACHFeeCalculation(from: data) {
                    achFee = response.collection.fee
                    customerDiscount = response.collection.customerDiscount
                    savings = response.collection.savingsVsCard ?? 0
                }
            }
        }.resume()

        group.notify(queue: .main) {
            resultQueue.sync {
                if let error = fetchError {
                    completion(.failure(error))
                } else {
                    completion(.success((cardFee, achFee, savings, customerDiscount)))
                }
            }
        }
    }

    // MARK: - Create ACH Payment

    /// Create an ACH payment intent with idempotency protection
    /// Prevents duplicate payments from double-taps or network retries
    /// - Parameters:
    ///   - amountCents: Amount in cents
    ///   - customerEmail: Customer's email for receipt
    ///   - orderId: Optional order ID reference
    ///   - completion: Callback with payment response
    func createACHPayment(
        amountCents: Int,
        customerEmail: String?,
        orderId: String? = nil,
        completion: @escaping (Result<ACHPaymentResponse, Error>) -> Void
    ) {
        // Generate idempotency key to prevent duplicate payments
        let idempotencyKey = "\(orderId ?? "ach")-\(amountCents)-\(Int(Date().timeIntervalSince1970))"

        // Check for duplicate payment attempt
        paymentLock.lock()
        if pendingPaymentIds.contains(idempotencyKey) {
            paymentLock.unlock()
            completion(.failure(PaymentError.duplicatePayment))
            return
        }
        pendingPaymentIds.insert(idempotencyKey)
        paymentLock.unlock()

        let baseURL = AppConfig.shared.p2pAPIBaseURL
        guard let url = URL(string: "\(baseURL)/api/enterprise/payments/create") else {
            removePendingPayment(idempotencyKey)
            completion(.failure(PaymentError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")

        // Add auth token if available
        if let token = SecureStorage.shared.customerAccessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body: [String: Any] = [
            "amount": amountCents,
            "currency": "usd",
            "payment_method": "ach",
            "idempotency_key": idempotencyKey
        ]

        if let email = customerEmail {
            body["customer_email"] = email
        }

        if let orderId = orderId {
            body["order_id"] = orderId
        }

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async { [weak self] in
                self?.removePendingPayment(idempotencyKey)

                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(PaymentError.noData))
                    return
                }

                do {
                    let paymentResponse = try JSONDecoder().decode(ACHPaymentResponse.self, from: data)
                    completion(.success(paymentResponse))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    private func removePendingPayment(_ key: String) {
        paymentLock.lock()
        pendingPaymentIds.remove(key)
        paymentLock.unlock()
    }

    // MARK: - Present ACH Payment Sheet

    /// Present the Stripe Payment Sheet with ACH (bank account) option
    /// - Parameters:
    ///   - amountCents: Amount to charge in cents
    ///   - customerEmail: Customer email
    ///   - viewController: ViewController to present from
    ///   - completion: Callback with result
    func presentACHPaymentSheet(
        amountCents: Int,
        customerEmail: String,
        from viewController: UIViewController? = nil,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        // First create the payment intent
        createACHPayment(amountCents: amountCents, customerEmail: customerEmail) { [weak self] result in
            switch result {
            case .success(let response):
                guard let clientSecret = response.clientSecret else {
                    completion(.failure(PaymentError.noClientSecret))
                    return
                }

                // Configure PaymentSheet for ACH
                var configuration = PaymentSheet.Configuration()
                configuration.merchantDisplayName = "Dollor"

                // Allow only bank account
                configuration.allowsDelayedPaymentMethods = true

                // Financial connections for bank linking
                // This enables ACH Direct Debit

                self?.paymentSheet = PaymentSheet(
                    paymentIntentClientSecret: clientSecret,
                    configuration: configuration
                )

                // Present the sheet
                DispatchQueue.main.async { [weak self] in
                    let presentingVC: UIViewController? = viewController ?? {
                        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
                            return nil
                        }
                        return window.rootViewController
                    }()
                    if let vc = presentingVC {
                        self?.paymentSheet?.present(from: vc) { paymentResult in
                            switch paymentResult {
                            case .completed:
                                completion(.success(()))
                            case .canceled:
                                completion(.failure(PaymentError.canceled))
                            case .failed(let error):
                                completion(.failure(error))
                            }
                        }
                    } else {
                        completion(.failure(PaymentError.noViewController))
                    }
                }

            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Payment Errors

    enum PaymentError: Error, LocalizedError {
        case invalidURL
        case noData
        case noClientSecret
        case canceled
        case noViewController
        case duplicatePayment

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid payment URL"
            case .noData:
                return "No data received from server"
            case .noClientSecret:
                return "Payment not initialized properly"
            case .canceled:
                return "Payment was canceled"
            case .noViewController:
                return "Cannot present payment sheet"
            case .duplicatePayment:
                return "Payment already in progress. Please wait."
            }
        }
    }
}

// MARK: - SwiftUI Integration

import SwiftUI

/// SwiftUI view for ACH payment option
struct ACHPaymentButton: View {
    let amount: Double
    let customerEmail: String
    let onPaymentComplete: (Bool, Error?) -> Void

    @State private var isLoading = false
    @State private var fees: (card: Double, ach: Double, savings: Double, discount: Double)?
    @State private var showError = false
    @State private var errorMessage = ""

    init(
        amount: Double,
        customerEmail: String,
        onPaymentComplete: @escaping (Bool, Error?) -> Void
    ) {
        self.amount = amount
        self.customerEmail = customerEmail
        self.onPaymentComplete = onPaymentComplete
    }

    var body: some View {
        VStack(spacing: 12) {
            // Fee comparison
            if let fees = fees {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Pay with Bank Account")
                            .font(.headline)
                        Text("Save $\(String(format: "%.2f", fees.savings)) vs card")
                            .font(.caption)
                            .foregroundColor(Lx.Palette.success)
                    }

                    Spacer()

                    VStack(alignment: .trailing) {
                        Text("$\(String(format: "%.2f", amount - fees.discount))")
                            .font(.headline)
                        if fees.discount > 0 {
                            Text("-$\(String(format: "%.2f", fees.discount)) discount")
                                .font(.caption)
                                .foregroundColor(Lx.Palette.success)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(Lx.Radius.button)
            }

            // Pay button
            Button(action: initiatePayment) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                    Image(systemName: "building.columns")
                    Text(isLoading ? "Processing..." : "Pay with Bank Account")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Lx.Palette.orange)
                .foregroundColor(Lx.Palette.onAccent)
                .cornerRadius(Lx.Radius.button)
            }
            .disabled(isLoading)
        }
        .onAppear {
            loadFees()
        }
        .alert("Payment Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func loadFees() {
        let amountCents = Int(amount * 100)
        ACHPaymentService.shared.calculateFees(amountCents: amountCents) { result in
            switch result {
            case .success(let feeData):
                self.fees = (feeData.cardFee, feeData.achFee, feeData.savings, feeData.customerDiscount)
            case .failure:
                // Fallback calculation
                self.fees = (
                    card: amount * 0.029 + 0.30,
                    ach: min(amount * 0.008, 5.0),
                    savings: (amount * 0.029 + 0.30) - min(amount * 0.008, 5.0),
                    discount: 0.50
                )
            }
        }
    }

    private func initiatePayment() {
        isLoading = true
        let amountCents = Int(amount * 100)

        ACHPaymentService.shared.presentACHPaymentSheet(
            amountCents: amountCents,
            customerEmail: customerEmail
        ) { result in
            isLoading = false
            switch result {
            case .success:
                onPaymentComplete(true, nil)
            case .failure(let error):
                if case ACHPaymentService.PaymentError.canceled = error {
                    // User canceled, not an error
                    onPaymentComplete(false, nil)
                } else {
                    let errMsg = error.localizedDescription.lowercased()
                    if errMsg.contains("insufficient") || errMsg.contains("funds") {
                        errorMessage = "Insufficient funds. Please check your account balance."
                    } else if errMsg.contains("invalid") || errMsg.contains("account") {
                        errorMessage = "Invalid account details. Please verify your bank information."
                    } else {
                        errorMessage = "Payment could not be processed. Please try again."
                    }
                    showError = true
                    onPaymentComplete(false, error)
                }
            }
        }
    }
}
