import SwiftUI
import EatFairShared

// MARK: - Terms and Conditions View
struct TermsAndConditionsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var hasAccepted = false
    @State private var fullTermsURL: URL?
    @State private var isLoading = false

    private let p2pService = P2PAPIService.shared
    let onAccept: (() -> Void)?

    init(onAccept: (() -> Void)? = nil) {
        self.onAccept = onAccept
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    TermsHeader()

                    TermsSummarySection(title: "Who we are", icon: "building.2.fill", items: [
                        "Dollor Driver is operated by Zietra Technologies Inc. (doing business as Dollor.ai).",
                        "Dollor.ai is a peer-to-peer rideshare marketplace in California, operating under CPUC Transportation Network Company permit TNC0050982-N.",
                        "Riders post a ride offer and independent drivers bid on it. Dollor.ai provides the technology and processes payments; the ride itself is provided by you."
                    ])

                    TermsSummarySection(title: "Independent contractor", icon: "person.badge.shield.checkmark", items: [
                        "You are an independent contractor, not an employee of Dollor.ai or Zietra Technologies Inc.",
                        "You decide when you go online, which requests to bid on, and whether to accept a match.",
                        "You may work for other platforms.",
                        "You are responsible for your own taxes, insurance, vehicle expenses, and any license or permit your work requires.",
                        "Dollor.ai does not guarantee any minimum earnings, hours, or rides, and does not provide benefits."
                    ])

                    FeeSummaryCard()

                    TermsSummarySection(title: "Requirements to go online", icon: "checkmark.seal.fill", items: [
                        "Be at least 21 years old.",
                        "Hold a valid driver's license and upload a photo of it.",
                        "Maintain valid vehicle insurance and upload proof of it.",
                        "Upload a profile photo and provide your vehicle information.",
                        "Complete a background check through Checkr and be approved by Dollor.ai. You cannot go online until your account is approved and your background check has cleared."
                    ])

                    TermsSummarySection(title: "Cancellations and no-shows", icon: "xmark.circle.fill", items: [
                        "If you cancel after a match, the rider is not charged, the card authorization is released, and the request is re-opened to other drivers. Frequent cancellations may affect your standing.",
                        "If the rider cancels before the trip starts, no fee is charged to the rider.",
                        "If you arrive at pickup, wait at least 5 minutes, and the rider does not show up, you may mark a no-show. The rider's saved card is charged a $5.00 no-show fee and $4.00 (80%) is paid to you, if you have completed Stripe payout onboarding and the card charge succeeds."
                    ])

                    TermsSummarySection(title: "Insurance and deactivation", icon: "shield.fill", items: [
                        "You are responsible for the insurance California law and the CPUC require of a driver providing rides arranged through an online platform. Dollor.ai does not provide insurance coverage to you through this agreement.",
                        "Your account may be suspended or deactivated for violating the terms, a background check that does not clear, a lapse of license or insurance, safety concerns, or fraud.",
                        "To appeal a deactivation, contact support@dollor.ai within 30 days."
                    ])

                    TermsSummarySection(title: "Contact", icon: "envelope.fill", items: [
                        "Support: support@dollor.ai"
                    ])

                    Text("This is a summary. The full Driver Terms of Service and Terms of Service are the binding text.")
                        .font(.caption)
                        .foregroundColor(Theme.lxTextSecondary)
                        .padding(.horizontal)

                    Button(action: { fullTermsURL = URL(string: AppConstants.driverTermsURL) }) {
                        TermsLinkLabel(title: "Read the full Driver Terms")
                    }
                    .padding(.horizontal)

                    Button(action: { fullTermsURL = URL(string: AppConstants.termsOfServiceURL) }) {
                        TermsLinkLabel(title: "Read the Terms of Service")
                    }
                    .padding(.horizontal)

                    // Accept Toggle
                    Toggle(isOn: $hasAccepted) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("I accept the Terms & Conditions")
                                .fontWeight(.semibold)
                                .foregroundColor(Theme.lxText)
                            Text("By accepting, you agree to the Driver Terms of Service, the Terms of Service, and the fee structure above.")
                                .font(.caption)
                                .foregroundColor(Theme.lxTextSecondary)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: Theme.lxOrange))
                    .padding()
                    .background(Theme.lxSurface)
                    .cornerRadius(Lx.Radius.button)
                    .overlay(RoundedRectangle(cornerRadius: Lx.Radius.button).stroke(Theme.lxHairline, lineWidth: 1))
                    .shadow(color: .black.opacity(0.4), radius: 4)
                    .padding(.horizontal)

                    // Accept Button
                    Button(action: acceptTerms) {
                        if isLoading {
                            ProgressView()
                                .tint(Lx.Palette.onAccent)
                        } else {
                            Text("Accept & Continue")
                                .fontWeight(.bold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(hasAccepted ? AnyShapeStyle(Theme.lxButtonGradient) : AnyShapeStyle(Theme.lxSurface2))
                    .foregroundColor(Lx.Palette.onAccent)
                    .cornerRadius(Lx.Radius.button)
                    .shadow(color: hasAccepted ? Theme.lxOrange.opacity(0.4) : .clear, radius: 10, x: 0, y: 4)
                    .padding(.horizontal)
                    .disabled(!hasAccepted || isLoading)

                    // Version
                    Text("Terms Version \(AppConstants.termsVersion) • Effective October 29, 2026")
                        .font(.caption)
                        .foregroundColor(Theme.lxTextMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 24)
                }
            }
            .background(Theme.lxBg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(Theme.lxTextSecondary)
                }
            }
            .inAppBrowser(url: $fullTermsURL)
        }
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

// MARK: - Terms Header
struct TermsHeader: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Dollor Driver")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(Theme.lxText)

            Text("Driver Terms & Conditions")
                .font(.title3)
                .foregroundColor(Theme.lxTextSecondary)

            Text("Terms for independent drivers on the Dollor.ai rideshare marketplace")
                .font(.subheadline)
                .foregroundColor(Theme.lxTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - Fee Summary
struct FeeSummaryCard: View {
    private let config = AppConfig.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "dollarsign.circle.fill", title: "How you are paid")

            Text("You name your bid. When the rider accepts, the rider's card is authorized; when the ride is completed the fare is captured. A flat Connection Fee and a CPUC charge are deducted from your payout.")
                .font(.subheadline)
                .foregroundColor(Theme.lxTextSecondary)

            ForEach(config.rideshareTierRows, id: \.label) { row in
                HStack {
                    Text(row.label)
                        .font(.subheadline)
                        .foregroundColor(Theme.lxText)
                    Spacer()
                    Text(row.fee)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.lxText)
                }
            }

            Text("The Connection Fee is a flat amount based on the fare, not a percentage. It is charged to you and, separately, to the rider.")
                .font(.caption)
                .foregroundColor(Theme.lxTextSecondary)
            Text("A $0.05 CPUC Access for All charge applies to you, and a separate $0.05 to the rider, on each completed trip.")
                .font(.caption)
                .foregroundColor(Theme.lxTextSecondary)
            Text("100% of tips go to you. Payouts are made through Stripe after you complete Stripe's payout onboarding.")
                .font(.caption)
                .foregroundColor(Theme.lxTextSecondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.lxSurface)
        .cornerRadius(Lx.Radius.card)
        .overlay(RoundedRectangle(cornerRadius: Lx.Radius.card).stroke(Theme.lxHairline, lineWidth: 1))
        .padding(.horizontal)
    }
}

// MARK: - Summary Section
struct TermsSummarySection: View {
    let title: String
    let icon: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: icon, title: title)

            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text("\u{2022}")
                        .foregroundColor(Theme.lxOrange)
                    Text(item)
                        .font(.subheadline)
                        .foregroundColor(Theme.lxText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.lxSurface)
        .cornerRadius(Lx.Radius.card)
        .overlay(RoundedRectangle(cornerRadius: Lx.Radius.card).stroke(Theme.lxHairline, lineWidth: 1))
        .padding(.horizontal)
    }
}

struct TermsLinkLabel: View {
    let title: String

    var body: some View {
        HStack {
            Image(systemName: "doc.text.fill")
            Text(title)
            Spacer()
            Image(systemName: "chevron.right")
        }
        .foregroundColor(Theme.lxOrange)
        .padding()
        .background(Theme.lxOrange.opacity(0.12))
        .cornerRadius(Lx.Radius.button)
        .overlay(RoundedRectangle(cornerRadius: Lx.Radius.button).stroke(Theme.lxOrange.opacity(0.4), lineWidth: 1))
    }
}

// MARK: - Section Header
struct SectionHeader: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(Theme.lxOrange)

            Text(title)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(Theme.lxText)
        }
    }
}

#Preview {
    TermsAndConditionsView()
}
