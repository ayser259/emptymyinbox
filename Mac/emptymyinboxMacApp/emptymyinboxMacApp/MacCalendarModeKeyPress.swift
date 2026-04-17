import EmptyMyInboxShared
import SwiftUI

/// Maps E/D/W/M to calendar view modes. Uses `KeyPress.key` (physical key) when `characters` is empty — common on macOS for unmodified letters.
enum MacCalendarModeKeyPress {
    static func handle(
        _ press: KeyPress,
        calendarModesActive: Bool,
        setMode: (GoogleCalendarViewModel.ViewMode) -> Void
    ) -> KeyPress.Result {
        guard calendarModesActive else { return .ignored }
        guard press.modifiers.intersection([.command, .control, .option]).isEmpty else { return .ignored }

        let letter: String? = {
            let trimmed = press.characters.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count == 1 {
                return String(trimmed.lowercased().first!)
            }
            let k = press.key.character
            let s = String(k).lowercased()
            return s.count == 1 ? s : nil
        }()

        guard let letter else { return .ignored }
        switch letter {
        case "e": setMode(.events); return .handled
        case "d": setMode(.day); return .handled
        case "w": setMode(.week); return .handled
        case "m": setMode(.month); return .handled
        default: return .ignored
        }
    }
}
