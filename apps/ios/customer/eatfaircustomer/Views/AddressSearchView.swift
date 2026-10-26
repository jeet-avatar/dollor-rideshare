import SwiftUI
import EatFairShared
import MapKit

struct AddressSearchView: View {
    @StateObject private var viewModel = AddressSearchViewModel()
    @Environment(\.presentationMode) var presentationMode
    
    var onAddressSelected: (String, String, String, String, CLLocationCoordinate2D?) -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(Lx.Palette.textMuted)
                    TextField("Search for your address", text: $viewModel.searchQuery)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    if !viewModel.searchQuery.isEmpty {
                        Button(action: { viewModel.searchQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(Lx.Palette.textMuted)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(Lx.Radius.chip)
                .padding()
                
                if viewModel.isLoading {
                    ProgressView()
                        .padding()
                }
                
                List(viewModel.results, id: \.self) { result in
                    Button(action: {
                        viewModel.selectAddress(result) { street, city, state, zip, coordinate in
                            onAddressSelected(street, city, state, zip, coordinate)
                            presentationMode.wrappedValue.dismiss()
                        }
                    }) {
                        VStack(alignment: .leading) {
                            Text(result.title)
                                .font(.headline)
                            Text(result.subtitle)
                                .font(.subheadline)
                                .foregroundColor(Lx.Palette.textMuted)
                        }
                    }
                }
                .listStyle(PlainListStyle())
            }
            .navigationTitle("Search Address")
            .navigationBarItems(trailing: Button("Cancel") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}
