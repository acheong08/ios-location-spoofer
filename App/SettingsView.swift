import SwiftUI
import NetworkExtension

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showResetConfirm = false
    @State private var showCopiedToast = false
    @ObservedObject private var diagLog = DiagLog.shared

    var body: some View {
        NavigationView {
            List {
                // 关于
                Section("About") {
                    HStack {
                        Text("Location Spoofer")
                        Spacer()
                        Text("Build \(buildNumber)")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion)
                            .foregroundColor(.secondary)
                    }
                }

                // 诊断信息
                Section("Diagnostics (use when contacting support)") {
                    diagnosticRow(label: "VPN Status", value: vpnStatusText)
                    diagnosticRow(label: "Certificate Status", value: certificateStatusText)
                    diagnosticRow(label: "Current Spoofed Location", value: currentLocationText)
                    diagnosticRow(label: "Current Coordinates", value: currentCoordinatesText)
                    diagnosticRow(label: "Initial Setup", value: setupCompletedText)

                    Button(action: { copyDiagnostic() }) {
                        HStack {
                            Image(systemName: "doc.on.doc")
                            Text(showCopiedToast ? "Copied" : "Copy Diagnostics (incl. flow logs)")
                            Spacer()
                        }
                        .foregroundColor(showCopiedToast ? .green : .blue)
                    }
                }

                // 流程日志
                Section(header: HStack {
                    Text("Flow Logs (most recent \(diagLog.entries.count))")
                    Spacer()
                    Button("Clear") { diagLog.clear() }
                        .font(.caption)
                        .foregroundColor(.red)
                        .disabled(diagLog.entries.isEmpty)
                }) {
                    Button(action: { queryGoLogsViaIPC() }) {
                        HStack {
                            Image(systemName: "arrow.down.doc")
                            Text("Fetch Go Proxy Logs (IPC)")
                            Spacer()
                        }
                        .foregroundColor(.blue)
                    }
                    if diagLog.entries.isEmpty {
                        Text("No logs yet. Run "Set as Location" once and come back.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(diagLog.entries.reversed()) { entry in
                            Text(entry.formatted)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                // 危险操作
                Section("Advanced") {
                    Button(role: .destructive, action: { showResetConfirm = true }) {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset App (clears all settings and favorites)")
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Confirm Reset App?", isPresented: $showResetConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) { resetApp() }
            } message: {
                Text("This clears all settings, favorites, and certificate state.\n\nYou will need to go through the initial setup again after resetting.")
            }
        }
    }

    // MARK: - 诊断信息收集

    @ViewBuilder
    private func diagnosticRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .font(.system(.body, design: .monospaced))
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    }

    private var vpnStatusText: String {
        guard let manager = ContentView.vpnManager else {
            return "Not initialized"
        }
        switch manager.connection.status {
        case .invalid:        return "Invalid"
        case .disconnected:   return "Disconnected"
        case .connecting:     return "Connecting"
        case .connected:      return "Connected"
        case .reasserting:    return "Reasserting"
        case .disconnecting:  return "Disconnecting"
        @unknown default:     return "Unknown"
        }
    }

    private var certificateStatusText: String {
        let downloaded = UserDefaults.standard.bool(forKey: "certDownloaded")
        let installed = UserDefaults.standard.bool(forKey: "certInstalled")
        let trusted = UserDefaults.standard.bool(forKey: "certTrusted")
        if trusted { return "Trusted" }
        if installed { return "Installed, not trusted" }
        if downloaded { return "Downloaded, not installed" }
        return "Not configured"
    }

    private var currentLocationText: String {
        UserDefaults.standard.string(forKey: "currentLocationName") ?? "None"
    }

    private var currentCoordinatesText: String {
        guard let coords = LocationConfiguration.shared.currentCoordinates else {
            return "None"
        }
        return String(format: "%.6f, %.6f", coords.latitude, coords.longitude)
    }

    private var setupCompletedText: String {
        UserDefaults.standard.bool(forKey: "firstSetupCompleted") ? "Completed" : "Not completed"
    }

    private func copyDiagnostic() {
        let logBlock = diagLog.entries.isEmpty
            ? "(no logs)"
            : diagLog.entries.map { $0.formatted }.joined(separator: "\n")

        let info = """
        Location Spoofer Diagnostics
        ─────────────
        App version: \(appVersion)
        Build: \(buildNumber)
        VPN status: \(vpnStatusText)
        Certificate status: \(certificateStatusText)
        Current spoofed location: \(currentLocationText)
        Current coordinates: \(currentCoordinatesText)
        Initial setup: \(setupCompletedText)

        ─── Flow Logs ───
        \(logBlock)
        """
        UIPasteboard.general.string = info
        showCopiedToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            showCopiedToast = false
        }
    }

    /// 通过 IPC 从 Tunnel 拉取 Go 端日志缓冲(handleLocationRequest 的逐次追踪)。
    /// 收到的字符串按行拆开,逐行 DiagLog.add 前缀 [Go] 写进流程日志显示。
    private func queryGoLogsViaIPC() {
        guard let manager = ContentView.vpnManager,
              let session = manager.connection as? NETunnelProviderSession else {
            DiagLog.add("[Go Logs] session unavailable (manager nil or connection is not NETunnelProviderSession)")
            return
        }
        let request = Data("getLogs".utf8)
        do {
            try session.sendProviderMessage(request) { response in
                DispatchQueue.main.async {
                    guard let data = response, !data.isEmpty else {
                        DiagLog.add("[Go Logs] fetch returned empty (no new Go logs or tunnel not ready)")
                        return
                    }
                    guard let text = String(data: data, encoding: .utf8) else {
                        DiagLog.add("[Go Logs] decode failed: \(data.count) bytes not UTF-8")
                        return
                    }
                    let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
                    DiagLog.add("[Go Logs] fetched \(lines.count) entries")
                    for line in lines {
                        DiagLog.add("[Go] \(line)")
                    }
                }
            }
        } catch {
            DiagLog.add("[Go Logs] sendProviderMessage error: \(error.localizedDescription)")
        }
    }

    // MARK: - 重置 App

    private func resetApp() {
        // 断开 VPN
        ContentView.vpnManager?.connection.stopVPNTunnel()
        // 清坐标
        LocationConfiguration.shared.clearCoordinates()
        // 清所有 UserDefaults key
        let keys = [
            "firstSetupCompleted",
            "certDownloaded", "certInstalled", "certTrusted",
            "currentLocationName", "savedLocations", "recentLocations"
        ]
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        // 清诊断日志
        DiagLog.shared.clear()
        dismiss()
    }
}
