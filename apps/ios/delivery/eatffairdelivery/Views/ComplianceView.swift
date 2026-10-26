import SwiftUI
import Combine
import UIKit
import EatFairShared

// MARK: - Compliance & Safety Screen (TNC)
struct ComplianceView: View {
    let driverId: Int
    @StateObject private var viewModel: ComplianceViewModel

    init(driverId: Int) {
        self.driverId = driverId
        _viewModel = StateObject(wrappedValue: ComplianceViewModel(driverId: driverId))
    }

    var body: some View {
        ScrollView {
            if viewModel.isLoading {
                ProgressView("Loading compliance status...")
                    .tint(Theme.lxOrange)
                    .foregroundColor(Theme.lxTextSecondary)
                    .padding(.top, 40)
            } else {
                VStack(spacing: 16) {
                    backgroundCheckSection
                    vehicleInspectionSection
                    accessibilitySection
                }
                .padding()
            }
        }
        .background(Theme.lxBg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .navigationTitle("Compliance & Safety")
        .onAppear { viewModel.loadAll() }
        .onDisappear { viewModel.stopPolling() }
        .alert("Inspection Submitted", isPresented: $viewModel.showInspectionSuccess) {
            Button("OK") { viewModel.showInspectionForm = false }
        } message: {
            Text("Your vehicle inspection has been recorded.")
        }
    }

    // MARK: - Background Check
    /// Explains the current status instead of always saying "in progress".
    private var backgroundCheckMessage: String {
        switch viewModel.bgCheckStatus.lowercased() {
        case "passed", "clear", "complete", "completed", "valid":
            return "Your background check is complete."
        case "pending", "processing", "in_progress":
            return "Your background check is in progress. This screen updates automatically when Checkr reports a result."
        default:
            return "Your background check needs attention. Contact support if you have questions."
        }
    }

    @ViewBuilder
    private var backgroundCheckSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Background Check", systemImage: "person.badge.shield.checkmark")
                .font(.headline)
                .foregroundColor(Theme.lxText)
            HStack {
                statusBadge(viewModel.bgCheckStatus)
                Spacer()
                if let date = viewModel.bgCheckDate {
                    Text("Checked: \(String(date.prefix(10)))")
                        .font(.caption)
                        .foregroundColor(Theme.lxTextSecondary)
                }
            }
            // In-app Checkr initiation. Hidden once the check is pending/clear.
            if viewModel.canStartBackgroundCheck {
                Text("Complete your Checkr background check to start accepting rides. You'll be taken to Checkr's secure page to finish.")
                    .font(.caption)
                    .foregroundColor(Theme.lxTextSecondary)

                Button(action: { viewModel.startBackgroundCheck() }) {
                    HStack {
                        if viewModel.isInitiatingCheck {
                            ProgressView()
                        } else {
                            Label("Start background check", systemImage: "shield.lefthalf.filled")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.lxOrange)
                .disabled(viewModel.isInitiatingCheck)
            } else {
                Text(backgroundCheckMessage)
                    .font(.caption)
                    .foregroundColor(Theme.lxTextSecondary)
            }

            if let error = viewModel.bgCheckError {
                Text(error).font(.caption).foregroundColor(Theme.lxError)
            }
        }
        .padding()
        .background(Theme.lxSurface)
        .cornerRadius(Lx.Radius.button)
        .overlay(RoundedRectangle(cornerRadius: Lx.Radius.button).stroke(Theme.lxHairline, lineWidth: 1))
    }

    // MARK: - Vehicle Inspection
    @ViewBuilder
    private var vehicleInspectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Vehicle Inspection", systemImage: "car.badge.gearshape")
                .font(.headline)
                .foregroundColor(Theme.lxText)
            HStack {
                statusBadge(viewModel.inspectionStatus)
                Spacer()
                if let days = viewModel.inspectionDaysRemaining {
                    Text(days >= 0 ? "\(days) days remaining" : "Overdue by \(abs(days)) days")
                        .font(.caption)
                        .foregroundColor(days <= 30 ? Theme.lxOrange : Theme.lxTextSecondary)
                }
            }
            if let nextDue = viewModel.inspectionNextDue {
                Text("Next due: \(nextDue)")
                    .font(.caption)
                    .foregroundColor(Theme.lxTextSecondary)
            }
            Button(action: { viewModel.showInspectionForm = true }) {
                Label("Submit Inspection", systemImage: "doc.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Theme.lxOrange)
            .sheet(isPresented: $viewModel.showInspectionForm) {
                inspectionFormSheet
            }
        }
        .padding()
        .background(Theme.lxSurface)
        .cornerRadius(Lx.Radius.button)
        .overlay(RoundedRectangle(cornerRadius: Lx.Radius.button).stroke(Theme.lxHairline, lineWidth: 1))
    }

    @ViewBuilder
    private var inspectionFormSheet: some View {
        NavigationView {
            Form {
                DatePicker("Inspection Date", selection: $viewModel.inspectionDate, in: ...Date(), displayedComponents: .date)
                TextField("Facility Name *", text: $viewModel.facilityName)
                TextField("BAR License Number", text: $viewModel.barLicense)
                TextField("Mileage at Inspection", text: $viewModel.mileage)
                    .keyboardType(.numberPad)
                TextField("Document URL *", text: $viewModel.documentUrl)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                if let error = viewModel.errorMessage {
                    Text(error).foregroundColor(Theme.lxError).font(.caption)
                }

                Button(action: { viewModel.submitInspection() }) {
                    if viewModel.isSubmittingInspection {
                        ProgressView()
                    } else {
                        Text("Submit")
                    }
                }
                .tint(Theme.lxOrange)
                .disabled(viewModel.facilityName.isEmpty || viewModel.documentUrl.isEmpty || viewModel.isSubmittingInspection)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.lxBg.ignoresSafeArea())
            .navigationTitle("Submit Inspection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { viewModel.showInspectionForm = false }
                        .foregroundColor(Theme.lxOrange)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Accessibility Capability
    @ViewBuilder
    private var accessibilitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Accessibility Capability", systemImage: "figure.roll")
                .font(.headline)
                .foregroundColor(Theme.lxText)

            Toggle("My vehicle is wheelchair accessible", isOn: $viewModel.accessibilityCapable)
                .tint(Theme.lxOrange)
                .foregroundColor(Theme.lxText)
                .onChange(of: viewModel.accessibilityCapable) { _ in
                    viewModel.saveAccessibility()
                }

            if viewModel.accessibilityCapable {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Wheelchair ramp/lift", isOn: $viewModel.wheelchairAccessible)
                        .font(.subheadline).tint(Theme.lxOrange).foregroundColor(Theme.lxTextSecondary)
                        .onChange(of: viewModel.wheelchairAccessible) { _ in viewModel.saveAccessibility() }
                    Toggle("Service animal friendly", isOn: $viewModel.serviceAnimalFriendly)
                        .font(.subheadline).tint(Theme.lxOrange).foregroundColor(Theme.lxTextSecondary)
                        .onChange(of: viewModel.serviceAnimalFriendly) { _ in viewModel.saveAccessibility() }
                    Toggle("Extra trunk space for mobility aids", isOn: $viewModel.mobilityStorage)
                        .font(.subheadline).tint(Theme.lxOrange).foregroundColor(Theme.lxTextSecondary)
                        .onChange(of: viewModel.mobilityStorage) { _ in viewModel.saveAccessibility() }
                }
                .padding(.leading, 4)
            }

            if viewModel.isSaving {
                HStack {
                    ProgressView().scaleEffect(0.7).tint(Theme.lxOrange)
                    Text("Saving...").font(.caption).foregroundColor(Theme.lxTextSecondary)
                }
            }
        }
        .padding()
        .background(Theme.lxSurface)
        .cornerRadius(Lx.Radius.button)
        .overlay(RoundedRectangle(cornerRadius: Lx.Radius.button).stroke(Theme.lxHairline, lineWidth: 1))
    }

    // MARK: - Helpers
    @ViewBuilder
    private func statusBadge(_ status: String) -> some View {
        let (color, icon, text): (Color, String, String) = {
            switch status {
            case "passed", "valid": return (Theme.lxSuccess, "checkmark.circle.fill", status.capitalized)
            case "pending": return (Theme.lxOrange, "clock.fill", "Pending")
            case "expired": return (Theme.lxError, "xmark.circle.fill", "Expired")
            case "failed": return (Theme.lxError, "xmark.circle.fill", "Failed")
            default: return (Theme.lxTextMuted, "questionmark.circle", "Not Started")
            }
        }()
        Label(text, systemImage: icon)
            .font(.subheadline.weight(.medium))
            .foregroundColor(color)
    }
}

// MARK: - ViewModel
class ComplianceViewModel: ObservableObject {
    @Published var bgCheckStatus = "not_started"
    @Published var bgCheckDate: String?
    @Published var inspectionStatus = "missing"
    @Published var inspectionNextDue: String?
    @Published var inspectionDaysRemaining: Int?
    @Published var accessibilityCapable = false
    @Published var wheelchairAccessible = false
    @Published var serviceAnimalFriendly = false
    @Published var mobilityStorage = false
    @Published var isLoading = true
    @Published var isSaving = false
    @Published var showInspectionForm = false
    @Published var showInspectionSuccess = false
    @Published var isSubmittingInspection = false
    @Published var errorMessage: String?
    @Published var inspectionDate = Date()
    @Published var facilityName = ""
    @Published var barLicense = ""
    @Published var mileage = ""
    @Published var documentUrl = ""

    // Checkr background-check initiation state
    @Published var isInitiatingCheck = false
    @Published var bgCheckError: String?

    private let driverId: Int
    private var bgPollTimer: Timer?

    /// The driver can kick off a new Checkr check only when one is not already
    /// in progress or completed. `pending`/`clear`/`consider`/`passed` hide the button.
    var canStartBackgroundCheck: Bool {
        switch bgCheckStatus.lowercased() {
        case "pending", "clear", "consider", "passed", "valid", "complete", "completed":
            return false
        default:
            return true
        }
    }

    init(driverId: Int) {
        self.driverId = driverId
    }

    deinit {
        bgPollTimer?.invalidate()
    }

    /// Initiate an in-app Checkr background check, then open the Checkr-hosted invitation URL.
    func startBackgroundCheck() {
        guard !isInitiatingCheck else { return }
        isInitiatingCheck = true
        bgCheckError = nil

        P2PAPIService.shared.initiateBackgroundCheck { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isInitiatingCheck = false
                switch result {
                case .success(let invitation):
                    if let urlString = invitation.invitationUrl,
                       let url = URL(string: urlString) {
                        UIApplication.shared.open(url)
                    }
                    // Reflect the new state and begin polling for the result.
                    self.bgCheckStatus = invitation.status ?? "pending"
                    self.startPolling()
                case .failure(let error):
                    self.bgCheckError = error.localizedDescription
                }
            }
        }
    }

    /// Poll the Checkr status so the compliance screen reflects pending → clear/consider.
    func startPolling() {
        bgPollTimer?.invalidate()
        bgPollTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            P2PAPIService.shared.getBackgroundCheckStatus(driverId: self.driverId) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if let status = result?["status"] as? String {
                        self.bgCheckStatus = status
                        self.bgCheckDate = result?["checked_at"] as? String
                        // Stop polling once we reach a terminal state.
                        if !self.canStartBackgroundCheck && status.lowercased() != "pending" {
                            self.stopPolling()
                        }
                    }
                }
            }
        }
    }

    func stopPolling() {
        bgPollTimer?.invalidate()
        bgPollTimer = nil
    }

    func loadAll() {
        isLoading = true
        let group = DispatchGroup()

        group.enter()
        P2PAPIService.shared.getBackgroundCheckStatus(driverId: driverId) { [weak self] result in
            self?.bgCheckStatus = result?["status"] as? String ?? "not_started"
            self?.bgCheckDate = result?["checked_at"] as? String
            group.leave()
        }

        group.enter()
        P2PAPIService.shared.getVehicleInspectionStatus(driverId: driverId) { [weak self] result in
            self?.inspectionStatus = result?["status"] as? String ?? "missing"
            self?.inspectionNextDue = result?["next_due_date"] as? String
            self?.inspectionDaysRemaining = result?["days_until_due"] as? Int
            group.leave()
        }

        group.enter()
        P2PAPIService.shared.getDriverAccessibility { [weak self] result in
            self?.accessibilityCapable = result?["accessibility_capable"] as? Bool ?? false
            if let features = result?["accessibility_features"] as? [String: Bool] {
                self?.wheelchairAccessible = features["wheelchair"] ?? false
                self?.serviceAnimalFriendly = features["service_animal"] ?? false
                self?.mobilityStorage = features["mobility_storage"] ?? false
            }
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.isLoading = false
            // Keep the screen live while a check is pending.
            if self.bgCheckStatus.lowercased() == "pending" {
                self.startPolling()
            }
        }
    }

    func saveAccessibility() {
        isSaving = true
        let features: [String: Bool] = [
            "wheelchair": wheelchairAccessible,
            "service_animal": serviceAnimalFriendly,
            "mobility_storage": mobilityStorage,
        ]
        P2PAPIService.shared.updateDriverAccessibility(capable: accessibilityCapable, features: features) { [weak self] _ in
            self?.isSaving = false
        }
    }

    func submitInspection() {
        isSubmittingInspection = true
        errorMessage = nil
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        P2PAPIService.shared.submitVehicleInspection(
            driverId: driverId,
            inspectionDate: formatter.string(from: inspectionDate),
            facilityName: facilityName,
            barLicense: barLicense.isEmpty ? nil : barLicense,
            mileage: Int(mileage),
            documentUrl: documentUrl
        ) { [weak self] success in
            self?.isSubmittingInspection = false
            if success {
                self?.showInspectionSuccess = true
                self?.loadAll()
            } else {
                self?.errorMessage = "Failed to submit inspection"
            }
        }
    }
}
