import Foundation
import Darwin

public struct IntegrationState: Codable {
    public var settingsURL: URL
    public var previousStatusLine: Data?
    public var installedCommand: String
    public var backupURL: URL
}

public struct ClaudeIntegration {
    public var directory: URL
    public var settingsURL: URL
    public init(directory: URL = UsageFiles.directory, settingsURL: URL? = nil) {
        self.directory = directory
        let config = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        self.settingsURL = settingsURL ?? config.appendingPathComponent("settings.json")
    }
    public var stateURL: URL { directory.appendingPathComponent("claude-integration.json") }
    public var isInstalled: Bool {
        guard let state = try? UsageFiles.read(IntegrationState.self, from: stateURL),
              let data = try? Data(contentsOf: state.settingsURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let line = root["statusLine"] as? [String: Any] else { return false }
        return line["command"] as? String == state.installedCommand
    }
    public static func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    public func install(helper: URL) throws {
        guard !FileManager.default.fileExists(atPath: stateURL.path) else {
            if isInstalled { return }
            throw UsageError.setup("Claude settings changed since setup. Restore the integration before connecting again.")
        }
        try UsageFiles.prepare(directory)
        let original = try? Data(contentsOf: settingsURL)
        if original == nil && FileManager.default.fileExists(atPath: settingsURL.path) {
            throw UsageError.setup("Claude settings could not be read. Check file permissions.")
        }
        var root = try decodeSettings(original)
        if let previous = root["statusLine"], !(previous is NSNull) {
            guard let line = previous as? [String: Any], line["type"] as? String == "command", line["command"] is String else {
                throw UsageError.setup("The existing Claude status line has an unsupported format. No settings were changed.")
            }
        }
        let destination = directory.appendingPathComponent("claude-statusline")
        let previous = try root["statusLine"].map { try JSONSerialization.data(withJSONObject: $0, options: [.fragmentsAllowed]) }
        let command = Self.shellQuote(destination.path) + " --directory " + Self.shellQuote(directory.path)
        let backup = directory.appendingPathComponent("claude-settings-backup-\(UUID().uuidString).json")
        let state = IntegrationState(settingsURL: settingsURL, previousStatusLine: previous, installedCommand: command, backupURL: backup)
        let helperData = try Data(contentsOf: helper)
        try helperData.write(to: destination, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: destination.path)
        try (original ?? Data("{}".utf8)).write(to: backup, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        try UsageFiles.write(state, to: stateURL)
        // Carry over layout options such as padding, replacing only the command.
        var statusLine = root["statusLine"] as? [String: Any] ?? [:]
        statusLine["type"] = "command"; statusLine["command"] = command
        root["statusLine"] = statusLine
        do {
            guard (try? Data(contentsOf: settingsURL)) == original else {
                throw UsageError.setup("Claude settings changed during setup. Try connecting again.")
            }
            try writeSettings(root)
        } catch {
            try? FileManager.default.removeItem(at: stateURL)
            throw error
        }
    }
    public func restore() throws {
        guard let state = try? UsageFiles.read(IntegrationState.self, from: stateURL) else { return }
        let original = try Data(contentsOf: state.settingsURL)
        var root = try decodeSettings(original)
        let current = root["statusLine"] as? [String: Any]
        guard current?["command"] as? String == state.installedCommand else {
            throw UsageError.setup("The status line was edited after setup. To avoid overwriting it, restore it manually using the backup in the data folder.")
        }
        if let previous = state.previousStatusLine {
            root["statusLine"] = try JSONSerialization.jsonObject(with: previous, options: [.fragmentsAllowed])
        } else { root.removeValue(forKey: "statusLine") }
        guard try Data(contentsOf: state.settingsURL) == original else { throw UsageError.setup("Claude settings changed during restoration. Try again.") }
        let target = ClaudeIntegration(directory: directory, settingsURL: state.settingsURL)
        try target.writeSettings(root)
        try FileManager.default.removeItem(at: stateURL)
        // Keep the helper: already-running Claude sessions may still call it.
    }
    private func decodeSettings(_ data: Data?) throws -> [String: Any] {
        guard let data else { return [:] }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageError.setup("Claude settings must contain a JSON object. No settings were changed.")
        }
        return root
    }
    private func writeSettings(_ root: [String: Any]) throws {
        let parent = settingsURL.deletingLastPathComponent()
        try UsageFiles.prepare(parent)
        let attributes = try? FileManager.default.attributesOfItem(atPath: settingsURL.path)
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed])
        try data.write(to: settingsURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: attributes?[.posixPermissions] ?? 0o600], ofItemAtPath: settingsURL.path)
    }
}

public enum ClaudeCapture {
    /// Serializes concurrent Claude sessions. Persist only the two quota windows.
    @discardableResult
    public static func capture(_ input: Data, directory: URL, at now: Date = Date()) throws -> UsageSnapshot {
        let snapshot = try UsageParser.claude(input, at: now)
        try UsageFiles.prepare(directory)
        let lockURL = directory.appendingPathComponent("claude.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw UsageError.unavailable("Could not lock Claude snapshot.") }
        defer { flock(descriptor, LOCK_UN); close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw UsageError.unavailable("Could not lock Claude snapshot.") }
        let url = directory.appendingPathComponent("claude.json")
        if let existing = try? UsageFiles.read(UsageSnapshot.self, from: url), existing.observedAt > snapshot.observedAt { return existing }
        try UsageFiles.write(snapshot, to: url)
        return snapshot
    }
    /// The latest status-line reading, validated as it is read.
    public static func read(directory: URL) throws -> UsageSnapshot {
        let snapshot = try UsageFiles.read(UsageSnapshot.self, from: directory.appendingPathComponent("claude.json"))
        guard snapshot.provider == .claude, !snapshot.windows.isEmpty,
              snapshot.windows.allSatisfy({ $0.usedPercent.isFinite && (0...100).contains($0.usedPercent) }) else { throw UsageError.invalidData }
        return snapshot
    }
}
