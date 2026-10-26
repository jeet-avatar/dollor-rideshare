import SwiftUI
import Combine
import Stripe
import EatFairShared

private let usStates = [
    "AL","AK","AZ","AR","CA","CO","CT","DE","FL","GA","HI","ID","IL","IN","IA","KS","KY",
    "LA","ME","MD","MA","MI","MN","MS","MO","MT","NE","NV","NH","NJ","NM","NY","NC","ND",
    "OH","OK","OR","PA","RI","SC","SD","TN","TX","UT","VT","VA","WA","WV","WI","WY","DC",
].sorted()

struct FoundingMemberView: View {
    @StateObject private var model = FoundingMemberModel(isDriver: false)
    @State private var cardParams: STPPaymentMethodParams?
    @State private var selectedState: String = "CA"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if model.isLoading {
                    ProgressView("Loading…").frame(maxWidth: .infinity).padding(.top, 40)
                        .tint(Theme.lxOrange)
                } else {
                    benefitsCard
                    statePicker
                    slotsCard

                    if model.isMember {
                        memberBadge
                    } else if model.eligible {
                        joinSection
                    } else {
                        Text("Founding membership isn't available for your account right now.")
                            .font(.subheadline)
                            .foregroundColor(Theme.lxTextSecondary)
                    }

                    if let error = model.errorMessage {
                        Text(error).font(.caption).foregroundColor(Theme.lxError)
                    }
                    if let success = model.successMessage {
                        Text(success).font(.subheadline).foregroundColor(Theme.lxSuccess)
                    }
                }
            }
            .padding()
        }
        .scrollContentBackground(.hidden)
        .background(Theme.lxBg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .navigationTitle("Founding Member")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            model.load(state: selectedState)
        }
        .onChange(of: selectedState) { newState in
            model.loadSlots(state: newState)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "star.circle.fill")
                .font(Lx.Typography.iconLarge)
                .foregroundColor(Theme.lxOrange)
            Text("Become a Founding Member")
                .font(.title2).fontWeight(.bold)
                .foregroundColor(Theme.lxText)
            Text("A one-time $\(Int(model.feeAmount)) joins you as a Dollor.ai founding member and locks your fees for life.")
                .font(.subheadline)
                .foregroundColor(Theme.lxTextSecondary)
        }
    }

    private var benefitsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Lifetime fee lock", systemImage: "lock.fill")
                .font(.headline)
                .foregroundColor(Theme.lxText)
            Text(model.benefitDescription ?? "Your platform fees are locked at today's rate for as long as you ride with Dollor.ai.")
                .font(.subheadline)
                .foregroundColor(Theme.lxTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Theme.lxSurface)
        .cornerRadius(Lx.Radius.button)
        .overlay(
            RoundedRectangle(cornerRadius: Lx.Radius.button)
                .stroke(Theme.lxHairline, lineWidth: 1)
        )
    }

    private var statePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your state")
                .font(.caption)
                .foregroundColor(Theme.lxTextSecondary)
            Menu {
                ForEach(usStates, id: \.self) { state in
                    Button(state) { selectedState = state }
                }
            } label: {
                HStack {
                    Text(selectedState)
                        .font(.headline)
                        .foregroundColor(Theme.lxText)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundColor(Theme.lxTextSecondary)
                }
                .padding()
                .background(Theme.lxSurface)
                .cornerRadius(Lx.Radius.button)
                .overlay(
                    RoundedRectangle(cornerRadius: Lx.Radius.button)
                        .stroke(Theme.lxHairline, lineWidth: 1)
                )
            }
        }
    }

    private var slotsCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Slots remaining in \(selectedState)")
                    .font(.caption).foregroundColor(Theme.lxTextSecondary)
                Text(model.slotsRemaining.map { "\($0)" } ?? "—")
                    .font(.title3).fontWeight(.bold)
                    .foregroundColor(Theme.lxOrange)
            }
            Spacer()
            if let total = model.slotsTotal {
                Text("of \(total)").font(.caption).foregroundColor(Theme.lxTextSecondary)
            }
        }
        .padding()
        .background(Theme.lxSurface)
        .cornerRadius(Lx.Radius.button)
        .overlay(
            RoundedRectangle(cornerRadius: Lx.Radius.button)
                .stroke(Theme.lxHairline, lineWidth: 1)
        )
    }

    private var memberBadge: some View {
        VStack(spacing: 8) {
            Label("You're a Founding Member", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundColor(Theme.lxOrange)
            if let st = model.memberState {
                Text("Locked in: \(st)")
                    .font(.caption)
                    .foregroundColor(Theme.lxTextSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Theme.lxOrange.opacity(0.1))
        .cornerRadius(Lx.Radius.button)
        .overlay(
            RoundedRectangle(cornerRadius: Lx.Radius.button)
                .stroke(Theme.lxOrange.opacity(0.4), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var joinSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.isDemo {
                Text("Payment")
                    .font(.headline)
                    .foregroundColor(Theme.lxText)
                FoundingCardField(params: $cardParams)
                    .frame(height: 44)
                    .padding(.horizontal, 8)
                    .background(Theme.lxSurface)
                    .overlay(RoundedRectangle(cornerRadius: Lx.Radius.chip).stroke(Theme.lxHairline))
                    .cornerRadius(Lx.Radius.chip)
            } else {
                #if DEBUG
                Text("Demo account — no charge will be made.")
                    .font(.caption).foregroundColor(Theme.lxTextSecondary)
                #endif
            }

            Button(action: { model.join(state: selectedState, params: cardParams) }) {
                HStack {
                    if model.isJoining {
                        ProgressView().tint(Lx.Palette.onAccent)
                    } else {
                        Text("Join for $\(Int(model.feeAmount)) · \(selectedState)")
                            .fontWeight(.bold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    Group {
                        if canJoin {
                            Theme.lxButtonGradient
                        } else {
                            Theme.lxSurface2
                        }
                    }
                )
                .foregroundColor(Lx.Palette.onAccent)
                .cornerRadius(Lx.Radius.button)
                .shadow(color: canJoin ? Theme.lxOrange.opacity(0.4) : .clear, radius: 14, x: 0, y: 6)
            }
            .disabled(!canJoin)

            Text("Non-refundable. Your platform fee is frozen at today's rate for life.")
                .font(.caption2)
                .foregroundColor(Theme.lxTextSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var canJoin: Bool {
        if model.isJoining { return false }
        if model.isDemo { return true }
        return cardParams != nil
    }
}

struct FoundingCardField: UIViewRepresentable {
    @Binding var params: STPPaymentMethodParams?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> STPPaymentCardTextField {
        let field = STPPaymentCardTextField()
        field.delegate = context.coordinator
        return field
    }

    func updateUIView(_ uiView: STPPaymentCardTextField, context: Context) {}

    final class Coordinator: NSObject, STPPaymentCardTextFieldDelegate {
        let parent: FoundingCardField
        init(_ parent: FoundingCardField) { self.parent = parent }
        func paymentCardTextFieldDidChange(_ textField: STPPaymentCardTextField) {
            parent.params = textField.isValid ? textField.paymentMethodParams : nil
        }
    }
}

// MARK: - Model

final class FoundingMemberModel: ObservableObject {
    @Published var isLoading = true
    @Published var isJoining = false
    @Published var eligible = false
    @Published var isMember = false
    @Published var isDemo = false
    @Published var slotsRemaining: Int?
    @Published var slotsTotal: Int?
    @Published var memberState: String?
    @Published var feeAmount: Double = 100
    @Published var benefitDescription: String?
    @Published var errorMessage: String?
    @Published var successMessage: String?

    let isDriver: Bool

    init(isDriver: Bool) { self.isDriver = isDriver }

    func load(state: String? = nil) {
        isLoading = true
        errorMessage = nil
        P2PAPIService.shared.getFoundingStatus(isDriver: isDriver, state: state) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                switch result {
                case .success(let status):
                    self.eligible = status.eligible
                    self.isMember = status.isMember
                    self.isDemo = status.demo
                    self.slotsRemaining = status.slotsRemaining
                    self.slotsTotal = status.slotsTotal
                    self.memberState = status.state
                    self.feeAmount = status.feeAmount
                    self.benefitDescription = status.benefitDescription
                    if let key = status.publishableKey, !key.isEmpty {
                        STPAPIClient.shared.publishableKey = key
                    }
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func loadSlots(state: String) {
        P2PAPIService.shared.getFoundingStatus(isDriver: isDriver, state: state) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if case .success(let status) = result {
                    self.slotsRemaining = status.slotsRemaining
                    self.slotsTotal = status.slotsTotal
                }
            }
        }
    }

    func join(state: String, params: STPPaymentMethodParams?) {
        guard !isJoining else { return }
        isJoining = true
        errorMessage = nil
        successMessage = nil

        if isDemo || params == nil {
            callJoin(state: state, paymentMethodId: nil)
            return
        }

        STPAPIClient.shared.createPaymentMethod(with: params!) { [weak self] paymentMethod, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    self.isJoining = false
                    self.errorMessage = error.localizedDescription
                    return
                }
                guard let paymentMethod = paymentMethod else {
                    self.isJoining = false
                    self.errorMessage = "Could not process your card. Please try again."
                    return
                }
                self.callJoin(state: state, paymentMethodId: paymentMethod.stripeId)
            }
        }
    }

    private func callJoin(state: String, paymentMethodId: String?) {
        P2PAPIService.shared.joinFounding(isDriver: isDriver, state: state, paymentMethodId: paymentMethodId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isJoining = false
                switch result {
                case .success(let joinResult):
                    self.isMember = joinResult.isMember
                    self.successMessage = joinResult.message ?? "Welcome, Founding Member!"
                    self.load(state: state)
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
