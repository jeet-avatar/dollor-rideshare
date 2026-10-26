import SwiftUI
import EatFairShared

struct WaybillSheet: View {
    let rideRequestId: Int
    @Environment(\.dismiss) private var dismiss
    @State private var waybill: [String: Any]?
    @State private var isLoading = true

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("Loading trip information...")
                        .tint(Theme.lxOrange)
                        .foregroundColor(Theme.lxTextSecondary)
                } else if let waybill = waybill {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            waybillSection("TNC Operator", items: [
                                ("Carrier", nestedString(waybill, "tnc_operator", "carrier_name")),
                                ("DBA", nestedString(waybill, "tnc_operator", "dba")),
                                ("Permit", nestedString(waybill, "tnc_operator", "permit_type")),
                            ])
                            waybillSection("Trip", items: [
                                ("Trip ID", "#\(rideRequestId)"),
                                ("Status", waybill["status"] as? String ?? "N/A"),
                            ])
                            waybillSection("Passenger", items: [
                                ("Name", nestedString(waybill, "passenger", "name")),
                            ])
                            waybillSection("Route", items: [
                                ("Pickup", nestedString(waybill, "route", "pickup_address")),
                                ("Dropoff", nestedString(waybill, "route", "dropoff_address")),
                                ("Pickup Time", nestedString(waybill, "route", "pickup_time")),
                            ])
                            waybillSection("Driver & Vehicle", items: [
                                ("Driver", nestedString(waybill, "driver", "name")),
                                ("License", nestedString(waybill, "driver", "license_number")),
                                ("Vehicle", nestedString(waybill, "driver", "vehicle")),
                                ("Plate", nestedString(waybill, "driver", "license_plate")),
                            ])

                            if let fare = waybill["fare"] as? [String: Any] {
                                waybillSection("Fare", items: [
                                    ("Amount", "$\(fare["amount"] ?? "N/A")"),
                                    ("Platform Fee", "$\(fare["platform_fee"] ?? "N/A")"),
                                    ("Access for All", "$\(fare["access_for_all_fee"] ?? "0.10")"),
                                ])
                            }

                            HStack {
                                Image(systemName: "info.circle")
                                Text("CPUC: 1-800-894-9444")
                            }
                            .font(.caption)
                            .foregroundColor(Theme.lxTextSecondary)
                            .padding(.top, 8)
                        }
                        .padding()
                    }
                } else {
                    Text("Unable to load trip information")
                        .foregroundColor(Theme.lxTextSecondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.lxBg.ignoresSafeArea())
            .navigationTitle("Trip Information")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Theme.lxOrange)
                }
            }
            .onAppear { loadWaybill() }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func waybillSection(_ title: String, items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(Theme.lxOrange)
            ForEach(items, id: \.0) { label, value in
                HStack {
                    Text(label)
                        .font(.subheadline)
                        .foregroundColor(Theme.lxTextSecondary)
                        .frame(width: 100, alignment: .leading)
                    Text(value)
                        .font(.subheadline)
                        .foregroundColor(Theme.lxText)
                    Spacer()
                }
            }
        }
        .padding()
        .background(Theme.lxSurface)
        .cornerRadius(Lx.Radius.button)
        .overlay(
            RoundedRectangle(cornerRadius: Lx.Radius.button)
                .stroke(Theme.lxHairline, lineWidth: 1)
        )
    }

    private func nestedString(_ dict: [String: Any], _ key1: String, _ key2: String) -> String {
        if let nested = dict[key1] as? [String: Any] {
            return "\(nested[key2] ?? "N/A")"
        }
        return "N/A"
    }

    private func loadWaybill() {
        P2PAPIService.shared.getRideWaybill(rideRequestId: rideRequestId) { result in
            waybill = result
            isLoading = false
        }
    }
}
