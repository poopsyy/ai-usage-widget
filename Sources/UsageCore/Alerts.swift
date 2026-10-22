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
            guard delivered[key] == nil else { return nil }
            return UsageAlert(key: key, provider: snapshot.provider, window: window, threshold: threshold)
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
