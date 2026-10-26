import SwiftUI
import EatFairShared

/// ReferAndEarnView - Referral program screen
/// Matches Android's ReferAndEarnScreen for platform parity
struct ReferAndEarnView: View {
    @State private var referralCode = ""
    @State private var showShareSheet = false
    @State private var copiedToClipboard = false

    var body: some View {
        ZStack {
            Theme.lxBg.edgesIgnoringSafeArea(.all)

            ScrollView {
                VStack(spacing: 25) {
                    // Header Card
                    VStack(spacing: 15) {
                        Image(systemName: "gift.fill")
                            .font(Lx.Typography.iconHero)
                            .foregroundColor(Theme.lxOrange)

                        Text("Refer Friends, Earn Rewards")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.lxText)

                        Text("Share Dollor.ai with friends and both of you earn credits!")
                            .font(.subheadline)
                            .foregroundColor(Theme.lxTextSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.vertical, 30)
                    .frame(maxWidth: .infinity)
                    .background(Theme.lxSurface)
                    .cornerRadius(Lx.Radius.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: Lx.Radius.card)
                            .stroke(Theme.lxHairline, lineWidth: 1)
                    )
                    .padding(.horizontal)

                    // Referral Code Card
                    VStack(spacing: 15) {
                        Text("YOUR REFERRAL CODE")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.lxTextSecondary)

                        HStack {
                            Text(referralCode.isEmpty ? "LOADING..." : referralCode)
                                .font(Lx.Typography.title.weight(.bold))
                                .foregroundColor(Theme.lxText)

                            Spacer()

                            Button(action: copyCode) {
                                Image(systemName: copiedToClipboard ? "checkmark" : "doc.on.doc")
                                    .foregroundColor(copiedToClipboard ? Theme.lxSuccess : Theme.lxOrange)
                                    .font(.title3)
                            }
                        }
                        .padding()
                        .background(Theme.lxSurface2)
                        .cornerRadius(Lx.Radius.button)
                        .overlay(
                            RoundedRectangle(cornerRadius: Lx.Radius.button)
                                .stroke(Theme.lxHairline, lineWidth: 1)
                        )

                        // Share Buttons
                        HStack(spacing: 15) {
                            Button(action: { showShareSheet = true }) {
                                HStack {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Share")
                                }
                                .font(.headline)
                                .foregroundColor(Lx.Palette.onAccent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Theme.lxButtonGradient)
                                .cornerRadius(Lx.Radius.button)
                                .shadow(color: Theme.lxOrange.opacity(0.4), radius: 14, x: 0, y: 6)
                            }

                            Button(action: copyCode) {
                                HStack {
                                    Image(systemName: "doc.on.doc")
                                    Text("Copy")
                                }
                                .font(.headline)
                                .foregroundColor(Theme.lxOrange)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Theme.lxSurface2)
                                .cornerRadius(Lx.Radius.button)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Lx.Radius.button)
                                        .stroke(Theme.lxOrange, lineWidth: 2)
                                )
                            }
                        }
                    }
                    .padding(20)
                    .background(Theme.lxSurface)
                    .cornerRadius(Lx.Radius.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: Lx.Radius.card)
                            .stroke(Theme.lxHairline, lineWidth: 1)
                    )
                    .padding(.horizontal)

                    // How It Works Section
                    VStack(alignment: .leading, spacing: 15) {
                        Text("HOW IT WORKS")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.lxTextSecondary)

                        VStack(spacing: 0) {
                            HowItWorksRow(
                                step: "1",
                                title: "Share Your Code",
                                description: "Send your unique code to friends",
                                isLast: false
                            )

                            HowItWorksRow(
                                step: "2",
                                title: "Friend Signs Up",
                                description: "They create an account with your code",
                                isLast: false
                            )

                            HowItWorksRow(
                                step: "3",
                                title: "Friend Orders",
                                description: "They place their first order",
                                isLast: false
                            )

                            HowItWorksRow(
                                step: "4",
                                title: "Both Earn Credits",
                                description: "You both get $5 in credits!",
                                isLast: true
                            )
                        }
                        .background(Theme.lxSurface)
                        .cornerRadius(Lx.Radius.button)
                        .overlay(
                            RoundedRectangle(cornerRadius: Lx.Radius.button)
                                .stroke(Theme.lxHairline, lineWidth: 1)
                        )
                    }
                    .padding(.horizontal)

                    // Terms
                    Text("Referral credits expire 90 days after issue. Terms apply.")
                        .font(.caption)
                        .foregroundColor(Theme.lxTextMuted)
                        .padding(.horizontal)
                        .padding(.bottom, 30)
                }
                .padding(.top, 20)
            }
        }
        .preferredColorScheme(.dark)
        .navigationTitle("Refer & Earn")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadReferralData()
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [
                "Join me on Dollor.ai! Use my code \(referralCode)\(AppConfig.shared.referralRewardText.map { " to get \($0)" } ?? ""). Download now: \(AppConstants.appDownloadURL)"
            ])
        }
    }

    private func loadReferralData() {
        // Generate or fetch referral code
        if let customerId = UserDefaults.standard.string(forKey: "p2p_customer_id") {
            referralCode = "DOLLOR\(customerId.prefix(4).uppercased())"
        }
    }

    private func copyCode() {
        UIPasteboard.general.string = referralCode
        copiedToClipboard = true

        // Reset after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedToClipboard = false
        }
    }
}

// MARK: - Stat Card Component
struct StatCard: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(Theme.lxOrange)

            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(Theme.lxText)

            Text(label)
                .font(.caption)
                .foregroundColor(Theme.lxTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Theme.lxSurface)
        .cornerRadius(Lx.Radius.button)
        .overlay(
            RoundedRectangle(cornerRadius: Lx.Radius.button)
                .stroke(Theme.lxHairline, lineWidth: 1)
        )
    }
}

// MARK: - How It Works Row
struct HowItWorksRow: View {
    let step: String
    let title: String
    let description: String
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            // Step indicator
            VStack {
                ZStack {
                    Circle()
                        .fill(Theme.lxOrange)
                        .frame(width: 30, height: 30)

                    Text(step)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(Lx.Palette.onAccent)
                }

                if !isLast {
                    Rectangle()
                        .fill(Theme.lxOrange.opacity(0.3))
                        .frame(width: 2, height: 30)
                }
            }

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
            .padding(.bottom, isLast ? 0 : 10)

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}

// MARK: - Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationView {
        ReferAndEarnView()
    }
}
