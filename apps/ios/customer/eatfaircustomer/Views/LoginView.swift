import SwiftUI
import AuthenticationServices
import EatFairShared

// MARK: - Dollor Luxury Theme (black + orange)
// Orange is the brand accent (matches the orange smiley ID stickers on driver cars).
private let lxBlack        = Lx.Palette.bg   // page canvas
private let lxSurface      = Lx.Palette.surface   // inputs / cards
private let lxSurface2     = Lx.Palette.surface2   // elevated
private let lxHairline     = Lx.Palette.hairline   // borders / dividers
private let lxOrange       = Lx.Palette.orange   // primary accent
private let lxOrangeBright = Lx.Palette.orangeBright   // gradient top / highlight
private let lxOrangeDeep   = Lx.Palette.orangeDeep   // pressed
private let lxText         = Lx.Palette.text            // primary text
private let lxTextSecondary = Lx.Palette.textSecondary  // secondary text
private let lxTextMuted    = Lx.Palette.textMuted   // muted / placeholders
private let lxError        = Lx.Palette.error
private let lxSuccess      = Lx.Palette.success

struct LoginView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var fullName = ""
    @State private var phone = ""
    @State private var emailError: String?
    @State private var legalPageURL: URL?

    var body: some View {
        ZStack {
            lxBlack.ignoresSafeArea()

            // Subtle orange glow at the top for depth
            RadialGradient(
                colors: [lxOrange.opacity(0.18), Color.clear],
                center: .top, startRadius: 0, endRadius: 420
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer().frame(height: 56)
                    brandMark
                    Spacer().frame(height: 30)
                    header
                    Spacer().frame(height: 28)
                    socialButtons
                    orDivider
                    inputFields
                    forgotPassword
                    primaryButton
                    messages
                    toggleAuth
                    trustLine
                    #if DEBUG
                    demoButton
                    #endif
                    footerLinks
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $authViewModel.showForgotPassword) {
            ForgotPasswordView(authViewModel: authViewModel)
        }
        .sheet(isPresented: $authViewModel.showResetCodeEntry) {
            ResetCodeEntryView(authViewModel: authViewModel)
        }
        .inAppBrowser(url: $legalPageURL)
    }

    // MARK: Brand mark (orange smiley + wordmark)
    private var brandMark: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: Lx.Radius.sheet, style: .continuous)
                    .fill(LinearGradient(colors: [lxOrangeBright, lxOrange],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 74, height: 74)
                    .shadow(color: lxOrange.opacity(0.5), radius: 20, y: 8)
                Image(systemName: "face.smiling.fill")
                    .font(Lx.Typography.icon.weight(.medium))
                    .foregroundColor(lxBlack)
            }
            HStack(spacing: 0) {
                Text("Dollor").foregroundColor(lxText)
                Text(".ai").foregroundColor(lxOrange)
            }
            .font(Lx.Typography.title.weight(.bold))
            .tracking(0.5)
        }
    }

    // MARK: Header
    private var header: some View {
        VStack(spacing: 8) {
            Text(isSignUp ? "Create your account" : "Welcome back")
                .font(Lx.Typography.largeTitle.weight(.bold))
                .foregroundColor(lxText)
            Text(isSignUp ? "Ride for a flat \(AppConfig.shared.rideshareFeeRangeText) platform fee." : "Sign in to continue")
                .font(Lx.Typography.subheadline)
                .foregroundColor(lxTextSecondary)
        }
    }

    // MARK: Social login
    private var socialButtons: some View {
        VStack(spacing: 12) {
            // Apple (white button is the HIG variant on dark backgrounds)
            Button(action: { authViewModel.signInWithApple() }) {
                HStack(spacing: 10) {
                    if authViewModel.isLoading {
                        ProgressView().tint(Lx.Palette.onSuccess)
                    } else {
                        Image(systemName: "apple.logo").font(Lx.Typography.body)
                        Text("Continue with Apple").font(Lx.Typography.callout.weight(.semibold))
                    }
                }
                .foregroundColor(Lx.Palette.onSuccess)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Lx.Palette.text)
                .cornerRadius(Lx.Radius.button)
            }
            .disabled(authViewModel.isLoading)
            .accessibilityLabel("Sign in with Apple")
            .accessibilityHint("Uses your Apple ID to sign in securely")

            // Google (dark surface + brand-blue G)
            Button(action: { authViewModel.signInWithGoogle() }) {
                HStack(spacing: 10) {
                    if authViewModel.isLoading {
                        ProgressView().tint(Lx.Palette.text)
                    } else {
                        Text("G")
                            .font(Lx.Typography.body.weight(.bold))
                            .foregroundColor(Lx.Palette.googleBlue)
                        Text("Continue with Google")
                            .font(Lx.Typography.callout.weight(.semibold))
                            .foregroundColor(lxText)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(lxSurface)
                .overlay(RoundedRectangle(cornerRadius: Lx.Radius.button).stroke(lxHairline, lineWidth: 1))
                .cornerRadius(Lx.Radius.button)
            }
            .disabled(authViewModel.isLoading)
            .accessibilityLabel("Sign in with Google")
            .accessibilityHint("Uses your Google account to sign in")
        }
        .padding(.horizontal, 24)
    }

    // MARK: "or" divider
    private var orDivider: some View {
        HStack {
            Rectangle().fill(lxHairline).frame(height: 1)
            Text("or")
                .font(Lx.Typography.footnote)
                .foregroundColor(lxTextMuted)
                .padding(.horizontal, 14)
            Rectangle().fill(lxHairline).frame(height: 1)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
    }

    // MARK: Inputs
    private var inputFields: some View {
        VStack(spacing: 14) {
            if isSignUp {
                AuthTextField(text: $fullName, placeholder: "Full name",
                              icon: "person", keyboardType: .default)
                AuthTextField(text: $phone, placeholder: "Phone number",
                              icon: "phone", keyboardType: .phonePad)
            }

            VStack(alignment: .leading, spacing: 6) {
                AuthTextField(text: $email, placeholder: "Email address",
                              icon: "envelope", keyboardType: .emailAddress)
                    .autocapitalization(.none)
                    .onChange(of: email) { emailError = nil }

                if let error = emailError {
                    Text(error)
                        .font(Lx.Typography.caption)
                        .foregroundColor(lxError)
                        .padding(.leading, 4)
                }
            }

            AuthSecureField(text: $password, placeholder: "Password")
        }
        .padding(.horizontal, 24)
    }

    // MARK: Forgot password
    @ViewBuilder private var forgotPassword: some View {
        if !isSignUp {
            HStack {
                Spacer()
                Button(action: { authViewModel.showForgotPassword = true }) {
                    Text("Forgot password?")
                        .font(Lx.Typography.footnote.weight(.semibold))
                        .foregroundColor(lxOrange)
                }
                .accessibilityLabel("Forgot password")
                .accessibilityHint("Opens password reset form")
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
        }
    }

    // MARK: Primary CTA
    private var primaryButton: some View {
        Button(action: {
            let validation = EmailValidator.validate(email)
            guard validation.isValid else {
                emailError = validation.errorMessage
                return
            }
            if isSignUp {
                authViewModel.register(email: email, password: password, fullName: fullName, phone: phone)
            } else {
                authViewModel.login(email: email, password: password)
            }
        }) {
            Group {
                if authViewModel.isLoading {
                    ProgressView().tint(Lx.Palette.onAccent)
                } else {
                    Text(isSignUp ? "Create account" : "Continue")
                        .font(Lx.Typography.callout.weight(.bold))
                }
            }
            .foregroundColor(Lx.Palette.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                LinearGradient(colors: [lxOrangeBright, lxOrange],
                               startPoint: .top, endPoint: .bottom)
            )
            .cornerRadius(Lx.Radius.button)
            .shadow(color: lxOrange.opacity(0.45), radius: 16, y: 8)
        }
        .padding(.horizontal, 24)
        .padding(.top, isSignUp ? 22 : 18)
        .disabled(authViewModel.isLoading)
        .accessibilityLabel(isSignUp ? "Create account" : "Continue to sign in")
        .accessibilityHint(isSignUp ? "Creates your new account" : "Signs in with your email and password")
    }

    // MARK: Error / success messages
    @ViewBuilder private var messages: some View {
        if let errorMessage = authViewModel.errorMessage {
            Text(errorMessage)
                .font(Lx.Typography.footnote)
                .foregroundColor(lxError)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 14)
        }
        if authViewModel.passwordResetSuccess {
            Text("Password reset successful! You can now log in.")
                .font(Lx.Typography.footnote)
                .foregroundColor(lxSuccess)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 14)
        }
    }

    // MARK: Toggle login / sign up
    private var toggleAuth: some View {
        HStack(spacing: 5) {
            Text(isSignUp ? "Already have an account?" : "Don't have an account?")
                .font(Lx.Typography.footnote)
                .foregroundColor(lxTextSecondary)
            Button(action: {
                withAnimation {
                    isSignUp.toggle()
                    authViewModel.errorMessage = nil
                }
            }) {
                Text(isSignUp ? "Log in" : "Sign up")
                    .font(Lx.Typography.footnote.weight(.bold))
                    .foregroundColor(lxOrange)
            }
            .accessibilityLabel(isSignUp ? "Switch to log in" : "Switch to sign up")
            .accessibilityHint(isSignUp ? "Shows the login form" : "Shows the registration form")
        }
        .padding(.top, 24)
    }

    // MARK: Trust line (replaces the bubbly $1 badge)
    private var trustLine: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(Lx.Typography.subheadline)
                .foregroundColor(lxOrange)
            Text("Flat \(AppConfig.shared.rideshareFeeRangeText) platform fee · 100% of tips go to drivers")
                .font(Lx.Typography.footnote.weight(.medium))
                .foregroundColor(lxTextSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(lxSurface)
        .overlay(RoundedRectangle(cornerRadius: Lx.Radius.button).stroke(lxHairline, lineWidth: 1))
        .cornerRadius(Lx.Radius.button)
        .padding(.horizontal, 24)
        .padding(.top, 28)
    }

    // MARK: Demo login (DEBUG only)
    #if DEBUG
    private var demoButton: some View {
        Button(action: {
            email = "demo.customer@dollor.ai"
            password = "DemoCustomer2025!"
            authViewModel.login(email: email, password: password)
        }) {
            HStack(spacing: 8) {
                Image(systemName: "play.circle").font(Lx.Typography.subheadline)
                Text("Demo Login (Testing)").font(Lx.Typography.footnote.weight(.medium))
            }
            .foregroundColor(lxTextSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .overlay(RoundedRectangle(cornerRadius: Lx.Radius.button).stroke(lxHairline, lineWidth: 1))
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .accessibilityLabel("Demo login for testing")
        .accessibilityHint("Signs in with demo account credentials")
    }
    #endif

    // MARK: Footer links
    private var footerLinks: some View {
        HStack(spacing: 8) {
            Button("Terms of Use") { legalPageURL = URL(string: AppConstants.termsOfServiceURL) }
                .foregroundColor(lxTextSecondary)
            Text("·").foregroundColor(lxTextMuted)
            Button("Privacy Policy") { legalPageURL = URL(string: AppConstants.privacyPolicyURL) }
                .foregroundColor(lxTextSecondary)
        }
        .font(Lx.Typography.footnote)
        .padding(.top, 18)
        .padding(.bottom, 28)
    }
}

// MARK: - Auth Text Field Component
struct AuthTextField: View {
    @Binding var text: String
    let placeholder: String
    let icon: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(Lx.Typography.callout)
                .foregroundColor(lxTextMuted)
                .frame(width: 20)

            TextField("", text: $text, prompt: Text(placeholder).foregroundColor(lxTextMuted))
                .font(Lx.Typography.callout)
                .foregroundColor(lxText)
                .keyboardType(keyboardType)
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(lxSurface)
        .overlay(RoundedRectangle(cornerRadius: Lx.Radius.button).stroke(lxHairline, lineWidth: 1))
        .cornerRadius(Lx.Radius.button)
    }
}

// MARK: - Auth Secure Field Component
struct AuthSecureField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock")
                .font(Lx.Typography.callout)
                .foregroundColor(lxTextMuted)
                .frame(width: 20)

            SecureField("", text: $text, prompt: Text(placeholder).foregroundColor(lxTextMuted))
                .font(Lx.Typography.callout)
                .foregroundColor(lxText)
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(lxSurface)
        .overlay(RoundedRectangle(cornerRadius: Lx.Radius.button).stroke(lxHairline, lineWidth: 1))
        .cornerRadius(Lx.Radius.button)
    }
}

// MARK: - Color Extension for Hex
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Forgot Password View
struct ForgotPasswordView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @State private var resetEmail = ""
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                lxBlack.ignoresSafeArea()

                VStack(spacing: 24) {
                    Text("Reset password")
                        .font(Lx.Typography.title.weight(.bold))
                        .foregroundColor(lxText)
                        .padding(.top, 30)

                    Text("Enter your email address and we'll send you a code to reset your password.")
                        .font(Lx.Typography.subheadline)
                        .foregroundColor(lxTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    AuthTextField(
                        text: $resetEmail,
                        placeholder: "Email address",
                        icon: "envelope",
                        keyboardType: .emailAddress
                    )
                    .autocapitalization(.none)
                    .padding(.horizontal, 24)

                    if let errorMessage = authViewModel.errorMessage {
                        Text(errorMessage)
                            .font(Lx.Typography.footnote)
                            .foregroundColor(lxError)
                            .padding(.horizontal, 24)
                    }

                    Button(action: {
                        authViewModel.requestPasswordReset(email: resetEmail)
                    }) {
                        Group {
                            if authViewModel.isLoading {
                                ProgressView().tint(Lx.Palette.onAccent)
                            } else {
                                Text("Send reset code")
                                    .font(Lx.Typography.callout.weight(.bold))
                            }
                        }
                        .foregroundColor(Lx.Palette.onAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(LinearGradient(colors: [lxOrangeBright, lxOrange],
                                                   startPoint: .top, endPoint: .bottom))
                        .cornerRadius(Lx.Radius.button)
                        .shadow(color: lxOrange.opacity(0.4), radius: 14, y: 6)
                    }
                    .padding(.horizontal, 24)
                    .disabled(authViewModel.isLoading || resetEmail.isEmpty)
                    .accessibilityLabel("Send password reset code")
                    .accessibilityHint("Sends a reset code to your email address")

                    Spacer()
                }
            }
            .navigationBarItems(trailing: Button("Cancel") {
                authViewModel.resetPasswordResetState()
                dismiss()
            }
            .foregroundColor(lxOrange)
            .accessibilityLabel("Cancel password reset"))
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Reset Code Entry View
struct ResetCodeEntryView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                lxBlack.ignoresSafeArea()

                VStack(spacing: 24) {
                    Text("Enter reset code")
                        .font(Lx.Typography.title.weight(.bold))
                        .foregroundColor(lxText)
                        .padding(.top, 30)

                    Text("We sent a code to \(authViewModel.resetEmail). Enter it below along with your new password.")
                        .font(Lx.Typography.subheadline)
                        .foregroundColor(lxTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    AuthTextField(
                        text: $authViewModel.resetCode,
                        placeholder: "Reset code",
                        icon: "number",
                        keyboardType: .numberPad
                    )
                    .padding(.horizontal, 24)

                    AuthSecureField(
                        text: $authViewModel.newPassword,
                        placeholder: "New password"
                    )
                    .padding(.horizontal, 24)

                    if let errorMessage = authViewModel.errorMessage {
                        Text(errorMessage)
                            .font(Lx.Typography.footnote)
                            .foregroundColor(lxError)
                            .padding(.horizontal, 24)
                    }

                    Button(action: {
                        authViewModel.confirmPasswordReset()
                    }) {
                        Group {
                            if authViewModel.isLoading {
                                ProgressView().tint(Lx.Palette.onAccent)
                            } else {
                                Text("Reset password")
                                    .font(Lx.Typography.callout.weight(.bold))
                            }
                        }
                        .foregroundColor(Lx.Palette.onAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(LinearGradient(colors: [lxOrangeBright, lxOrange],
                                                   startPoint: .top, endPoint: .bottom))
                        .cornerRadius(Lx.Radius.button)
                        .shadow(color: lxOrange.opacity(0.4), radius: 14, y: 6)
                    }
                    .padding(.horizontal, 24)
                    .disabled(authViewModel.isLoading || authViewModel.resetCode.isEmpty || authViewModel.newPassword.isEmpty)
                    .accessibilityLabel("Reset password")
                    .accessibilityHint("Confirms your new password using the reset code")

                    Spacer()
                }
            }
            .navigationBarItems(trailing: Button("Cancel") {
                authViewModel.resetPasswordResetState()
                dismiss()
            }
            .foregroundColor(lxOrange)
            .accessibilityLabel("Cancel reset code entry"))
            .onChange(of: authViewModel.passwordResetSuccess) { oldValue, newValue in
                if newValue {
                    dismiss()
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
