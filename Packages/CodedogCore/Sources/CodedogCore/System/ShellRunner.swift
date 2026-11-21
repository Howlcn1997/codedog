import Foundation

public struct ShellResult: Sendable {
    public var status: Int32
    public var stdout: String
    public var stderr: String
    public var ok: Bool { status == 0 }
}

public enum ShellError: Error, Sendable {
    case notFound(String)
    case timedOut(String)
}

/// 运行外部命令。不经过 shell，带超时，使用登录 shell 的 PATH。
public enum ShellRunner {
    /// 同时运行的外部进程上限。每个进程要占两个阻塞线程读输出，进程太多会耗尽 GCD 线程池，
    /// 导致读取排不上队、命令超时（扫描几十个项目时出现过 git log 大面积超时）。
    static let limiter = ProcessLimiter(limit: 12)

    public static func run(_ executable: String, _ arguments: [String], cwd: String? = nil, timeout: Duration = .seconds(30), environment extra: [String: String] = [:]) async throws -> ShellResult {
        // 排队等待不计入超时
        await limiter.acquire()
        do {
            let result = try await runNow(executable, arguments, cwd: cwd, timeout: timeout, environment: extra)
            await limiter.release()
            return result
        } catch {
            await limiter.release()
            throw error
        }
    }

    private static func runNow(_ executable: String, _ arguments: [String], cwd: String?, timeout: Duration, environment extra: [String: String]) async throws -> ShellResult {
        let env = await LoginEnvironment.shared.environment.merging(extra) { $1 }
        guard let exe = resolve(executable, path: env["PATH"] ?? "") else { throw ShellError.notFound(executable) }

        let process = Process()
        process.executableURL = URL(filePath: exe)
        process.arguments = arguments
        process.environment = env
        if let cwd { process.currentDirectoryURL = URL(filePath: cwd, directoryHint: .isDirectory) }
        process.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err

        return try await withThrowingTaskGroup(of: ShellResult?.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<ShellResult?, Error>) in
                    // 先并发读取管道，避免输出过大时阻塞子进程。
                    let outBox = DataBox(), errBox = DataBox()
                    let reading = DispatchGroup()
                    for (pipe, box) in [(out, outBox), (err, errBox)] {
                        reading.enter()
                        DispatchQueue.global().async {
                            box.data = pipe.fileHandleForReading.readDataToEndOfFile()
                            reading.leave()
                        }
                    }
                    process.terminationHandler = { p in
                        reading.notify(queue: .global()) {
                            cont.resume(returning: ShellResult(
                                status: p.terminationStatus,
                                stdout: String(decoding: outBox.data, as: UTF8.self),
                                stderr: String(decoding: errBox.data, as: UTF8.self)))
                        }
                    }
                    do { try process.run() } catch { cont.resume(throwing: error) }
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                return nil
            }
            defer { group.cancelAll() }
            guard let first = try await group.next(), let result = first else {
                if process.isRunning { process.terminate() }
                throw ShellError.timedOut(([executable] + arguments).joined(separator: " "))
            }
            return result
        }
    }

    static func resolve(_ name: String, path: String) -> String? {
        if name.contains("/") { return FileManager.default.isExecutableFile(atPath: name) ? name : nil }
        for dir in path.split(separator: ":") {
            let candidate = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }
}

/// 简单的异步信号量。
actor ProcessLimiter {
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { available = limit }

    func acquire() async {
        if available > 0 { available -= 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty { available += 1 } else { waiters.removeFirst().resume() }
    }
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}

/// 从访达启动的 App 只有最小 PATH；读取一次用户登录 shell 的 PATH，保证能找到 git、claude 等工具。
public actor LoginEnvironment {
    public static let shared = LoginEnvironment()
    private var cached: [String: String]?

    public var environment: [String: String] {
        get async {
            if let cached { return cached }
            var env = ProcessInfo.processInfo.environment
            env["GIT_TERMINAL_PROMPT"] = "0"
            if env["CODEDOG_SKIP_PATH"] == nil, let path = await Self.loginPath(shell: env["SHELL"] ?? "/bin/zsh") {
                env["PATH"] = path
            } else {
                env["PATH"] = (env["PATH"] ?? "") + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            }
            cached = env
            return env
        }
    }

    private static func loginPath(shell: String) async -> String? {
        await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = URL(filePath: shell)
            p.arguments = ["-ilc", "printf '\\nCODEDOG_PATH=%s\\n' \"$PATH\""]
            p.standardInput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            let out = Pipe()
            p.standardOutput = out
            let done = DispatchSemaphore(value: 0)
            p.terminationHandler = { _ in done.signal() }
            let box = DataBox()
            let read = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                do { try p.run() } catch { cont.resume(returning: nil); return }
                DispatchQueue.global().async {
                    box.data = out.fileHandleForReading.readDataToEndOfFile()
                    read.signal()
                }
                if done.wait(timeout: .now() + 5) == .timedOut { p.terminate() }
                _ = read.wait(timeout: .now() + 1)
                let text = String(decoding: box.data, as: UTF8.self)
                let line = text.split(separator: "\n").last { $0.hasPrefix("CODEDOG_PATH=") }
                cont.resume(returning: line.map { String($0.dropFirst("CODEDOG_PATH=".count)) })
            }
        }
    }
}
