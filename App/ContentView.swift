//
//  ContentView.swift
//  location-spoofer
//
//  Main UI view with VPN control and coordinate input for location spoofing
//

import SwiftUI
import NetworkExtension
import UIKit
import os.log

struct ContentView: View {
    @State private var vpnStatus: NEVPNStatus = .invalid
    @State private var isConnecting = false
    @State private var needsVPNInstallation = false
    @State private var showingInstallationAlert = false
    @State private var installationError: String?
    @State private var showingCoordinates = false
    
    var body: some View {
        TabView {
            VPNControlView(
                vpnStatus: $vpnStatus,
                isConnecting: $isConnecting,
                needsVPNInstallation: $needsVPNInstallation,
                showingInstallationAlert: $showingInstallationAlert,
                installationError: $installationError,
                showingCoordinates: $showingCoordinates,
                loadVPNConfiguration: loadVPNConfiguration,
                installVPNProfile: installVPNProfile,
                toggleVPN: toggleVPN
            )
            .tabItem {
                Image(systemName: "network")
                Text("VPN")
            }
            .tag(0)
            
            CoordinateInputView()
                .tabItem {
                    Image(systemName: "location.fill")
                    Text("Location")
                }
                .tag(1)
        }
        .onAppear {
            loadVPNConfiguration()
        }
        .alert("VPN Installation", isPresented: $showingInstallationAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(installationError ?? "Failed to install VPN profile")
        }
    }
}

struct VPNControlView: View {
    @Binding var vpnStatus: NEVPNStatus
    @Binding var isConnecting: Bool
    @Binding var needsVPNInstallation: Bool
    @Binding var showingInstallationAlert: Bool
    @Binding var installationError: String?
    @Binding var showingCoordinates: Bool
    
    let loadVPNConfiguration: () -> Void
    let installVPNProfile: () -> Void
    let toggleVPN: () -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "location.fill")
                    .imageScale(.large)
                    .foregroundStyle(.tint)
                
                Text("Location Spoofer")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                VStack(spacing: 12) {
                    HStack {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 12, height: 12)
                        Text("VPN Status: \(statusText)")
                            .font(.body)
                    }
                    
                    if needsVPNInstallation {
                        Button("Install VPN Profile") {
                            installVPNProfile()
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .buttonStyle(.borderedProminent)
                        .disabled(isConnecting)
                    } else {
                        Button(action: toggleVPN) {
                            HStack {
                                if isConnecting {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                                Text(vpnStatus == .connected ? "Disconnect" : "Connect")
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isConnecting)
                    }
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)
                
                Text("When connected, this app will intercept Apple location services requests and spoof them to your configured coordinates.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Location Spoofer")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private var statusColor: Color {
        switch vpnStatus {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnecting: return .orange
        case .disconnected: return .red
        case .invalid: return .gray
        @unknown default: return .gray
        }
    }
    
    private var statusText: String {
        switch vpnStatus {
        case .connected: return "Connected"
        case .connecting: return "Connecting"
        case .disconnecting: return "Disconnecting"
        case .disconnected: return "Disconnected"
        case .invalid: return needsVPNInstallation ? "Installation Required" : "Not Configured"
        @unknown default: return "Unknown"
        }
    }
}

// MARK: - VPN Management Extensions
extension ContentView {
    private func loadVPNConfiguration() {
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.needsVPNInstallation = true
                    return
                }
                
                if let manager = managers?.first {
                    self.vpnStatus = manager.connection.status
                    self.needsVPNInstallation = false
                    
                    NotificationCenter.default.addObserver(
                        forName: .NEVPNStatusDidChange,
                        object: manager.connection,
                        queue: .main
                    ) { _ in
                        self.vpnStatus = manager.connection.status
                        self.isConnecting = false
                    }
                    
                    NotificationCenter.default.addObserver(
                        forName: .NEVPNConfigurationChange,
                        object: manager,
                        queue: .main
                    ) { _ in
                        self.loadVPNConfiguration()
                    }
                } else {
                    self.needsVPNInstallation = true
                }
            }
        }
    }
    
    private func installVPNProfile() {
        guard !isConnecting else { return }
        isConnecting = true

        let manager = makeManager()
        manager.saveToPreferences { error in
            if let error = error {
                DispatchQueue.main.async {
                    self.isConnecting = false
                    self.installationError = "Failed to install VPN profile: \(error.localizedDescription)"
                    self.showingInstallationAlert = true
                }
                return
            }
            
            // Workaround for Apple bug: must call loadFromPreferences after saveToPreferences
            // See https://forums.developer.apple.com/thread/25928
            manager.loadFromPreferences { loadError in
                DispatchQueue.main.async {
                    self.isConnecting = false
                    
                    if let loadError = loadError {
                        os_log("Warning: Failed to reload VPN preferences after install: %@", log: OSLog.default, type: .error, loadError.localizedDescription)
                    }
                    
                    os_log("VPN profile installed successfully", log: OSLog.default, type: .info)
                    self.loadVPNConfiguration()
                }
            }
        }
    }
    
    private func makeManager() -> NETunnelProviderManager {
        let manager = NETunnelProviderManager()
        manager.localizedDescription = "Location Spoofer"
        
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = "dev.duti.location-spoofer.tunnel"
        proto.serverAddress = "127.0.0.1"
        proto.providerConfiguration = [:]
        
        manager.protocolConfiguration = proto
        manager.isEnabled = true
        
        return manager
    }
    
    private func toggleVPN() {
        guard !isConnecting else { return }
        
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.needsVPNInstallation = true
                    return
                }
                
                guard let manager = managers?.first else {
                    self.needsVPNInstallation = true
                    return
                }
                
                self.isConnecting = true
                
                switch manager.connection.status {
                case .connected, .connecting:
                    manager.connection.stopVPNTunnel()
                case .disconnected, .disconnecting, .invalid:
                    // Ensure our VPN is enabled before saving. When another VPN (like WireGuard)
                    // is active, iOS may have disabled our configuration. Setting isEnabled = true
                    // and saving makes this the selected/active VPN configuration.
                    manager.isEnabled = true
                    manager.saveToPreferences { saveError in
                        if let saveError = saveError {
                            os_log("Failed to save VPN preferences: %@", log: OSLog.default, type: .error, saveError.localizedDescription)
                            DispatchQueue.main.async {
                                self.isConnecting = false
                            }
                            return
                        }
                        
                        // Reload from preferences after saving (workaround for Apple bug)
                        manager.loadFromPreferences { loadError in
                            DispatchQueue.main.async {
                                if let loadError = loadError {
                                    os_log("Failed to load VPN preferences: %@", log: OSLog.default, type: .error, loadError.localizedDescription)
                                    self.isConnecting = false
                                    return
                                }
                                
                                do {
                                    try manager.connection.startVPNTunnel()
                                } catch {
                                    os_log("Failed to start VPN tunnel: %@", log: OSLog.default, type: .error, error.localizedDescription)
                                    self.isConnecting = false
                                }
                            }
                        }
                    }
                @unknown default:
                    self.isConnecting = false
                }
            }
        }
    }
}

#Preview {
    ContentView()
}