import Foundation

public enum ProviderID: String, Codable, CaseIterable, Sendable {
    case claude, codex
    public var title: String { self == .claude ? "Claude" : "Codex" }
    public var usageURL: URL {
        URL(string: self == .claude ? "https://claude.ai/settings/usage" : "https://chatgpt.com/codex/settings/usage")!
    }
}

public struct UsageWindow: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var usedPercent: Double
    public var resetsAt: Date?
    public var remaining: Double { max(0, min(100, 100 - usedPercent)) }
    public func isExpired(at now: Date) -> Bool { resetsAt.map { $0 <= now } ?? false }

    public init(id: String, title: String, usedPercent: Double, resetsAt: Date?) {
        self.id = id; self.title = title; self.usedPercent = usedPercent; self.resetsAt = resetsAt
    }
}

public struct UsageSnapshot: Codable, Equatable, Sendable {
    public var provider: ProviderID
    public var observedAt: Date
    public var windows: [UsageWindow]
    public var plan: String?
    public init(provider: ProviderID, observedAt: Date, windows: [UsageWindow], plan: String? = nil) {
        self.provider = provider; self.observedAt = observedAt; self.windows = windows; self.plan = plan
    }
    public func isStale(at now: Date) -> Bool {
        now.timeIntervalSince(observedAt) > 900 || observedAt.timeIntervalSince(now) > 60
    }
    public func remaining(at now: Date) -> Double? {
        guard !isStale(at: now) else { return nil }
        return windows.filter { !$0.isExpired(at: now) }.map(\.remaining).min()
    }
}

public enum UsageError: LocalizedError {
    case setup(String), unavailable(String), invalidData
    public var errorDescription: String? {
        switch self {
        case .setup(let message), .unavailable(let message): return message
        case .invalidData: return "The provider returned unsupported usage data."
        }
    }
}

public enum UsageParser {
    private static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }
        return n.doubleValue
    }
    private static func window(id: String, title: String, raw: [String: Any], percentKey: String, resetKey: String) -> UsageWindow? {
        guard let percent = number(raw[percentKey]), (0...100).contains(percent) else { return nil }
        let reset = number(raw[resetKey]).flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
        return UsageWindow(id: id, title: title, usedPercent: percent, resetsAt: reset)
    }
    public static func claude(_ data: Data, at now: Date = Date()) throws -> UsageSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let limits = root["rate_limits"] as? [String: Any] else { throw UsageError.invalidData }
        let windows = [("five_hour", "5 hours"), ("seven_day", "Weekly")].compactMap { id, title -> UsageWindow? in
            guard let raw = limits[id] as? [String: Any] else { return nil }
            return window(id: id, title: title, raw: raw, percentKey: "used_percentage", resetKey: "resets_at")
        }
        guard !windows.isEmpty else { throw UsageError.invalidData }
        return UsageSnapshot(provider: .claude, observedAt: now, windows: windows)
    }
    public static func codex(_ data: Data, at now: Date = Date()) throws -> UsageSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw UsageError.invalidData }
        let result = root["result"] as? [String: Any] ?? root
        var buckets: [(String, [String: Any])] = []
        if let all = result["rateLimitsByLimitId"] as? [String: Any], !all.isEmpty {
            buckets = all.sorted { $0.key < $1.key }.compactMap { key, value in
                (value as? [String: Any]).map { (key, $0) }
            }
        }
        if buckets.isEmpty, let single = result["rateLimits"] as? [String: Any] { buckets = [("codex", single)] }
        var windows: [UsageWindow] = []
        for (bucketID, bucket) in buckets {
            for key in ["primary", "secondary"] {
                guard let raw = bucket[key] as? [String: Any] else { continue }
                let minutes = number(raw["windowDurationMins"])
                let duration: String
                if let minutes, minutes > 0 {
                    if minutes == 10080 { duration = "Weekly" }
                    else if minutes.truncatingRemainder(dividingBy: 60) == 0 { duration = "\(Int(minutes / 60)) hours" }
                    else { duration = "\(Int(minutes)) min" }
                } else { duration = key == "primary" ? "Primary limit" : "Secondary limit" }
                let name = bucket["limitName"] as? String ?? bucketID
                let title = buckets.count > 1 ? "\(name) · \(duration)" : duration
                if let parsed = window(id: "\(bucketID).\(key)", title: title, raw: raw, percentKey: "usedPercent", resetKey: "resetsAt") {
                    windows.append(parsed)
                }
            }
        }
        guard !windows.isEmpty else { throw UsageError.unavailable("No subscription limits were reported for this account.") }
        return UsageSnapshot(provider: .codex, observedAt: now, windows: windows, plan: buckets.first?.1["planType"] as? String)
    }
}

import CoreFoundation

public enum UsageFiles {
    public static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AI Usage", isDirectory: true)
    }
    public static func prepare(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    public static func write<T: Encodable>(_ value: T, to url: URL) throws {
        try prepare(url.deletingLastPathComponent())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    public static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }
}
