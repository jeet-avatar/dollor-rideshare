import SwiftUI
import EatFairShared

// MARK: - Terms and Conditions View
//
// Shown by DriverDashboardView until the driver has accepted the current
// Driver Terms. Acceptance is recorded locally (see `acceptTerms`).
struct TermsAndConditionsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var hasAccepted = false
    @State private var isLoading = false

    private let p2pService = P2PAPIService.shared
    let onAccept: (() -> Void)?

    init(onAccept: (() -> Void)? = nil) {
        self.onAccept = onAccept
    }

    var body: some View {
        NavigationStack {
            DriverTermsList(hasAgreed: $hasAccepted)
                .navigationTitle("Driver Terms")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Agree", action: acceptTerms)
                            .fontWeight(.semibold)
                            .disabled(!hasAccepted || isLoading)
                    }
                }
        }
        .interactiveDismissDisabled(isLoading)
        .preferredColorScheme(.dark)
    }

    private func acceptTerms() {
        // Check if driver is logged in via P2P
        guard p2pService.isDriverLoggedIn else { return }

        isLoading = true

        // Store terms acceptance locally (P2P backend doesn't have terms endpoint yet)
        // Key must match what DriverDashboardView checks
        UserDefaults.standard.set(true, forKey: "p2p_driver_terms_accepted")
        UserDefaults.standard.set(Int64(Date().timeIntervalSince1970 * 1000), forKey: "p2p_driver_terms_accepted_at")
        UserDefaults.standard.set(AppConstants.termsVersion, forKey: UserDefaultsKeys.driverTermsVersion)

        isLoading = false
        onAccept?()
        dismiss()
    }
}

// MARK: - Driver Terms summary list
//
// Grouped summary of https://api.dollor.ai/driver-terms. Shared by the
// sign-up sheet (DriverTermsSheet) and the post-login gate above. The full
// Driver Terms of Service and Terms of Service remain the binding text.
struct DriverTermsList: View {
    @Binding var hasAgreed: Bool
    @State private var legalPageURL: URL?

    private let config = AppConfig.shared

    var body: some View {
        List {
            Section("About Dollor") {
                TermsRow("building.2", "Dollor Driver is operated by Zietra Technologies Inc. (doing business as Dollor.ai).")
                TermsRow("checkmark.seal", "Dollor.ai is a peer-to-peer rideshare marketplace in California, operating under CPUC Transportation Network Company permit TNC0050982-N.")
                TermsRow("person.badge.shield.checkmark", "You are an independent contractor, not an employee of Dollor.ai or Zietra Technologies Inc.")
            }
            .listRowBackground(Theme.lxSurface)

            Section("How bidding works") {
                TermsRow("hand.raised", "Riders post a ride offer and independent drivers bid on it. Dollor.ai provides the technology and processes payments; the ride itself is provided by you.")
                TermsRow("tag", "You name your bid. When the rider accepts, the rider's card is authorized; when the ride is completed the fare is captured.")
                TermsRow("power", "You decide when you go online, which requests to bid on, and whether to accept a match.")
                TermsRow("arrow.triangle.branch", "You may work for other platforms.")
            }
            .listRowBackground(Theme.lxSurface)

            Section {
                ForEach(config.rideshareTierRows, id: \.label) { row in
                    LabeledContent(row.label, value: row.fee)
                        .foregroundColor(Theme.lxText)
                }
                TermsRow("percent", "The Connection Fee is a flat amount based on the fare, not a percentage. It is charged to you and, separately, to the rider.")
                TermsRow("building.columns", "A $0.05 CPUC Access for All charge applies to you, and a separate $0.05 to the rider, on each completed trip.")
                TermsRow("banknote", "100% of tips go to you. Payouts are made through Stripe after you complete Stripe's payout onboarding.")
                TermsRow("exclamationmark.circle", "Dollor.ai does not guarantee any minimum earnings, hours, or rides, and does not provide benefits.")
            } header: {
                Text("Fees and payouts")
            } footer: {
                Text("A flat Connection Fee and a CPUC charge are deducted from your payout.")
            }
            .listRowBackground(Theme.lxSurface)

            Section("Your responsibilities") {
                TermsRow("person.text.rectangle", "Be at least 21 years old.")
                TermsRow("creditcard", "Hold a valid driver's license and upload a photo of it.")
                TermsRow("car", "Maintain valid vehicle insurance and upload proof of it.")
                TermsRow("person.crop.circle", "Upload a profile photo and provide your vehicle information.")
                TermsRow("magnifyingglass", "Complete a background check through Checkr and be approved by Dollor.ai. You cannot go online until your account is approved and your background check has cleared.")
                TermsRow("doc.text", "You are responsible for your own taxes, insurance, vehicle expenses, and any license or permit your work requires.")
                TermsRow("shield", "You are responsible for the insurance California law and the CPUC require of a driver providing rides arranged through an online platform. Dollor.ai does not provide insurance coverage to you through this agreement.")
            }
            .listRowBackground(Theme.lxSurface)

            Section("Cancellations") {
                TermsRow("xmark.circle", "If you cancel after a match, the rider is not charged, the card authorization is released, and the request is re-opened to other drivers. Frequent cancellations may affect your standing.")
                TermsRow("person.crop.circle.badge.xmark", "If the rider cancels before the trip starts, no fee is charged to the rider.")
                TermsRow("clock", "If you arrive at pickup, wait at least 5 minutes, and the rider does not show up, you may mark a no-show. The rider's saved card is charged a $5.00 no-show fee and $4.00 (80%) is paid to you, if you have completed Stripe payout onboarding and the card charge succeeds.")
            }
            .listRowBackground(Theme.lxSurface)

            Section("Account and data") {
                TermsRow("lock.shield", "Your account may be suspended or deactivated for violating the terms, a background check that does not clear, a lapse of license or insurance, safety concerns, or fraud.")
                TermsRow("exclamationmark.triangle", "Harassment, discrimination, impaired or unsafe driving, fraud, or misuse of rider information may result in suspension or deactivation.")
                TermsRow("arrow.uturn.backward", "To appeal a deactivation, contact support@dollor.ai within 30 days.")
                Button {
                    legalPageURL = URL(string: AppConstants.privacyPolicyURL)
                } label: {
                    TermsLinkRow("hand.raised", "Privacy Policy")
                }
            }
            .listRowBackground(Theme.lxSurface)

            Section {
                if let supportURL = URL(string: "mailto:\(AppConstants.contactEmail)") {
                    Link(destination: supportURL) {
                        TermsLinkRow("envelope", "Contact support (\(AppConstants.contactEmail))")
                    }
                }
                Button {
                    legalPageURL = URL(string: AppConstants.driverTermsURL)
                } label: {
                    TermsLinkRow("doc.text", "Read full Driver Terms")
                }
                Button {
                    legalPageURL = URL(string: AppConstants.termsOfServiceURL)
                } label: {
                    TermsLinkRow("doc.text", "Read Terms of Service")
                }
            } header: {
                Text("Support")
            } footer: {
                Text("This is a summary. The full Driver Terms of Service and Terms of Service are the binding text.")
            }
            .listRowBackground(Theme.lxSurface)

            Section {
                Toggle("I have read and agree to the Driver Terms", isOn: $hasAgreed)
                    .foregroundColor(Theme.lxText)
                    .tint(Theme.lxOrange)
            } footer: {
                Text("Terms version \(AppConstants.termsVersion) · Effective October 29, 2026")
            }
            .listRowBackground(Theme.lxSurface)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.lxBg.ignoresSafeArea())
        .inAppBrowser(url: $legalPageURL)
    }
}

// MARK: - Rows

private struct TermsRow: View {
    let icon: String
    let text: String

    init(_ icon: String, _ text: String) {
        self.icon = icon
        self.text = text
    }

    var body: some View {
        Label {
            Text(text)
                .font(Lx.Typography.body)
                .foregroundColor(Theme.lxText)
        } icon: {
            Image(systemName: icon)
                .foregroundColor(Theme.lxOrange)
        }
    }
}

private struct TermsLinkRow: View {
    let icon: String
    let title: String

    init(_ icon: String, _ title: String) {
        self.icon = icon
        self.title = title
    }

    var body: some View {
        HStack {
            Label(title, systemImage: icon)
                .foregroundColor(Theme.lxOrange)
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(Lx.Typography.caption)
                .foregroundColor(Theme.lxTextMuted)
                .accessibilityHidden(true)
        }
        .frame(minHeight: Lx.Size.buttonHeightCompact)
        .contentShape(Rectangle())
    }
}

#Preview {
    TermsAndConditionsView()
}
