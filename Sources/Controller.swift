import Foundation
import Darwin

struct CommandResult {
    let code: Int32
    let output: String
    var timedOut = false
}

protocol CommandRunning {
    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> CommandResult
}

// Called exclusively on a background queue. A file avoids pipe/EOF waits when a
// launched service outlives launchctl. Every process also has a bounded timeout.
final class ProcessRunner: CommandRunning {
    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> CommandResult {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ou-vpn-\(UUID().uuidString).log")
        guard FileManager.default.createFile(atPath: url.path, contents: nil,
                                             attributes: [.posixPermissions: 0o600]),
              let handle = try? FileHandle(forWritingTo: url) else {
            return CommandResult(code: -1, output: "无法创建操作记录。")
        }
        defer {
            try? handle.close()
            try? FileManager.default.removeItem(at: url)
        }
        let process = Process()
        let finished = DispatchSemaphore(value: 0)
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = handle
        process.standardError = handle
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() }
        catch { return CommandResult(code: -1, output: error.localizedDescription) }
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            if process.isRunning { process.terminate() }
            if finished.wait(timeout: .now() + 0.5) == .timedOut {
                if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
                _ = finished.wait(timeout: .now() + 0.5)
            }
            return CommandResult(code: -1, output: "系统命令等待超时，请稍后再试。", timedOut: true)
        }
        let data = (try? Data(contentsOf: url)) ?? Data()
        return CommandResult(code: process.terminationStatus,
                             output: String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

enum GPState: String { case on, off, partial, unknown }

struct VPNError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

final class GPController {
    static let ui = "com.paloaltonetworks.gp.pangpa"
    static let service = "com.paloaltonetworks.gp.pangps"
    let domain: String
    let runner: CommandRunning
    init(runner: CommandRunning) {
        self.runner = runner
        domain = "gui/\(getuid())"
    }

    private func target(_ label: String) -> String { "\(domain)/\(label)" }
    private func inspectTarget(_ target: String) throws -> String? {
        let result = runner.run("/bin/launchctl", ["print", target], timeout: 3)
        if result.code == 0 && !result.timedOut { return result.output }
        if !result.timedOut && result.output.contains("Could not find service") { return nil }
        throw VPNError(message: "无法读取 GlobalProtect 状态。\n\(result.output)")
    }
    private func inspect(_ label: String) throws -> String? { try inspectTarget(target(label)) }

    func state() throws -> GPState {
        let ui = try inspect(Self.ui)
        let service = try inspect(Self.service)
        if ui == nil && service == nil { return .off }
        if ui?.contains("state = running") == true && service?.contains("state = running") == true { return .on }
        return .partial
    }

    func setEnabled(_ enabled: Bool) throws {
        // zsh expands the wildcard in the original command. No separate app launch.
        let action = enabled ? "load" : "unload"
        let command = "/bin/launchctl \(action) /Library/LaunchAgents/com.paloaltonetworks.gp.pangp*"
        let result = runner.run("/bin/zsh", ["-f", "-c", command], timeout: 60)
        guard result.code == 0 && !result.timedOut else {
            throw VPNError(message: "\(action) 未完成。\n\(result.output)")
        }
    }
}
