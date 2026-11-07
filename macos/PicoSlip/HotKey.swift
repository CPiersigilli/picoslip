import AppKit
import Carbon.HIToolbox

/// The global "new note" shortcut, Ctrl+Alt++ on Windows: here ⌃⌥ and the key
/// that types "+" on the current keyboard layout, plus the keypad "+".
/// RegisterEventHotKey needs no Accessibility permission.
final class HotKey {
    private let action: () -> Void
    private var references: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    init(action: @escaping () -> Void) { self.action = action }

    fileprivate func fire() { action() }

    func register() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), hotKeyPressed, 1, &spec, context, &handler)
        let modifiers = UInt32(controlKey | optionKey)
        for (index, code) in Set([Self.plusKeyCode(), UInt32(kVK_ANSI_KeypadPlus)]).enumerated() {
            var reference: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x5053_6C70), id: UInt32(index + 1))   // "PSlp"
            if RegisterEventHotKey(code, modifiers, id, GetApplicationEventTarget(), 0, &reference) == noErr, let reference {
                references.append(reference)
            }
        }
    }

    /// The key producing "+" without modifiers (Italian, Spanish…) or with Shift
    /// (US "="), like VK_OEM_PLUS on Windows.
    private static func plusKeyCode() -> UInt32 {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return UInt32(kVK_ANSI_Equal)
        }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return UInt32(kVK_ANSI_Equal) }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        for shift in [false, true] {
            for code in 0..<UInt16(128) {
                var dead: UInt32 = 0
                var length = 0
                var characters = [UniChar](repeating: 0, count: 4)
                let state = shift ? UInt32(shiftKey >> 8) & 0xff : 0
                let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), state, UInt32(LMGetKbdType()),
                                            OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, characters.count,
                                            &length, &characters)
                if status == noErr, length == 1, characters[0] == UniChar(UInt8(ascii: "+")) { return UInt32(code) }
            }
        }
        return UInt32(kVK_ANSI_Equal)
    }
}

/// Carbon delivers hot-key events on the main thread.
private nonisolated func hotKeyPressed(_ call: EventHandlerCallRef?, _ event: EventRef?, _ context: UnsafeMutableRawPointer?) -> OSStatus {
    guard let context else { return OSStatus(eventNotHandledErr) }
    let address = UInt(bitPattern: context)
    MainActor.assumeIsolated {
        guard let pointer = UnsafeRawPointer(bitPattern: address) else { return }
        Unmanaged<HotKey>.fromOpaque(pointer).takeUnretainedValue().fire()
    }
    return noErr
}
