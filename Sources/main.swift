import Cocoa
import Darwin
import IOKit

func run(_ path: String, _ args: [String]) throws -> String {
    let p = Process(), pipe = Pipe()
    p.executableURL = URL(fileURLWithPath: path); p.arguments = args
    p.standardOutput = pipe; p.standardError = pipe
    try p.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    let text = String(decoding: data, as: UTF8.self)
    guard p.terminationStatus == 0 else { throw NSError(domain: "Coffee", code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey: text.isEmpty ? "Commande refusée par macOS." : text]) }
    return text
}
func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
func admin(_ command: String) throws {
    let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    _ = try run("/usr/bin/osascript", ["-e", "do shell script \"\(escaped)\" with administrator privileges"])
}
func flag(_ key: String) throws -> Bool {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
    guard service != 0 else { throw NSError(domain: "Coffee", code: 1, userInfo: [NSLocalizedDescriptionKey: "État d’alimentation illisible."]) }
    defer { IOObjectRelease(service) }
    guard let v = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(), CFGetTypeID(v) == CFBooleanGetTypeID(), let value = v as? Bool else { throw NSError(domain: "Coffee", code: 2, userInfo: [NSLocalizedDescriptionKey: "État \(key) illisible."]) }
    return value
}
func pmset(_ disabled: Bool) throws {
    _ = try run("/usr/bin/sudo", ["-k", "-n", "/usr/bin/pmset", "-a", "disablesleep", disabled ? "1" : "0"])
}
func durationSeconds(_ d: String, _ h: String, _ m: String) -> Int? {
    let parts = [d, h, m].map { $0.trimmingCharacters(in: .whitespaces) }
    guard parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),
          let days = Int(parts[0]), let hours = Int(parts[1]), let minutes = Int(parts[2]),
          (0...30).contains(days), (0...23).contains(hours), (0...59).contains(minutes) else { return nil }
    let result = days * 86400 + hours * 3600 + minutes * 60
    return (60...2592000).contains(result) ? result : nil
}
struct Permission {
    static var user: String { String(cString: getpwuid(getuid())!.pointee.pw_name) }
    static var path: String {
        // Preserve a previously granted rule through an external app preference.
        if let saved = UserDefaults.standard.string(forKey: "authorizationRulePath"),
           URL(fileURLWithPath: saved).deletingLastPathComponent().path == "/etc/sudoers.d",
           saved.hasSuffix("-local-\(getuid())") { return saved }
        return "/etc/sudoers.d/coffee-local-\(getuid())"
    }
    static var rule: String {
        "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1\n\(user) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0\n"
    }
    static func available() -> Bool {
        ["0", "1"].allSatisfy { (try? run("/usr/bin/sudo", ["-k", "-n", "-l", "/usr/bin/pmset", "-a", "disablesleep", $0])) != nil }
    }
    static func setupCommand() -> String {
        """
        set -eu
        /bin/mkdir -p /private/etc/sudoers.d
        temp=$(/usr/bin/mktemp /private/tmp/coffee-rule.XXXXXX)
        trap '/bin/rm -f "$temp"' EXIT
        /usr/bin/printf '%s' \(quote(rule)) > "$temp"
        /usr/sbin/visudo -cf "$temp" >/dev/null
        if [ -L \(quote(path)) ]; then exit 31; fi
        if [ -e \(quote(path)) ]; then
          /usr/bin/grep -v '^#' \(quote(path)) | /usr/bin/cmp -s - "$temp" || exit 32
        else
          /usr/bin/install -o root -g wheel -m 0440 "$temp" \(quote(path))
        fi
        """
    }
    static func removeCommand() -> String {
        """
        set -eu
        if [ -L \(quote(path)) ]; then exit 31; fi
        if [ -e \(quote(path)) ]; then
          temp=$(/usr/bin/mktemp /private/tmp/coffee-rule.XXXXXX)
          trap '/bin/rm -f "$temp"' EXIT
          /usr/bin/printf '%s' \(quote(rule)) > "$temp"
          /usr/bin/grep -v '^#' \(quote(path)) | /usr/bin/cmp -s - "$temp" || exit 32
          /bin/rm \(quote(path))
        fi
        """
    }
}

let args = CommandLine.arguments
if args.count == 2 && args[1] == "--diagnostics" {
    do { print("Veille désactivée : \(try flag("SleepDisabled"))\nCapot fermé : \(try flag("AppleClamshellState"))"); exit(0) }
    catch { fputs("\(error)\n", stderr); exit(1) }
}
if args.count == 2 && args[1] == "--self-test" {
    let cases: [(String,String,String,Int?)] = [("0","0","1",60),("1","2","3",93780),("30","0","0",2592000),("30","0","1",nil),("0","0","0",nil),("0","24","0",nil),("0","0","60",nil),("-1","0","0",nil),("abc","0","0",nil),("99999999999999999999999","0","0",nil)]
    for (d,h,m,expected) in cases { guard durationSeconds(d,h,m) == expected else { exit(1) } }
    guard Permission.rule.components(separatedBy: "NOPASSWD:").count == 3,
          !Permission.rule.contains("NOPASSWD: ALL"),
          Permission.setupCommand().contains("visudo -cf"),
          Permission.removeCommand().contains("cmp -s") else { exit(2) }
    print("Durées et portée des deux autorisations : vérifications réussies."); exit(0)
}
if args.count == 3 && args[1] == "--permission-script" {
    print(args[2] == "install" ? Permission.setupCommand() : Permission.removeCommand()); exit(0)
}
// Unprivileged watchdog. Only the two exact pmset commands run with sudo.
// The app never stores a password or grants permission to execute a user file as root.
if args.count == 5 && args[1] == "--guardian" {
    guard geteuid() == getuid(), let seconds = Int(args[2]), (60...2592000).contains(seconds),
          let parent = Int32(args[3]), parent > 1 else { exit(2) }
    let marker = args[4]
    guard marker.hasPrefix("/private/tmp/coffee-"), FileManager.default.fileExists(atPath: marker), (try? flag("SleepDisabled")) == false else { exit(3) }
    var restored = false
    do {
        defer {
            // Retry restoration if powerd is briefly unavailable. The marker is
            // the acknowledgement, removed only after the live state is restored.
            for _ in 0..<30 {
                do { try pmset(false); if try !flag("SleepDisabled") { restored = true; break } } catch {}
                Thread.sleep(forTimeInterval: 1)
            }
            if restored { try? FileManager.default.removeItem(atPath: marker) }
        }
        try pmset(true)
        guard try flag("SleepDisabled") else { throw NSError(domain: "Coffee", code: 4) }
        let end = ProcessInfo.processInfo.systemUptime + Double(seconds)
        while ProcessInfo.processInfo.systemUptime < end, kill(parent, 0) == 0,
              !FileManager.default.fileExists(atPath: marker + "/stop") {
            Thread.sleep(forTimeInterval: 0.5)
        }
    } catch { exit(5) }
    exit(restored ? 0 : 6)
}

final class DurationControl: NSControl {
    let maximum: Int
    let unit: String
    var onChange: (() -> Void)?
    private var dragY: CGFloat = 0
    private var scrollRemainder: CGFloat = 0
    private var typed = ""
    private var lastTyped: TimeInterval = 0
    private var clickPulse: CGFloat = 0
    private var pulseTimer: Timer?
    var value: Int {
        didSet { value = min(maximum, max(0, value)); needsDisplay = true; setAccessibilityValue(String(value)) }
    }
    override var stringValue: String { get { String(value) } set { value = Int(newValue) ?? 0 } }
    override var isEnabled: Bool { didSet { needsDisplay = true } }
    override var acceptsFirstResponder: Bool { isEnabled }
    override var intrinsicContentSize: NSSize { NSSize(width: 68, height: 62) }
    init(value: Int, maximum: Int, unit: String) {
        self.value = value; self.maximum = maximum; self.unit = unit
        super.init(frame: .zero)
        focusRingType = .none
        toolTip = nil
        setAccessibilityElement(true); setAccessibilityRole(.incrementor)
        setAccessibilityLabel(unit); setAccessibilityValue(String(value))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        let color = NSColor.labelColor.withAlphaComponent(isEnabled ? 1 : 0.4)
        let digits = NSAttributedString(string: String(format: "%02d", value), attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 32, weight: .regular), .foregroundColor: color])
        NSGraphicsContext.saveGraphicsState()
        let scale = 1 + 0.025 * clickPulse
        let transform = AffineTransform(translationByX: bounds.midX, byY: 38)
        var pulseTransform = transform
        pulseTransform.scale(scale)
        pulseTransform.translate(x: -bounds.midX, y: -38)
        (pulseTransform as NSAffineTransform).concat()
        digits.draw(at: NSPoint(x: (bounds.width - digits.size().width) / 2, y: 21))
        NSGraphicsContext.restoreGraphicsState()
        let caption = NSAttributedString(string: unit, attributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.labelColor.withAlphaComponent(0.9)])
        caption.draw(at: NSPoint(x: (bounds.width - caption.size().width) / 2, y: 3))
        if window?.firstResponder === self {
            NSColor.secondaryLabelColor.withAlphaComponent(0.35 + 0.2 * clickPulse).setFill()
            let width = 20 + 6 * clickPulse
            NSBezierPath(roundedRect: NSRect(x: bounds.midX - width / 2, y: 0, width: width, height: 1), xRadius: 0.5, yRadius: 0.5).fill()
        }
    }
    private func animateClick() {
        pulseTimer?.invalidate()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { clickPulse = 0; needsDisplay = true; return }
        let start = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let progress = min(1, (ProcessInfo.processInfo.systemUptime - start) / 0.24)
            self.clickPulse = CGFloat(sin(progress * .pi))
            self.needsDisplay = true
            if progress >= 1 { timer.invalidate(); self.pulseTimer = nil; self.clickPulse = 0 }
        }
        pulseTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    deinit { pulseTimer?.invalidate() }
    private func change(_ delta: Int) { guard isEnabled else { return }; value += delta; onChange?() }
    override func mouseDown(with event: NSEvent) { guard isEnabled else { return }; window?.makeFirstResponder(self); dragY = event.locationInWindow.y; typed = ""; animateClick(); needsDisplay = true }
    override func mouseDragged(with event: NSEvent) {
        let steps = Int((event.locationInWindow.y - dragY) / 8)
        if steps != 0 { dragY += CGFloat(steps) * 8; change(steps) }
    }
    override func scrollWheel(with event: NSEvent) {
        guard isEnabled, let window, window.firstResponder === self else { return }
        scrollRemainder += event.scrollingDeltaY / (event.hasPreciseScrollingDeltas ? 8 : 1)
        let steps = Int(scrollRemainder)
        if steps != 0 { scrollRemainder -= CGFloat(steps); change(steps) }
    }
    override func keyDown(with event: NSEvent) {
        guard isEnabled else { return }
        if event.keyCode == 126 { change(1); return }
        if event.keyCode == 125 { change(-1); return }
        if event.keyCode == 48 { window?.selectNextKeyView(self); return }
        if event.keyCode == 51 { typed = ""; value = 0; onChange?(); return }
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastTyped > 1.2 { typed = "" }
        if let text = event.characters, text.count == 1, text.allSatisfy({ $0.isASCII && $0.isNumber }) {
            typed += text
            if typed.count > 2 || (Int(typed) ?? 0) > maximum { typed = text }
            value = Int(typed) ?? 0; lastTyped = now; onChange?()
        } else { super.keyDown(with: event) }
    }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return true }
    override func accessibilityPerformIncrement() -> Bool { guard isEnabled else { return false }; change(1); return true }
    override func accessibilityPerformDecrement() -> Bool { guard isEnabled else { return false }; change(-1); return true }
}

final class StatusLabel: NSTextField {
    var onChange: (() -> Void)?
    override var stringValue: String {
        didSet { isHidden = stringValue.isEmpty; onChange?() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    var item: NSStatusItem!
    let popover = NSPopover()
    let optionsMenu = NSMenu()
    let days = DurationControl(value: 0, maximum: 30, unit: "jours")
    let hours = DurationControl(value: 1, maximum: 23, unit: "heures")
    let minutes = DurationControl(value: 0, maximum: 59, unit: "min")
    let status = StatusLabel(wrappingLabelWithString: "")
    var contentStack: NSStackView?
    var durationRow: NSStackView?
    let counter = NSTextField(labelWithString: "")
    let button = NSButton(title: "Activer", target: nil, action: nil)
    var guardian: Process?
    var marker: String?
    var end: TimeInterval?
    var busy = false, stopping = false, displayRequested = false
    var timer: Timer?
    var quitting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        icon(false)
        item.button?.target = self; item.button?.action = #selector(show)
        let vc = NSViewController()
        vc.view = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 180))
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .centerX; stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false; vc.view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor, constant: -24), stack.topAnchor.constraint(equalTo: vc.view.topAnchor, constant: 22)])
        contentStack = stack
        counter.font = .monospacedDigitSystemFont(ofSize: 22, weight: .medium); counter.alignment = .center; counter.isHidden = true; stack.addArrangedSubview(counter)
        let row = NSStackView(); row.spacing = 4; row.distribution = .fillEqually; durationRow = row
        for control in [days, hours, minutes] {
            control.onChange = { [weak self] in
                guard let self else { return }
                if self.days.value == 30 { self.hours.value = 0; self.minutes.value = 0 }
                self.status.stringValue = ""
            }
            row.addArrangedSubview(control)
        }
        stack.addArrangedSubview(row); row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        button.target = self; button.action = #selector(toggle); button.bezelStyle = .rounded; button.controlSize = .large; button.contentTintColor = .systemIndigo
        stack.addArrangedSubview(button); button.widthAnchor.constraint(equalToConstant: 160).isActive = true
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor; status.maximumNumberOfLines = 3; status.alignment = .center; status.isHidden = true
        status.onChange = { [weak self] in self?.resizePanel() }
        stack.addArrangedSubview(status); status.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        let options = NSButton(title: "", target: self, action: #selector(showOptions(_:)))
        options.isBordered = false
        let settingsImage = NSImage(size: NSSize(width: 30, height: 18), flipped: false) { _ in
            // Both symbols share the same vertical center (y = 9).
            NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)?.draw(in: NSRect(x: 1, y: 2, width: 14, height: 14))
            NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?.draw(in: NSRect(x: 20, y: 6, width: 8, height: 6))
            return true
        }
        settingsImage.isTemplate = true
        options.image = settingsImage
        options.imagePosition = .imageOnly
        options.font = .systemFont(ofSize: 11)
        options.contentTintColor = .secondaryLabelColor
        options.setAccessibilityLabel("Options de Coffee")
        stack.addArrangedSubview(options)
        let revoke = NSMenuItem(title: "Retirer l’autorisation…", action: #selector(removePermission), keyEquivalent: "")
        revoke.target = self
        optionsMenu.addItem(revoke)
        optionsMenu.addItem(.separator())
        let quit = NSMenuItem(title: "Quitter Coffee", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        optionsMenu.addItem(quit)
        popover.contentViewController = vc; popover.behavior = .transient; popover.contentSize = NSSize(width: 260, height: 180)
        resizePanel()
        timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }; RunLoop.main.add(timer!, forMode: .common)
    }
    @objc func showOptions(_ sender: NSButton) {
        guard let window = sender.window else { return }
        optionsMenu.update()
        let buttonRect = window.convertToScreen(sender.convert(sender.bounds, to: nil))
        let visible = window.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        let menuWidth = optionsMenu.size.width
        // Keep the native floating menu, but position the whole menu to one
        // side of the gear. A generous gap also accounts for its rounded border.
        let gap: CGFloat = 8
        let x: CGFloat
        if buttonRect.maxX + gap + menuWidth <= visible.maxX - 8 {
            x = buttonRect.maxX + gap
        } else {
            x = max(visible.minX + 8, buttonRect.minX - gap - menuWidth)
        }
        optionsMenu.popUp(positioning: nil, at: NSPoint(x: x, y: buttonRect.maxY), in: nil)
    }
    func icon(_ active: Bool) {
        guard let symbol = NSImage(systemSymbolName: active ? "cup.and.saucer.fill" : "cup.and.saucer", accessibilityDescription: nil) else { return }
        let image = NSImage(size: NSSize(width: 22, height: 22), flipped: false) { _ in
            let size = symbol.size
            symbol.draw(in: NSRect(x: (22 - size.width) / 2,
                                  y: (22 - size.height) / 2 - 1.5,
                                  width: size.width, height: size.height))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Coffee"
        item.button?.image = image
        item.button?.imagePosition = .imageOnly
        item.button?.toolTip = active ? "Coffee — session active" : "Coffee — choisir une durée"
    }
    @objc func show() {
        guard let anchor = item.button else { return }
        if popover.isShown { popover.performClose(nil) } else { resizePanel(); NSApp.activate(ignoringOtherApps:true); popover.show(relativeTo:anchor.bounds,of:anchor,preferredEdge:.minY) }
    }
    func resizePanel() {
        guard let stack = contentStack else { return }
        stack.layoutSubtreeIfNeeded()
        popover.contentSize = NSSize(width: 260, height: max(150, stack.fittingSize.height + 44))
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(removePermission) { return !busy && marker == nil }
        if menuItem.action == #selector(quit) { return !busy }
        return true
    }
    func controls(_ enabled:Bool) { durationRow?.isHidden = end != nil; resizePanel(); button.isEnabled = enabled; [days,hours,minutes].forEach { $0.isEnabled = enabled && marker == nil } }
    func alert(_ text:String) { NSApp.activate(ignoringOtherApps:true); let a = NSAlert(); a.messageText = "Coffee"; a.informativeText = text; a.runModal() }
    @objc func toggle() {
        guard !busy, !stopping else { return }
        if marker != nil { stop(); return }
        guard let seconds = durationSeconds(days.stringValue,hours.stringValue,minutes.stringValue) else { status.stringValue = "Durée : 1 minute à 30 jours. Heures : 0–23 ; minutes : 0–59."; return }
        guard (try? flag("SleepDisabled")) == false else { alert("La veille est déjà désactivée ou son état est illisible. Termine l’autre session avant de réessayer."); return }
        busy = true; controls(false); status.stringValue = "Vérification de l’autorisation…"
        DispatchQueue.global().async {
            let ready = Permission.available()
            DispatchQueue.main.async {
                if ready { self.start(seconds); return }
                let a = NSAlert(); a.messageText = "Configurer une seule fois"
                a.informativeText = "macOS va demander ton mot de passe pour autoriser exactement deux commandes : activer et rétablir la veille. Les prochaines sessions ne demanderont plus ce mot de passe. Tout programme lancé sous ton compte pourra utiliser ces deux commandes. Tu peux retirer cette autorisation dans Coffee."
                a.addButton(withTitle:"Configurer et démarrer"); a.addButton(withTitle:"Annuler")
                guard a.runModal() == .alertFirstButtonReturn else { self.busy = false; self.controls(true); self.status.stringValue = "Configuration annulée."; return }
                self.status.stringValue = "Configuration initiale avec macOS…"
                DispatchQueue.global().async {
                    let result = Result { try admin(Permission.setupCommand()); guard Permission.available() else { throw NSError(domain:"Coffee",code:8,userInfo:[NSLocalizedDescriptionKey:"Autorisation non confirmée."]) } }
                    DispatchQueue.main.async {
                        switch result {
                        case .success: self.start(seconds)
                        case .failure(let error): self.busy = false; self.controls(true); self.alert(error.localizedDescription)
                        }
                    }
                }
            }
        }
    }
    func start(_ seconds:Int) {
        do {
            let path = "/private/tmp/coffee-" + UUID().uuidString
            try FileManager.default.createDirectory(atPath:path,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
            marker = path
            let p = Process(); p.executableURL = Bundle.main.executableURL; p.arguments = ["--guardian",String(seconds),String(getpid()),path]
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            try p.run(); guardian = p
            status.stringValue = "Activation…"
            DispatchQueue.main.asyncAfter(deadline:.now()+1) {
                self.busy = false
                if p.isRunning, (try? flag("SleepDisabled")) == true {
                    self.end = ProcessInfo.processInfo.systemUptime + Double(seconds); self.displayRequested = false; self.button.title = "Arrêter"; self.counter.isHidden = false; self.controls(true); self.refresh()
                } else {
                    self.stop(); self.alert("La veille n’a pas pu être désactivée. Si le problème persiste, retire puis reconfigure l’autorisation.")
                }
            }
        } catch { busy = false; stop(); alert(error.localizedDescription) }
    }
    func stop() {
        guard let marker else { busy = false; stopping = false; controls(true); return }
        do { try Data().write(to:URL(fileURLWithPath:marker+"/stop")) }
        catch { alert("Impossible de signaler l’arrêt. Le minuteur reste responsable du rétablissement : \(error.localizedDescription)"); return }
        stopping = true; end = nil; controls(false); status.stringValue = "Rétablissement de la veille…"
    }
    func refresh() {
        guard !busy, let marker else { return }
        if stopping {
            if guardian?.isRunning != true, (try? flag("SleepDisabled")) == false {
                try? FileManager.default.removeItem(atPath:marker); self.marker = nil; guardian = nil; stopping = false; displayRequested = false
                counter.stringValue = ""; counter.isHidden = true; button.title = "Activer"; status.stringValue = ""; icon(false); controls(true)
                if quitting { NSApp.reply(toApplicationShouldTerminate:true) }
            } else if guardian?.isRunning != true {
                status.stringValue = "Rétablissement non confirmé. Secours : sudo pmset -a disablesleep 0"
                if quitting { quitting = false; NSApp.reply(toApplicationShouldTerminate:false) }
            }
            return
        }
        guard let end else { return }
        let remaining = max(0,Int(ceil(end-ProcessInfo.processInfo.systemUptime)))
        guard remaining > 0, guardian?.isRunning == true, (try? flag("SleepDisabled")) == true else { stop(); return }
        counter.stringValue = (remaining >= 86400 ? "\(remaining/86400) j · " : "") + String(format:"%02d:%02d:%02d",remaining%86400/3600,remaining%3600/60,remaining%60)
        counter.textColor = .systemIndigo; icon(true)
        do {
            let closed = try flag("AppleClamshellState")
            if !closed { displayRequested = false }
            else if !displayRequested { _ = try run("/usr/bin/pmset",["displaysleepnow"]); displayRequested = true }
            status.stringValue = ""
        } catch { status.stringValue = "Capot / écran non confirmé : \(error.localizedDescription)" }
    }
    @objc func removePermission() {
        guard !busy, marker == nil else { return }
        let a = NSAlert(); a.messageText = "Retirer l’autorisation permanente ?"; a.informativeText = "macOS peut demander ton mot de passe pour supprimer la règle. Une prochaine activation nécessitera à nouveau la configuration initiale."; a.addButton(withTitle:"Retirer"); a.addButton(withTitle:"Annuler")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        busy = true; controls(false)
        DispatchQueue.global().async {
            let result = Result { try admin(Permission.removeCommand()) }
            DispatchQueue.main.async {
                self.busy = false; self.controls(true)
                switch result { case .success: self.status.stringValue = "Autorisation retirée."; case .failure(let e): self.alert(e.localizedDescription) }
            }
        }
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender:NSApplication) -> NSApplication.TerminateReply {
        if busy { return .terminateCancel }
        if marker != nil { quitting = true; stop(); return .terminateLater }
        return .terminateNow
    }
}
let app = NSApplication.shared
let delegate = AppDelegate(); app.delegate = delegate; app.setActivationPolicy(.accessory); app.run()
