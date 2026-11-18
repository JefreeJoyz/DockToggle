import Cocoa
import ApplicationServices

// DockToggle: клик по иконке активного приложения в Dock сворачивает его окна (как в Windows).

func log(_ m: String) {
    let line = "\(Date()) \(m)\n"
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DockToggle.log")
    if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
    else { try? line.write(to: url, atomically: true, encoding: .utf8) }
}

final class DockToggle {
    private var tap: CFMachPort?
    private var swallowNextUp = false
    private let dockPID: pid_t? = NSRunningApplication
        .runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier

    func start() -> Bool {
        let mask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let me = Unmanaged<DockToggle>.fromOpaque(refcon!).takeUnretainedValue()
            return me.handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(mask), callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        self.tap = tap
        observeActivations()
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        case .leftMouseDown:
            // Модификаторы (⌘-клик = показать в Finder и т.п.) не трогаем.
            let blocking: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
            if event.flags.intersection(blocking).isEmpty,
               let app = frontmostAppUnderDockClick(at: event.location),
               minimizeWindows(of: app) {
                swallowNextUp = true
                return nil
            }
            return Unmanaged.passUnretained(event)
        case .leftMouseUp:
            if swallowNextUp {
                swallowNextUp = false
                return nil
            }
            return Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// Если клик пришёлся на иконку приложения в Dock и это приложение сейчас активно — вернуть его.
    private func frontmostAppUnderDockClick(at point: CGPoint) -> NSRunningApplication? {
        guard let front = NSWorkspace.shared.frontmostApplication else { return nil }
        var el: AXUIElement?
        let system = AXUIElementCreateSystemWide()
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &el) == .success,
              let el else { return nil }

        var pid: pid_t = 0
        AXUIElementGetPid(el, &pid)
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role)
        var sr: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXSubroleAttribute as CFString, &sr)
        if pid == dockPID { log("dock click role=\(role as? String ?? "-") subrole=\(sr as? String ?? "-") front=\(front.bundleIdentifier ?? "-")") }
        guard pid == dockPID else { return nil }

        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXSubroleAttribute as CFString, &subrole)
        guard (subrole as? String) == "AXApplicationDockItem" else { return nil }

        var urlRef: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXURLAttribute as CFString, &urlRef)
        guard let url = urlRef as? URL, let bundleID = Bundle(url: url)?.bundleIdentifier,
              bundleID == front.bundleIdentifier else { return nil }
        return front
    }

    /// Приложения, окна которых свернули мы. Нужно для Stage Manager: там свёрнутое окно
    /// не помечается как minimized, а приложение остаётся активным, поэтому состояние помним сами.
    private var minimizedByUs = Set<pid_t>()
    private var activationObserver: NSObjectProtocol?

    private func observeActivations() {
        guard activationObserver == nil else { return }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            // Если активировалось другое приложение, наша «память» о свёрнутых окнах устарела.
            let active = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            self?.minimizedByUs = self?.minimizedByUs.filter { $0 == active } ?? []
        }
    }

    /// Сворачивает окна активного приложения, а если мы его уже свернули (или окна
    /// помечены свёрнутыми) — разворачивает. true — если клик обработан.
    private func minimizeWindows(of app: NSRunningApplication) -> Bool {
        let pid = app.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &ref) == .success,
              let windows = ref as? [AXUIElement], !windows.isEmpty else { return false }

        var visible: [AXUIElement] = []
        var flaggedMinimized: [AXUIElement] = []
        for w in windows {
            var min: CFTypeRef?
            AXUIElementCopyAttributeValue(w, kAXMinimizedAttribute as CFString, &min)
            if (min as? Bool) == true { flaggedMinimized.append(w) } else { visible.append(w) }
        }
        log("windows=\(windows.count) visible=\(visible.count) minimized=\(flaggedMinimized.count) byUs=\(minimizedByUs.contains(pid))")

        if minimizedByUs.contains(pid) || visible.isEmpty {
            minimizedByUs.remove(pid)
            return restore(windows, of: app)
        }

        var did = false
        for w in visible {
            let r = AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
            var back: CFTypeRef?
            AXUIElementCopyAttributeValue(w, kAXMinimizedAttribute as CFString, &back)
            log("minimize result=\(r.rawValue) readback=\(String(describing: back))")
            if r == .success { did = true }
        }
        if did { minimizedByUs.insert(pid) }
        return did
    }

    private func restore(_ windows: [AXUIElement], of app: NSRunningApplication) -> Bool {
        var did = false
        for w in windows {
            let r = AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            let raise = AXUIElementPerformAction(w, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(w, kAXMainAttribute as CFString, kCFBooleanTrue)
            log("restore result=\(r.rawValue) raise=\(raise.rawValue)")
            if r == .success || raise == .success { did = true }
        }
        app.activate(options: [.activateIgnoringOtherApps])
        return did
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let toggle = DockToggle()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ n: Notification) {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(opts)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "DockToggle")
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit DockToggle", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem?.menu = menu

        log("trusted=\(trusted)")
        if !trusted || !toggle.start() {
            // Ждём, пока выдадут доступ, и пробуем снова.
            Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
                if AXIsProcessTrusted(), self?.toggle.start() == true { t.invalidate() }
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
