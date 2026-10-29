import Cocoa
import ApplicationServices

// Protokoll neben der App: ~/Downloads/DeskTOP/DeskTOP.log
let logURL = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("DeskTOP.log")
func dlog(_ msg: String) {
    NSLog("DeskTOP: %@", msg)
    let line = "\(Date()) \(msg)\n"
    guard let data = line.data(using: .utf8) else { return }
    if let h = try? FileHandle(forWritingTo: logURL) {
        h.seekToEndOfFile(); h.write(data); try? h.close()
    } else {
        try? data.write(to: logURL)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var pendingDockDisplay: CGDirectDisplayID?   // Bildschirm, auf den das Dock soll (nach dem Loslassen)
    var dockMoveRunning = false

    // Haben WIR "Dock automatisch ausblenden" ausgeschaltet? (bleibt auch nach Absturz gespeichert)
    var autohideTurnedOffByUs: Bool {
        get { UserDefaults.standard.bool(forKey: "dockShownByUs") }
        set { UserDefaults.standard.set(newValue, forKey: "dockShownByUs") }
    }

    // MARK: - AppleScript

    @discardableResult
    func runAppleScript(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error = error {
            // -1743 = keine Erlaubnis -> Systemeinstellungen > Datenschutz & Sicherheit > Automation
            dlog("AppleScript-Fehler: \(error)")
        }
        return result
    }

    // MARK: - Start / Ende

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        dlog("---- Start ----")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: "DeskTOP")
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "DeskTOP beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(options)
        dlog("Bedienungshilfen erlaubt: \(trusted)")

        let spansDisplays = UserDefaults(suiteName: "com.apple.spaces")?.bool(forKey: "spans-displays") ?? false
        dlog("'Monitore verwenden verschiedene Spaces' an: \(!spansDisplays)  (muss an sein, damit das Dock wandern kann)")

        // Dock dauerhaft sichtbar machen, falls automatisches Ausblenden an ist
        let autohide = runAppleScript("tell application \"System Events\" to get autohide of dock preferences")?.booleanValue ?? false
        dlog("Dock automatisch ausblenden: \(autohide)")
        if autohide {
            runAppleScript("tell application \"System Events\" to set autohide of dock preferences to false")
            autohideTurnedOffByUs = true
        }

        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { _ in
            self.handleMouseDown()
        }
        // Dock erst NACH dem Loslassen verschieben, sonst würde aus dem Klick ein Ziehen
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in
            guard let target = self.pendingDockDisplay else { return }
            self.pendingDockDisplay = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.moveDockIfNeeded(to: target)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if autohideTurnedOffByUs {
            runAppleScript("tell application \"System Events\" to set autohide of dock preferences to true")
            autohideTurnedOffByUs = false
        }
        dlog("---- Ende ----")
    }

    // MARK: - Klick

    func handleMouseDown() {
        guard let cgEvent = CGEvent(source: nil) else { return }
        let cgMouseLocation = cgEvent.location

        let windowListInfo = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as NSArray? as? [[String: AnyObject]] ?? []

        for window in windowListInfo {
            if let layer = window[kCGWindowLayer as String] as? Int, layer >= 0,
               let boundsDict = window[kCGWindowBounds as String] as? [String: AnyObject],
               let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
               bounds.contains(cgMouseLocation) {
                let owner = window[kCGWindowOwnerName as String] as? String ?? "Unbekannt"
                if owner == "Dock" && (bounds.width > 800 || bounds.height > 800) { continue }
                if owner == "WindowManager" && (bounds.width > 800 || bounds.height > 800) { continue }
                return   // Klick auf ein Fenster / Dock / Menüleiste -> nichts tun
            }
        }

        // Klick auf den Schreibtisch
        guard let display = displayAt(cgMouseLocation) else { dlog("Kein Bildschirm unter der Maus"); return }
        dlog("Klick auf Schreibtisch, Bildschirm \(display)")
        moveIcons(to: display)
        pendingDockDisplay = display
    }

    func displayAt(_ p: CGPoint) -> CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetDisplaysWithPoint(p, 16, &ids, &count)
        return count > 0 ? ids[0] : nil
    }

    // MARK: - Dock

    /// Auf welchem Bildschirm ist das Dock gerade?
    func currentDockDisplay() -> CGDirectDisplayID? {
        let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as NSArray? as? [[String: AnyObject]] ?? []
        let dockLevel = Int(CGWindowLevelForKey(.dockWindow))
        for w in list {
            guard (w[kCGWindowOwnerName as String] as? String) == "Dock",
                  let layer = w[kCGWindowLayer as String] as? Int, layer == dockLevel,
                  let bd = w[kCGWindowBounds as String] as? [String: AnyObject],
                  let b = CGRect(dictionaryRepresentation: bd as CFDictionary),
                  b.width < 5000 else { continue }
            return displayAt(CGPoint(x: b.midX, y: b.midY))
        }
        return nil
    }

    func moveDockIfNeeded(to target: CGDirectDisplayID) {
        guard !dockMoveRunning else { return }
        let current = currentDockDisplay()
        dlog("Dock ist auf Bildschirm \(current.map { String($0) } ?? "unbekannt"), Ziel \(target)")
        if current == target { return }
        moveDock(to: target)
    }

    /// macOS holt das Dock auf einen Bildschirm, wenn die Maus dort an den Dock-Rand "drückt".
    /// Genau das simulieren wir kurz und setzen die Maus danach zurück.
    func moveDock(to display: CGDirectDisplayID) {
        dockMoveRunning = true
        let r = CGDisplayBounds(display)
        let original = CGEvent(source: nil)?.location ?? CGPoint(x: r.midX, y: r.midY)
        let orientation = UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") ?? "bottom"

        let edge: CGPoint
        var dx: Int64 = 0, dy: Int64 = 0
        switch orientation {
        case "left":  edge = CGPoint(x: r.minX, y: r.midY);     dx = -10
        case "right": edge = CGPoint(x: r.maxX - 1, y: r.midY); dx = 10
        default:      edge = CGPoint(x: r.midX, y: r.maxY - 1); dy = 10
        }

        dlog("Bedienungshilfen erlaubt: \(AXIsProcessTrusted())")
        let src = CGEventSource(stateID: .hidSystemState)
        // Start etwas vor dem Rand, dann wie eine echte Maus hinfahren und weiter "drücken"
        let start = CGPoint(x: edge.x - CGFloat(dx * 6), y: edge.y - CGFloat(dy * 6))
        CGWarpMouseCursorPosition(start)
        var step = 0
        Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { t in
            step += 1
            let f = min(CGFloat(step) / 8, 1)
            let pos = CGPoint(x: start.x + (edge.x - start.x) * f, y: start.y + (edge.y - start.y) * f)
            if let e = CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: pos, mouseButton: .left) {
                e.setIntegerValueField(.mouseEventDeltaX, value: dx)
                e.setIntegerValueField(.mouseEventDeltaY, value: dy)
                e.post(tap: .cghidEventTap)
            }
            if step >= 60 || self.currentDockDisplay() == display {   // max. ~1,2 s
                t.invalidate()
                CGWarpMouseCursorPosition(original)
                self.dockMoveRunning = false
                dlog("Dock verschoben: \(self.currentDockDisplay() == display) (nach \(step) Schritten)")
            }
        }
    }

    // MARK: - Ordner verschieben (wie bisher)

    func moveIcons(to display: CGDirectDisplayID) {
        let cgRect = CGDisplayBounds(display)
        let targetX = Int(cgRect.origin.x)
        let targetY = Int(cgRect.origin.y)
        let screenWidth = Int(cgRect.width)

        let script = """
        tell application "Finder"
            set deskItems to items of desktop
            if (count of deskItems) > 0 then
                set maxX to -999999
                set minY to 999999
                
                repeat with i in deskItems
                    try
                        set pos to desktop position of i
                        if item 1 of pos > maxX then set maxX to item 1 of pos
                        if item 2 of pos < minY then set minY to item 2 of pos
                    end try
                end repeat
                
                if (maxX > \(targetX)) and (maxX < (\(targetX) + \(screenWidth))) then
                    return "ALREADY_THERE"
                end if
                
                set deltaX to (\(targetX) + \(screenWidth) - 80) - maxX
                set deltaY to \(targetY) - minY + 50
                
                repeat with i in deskItems
                    try
                        set pos to desktop position of i
                        set newX to (item 1 of pos) + deltaX
                        set newY to (item 2 of pos) + deltaY
                        set desktop position of i to {newX, newY}
                    end try
                end repeat
                
                try
                    clean up window of desktop
                end try
            end if
        end tell
        """
        let result = runAppleScript(script)
        dlog("Ordner: \(result?.stringValue ?? "verschoben")")
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
