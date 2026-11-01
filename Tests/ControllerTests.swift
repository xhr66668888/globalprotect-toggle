import Foundation

final class RecordingRunner: CommandRunning {
    var calls: [(executable: String, arguments: [String])] = []
    var result = CommandResult(code: 0, output: "")
    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> CommandResult {
        calls.append((executable, arguments))
        return result
    }
}

@main struct Tests {
    static func main() throws {
        let runner = RecordingRunner()
        let controller = GPController(runner: runner)
        try controller.setEnabled(true)
        precondition(runner.calls.count == 1, "On must not perform any additional launch action")
        precondition(runner.calls[0].executable == "/bin/zsh")
        precondition(runner.calls[0].arguments == ["-f", "-c", "/bin/launchctl load /Library/LaunchAgents/com.paloaltonetworks.gp.pangp*"])

        runner.calls.removeAll()
        try controller.setEnabled(false)
        precondition(runner.calls.count == 1, "Off must run only the original unload command")
        precondition(runner.calls[0].executable == "/bin/zsh")
        precondition(runner.calls[0].arguments == ["-f", "-c", "/bin/launchctl unload /Library/LaunchAgents/com.paloaltonetworks.gp.pangp*"])

        // Repeating On repeats load, without opening or kickstarting another app.
        runner.calls.removeAll()
        try controller.setEnabled(true)
        try controller.setEnabled(true)
        precondition(runner.calls.count == 2)
        precondition(runner.calls.allSatisfy { $0.executable == "/bin/zsh" && $0.arguments.last == "/bin/launchctl load /Library/LaunchAgents/com.paloaltonetworks.gp.pangp*" })

        runner.result = CommandResult(code: 5, output: "test command failed")
        do {
            try controller.setEnabled(true)
            preconditionFailure("Command failures must be reported")
        } catch let error as VPNError {
            precondition(error.message.contains("test command failed"))
        }
        runner.result = CommandResult(code: 0, output: "", timedOut: true)
        do {
            try controller.setEnabled(false)
            preconditionFailure("Timeouts must be reported")
        } catch is VPNError { }
        print("On and Off execute only the original load/unload commands; failure reporting passed.")
    }
}
