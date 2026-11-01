import Foundation

final class FakeRunner: CommandRunning {
    var services: Set<String> = []
    var disabled: Set<String> = [GPController.ui, GPController.service]
    var calls: [(String, [String])] = []
    var failure: String?
    var systemDaemon = false
    var residualProcess = false
    var inspectionError = false
    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> CommandResult {
        calls.append((executable, arguments))
        if executable.hasSuffix("pgrep") { return CommandResult(code: residualProcess ? 0 : 1, output: "") }
        if executable.hasSuffix("open") { return CommandResult(code: 0, output: "") }
        let op = arguments[0]
        let target = arguments[1]
        let label = URL(fileURLWithPath: target).lastPathComponent.replacingOccurrences(of: ".plist", with: "")
        if failure == "\(op):\(label)" { return CommandResult(code: 5, output: "test failure") }
        if op == "print" {
            if inspectionError { return CommandResult(code: -1, output: "timed out", timedOut: true) }
            if target.hasPrefix("gui/") && target.split(separator: "/").count == 2 { return CommandResult(code: 0, output: "") }
            if target.hasPrefix("system/") { return CommandResult(code: systemDaemon ? 0 : 113, output: systemDaemon ? "state = running" : "Could not find service") }
            return CommandResult(code: services.contains(label) ? 0 : 113, output: services.contains(label) ? "state = running" : "Could not find service")
        }
        if op == "enable" { disabled.remove(label) }
        if op == "load" {
            if disabled.contains(label) { return CommandResult(code: 5, output: "disabled") }
            services.insert(label)
        }
        if op == "unload" { services.remove(label) }
        return CommandResult(code: 0, output: "")
    }
}

@main struct Tests {
    static var count = 0
    static func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try value() else { fatalError(message) }
        count += 1
    }
    static func expectError(_ body: () throws -> Void) throws {
        do { try body() } catch { count += 1; return }
        fatalError("Expected an error")
    }
    static func main() throws {
        let fake = FakeRunner()
        let controller = GPController(runner: fake, validateFiles: false, pollDelay: 0)
        try check(try controller.state() == .off, "Initially off")
        try check(fake.calls.allSatisfy { $0.1[0] == "print" }, "Opening app must only inspect")
        try controller.setEnabled(true)
        try check(try controller.state() == .on, "On starts both services")
        try check(fake.disabled.isEmpty, "On repairs disabled flags from old app")
        let loadCount = fake.calls.filter { $0.1[0] == "load" }.count
        try controller.setEnabled(true)
        try check(fake.calls.filter { $0.1[0] == "load" }.count == loadCount, "Repeated On does not restart connection")
        try check(!fake.calls.contains { $0.1.contains("-k") }, "No forced service restarts")
        try controller.setEnabled(false)
        try check(try controller.state() == .off, "Off unloads both services")
        let unloads = fake.calls.filter { $0.1[0] == "unload" }.map { $0.1[1] }
        try check(unloads[0].contains(GPController.ui) && unloads[1].contains(GPController.service), "Unload UI before service")
        try controller.setEnabled(false)
        try check(fake.calls.filter { $0.1[0] == "unload" }.count == 2, "Repeated Off is harmless")
        fake.systemDaemon = true
        try expectError { try controller.setEnabled(false) }
        fake.systemDaemon = false
        fake.failure = "load:\(GPController.service)"
        try expectError { try controller.setEnabled(true) }
        fake.failure = nil
        try controller.setEnabled(true)
        fake.failure = "unload:\(GPController.ui)"
        try expectError { try controller.setEnabled(false) }
        try check(!fake.services.contains(GPController.service), "Service stop still attempted after UI failure")
        fake.failure = nil
        fake.residualProcess = true
        try expectError { try controller.setEnabled(false) }
        fake.residualProcess = false
        fake.inspectionError = true
        try expectError { _ = try controller.state() }

        let real = ProcessRunner()
        let start = Date()
        let timeout = real.run("/bin/sleep", ["5"], timeout: 0.15)
        try check(timeout.timedOut && Date().timeIntervalSince(start) < 2, "Process timeout must be bounded")
        let large = real.run("/usr/bin/seq", ["1", "100000"], timeout: 5)
        try check(large.code == 0 && large.output.hasSuffix("100000"), "Large output must not block on a pipe")
        let absent = real.run("/nonexistent/ou-vpn-test", [], timeout: 1)
        try check(absent.code != 0, "Missing command reports failure")
        print("Passed \(count) controller and process-runner checks.")
    }
}
