//
//  DisputeRideView.swift
//  eatfaircustomer
//
//  Created by Dollor.ai
//  Dispute/report issue for a completed ride
//

import SwiftUI
import EatFairShared
import os

private let logger = Logger(subsystem: "com.dollorai.customer", category: "DisputeRideView")

// MARK: - Dispute Models

enum DisputeReasonOption: String, CaseIterable, Identifiable {
    case wrongRoute = "wrong_route"
    case overcharged = "overcharged"
    case safetyConcern = "safety_concern"
    case driverBehavior = "driver_behavior"
    case other = "other"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .wrongRoute: return "Wrong Route"
        case .overcharged: return "Overcharged"
        case .safetyConcern: return "Safety Concern"
        case .driverBehavior: return "Driver Behavior"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .wrongRoute: return "arrow.triangle.turn.up.right.diamond"
        case .overcharged: return "dollarsign.circle"
        case .safetyConcern: return "exclamationmark.shield"
        case .driverBehavior: return "person.crop.circle.badge.exclamationmark"
        case .other: return "ellipsis.circle"
        }
    }
}

struct DisputeResponse: Codable {
    let success: Bool?
    let message: String?
    let dispute: DisputeResponseDetail?
}

struct DisputeResponseDetail: Codable {
    let id: Int
    let rideRequestId: Int?
    let reason: String?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case id
        case rideRequestId = "ride_request_id"
        case reason
        case status
    }
}

// MARK: - Dispute Ride View

struct DisputeRideView: View {
    let rideRequestId: Int

    @Environment(\.dismiss) var dismiss
    @State private var selectedReason: DisputeReasonOption?
    @State private var descriptionText = ""
    @State private var isSubmitting = false
    @State private var submitted = false
    @State private var disputeId: Int?
    @State private var errorMessage: String?

    private let baseURL = AppConfig.shared.p2pAPIBaseURL

    var body: some View {
        NavigationView {
            Group {
                if submitted {
                    submittedView
                } else {
                    formView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.lxBg.ignoresSafeArea())
            .navigationTitle("Report Issue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(submitted ? "Done" : "Cancel") { dismiss() }
                        .foregroundColor(Theme.lxOrange)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Form View

    @ViewBuilder
    private var formView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .resizable()
                        .frame(width: 40, height: 36)
                        .foregroundColor(Theme.lxOrange)

                    Text("What went wrong?")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.lxText)

                    Text("Ride #\(rideRequestId)")
                        .font(.caption)
                        .foregroundColor(Theme.lxTextSecondary)
                }
                .padding(.top)

                // Reason Selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Select a reason")
                        .font(.headline)
                        .foregroundColor(Theme.lxText)

                    ForEach(DisputeReasonOption.allCases) { reason in
                        Button(action: { selectedReason = reason }) {
                            HStack(spacing: 12) {
                                Image(systemName: reason.icon)
                                    .font(.title3)
                                    .frame(width: 30)
                                    .foregroundColor(selectedReason == reason ? .white : Theme.lxText)

                                Text(reason.displayName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(selectedReason == reason ? .white : Theme.lxText)

                                Spacer()

                                if selectedReason == reason {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(Lx.Palette.onAccent)
                                }
                            }
                            .padding()
                            .background(selectedReason == reason ? Theme.lxOrange : Theme.lxSurface)
                            .cornerRadius(Lx.Radius.button)
                            .overlay(
                                RoundedRectangle(cornerRadius: Lx.Radius.button)
                                    .stroke(selectedReason == reason ? Color.clear : Theme.lxHairline, lineWidth: 1)
                            )
                        }
                    }
                }

                // Description
                VStack(alignment: .leading, spacing: 8) {
                    Text("Details")
                        .font(.headline)
                        .foregroundColor(Theme.lxText)

                    TextEditor(text: $descriptionText)
                        .frame(height: 120)
                        .padding(8)
                        .scrollContentBackground(.hidden)
                        .foregroundColor(Theme.lxText)
                        .background(Theme.lxSurface2)
                        .cornerRadius(Lx.Radius.button)
                        .overlay(
                            RoundedRectangle(cornerRadius: Lx.Radius.button)
                                .stroke(Theme.lxHairline, lineWidth: 1)
                        )

                    Text("\(descriptionText.count)/500")
                        .font(.caption2)
                        .foregroundColor(Theme.lxTextMuted)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                // Error
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(Theme.lxError)
                        .padding(8)
                        .background(Theme.lxError.opacity(0.1))
                        .cornerRadius(Lx.Radius.chip)
                }

                // Submit
                Button(action: submitDispute) {
                    HStack {
                        if isSubmitting {
                            ProgressView()
                                .tint(Lx.Palette.onAccent)
                        } else {
                            Image(systemName: "paperplane.fill")
                            Text("Submit Report")
                        }
                    }
                    .font(.headline)
                    .foregroundColor(Lx.Palette.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(selectedReason != nil ? AnyShapeStyle(Theme.lxButtonGradient) : AnyShapeStyle(Theme.lxTextMuted))
                    .cornerRadius(Lx.Radius.button)
                    .shadow(color: selectedReason != nil ? Theme.lxOrange.opacity(0.4) : Color.clear, radius: 14, x: 0, y: 6)
                }
                .disabled(selectedReason == nil || isSubmitting)

                Spacer(minLength: 20)
            }
            .padding()
        }
    }

    // MARK: - Submitted View

    @ViewBuilder
    private var submittedView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .frame(width: 64, height: 64)
                .foregroundColor(Theme.lxSuccess)

            Text("Report Submitted")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(Theme.lxText)

            if let id = disputeId {
                Text("Dispute #\(id)")
                    .font(.subheadline)
                    .foregroundColor(Theme.lxTextSecondary)
            }

            Text("We'll review your report and get back to you. If a refund is warranted, it will be processed within 3-5 business days.")
                .font(.subheadline)
                .foregroundColor(Theme.lxTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            Button("Done") { dismiss() }
                .font(.headline)
                .foregroundColor(Lx.Palette.onAccent)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Theme.lxButtonGradient)
                .cornerRadius(Lx.Radius.button)
                .shadow(color: Theme.lxOrange.opacity(0.4), radius: 14, x: 0, y: 6)
                .padding(.horizontal)
                .padding(.bottom)
        }
    }

    // MARK: - API

    private func submitDispute() {
        guard let reason = selectedReason else { return }
        isSubmitting = true
        errorMessage = nil

        guard let url = URL(string: "\(baseURL)/api/rides/dispute") else {
            errorMessage = "Invalid URL"
            isSubmitting = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = SecureStorage.shared.customerAccessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "ride_request_id": rideRequestId,
            "reason": reason.rawValue,
            "description": String(descriptionText.prefix(500))
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isSubmitting = false

                if let error = error {
                    errorMessage = error.localizedDescription
                    logger.error("[DisputeRideView] Submit failed: \(error.localizedDescription)")
                    return
                }

                guard let data = data else {
                    errorMessage = "No data received"
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    if let errJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let detail = errJson["detail"] as? String {
                        errorMessage = detail
                    } else {
                        errorMessage = "Failed to submit report"
                    }
                    return
                }

                if let parsed = try? JSONDecoder().decode(DisputeResponse.self, from: data) {
                    disputeId = parsed.dispute?.id
                }
                submitted = true
                logger.info("[DisputeRideView] Dispute submitted for ride \(rideRequestId)")
            }
        }.resume()
    }
}
