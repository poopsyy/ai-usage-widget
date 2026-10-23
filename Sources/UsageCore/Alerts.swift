import Foundation

public struct UsageAlert: Equatable, Sendable {
    public var key: String
    public var provider: ProviderID
    public var window: UsageWindow
    public var threshold: Int
}

/// Persist delivery keys, rather than previous percentages, so app restarts cannot repeat an alert.
public struct AlertLedger: Codable, Sendable {
    public var delivered: [String: Date] = [:]
    public init() {}
    public func candidates(for snapshot: UsageSnapshot, at now: Date) -> [UsageAlert] {
        guard !snapshot.isStale(at: now) else { return [] }
        return snapshot.windows.compactMap { window in
            guard let reset = window.resetsAt, reset > now else { return nil }
            let eligible = [80, 95].filter { window.usedPercent >= Double($0) }
            guard let threshold = eligible.last else { return nil }
            let key = "\(snapshot.provider.rawValue)|\(window.id)|\(Int(reset.timeIntervalSince1970))|\(threshold)"
            guard !isDelivered(provider: snapshot.provider, window: window.id, threshold: threshold, reset: reset) else { return nil }
            return UsageAlert(key: key, provider: snapshot.provider, window: window, threshold: threshold)
        }
    }
    /// Sources report the same reset with minute or second precision, so nearby resets are one window.
    private func isDelivered(provider: ProviderID, window: String, threshold: Int, reset: Date) -> Bool {
        delivered.keys.contains { key in
            let parts = key.split(separator: "|", omittingEmptySubsequences: false)
            guard parts.count == 4, parts[0] == provider.rawValue, parts[1] == window, parts[3] == String(threshold),
                  let seconds = TimeInterval(parts[2]) else { return false }
            return abs(seconds - reset.timeIntervalSince1970) <= 1800
        }
    }
    public mutating func markDelivered(_ alert: UsageAlert, at now: Date) {
        guard let reset = alert.window.resetsAt else { return }
        // A first observation at 96% also satisfies the lower threshold.
        for threshold in [80, 95] where threshold <= alert.threshold {
            let key = "\(alert.provider.rawValue)|\(alert.window.id)|\(Int(reset.timeIntervalSince1970))|\(threshold)"
            delivered[key] = now
        }
        delivered = delivered.filter { now.timeIntervalSince($0.value) < 60 * 60 * 24 * 35 }
    }
}
