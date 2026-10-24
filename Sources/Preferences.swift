import AppKit
import Carbon
import Combine
import ServiceManagement

@MainActor
final class Preferences: ObservableObject {
    private let defaults: UserDefaults
    @Published var pinned: Bool { didSet { defaults.set(pinned, forKey: "pinned") } }
    @Published var collapsed: Bool { didSet { defaults.set(collapsed, forKey: "collapsed") } }
    @Published var shortcutKey: UInt32 { didSet { defaults.set(Int(shortcutKey), forKey: "shortcutKey") } }
    @Published var shortcutModifiers: UInt32 { didSet { defaults.set(Int(shortcutModifiers), forKey: "shortcutModifiers") } }
    @Published var shortcutError: String?
    @Published var loginError: String?
    @Published var loginEnabled = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        pinned = defaults.object(forKey: "pinned") as? Bool ?? true
        collapsed = defaults.bool(forKey: "collapsed")
        shortcutKey = UInt32(defaults.object(forKey: "shortcutKey") as? Int ?? kVK_ANSI_T)
        shortcutModifiers = UInt32(defaults.object(forKey: "shortcutModifiers") as? Int ?? (controlKey | optionKey))
        refreshLogin()
    }

    func refreshLogin() { loginEnabled = SMAppService.mainApp.status == .enabled }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            refreshLogin()
            loginError = SMAppService.mainApp.status == .requiresApproval ? "Allow Floating Glass To-Do in System Settings → General → Login Items." : nil
        } catch { refreshLogin(); loginError = error.localizedDescription }
    }

    var shortcutLabel: String {
        let keys: [UInt32: String] = [0:"A",11:"B",8:"C",2:"D",14:"E",3:"F",5:"G",4:"H",34:"I",38:"J",40:"K",37:"L",46:"M",45:"N",31:"O",35:"P",12:"Q",15:"R",1:"S",17:"T",32:"U",9:"V",13:"W",7:"X",16:"Y",6:"Z",18:"1",19:"2",20:"3",21:"4",23:"5",22:"6",26:"7",28:"8",25:"9",29:"0",49:"Space"]
        return (shortcutModifiers & UInt32(controlKey) != 0 ? "⌃" : "") +
            (shortcutModifiers & UInt32(optionKey) != 0 ? "⌥" : "") +
            (shortcutModifiers & UInt32(shiftKey) != 0 ? "⇧" : "") +
            (shortcutModifiers & UInt32(cmdKey) != 0 ? "⌘" : "") + (keys[shortcutKey] ?? "Key \(shortcutKey)")
    }
}

@MainActor
final class GlobalShortcut {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onPress: (() -> Void)?

    init() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let shortcut = Unmanaged<GlobalShortcut>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { shortcut.onPress?() }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func register(key: UInt32, modifiers: UInt32) -> Bool {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        let identifier = EventHotKeyID(signature: 0x46475444, id: 1)
        return RegisterEventHotKey(key, modifiers, identifier, GetApplicationEventTarget(), 0, &hotKey) == noErr
    }
}
