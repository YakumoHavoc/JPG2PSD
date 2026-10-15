//
//  AppDelegate.swift
//  JPG → PSD 批量无损转换
//
//  用 NSApplicationDelegate 原生接收 Finder 拖到图标上的文件（odoc AppleEvent），
//  不需要任何 argv 仿真，也不会像 Tk 那样在初始化菜单时崩溃。
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: MainWindowController?
    /// 启动早期（窗口还没建好）收到的文件路径先缓存
    private var pendingPaths: [String] = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        buildMenu()
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = MainWindowController()
        self.controller = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)

        if !pendingPaths.isEmpty {
            controller.addSources(pendingPaths)
            pendingPaths.removeAll()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Finder 把文件 / 文件夹拖到应用图标上，或双击由本应用打开的文件
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        if let controller {
            controller.addSources(filenames)
        } else {
            pendingPaths.append(contentsOf: filenames)
        }
        sender.reply(toOpenOrPrint: .success)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            controller?.showWindow(nil)
            controller?.window?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - 菜单（提供 ⌘Q / 编辑快捷键等标准行为）

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu(title: "JPG转PSD")
        appMenu.addItem(withTitle: "关于 JPG转PSD",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 JPG转PSD",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 JPG转PSD",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "最小化",
                           action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "缩放",
                           action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }
}
