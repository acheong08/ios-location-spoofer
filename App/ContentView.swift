import SwiftUI
import NetworkExtension
import os.log

struct ContentView: View {
    @State private var firstSetupCompleted: Bool = UserDefaults.standard.bool(forKey: "firstSetupCompleted")

    var body: some View {
        Group {
            if firstSetupCompleted {
                MapHomeView()
            } else {
                FirstSetupView()
            }
        }
        .onAppear {
            loadVPNManagerIfExists()
            // 监听 firstSetupCompleted 变化(FirstSetupView 完成 setup 后会写 UserDefaults)
            NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
                let newValue = UserDefaults.standard.bool(forKey: "firstSetupCompleted")
                if newValue != firstSetupCompleted {
                    firstSetupCompleted = newValue
                }
            }
        }
    }

    /// 进 App 时只加载已存在的 VPN 配置,不创建、不弹权限。
    /// 没装过的用户会在 FirstSetupView 点【授权VPN】时再走 installAndStartVPN。
    private func loadVPNManagerIfExists() {
        NETunnelProviderManager.loadAllFromPreferences { managers, _ in
            if let existing = managers?.first {
                ContentView.vpnManager = existing
            }
        }
    }

    /// 创建/复用 manager,写入 protocol 配置并 saveToPreferences。
    /// save 成功通过 completion 回传 manager,失败回传 error。调用方负责后续 startVPNTunnel。
    static func installAndStartVPN(completion: @escaping (Result<NETunnelProviderManager, Error>) -> Void) {
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            let manager = managers?.first ?? NETunnelProviderManager()

            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = "dev.duti.location-spoofer.tunnel"
            proto.serverAddress = "127.0.0.1"
            manager.protocolConfiguration = proto
            manager.localizedDescription = "Location Spoofer"
            manager.isEnabled = true

            manager.saveToPreferences { error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                // save 完后必须再 load 一次,让内核把新配置真正绑到 manager 上,
                // 否则立刻 startVPNTunnel 会拿到 stale config 报 NEVPNErrorDomain error 1。
                manager.loadFromPreferences { error in
                    if let error = error {
                        completion(.failure(error))
                    } else {
                        ContentView.vpnManager = manager
                        completion(.success(manager))
                    }
                }
            }
        }
    }
}

extension ContentView {
    static var vpnManager: NETunnelProviderManager?
}

#Preview {
    ContentView()
}
