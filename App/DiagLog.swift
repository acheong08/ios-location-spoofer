import Foundation

/// 单条诊断日志记录:时间戳 + 消息。
struct DiagEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String
}

extension DiagEntry {
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    /// 格式化为 "HH:mm:ss.SSS  消息" 一行。
    var formatted: String {
        "\(DiagEntry.timeFormatter.string(from: timestamp))  \(message)"
    }
}

/// 全局诊断日志收集器(单例,内存内,最近 100 条)。
/// TestFlight 看不到 Xcode 控制台,通过设置页诊断面板把流程进展暴露给用户。
final class DiagLog: ObservableObject {
    static let shared = DiagLog()

    /// 静态便捷调用,等价于 DiagLog.shared.add(msg);埋点处可写成 DiagLog.add("...")。
    static func add(_ message: String) {
        shared.add(message)
    }

    @Published private(set) var entries: [DiagEntry] = []

    private let maxEntries = 100

    private init() {}

    /// 追加一条日志。线程安全:非主线程会自动派发到主线程(@Published 需主线程更新)。
    func add(_ message: String) {
        if Thread.isMainThread {
            appendInternal(message)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.appendInternal(message)
            }
        }
    }

    private func appendInternal(_ message: String) {
        entries.append(DiagEntry(timestamp: Date(), message: message))
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    /// 清空所有日志(主线程派发)。
    func clear() {
        if Thread.isMainThread {
            entries.removeAll()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.entries.removeAll()
            }
        }
    }
}
