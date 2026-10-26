import SwiftUI
import EatFairShared

struct SafetyReportSheet: View {
    let driverId: Int
    let rideRequestId: Int?
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: SafetyCategory = .drugAlcohol
    @State private var description: String = ""
    @State private var isSubmitting = false
    @State private var showSuccess = false
    @State private var errorMessage: String?

    enum SafetyCategory: String, CaseIterable, Identifiable {
        case drugAlcohol = "Drug/alcohol suspicion"
        case unsafeDriving = "Unsafe driving"
        case harassment = "Harassment"
        case other = "Other safety concern"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("What happened?")
                        .font(.headline)

                    ForEach(SafetyCategory.allCases) { category in
                        HStack {
                            Image(systemName: selectedCategory == category ? "largecircle.fill.circle" : "circle")
                                .foregroundColor(selectedCategory == category ? .red : .gray)
                            Text(category.rawValue)
                                .font(.subheadline)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { selectedCategory = category }
                    }

                    Text("Describe what happened")
                        .font(.headline)

                    TextEditor(text: $description)
                        .frame(minHeight: 100)
                        .overlay(RoundedRectangle(cornerRadius: Lx.Radius.chip).stroke(Lx.Palette.textMuted.opacity(0.3)))

                    if description.count < 10 && !description.isEmpty {
                        Text("Please provide at least 10 characters")
                            .font(.caption)
                            .foregroundColor(Lx.Palette.error)
                    }

                    Button(action: submitReport) {
                        HStack {
                            if isSubmitting {
                                ProgressView().tint(Lx.Palette.onAccent)
                            }
                            Text("Submit Safety Report")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(description.count >= 10 ? Lx.Palette.error : Lx.Palette.textMuted)
                        .foregroundColor(Lx.Palette.onAccent)
                        .cornerRadius(Lx.Radius.button)
                    }
                    .disabled(description.count < 10 || isSubmitting)

                    if let error = errorMessage {
                        Text(error).font(.caption).foregroundColor(Lx.Palette.error)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Divider()
                        Text("Dollor.ai has a zero-tolerance policy for drug or alcohol use by drivers. Report a suspected violation with this form, by phone, or by email:")
                            .font(.caption).foregroundColor(Lx.Palette.textSecondary)
                        HStack {
                            Image(systemName: "phone.fill").font(.caption)
                            Text(AppConfig.shared.supportPhone).font(.caption.weight(.medium))
                        }
                        HStack {
                            Image(systemName: "envelope.fill").font(.caption)
                            Text(AppConfig.shared.supportEmail).font(.caption.weight(.medium))
                        }
                        Text("You may also contact CPUC directly:")
                            .font(.caption).foregroundColor(Lx.Palette.textSecondary)
                            .padding(.top, 4)
                        HStack {
                            Image(systemName: "phone.fill").font(.caption)
                            Text("1-800-894-9444").font(.caption.weight(.medium))
                        }
                        HStack {
                            Image(systemName: "envelope.fill").font(.caption)
                            Text("CIU_intake@cpuc.ca.gov").font(.caption.weight(.medium))
                        }
                    }
                    .foregroundColor(Lx.Palette.textSecondary)
                }
                .padding()
            }
            .navigationTitle("Report Safety Concern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Report Submitted", isPresented: $showSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text("The driver has been immediately suspended pending investigation. Our safety team will review within 48 hours.")
            }
        }
    }

    private func submitReport() {
        isSubmitting = true
        errorMessage = nil
        let desc = "[\(selectedCategory.rawValue)] \(description)"

        P2PAPIService.shared.reportSafetyConcern(
            driverId: driverId,
            rideRequestId: rideRequestId,
            description: desc
        ) { success in
            isSubmitting = false
            if success {
                showSuccess = true
            } else {
                errorMessage = "Unable to submit report. Please call CPUC at 1-800-894-9444."
            }
        }
    }
}
