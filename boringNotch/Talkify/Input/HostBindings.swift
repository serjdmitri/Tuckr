import AppKit
import KeyboardShortcuts

/// Boring's two notch shortcuts as bindings, with the defaults Boring ships:
/// command-shift-I opens the notch, command-shift-H peeks at the media.
extension KeyBinding {
  static let boringOpenNotch = KeyBinding(
    keyCode: 34,
    modifierFlags: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue,
    isModifierKey: false, label: "⌘ ⇧ I", keyEquivalent: "i"
  )

  static let boringSneakPeek = KeyBinding(
    keyCode: 4,
    modifierFlags: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue,
    isModifierKey: false, label: "⌘ ⇧ H", keyEquivalent: "h"
  )
}

extension KeyBinding {
  /// This binding as a shortcut for the host's shortcut store, which speaks
  /// Carbon modifiers. Nil for a mouse button, which that store cannot hold.
  var hostShortcut: KeyboardShortcuts.Shortcut? {
    guard let keyCode else { return nil }
    let flags = CGEventFlags(rawValue: modifierFlags)
    var carbonModifiers = 0
    if flags.contains(.maskCommand) { carbonModifiers |= 256 }
    if flags.contains(.maskShift) { carbonModifiers |= 512 }
    if flags.contains(.maskAlternate) { carbonModifiers |= 2048 }
    if flags.contains(.maskControl) { carbonModifiers |= 4096 }
    return KeyboardShortcuts.Shortcut(carbonKeyCode: Int(keyCode), carbonModifiers: carbonModifiers)
  }
}
