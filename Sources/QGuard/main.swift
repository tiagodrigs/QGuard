// QGuard — menu-bar app that stops ⌘⇧Q / ⌥⌘⇧Q from triggering "Log Out".
//
// Two layers:
//  1. Carbon RegisterEventHotKey claims both combos. Needs no permissions, but games
//     like WoW disable global hotkeys while focused, so it doesn't cover them.
//  2. A keyboard event tap (needs Accessibility) drops ⌘⇧Q before any app sees it,
//     including games. The callback only inspects keycode + modifiers and returns
//     every other event untouched; nothing is stored or logged.
//
// Optional: while World of Warcraft is frontmost, the tap replaces ⌘⇧Q with a
// user-chosen key combo (default ⌃⇧Q) instead of dropping it, so it can be bound in-game.

import AppKit
import Carbon.HIToolbox
import ServiceManagement

let wowBundleID = "com.blizzard.worldofwarcraft"

// MARK: - Settings

enum Settings {
    static let forwardKey = "forwardToWoW"
    static let comboKeyCode = "wowKeyCode"
    static let comboFlags = "wowFlags"

    static let defaultCombo = KeyCombo(keyCode: CGKeyCode(kVK_ANSI_Q), flags: [.maskControl, .maskShift])

    static var forward: Bool {
        get { UserDefaults.standard.bool(forKey: forwardKey) }
        set { UserDefaults.standard.set(newValue, forKey: forwardKey) }
    }

    static var combo: KeyCombo {
        get {
            let d = UserDefaults.standard
            guard d.object(forKey: comboKeyCode) != nil else { return defaultCombo }
            return KeyCombo(keyCode: CGKeyCode(d.integer(forKey: comboKeyCode)),
                            flags: CGEventFlags(rawValue: UInt64(d.integer(forKey: comboFlags))))
        }
        set {
            UserDefaults.standard.set(Int(newValue.keyCode), forKey: comboKeyCode)
            UserDefaults.standard.set(Int(newValue.flags.rawValue), forKey: comboFlags)
        }
    }
}

// MARK: - Key combo

struct KeyCombo {
    static let modifierMask: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]

    var keyCode: CGKeyCode
    var flags: CGEventFlags

    init(keyCode: CGKeyCode, flags: CGEventFlags) {
        self.keyCode = keyCode
        self.flags = flags.intersection(KeyCombo.modifierMask)
    }

    /// The combo QGuard exists to block: anything ⌘⇧Q.
    var isLogoutCombo: Bool {
        keyCode == CGKeyCode(kVK_ANSI_Q) && flags.contains(.maskCommand) && flags.contains(.maskShift)
    }

    var displayName: String {
        var s = ""
        if flags.contains(.maskControl) { s += "⌃" }
        if flags.contains(.maskAlternate) { s += "⌥" }
        if flags.contains(.maskShift) { s += "⇧" }
        if flags.contains(.maskCommand) { s += "⌘" }
        return s + KeyCombo.keyName(keyCode)
    }

    private static let specialKeys: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫", kVK_Escape: "⎋",
        kVK_ForwardDelete: "⌦", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]

    /// Name of the key in the current keyboard layout (e.g. "Q", "1", "F5").
    static func keyName(_ code: CGKeyCode) -> String {
        if let n = specialKeys[Int(code)] { return n }
        guard let src = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else { return "#\(code)" }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var dead: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var len = 0
        let status = data.withUnsafeBytes { raw in
            UCKeyTranslate(raw.bindMemory(to: UCKeyboardLayout.self).baseAddress, code, UInt16(kUCKeyActionDisplay), 0,
                           UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &len, &chars)
        }
        guard status == noErr, len > 0 else { return "#\(code)" }
        return String(utf16CodeUnits: chars, count: len).uppercased()
    }
}

// MARK: - App

final class App: NSObject, NSApplicationDelegate {
    private enum Action { case drop, replace(KeyCombo) }

    private var statusItem: NSStatusItem!
    private var registered = 0
    fileprivate var tap: CFMachPort?
    /// What we did with the last ⌘⇧Q key-down, so its key-up gets the same treatment
    /// even if ⌘/⇧ were released first (otherwise the replacement key could stick).
    private var pending: Action?
    private let headerItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let tapItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let forwardItem = NSMenuItem(title: "", action: #selector(toggleForward), keyEquivalent: "")
    private let changeItem = NSMenuItem(title: "Change WoW Key…", action: #selector(changeCombo), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")

    func applicationDidFinishLaunching(_ n: Notification) {
        registerHotKeys()
        buildMenu()
        if !installTap() {
            // Wait for the user to grant Accessibility, then install without a relaunch.
            Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
                if self?.installTap() == true { t.invalidate() }
            }
        }
        refresh()
    }

    // MARK: Hotkeys (no permissions; covers regular apps)

    private func registerHotKeys() {
        // Claiming the combo is what stops Log Out; the handler has nothing to do.
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in noErr }, 1, &spec, nil, nil)

        let combos: [UInt32] = [
            UInt32(cmdKey | shiftKey),              // ⌘⇧Q  — Log Out…
            UInt32(cmdKey | shiftKey | optionKey),  // ⌥⌘⇧Q — Log Out immediately
        ]
        for (i, mods) in combos.enumerated() {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x51475244) /* 'QGRD' */, id: UInt32(i + 1))
            if RegisterEventHotKey(UInt32(kVK_ANSI_Q), mods, id, GetApplicationEventTarget(), 0, &ref) == noErr {
                registered += 1
            }
        }
    }

    // MARK: Event tap (covers games that disable global hotkeys)

    @discardableResult
    private func installTap() -> Bool {
        guard tap == nil, AXIsProcessTrusted() else { return tap != nil }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask, callback: tapCallback,
                                        userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        tap = t
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, t, 0), .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        refresh()
        return true
    }

    /// Returns nil to drop the event, the same event to pass it on, or a replacement event.
    fileprivate func filter(_ type: CGEventType, _ e: CGEvent) -> Unmanaged<CGEvent>? {
        guard e.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_ANSI_Q) else { return .passUnretained(e) }

        let action: Action
        if type == .keyDown && KeyCombo(keyCode: CGKeyCode(kVK_ANSI_Q), flags: e.flags).isLogoutCombo {
            action = Settings.forward && NSWorkspace.shared.frontmostApplication?.bundleIdentifier == wowBundleID
                ? .replace(Settings.combo) : .drop
            pending = action
        } else if let p = pending {
            action = p                       // key-up (or repeat) belonging to a handled ⌘⇧Q
            if type == .keyUp { pending = nil }
        } else {
            return .passUnretained(e)        // plain Q, ⌃Q, ⇧Q… untouched
        }

        switch action {
        case .drop:
            return nil
        case .replace(let combo):
            guard let out = CGEvent(keyboardEventSource: CGEventSource(event: e), virtualKey: combo.keyCode,
                                    keyDown: type == .keyDown) else { return nil }
            out.flags = e.flags.subtracting(KeyCombo.modifierMask).union(combo.flags)
            out.setIntegerValueField(.keyboardEventAutorepeat, value: e.getIntegerValueField(.keyboardEventAutorepeat))
            return .passRetained(out)        // the event system releases replacement events
        }
    }

    // MARK: Menu

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = QIcon.menuBarImage()
        let menu = NSMenu()
        menu.addItem(headerItem)
        menu.addItem(tapItem)
        menu.addItem(.separator())
        for item in [tapItem, forwardItem, changeItem, loginItem] { item.target = self }
        for item in [forwardItem, changeItem, loginItem] {
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit QGuard (re-enables ⌘⇧Q Log Out)", action: #selector(NSApp.terminate), keyEquivalent: ""))
        statusItem.menu = menu
    }

    private func refresh() {
        headerItem.title = registered == 2
            ? "⌘⇧Q Log Out: blocked"
            : "⚠︎ Could only claim \(registered)/2 shortcuts"
        tapItem.title = tap != nil
            ? "In-game protection: active"
            : "⚠︎ In-game protection off: click to grant Accessibility…"
        tapItem.action = tap != nil ? nil : #selector(grantAccess)
        forwardItem.title = "In WoW: send \(Settings.combo.displayName) instead"
        forwardItem.state = Settings.forward ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func toggleForward() {
        Settings.forward.toggle()
        refresh()
    }

    @objc private func changeCombo() {
        NSApp.activate(ignoringOtherApps: true)
        let recorder = KeyRecorder(combo: Settings.combo)
        let alert = NSAlert()
        alert.messageText = "Key to send to WoW"
        alert.informativeText = "Click the box and press the combination WoW should receive when you hit ⌘⇧Q. "
            + "Then bind that combination in WoW's Key Bindings."
        alert.accessoryView = recorder
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Reset to \(Settings.defaultCombo.displayName)")
        // Let Return/Esc be recordable instead of pressing buttons.
        alert.buttons.forEach { $0.keyEquivalent = "" }
        alert.window.initialFirstResponder = recorder

        switch alert.runModal() {
        case .alertFirstButtonReturn: Settings.combo = recorder.combo
        case .alertThirdButtonReturn: Settings.combo = Settings.defaultCombo
        default: break
        }
        refresh()
    }

    @objc private func grantAccess() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts) {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let a = NSAlert()
            a.messageText = "Couldn't change Launch at Login"
            a.informativeText = "\(error.localizedDescription)\n\nYou can add QGuard manually in System Settings › General › Login Items."
            a.runModal()
        }
        refresh()
    }
}

// MARK: - Key recorder

/// A box that shows a key combo and replaces it with the next one pressed while focused.
final class KeyRecorder: NSView {
    private(set) var combo: KeyCombo { didSet { label.stringValue = combo.displayName } }
    private let label = NSTextField(labelWithString: "")

    init(combo: KeyCombo) {
        self.combo = combo
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 48))
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        label.font = .systemFont(ofSize: 20, weight: .medium)
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 10, width: 260, height: 28)
        addSubview(label)
        label.stringValue = combo.displayName
        updateBorder()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { defer { updateBorder() }; return true }
    override func resignFirstResponder() -> Bool { defer { updateBorder() }; return true }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }

    private func updateBorder() {
        layer?.borderColor = (window?.firstResponder === self ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        layer?.borderWidth = window?.firstResponder === self ? 2 : 1
    }

    override func keyDown(with event: NSEvent) { record(event) }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, event.type == .keyDown else { return false }
        record(event)
        return true
    }

    private func record(_ event: NSEvent) {
        guard let cg = event.cgEvent else { return }
        let c = KeyCombo(keyCode: CGKeyCode(event.keyCode), flags: cg.flags)
        if !c.isLogoutCombo { combo = c }
    }
}

// MARK: - Entry

private func tapCallback(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent,
                         _ refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    let me = Unmanaged<App>.fromOpaque(refcon!).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let t = me.tap { CGEvent.tapEnable(tap: t, enable: true) }
        return .passUnretained(event)
    }
    return me.filter(type, event)
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
