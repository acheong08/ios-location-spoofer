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

        let coords = configuration.currentCoordinates
        let lat = coords?.latitude
        let lon = coords?.longitude
        if let lat = lat, let lon = lon {
            os_log("Location spoofing active: %.6f, %.6f", log: OSLog.default, type: .info, lat, lon)
        } else {
            os_log("No coordinates configured - running in transparent mode", log: OSLog.default, type: .info)
        }

        guard let proxy = goLocationSpoofer, proxy.startProxy(lat: lat, lon: lon) else {
            let error = TunnelError.proxyServerFailed
            os_log("Failed to start Go location spoofing proxy", log: OSLog.default, type: .error)
            completionHandler(error)
            return
        }

        os_log("Go proxy started successfully", log: OSLog.default, type: .info)
        startTunnelWithProxy(completionHandler: completionHandler)
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

        let dnsSettings = NEDNSSettings(servers: ["223.5.5.5", "114.114.114.114"])
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
        guard let handler = completionHandler else { return }
        let cmd = String(data: messageData, encoding: .utf8) ?? ""
        switch cmd {
        case "getCoords":
            // 17 字节定长回包:1 字节 enabled + 8 字节 lat (LE) + 8 字节 lon (LE)。
            // App 端按相同格式解;两端都在 iOS arm64 上,统一小端无跨架构问题。
            guard let proxy = goLocationSpoofer,
                  let coords = proxy.getCurrentCoords() else {
                handler(nil)
                return
            }
            var resp = Data()
            resp.append(coords.enabled ? 1 : 0)
            var lat = coords.lat
            var lon = coords.lon
            withUnsafeBytes(of: &lat) { resp.append(contentsOf: $0) }
            withUnsafeBytes(of: &lon) { resp.append(contentsOf: $0) }
            handler(resp)
        case "getLogs":
            // 拉取 Go 内部 handleLocationRequest 的逐次执行日志(诊断面板用)。
            // 回包为日志文本 UTF-8;无日志或 proxy 未起 → handler(nil)。
            guard let proxy = goLocationSpoofer,
                  let logs = proxy.drainGoLogs() else {
                handler(nil)
                return
            }
            handler(Data(logs.utf8))
        default:
            // 未知命令保持原 echo 行为,兼容潜在旧调用方
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