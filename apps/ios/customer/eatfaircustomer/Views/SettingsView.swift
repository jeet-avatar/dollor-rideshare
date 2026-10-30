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
        .alert("Couldn't Delete Account", isPresented: .constant(deleteError != nil)) {
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
                    deleteError = error.localizedDescription
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
    @State private var fullPolicyURL: URL?

    var body: some View {
        LegalSummaryList(
            effectiveDate: "Effective October 13, 2026",
            sections: [
                LegalSection(title: "Who we are", icon: "building.2", items: [
                    "Dollor.ai is a peer-to-peer rideshare marketplace operated by Zietra Technologies Inc."
                ]),
                LegalSection(title: "Our commitment", icon: "hand.raised", items: [
                    "We do NOT sell your personal information. We do NOT share your information for cross-context behavioral advertising."
                ]),
                LegalSection(title: "What we collect", icon: "list.bullet.rectangle", items: [
                    "Account details such as name, email, and phone number",
                    "Payment details, handled by Stripe (we do not store full card numbers)",
                    "Precise location while the app is in use, to set your pickup point and show nearby drivers",
                    "In-app messages between riders and drivers",
                    "Device, usage, and log data"
                ]),
                LegalSection(title: "Your rights", icon: "person.badge.shield.checkmark", items: [
                    "California residents can know, delete, correct, and limit use of sensitive personal information. Email privacy@dollor.ai. To delete your account, use Profile > Delete Account in the app."
                ])
            ],
            footer: "This is a summary. The full Privacy Policy is the binding text.",
            fullTextTitle: "Read the full Privacy Policy",
            onReadFullText: { fullPolicyURL = URL(string: AppConstants.privacyPolicyURL) }
        )
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
        .inAppBrowser(url: $fullPolicyURL)
    }
}

// MARK: - Terms of Service View
struct TermsOfServiceView: View {
    @State private var fullTermsURL: URL?

    var body: some View {
        LegalSummaryList(
            effectiveDate: "Effective October 29, 2026",
            sections: [
                LegalSection(title: "What Dollor.ai is", icon: "building.2", items: [
                    "Dollor.ai is a peer-to-peer rideshare marketplace for California, operated by Zietra Technologies Inc. (doing business as Dollor.ai) under CPUC Transportation Network Company permit TNC0050982-N. Riders post a ride offer and independent drivers bid on it. Dollor.ai provides the technology that connects them and processes payment. Drivers are independent contractors."
                ]),
                LegalSection(title: "How a ride works", icon: "car", items: [
                    "Your request stays open for bids for 5 minutes.",
                    "You may accept a bid, make a counter-offer, or decline.",
                    "When you accept a bid, your card is authorized through Stripe (not charged) for the agreed fare.",
                    "When the trip is completed, the authorized amount is captured. Tips are optional.",
                    "If the card cannot be authorized at the match, the ride is cancelled."
                ]),
                LegalSection(title: "Fees", icon: "dollarsign.circle", items: [
                    "Connection Fee, charged to the rider and separately to the driver: $1.00 if the fare is $35 or less, $2.00 if over $35 up to $70, $3.00 if over $70.",
                    "CPUC Access for All charge: $0.05 to the rider and $0.05 to the driver.",
                    "100% of tips go to the driver."
                ]),
                LegalSection(title: "Cancellations", icon: "xmark.circle", items: [
                    "Rider cancels before the ride starts: no cancellation fee. You cannot cancel once the trip is in progress.",
                    "Driver cancels after a match: no charge to you, and the request is re-opened to other drivers.",
                    "Rider no-show: after the driver has waited at least 5 minutes at pickup, the driver may mark a no-show and your saved card is charged a $5.00 no-show fee, of which $4.00 (80%) is paid to the driver."
                ]),
                LegalSection(title: "Riders", icon: "person", items: [
                    "You must be at least 18, provide a valid payment card, and provide accurate account information."
                ])
            ],
            footer: "This is a summary. The full Terms of Service, including liability limits and dispute resolution, are the binding text. Questions: support@dollor.ai.",
            fullTextTitle: "Read the full Terms of Service",
            onReadFullText: { fullTermsURL = URL(string: AppConstants.termsOfServiceURL) }
        )
        .navigationTitle("Terms of Service")
        .navigationBarTitleDisplayMode(.inline)
        .inAppBrowser(url: $fullTermsURL)
    }
}

// MARK: - Legal summary list (same grouped-List pattern as the driver app's Driver Terms)

struct LegalSection {
    let title: String
    let icon: String
    let items: [String]
}

struct LegalSummaryList: View {
    let effectiveDate: String
    let sections: [LegalSection]
    let footer: String
    let fullTextTitle: String
    let onReadFullText: () -> Void

    var body: some View {
        List {
            ForEach(sections, id: \.title) { section in
                Section(section.title) {
                    ForEach(section.items, id: \.self) { item in
                        Label {
                            Text(item)
                                .font(Lx.Typography.body)
                                .foregroundColor(Lx.Palette.text)
                        } icon: {
                            Image(systemName: section.icon)
                                .foregroundColor(Lx.Palette.orange)
                        }
                    }
                }
                .listRowBackground(Lx.Palette.surface)
            }

            Section {
                Button(action: onReadFullText) {
                    HStack {
                        Label(fullTextTitle, systemImage: "doc.text")
                            .foregroundColor(Lx.Palette.orange)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(Lx.Typography.caption)
                            .foregroundColor(Lx.Palette.textMuted)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: Lx.Size.buttonHeightCompact)
                    .contentShape(Rectangle())
                }
            } footer: {
                Text("\(footer)\n\n\(effectiveDate)")
            }
            .listRowBackground(Lx.Palette.surface)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Lx.Palette.bg.ignoresSafeArea())
    }
}

#Preview {
    NavigationView {
        SettingsView()
    }
}
