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

// MARK: - Prop 22 Data Models

struct Prop22Period: Codable, Identifiable {
    let id: Int
    let periodStart: String
    let periodEnd: String
    let status: String
    let serviceType: String
    let engagedHours: Double
    let engagedMiles: Double
    let netEarnings: Double
    let prop22Floor: Double
    let topUpAmount: Double
    let deadlineAt: String?
    let qtdEngagedHours: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case periodStart = "period_start"
        case periodEnd = "period_end"
        case status
        case serviceType = "service_type"
        case engagedHours = "engaged_hours"
        case engagedMiles = "engaged_miles"
        case netEarnings = "net_earnings"
        case prop22Floor = "prop22_floor"
        case topUpAmount = "top_up_amount"
        case deadlineAt = "deadline_at"
        case qtdEngagedHours = "qtd_engaged_hours"
    }
}

struct Prop22RideItem: Decodable, Identifiable {
    let id: Int   // ride_id (rideshare) or order_id (food delivery)
    let completedAt: String?
    let prop22EngagedHours: Double?
    let prop22EngagedMiles: Double?
    let prop22FloorAmount: Double?

    // Custom decode: API returns ride_id for rideshare, order_id for food delivery
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let rideId = try? container.decode(Int.self, forKey: .rideId) {
            self.id = rideId
        } else if let orderId = try? container.decode(Int.self, forKey: .orderId) {
            self.id = orderId
        } else {
            self.id = 0
        }
        completedAt = try? container.decode(String.self, forKey: .completedAt)
        prop22EngagedHours = try? container.decode(Double.self, forKey: .prop22EngagedHours)
        prop22EngagedMiles = try? container.decode(Double.self, forKey: .prop22EngagedMiles)
        prop22FloorAmount = try? container.decode(Double.self, forKey: .prop22FloorAmount)
    }

    private enum CodingKeys: String, CodingKey {
        case rideId = "ride_id"
        case orderId = "order_id"
        case completedAt = "completed_at"
        case prop22EngagedHours = "prop22_engaged_hours"
        case prop22EngagedMiles = "prop22_engaged_miles"
        case prop22FloorAmount = "prop22_floor_amount"
    }
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

    // Prop 22 compliance state
    @State private var prop22Periods: [Prop22Period] = []
    @State private var prop22Loading = true
    @State private var prop22Error: String?

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
                            prop22Section()
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

    private func formatDate(_ dateStr: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateStr) {
            let df = DateFormatter()
            df.dateStyle = .short
            df.timeStyle = .short
            return df.string(from: date)
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: dateStr) {
            let df = DateFormatter()
            df.dateStyle = .short
            df.timeStyle = .short
            return df.string(from: date)
        }
        return dateStr
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

    // MARK: - Prop 22 Compliance Section

    @ViewBuilder
    private func prop22Section() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Prop 22 Compliance")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(Theme.lxText)
                .padding(.top, 8)

            if prop22Loading {
                HStack {
                    Spacer()
                    ProgressView("Loading Prop 22 data...")
                    Spacer()
                }
                .padding()
            } else if let error = prop22Error {
                Text(error)
                    .foregroundColor(Theme.lxError)
                    .font(.caption)
            } else if prop22Periods.isEmpty {
                Text("No Prop 22 periods yet. Periods are calculated every 14 days.")
                    .foregroundColor(Theme.lxTextSecondary)
                    .font(.caption)
            } else {
                ForEach(prop22Periods) { period in
                    NavigationLink(destination: Prop22PeriodDetailView(period: period)) {
                        prop22PeriodCard(period)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .onAppear { fetchProp22Periods() }
    }

    @ViewBuilder
    private func prop22PeriodCard(_ period: Prop22Period) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(formatProp22PeriodDate(period.periodStart, period.periodEnd))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(Theme.lxText)
                Spacer()
                prop22StatusBadge(period.status)
            }

            Divider().overlay(Theme.lxHairline)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Engaged Hours")
                        .font(.caption)
                        .foregroundColor(Theme.lxTextSecondary)
                    Text(String(format: "%.1f hrs", period.engagedHours))
                        .font(.subheadline)
                        .foregroundColor(Theme.lxText)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Engaged Miles")
                        .font(.caption)
                        .foregroundColor(Theme.lxTextSecondary)
                    Text(String(format: "%.1f mi", period.engagedMiles))
                        .font(.subheadline)
                        .foregroundColor(Theme.lxText)
                }
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your Earnings")
                        .font(.caption)
                        .foregroundColor(Theme.lxTextSecondary)
                    Text(String(format: "$%.2f", period.netEarnings))
                        .font(.subheadline)
                        .foregroundColor(Theme.lxText)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Earnings Floor")
                        .font(.caption)
                        .foregroundColor(Theme.lxTextSecondary)
                    Text(String(format: "$%.2f", period.prop22Floor))
                        .font(.subheadline)
                        .foregroundColor(Theme.lxText)
                }
                if period.topUpAmount > 0 {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Top-Up")
                            .font(.caption)
                            .foregroundColor(Theme.lxTextSecondary)
                        Text(String(format: "$%.2f", period.topUpAmount))
                            .font(.subheadline)
                            .foregroundColor(Theme.lxSuccess)
                    }
                }
            }

            // Deadline shown only for MANUAL_REVIEW and OVERDUE — BPC §7454(b)
            if ["MANUAL_REVIEW", "OVERDUE"].contains(period.status),
               let deadline = period.deadlineAt {
                Text("Payment due by: \(formatDeadlineDate(deadline))")
                    .font(.caption)
                    .foregroundColor(period.status == "OVERDUE" ? Theme.lxError : Theme.lxOrange)
            }
        }
        .padding()
        .background(Theme.lxSurface)
        .cornerRadius(Lx.Radius.button)
        .overlay(RoundedRectangle(cornerRadius: Lx.Radius.button).stroke(Theme.lxHairline, lineWidth: 1))
        .shadow(color: Lx.Palette.shadow.opacity(0.06), radius: 4, x: 0, y: 2)
    }

    @ViewBuilder
    private func prop22StatusBadge(_ status: String) -> some View {
        let (label, color): (String, Color) = {
            switch status {
            case "PENDING":       return ("Calculating", Theme.lxOrange)
            case "RECONCILED":    return ("No Top-Up", Theme.lxSuccess)
            case "PAID":          return ("Paid", Theme.lxSuccess)
            case "MANUAL_REVIEW": return ("Review", Theme.lxOrange)
            case "OVERDUE":       return ("Overdue", Theme.lxError)
            default:              return (status, Theme.lxTextMuted)
            }
        }()

        Text(label)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(Lx.Radius.chip)
    }

    private func fetchProp22Periods() {
        prop22Loading = true
        prop22Error = nil

        guard let url = URL(string: "\(baseURL)/api/driver/prop22/periods") else {
            prop22Loading = false
            prop22Error = "Invalid URL"
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
                self.prop22Loading = false
                if let error = error {
                    self.prop22Error = "Failed to load Prop 22 data: \(error.localizedDescription)"
                    logger.error("[PayoutDashboard] Prop22 fetch failed: \(error.localizedDescription)")
                    return
                }
                guard let data = data else {
                    self.prop22Error = "No data received"
                    return
                }
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    self.prop22Error = "Server error (\(httpResponse.statusCode))"
                    return
                }
                do {
                    self.prop22Periods = try JSONDecoder().decode([Prop22Period].self, from: data)
                    logger.info("[PayoutDashboard] Loaded \(self.prop22Periods.count) Prop22 periods")
                } catch {
                    self.prop22Error = "Could not parse Prop 22 data"
                    logger.error("[PayoutDashboard] Prop22 decode error: \(error.localizedDescription)")
                }
            }
        }.resume()
    }

    private func formatProp22PeriodDate(_ start: String, _ end: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "MMM d"
        func parse(_ s: String) -> Date? {
            if let d = formatter.date(from: s) { return d }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: s)
        }
        if let startDate = parse(start), let endDate = parse(end) {
            return "\(displayFormatter.string(from: startDate)) – \(displayFormatter.string(from: endDate))"
        }
        return "\(start) – \(end)"
    }

    private func formatDeadlineDate(_ deadlineString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        if let date = formatter.date(from: deadlineString) { return displayFormatter.string(from: date) }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: deadlineString) { return displayFormatter.string(from: date) }
        return deadlineString
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

// MARK: - Prop 22 Period Detail View

struct Prop22PeriodDetailView: View {
    let period: Prop22Period
    @State private var rides: [Prop22RideItem] = []
    @State private var loading = true

    private let baseURL = AppConfig.shared.p2pAPIBaseURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // QTD Engaged Hours — BPC §7454(b)(2) disclosure
                if let qtdHours = period.qtdEngagedHours {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("QTD Engaged Hours")
                                .font(.caption)
                                .foregroundColor(Theme.lxTextSecondary)
                            Text(String(format: "%.1f hours", qtdHours))
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(Theme.lxText)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(Theme.lxSurface2)
                    .cornerRadius(Lx.Radius.chip)
                    .overlay(RoundedRectangle(cornerRadius: Lx.Radius.chip).stroke(Theme.lxHairline, lineWidth: 1))
                    .padding(.horizontal)
                }

                Text("Rides / Deliveries")
                    .font(.headline)
                    .foregroundColor(Theme.lxText)
                    .padding(.horizontal)

                if loading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding()
                } else if rides.isEmpty {
                    Text("No rides found for this period.")
                        .foregroundColor(Theme.lxTextSecondary)
                        .font(.caption)
                        .padding(.horizontal)
                } else {
                    VStack(spacing: 0) {
                        ForEach(rides) { ride in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(formatCompletedAt(ride.completedAt))
                                        .font(.subheadline)
                                        .foregroundColor(Theme.lxText)
                                    if let hours = ride.prop22EngagedHours {
                                        Text(String(format: "%.2f hrs · %.1f mi",
                                                    hours,
                                                    ride.prop22EngagedMiles ?? 0))
                                            .font(.caption)
                                            .foregroundColor(Theme.lxTextSecondary)
                                    }
                                }
                                Spacer()
                                // prop22_floor_amount: nil = "—" (pre-deployment), 0.0 = "$0.00"
                                if let floor = ride.prop22FloorAmount {
                                    Text(String(format: "$%.2f", floor))
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(Theme.lxText)
                                } else {
                                    Text("—")
                                        .font(.subheadline)
                                        .foregroundColor(Theme.lxTextSecondary)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                            Divider().overlay(Theme.lxHairline).padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.lxBg.ignoresSafeArea())
        .navigationTitle("Period Detail")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .onAppear { fetchRides() }
    }

    private func fetchRides() {
        loading = true
        guard let url = URL(string: "\(baseURL)/api/driver/prop22/periods/\(period.id)/rides") else {
            loading = false
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = SecureStorage.shared.driverAccessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                self.loading = false
                if let data = data,
                   let items = try? JSONDecoder().decode([Prop22RideItem].self, from: data) {
                    self.rides = items
                }
            }
        }.resume()
    }

    private func formatCompletedAt(_ dateString: String?) -> String {
        guard let s = dateString else { return "Unknown" }
        let formatter = ISO8601DateFormatter()
        let display = DateFormatter()
        display.dateFormat = "MMM d, h:mm a"
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: s) { return display.string(from: date) }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: s) { return display.string(from: date) }
        return s
    }
}
