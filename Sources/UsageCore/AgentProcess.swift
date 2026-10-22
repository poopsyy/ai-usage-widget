import Darwin
import Foundation

/// Cancelling an operation terminates only its dedicated process group.
final class AgentCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var pid: pid_t?
    func check() throws { lock.lock(); defer { lock.unlock() }; if cancelled { throw CancellationError() } }
    func attach(_ value: pid_t) { lock.lock(); defer { lock.unlock() }; pid = value; if cancelled { kill(-value, SIGTERM) } }
    func detach() { lock.lock(); defer { lock.unlock() }; pid = nil }
    func cancel() { lock.lock(); defer { lock.unlock() }; cancelled = true; if let pid { kill(-pid, SIGTERM) } }
}

func agentOperation<T: Sendable>(_ body: @escaping @Sendable (AgentCancellation) throws -> T) async throws -> T {
    let cancellation = AgentCancellation()
    return try await withTaskCancellationHandler {
        try await Task.detached(priority: .utility) { try cancellation.check(); return try body(cancellation) }.value
    } onCancel: { cancellation.cancel() }
}

/// Bounded, nonblocking transport. No output is logged or written to disk.
final class AgentProcess: @unchecked Sendable {
    let provider: ProviderID
    let deadline: TimeInterval
    let cancellation: AgentCancellation
    private(set) var pid: pid_t = 0
    private var readFD: Int32 = -1
    private var writeFD: Int32 = -1
    private var exited = false
    private var totalBytes = 0
    private(set) var exitCode: Int32?
    private var pending = Data()
    private var stopped = false

    init(executable: URL, arguments: [String], provider: ProviderID, directory: URL, environment: [String: String], terminal: Bool = false, timeout: TimeInterval = 30, cancellation: AgentCancellation) throws {
        self.provider = provider; self.cancellation = cancellation
        deadline = ProcessInfo.processInfo.systemUptime + timeout
        try cancellation.check()
        var input: [Int32] = [-1, -1], output: [Int32] = [-1, -1]
        var master: Int32 = -1, slave: Int32 = -1
        if terminal {
            var size = winsize(ws_row: 200, ws_col: 160, ws_xpixel: 0, ws_ypixel: 0)
            guard openpty(&master, &slave, nil, nil, &size) == 0 else { throw AgentError.unavailable(provider) }
            var settings = termios()
            if tcgetattr(slave, &settings) == 0 { settings.c_lflag &= ~tcflag_t(ECHO); tcsetattr(slave, TCSANOW, &settings) }
            readFD = master; writeFD = master
        } else {
            guard pipe(&input) == 0 else { throw AgentError.unavailable(provider) }
            guard pipe(&output) == 0 else { close(input[0]); close(input[1]); throw AgentError.unavailable(provider) }
            readFD = output[0]; writeFD = input[1]
        }
        let nullFD = open("/dev/null", O_RDWR)
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions); posix_spawnattr_init(&attributes)
        defer {
            posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attributes)
            if nullFD >= 0 { close(nullFD) }
            if terminal { close(slave) } else { close(input[0]); close(output[1]) }
        }
        posix_spawn_file_actions_adddup2(&actions, terminal ? slave : input[0], STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&actions, terminal ? slave : output[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, terminal ? slave : nullFD, STDERR_FILENO)
        for fd in Set([readFD, writeFD, terminal ? slave : input[0], terminal ? slave : output[1], nullFD]) where fd > 2 {
            posix_spawn_file_actions_addclose(&actions, fd)
        }
        posix_spawn_file_actions_addchdir_np(&actions, directory.path)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&attributes, 0)
        let argv = ([executable.path] + arguments).map { strdup($0) } + [nil]
        let envp = environment.sorted { $0.key < $1.key }.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { argv.forEach { free($0) }; envp.forEach { free($0) } }
        var args = argv, env = envp
        let result = posix_spawn(&pid, executable.path, &actions, &attributes, &args, &env)
        guard result == 0 else {
            close(readFD); if writeFD != readFD { close(writeFD) }; readFD = -1; writeFD = -1
            throw AgentError.unavailable(provider)
        }
        _ = fcntl(readFD, F_SETFL, O_NONBLOCK)
        _ = fcntl(writeFD, F_SETFL, O_NONBLOCK)
        // A closed child stdin must produce EPIPE rather than terminate the widget.
        _ = fcntl(writeFD, F_SETNOSIGPIPE, 1)
        cancellation.attach(pid)
    }
    deinit { stop() }
    func check() throws {
        try cancellation.check()
        guard ProcessInfo.processInfo.systemUptime < deadline else { throw AgentError.timeout(provider) }
    }
    func send(_ text: String) throws {
        try send(Data(text.utf8))
    }
    func send(_ data: Data) throws {
        var offset = 0
        while offset < data.count {
            try check()
            let count = data.withUnsafeBytes { Darwin.write(writeFD, $0.baseAddress!.advanced(by: offset), data.count - offset) }
            if count > 0 { offset += count }
            else if errno == EAGAIN || errno == EINTR { var descriptor = pollfd(fd: writeFD, events: Int16(POLLOUT), revents: 0); poll(&descriptor, 1, 50) }
            else { throw AgentError.unavailable(provider) }
        }
    }
    func readChunk() throws -> Data {
        try check()
        var descriptor = pollfd(fd: readFD, events: Int16(POLLIN), revents: 0)
        poll(&descriptor, 1, 50)
        var bytes = [UInt8](repeating: 0, count: 16384)
        let count = Darwin.read(readFD, &bytes, bytes.count)
        if count > 0 {
            totalBytes += count
            guard totalBytes <= 2_000_000 else { throw AgentError.invalidResponse(provider) }
            return Data(bytes.prefix(count))
        }
        if !exited {
            observeExit()
        }
        if exited, count <= 0 { return Data() }
        if count < 0, errno != EAGAIN, errno != EINTR, errno != EIO { throw AgentError.unavailable(provider) }
        return Data()
    }
    var hasExited: Bool { exited }
    private func observeExit() {
        var info = siginfo_t()
        // Keep the zombie reserved until group cleanup so its pid cannot be reused by another app.
        if waitid(P_PID, id_t(pid), &info, WEXITED | WNOHANG | WNOWAIT) == 0, info.si_pid == pid {
            exited = true
            exitCode = info.si_code == CLD_EXITED ? info.si_status : 128 + info.si_status
        }
    }
    func readLine() throws -> Data {
        while true {
            if let index = pending.firstIndex(of: 10) {
                let line = Data(pending[..<index]); pending.removeSubrange(...index); return line
            }
            let chunk = try readChunk(); pending.append(chunk)
            if hasExited, chunk.isEmpty { throw AgentError.unavailable(provider) }
        }
    }
    func collect() throws -> Data {
        var result = Data()
        while true {
            let chunk = try readChunk(); result.append(chunk)
            if hasExited, chunk.isEmpty { return result }
        }
    }
    func stop() {
        guard !stopped, pid > 0 else { return }; stopped = true
        cancellation.detach()
        kill(-pid, SIGTERM)
        let until = ProcessInfo.processInfo.systemUptime + 0.3
        while !exited, ProcessInfo.processInfo.systemUptime < until {
            observeExit()
            if exited { break }
            usleep(10_000)
        }
        kill(-pid, SIGKILL)
        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1, errno == EINTR {}
        exited = true
        if readFD >= 0 { close(readFD) }
        if writeFD >= 0, writeFD != readFD { close(writeFD) }
        readFD = -1; writeFD = -1
    }
}
