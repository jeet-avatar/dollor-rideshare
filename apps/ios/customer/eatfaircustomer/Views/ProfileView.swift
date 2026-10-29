import SwiftUI
import FirebaseAuth
import EatFairShared

struct ProfileView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var showEditProfile = false
    @State private var showLanguageSheet = false
    @AppStorage("app_selected_language") private var selectedLanguage = "English"

    @State private var showRecurringRides = false

    // Account deletion states (Apple App Store Guideline 5.1.1)
    @State private var showDeleteAccountAlert = false
    @State private var showDeleteConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteError: String?

    private let availableLanguages = ["English", "Spanish", "French", "Chinese", "Hindi"]

    // Use P2P backend data via AuthViewModel
    private var userName: String {
        if !authViewModel.customerName.isEmpty {
            return authViewModel.customerName
        }
        // Fallback to UserDefaults
        if let name = UserDefaults.standard.string(forKey: "p2p_customer_name"), !name.isEmpty {
            return name
        }
        // Last resort - Firebase
        return Auth.auth().currentUser?.displayName ?? "User"
    }

    private var userEmail: String {
        if !authViewModel.customerEmail.isEmpty {
            return authViewModel.customerEmail
        }
        // Fallback to UserDefaults
        if let email = UserDefaults.standard.string(forKey: "p2p_customer_email"), !email.isEmpty {
            return email
        }
        // Last resort - Firebase
        return Auth.auth().currentUser?.email ?? "No Email"
    }

    var body: some View {
        NavigationView {
            ZStack {
                Theme.lxBg.edgesIgnoringSafeArea(.all)

                ScrollView {
                    VStack(spacing: 25) {
                        // Profile Header
                        VStack(spacing: 15) {
                            ZStack {
                                Circle()
                                    .fill(Theme.lxButtonGradient)
                                    .frame(width: 100, height: 100)
                                    .shadow(color: Theme.lxOrange.opacity(0.4), radius: 14, x: 0, y: 6)
                                Text(String(userName.prefix(1)))
                                    .font(Lx.Typography.icon.weight(.bold))
                                    .foregroundColor(Lx.Palette.onAccent)

                                // Edit Badge - Tappable
                                VStack {
                                    Spacer()
                                    HStack {
                                        Spacer()
                                        Button(action: { showEditProfile = true }) {
                                            Image(systemName: "pencil.circle.fill")
                                                .foregroundColor(Theme.lxOrange)
                                                .font(.title)
                                                .background(Theme.lxSurface.clipShape(Circle()))
                                        }
                                        .accessibilityLabel("Edit profile")
                                    }
                                }
                                .frame(width: 100, height: 100)
                            }
                            
                            VStack(spacing: 5) {
                                Text(userName)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(Theme.lxText)

                                Text(userEmail)
                                    .font(.subheadline)
                                    .foregroundColor(Theme.lxTextSecondary)
                            }
                        }
                        .padding(.top, 30)
                        
                        // Account Settings Section
                        VStack(alignment: .leading, spacing: 0) {
                            Text("ACCOUNT")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(Theme.lxTextMuted)
                                .padding(.leading, 20)
                                .padding(.bottom, 10)

                            VStack(spacing: 0) {
                                NavigationLink(destination: AddressListView()) {
                                    ProfileOptionRow(icon: "mappin.circle.fill", title: "Manage Addresses")
                                }
                                Divider().overlay(Theme.lxHairline)
                                NavigationLink(destination: PaymentMethodsView()) {
                                    ProfileOptionRow(icon: "creditcard.fill", title: "Payment Methods")
                                }
                            }
                            .background(Theme.lxSurface)
                            .cornerRadius(Lx.Radius.button)
                            .overlay(
                                RoundedRectangle(cornerRadius: Lx.Radius.button)
                                    .stroke(Theme.lxHairline, lineWidth: 1)
                            )
                            .shadow(color: Lx.Palette.shadow.opacity(0.25), radius: 5, x: 0, y: 2)
                        }
                        .padding(.horizontal)
                        
                        // App Settings Section
                        VStack(alignment: .leading, spacing: 0) {
                            Text("APP SETTINGS")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(Theme.lxTextMuted)
                                .padding(.leading, 20)
                                .padding(.bottom, 10)

                            VStack(spacing: 0) {
                                NavigationLink(destination: SettingsView()) {
                                    ProfileOptionRow(icon: "gearshape.fill", title: "Settings")
                                }
                                Divider().overlay(Theme.lxHairline)
                                NavigationLink(destination: NotificationsView()) {
                                    ProfileOptionRow(icon: "bell.fill", title: "Notifications")
                                }
                                Divider().overlay(Theme.lxHairline)
                                if AppConfig.shared.referralRewardText != nil {
                                    NavigationLink(destination: ReferAndEarnView()) {
                                        ProfileOptionRow(icon: "gift.fill", title: "Refer & Earn")
                                    }
                                    Divider().overlay(Theme.lxHairline)
                                }
                                NavigationLink(destination: HelpSupportView()) {
                                    ProfileOptionRow(icon: "questionmark.circle.fill", title: "Help & Support")
                                }
                                // Recurring Rides hidden for launch: non-functional (no scheduler
                                // materializes recurring rides yet). Re-enable when the scheduler ships.
                            }
                            .background(Theme.lxSurface)
                            .cornerRadius(Lx.Radius.button)
                            .overlay(
                                RoundedRectangle(cornerRadius: Lx.Radius.button)
                                    .stroke(Theme.lxHairline, lineWidth: 1)
                            )
                            .shadow(color: Lx.Palette.shadow.opacity(0.25), radius: 5, x: 0, y: 2)
                        }
                        .padding(.horizontal)

                        // Privacy & Safety Section - Uber Eats style transparency
                        VStack(alignment: .leading, spacing: 0) {
                            Text("PRIVACY & SAFETY")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(Theme.lxTextMuted)
                                .padding(.leading, 20)
                                .padding(.bottom, 10)

                            VStack(spacing: 0) {
                                NavigationLink(destination: WhatDriversSeePage()) {
                                    ProfileOptionRow(icon: "eye.fill", title: "What Drivers See")
                                }
                                Divider().overlay(Theme.lxHairline)
                                NavigationLink(destination: YourPrivacyPage()) {
                                    ProfileOptionRow(icon: "lock.shield.fill", title: "Your Privacy")
                                }
                                Divider().overlay(Theme.lxHairline)
                                NavigationLink(destination: SafetyFeaturesPage()) {
                                    ProfileOptionRow(icon: "checkmark.shield.fill", title: "Safety Features")
                                }
                            }
                            .background(Theme.lxSurface)
                            .cornerRadius(Lx.Radius.button)
                            .overlay(
                                RoundedRectangle(cornerRadius: Lx.Radius.button)
                                    .stroke(Theme.lxHairline, lineWidth: 1)
                            )
                            .shadow(color: Lx.Palette.shadow.opacity(0.25), radius: 5, x: 0, y: 2)
                        }
                        .padding(.horizontal)

                        // Login / Logout Button
                        AuthActionButton(isAuthenticated: authViewModel.isAuthenticated, authViewModel: authViewModel, onLogout: {
                            authViewModel.logout()
                            try? Auth.auth().signOut()
                        })
                        .padding(.horizontal)
                        .padding(.top, 10)

                        // Delete Account Button (Apple App Store Guideline 5.1.1)
                        Button(action: {
                            showDeleteAccountAlert = true
                        }) {
                            HStack {
                                if isDeletingAccount {
                                    ProgressView()
                                        .tint(Theme.lxError)
                                } else {
                                    Image(systemName: "trash.fill")
                                    Text("Delete Account")
                                }
                            }
                            .fontWeight(.semibold)
                            .foregroundColor(Theme.lxError)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Theme.lxError.opacity(0.15))
                            .cornerRadius(Lx.Radius.button)
                            .overlay(
                                RoundedRectangle(cornerRadius: Lx.Radius.button)
                                    .stroke(Theme.lxError.opacity(0.4), lineWidth: 1)
                            )
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 30)
                        .disabled(isDeletingAccount)
                    }
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .sheet(isPresented: $showEditProfile) {
                EditProfileView(authViewModel: authViewModel)
            }
            .sheet(isPresented: $showLanguageSheet) {
                LanguageSelectionSheet(selectedLanguage: $selectedLanguage, languages: availableLanguages)
            }
            .sheet(isPresented: $showRecurringRides) {
                RecurringRidesView()
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
    }

    // MARK: - Account Deletion (Apple App Store Guideline 5.1.1)

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
                    // Clear all local data
                    self.clearAllLocalData()
                    // Sign out from Firebase
                    try? Auth.auth().signOut()
                    // Use the authViewModel to logout
                    self.authViewModel.logout()
                case .failure(let error):
                    self.deleteError = "Failed to delete account: \(error.localizedDescription)"
                }
            }
        }
    }

    private func clearAllLocalData() {
        // Clear UserDefaults
        let customerKeys = [
            "p2p_customer_id",
            "p2p_customer_name",
            "p2p_customer_email",
            "p2p_customer_access_token",
            "p2p_access_token",
            "saved_addresses",
            "favorites"
        ]
        for key in customerKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        UserDefaults.standard.synchronize()

        // Clear Keychain
        SecureStorage.shared.clearAuthTokens(type: .customer)
    }
}

// MARK: - Edit Profile View
struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var authViewModel: AuthViewModel
    @State private var editedName: String = ""
    @State private var isSaving = false
    @State private var saveError: String?

    private var userEmail: String {
        if !authViewModel.customerEmail.isEmpty {
            return authViewModel.customerEmail
        }
        if let email = UserDefaults.standard.string(forKey: "p2p_customer_email"), !email.isEmpty {
            return email
        }
        return Auth.auth().currentUser?.email ?? "No Email"
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Profile Information") {
                    TextField("Name", text: $editedName)
                        .textContentType(.name)

                    HStack {
                        Text("Email")
                            .foregroundColor(Lx.Palette.textSecondary)
                        Spacer()
                        Text(userEmail)
                            .foregroundColor(Lx.Palette.textMuted)
                    }
                }

                Section {
                    Text("Your email cannot be changed. Contact support if you need to update it.")
                        .font(.caption)
                        .foregroundColor(Lx.Palette.textSecondary)
                }

                if let error = saveError {
                    Section {
                        Text(error)
                            .foregroundColor(Lx.Palette.error)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveProfile()
                    }
                    .disabled(editedName.isEmpty || isSaving)
                }
            }
            .onAppear {
                // Initialize with current name
                if !authViewModel.customerName.isEmpty {
                    editedName = authViewModel.customerName
                } else if let name = UserDefaults.standard.string(forKey: "p2p_customer_name"), !name.isEmpty {
                    editedName = name
                } else {
                    editedName = Auth.auth().currentUser?.displayName ?? ""
                }
            }
        }
    }

    private func saveProfile() {
        isSaving = true
        saveError = nil

        // Get customer ID for P2P update
        let customerId = UserDefaults.standard.integer(forKey: "p2p_customer_id")

        if customerId > 0 {
            // Update via P2P backend
            P2PAPIService.shared.updateCustomerProfile(customerId: customerId, name: editedName) { result in
                DispatchQueue.main.async {
                    self.isSaving = false
                    switch result {
                    case .success:
                        // Update local state
                        self.authViewModel.customerName = self.editedName
                        UserDefaults.standard.set(self.editedName, forKey: "p2p_customer_name")
                        self.dismiss()
                    case .failure(let error):
                        self.saveError = error.localizedDescription
                    }
                }
            }
        } else {
            // Fallback to Firebase
            let changeRequest = Auth.auth().currentUser?.createProfileChangeRequest()
            changeRequest?.displayName = editedName
            changeRequest?.commitChanges { error in
                isSaving = false
                if let error = error {
                    saveError = error.localizedDescription
                } else {
                    authViewModel.customerName = editedName
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Language Selection Sheet
struct LanguageSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedLanguage: String
    let languages: [String]
    @State private var showRestartAlert = false

    private let languageCodes: [String: String] = [
        "English": "en",
        "Spanish": "es",
        "French": "fr",
        "Chinese": "zh-Hans",
        "Hindi": "hi"
    ]

    var body: some View {
        NavigationView {
            VStack {
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
                                    .foregroundColor(Theme.lxOrange)
                            }
                        }
                    }
                }

                // Note about language
                Text("Language changes will take effect on next app launch.")
                    .font(.caption)
                    .foregroundColor(Lx.Palette.textSecondary)
                    .padding()
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

struct ProfileOptionRow: View {
    let icon: String
    let title: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(Theme.lxOrange)
                .font(.title3)
                .frame(width: 30)

            Text(title)
                .font(.body)
                .foregroundColor(Theme.lxText)

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(Theme.lxTextMuted)
                .font(.caption)
        }
        .padding()
    }
}

// MARK: - Auth Action Button (extracted to reduce body complexity)
struct AuthActionButton: View {
    let isAuthenticated: Bool
    @ObservedObject var authViewModel: AuthViewModel
    let onLogout: () -> Void

    var body: some View {
        if isAuthenticated {
            Button(action: onLogout) {
                Text("Log Out")
                    .fontWeight(.bold)
                    .foregroundColor(Lx.Palette.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.lxError)
                    .cornerRadius(Lx.Radius.button)
                    .shadow(color: Theme.lxError.opacity(0.4), radius: 14, x: 0, y: 6)
            }
        } else {
            NavigationLink(destination: LoginView(authViewModel: authViewModel)) {
                Text("Log In")
                    .fontWeight(.bold)
                    .foregroundColor(Lx.Palette.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.lxButtonGradient)
                    .cornerRadius(Lx.Radius.button)
                    .shadow(color: Theme.lxOrange.opacity(0.4), radius: 14, x: 0, y: 6)
            }
        }
    }
}
