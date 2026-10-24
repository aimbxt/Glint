import AppKit
import SwiftUI
import Combine

@main
enum GlintApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    private var controller: PanelController?
    private var statusItem: NSStatusItem!
    private var showItem: NSMenuItem!
    private var pinItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Glint", isDirectory: true)
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            let store = try TaskStore(url: support.appendingPathComponent("Tasks.store"))
            controller = PanelController(store: store, preferences: Preferences())
            setupMenus()
            controller?.show(focus: false)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Glint couldn’t open your tasks"
            alert.informativeText = "Your saved data has been left in place. \(error.localizedDescription)"
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        controller?.panel.makeFirstResponder(nil)
        return .terminateNow
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func setupMenus() {
        let main = NSMenu()
        let application = NSMenu()
        application.addItem(item("Glint Settings…", #selector(settings), key: ","))
        application.addItem(.separator())
        application.addItem(item("Quit Glint", #selector(quit), key: "q"))
        let appItem = NSMenuItem(); appItem.submenu = application; main.addItem(appItem)

        let edit = NSMenu(title: "Edit")
        edit.addItem(item("Undo", #selector(undo), key: "z"))
        let redoItem = item("Redo", #selector(redo), key: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(redoItem)
        edit.addItem(.separator())
        for (title, action, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
        }
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""); editItem.submenu = edit; main.addItem(editItem)
        let window = NSMenu(title: "Window")
        window.addItem(item("Hide Glint", #selector(hide), key: "w"))
        let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: ""); windowItem.submenu = window; main.addItem(windowItem)
        NSApp.mainMenu = main

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "Glint")
        statusItem.button?.toolTip = "Glint — your floating to-do list"
        let menu = NSMenu(); menu.delegate = self
        showItem = item("Hide Glint", #selector(toggle)); menu.addItem(showItem)
        pinItem = item("Keep on Top", #selector(pin)); menu.addItem(pinItem)
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(settings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item("Quit Glint", #selector(quit), key: "q"))
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        showItem.title = controller?.visible == true ? "Hide Glint" : "Show Glint"
        pinItem.state = controller?.preferences.pinned == true ? .on : .off
    }
    @objc private func toggle() { controller?.toggleVisibility() }
    @objc private func hide() {
        if let window = NSApp.keyWindow, window !== controller?.panel { window.performClose(nil) }
        else { controller?.hide() }
    }
    @objc private func pin() { controller?.preferences.pinned.toggle() }
    @objc private func settings() { controller?.openSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func undo() {
        if let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.undoManager?.canUndo == true { editor.undoManager?.undo() }
        else { controller?.store.undoManager.undo() }
    }
    @objc private func redo() {
        if let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.undoManager?.canRedo == true { editor.undoManager?.redo() }
        else { controller?.store.undoManager.redo() }
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let editor = NSApp.keyWindow?.firstResponder as? NSTextView
        if menuItem.action == #selector(undo) { return editor?.undoManager?.canUndo == true || controller?.store.undoManager.canUndo == true }
        if menuItem.action == #selector(redo) { return editor?.undoManager?.canRedo == true || controller?.store.undoManager.canRedo == true }
        return true
    }
}
