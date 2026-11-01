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
    let validateFiles: Bool
    let pollDelay: TimeInterval
    let appPath = "/Applications/GlobalProtect.app"

    init(runner: CommandRunning, validateFiles: Bool = true, pollDelay: TimeInterval = 0.25) {
        self.runner = runner
        self.validateFiles = validateFiles
        self.pollDelay = pollDelay
        domain = "gui/\(getuid())"
    }

    private func plist(_ label: String) -> String { "/Library/LaunchAgents/\(label).plist" }
    private func target(_ label: String) -> String { "\(domain)/\(label)" }
    private func command(_ args: [String], timeout: TimeInterval = 5) -> CommandResult {
        runner.run("/bin/launchctl", args, timeout: timeout)
    }
    private func require(_ result: CommandResult, _ context: String) throws {
        guard result.code == 0 && !result.timedOut else {
            throw VPNError(message: "\(context)\n\(result.output)")
        }
    }
    private func inspectTarget(_ target: String) throws -> String? {
        let result = command(["print", target], timeout: 3)
        if result.code == 0 && !result.timedOut { return result.output }
        if !result.timedOut && result.output.contains("Could not find service") { return nil }
        throw VPNError(message: "无法读取 GlobalProtect 状态。\n\(result.output)")
    }
    private func inspect(_ label: String) throws -> String? { try inspectTarget(target(label)) }
    private func isRunning(_ label: String) throws -> Bool {
        try inspect(label)?.contains("state = running") == true
    }
    private func waitBriefly() {
        if pollDelay > 0 { Thread.sleep(forTimeInterval: pollDelay) }
    }

    func state() throws -> GPState {
        let ui = try inspect(Self.ui)
        let service = try inspect(Self.service)
        if ui == nil && service == nil { return .off }
        if ui?.contains("state = running") == true && service?.contains("state = running") == true { return .on }
        return .partial
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled { try turnOn() } else { try turnOff() }
    }

    private func turnOn() throws {
        if validateFiles {
            for path in [appPath, plist(Self.service), plist(Self.ui)] {
                guard FileManager.default.fileExists(atPath: path) else {
                    throw VPNError(message: "找不到 GlobalProtect 安装文件：\n\(path)")
                }
            }
        }
        try require(command(["print", domain]), "请在当前 Mac 桌面登录用户下运行。")
        for label in [Self.service, Self.ui] {
            // Re-enable launch agents without changing school settings or
            // restarting an already running VPN connection.
            try require(command(["enable", target(label)]), "无法恢复 GlobalProtect 启动权限。")
            if try inspect(label) == nil {
                // Same load command as the user's screenshot, with exact paths.
                let result = command(["load", plist(label)], timeout: 15)
                if result.code != 0 || result.timedOut {
                    if try inspect(label) == nil {
                        try require(result, "无法加载 GlobalProtect。")
                    }
                }
            }
            if try !isRunning(label) {
                try require(command(["kickstart", target(label)]), "无法启动 GlobalProtect。")
            }
        }
        for _ in 0..<20 {
            if try state() == .on {
                try require(runner.run("/usr/bin/open", ["-a", appPath], timeout: 5), "后台服务已启动，但无法打开 GlobalProtect。")
                return
            }
            waitBriefly()
        }
        throw VPNError(message: "GlobalProtect 尚未正常启动。请检查系统设置中是否允许 Palo Alto Networks 在后台运行。")
    }

    private func turnOff() throws {
        if try inspectTarget("system/com.paloaltonetworks.gp.pangpsd") != nil {
            throw VPNError(message: "检测到另一种系统级 GlobalProtect 服务，无法确认完整关闭。请先在 GlobalProtect 中点击 Disconnect。")
        }
        var errors: [String] = []
        for label in [Self.ui, Self.service] {
            do {
                if try inspect(label) != nil {
                    // Same unload command as the screenshot. Allow the service's
                    // 20-second graceful shutdown without freezing the menu bar.
                    let result = command(["unload", plist(label)], timeout: 30)
                    if result.code != 0 || result.timedOut {
                        if try inspect(label) != nil { errors.append(result.output) }
                    }
                }
            } catch { errors.append(error.localizedDescription) }
        }
        for _ in 0..<20 {
            if try state() == .off {
                let processes = runner.run("/usr/bin/pgrep", ["-f", "^/Applications/GlobalProtect[.]app/Contents/(MacOS/GlobalProtect|Resources/PanGPS)([[:space:]]|$)"], timeout: 3)
                if processes.code == 1 && !processes.timedOut { return }
                if processes.code != 0 || processes.timedOut {
                    throw VPNError(message: "无法确认 GlobalProtect 进程已退出。\n\(processes.output)")
                }
            }
            waitBriefly()
        }
        throw VPNError(message: "GlobalProtect 关闭未完成，请稍后重试。\n\(errors.joined(separator: "\n"))")
    }
}
