import SwiftUI
import EatFairShared

// MARK: - Terms and Conditions View
struct TermsAndConditionsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var hasAccepted = false
    @State private var showFullTerms = false
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
                    // Header
                    TermsHeader()

                    // Platform Fee Highlight
                    PlatformFeeCard()

                    // Key Benefits
                    KeyBenefitsSection()

                    // How It Works
                    HowItWorksSection()

                    // Driver Rights
                    DriverRightsSection()

                    // Direct Rider Requests
                    DirectOrderSection()

                    // Privacy & Data
                    PrivacySection()

                    // Full Terms Link
                    Button(action: { showFullTerms = true }) {
                        HStack {
                            Image(systemName: "doc.text.fill")
                            Text("Read Full Terms & Conditions")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .foregroundColor(Theme.lxOrange)
                        .padding()
                        .background(Theme.lxOrange.opacity(0.12))
                        .cornerRadius(Lx.Radius.button)
                        .overlay(RoundedRectangle(cornerRadius: Lx.Radius.button).stroke(Theme.lxOrange.opacity(0.4), lineWidth: 1))
                    }
                    .padding(.horizontal)

                    // Accept Toggle
                    Toggle(isOn: $hasAccepted) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("I accept the Terms & Conditions")
                                .fontWeight(.semibold)
                                .foregroundColor(Theme.lxText)
                            Text("By accepting, you agree to our platform policies, $1 fee structure, and driver guidelines.")
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
                    Text("Terms Version \(AppConstants.termsVersion) • Last Updated: December 2024")
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
            .sheet(isPresented: $showFullTerms) {
                FullTermsView()
            }
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
        VStack(spacing: 16) {
            // Smiling dollar sign logo
            ZStack {
                Circle()
                    .fill(Theme.lxOrange.opacity(0.15))
                    .frame(width: 100, height: 100)

                Text("$")
                    .font(Lx.Typography.iconLarge.weight(.bold))
                    .foregroundColor(Theme.lxOrange)
            }

            Text("Dollor AI Service")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(Theme.lxText)

            Text("$ online store")
                .font(.headline)
                .foregroundColor(Theme.lxOrange)

            Text("Driver Terms & Conditions")
                .font(.title3)
                .foregroundColor(Theme.lxTextSecondary)

            Text("A peer-to-peer matchmaking platform connecting independent drivers with riders.")
                .font(.subheadline)
                .foregroundColor(Theme.lxTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Independent Contractor Badge
            HStack(spacing: 6) {
                Image(systemName: "person.badge.shield.checkmark")
                    .foregroundColor(Theme.lxOrange)
                Text("You are an Independent Contractor")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.lxText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.lxOrange.opacity(0.12))
            .cornerRadius(Lx.Radius.sheet)
            .overlay(Capsule().stroke(Theme.lxOrange.opacity(0.4), lineWidth: 1))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - Connection Fee Card (P2P Matchmaking)
struct PlatformFeeCard: View {
    private let config = AppConfig.shared

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "link.circle.fill")
                    .font(.title)
                    .foregroundColor(Theme.lxOrange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Connection Fee Structure")
                        .font(.headline)
                        .foregroundColor(Theme.lxText)
                    Text("Matchmaking service fees only")
                        .font(.caption)
                        .foregroundColor(Theme.lxTextSecondary)
                }

                Spacer()
            }

            Divider().overlay(Theme.lxHairline)

            // Fee Structure - P2P matchmaking model
            VStack(spacing: 12) {
                FeeRow(
                    title: "Rider Connection Fee",
                    amount: String(format: "$%.2f", config.serviceFee),
                    description: "For using our matchmaking service"
                )

                FeeRow(
                    title: "Platform Fee",
                    amount: "$\(Int(config.rideshareTier1Fee))–$\(Int(config.rideshareTier3Fee))",
                    description: "\(AppConfig.shared.rideshareFeeSummary) — per ride"
                )

                FeeRow(
                    title: "Your Tips",
                    amount: "100%",
                    description: "Tips are 100% yours"
                )
            }

            // Highlight Box - Independent contractor emphasis
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "star.fill")
                        .foregroundColor(Theme.lxOrange)

                    Text("Keep 100% of what you earn")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.lxText)
                }

                Text("You're an independent contractor - set your own prices for rideshare")
                    .font(.caption)
                    .foregroundColor(Theme.lxTextSecondary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Theme.lxSuccess.opacity(0.12))
            .cornerRadius(Lx.Radius.button)
            .overlay(RoundedRectangle(cornerRadius: Lx.Radius.button).stroke(Theme.lxSuccess.opacity(0.35), lineWidth: 1))
        }
        .padding()
        .background(Theme.lxSurface)
        .cornerRadius(Lx.Radius.card)
        .overlay(RoundedRectangle(cornerRadius: Lx.Radius.card).stroke(Theme.lxHairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 8)
        .padding(.horizontal)
    }
}

struct FeeRow: View {
    let title: String
    let amount: String
    let description: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(Theme.lxText)
                Text(description)
                    .font(.caption)
                    .foregroundColor(Theme.lxTextSecondary)
            }

            Spacer()

            Text(amount)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(amount == "$0.00" ? Theme.lxSuccess : Theme.lxText)
        }
    }
}

// MARK: - Key Benefits Section
struct KeyBenefitsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(icon: "star.circle.fill", title: "What Makes Us Different")

            VStack(spacing: 12) {
                BenefitRow(
                    icon: "message.fill",
                    title: "Direct Rider Chat",
                    description: "Communicate directly with riders for better coordination and tips"
                )

                BenefitRow(
                    icon: "mappin.and.ellipse",
                    title: "Direct Rider Pickups",
                    description: "Pick up your rider and drive straight to their destination"
                )

                BenefitRow(
                    icon: "hand.raised.fill",
                    title: "Independent Contractor Freedom",
                    description: "Set your own schedule, prices, and negotiate directly with riders"
                )

                BenefitRow(
                    icon: "speaker.wave.2.fill",
                    title: "Voice Assistant",
                    description: "Hands-free operation while driving - stay safe, stay productive"
                )

                BenefitRow(
                    icon: "banknote.fill",
                    title: "Transparent Earnings",
                    description: "No hidden fees, no percentage cuts - what you earn is yours"
                )
            }
        }
        .padding(.horizontal)
    }
}

struct BenefitRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(Theme.lxOrange)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.lxText)
                Text(description)
                    .font(.caption)
                    .foregroundColor(Theme.lxTextSecondary)
            }

            Spacer()
        }
        .padding()
        .background(Theme.lxSurface)
        .cornerRadius(Lx.Radius.button)
        .overlay(RoundedRectangle(cornerRadius: Lx.Radius.button).stroke(Theme.lxHairline, lineWidth: 1))
    }
}

// MARK: - How It Works Section
struct HowItWorksSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(icon: "gearshape.fill", title: "How Earnings Work")

            VStack(spacing: 0) {
                StepRow(
                    number: 1,
                    title: "Rider Requests a Ride",
                    description: "Rider pays ride fare + platform fee + tip",
                    isLast: false
                )

                StepRow(
                    number: 2,
                    title: "You Accept the Trip",
                    description: "Review the fare and pickup, then accept, decline, or counter the offer",
                    isLast: false
                )

                StepRow(
                    number: 3,
                    title: "You Drive the Rider",
                    description: "You receive the full fare + full tip (zero platform cut on your earnings!)",
                    isLast: false
                )

                StepRow(
                    number: 4,
                    title: "Bonus: Repeat Riders",
                    description: "Riders can request you directly - earn points & higher tips",
                    isLast: true
                )
            }
            .padding()
            .background(Theme.lxSurface)
            .cornerRadius(Lx.Radius.card)
            .overlay(RoundedRectangle(cornerRadius: Lx.Radius.card).stroke(Theme.lxHairline, lineWidth: 1))
        }
        .padding(.horizontal)
    }
}

struct StepRow: View {
    let number: Int
    let title: String
    let description: String
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Number Circle with Line
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(Theme.lxOrange)
                        .frame(width: 32, height: 32)

                    Text("\(number)")
                        .font(.headline)
                        .foregroundColor(Lx.Palette.onAccent)
                }

                if !isLast {
                    Rectangle()
                        .fill(Theme.lxOrange.opacity(0.3))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 32)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.lxText)

                Text(description)
                    .font(.caption)
                    .foregroundColor(Theme.lxTextSecondary)
            }
            .padding(.bottom, isLast ? 0 : 24)

            Spacer()
        }
    }
}

// MARK: - Independent Contractor Rights Section
struct DriverRightsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(icon: "shield.fill", title: "Your Rights as an Independent Contractor")

            VStack(alignment: .leading, spacing: 12) {
                RightItem(text: "Accept or decline any request without penalty")
                RightItem(text: "Set your own schedule - work when you want")
                RightItem(text: "Set your own prices for rideshare trips")
                RightItem(text: "Negotiate directly with your riders")
                RightItem(text: "Use multiple platforms - no exclusivity required")
                RightItem(text: "Keep 100% of your earnings (no percentage cuts)")
                RightItem(text: "Operate your own independent business")
                RightItem(text: "24/7 platform support")
            }
            .padding()
            .background(Theme.lxSurface)
            .cornerRadius(Lx.Radius.card)
            .overlay(RoundedRectangle(cornerRadius: Lx.Radius.card).stroke(Theme.lxHairline, lineWidth: 1))
        }
        .padding(.horizontal)
    }
}

struct RightItem: View {
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Theme.lxSuccess)

            Text(text)
                .font(.subheadline)
                .foregroundColor(Theme.lxText)

            Spacer()
        }
    }
}

// MARK: - Direct Rider Section
struct DirectOrderSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(icon: "person.2.fill", title: "Direct Rider Requests")

            VStack(alignment: .leading, spacing: 16) {
                Text("The Game Changer")
                    .font(.headline)
                    .foregroundColor(Theme.lxOrange)

                Text("Riders can contact you directly through chat to request rides. This gives you:")
                    .font(.subheadline)
                    .foregroundColor(Theme.lxTextSecondary)

                VStack(spacing: 8) {
                    DirectBenefitRow(icon: "plus.circle.fill", text: "Higher tips from satisfied riders")
                    DirectBenefitRow(icon: "plus.circle.fill", text: "Repeat rides from regular riders")
                    DirectBenefitRow(icon: "plus.circle.fill", text: "Points toward driver rewards")
                    DirectBenefitRow(icon: "plus.circle.fill", text: "Build your own rider base")
                    DirectBenefitRow(icon: "plus.circle.fill", text: "Flexibility to negotiate ride terms")
                }

                // Example Scenario
                VStack(alignment: .leading, spacing: 8) {
                    Text("Example Scenario:")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.lxTextMuted)

                    Text("\"Hey driver, can you pick me up 5 minutes early? I'll add $5 extra tip\"")
                        .font(.subheadline)
                        .italic()
                        .foregroundColor(Theme.lxTextSecondary)
                        .padding()
                        .background(Theme.lxSurface2)
                        .cornerRadius(Lx.Radius.chip)
                        .overlay(RoundedRectangle(cornerRadius: Lx.Radius.chip).stroke(Theme.lxHairline, lineWidth: 1))

                    Text("You have the freedom to accept direct ride requests and earn more!")
                        .font(.caption)
                        .foregroundColor(Theme.lxSuccess)
                }
            }
            .padding()
            .background(Theme.lxSurface)
            .cornerRadius(Lx.Radius.card)
            .overlay(RoundedRectangle(cornerRadius: Lx.Radius.card).stroke(Theme.lxHairline, lineWidth: 1))
        }
        .padding(.horizontal)
    }
}

struct DirectBenefitRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(Theme.lxSuccess)
                .font(.caption)

            Text(text)
                .font(.subheadline)
                .foregroundColor(Theme.lxText)
        }
    }
}

// MARK: - Privacy Section
struct PrivacySection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(icon: "lock.fill", title: "Privacy & Data")

            VStack(alignment: .leading, spacing: 12) {
                PrivacyItem(
                    title: "Location Data",
                    description: "Used only during active trips for rider tracking. Never sold."
                )

                PrivacyItem(
                    title: "Personal Information",
                    description: "Stored securely. Only shared with riders for trip purposes."
                )

                PrivacyItem(
                    title: "Earnings Data",
                    description: "Your earnings history is private and only visible to you."
                )

                PrivacyItem(
                    title: "Chat History",
                    description: "Messages stored securely. Reviewed only for support or disputes."
                )
            }
            .padding()
            .background(Theme.lxSurface)
            .cornerRadius(Lx.Radius.card)
            .overlay(RoundedRectangle(cornerRadius: Lx.Radius.card).stroke(Theme.lxHairline, lineWidth: 1))
        }
        .padding(.horizontal)
    }
}

struct PrivacyItem: View {
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundColor(Theme.lxOrange)
                    .font(.caption)

                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.lxText)
            }

            Text(description)
                .font(.caption)
                .foregroundColor(Theme.lxTextSecondary)
                .padding(.leading, 24)
        }
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

// MARK: - Full Terms View
struct FullTermsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Group {
                        TermsSection(title: "1. Introduction & Legal Status") {
                            Text("""
                            Welcome to Dollor AI Service ("Platform", "we", "us", "our"). These Terms and Conditions ("Terms") govern your use of our peer-to-peer matchmaking platform.

                            IMPORTANT LEGAL NOTICE: Dollor AI Service is a MATCHMAKING PLATFORM that connects riders with independent drivers. We do NOT provide transportation services. We are NOT a Transportation Network Company (TNC). All transportation arrangements are directly between you (the driver) and the rider.

                            By accessing or using Dollor AI Service as a driver, you agree to be bound by these Terms and acknowledge your status as an INDEPENDENT CONTRACTOR. If you disagree with any part of the terms, you may not access the service.
                            """)
                        }

                        TermsSection(title: "2. Connection Fee Structure") {
                            Text("""
                            Dollor AI Service operates on a transparent, flat-fee model for our MATCHMAKING service:

                            PLATFORM FEES (for use of our matching platform):
                            • Rider Connection Fee: $1.00 per connection
                            • Driver Platform Fee (per ride):
                               - \(AppConfig.shared.rideshareFeeSummary)

                            As an INDEPENDENT DRIVER, you retain 100% of:
                            - Fares negotiated directly with riders (less the per-ride platform fee above)
                            - All tips provided by riders (tips are always 100% yours)
                            - Any additional compensation agreed upon with riders

                            IMPORTANT: Dollor AI Service charges a flat platform fee for matching you with riders. We do NOT take a percentage of your earnings. You set your own prices and negotiate directly with riders.
                            """)
                        }

                        TermsSection(title: "3. Independent Contractor Status") {
                            Text("""
                            As an INDEPENDENT CONTRACTOR using Dollor AI Service, you acknowledge:

                            • You are NOT an employee of Dollor AI Service
                            • You operate your own independent transportation business
                            • You set your own schedule and working hours
                            • You may accept or decline any ride request without penalty
                            • You are responsible for your own taxes, insurance, and vehicle expenses
                            • You may use other platforms simultaneously
                            • Transportation services are provided by YOU, not by Dollor AI Service

                            ELIGIBILITY REQUIREMENTS:
                            • Be at least 18 years of age
                            • Possess a valid driver's license
                            • Have access to a reliable, legally registered vehicle
                            • Maintain valid auto insurance meeting your state's requirements
                            • Complete identity verification
                            • Have a smartphone capable of running the Dollor AI Service app
                            """)
                        }

                        TermsSection(title: "4. Driver Responsibilities") {
                            Text("""
                            As a Dollor AI Service driver, you agree to:

                            • Complete trips in a timely and professional manner
                            • Drive safely and maintain a valid driver's license and current auto insurance
                            • Communicate professionally with riders
                            • Follow all applicable traffic laws and regulations
                            • Keep your vehicle clean and in good working condition
                            • Update your availability status accurately
                            • Report any issues or incidents promptly
                            """)
                        }

                        TermsSection(title: "5. Direct Rider Communication") {
                            Text("""
                            Dollor AI Service encourages direct communication between drivers and riders through our in-app chat feature. This includes:

                            • Coordinating pickup details
                            • Providing trip updates
                            • Confirming pickup and dropoff locations
                            • Discussing tip arrangements

                            Guidelines for direct communication:
                            • Maintain professional conduct at all times
                            • Do not share personal contact information outside the platform
                            • Report any inappropriate behavior immediately
                            • Respect rider privacy and preferences
                            """)
                        }

                        TermsSection(title: "6. Ride Conduct & Vehicle Standards") {
                            Text("""
                            Drivers are responsible for providing safe, professional rides. Each trip is a single rider pickup to dropoff. You agree to:

                            • Drive safely and obey all traffic laws
                            • Maintain a valid driver's license and current auto insurance at all times
                            • Keep your vehicle clean, well-maintained, and in safe working condition
                            • Treat every rider with respect and professionalism

                            Conditions:
                            • Your vehicle must meet applicable safety and registration requirements
                            • Follow the agreed pickup and dropoff locations
                            • Reasonable time expectations must be communicated
                            • Any additional compensation should be agreed upon in advance
                            """)
                        }

                        TermsSection(title: "7. Earnings and Payments") {
                            Text("""
                            As an INDEPENDENT CONTRACTOR, your earnings are:

                            RIDESHARE (P2P Matchmaking):
                            • YOU set your own prices for rides
                            • Riders make offers which you can accept, decline, or counter
                            • All negotiated fares go directly to you
                            • Dollor AI Service only charges a per-ride platform fee (\(AppConfig.shared.rideshareFeeSummary))
                            • Tips are 100% yours

                            Payment Schedule:
                            • Earnings are calculated in real-time
                            • Weekly automatic deposits to your linked bank account
                            • Instant cashout available for a small fee
                            • Detailed earnings reports available in the app
                            """)
                        }

                        TermsSection(title: "8. Voice Assistant Feature") {
                            Text("""
                            Dollor AI Service provides a hands-free voice assistant for driver safety:

                            • Accept or decline rides by voice
                            • Get navigation directions
                            • Send quick messages to riders
                            • Check earnings
                            • Mark trips as complete

                            Important: Always prioritize safe driving. Use voice features responsibly.
                            """)
                        }

                        TermsSection(title: "9. Tax & Legal Compliance") {
                            Text("""
                            INDEPENDENT CONTRACTOR TAX OBLIGATIONS:

                            As an independent contractor, YOU are responsible for:
                            • Reporting all earnings to the IRS and state tax authorities
                            • Paying self-employment taxes (Social Security & Medicare)
                            • Making quarterly estimated tax payments if required
                            • Maintaining records of all business expenses
                            • Filing appropriate tax returns (Schedule C, etc.)

                            Dollor AI Service will provide:
                            • Form 1099-NEC for earnings over $600/year
                            • Year-end earnings summary for your records
                            • Transaction history available anytime in the app

                            DEDUCTIBLE EXPENSES (consult your tax advisor):
                            • Mileage or actual vehicle expenses
                            • Phone and data plan (business portion)
                            • Vehicle maintenance and repairs
                            • Insurance premiums (business portion)
                            • Supplies and equipment

                            LEGAL COMPLIANCE:
                            • You are responsible for complying with all local, state, and federal laws
                            • You must maintain appropriate insurance coverage
                            • Vehicle registration and licensing requirements are your responsibility
                            • Dollor AI Service does not provide legal, tax, or insurance advice
                            """)
                        }

                        TermsSection(title: "10. Termination") {
                            Text("""
                            Either party may terminate this agreement at any time. Dollor AI Service may suspend or terminate your account for:

                            • Violation of these Terms
                            • Fraudulent activity
                            • Unsafe driving practices
                            • Poor rider ratings
                            • Illegal activity
                            • Harassment or inappropriate conduct

                            Upon termination, any pending earnings will be paid according to our standard payment schedule.
                            """)
                        }

                        TermsSection(title: "11. Contact & Legal Information") {
                            Text("""
                            For questions about these Terms, please contact us:

                            Platform Support: support@dollor.ai
                            Website: www.dollor.ai
                            Privacy Policy: www.dollor.ai/privacy
                            Terms of Service: www.dollor.ai/terms

                            LEGAL NOTICE:
                            Dollor AI Service is a peer-to-peer matchmaking platform.
                            We do NOT provide transportation services.
                            Drivers using our platform are independent contractors.

                            Effective Date: December 9, 2024
                            Version: 2.0 (P2P Matchmaking Model)
                            """)
                        }
                    }
                }
                .padding()
            }
            .background(Theme.lxBg.ignoresSafeArea())
            .navigationTitle("Full Terms & Conditions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(Theme.lxOrange)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct TermsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundColor(Theme.lxOrange)

            content
                .font(.subheadline)
                .foregroundColor(Theme.lxTextSecondary)
        }
    }
}

#Preview {
    TermsAndConditionsView()
}
