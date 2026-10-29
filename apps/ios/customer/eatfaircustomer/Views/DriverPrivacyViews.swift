import SwiftUI
import EatFairShared

/// Driver Privacy Views - Uber Eats style transparency screens
/// Shows what information is shared with drivers to protect customer privacy
/// Matches Android's DriverPrivacyScreens.kt for platform parity

// MARK: - What Drivers See Page
struct WhatDriversSeePage: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.lxBg.edgesIgnoringSafeArea(.all)

            ScrollView {
                VStack(spacing: 25) {
                    // Header
                    VStack(spacing: 15) {
                        ZStack {
                            Circle()
                                .fill(Theme.lxOrange.opacity(0.15))
                                .frame(width: 80, height: 80)

                            Image(systemName: "eye.fill")
                                .font(Lx.Typography.icon)
                                .foregroundColor(Theme.lxOrange)
                        }

                        Text("What Drivers See")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.lxText)

                        Text("We only share what's necessary for your ride")
                            .font(.subheadline)
                            .foregroundColor(Theme.lxTextSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .padding(.top, 30)

                    // What Drivers CAN See Section
                    VStack(alignment: .leading, spacing: 0) {
                        Text("DRIVERS CAN SEE")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.lxTextSecondary)
                            .padding(.leading, 20)
                            .padding(.bottom, 10)

                        VStack(spacing: 0) {
                            PrivacyInfoRow(
                                icon: "person.fill",
                                title: "Your First Name Only",
                                subtitle: "Last name is hidden",
                                iconColor: Theme.lxOrange
                            )
                            Rectangle().fill(Theme.lxHairline).frame(height: 1).padding(.leading, 60)
                            PrivacyInfoRow(
                                icon: "phone.fill",
                                title: "Phone Number",
                                subtitle: "Shared only for calls during an active ride",
                                iconColor: Theme.lxOrange
                            )
                            Rectangle().fill(Theme.lxHairline).frame(height: 1).padding(.leading, 60)
                            PrivacyInfoRow(
                                icon: "mappin.circle.fill",
                                title: "Pickup Address",
                                subtitle: "Only during active ride",
                                iconColor: Theme.lxOrange
                            )
                            Rectangle().fill(Theme.lxHairline).frame(height: 1).padding(.leading, 60)
                            PrivacyInfoRow(
                                icon: "bag.fill",
                                title: "Trip Details",
                                subtitle: "Your pickup and dropoff",
                                iconColor: Theme.lxOrange
                            )
                            Rectangle().fill(Theme.lxHairline).frame(height: 1).padding(.leading, 60)
                            PrivacyInfoRow(
                                icon: "doc.text.fill",
                                title: "Ride Instructions",
                                subtitle: "Any notes you provide",
                                iconColor: Theme.lxOrange
                            )
                        }
                        .background(Theme.lxSurface)
                        .cornerRadius(Lx.Radius.button)
                        .overlay(
                            RoundedRectangle(cornerRadius: Lx.Radius.button)
                                .stroke(Theme.lxHairline, lineWidth: 1)
                        )
                        .shadow(color: Lx.Palette.shadow.opacity(0.3), radius: 5, x: 0, y: 2)
                    }
                    .padding(.horizontal)

                    // What Drivers CANNOT See Section
                    VStack(alignment: .leading, spacing: 0) {
                        Text("DRIVERS CANNOT SEE")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.lxTextSecondary)
                            .padding(.leading, 20)
                            .padding(.bottom, 10)

                        VStack(spacing: 0) {
                            PrivacyInfoRow(
                                icon: "person.text.rectangle.fill",
                                title: "Your Full Name",
                                subtitle: "Last name stays private",
                                iconColor: Theme.lxError
                            )
                            Rectangle().fill(Theme.lxHairline).frame(height: 1).padding(.leading, 60)
                            PrivacyInfoRow(
                                icon: "phone.badge.plus",
                                title: "Phone Number",
                                subtitle: "Shared only during an active ride",
                                iconColor: Theme.lxError
                            )
                            Rectangle().fill(Theme.lxHairline).frame(height: 1).padding(.leading, 60)
                            PrivacyInfoRow(
                                icon: "envelope.fill",
                                title: "Email Address",
                                subtitle: "Never shared with drivers",
                                iconColor: Theme.lxError
                            )
                            Rectangle().fill(Theme.lxHairline).frame(height: 1).padding(.leading, 60)
                            PrivacyInfoRow(
                                icon: "creditcard.fill",
                                title: "Payment Information",
                                subtitle: "Securely processed by Stripe",
                                iconColor: Theme.lxError
                            )
                            Rectangle().fill(Theme.lxHairline).frame(height: 1).padding(.leading, 60)
                            PrivacyInfoRow(
                                icon: "clock.fill",
                                title: "Ride History",
                                subtitle: "Past rides stay private",
                                iconColor: Theme.lxError
                            )
                        }
                        .background(Theme.lxSurface)
                        .cornerRadius(Lx.Radius.button)
                        .overlay(
                            RoundedRectangle(cornerRadius: Lx.Radius.button)
                                .stroke(Theme.lxHairline, lineWidth: 1)
                        )
                        .shadow(color: Lx.Palette.shadow.opacity(0.3), radius: 5, x: 0, y: 2)
                    }
                    .padding(.horizontal)

                    Spacer().frame(height: 30)
                }
            }
        }
        .preferredColorScheme(.dark)
        .navigationTitle("What Drivers See")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Your Privacy Page
struct YourPrivacyPage: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.lxBg.edgesIgnoringSafeArea(.all)

            ScrollView {
                VStack(spacing: 25) {
                    // Header
                    VStack(spacing: 15) {
                        ZStack {
                            Circle()
                                .fill(Theme.lxOrange.opacity(0.15))
                                .frame(width: 80, height: 80)

                            Image(systemName: "lock.shield.fill")
                                .font(Lx.Typography.icon)
                                .foregroundColor(Theme.lxOrange)
                        }

                        Text("Your Privacy")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.lxText)

                        Text("How we protect your personal information")
                            .font(.subheadline)
                            .foregroundColor(Theme.lxTextSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .padding(.top, 30)

                    // Privacy Protections Section
                    VStack(alignment: .leading, spacing: 0) {
                        Text("PRIVACY PROTECTIONS")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.lxTextSecondary)
                            .padding(.leading, 20)
                            .padding(.bottom, 10)

                        VStack(spacing: 0) {
                                                        PrivacyFeatureRow(
                                icon: "location.slash.fill",
                                title: "Address Protection",
                                description: "Drivers only see your address during active rides. It's hidden before and after."
                            )
                            Rectangle().fill(Theme.lxHairline).frame(height: 1).padding(.leading, 60)
                            PrivacyFeatureRow(
                                icon: "key.fill",
                                title: "Encrypted Data",
                                description: "All your personal information is encrypted using industry-standard TLS/SSL."
                            )
                            Rectangle().fill(Theme.lxHairline).frame(height: 1).padding(.leading, 60)
                            PrivacyFeatureRow(
                                icon: "trash.slash.fill",
                                title: "Data Deletion Rights",
                                description: "You can delete your account and all associated data at any time from Settings."
                            )
                        }
                        .background(Theme.lxSurface)
                        .cornerRadius(Lx.Radius.button)
                        .overlay(
                            RoundedRectangle(cornerRadius: Lx.Radius.button)
                                .stroke(Theme.lxHairline, lineWidth: 1)
                        )
                        .shadow(color: Lx.Palette.shadow.opacity(0.3), radius: 5, x: 0, y: 2)
                    }
                    .padding(.horizontal)

                    // California Privacy Rights Section
                    VStack(alignment: .leading, spacing: 0) {
                        Text("CALIFORNIA PRIVACY RIGHTS (CCPA)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.lxTextSecondary)
                            .padding(.leading, 20)
                            .padding(.bottom, 10)

                        VStack(spacing: 0) {
                            PrivacyRightRow(icon: "doc.text.magnifyingglass", title: "Right to Know", description: "Request what data we collect")
                            Rectangle().fill(Theme.lxHairline).frame(height: 1).padding(.leading, 60)
                            PrivacyRightRow(icon: "trash.fill", title: "Right to Delete", description: "Request deletion of your data")
                            Rectangle().fill(Theme.lxHairline).frame(height: 1).padding(.leading, 60)
                            PrivacyRightRow(icon: "hand.raised.slash.fill", title: "Right to Opt-Out", description: "We don't sell your data")
                            Rectangle().fill(Theme.lxHairline).frame(height: 1).padding(.leading, 60)
                            PrivacyRightRow(icon: "equal.circle.fill", title: "Non-Discrimination", description: "Equal service for all choices")
                        }
                        .background(Theme.lxSurface)
                        .cornerRadius(Lx.Radius.button)
                        .overlay(
                            RoundedRectangle(cornerRadius: Lx.Radius.button)
                                .stroke(Theme.lxHairline, lineWidth: 1)
                        )
                        .shadow(color: Lx.Palette.shadow.opacity(0.3), radius: 5, x: 0, y: 2)
                    }
                    .padding(.horizontal)

                    // Contact Section
                    VStack(alignment: .leading, spacing: 0) {
                        Text("QUESTIONS?")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.lxTextSecondary)
                            .padding(.leading, 20)
                            .padding(.bottom, 10)

                        HStack {
                            Image(systemName: "envelope.fill")
                                .foregroundColor(Theme.lxOrange)
                                .font(.title3)
                                .frame(width: 30)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Contact Privacy Team")
                                    .font(.body)
                                    .foregroundColor(Theme.lxText)
                                Text("privacy@dollor.ai")
                                    .font(.caption)
                                    .foregroundColor(Theme.lxTextSecondary)
                            }

                            Spacer()
                        }
                        .padding()
                        .background(Theme.lxSurface)
                        .cornerRadius(Lx.Radius.button)
                        .overlay(
                            RoundedRectangle(cornerRadius: Lx.Radius.button)
                                .stroke(Theme.lxHairline, lineWidth: 1)
                        )
                        .shadow(color: Lx.Palette.shadow.opacity(0.3), radius: 5, x: 0, y: 2)
                    }
                    .padding(.horizontal)

                    Spacer().frame(height: 30)
                }
            }
        }
        .preferredColorScheme(.dark)
        .navigationTitle("Your Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Safety Features Page
struct SafetyFeaturesPage: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.lxBg.edgesIgnoringSafeArea(.all)

            ScrollView {
                VStack(spacing: 25) {
                    // Header
                    VStack(spacing: 15) {
                        ZStack {
                            Circle()
                                .fill(Theme.lxOrange.opacity(0.15))
                                .frame(width: 80, height: 80)

                            Image(systemName: "checkmark.shield.fill")
                                .font(Lx.Typography.icon)
                                .foregroundColor(Theme.lxOrange)
                        }

                        Text("Safety Features")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.lxText)

                        Text("Your safety is our top priority")
                            .font(.subheadline)
                            .foregroundColor(Theme.lxTextSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .padding(.top, 30)

                    // Safety Features Section
                    VStack(alignment: .leading, spacing: 0) {
                        Text("SAFETY MEASURES")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.lxTextSecondary)
                            .padding(.leading, 20)
                            .padding(.bottom, 10)

                        VStack(spacing: 0) {
                            SafetyFeatureRow(
                                icon: "person.badge.shield.checkmark.fill",
                                title: "Verified Drivers",
                                description: "Drivers must submit their license and insurance and complete a background check (through Checkr) before they can go online.",
                                iconColor: Theme.lxOrange
                            )
                            Rectangle().fill(Theme.lxHairline).frame(height: 1).padding(.leading, 60)
                            SafetyFeatureRow(
                                icon: "location.fill.viewfinder",
                                title: "Real-Time GPS Tracking",
                                description: "Track your ride live on the map with accurate ETA.",
                                iconColor: Theme.lxOrange
                            )
                            Rectangle().fill(Theme.lxHairline).frame(height: 1).padding(.leading, 60)
                            SafetyFeatureRow(
                                icon: "square.and.arrow.up.fill",
                                title: "Share Trip Status",
                                description: "Share your live trip details with friends and family.",
                                iconColor: Theme.lxOrange
                            )
                            Rectangle().fill(Theme.lxHairline).frame(height: 1).padding(.leading, 60)
                            SafetyFeatureRow(
                                icon: "star.fill",
                                title: "Two-Way Ratings",
                                description: "Both customers and drivers rate each other for accountability.",
                                iconColor: Theme.gold
                            )
                        }
                        .background(Theme.lxSurface)
                        .cornerRadius(Lx.Radius.button)
                        .overlay(
                            RoundedRectangle(cornerRadius: Lx.Radius.button)
                                .stroke(Theme.lxHairline, lineWidth: 1)
                        )
                        .shadow(color: Lx.Palette.shadow.opacity(0.3), radius: 5, x: 0, y: 2)
                    }
                    .padding(.horizontal)

                    // Emergency Support Section
                    VStack(alignment: .leading, spacing: 0) {
                        Text("EMERGENCY SUPPORT")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.lxTextSecondary)
                            .padding(.leading, 20)
                            .padding(.bottom, 10)

                        VStack(spacing: 0) {
                            SafetyFeatureRow(
                                icon: "phone.fill",
                                title: "Support",
                                description: "Contact our support team from Help & Support.",
                                iconColor: Theme.lxOrange
                            )
                            Rectangle().fill(Theme.lxHairline).frame(height: 1).padding(.leading, 60)
                            SafetyFeatureRow(
                                icon: "exclamationmark.triangle.fill",
                                title: "In-App Emergency Button",
                                description: "Quick access to emergency services during active trips.",
                                iconColor: Theme.lxError
                            )
                            Rectangle().fill(Theme.lxHairline).frame(height: 1).padding(.leading, 60)
                            SafetyFeatureRow(
                                icon: "text.bubble.fill",
                                title: "Report Issues",
                                description: "Report safety concerns directly through the app.",
                                iconColor: Theme.lxOrange
                            )
                        }
                        .background(Theme.lxSurface)
                        .cornerRadius(Lx.Radius.button)
                        .overlay(
                            RoundedRectangle(cornerRadius: Lx.Radius.button)
                                .stroke(Theme.lxHairline, lineWidth: 1)
                        )
                        .shadow(color: Lx.Palette.shadow.opacity(0.3), radius: 5, x: 0, y: 2)
                    }
                    .padding(.horizontal)

                    // Trust Badge Section
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "building.columns.fill")
                                .foregroundColor(Theme.lxOrange)
                            Text("Compliant with US Transportation Regulations")
                                .font(.caption)
                                .foregroundColor(Theme.lxTextSecondary)
                        }

                        HStack {
                            Image(systemName: "lock.shield.fill")
                                .foregroundColor(Theme.lxOrange)
                            Text("SOC 2 Type II Certified")
                                .font(.caption)
                                .foregroundColor(Theme.lxTextSecondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Theme.lxSurface)
                    .cornerRadius(Lx.Radius.button)
                    .overlay(
                        RoundedRectangle(cornerRadius: Lx.Radius.button)
                            .stroke(Theme.lxHairline, lineWidth: 1)
                    )
                    .padding(.horizontal)

                    Spacer().frame(height: 30)
                }
            }
        }
        .preferredColorScheme(.dark)
        .navigationTitle("Safety Features")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Helper Views

struct PrivacyInfoRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let iconColor: Color

    var body: some View {
        HStack(alignment: .center, spacing: 15) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .font(.title3)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundColor(Theme.lxText)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(Theme.lxTextSecondary)
            }

            Spacer()
        }
        .padding()
    }
}

struct PrivacyFeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: icon)
                .foregroundColor(Theme.lxOrange)
                .font(.title3)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(Theme.lxText)
                Text(description)
                    .font(.caption)
                    .foregroundColor(Theme.lxTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding()
    }
}

struct PrivacyRightRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .center, spacing: 15) {
            Image(systemName: icon)
                .foregroundColor(Theme.lxOrange)
                .font(.title3)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundColor(Theme.lxText)
                Text(description)
                    .font(.caption)
                    .foregroundColor(Theme.lxTextSecondary)
            }

            Spacer()
        }
        .padding()
    }
}

struct SafetyFeatureRow: View {
    let icon: String
    let title: String
    let description: String
    let iconColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .font(.title3)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(Theme.lxText)
                Text(description)
                    .font(.caption)
                    .foregroundColor(Theme.lxTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding()
    }
}

// MARK: - Previews
#Preview("What Drivers See") {
    NavigationView {
        WhatDriversSeePage()
    }
}

#Preview("Your Privacy") {
    NavigationView {
        YourPrivacyPage()
    }
}

#Preview("Safety Features") {
    NavigationView {
        SafetyFeaturesPage()
    }
}
