import SwiftUI
import AppKit
import SystemConfiguration

@main
struct NightShiftAgentApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() } // No window needed
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var isEnabled = false
    private var toggleMenuItem: NSMenuItem?
    private var dnsTask: Process?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = "NightShift"
        statusItem?.menu = buildMenu()

        // Listen for sleep notifications to re-register.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(willSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let toggle = NSMenuItem(title: isEnabled ? "Disable" : "Enable", action: #selector(toggleProxy), keyEquivalent: "")
        toggle.target = self
        toggleMenuItem = toggle
        menu.addItem(toggle)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    @objc private func toggleProxy() {
        isEnabled.toggle()
        statusItem?.button?.title = isEnabled ? "NightShift ✅" : "NightShift"
        toggleMenuItem?.title = isEnabled ? "Disable" : "Enable"

        if isEnabled {
            DispatchQueue.global(qos: .background).async { [weak self] in
                self?.registerWithProxy()
            }
        } else {
            unregisterFromProxy()
        }
    }

    @objc private func willSleep() {
        guard isEnabled else { return }
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.registerWithProxy()
        }
    }

    nonisolated private func registerWithProxy() {
        // NOTE: Replace the MAC/IP arguments below with your machine's values.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/dns-sd")
        task.arguments = [
            "-R",
            "MyMac",
            "_sleep-proxy._udp",
            "local",
            "9",
            "mac=aa:bb:cc:dd:ee:ff",
            "ip=192.168.1.100"
        ]
        
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        
        do {
            try task.run()
            DispatchQueue.main.async { [weak self] in
                self?.dnsTask = task
            }
            NSLog("Registered with proxy")
        } catch {
            NSLog("Failed to register: \(error)")
        }
    }
    
    private func unregisterFromProxy() {
        if let task = dnsTask, task.isRunning {
            task.terminate()
            NSLog("Unregistered from proxy")
        }
        dnsTask = nil
    }
}
