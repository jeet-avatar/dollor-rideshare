//
//  RecurringRidesView.swift
//  eatfaircustomer
//
//  Created by Dollor.ai
//  Manage recurring/saved ride patterns
//

import SwiftUI
import EatFairShared
import CoreLocation
import os

private let logger = Logger(subsystem: "com.dollorai.customer", category: "RecurringRidesView")

// MARK: - Recurring Ride Model

struct RecurringRideModel: Codable, Identifiable {
    let id: Int
    let pickupAddress: String?
    let pickupLatitude: Double?
    let pickupLongitude: Double?
    let dropoffAddress: String?
    let dropoffLatitude: Double?
    let dropoffLongitude: Double?
    let scheduleDays: String
    let scheduleTime: String
    let timezone: String?
    let preferredDriverId: Int?
    let maxPrice: Double?
    let isActive: Bool
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case pickupAddress = "pickup_address"
        case pickupLatitude = "pickup_latitude"
        case pickupLongitude = "pickup_longitude"
        case dropoffAddress = "dropoff_address"
        case dropoffLatitude = "dropoff_latitude"
        case dropoffLongitude = "dropoff_longitude"
        case scheduleDays = "schedule_days"
        case scheduleTime = "schedule_time"
        case timezone
        case preferredDriverId = "preferred_driver_id"
        case maxPrice = "max_price"
        case isActive = "is_active"
        case createdAt = "created_at"
    }

    var daysArray: [String] {
        scheduleDays.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    var formattedDays: String {
        let days = daysArray
        let shortMap = ["mon": "Mon", "tue": "Tue", "wed": "Wed", "thu": "Thu", "fri": "Fri", "sat": "Sat", "sun": "Sun"]
        return days.compactMap { shortMap[$0.lowercased()] }.joined(separator: ", ")
    }
}

struct RecurringRidesListResponse: Codable {
    let recurringRides: [RecurringRideModel]

    enum CodingKeys: String, CodingKey {
        case recurringRides = "recurring_rides"
    }
}

// MARK: - Recurring Rides View

struct RecurringRidesView: View {
    @Environment(\.dismiss) var dismiss
    @State private var rides: [RecurringRideModel] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showSetupSheet = false

    private let baseURL = AppConfig.shared.p2pAPIBaseURL

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("Loading saved rides...")
                        .tint(Theme.lxOrange)
                        .foregroundColor(Theme.lxTextSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundColor(Theme.lxOrange)
                        Text(error)
                            .foregroundColor(Theme.lxTextSecondary)
                        Button("Retry") { fetchRecurringRides() }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.lxOrange)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if rides.isEmpty {
                    emptyState
                } else {
                    ridesList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.lxBg.ignoresSafeArea())
            .navigationTitle("Recurring Rides")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Theme.lxOrange)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showSetupSheet = true }) {
                        Image(systemName: "plus")
                            .foregroundColor(Theme.lxOrange)
                    }
                }
            }
            .sheet(isPresented: $showSetupSheet) {
                RecurringRideSetupSheet { fetchRecurringRides() }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { fetchRecurringRides() }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "repeat.circle")
                .resizable()
                .frame(width: 64, height: 64)
                .foregroundColor(Theme.lxTextMuted)

            Text("No Recurring Rides")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(Theme.lxText)

            Text("Save your regular routes to quickly request rides with your preferred drivers.")
                .font(.subheadline)
                .foregroundColor(Theme.lxTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button(action: { showSetupSheet = true }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Recurring Ride")
                }
                .font(.headline)
                .foregroundColor(Lx.Palette.onAccent)
                .padding()
                .background(Theme.lxButtonGradient)
                .cornerRadius(Lx.Radius.button)
                .shadow(color: Theme.lxOrange.opacity(0.4), radius: 14, x: 0, y: 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Rides List

    @ViewBuilder
    private var ridesList: some View {
        List {
            ForEach(rides) { ride in
                recurringRideRow(ride)
                    .listRowBackground(Theme.lxSurface)
                    .listRowSeparatorTint(Theme.lxHairline)
            }
            .onDelete(perform: deleteRide)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.lxBg)
    }

    @ViewBuilder
    private func recurringRideRow(_ ride: RecurringRideModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Route
            HStack(spacing: 8) {
                VStack(spacing: 4) {
                    Circle().fill(Theme.lxSuccess).frame(width: 8, height: 8)
                    Rectangle().fill(Theme.lxHairline).frame(width: 1, height: 14)
                    Circle().fill(Theme.lxError).frame(width: 8, height: 8)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(ride.pickupAddress ?? "Pickup")
                        .font(.caption)
                        .foregroundColor(Theme.lxText)
                        .lineLimit(1)
                    Text(ride.dropoffAddress ?? "Dropoff")
                        .font(.caption)
                        .foregroundColor(Theme.lxText)
                        .lineLimit(1)
                }
            }

            Divider()
                .overlay(Theme.lxHairline)

            // Schedule
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(Theme.lxOrange)
                    .frame(width: 20)
                Text(ride.formattedDays)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(Theme.lxText)

                Spacer()

                Image(systemName: "clock")
                    .foregroundColor(Theme.lxOrange)
                    .frame(width: 20)
                Text(ride.scheduleTime)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(Theme.lxText)
            }

            // Status + Max Price
            HStack {
                HStack(spacing: 4) {
                    Circle()
                        .fill(ride.isActive ? Theme.lxSuccess : Theme.lxTextMuted)
                        .frame(width: 8, height: 8)
                    Text(ride.isActive ? "Active" : "Paused")
                        .font(.caption2)
                        .foregroundColor(ride.isActive ? Theme.lxSuccess : Theme.lxTextMuted)
                }

                Spacer()

                if let maxPrice = ride.maxPrice {
                    Text("Max \(Lx.Money.text(maxPrice))")
                        .font(.caption2)
                        .foregroundColor(Theme.lxTextSecondary)
                }

                if ride.preferredDriverId != nil {
                    Label("Preferred Driver", systemImage: "star.fill")
                        .font(.caption2)
                        .foregroundColor(Theme.lxOrange)
                }
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                deleteRecurringRide(ride.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                toggleActive(ride)
            } label: {
                Label(ride.isActive ? "Pause" : "Activate",
                      systemImage: ride.isActive ? "pause.circle" : "play.circle")
            }
            .tint(ride.isActive ? Theme.lxOrange : Theme.lxSuccess)
        }
    }

    // MARK: - Actions

    private func deleteRide(at offsets: IndexSet) {
        for index in offsets {
            deleteRecurringRide(rides[index].id)
        }
    }

    private func toggleActive(_ ride: RecurringRideModel) {
        updateRecurringRide(ride.id, body: ["is_active": !ride.isActive])
    }

    // MARK: - API

    private func fetchRecurringRides() {
        isLoading = true
        errorMessage = nil

        guard let customerId = UserDefaults.standard.value(forKey: "p2p_customer_id") as? Int else {
            errorMessage = "Customer ID not found"
            isLoading = false
            return
        }

        guard let url = URL(string: "\(baseURL)/api/rides/customer/\(customerId)/recurring-rides") else {
            errorMessage = "Invalid URL"
            isLoading = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = SecureStorage.shared.customerAccessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
                if let error = error {
                    errorMessage = error.localizedDescription
                    return
                }
                guard let data = data else { errorMessage = "No data"; return }

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
                    let resp = try JSONDecoder().decode(RecurringRidesListResponse.self, from: data)
                    rides = resp.recurringRides
                    logger.info("[RecurringRides] Loaded \(rides.count) rides")
                } catch {
                    errorMessage = "Failed to parse data"
                    logger.error("[RecurringRides] Decode error: \(error.localizedDescription)")
                }
            }
        }.resume()
    }

    private func deleteRecurringRide(_ id: Int) {
        guard let url = URL(string: "\(baseURL)/api/rides/recurring-rides/\(id)") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        if let token = SecureStorage.shared.customerAccessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        URLSession.shared.dataTask(with: request) { _, response, _ in
            DispatchQueue.main.async {
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode < 400 {
                    rides.removeAll { $0.id == id }
                    logger.info("[RecurringRides] Deleted ride \(id)")
                }
            }
        }.resume()
    }

    private func updateRecurringRide(_ id: Int, body: [String: Any]) {
        guard let url = URL(string: "\(baseURL)/api/rides/recurring-rides/\(id)") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = SecureStorage.shared.customerAccessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { _, response, _ in
            DispatchQueue.main.async {
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode < 400 {
                    fetchRecurringRides()
                }
            }
        }.resume()
    }
}

// MARK: - Recurring Ride Setup Sheet

struct RecurringRideSetupSheet: View {
    let onCreated: () -> Void
    @Environment(\.dismiss) var dismiss

    @State private var pickupAddress = ""
    @State private var dropoffAddress = ""
    @State private var selectedDays: Set<String> = []
    @State private var scheduleTime = Date()
    @State private var maxPrice = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private let baseURL = AppConfig.shared.p2pAPIBaseURL
    private let daysOfWeek = [
        ("mon", "Mon"), ("tue", "Tue"), ("wed", "Wed"), ("thu", "Thu"),
        ("fri", "Fri"), ("sat", "Sat"), ("sun", "Sun")
    ]

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Pickup Address", text: $pickupAddress)
                        .foregroundColor(Theme.lxText)
                    TextField("Dropoff Address", text: $dropoffAddress)
                        .foregroundColor(Theme.lxText)
                } header: {
                    Text("Route").foregroundColor(Theme.lxTextSecondary)
                }
                .listRowBackground(Theme.lxSurface)

                Section {
                    // Day picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Days")
                            .font(.subheadline)
                            .foregroundColor(Theme.lxTextSecondary)

                        HStack(spacing: 8) {
                            ForEach(daysOfWeek, id: \.0) { day in
                                Button(action: {
                                    if selectedDays.contains(day.0) {
                                        selectedDays.remove(day.0)
                                    } else {
                                        selectedDays.insert(day.0)
                                    }
                                }) {
                                    Text(day.1)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .frame(width: 36, height: 36)
                                        .background(selectedDays.contains(day.0) ? Theme.lxOrange : Theme.lxSurface2)
                                        .foregroundColor(selectedDays.contains(day.0) ? .white : Theme.lxText)
                                        .cornerRadius(Lx.Radius.chip)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    DatePicker("Time", selection: $scheduleTime, displayedComponents: .hourAndMinute)
                        .foregroundColor(Theme.lxText)
                        .tint(Theme.lxOrange)
                } header: {
                    Text("Schedule").foregroundColor(Theme.lxTextSecondary)
                }
                .listRowBackground(Theme.lxSurface)

                Section {
                    TextField("Max Price (optional)", text: $maxPrice)
                        .foregroundColor(Theme.lxText)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Preferences").foregroundColor(Theme.lxTextSecondary)
                }
                .listRowBackground(Theme.lxSurface)

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(Theme.lxError)
                            .font(.caption)
                    }
                    .listRowBackground(Theme.lxSurface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.lxBg.ignoresSafeArea())
            .navigationTitle("New Recurring Ride")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Theme.lxOrange)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: createRecurringRide) {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text("Save")
                                .fontWeight(.bold)
                        }
                    }
                    .foregroundColor(Theme.lxOrange)
                    .disabled(pickupAddress.isEmpty || dropoffAddress.isEmpty || selectedDays.isEmpty || isSubmitting)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func createRecurringRide() {
        isSubmitting = true
        errorMessage = nil

        guard let customerId = UserDefaults.standard.value(forKey: "p2p_customer_id") as? Int else {
            errorMessage = "Customer ID not found"
            isSubmitting = false
            return
        }

        // Geocode both addresses before sending
        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(pickupAddress) { pickupPlacemarks, pickupError in
            guard let pickupCoord = pickupPlacemarks?.first?.location?.coordinate else {
                DispatchQueue.main.async {
                    self.errorMessage = "Could not find pickup location. Please enter a valid address."
                    self.isSubmitting = false
                }
                return
            }

            geocoder.geocodeAddressString(self.dropoffAddress) { dropoffPlacemarks, dropoffError in
                guard let dropoffCoord = dropoffPlacemarks?.first?.location?.coordinate else {
                    DispatchQueue.main.async {
                        self.errorMessage = "Could not find dropoff location. Please enter a valid address."
                        self.isSubmitting = false
                    }
                    return
                }

                self.submitRecurringRide(
                    customerId: customerId,
                    pickupLat: pickupCoord.latitude,
                    pickupLng: pickupCoord.longitude,
                    dropoffLat: dropoffCoord.latitude,
                    dropoffLng: dropoffCoord.longitude
                )
            }
        }
    }

    private func submitRecurringRide(customerId: Int, pickupLat: Double, pickupLng: Double, dropoffLat: Double, dropoffLng: Double) {
        guard let url = URL(string: "\(baseURL)/api/rides/customer/\(customerId)/recurring-rides") else {
            DispatchQueue.main.async {
                self.errorMessage = "Invalid URL"
                self.isSubmitting = false
            }
            return
        }

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        var body: [String: Any] = [
            "pickup_address": pickupAddress,
            "pickup_latitude": pickupLat,
            "pickup_longitude": pickupLng,
            "dropoff_address": dropoffAddress,
            "dropoff_latitude": dropoffLat,
            "dropoff_longitude": dropoffLng,
            "schedule_days": selectedDays.sorted().joined(separator: ","),
            "schedule_time": timeFormatter.string(from: scheduleTime),
            "timezone": TimeZone.current.identifier
        ]

        if let price = Double(maxPrice), price > 0 {
            body["max_price"] = price
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = SecureStorage.shared.customerAccessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isSubmitting = false

                if let error = error {
                    self.errorMessage = error.localizedDescription
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    if let data = data,
                       let errJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let detail = errJson["detail"] as? String {
                        self.errorMessage = detail
                    } else {
                        self.errorMessage = "Failed to create"
                    }
                    return
                }

                self.onCreated()
                self.dismiss()
                logger.info("[RecurringRides] Created new recurring ride")
            }
        }.resume()
    }
}
