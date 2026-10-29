//
//  PayoutDashboardView.swift
//  eatffairdelivery
//
//  Created by Dollor.ai
//  Per-ride payout breakdown with period filtering
//

import SwiftUI
import EatFairShared
import os

private let logger = Logger(subsystem: "com.dollorai.delivery", category: "PayoutDashboardView")

// MARK: - Payout Data Models

struct PayoutSummary: Codable {
    let totalGross: Double
    let totalFees: Double
    let totalTips: Double
    let totalNet: Double
    let rideCount: Int
    let avgPerRide: Double

    enum CodingKeys: String, CodingKey {
        case totalGross = "total_gross"
        case totalFees = "total_fees"
        case totalTips = "total_tips"
        case totalNet = "total_net"
        case rideCount = "ride_count"
        case avgPerRide = "avg_per_ride"
    }
}

struct PayoutRideItem: Codable, Identifiable {
    let id: Int
    let date: String?
    let fare: Double
    let platformFee: Double
    let tip: Double
    let netPayout: Double
    let stripeStatus: String?
    let pickupAddress: String?
    let dropoffAddress: String?

    enum CodingKeys: String, CodingKey {
        case id = "ride_id"
        case date
        case fare
        case platformFee = "platform_fee"
        case tip
        case netPayout = "net_payout"
        case stripeStatus = "stripe_status"
        case pickupAddress = "pickup_address"
        case dropoffAddress = "dropoff_address"
    }
}

struct PayoutHistoryResponse: Codable {
    let summary: PayoutSummary
    let rides: [PayoutRideItem]
    let period: String
}

// MARK: - Payout Dashboard View

struct PayoutDashboardView: View {
    @Environment(\.dismiss) var dismiss
    @State private var response: PayoutHistoryResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedPeriod = "week"
    @State private var expandedRideId: Int?
    // Optional server fields: nil shows a dash, never a made-up $0.00 / 0.0 h
    @State private var availableBalance: Double?
    @State private var hoursOnline: Double?

    private let baseURL = AppConfig.shared.p2pAPIBaseURL
    private let periods = ["today", "week", "month"]
    private let periodLabels = ["Today": "today", "This Week": "week", "This Month": "month"]

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Period Selector
                Picker("Period", selection: $selectedPeriod) {
                    Text("Today").tag("today")
                    Text("This Week").tag("week")
                    Text("This Month").tag("month")
                }
                .pickerStyle(.segmented)
                .padding()
                .onChange(of: selectedPeriod) { fetchPayoutHistory() }

                if isLoading {
                    Spacer()
                    ProgressView("Loading payouts...")
                    Spacer()
                } else if let error = errorMessage {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundColor(Theme.lxOrange)
                        Text(error)
                            .foregroundColor(Theme.lxTextSecondary)
                        Button("Retry") { fetchPayoutHistory() }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.lxOrange)
                    }
                    Spacer()
                } else if let response = response {
                    ScrollView {
                        VStack(spacing: 16) {
                            summaryCard(response.summary)
                            ridesList(response.rides)
                        }
                        .padding()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.lxBg.ignoresSafeArea())
            .navigationTitle("Payout History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Theme.lxOrange)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: openStripeDashboard) {
                        Image(systemName: "building.columns")
                            .foregroundColor(Theme.lxOrange)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { fetchPayoutHistory() }
    }

    // MARK: - Summary Card

    @ViewBuilder
    private func summaryCard(_ summary: PayoutSummary) -> some View {
        VStack(spacing: 16) {
            // Net Earnings
            VStack(spacing: 4) {
                Text("Net Earnings")
                    .font(.subheadline)
                    .foregroundColor(Theme.lxTextSecondary)
                Text("$\(String(format: "%.2f", summary.totalNet))")
                    .font(Lx.Typography.icon.weight(.bold))
                    .foregroundColor(Theme.lxText)
            }

            Divider().overlay(Theme.lxHairline)

            // Breakdown
            HStack(spacing: 20) {
                summaryItem(label: "Gross", value: summary.totalGross, color: Theme.lxText)
                summaryItem(label: "Fees", value: -summary.totalFees, color: Theme.lxError)
                summaryItem(label: "Tips", value: summary.totalTips, color: Theme.lxSuccess)
            }

            Divider().overlay(Theme.lxHairline)

            // Stats
            HStack {
                VStack(spacing: 2) {
                    Text("\(summary.rideCount)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.lxText)
                    Text("Rides")
                        .font(.caption)
                        .foregroundColor(Theme.lxTextSecondary)
                }
                Spacer()
                VStack(spacing: 2) {
                    Text("$\(String(format: "%.2f", summary.avgPerRide))")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.lxText)
                    Text("Avg/Ride")
                        .font(.caption)
                        .foregroundColor(Theme.lxTextSecondary)
                }
                Spacer()
                VStack(spacing: 2) {
                    Text(hoursOnline.map { String(format: "%.1f h", $0) } ?? "\u{2014}")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.lxText)
                    Text("Hours online")
                        .font(.caption)
                        .foregroundColor(Theme.lxTextSecondary)
                }
            }

            Divider().overlay(Theme.lxHairline)

            HStack {
                Text("Available to pay out")
                    .font(.subheadline)
                    .foregroundColor(Theme.lxTextSecondary)
                Spacer()
                Text(availableBalance.map { "$\(String(format: "%.2f", $0))" } ?? "\u{2014}")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Theme.lxText)
            }
        }
        .padding()
        .background(Theme.lxSurface)
        .cornerRadius(Lx.Radius.button)
        .overlay(RoundedRectangle(cornerRadius: Lx.Radius.button).stroke(Theme.lxHairline, lineWidth: 1))
    }

    @ViewBuilder
    private func summaryItem(label: String, value: Double, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value >= 0 ? "$\(String(format: "%.2f", value))" : "-$\(String(format: "%.2f", abs(value)))")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(Theme.lxTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Rides List

    @ViewBuilder
    private func ridesList(_ rides: [PayoutRideItem]) -> some View {
        if rides.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "car.slash")
                    .font(.largeTitle)
                    .foregroundColor(Theme.lxTextMuted)
                Text("No rides this period")
                    .foregroundColor(Theme.lxTextSecondary)
            }
            .padding(.vertical, 40)
        } else {
            VStack(spacing: 0) {
                HStack {
                    Text("Rides")
                        .font(.headline)
                        .foregroundColor(Theme.lxText)
                    Spacer()
                    Text("\(rides.count) rides")
                        .font(.caption)
                        .foregroundColor(Theme.lxTextSecondary)
                }
                .padding(.bottom, 8)

                ForEach(rides) { ride in
                    rideRow(ride)
                    if ride.id != rides.last?.id {
                        Divider().overlay(Theme.lxHairline)
                    }
                }
            }
            .padding()
            .background(Theme.lxSurface)
            .cornerRadius(Lx.Radius.button)
            .overlay(RoundedRectangle(cornerRadius: Lx.Radius.button).stroke(Theme.lxHairline, lineWidth: 1))
        }
    }

    @ViewBuilder
    private func rideRow(_ ride: PayoutRideItem) -> some View {
        VStack(spacing: 0) {
            Button(action: {
                withAnimation { expandedRideId = expandedRideId == ride.id ? nil : ride.id }
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ride #\(ride.id)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(Theme.lxText)
                        if let date = ride.date {
                            Text(formatDate(date))
                                .font(.caption)
                                .foregroundColor(Theme.lxTextSecondary)
                        }
                    }

                    Spacer()

                    // Status indicator
                    statusBadge(ride.stripeStatus)

                    Text("$\(String(format: "%.2f", ride.netPayout))")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.lxSuccess)

                    Image(systemName: expandedRideId == ride.id ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(Theme.lxTextMuted)
                }
            }
            .padding(.vertical, 10)

            // Expanded detail
            if expandedRideId == ride.id {
                VStack(spacing: 6) {
                    if let pickup = ride.pickupAddress {
                        HStack(spacing: 6) {
                            Circle().fill(Theme.lxSuccess).frame(width: 6, height: 6)
                            Text(pickup).font(.caption).foregroundColor(Theme.lxTextSecondary).lineLimit(1)
                            Spacer()
                        }
                    }
                    if let dropoff = ride.dropoffAddress {
                        HStack(spacing: 6) {
                            Circle().fill(Theme.lxError).frame(width: 6, height: 6)
                            Text(dropoff).font(.caption).foregroundColor(Theme.lxTextSecondary).lineLimit(1)
                            Spacer()
                        }
                    }
                    Divider().overlay(Theme.lxHairline)
                    HStack {
                        Text("Fare").font(.caption).foregroundColor(Theme.lxTextSecondary)
                        Spacer()
                        Text("$\(String(format: "%.2f", ride.fare))").font(.caption).foregroundColor(Theme.lxText)
                    }
                    HStack {
                        Text("Platform Fee").font(.caption).foregroundColor(Theme.lxTextSecondary)
                        Spacer()
                        Text("-$\(String(format: "%.2f", ride.platformFee))").font(.caption).foregroundColor(Theme.lxError)
                    }
                    if ride.tip > 0 {
                        HStack {
                            Text("Tip").font(.caption).foregroundColor(Theme.lxTextSecondary)
                            Spacer()
                            Text("+$\(String(format: "%.2f", ride.tip))").font(.caption).foregroundColor(Theme.lxSuccess)
                        }
                    }
                }
                .padding(.bottom, 10)
                .padding(.leading, 4)
            }
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: String?) -> some View {
        let (label, color): (String, Color) = {
            switch status?.lowercased() {
            case "paid", "succeeded": return ("Paid", Theme.lxSuccess)
            case "pending": return ("Pending", Theme.lxOrange)
            case "failed": return ("Failed", Theme.lxError)
            default: return ("--", Theme.lxTextMuted)
            }
        }()

        Text(label)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .cornerRadius(Lx.Radius.grabber)
            .padding(.trailing, 8)
    }

    // MARK: - Helpers

    /// Local readable date/time. The server sends naive UTC timestamps (no zone, microsecond
    /// fraction), so a missing zone means UTC.
    private func formatDate(_ dateStr: String) -> String {
        var date: Date?
        let hasZone = dateStr.count > 19 && (dateStr.hasSuffix("Z") || dateStr.dropFirst(19).contains("+") || dateStr.dropFirst(19).contains("-"))
        if hasZone {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            date = iso.date(from: dateStr)
            if date == nil {
                iso.formatOptions = [.withInternetDateTime]
                date = iso.date(from: dateStr)
            }
        } else {
            let parser = DateFormatter()
            parser.locale = Locale(identifier: "en_US_POSIX")
            parser.timeZone = TimeZone(identifier: "UTC")
            parser.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            date = parser.date(from: String(dateStr.prefix(19)))
        }
        guard let date = date else { return dateStr }
        let display = DateFormatter()
        display.dateFormat = "MMM d, h:mm a"
        return display.string(from: date)
    }

    private func openStripeDashboard() {
        guard let driverId = UserDefaults.standard.value(forKey: "p2p_driver_id") as? Int else { return }
        P2PAPIService.shared.getStripeDashboardLink(driverId: driverId) { result in
            if case .success(let urlStr) = result, let url = URL(string: urlStr) {
                DispatchQueue.main.async {
                    UIApplication.shared.open(url)
                }
            }
        }
    }

    // MARK: - API

    private func fetchPayoutHistory() {
        isLoading = true
        errorMessage = nil
        availableBalance = nil
        hoursOnline = nil
        P2PAPIService.shared.getDriverPayoutFields(period: selectedPeriod) { result in
            if case .success(let fields) = result {
                availableBalance = fields.availableBalance
                hoursOnline = fields.hoursOnline
            }
        }

        guard let driverId = UserDefaults.standard.value(forKey: "p2p_driver_id") as? Int else {
            errorMessage = "Driver ID not found"
            isLoading = false
            return
        }

        guard let url = URL(string: "\(baseURL)/api/drivers/\(driverId)/payout-history?period=\(selectedPeriod)") else {
            errorMessage = "Invalid URL"
            isLoading = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = SecureStorage.shared.driverAccessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false

                if let error = error {
                    errorMessage = error.localizedDescription
                    logger.error("[PayoutDashboard] Fetch failed: \(error.localizedDescription)")
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
                        errorMessage = "Server error"
                    }
                    return
                }

                do {
                    self.response = try JSONDecoder().decode(PayoutHistoryResponse.self, from: data)
                    logger.info("[PayoutDashboard] Loaded \(self.response?.rides.count ?? 0) rides")
                } catch {
                    errorMessage = "Failed to parse data"
                    logger.error("[PayoutDashboard] Decode error: \(error.localizedDescription)")
                }
            }
        }.resume()
    }
}
