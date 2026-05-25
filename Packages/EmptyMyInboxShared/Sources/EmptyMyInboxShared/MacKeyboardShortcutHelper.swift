//
//  MacKeyboardShortcutHelper.swift
//  EmptyMyInboxShared
//

#if os(macOS)
import AppKit

/// Sendable key facts extracted from `NSEvent` for use across Swift 6 isolation boundaries.
public struct MacKeyEventSnapshot: Sendable {
    public let keyCode: UInt16
    public let deviceFlagsRaw: UInt
    public let characterLowercased: String?
    public let hasShift: Bool

    public init(_ event: NSEvent) {
        keyCode = event.keyCode
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        deviceFlagsRaw = flags.rawValue
        characterLowercased = event.charactersIgnoringModifiers?.lowercased()
        hasShift = event.modifierFlags.contains(.shift)
    }

    public var deviceFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: deviceFlagsRaw)
    }
}

/// Helpers for matching key events in `NSEvent` local monitors (macOS).
public enum MacKeyboardShortcutHelper {

    public static func deviceFlags(_ event: NSEvent) -> NSEvent.ModifierFlags {
        event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    }

    public static func deviceFlags(_ snapshot: MacKeyEventSnapshot) -> NSEvent.ModifierFlags {
        snapshot.deviceFlags
    }

    /// No Command, Option, or Control (Shift allowed).
    public static func hasNoCommandOptionControl(_ event: NSEvent) -> Bool {
        hasNoCommandOptionControl(MacKeyEventSnapshot(event))
    }

    public static func hasNoCommandOptionControl(_ snapshot: MacKeyEventSnapshot) -> Bool {
        deviceFlags(snapshot).intersection([.command, .option, .control]).isEmpty
    }

    public static func isOptionOnly(_ event: NSEvent) -> Bool {
        isOptionOnly(MacKeyEventSnapshot(event))
    }

    public static func isOptionOnly(_ snapshot: MacKeyEventSnapshot) -> Bool {
        let flags = deviceFlags(snapshot)
        return flags.contains(.option)
            && flags.intersection([.command, .shift, .control]).isEmpty
    }

    public static func isShiftOnly(_ event: NSEvent) -> Bool {
        isShiftOnly(MacKeyEventSnapshot(event))
    }

    public static func isShiftOnly(_ snapshot: MacKeyEventSnapshot) -> Bool {
        let flags = deviceFlags(snapshot)
        return flags.contains(.shift)
            && flags.intersection([.command, .option, .control]).isEmpty
    }

    public static func isCommandShift(_ event: NSEvent) -> Bool {
        isCommandShift(MacKeyEventSnapshot(event))
    }

    public static func isCommandShift(_ snapshot: MacKeyEventSnapshot) -> Bool {
        let flags = deviceFlags(snapshot)
        return flags.contains(.command) && flags.contains(.shift)
            && flags.intersection([.option, .control]).isEmpty
    }

    public static func character(_ event: NSEvent) -> String? {
        event.charactersIgnoringModifiers?.lowercased()
    }

    public static func character(_ snapshot: MacKeyEventSnapshot) -> String? {
        snapshot.characterLowercased
    }
}
#endif
