import SwiftUI
import Combine
import UIKit
import EatFairShared
import os

private let onboardingLogger = Logger(subsystem: "com.dollorai.delivery", category: "DriverOnboarding")

// MARK: - Driver Onboarding / Verification Flow
//
// Gated flow a newly-registered (unapproved) driver completes before reaching
// the dashboard. Collects the documents the backend needs to auto-approve:
//   drivers_license + insurance + background_check  →  status flips to APPROVED.
//
// Steps:
//   1. Contractor agreement / terms
//   2. Driver's license photo        → POST /api/auth/driver/documents (drivers_license)
//   3. Insurance photo               → POST /api/auth/driver/documents (insurance)
//   4. Vehicle details               → PUT  /api/drivers/{id}  (updateDriverProfile)
//   5. Background check (Checkr)      → POST /api/checkr/background-check/initiate + poll status
//   6. Pending approval              → poll GET /api/auth/driver/me until APPROVED
struct DriverOnboardingView: View {
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var viewModel: DriverOnboardingViewModel
    @StateObject private var complianceVM: ComplianceViewModel

    private let totalSteps = 6

    // Local preview images for the document tiles (design-only; upload is driven by the ViewModel).
    @State private var licensePreview: UIImage?
    @State private var insurancePreview: UIImage?
    @State private var registrationPreview: UIImage?
    @State private var showLogoutConfirm = false

    private var progressFraction: Double {
        Double(viewModel.step.rawValue) / Double(totalSteps)
    }

    init() {
        let driverId = UserDefaults.standard.object(forKey: UserDefaultsKeys.driverId) as? Int ?? 0
        _viewModel = StateObject(wrappedValue: DriverOnboardingViewModel(driverId: driverId))
        _complianceVM = StateObject(wrappedValue: ComplianceViewModel(driverId: driverId))
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacingL) {
                    switch viewModel.step {
                    case .terms:          termsStep
                    case .license:        licenseStep
                    case .insurance:      insuranceStep
                    case .vehicle:        vehicleStep
                    case .backgroundCheck: backgroundCheckStep
                    case .pending:        pendingStep
                    }

                    if let error = viewModel.errorMessage {
                        errorBanner(error)
                    }
                }
                .padding()
            }
        }
        .background(Theme.lxBg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .navigationTitle("Driver Verification")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .onAppear {
            viewModel.loadInitialStatus()
        }
        .onDisappear {
            viewModel.stopStatusPolling()
            complianceVM.stopPolling()
        }
        .alert("Log Out?", isPresented: $showLogoutConfirm) {
            Button("Log Out", role: .destructive) { authManager.logout() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your progress is saved — you can log back in and pick up where you left off.")
        }
    }

    // MARK: - Header / Progress

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.spacingS) {
            // Back (left) / Log Out (right) — a driver who made a mistake on an earlier
            // step (wrong vehicle info, a bad document photo, etc.) can step back and
            // correct it. Hidden only on step 1 (nothing before Terms). Available even on
            // the Pending step — a driver who resumes there (background check already
            // submitted) may still need to revisit an earlier step, and background-check
            // polling keeps running regardless of which step is on screen, so stepping
            // back doesn't interrupt it. Log Out stays available on every step too, since
            // the Pending step still has no bottom bar otherwise.
            HStack {
                if viewModel.step.rawValue > 1 {
                    Button(action: { viewModel.goBack(from: viewModel.step) }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.lxOrange)
                }
                Spacer()
                Button("Log Out") { showLogoutConfirm = true }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.lxTextSecondary)
            }

            HStack {
                Text("Step \(viewModel.step.rawValue) of \(totalSteps)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.lxTextSecondary)
                Spacer()
                Text("\(Int(progressFraction * 100))%")
                    .font(.caption.weight(.bold))
                    .foregroundColor(Theme.lxOrange)
            }

            // Segmented progress bar (one segment per step).
            HStack(spacing: 4) {
                ForEach(1...totalSteps, id: \.self) { index in
                    Capsule()
                        .fill(index <= viewModel.step.rawValue ? Theme.lxOrange : Theme.lxHairline)
                        .frame(height: 6)
                }
            }

            Text(viewModel.step.title)
                .font(.title2.weight(.bold))
                .foregroundColor(Theme.lxText)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Theme.lxSurface)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Theme.lxHairline),
            alignment: .bottom
        )
    }

    // MARK: - Bottom Action Bar (pinned)

    @ViewBuilder
    private var bottomBar: some View {
        switch viewModel.step {
        case .terms:
            primaryBar(title: "Accept & Continue", enabled: true) {
                viewModel.advance(from: .terms)
            }
        case .license:
            primaryBar(title: "Continue", enabled: viewModel.licenseUploaded) {
                viewModel.advance(from: .license)
            }
        case .insurance:
            primaryBar(title: "Continue", enabled: viewModel.insuranceUploaded) {
                viewModel.advance(from: .insurance)
            }
        case .vehicle:
            primaryBar(
                title: viewModel.isSavingVehicle ? "Saving…" : "Continue",
                enabled: viewModel.canSubmitVehicle && !viewModel.isSavingVehicle
            ) {
                viewModel.submitVehicle { success in
                    if success { viewModel.advance(from: .vehicle) }
                }
            }
        case .backgroundCheck:
            primaryBar(title: "Continue", enabled: !complianceVM.canStartBackgroundCheck) {
                viewModel.advance(from: .backgroundCheck)
            }
        case .pending:
            EmptyView()
        }
    }

    private func primaryBar(title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(Lx.Palette.onAccent)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    Group {
                        if enabled {
                            Theme.lxButtonGradient
                        } else {
                            Theme.lxSurface2
                        }
                    }
                )
                .cornerRadius(Lx.Radius.button)
                .shadow(color: enabled ? Theme.lxOrange.opacity(0.4) : .clear, radius: 14, x: 0, y: 6)
        }
        .disabled(!enabled)
        .padding()
        .background(Theme.lxBg)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Theme.lxHairline),
            alignment: .top
        )
    }

    // MARK: - Step 1: Terms

    private var termsStep: some View {
        VStack(alignment: .leading, spacing: Theme.spacingL) {
            sectionCard {
                stepIntro(
                    icon: "doc.text.fill",
                    title: "Independent Contractor Agreement",
                    detail: "Please review the terms below, then accept to continue."
                )

                Text("""
                By continuing you confirm that you will operate as an independent \
                contractor providing rideshare transportation through Dollor.ai. You \
                are responsible for maintaining a valid driver's license, active \
                vehicle insurance, and a vehicle that meets all local requirements. \
                You agree to complete a background check and to comply with all \
                applicable transportation regulations.
                """)
                    .font(.subheadline)
                    .foregroundColor(Theme.lxTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: Theme.spacingS) {
                    requirementRow("Valid driver's license")
                    requirementRow("Active vehicle insurance")
                    requirementRow("Pass a background check")
                }
            }

            feeSummaryCard
        }
    }

    // MARK: - Fee Summary (read-only, informational)

    /// Static "What you earn & pay" card shown alongside the contractor agreement so
    /// drivers see the economics up front. Purely informational — no state or logic.
    private var feeSummaryCard: some View {
        sectionCard {
            HStack(spacing: Theme.spacingM) {
                ZStack {
                    Circle()
                        .fill(Theme.lxOrange.opacity(0.14))
                        .frame(width: 40, height: 40)
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.title3)
                        .foregroundColor(Theme.lxOrange)
                }
                Text("What you earn & pay")
                    .font(.headline)
                    .foregroundColor(Theme.lxText)
            }

            VStack(alignment: .leading, spacing: Theme.spacingM) {
                feeRow(
                    icon: "percent",
                    text: "Platform fee per ride: \(AppConfig.shared.rideshareFeeSummary) — deducted from each fare"
                )
                feeRow(
                    icon: "hand.thumbsup.fill",
                    text: "You keep 100% of tips"
                )
                feeRow(
                    icon: "banknote.fill",
                    text: "Payouts: standard (≈2 days) free · instant cash-out ~1%"
                )
                feeRow(
                    icon: "doc.text.fill",
                    text: "You're an independent contractor (1099) — taxes are your responsibility"
                )
            }
        }
    }

    private func feeRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.spacingS) {
            Image(systemName: icon)
                .font(.footnote)
                .foregroundColor(Theme.lxOrange)
                .frame(width: 20, alignment: .center)
            Text(text)
                .font(.subheadline)
                .foregroundColor(Theme.lxTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Step 2: Driver's License

    private var licenseStep: some View {
        sectionCard {
            stepIntro(
                icon: "creditcard.fill",
                title: "Driver's License",
                detail: "Upload a clear photo of the front of your driver's license."
            )

            uploadTile(
                preview: $licensePreview,
                isUploaded: viewModel.licenseUploaded,
                isUploading: viewModel.isUploadingLicense,
                placeholder: "Tap to upload license photo",
                documentType: "drivers_license"
            )
        }
    }

    // MARK: - Step 3: Insurance

    private var insuranceStep: some View {
        sectionCard {
            stepIntro(
                icon: "checkmark.shield.fill",
                title: "Vehicle Insurance",
                detail: "Upload a photo of your current vehicle insurance card."
            )

            uploadTile(
                preview: $insurancePreview,
                isUploaded: viewModel.insuranceUploaded,
                isUploading: viewModel.isUploadingInsurance,
                placeholder: "Tap to upload insurance card",
                documentType: "insurance"
            )
        }
    }

    // MARK: - Step 4: Vehicle Details

    private var vehicleStep: some View {
        VStack(alignment: .leading, spacing: Theme.spacingL) {
            sectionCard {
                stepIntro(
                    icon: "car.fill",
                    title: "Vehicle Details",
                    detail: "Tell us about the vehicle you'll drive."
                )

                onboardingField("Make", text: $viewModel.vehicleMake)
                onboardingField("Model", text: $viewModel.vehicleModel)
                onboardingField("Year", text: $viewModel.vehicleYear, keyboard: .numberPad)
                onboardingField("Color", text: $viewModel.vehicleColor)
                onboardingField("License Plate", text: $viewModel.licensePlate)
            }

            sectionCard {
                Text("Vehicle registration (optional)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Theme.lxText)
                uploadTile(
                    preview: $registrationPreview,
                    isUploaded: viewModel.registrationUploaded,
                    isUploading: viewModel.isUploadingRegistration,
                    placeholder: "Tap to upload registration photo",
                    documentType: "vehicle_registration"
                )
            }
        }
    }

    // MARK: - Step 5: Background Check

    private var backgroundCheckStep: some View {
        sectionCard {
            stepIntro(
                icon: "person.fill.checkmark",
                title: "Background Check",
                detail: "Complete your Checkr background check. You'll be taken to Checkr's secure page, then brought back here."
            )

            HStack {
                Text("Status")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(Theme.lxTextSecondary)
                Spacer()
                bgStatusChip
            }

            if complianceVM.canStartBackgroundCheck {
                Button(action: { complianceVM.startBackgroundCheck() }) {
                    HStack(spacing: Theme.spacingS) {
                        if complianceVM.isInitiatingCheck {
                            ProgressView()
                                .tint(Lx.Palette.onAccent)
                        } else {
                            Image(systemName: "shield.lefthalf.filled")
                            Text("Start Background Check")
                        }
                    }
                    .font(.headline)
                    .foregroundColor(Lx.Palette.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.lxButtonGradient)
                    .cornerRadius(Theme.cornerRadiusMedium)
                    .shadow(color: Theme.lxOrange.opacity(0.4), radius: 14, y: 6)
                }
                .disabled(complianceVM.isInitiatingCheck)
            } else {
                HStack(spacing: Theme.spacingS) {
                    Image(systemName: "clock.fill")
                        .foregroundColor(Theme.lxOrange)
                    Text("Your background check is underway. Tap Continue to track its progress.")
                        .font(.subheadline)
                        .foregroundColor(Theme.lxTextSecondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.lxOrange.opacity(0.1))
                .cornerRadius(Theme.cornerRadiusMedium)
            }

            if let error = complianceVM.bgCheckError {
                errorBanner(error)
            }
        }
        .onAppear {
            // Pull the live Checkr status so a returning, in-progress check shows its
            // real state (e.g. "Pending") instead of defaulting to "Not started".
            complianceVM.loadAll()
        }
    }

    // MARK: - Step 6: Pending Approval

    private var pendingStep: some View {
        sectionCard {
            VStack(spacing: Theme.spacingL) {
                ZStack {
                    Circle()
                        .fill(Theme.lxOrange.opacity(0.15))
                        .frame(width: 96, height: 96)
                    ProgressView()
                        .scaleEffect(1.6)
                        .tint(Theme.lxOrange)
                }
                .padding(.top, Theme.spacingL)

                Text("Verifying your account…")
                    .font(.title3.weight(.bold))
                    .foregroundColor(Theme.lxText)

                Text("We're confirming your documents and background check. This usually takes just a moment. You'll be taken to your dashboard automatically once approved.")
                    .font(.subheadline)
                    .foregroundColor(Theme.lxTextSecondary)
                    .multilineTextAlignment(.center)

                Button("Check status now") {
                    viewModel.pollStatusOnce { approved in
                        if approved { authManager.markApproved() }
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Theme.lxOrange)
                .padding(.top, Theme.spacingS)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, Theme.spacingL)
        }
        .onAppear {
            viewModel.startStatusPolling { approved in
                if approved { authManager.markApproved() }
            }
        }
    }

    // MARK: - Reusable Components

    /// Card wrapper giving every step a consistent elevated surface.
    private func sectionCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingL) {
            content()
        }
        .padding(Theme.spacingL)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.lxSurface)
        .cornerRadius(Theme.cornerRadiusLarge)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusLarge)
                .stroke(Theme.lxHairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: Theme.cardShadowRadius, x: 0, y: 4)
    }

    /// Icon + title + instruction header used at the top of each step card.
    private func stepIntro(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Theme.spacingM) {
            ZStack {
                Circle()
                    .fill(Theme.lxOrange.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(Theme.lxOrange)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(Theme.lxText)
                Text(detail)
                    .font(.subheadline)
                    .foregroundColor(Theme.lxTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func requirementRow(_ text: String) -> some View {
        HStack(spacing: Theme.spacingS) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Theme.lxOrange)
            Text(text)
                .font(.subheadline)
                .foregroundColor(Theme.lxText)
        }
    }

    private var bgStatusChip: some View {
        let display = bgStatusDisplay
        return HStack(spacing: 6) {
            Circle()
                .fill(display.color)
                .frame(width: 8, height: 8)
            Text(display.label)
                .font(.caption.weight(.semibold))
                .foregroundColor(display.color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(display.color.opacity(0.12))
        .clipShape(Capsule())
    }

    private var bgStatusDisplay: (label: String, color: Color) {
        switch complianceVM.bgCheckStatus.lowercased() {
        case "clear", "passed", "valid", "complete", "completed":
            return ("Cleared", Theme.lxSuccess)
        case "pending", "consider":
            return ("In progress", Theme.lxOrange)
        default:
            return ("Not started", Theme.lxTextSecondary)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: Theme.spacingS) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Theme.statusError)
            Text(message)
                .font(.caption)
                .foregroundColor(Theme.statusError)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.statusError.opacity(0.1))
        .cornerRadius(Theme.cornerRadiusMedium)
    }

    /// Upload tile: dashed drop target → thumbnail + ✓ once a photo is chosen, with a
    /// Retake/Replace affordance. Tapping offers "Take Photo" (camera) or "Choose from
    /// Library", so a driver without existing photos of their license can capture one
    /// directly instead of being stuck with a library-only picker.
    @ViewBuilder
    private func uploadTile(
        preview: Binding<UIImage?>,
        isUploaded: Bool,
        isUploading: Bool,
        placeholder: String,
        documentType: String
    ) -> some View {
        DocumentUploadTile(
            preview: preview,
            isUploaded: isUploaded,
            isUploading: isUploading,
            placeholder: placeholder,
            onPicked: { image in
                preview.wrappedValue = image
                guard let jpeg = image.resizedForDocumentUpload() else { return }
                viewModel.upload(documentType: documentType, imageData: jpeg)
            }
        )
    }

    @ViewBuilder
    private func onboardingField(_ label: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(Theme.lxTextSecondary)
            TextField(label, text: text)
                .keyboardType(keyboard)
                .padding(12)
                .foregroundColor(Theme.lxText)
                .background(Theme.lxSurface)
                .cornerRadius(Theme.cornerRadiusSmall)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                        .stroke(Theme.lxHairline, lineWidth: 1)
                )
        }
    }
}

/// Self-contained tile: owns the "Take Photo vs Choose from Library" dialog and the
/// capture sheet, so each of the 3 onboarding upload tiles gets its own independent state.
private struct DocumentUploadTile: View {
    @Binding var preview: UIImage?
    let isUploaded: Bool
    let isUploading: Bool
    let placeholder: String
    let onPicked: (UIImage) -> Void

    @State private var showSourceDialog = false
    @State private var activeSource: DocumentCaptureView.Source?

    var body: some View {
        Button {
            showSourceDialog = true
        } label: {
            content
        }
        .disabled(isUploading)
        .confirmationDialog("Add Photo", isPresented: $showSourceDialog, titleVisibility: .visible) {
            if DocumentCaptureView.isCameraAvailable {
                Button("Take Photo") { activeSource = .camera }
            }
            Button("Choose from Library") { activeSource = .photoLibrary }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(item: $activeSource) { source in
            // The binding's setter forwards the captured image straight to `onPicked` —
            // avoids needing UIImage to be Equatable for an `.onChange(of:)` observer.
            DocumentCaptureView(
                source: source,
                image: Binding(
                    get: { nil },
                    set: { newImage in
                        if let newImage { onPicked(newImage) }
                    }
                )
            )
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let image = preview {
            VStack(spacing: Theme.spacingS) {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 170)
                        .clipped()
                        .cornerRadius(Theme.cornerRadiusMedium)

                    if isUploading {
                        ProgressView()
                            .tint(Lx.Palette.onAccent)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(10)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(Theme.lxOrange)
                            .background(Circle().fill(Theme.lxSurface))
                            .padding(10)
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text(isUploading ? "Uploading…" : "Retake / Replace")
                }
                .font(.subheadline.weight(.medium))
                .foregroundColor(Theme.lxOrange)
            }
        } else if isUploaded {
            HStack(spacing: Theme.spacingM) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title)
                    .foregroundColor(Theme.lxSuccess)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Uploaded")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Theme.lxText)
                    Text("Tap to replace")
                        .font(.caption)
                        .foregroundColor(Theme.lxTextSecondary)
                }
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.lxSuccess.opacity(0.12))
            .cornerRadius(Theme.cornerRadiusMedium)
        } else {
            VStack(spacing: Theme.spacingS) {
                if isUploading {
                    ProgressView()
                        .tint(Theme.lxOrange)
                    Text("Uploading…")
                        .font(.subheadline)
                        .foregroundColor(Theme.lxTextSecondary)
                } else {
                    Image(systemName: "camera.fill")
                        .font(.largeTitle)
                        .foregroundColor(Theme.lxOrange)
                    Text(placeholder)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(Theme.lxText)
                    Text("Take a photo or choose from library")
                        .font(.caption)
                        .foregroundColor(Theme.lxTextSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 170)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium)
                    .fill(Theme.lxSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    .foregroundColor(Theme.lxHairline)
            )
        }
    }
}

// MARK: - ViewModel

@MainActor
final class DriverOnboardingViewModel: ObservableObject {
    enum Step: Int {
        case terms = 1
        case license = 2
        case insurance = 3
        case vehicle = 4
        case backgroundCheck = 5
        case pending = 6

        var title: String {
            switch self {
            case .terms:           return "Contractor Agreement"
            case .license:         return "Driver's License"
            case .insurance:       return "Insurance"
            case .vehicle:         return "Vehicle Details"
            case .backgroundCheck: return "Background Check"
            case .pending:         return "Pending Approval"
            }
        }
    }

    @Published var step: Step = .terms
    @Published var errorMessage: String?

    // Document upload state
    @Published var licenseUploaded = false
    @Published var insuranceUploaded = false
    @Published var registrationUploaded = false
    @Published var isUploadingLicense = false
    @Published var isUploadingInsurance = false
    @Published var isUploadingRegistration = false

    // Vehicle form
    @Published var vehicleMake = ""
    @Published var vehicleModel = ""
    @Published var vehicleYear = ""
    @Published var vehicleColor = ""
    @Published var licensePlate = ""
    @Published var isSavingVehicle = false

    var canSubmitVehicle: Bool {
        !vehicleMake.trimmingCharacters(in: .whitespaces).isEmpty &&
        !vehicleModel.trimmingCharacters(in: .whitespaces).isEmpty &&
        !licensePlate.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // Read live from UserDefaults rather than captured once at init: a delete+reinstall
    // wipes UserDefaults but leaves the Keychain-backed auth token behind, so this view
    // model can be constructed (with whatever was passed to init, likely 0) before
    // AuthManager's background `/auth/driver/me` call repopulates the real id. Caching
    // that stale value here would lock in 0 for the rest of this instance's lifetime,
    // and every call below (profile fetch, vehicle save, ...) would keep hitting the
    // backend's ownership check as a different driver -> 403 "Access denied".
    private var driverId: Int {
        UserDefaults.standard.object(forKey: UserDefaultsKeys.driverId) as? Int ?? 0
    }
    private let api = P2PAPIService.shared
    private var statusTimer: Timer?

    init(driverId: Int) {
        // Kept for call-site compatibility (DriverOnboardingView passes its init-time
        // UserDefaults snapshot) — intentionally unused; see `driverId` above.
    }

    deinit {
        statusTimer?.invalidate()
    }

    func advance(from current: Step) {
        errorMessage = nil
        if let next = Step(rawValue: current.rawValue + 1) {
            step = next
        }
    }

    /// Step back one screen so a driver who made a mistake (wrong vehicle info, a bad
    /// document photo, etc.) can revisit and correct it before continuing. Does not
    /// discard anything already uploaded/saved for earlier steps — their completion
    /// state (licenseUploaded, insuranceUploaded, vehicle fields) is untouched, so
    /// stepping forward again just lands back where they were.
    func goBack(from current: Step) {
        errorMessage = nil
        if let previous = Step(rawValue: current.rawValue - 1) {
            step = previous
        }
    }

    /// Pre-fill completion state so a returning driver resumes at the right step.
    func loadInitialStatus() {
        api.getDriverDocumentsStatus { [weak self] result in
            guard let self = self else { return }
            guard case .success(let json) = result,
                  let documents = json["documents"] as? [String: Any] else { return }

            if let license = documents["drivers_license"] as? [String: Any] {
                self.licenseUploaded = license["uploaded"] as? Bool ?? false
            }
            if let insurance = documents["insurance"] as? [String: Any] {
                self.insuranceUploaded = insurance["uploaded"] as? Bool ?? false
            }
            let bgCompleted = (documents["background_check"] as? [String: Any])?["completed"] as? Bool ?? false

            // Vehicle details live on the driver profile, not the documents payload,
            // so fetch the profile to tell whether the vehicle step is still pending.
            // Without this, a returning driver skips straight past the vehicle step.
            self.api.getDriverProfile(driverId: self.driverId) { [weak self] profileResult in
                guard let self = self else { return }

                var vehicleProvided = false
                if case .success(let profile) = profileResult,
                   let make = profile["vehicle_make"] as? String {
                    vehicleProvided = !make.trimmingCharacters(in: .whitespaces).isEmpty
                }

                // Jump to the first incomplete step (only ever move forward from terms).
                guard self.step == .terms else { return }
                if !self.licenseUploaded {
                    self.step = .license
                } else if !self.insuranceUploaded {
                    self.step = .insurance
                } else if !vehicleProvided {
                    self.step = .vehicle
                } else if bgCompleted {
                    self.step = .pending
                } else {
                    self.step = .backgroundCheck
                }
            }
        }
    }

    /// Compress to JPEG and POST to /api/auth/driver/documents.
    func upload(documentType: String, imageData: Data) {
        let jpeg = UIImage(data: imageData)?.jpegData(compressionQuality: 0.8) ?? imageData
        setUploading(documentType, true)
        errorMessage = nil

        api.uploadDriverDocument(documentType: documentType, imageData: jpeg) { [weak self] result in
            guard let self = self else { return }
            self.setUploading(documentType, false)
            switch result {
            case .success:
                self.setUploaded(documentType, true)
                onboardingLogger.info("Uploaded \(documentType) for driver \(self.driverId)")
            case .failure(let error):
                self.errorMessage = "Upload failed: \(error.localizedDescription)"
            }
        }
    }

    /// Submit vehicle details via the existing driver profile update endpoint.
    func submitVehicle(completion: @escaping (Bool) -> Void) {
        guard canSubmitVehicle else {
            errorMessage = "Please fill in make, model, and license plate."
            completion(false)
            return
        }
        isSavingVehicle = true
        errorMessage = nil

        api.updateDriverProfile(
            driverId: driverId,
            vehicleMake: vehicleMake,
            vehicleModel: vehicleModel,
            vehicleYear: Int(vehicleYear),
            vehicleColor: vehicleColor.isEmpty ? nil : vehicleColor,
            licensePlate: licensePlate
        ) { [weak self] result in
            guard let self = self else { return }
            self.isSavingVehicle = false
            switch result {
            case .success:
                completion(true)
            case .failure(let error):
                self.errorMessage = "Couldn't save vehicle: \(error.localizedDescription)"
                completion(false)
            }
        }
    }

    // MARK: - Status Polling (Step 6)

    func startStatusPolling(onApproved: @escaping (Bool) -> Void) {
        statusTimer?.invalidate()
        pollStatusOnce(onApproved: onApproved)
        statusTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.pollStatusOnce(onApproved: onApproved)
        }
    }

    func pollStatusOnce(onApproved: @escaping (Bool) -> Void) {
        api.getDriverMe { [weak self] result in
            guard let self = self else { return }
            guard case .success(let json) = result,
                  let statusValue = json["status"] as? String else { return }
            let approved = ["approved", "active", "online"].contains(statusValue.lowercased())
            if approved {
                self.stopStatusPolling()
            }
            onApproved(approved)
        }
    }

    func stopStatusPolling() {
        statusTimer?.invalidate()
        statusTimer = nil
    }

    // MARK: - Helpers

    private func setUploading(_ documentType: String, _ value: Bool) {
        switch documentType {
        case "drivers_license":     isUploadingLicense = value
        case "insurance":           isUploadingInsurance = value
        case "vehicle_registration": isUploadingRegistration = value
        default: break
        }
    }

    private func setUploaded(_ documentType: String, _ value: Bool) {
        switch documentType {
        case "drivers_license":     licenseUploaded = value
        case "insurance":           insuranceUploaded = value
        case "vehicle_registration": registrationUploaded = value
        default: break
        }
    }
}
