import Foundation
import UsageCore
import Darwin

func option(_ name: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: name), CommandLine.arguments.indices.contains(index + 1) else { return nil }
    return CommandLine.arguments[index + 1]
}

if CommandLine.arguments.contains("--check-claude") {
    let path = option("--claude-path") ?? ""
    let directory = option("--directory").map { URL(fileURLWithPath: $0) } ?? UsageFiles.directory
    Task {
        do {
            _ = try await ClaudeCLIProvider(executableOverride: path, directory: directory).fetchAccount()
            print("Claude check: quota read succeeded. Account details and usage values omitted.")
            exit(0)
        } catch {
            // Only fixed, app-authored messages: never print captured output or arbitrary errors.
            let problem = error as? AgentError ?? .unavailable(.claude)
            print("Claude check: \(problem.localizedDescription)")
            exit(1)
        }
    }
    dispatchMain()
}

if CommandLine.arguments.contains("--probe-codex") {
    let override = option("--codex-path") ?? ""
    Task {
        do {
            let snapshot = try await CodexProvider(executableOverride: override).fetch()
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            let result = try encoder.encode(snapshot)
            FileHandle.standardOutput.write(result); print("")
            exit(0)
        } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
    }
    dispatchMain()
}

let directory = option("--directory").map { URL(fileURLWithPath: $0) } ?? UsageFiles.directory
let input = FileHandle.standardInput.readDataToEndOfFile()
// Do not log input: status-line payloads can contain workspace and session metadata.
let snapshot = input.count < 2_000_000 ? try? ClaudeCapture.capture(input, directory: directory) : nil
let state = try? UsageFiles.read(IntegrationState.self, from: directory.appendingPathComponent("claude-integration.json"))
let previous = state?.previousStatusLine.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
if let command = previous?["command"] as? String, !command.isEmpty {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command]
    process.standardInput = pipe
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
        DispatchQueue.global().async {
            try? pipe.fileHandleForWriting.write(contentsOf: input)
            try? pipe.fileHandleForWriting.close()
        }
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now() + 3)
        timer.setEventHandler { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
        timer.resume()
        process.waitUntilExit()
        timer.cancel()
    } catch { /* Capturing usage must never break a Claude session. */ }
} else if let snapshot {
    print(snapshot.windows.map { "\($0.title): \(Int($0.usedPercent.rounded()))% used" }.joined(separator: " · "))
} else { print("Claude") }
