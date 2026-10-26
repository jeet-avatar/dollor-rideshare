import SwiftUI
import FirebaseAuth
import EatFairShared

/// SettingsView - Dedicated settings screen
/// Matches Android's SettingsScreen for platform parity
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authViewModel: AuthViewModel
    @AppStorage("app_selected_language") private var selectedLanguage = "English"
    @AppStorage("notifications_enabled") private var notificationsEnabled = true
    @AppStorage("email_notifications") private var emailNotifications = true
    @AppStorage("push_notifications") private var pushNotifications = true

    @State private var showLanguageSheet = false
    @State private var showDeleteAccountAlert = false
    @State private var showDeleteConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteError: String?
    @State private var showBugReport = false

    private let availableLanguages = ["English", "Spanish", "French", "Chinese", "Hindi"]

    var body: some View {
        ZStack {
            Theme.brandGrey.edgesIgnoringSafeArea(.all)

            ScrollView {
                VStack(spacing: 25) {
                    // Notifications Section
                    VStack(alignment: .leading, spacing: 0) {
                        Text("NOTIFICATIONS")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.textGrey)
                            .padding(.leading, 20)
                            .padding(.bottom, 10)

                        VStack(spacing: 0) {
                            SettingsToggleRow(
                                icon: "bell.fill",
                                title: "Push Notifications",
                                isOn: $pushNotifications
                            )
                            Divider().padding(.leading, 60)
                            SettingsToggleRow(
                                icon: "envelope.fill",
                                title: "Email Notifications",
                                isOn: $emailNotifications
                            )
                        }
                        .background(Lx.Palette.surface)
                        .cornerRadius(Lx.Radius.button)
                        .shadow(color: Lx.Palette.shadow.opacity(0.05), radius: 5, x: 0, y: 2)
                    }
                    .padding(.horizontal)

                    // Preferences Section
                    VStack(alignment: .leading, spacing: 0) {
                        Text("PREFERENCES")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.textGrey)
                            .padding(.leading, 20)
                            .padding(.bottom, 10)

                        VStack(spacing: 0) {
                            Button(action: { showLanguageSheet = true }) {
                                HStack {
                                    Image(systemName: "globe")
                                        .foregroundColor(Theme.brandOrange)
                                        .font(.title3)
                                        .frame(width: 30)

                                    Text("Language")
                                        .font(.body)
                                        .foregroundColor(Theme.brandBlack)

                                    Spacer()

                                    Text(selectedLanguage)
                                        .font(.subheadline)
                                        .foregroundColor(Lx.Palette.textMuted)

                                    Image(systemName: "chevron.right")
                                        .foregroundColor(Lx.Palette.textMuted)
                                        .font(.caption)
                                }
                                .padding()
                            }
                        }
                        .background(Lx.Palette.surface)
                        .cornerRadius(Lx.Radius.button)
                        .shadow(color: Lx.Palette.shadow.opacity(0.05), radius: 5, x: 0, y: 2)
                    }
                    .padding(.horizontal)

                    // Legal Section
                    VStack(alignment: .leading, spacing: 0) {
                        Text("LEGAL")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.textGrey)
                            .padding(.leading, 20)
                            .padding(.bottom, 10)

                        VStack(spacing: 0) {
                            NavigationLink(destination: PrivacyPolicyView()) {
                                SettingsOptionRow(icon: "lock.shield.fill", title: "Privacy Policy")
                            }
                            Divider().padding(.leading, 60)
                            NavigationLink(destination: TermsOfServiceView()) {
                                SettingsOptionRow(icon: "doc.text.fill", title: "Terms & Conditions")
                            }
                        }
                        .background(Lx.Palette.surface)
                        .cornerRadius(Lx.Radius.button)
                        .shadow(color: Lx.Palette.shadow.opacity(0.05), radius: 5, x: 0, y: 2)
                    }
                    .padding(.horizontal)

                    // Support Section
                    VStack(alignment: .leading, spacing: 0) {
                        Text("SUPPORT")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.textGrey)
                            .padding(.leading, 20)
                            .padding(.bottom, 10)

                        VStack(spacing: 0) {
                            Button(action: { showBugReport = true }) {
                                SettingsOptionRow(icon: "ladybug.fill", title: "Report a Bug")
                            }
                            Divider().padding(.leading, 60)
                            NavigationLink(destination: HelpSupportView()) {
                                SettingsOptionRow(icon: "questionmark.circle.fill", title: "Help Center")
                            }
                        }
                        .background(Lx.Palette.surface)
                        .cornerRadius(Lx.Radius.button)
                        .shadow(color: Lx.Palette.shadow.opacity(0.05), radius: 5, x: 0, y: 2)
                    }
                    .padding(.horizontal)

                    // App Info Section
                    VStack(alignment: .leading, spacing: 0) {
                        Text("ABOUT")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.textGrey)
                            .padding(.leading, 20)
                            .padding(.bottom, 10)

                        VStack(spacing: 0) {
                            HStack {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(Theme.brandOrange)
                                    .font(.title3)
                                    .frame(width: 30)

                                Text("App Version")
                                    .font(.body)
                                    .foregroundColor(Theme.brandBlack)

                                Spacer()

                                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                                    .font(.subheadline)
                                    .foregroundColor(Lx.Palette.textMuted)
                            }
                            .padding()
                        }
                        .background(Lx.Palette.surface)
                        .cornerRadius(Lx.Radius.button)
                        .shadow(color: Lx.Palette.shadow.opacity(0.05), radius: 5, x: 0, y: 2)
                    }
                    .padding(.horizontal)

                    // Danger Zone - Delete Account
                    VStack(alignment: .leading, spacing: 0) {
                        Text("DANGER ZONE")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(Lx.Palette.error)
                            .padding(.leading, 20)
                            .padding(.bottom, 10)

                        Button(action: { showDeleteAccountAlert = true }) {
                            HStack {
                                if isDeletingAccount {
                                    ProgressView()
                                        .tint(Lx.Palette.error)
                                        .frame(width: 30)
                                } else {
                                    Image(systemName: "trash.fill")
                                        .foregroundColor(Lx.Palette.error)
                                        .font(.title3)
                                        .frame(width: 30)
                                }

                                Text("Delete Account")
                                    .font(.body)
                                    .foregroundColor(Lx.Palette.error)

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .foregroundColor(.red.opacity(0.5))
                                    .font(.caption)
                            }
                            .padding()
                        }
                        .disabled(isDeletingAccount)
                        .background(Lx.Palette.error.opacity(0.1))
                        .cornerRadius(Lx.Radius.button)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 30)
                }
                .padding(.top, 20)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showLanguageSheet) {
            LanguageSettingsSheet(selectedLanguage: $selectedLanguage, languages: availableLanguages)
        }
        .sheet(isPresented: $showBugReport) {
            BugReportView()
        }
        .alert("Delete Account?", isPresented: $showDeleteAccountAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Continue", role: .destructive) {
                showDeleteConfirmation = true
            }
        } message: {
            Text("This will permanently delete your account, including all your ride history, saved addresses, and payment methods. This action cannot be undone.")
        }
        .alert("Final Confirmation", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete Forever", role: .destructive) {
                performAccountDeletion()
            }
        } message: {
            Text("Are you absolutely sure? Your account and all associated data will be permanently deleted.")
        }
        .alert("Error", isPresented: .constant(deleteError != nil)) {
            Button("OK") { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
    }

    private func performAccountDeletion() {
        isDeletingAccount = true
        let customerId = UserDefaults.standard.integer(forKey: "p2p_customer_id")

        guard customerId > 0 else {
            deleteError = "Unable to identify account. Please try logging out and back in."
            isDeletingAccount = false
            return
        }

        P2PAPIService.shared.deleteCustomerAccount(customerId: customerId) { result in
            DispatchQueue.main.async {
                self.isDeletingAccount = false
                switch result {
                case .success:
                    clearAllLocalData()
                    try? Auth.auth().signOut()
                    authViewModel.logout()
                case .failure(let error):
                    deleteError = "Failed to delete account: \(error.localizedDescription)"
                }
            }
        }
    }

    private func clearAllLocalData() {
        let customerKeys = [
            "p2p_customer_id", "p2p_customer_name", "p2p_customer_email",
            "p2p_customer_access_token", "p2p_access_token",
            "saved_addresses", "favorites"
        ]
        for key in customerKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        UserDefaults.standard.synchronize()
        SecureStorage.shared.clearAuthTokens(type: .customer)
    }
}

// MARK: - Settings Toggle Row
struct SettingsToggleRow: View {
    let icon: String
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(Theme.brandOrange)
                .font(.title3)
                .frame(width: 30)

            Text(title)
                .font(.body)
                .foregroundColor(Theme.brandBlack)

            Spacer()

            Toggle("", isOn: $isOn)
                .tint(Theme.brandOrange)
        }
        .padding()
    }
}

// MARK: - Settings Option Row
struct SettingsOptionRow: View {
    let icon: String
    let title: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(Theme.brandOrange)
                .font(.title3)
                .frame(width: 30)

            Text(title)
                .font(.body)
                .foregroundColor(Theme.brandBlack)

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(Lx.Palette.textMuted)
                .font(.caption)
        }
        .padding()
    }
}

// MARK: - Language Settings Sheet
struct LanguageSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedLanguage: String
    let languages: [String]
    @State private var showRestartAlert = false

    private let languageCodes: [String: String] = [
        "English": "en", "Spanish": "es", "French": "fr",
        "Chinese": "zh-Hans", "Hindi": "hi"
    ]

    var body: some View {
        NavigationView {
            List(languages, id: \.self) { language in
                Button(action: {
                    if language != selectedLanguage {
                        selectedLanguage = language
                        saveLanguagePreference(language)
                        showRestartAlert = true
                    }
                }) {
                    HStack {
                        Text(language)
                            .foregroundColor(Theme.brandBlack)
                        Spacer()
                        if language == selectedLanguage {
                            Image(systemName: "checkmark")
                                .foregroundColor(Theme.brandOrange)
                        }
                    }
                }
            }
            .navigationTitle("Select Language")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Language Changed", isPresented: $showRestartAlert) {
                Button("OK") { dismiss() }
            } message: {
                Text("Please restart the app for the language change to take effect.")
            }
        }
    }

    private func saveLanguagePreference(_ language: String) {
        UserDefaults.standard.set(language, forKey: "app_selected_language")
        if let code = languageCodes[language] {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()
    }
}

// MARK: - Bug Report View
struct BugReportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var bugDescription = ""
    @State private var isSubmitting = false
    @State private var showSuccess = false

    var body: some View {
        NavigationView {
            Form {
                Section("Describe the issue") {
                    TextEditor(text: $bugDescription)
                        .frame(minHeight: 150)
                }

                Section {
                    Text("Include as much detail as possible: what you were trying to do, what happened, and any error messages you saw.")
                        .font(.caption)
                        .foregroundColor(Lx.Palette.textSecondary)
                }

                Section {
                    Button(action: submitBugReport) {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text("Submit Report")
                        }
                    }
                    .disabled(bugDescription.isEmpty || isSubmitting)
                }
            }
            .navigationTitle("Report a Bug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Report Submitted", isPresented: $showSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text("Thank you for your feedback! We'll review your report.")
            }
        }
    }

    private func submitBugReport() {
        isSubmitting = true
        // Simulate submission
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isSubmitting = false
            showSuccess = true
        }
    }
}

// MARK: - Privacy Policy View
struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Privacy Policy")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Last Updated: December 2024")
                    .font(.caption)
                    .foregroundColor(Lx.Palette.textSecondary)

                Group {
                    PolicySection(title: "Information We Collect", content: """
                    We collect information you provide directly, such as:
                    • Account information (name, email, phone)
                    • Pickup and dropoff addresses
                    • Payment information (processed securely via Stripe)
                    • Ride history
                    """)

                    PolicySection(title: "How We Use Your Information", content: """
                    Your information is used to:
                    • Process and complete your rides
                    • Connect you with independent drivers
                    • Improve our services
                    • Send ride updates and promotions
                    """)

                    PolicySection(title: "Information Sharing", content: """
                    We share limited information with:
                    • Independent drivers for your rides
                    • Payment processors (Stripe)

                    We never sell your personal information.
                    """)

                    PolicySection(title: "Data Security", content: """
                    We use industry-standard security measures including:
                    • Encrypted data transmission (TLS)
                    • Secure payment processing
                    • Regular security audits
                    """)

                    PolicySection(title: "Your Rights", content: """
                    You have the right to:
                    • Access your data
                    • Request data deletion
                    • Opt out of marketing
                    • Update your information
                    """)
                }
            }
            .padding()
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Terms of Service View
struct TermsOfServiceView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Terms of Service")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Last Updated: December 2024")
                    .font(.caption)
                    .foregroundColor(Lx.Palette.textSecondary)

                Group {
                    PolicySection(title: "Acceptance of Terms", content: """
                    By using Dollor.ai, you agree to these terms. If you disagree, please do not use our services.
                    """)

                    PolicySection(title: "Platform Description", content: """
                    Dollor.ai is a matchmaking platform that connects:
                    • Riders with independent drivers

                    We do not employ drivers. All drivers are independent contractors.
                    """)

                    PolicySection(title: "User Responsibilities", content: """
                    Users must:
                    • Provide accurate information
                    • Maintain account security
                    • Use the platform lawfully
                    • Treat drivers respectfully
                    """)

                    PolicySection(title: "Platform Fees", content: """
                    Dollor.ai charges transparent platform fees:
                    • Rideshare: Tiered fees ($1-$3 based on fare)

                    100% of tips go directly to drivers.
                    """)

                    PolicySection(title: "Liability Limitations", content: """
                    As a matchmaking platform:
                    • We facilitate connections but don't control service quality
                    • Drivers are independent contractors
                    • We're not liable for driver actions
                    """)
                }
            }
            .padding()
        }
        .navigationTitle("Terms of Service")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Policy Section Component
struct PolicySection: View {
    let title: String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(Theme.brandBlack)

            Text(content)
                .font(.body)
                .foregroundColor(Theme.textGrey)
        }
    }
}

#Preview {
    NavigationView {
        SettingsView()
    }
}
