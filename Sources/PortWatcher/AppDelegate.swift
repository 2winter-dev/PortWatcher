import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var monitorToken: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            // 优先用自绘顶栏模板图（黑色单色，isTemplate 跟随菜单栏明暗自动反色）
            if let url = Bundle.main.url(forResource: "menubar", withExtension: "png"),
               let img = NSImage(contentsOf: url) {
                img.isTemplate = true
                img.size = NSSize(width: 20, height: 20)
                button.image = img
            } else {
                // 兜底：直接跑二进制（无 .app bundle）时退回 SF Symbol
                button.image = NSImage(systemSymbolName: "network",
                                       accessibilityDescription: "PortWatcher")
                button.image?.isTemplate = true
            }
            button.action = #selector(togglePopover(_:))
            button.target = self
            // 左键弹面板、右键弹菜单（关于/退出）
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item

        let root = ContentView()
            .environmentObject(PortMonitor.shared)
            .environmentObject(HistoryStore.shared)
            .environmentObject(L10n.shared)
        let vc = NSHostingController(rootView: root)
        vc.view.frame = NSRect(x: 0, y: 0, width: 480, height: 680)

        let pop = NSPopover()
        pop.contentViewController = vc
        pop.behavior = .transient
        pop.contentSize = NSSize(width: 480, height: 680)
        popover = pop

        updateTitle()
        monitorToken = PortMonitor.shared.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { @MainActor in self?.updateTitle() }
        }

        PortMonitor.shared.startTimer()
        PortMonitor.shared.refresh()
    }

    private func updateTitle() {
        guard let button = statusItem?.button else { return }
        button.title = " \(PortMonitor.shared.ports.count)"
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let pop = popover, let button = statusItem?.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
            return
        }
        if pop.isShown {
            pop.performClose(nil)
        } else {
            pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    // 右键菜单：关于 / 退出。临时挂 menu 触发展示，收起后移除以恢复左键 popover 行为
    private func showStatusMenu() {
        let menu = NSMenu()
        let about = NSMenuItem(title: L10n.shared.loc("aboutPortWatcher"), action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: L10n.shared.loc("quitPortWatcher"), action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func showAbout() {
        let a = NSAlert()
        a.messageText = "PortWatcher"
        a.informativeText = L10n.shared.loc("aboutText")
        a.alertStyle = .informational
        a.runModal()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitorToken?.cancel()
    }
}
