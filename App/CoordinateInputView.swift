//
//  CoordinateInputView.swift
//  location-spoofer
//
//  View for entering coordinates to spoof location
//

import SwiftUI
import UIKit

struct CoordinateInputView: View {
    @StateObject private var locationConfig = LocationConfiguration.shared
    @State private var latitudeText: String = ""
    @State private var longitudeText: String = ""
    @State private var showingPresetLocations = false
    @State private var saveError: String?
    @State private var showingSaveAlert = false
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Latitude")
                                .font(.headline)
                            
                            TextField("e.g., 40.7128", text: $latitudeText)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.decimalPad)
                                .onChange(of: latitudeText) { _, newValue in
                                    validateAndSave()
                                }
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Longitude")
                                .font(.headline)
                            
                            TextField("e.g., -74.0060", text: $longitudeText)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.decimalPad)
                                .onChange(of: longitudeText) { _, newValue in
                                    validateAndSave()
                                }
                        }
                    }
                } header: {
                    Text("Target Coordinates")
                } footer: {
                    Text("Enter the latitude and longitude you want to spoof your location to. Valid range: Latitude -90 to 90, Longitude -180 to 180.")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        if let coords = locationConfig.currentCoordinates {
                            HStack {
                                Text("Current Settings:")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(String(format: "%.6f, %.6f", coords.latitude, coords.longitude))
                                    .font(.system(.body, design: .monospaced))
                            }
                            .padding(.vertical, 8)
                            
                            Button("Clear Coordinates") {
                                clearCoordinates()
                            }
                            .foregroundColor(.red)
                        } else {
                            Text("No coordinates configured")
                                .foregroundColor(.secondary)
                                .italic()
                        }
                    }
                } header: {
                    Text("Status")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Common Locations")
                            .font(.headline)
                        
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 12) {
                            PresetLocationButton(name: "New York", lat: 40.7128, lon: -74.0060, onTap: { lat, lon in
                                setCoordinates(lat: lat, lon: lon)
                            })
                            
                            PresetLocationButton(name: "London", lat: 51.5074, lon: -0.1278, onTap: { lat, lon in
                                setCoordinates(lat: lat, lon: lon)
                            })
                            
                            PresetLocationButton(name: "Tokyo", lat: 35.6762, lon: 139.6503, onTap: { lat, lon in
                                setCoordinates(lat: lat, lon: lon)
                            })
                            
                            PresetLocationButton(name: "Sydney", lat: -33.8688, lon: 151.2093, onTap: { lat, lon in
                                setCoordinates(lat: lat, lon: lon)
                            })
                            
                            PresetLocationButton(name: "Paris", lat: 48.8566, lon: 2.3522, onTap: { lat, lon in
                                setCoordinates(lat: lat, lon: lon)
                            })
                            
                            PresetLocationButton(name: "Los Angeles", lat: 34.0522, lon: -118.2437, onTap: { lat, lon in
                                setCoordinates(lat: lat, lon: lon)
                            })
                        }
                    }
                } header: {
                    Text("Quick Presets")
                } footer: {
                    Text("Tap any preset to quickly set those coordinates. Your VPN must be restarted for changes to take effect.")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Installation Guide")
                            .font(.headline)
                        
                        Text("To use location spoofing:")
                            .font(.subheadline)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("1. Enable the VPN from the VPN tab")
                            Text("2. Visit mitm.it in Safari")
                            Text("3. Install the CA certificate")
                            Text("4. Trust the certificate in Settings > General > VPN & Device Management")
                            Text("5. Restart the VPN connection")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Setup Instructions")
                }
            }
            .navigationTitle("Location Settings")
            .onAppear {
                loadCurrentCoordinates()
            }
            .alert("Save Error", isPresented: $showingSaveAlert) {
                Button("OK") {}
            } message: {
                Text(saveError ?? "Failed to save coordinates")
            }
        }
    }
    
    private func loadCurrentCoordinates() {
        if let coords = locationConfig.currentCoordinates {
            latitudeText = String(format: "%.6f", coords.latitude)
            longitudeText = String(format: "%.6f", coords.longitude)
        }
    }
    
    private func setCoordinates(lat: Double, lon: Double) {
        latitudeText = String(format: "%.6f", lat)
        longitudeText = String(format: "%.6f", lon)
        validateAndSave()
    }
    
    private func clearCoordinates() {
        latitudeText = ""
        longitudeText = ""
        locationConfig.clearCoordinates()
    }
    
    private func validateAndSave() {
        guard let lat = Double(latitudeText), let lon = Double(longitudeText) else {
            if !latitudeText.isEmpty || !longitudeText.isEmpty {
                saveError = "Please enter valid coordinates"
                showingSaveAlert = true
            }
            return
        }
        
        guard lat >= -90 && lat <= 90 else {
            saveError = "Latitude must be between -90 and 90"
            showingSaveAlert = true
            return
        }
        
        guard lon >= -180 && lon <= 180 else {
            saveError = "Longitude must be between -180 and 180"
            showingSaveAlert = true
            return
        }
        
        locationConfig.setCoordinates(latitude: lat, longitude: lon)
    }
}

struct PresetLocationButton: View {
    let name: String
    let lat: Double
    let lon: Double
    let onTap: (Double, Double) -> Void
    
    var body: some View {
        Button {
            onTap(lat, lon)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "mappin.circle.fill")
                    .font(.title2)
                Text(name)
                    .font(.caption)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    CoordinateInputView()
}