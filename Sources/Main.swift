import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var onItem: NSMenuItem!
    private var offItem: NSMenuItem!
    private let worker = DispatchQueue(label: "local.ou-vpn.menubar.worker", qos: .userInitiated)
    private let controller: GPController
    private var isBusy = false
    private var isRefreshing = false
    private var quitAfterOperation = false
    private var currentState = GPState.unknown
    private lazy var monogram: NSImage? = {
        guard let url = Bundle.main.url(forResource: "OUMonogram", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }()

    override init() {
        controller = GPController(runner: ProcessRunner())
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "OUVPNMenuBar"
        onItem = NSMenuItem(title: "On", action: #selector(turnOn), keyEquivalent: "")
        offItem = NSMenuItem(title: "Off", action: #selector(turnOff), keyEquivalent: "")
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        for item in [onItem!, offItem!, quitItem] { item.target = self; menu.addItem(item) }
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.setAccessibilityLabel("OU VPN")
        render()
        refresh()
    }

    func menuWillOpen(_ menu: NSMenu) { refresh() }

    private func refresh() {
        guard !isBusy && !isRefreshing else { return }
        isRefreshing = true
        worker.async { [self] in
            let state = (try? controller.state()) ?? .unknown
            DispatchQueue.main.async { [self] in
                isRefreshing = false
                if !isBusy { currentState = state; render() }
            }
        }
    }

    private func render() {
        statusItem.button?.image = monogram
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.title = isBusy ? "…" : (monogram == nil ? "OU" : "")
        statusItem.button?.appearsDisabled = currentState == .off && !isBusy
        onItem.isEnabled = !isBusy
        offItem.isEnabled = !isBusy
        onItem.state = currentState == .on && !isBusy ? .on : .off
        offItem.state = currentState == .off && !isBusy ? .on : .off
        let detail: String
        if isBusy { detail = quitAfterOperation ? "完成开关操作后退出" : "正在处理，请稍候" }
        else {
            switch currentState {
            case .on: detail = "GlobalProtect 已开启；VPN 是否连通请查看 Connected"
            case .off: detail = "GlobalProtect 已关闭"
            case .partial: detail = "GlobalProtect 状态不完整，可重新选择 On 或 Off"
            case .unknown: detail = "右键选择 On、Off 或 Quit"
            }
        }
        statusItem.button?.toolTip = "OU VPN — \(detail)"
    }

    @objc private func turnOn() { perform(enabled: true) }
    @objc private func turnOff() { perform(enabled: false) }

    private func perform(enabled: Bool) {
        guard !isBusy else { return }
        isBusy = true
        render()
        worker.async { [self] in
            var operationError: Error?
            do { try controller.setEnabled(enabled) }
            catch { operationError = error }
            let state = (try? controller.state()) ?? .unknown
            let errorToPresent = operationError
            DispatchQueue.main.async { [self] in
                currentState = state
                isBusy = false
                render()
                if quitAfterOperation {
                    NSApp.reply(toApplicationShouldTerminate: true)
                    return
                }
                if let error = errorToPresent {
                    NSApp.activate(ignoringOtherApps: true)
                    let alert = NSAlert()
                    alert.messageText = enabled ? "On 未完成" : "Off 未完成"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "好")
                    alert.runModal()
                }
            }
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Quit never sends an On or Off command. If the user has already started
        // an operation, let it finish before exiting rather than leaving it halfway.
        if isBusy {
            quitAfterOperation = true
            render()
            return .terminateLater
        }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Deliberately no launchctl commands or GlobalProtect cleanup here.
    }
}

@main struct Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
