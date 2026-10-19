import AppKit
import SwiftUI
import Combine
import Carbon
import ServiceManagement

/// Global hotkey via Carbon (works without any special permission).
final class HotKey {
    static var handler: (() -> Void)?
    private var ref: EventHotKeyRef?
    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        HotKey.handler = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            HotKey.handler?()
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x4A565345), id: 1)
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
    }
}

final class Panel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = Launcher()
    var panel: Panel!
    var status: NSStatusItem!
    var hotKey: HotKey?
    var bag = Set<AnyCancellable>()
    let width: CGFloat = 680

    func applicationDidFinishLaunching(_ n: Notification) {
        setupMenu()
        setupPanel()
        setupStatus()
        model.onClose = { [weak self] in self?.hide() }
        hotKey = HotKey(keyCode: 49, modifiers: UInt32(optionKey)) { [weak self] in self?.toggle() }  // Option+Space
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let s = self else { return e }
            return s.key(e)
        }
        show()
    }

    func key(_ e: NSEvent) -> NSEvent? {
        guard panel.isKeyWindow else { return e }
        switch e.keyCode {
        case 125: model.move(1); return nil
        case 126: model.move(-1); return nil
        case 53: if model.query.isEmpty { hide() } else { model.query = "" }; return nil
        case 48: model.tab(); return nil
        default: break
        }
        if e.modifierFlags.contains(.option), let c = e.charactersIgnoringModifiers, let n = Int(c), (1...9).contains(n) {
            model.run(n - 1)
            return nil
        }
        return e
    }

    func setupPanel() {
        panel = Panel(contentRect: NSRect(x: 0, y: 0, width: width, height: 72),
                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: RootView(m: model))
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            self?.hide()
        }
        model.$items.receive(on: DispatchQueue.main).sink { [weak self] items in
            self?.resize(items.count)
        }.store(in: &bag)
    }

    func resize(_ n: Int) {
        let h = CGFloat(72 + (n > 0 ? 1 : 0) + min(n, 8) * 48)
        var f = panel.frame
        f.origin.y += f.height - h
        f.size = NSSize(width: width, height: h)
        panel.setFrame(f, display: true)
    }

    func position() {
        let scr = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let s = scr.visibleFrame
        panel.setFrameTopLeftPoint(NSPoint(x: s.midX - width / 2, y: s.maxY - s.height * 0.2))
    }

    func show() {
        model.query = ""
        position()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        model.focusTick += 1
    }
    func hide() { panel.orderOut(nil) }
    func toggle() { panel.isVisible ? hide() : show() }

    func setupStatus() {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.title = "🎩"
        let m = NSMenu()
        let show = NSMenuItem(title: "Show Jeeves", action: #selector(showAction), keyEquivalent: "")
        show.target = self
        let login = NSMenuItem(title: "Launch at login", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        let quit = NSMenuItem(title: "Quit Jeeves", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        [show, login, quit].forEach { m.addItem($0) }
        status.menu = m
    }
    @objc func showAction() { show() }
    @objc func toggleLogin(_ item: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch {}
        item.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    /// Accessory apps have no menu bar, so text fields need an Edit menu for ⌘C / ⌘V / ⌘A to work.
    func setupMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Jeeves", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        NSApp.mainMenu = main
    }
}
