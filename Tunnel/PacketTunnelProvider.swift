//
//  PacketTunnelProvider.swift
//  location-spoofer-tunnel
//
//  Created by Antonio on 10/09/2025.
//

import NetworkExtension
import os.log

class PacketTunnelProvider: NEPacketTunnelProvider {

    private let proxyPort: Int = 8888
    private let proxyHost = "127.0.0.1"
    private let configuration = LocationConfiguration.shared

    // Go location spoofer proxy integration
    private var goLocationSpoofer: GoLocationSpoofer?

    override func startTunnel(
        options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void
    ) {
        os_log("Tunnel starting...", log: OSLog.default, type: .info)

        goLocationSpoofer = GoLocationSpoofer()

        goLocationSpoofer?.hello()
        let version = goLocationSpoofer?.version() ?? "unknown"
        os_log("Go spoofer library version: %@", log: OSLog.default, type: .info, version)

        let coords = getSpoofedCoordinates()
        if let lat = coords.latitude, let lon = coords.longitude {
            os_log("Location spoofing active: %.6f, %.6f", log: OSLog.default, type: .info, lat, lon)
        } else {
            os_log("No coordinates configured - running in transparent mode", log: OSLog.default, type: .info)
        }

        guard let proxy = goLocationSpoofer, proxy.startProxy(lat: coords.latitude, lon: coords.longitude) else {
            let error = TunnelError.proxyServerFailed
            os_log("Failed to start Go location spoofing proxy", log: OSLog.default, type: .error)
            completionHandler(error)
            return
        }

        os_log("Go proxy started successfully", log: OSLog.default, type: .info)
        startTunnelWithProxy(completionHandler: completionHandler)
    }

    private func getSpoofedCoordinates() -> (latitude: Double?, longitude: Double?) {
        let suiteName = "group.dev.duti.location-spoofer"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return (nil, nil)
        }
        
        let lat = defaults.object(forKey: "spoofed_latitude") as? Double
        let lon = defaults.object(forKey: "spoofed_longitude") as? Double
        
        return (lat, lon)
    }

    private func startTunnelWithProxy(completionHandler: @escaping (Error?) -> Void) {
        let tunnelSettings = createTunnelSettings(proxyHost: proxyHost, proxyPort: proxyPort)

        setTunnelNetworkSettings(tunnelSettings) { error in
            if let error = error {
                os_log("Failed to set tunnel network settings: %@", log: OSLog.default, type: .error, error.localizedDescription)
                completionHandler(error)
            } else {
                os_log("Tunnel started successfully", log: OSLog.default, type: .info)
                completionHandler(nil)
            }
        }
    }

    private func createTunnelSettings(proxyHost: String, proxyPort: Int)
        -> NEPacketTunnelNetworkSettings
    {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")

        let proxySettings = NEProxySettings()
        proxySettings.httpServer = NEProxyServer(
            address: proxyHost,
            port: proxyPort
        )
        proxySettings.httpsServer = NEProxyServer(
            address: proxyHost,
            port: proxyPort
        )
        proxySettings.autoProxyConfigurationEnabled = false
        proxySettings.httpEnabled = true
        proxySettings.httpsEnabled = true
        proxySettings.excludeSimpleHostnames = true
        proxySettings.exceptionList = [
            "192.168.0.0/16",
            "10.0.0.0/8",
            "172.16.0.0/12",
            "127.0.0.1",
            "localhost",
            "*.local",
        ]
        settings.proxySettings = proxySettings

        let ipv4Settings = NEIPv4Settings(
            addresses: [settings.tunnelRemoteAddress],
            subnetMasks: ["255.255.255.255"]
        )
        ipv4Settings.includedRoutes = [NEIPv4Route.default()]
        ipv4Settings.excludedRoutes = [
            NEIPv4Route(destinationAddress: "192.168.0.0", subnetMask: "255.255.0.0"),
            NEIPv4Route(destinationAddress: "10.0.0.0", subnetMask: "255.0.0.0"),
            NEIPv4Route(destinationAddress: "172.16.0.0", subnetMask: "255.240.0.0"),
        ]
        settings.ipv4Settings = ipv4Settings

        let dnsSettings = NEDNSSettings(servers: ["8.8.8.8", "1.1.1.1"])
        settings.dnsSettings = dnsSettings

        settings.mtu = 1500

        return settings
    }

    override func stopTunnel(
        with reason: NEProviderStopReason, completionHandler: @escaping () -> Void
    ) {
        os_log("Tunnel stopping, reason: %ld", log: OSLog.default, type: .info, reason.rawValue)

        if let proxy = goLocationSpoofer {
            if proxy.stopProxy() {
                os_log("Go proxy stopped successfully", log: OSLog.default, type: .info)
            } else {
                os_log("Failed to stop Go proxy", log: OSLog.default, type: .error)
            }
        }

        goLocationSpoofer = nil
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        if let handler = completionHandler {
            handler(messageData)
        }
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    override func wake() {
    }
}

enum TunnelError: Error {
    case proxyServerFailed
}