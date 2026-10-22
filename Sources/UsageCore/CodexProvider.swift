import Foundation
import Darwin

public enum ExecutableLocator {
    public static func codex(override: String = "") -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let candidates = override.isEmpty ? (paths + ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.cargo/bin"]).map { "\($0)/codex" } + ["/Applications/Codex.app/Contents/Resources/codex"] : [(override as NSString).expandingTildeInPath]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map { URL(fileURLWithPath: $0) }
    }
}

public struct CodexProvider: UsageProvider {
    public var executableOverride: String
    public init(executableOverride: String = "") { self.executableOverride = executableOverride }
    public func fetch() async throws -> UsageSnapshot {
        let path = executableOverride
        return try await Task.detached(priority: .utility) {
            guard let executable = ExecutableLocator.codex(override: path) else {
                throw UsageError.setup("Install Codex CLI or choose its executable in Settings, then run codex login.")
            }
            let session = RPCSession()
            try session.start(executable: executable)
            defer { session.stop() }
            _ = try session.request(id: 1, method: "initialize", params: ["clientInfo": ["name": "ai_usage_widget", "title": "AI Usage", "version": "0.1.0"]])
            try session.notify(method: "initialized")
            let result = try session.request(id: 2, method: "account/rateLimits/read", params: nil)
            return try UsageParser.codex(result)
        }.value
    }
}

/// A short-lived, read-only connection. No threads or model turns are created.
final class RPCSession: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let condition = NSCondition()
    private var buffer = Data()
    private var responses: [Int: Data] = [:]
    private var ended = false

    func start(executable: URL) throws {
        process.executableURL = executable
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = input
        process.standardOutput = output
        // Provider logs can include account details. Keep them out of app logs.
        process.standardError = FileHandle.nullDevice
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(executable.deletingLastPathComponent().path):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        process.environment = environment
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            self?.receive(data)
        }
        process.terminationHandler = { [weak self] _ in
            guard let self else { return }
            self.condition.lock(); self.ended = true; self.condition.broadcast(); self.condition.unlock()
        }
        do { try process.run() }
        catch { output.fileHandleForReading.readabilityHandler = nil; throw UsageError.unavailable("Could not launch Codex. Check its executable in Settings.") }
    }
    private func receive(_ data: Data) {
        condition.lock(); defer { condition.unlock() }
        guard !data.isEmpty else { ended = true; condition.broadcast(); return }
        buffer.append(data)
        guard buffer.count <= 2_000_000 else { ended = true; condition.broadcast(); return }
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
            if let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let id = root["id"] as? Int, id == 1 || id == 2 {
                responses[id] = line
            }
        }
        condition.broadcast()
    }
    func notify(method: String) throws { try send(["method": method, "params": [:]]) }
    private func send(_ message: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(10)
        do { try input.fileHandleForWriting.write(contentsOf: data) }
        catch { throw UsageError.unavailable("Codex disconnected. Try refreshing.") }
    }
    func request(id: Int, method: String, params: [String: Any]?) throws -> Data {
        var message: [String: Any] = ["id": id, "method": method]
        if let params { message["params"] = params }
        try send(message)
        let deadline = Date().addingTimeInterval(20)
        condition.lock()
        while responses[id] == nil && !ended {
            if !condition.wait(until: deadline) { break }
        }
        let response = responses.removeValue(forKey: id)
        let didEnd = ended
        condition.unlock()
        guard let response else {
            if didEnd { throw UsageError.unavailable("Codex disconnected. Update Codex CLI and try again.") }
            throw UsageError.timeout
        }
        if let root = try JSONSerialization.jsonObject(with: response) as? [String: Any], let error = root["error"] as? [String: Any] {
            let message = (error["message"] as? String ?? "").lowercased()
            if ["auth", "sign in", "unauthorized", "401", "chatgpt"].contains(where: message.contains) { throw UsageError.signedOut }
            throw UsageError.unavailable("Codex could not fetch limits. Check your connection and update Codex CLI.")
        }
        return response
    }
    func stop() {
        output.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
            let deadline = Date().addingTimeInterval(1)
            condition.lock()
            while !ended && Date() < deadline { _ = condition.wait(until: deadline) }
            condition.unlock()
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
        try? output.fileHandleForReading.close()
    }
}
