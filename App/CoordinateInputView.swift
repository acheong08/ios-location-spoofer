import SwiftUI
import MapKit

struct SavedLocation: Codable, Identifiable {
    let id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    init(name: String, latitude: Double, longitude: Double) {
        self.id = UUID()
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }
}

struct CoordinateInputView: View {
    var onLocationConfirmed: (() -> Void)? = nil
    @State private var locationConfig = LocationConfiguration.shared
    @State private var searchText = ""
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @State private var pin: CLLocationCoordinate2D? = nil
    @State private var selectedName = ""
    @State private var showingConfirm = false
    @State private var showingAddFavorite = false
    @State private var favoriteName = ""
    @State private var savedLocations: [SavedLocation] = []
    @State private var currentLocationName: String? = nil
    @State private var showingSaveAlert = false
    @State private var saveError: String? = nil
    @State private var showLocationSetAlert = false
    private let savedLocationsKey = "savedLocations"

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search a place, e.g. Times Square", text: $searchText)
                            .onSubmit { searchLocation() }
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(10)

                    MapReader { proxy in
                        Map(position: .constant(.region(region))) {
                            if let pin = pin {
                                Marker("Target Location", coordinate: pin)
                                    .tint(.red)
                            }
                        }
                        .onTapGesture { position in
                            if let coordinate = proxy.convert(position, from: .local) {
                                selectLocation(coordinate: coordinate, name: nil)
                            }
                        }
                    }
                    .frame(height: 280)
                    .cornerRadius(12)

                    VStack(spacing: 8) {
                        if let name = currentLocationName {
                            HStack {
                                Image(systemName: "location.fill")
                                    .foregroundColor(.green)
                                Text("Current location: \(name)")
                                    .font(.body)
                                    .fontWeight(.medium)
                                Spacer()
                            }
                        } else {
                            HStack {
                                Image(systemName: "location.slash")
                                    .foregroundColor(.secondary)
                                Text("No location set")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(10)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Favorites")
                                .font(.headline)
                            Spacer()
                            Button(action: { showingAddFavorite = true }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                            }
                        }
                        if savedLocations.isEmpty {
                            Text("No favorites yet. Tap + to add a location.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 4)
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 10) {
                                ForEach(savedLocations) { loc in
                                    Button(action: {
                                        let coord = CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude)
                                        selectLocation(coordinate: coord, name: loc.name)
                                    }) {
                                        HStack {
                                            Image(systemName: "mappin.circle.fill")
                                                .foregroundColor(.blue)
                                            Text(loc.name)
                                                .font(.subheadline)
                                                .lineLimit(1)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .padding(.horizontal, 12)
                                        .background(Color(UIColor.tertiarySystemBackground))
                                        .cornerRadius(8)
                                    }
                                    .foregroundColor(.primary)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            deleteFavorite(loc)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(10)
                }
                .padding()
            }
            .navigationTitle("Location")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Confirm Location", isPresented: $showingConfirm) {
                Button("Confirm") { confirmLocation() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Set location to: \(selectedName)")
            }
            .alert("Add Favorite", isPresented: $showingAddFavorite) {
                TextField("Location name", text: $favoriteName)
                Button("Save") { addCurrentAsFavorite() }
                Button("Cancel", role: .cancel) { favoriteName = "" }
            } message: {
                Text("Name this location")
            }
            .alert("Save Error", isPresented: $showingSaveAlert) {
                Button("OK") {}
            } message: {
                Text(saveError ?? "Failed to save coordinates")
            }
            .alert("Location Set", isPresented: $showLocationSetAlert) {
                Button("OK") { }
            } message: {
                Text("Location set to: \(selectedName). Return to the home screen and follow the prompt to restart VPN for the new location to take effect.")
            }
            .onAppear {
                loadSavedLocations()
                loadCurrentLocation()
            }
        }
    }

    private func selectLocation(coordinate: CLLocationCoordinate2D, name: String?) {
        pin = coordinate
        region.center = coordinate
        if let name = name {
            selectedName = name
            showingConfirm = true
        } else {
            let geocoder = CLGeocoder()
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            geocoder.reverseGeocodeLocation(location) { placemarks, error in
                if let placemark = placemarks?.first {
                    let components = [placemark.locality, placemark.subLocality, placemark.name].compactMap { $0 }
                    selectedName = components.joined(separator: " ")
                    if selectedName.isEmpty {
                        selectedName = String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
                    }
                } else {
                    selectedName = String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
                }
                showingConfirm = true
            }
        }
    }

    private func confirmLocation() {
        guard let pin = pin else { return }
        let converted = CoordinateConverter.gcj02ToWgs84(lat: pin.latitude, lng: pin.longitude)
        locationConfig.setCoordinates(latitude: converted.latitude, longitude: converted.longitude)
        currentLocationName = selectedName
        UserDefaults.standard.set(selectedName, forKey: "currentLocationName")
        showLocationSetAlert = true
        onLocationConfirmed?()
    }

    private func searchLocation() {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            guard let response = response, let item = response.mapItems.first else { return }
            let coord = item.placemark.coordinate
            selectLocation(coordinate: coord, name: item.name ?? searchText)
        }
    }

    private func loadSavedLocations() {
        if let data = UserDefaults.standard.data(forKey: savedLocationsKey),
           let locations = try? JSONDecoder().decode([SavedLocation].self, from: data) {
            savedLocations = locations
        }
    }

    private func saveFavorites() {
        if let data = try? JSONEncoder().encode(savedLocations) {
            UserDefaults.standard.set(data, forKey: savedLocationsKey)
        }
    }

    private func addCurrentAsFavorite() {
        guard let pin = pin, !favoriteName.isEmpty else { return }
        let loc = SavedLocation(name: favoriteName, latitude: pin.latitude, longitude: pin.longitude)
        savedLocations.append(loc)
        saveFavorites()
        favoriteName = ""
    }

    private func deleteFavorite(_ location: SavedLocation) {
        savedLocations.removeAll { $0.id == location.id }
        saveFavorites()
    }

    private func loadCurrentLocation() {
        currentLocationName = UserDefaults.standard.string(forKey: "currentLocationName")
        if let coords = locationConfig.currentCoordinates {
            pin = CLLocationCoordinate2D(latitude: coords.latitude, longitude: coords.longitude)
            region.center = pin!
        }
    }
}
