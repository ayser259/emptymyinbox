//
//  MacReplyComposerKeyboardMonitor.swift
//  EmptyMyInboxShared
//

#if os(macOS)
import AppKit
import Combine

@MainActor
public final class MacReplyComposerKeyboardMonitor: ObservableObject {
    public init() {}
    private var monitor: Any?

    var onToggleQuickReply: () -> Void = {}
    var onSend: () -> Void = {}
    var onSaveDraft: () -> Void = {}
    var onGenerateQuickReply: () -> Void = {}
    var onUpdateQuickReply: () -> Void = {}
    var onInsertQuickReply: () -> Void = {}
    var onOutcomeMarkRead: () -> Void = {}
    var onOutcomeReviewLater: () -> Void = {}
    var onOutcomeStay: () -> Void = {}

    var canSend = false
    var canSaveDraft = false
    var canGenerateQuickReply = false
    var canUpdateQuickReply = false
    var canInsertQuickReply = false
    var isQuickReplyVisible = false
    var showCatchUpOutcomePrompt = false

    func installIfNeeded() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let snapshot = MacKeyEventSnapshot(event)
            let consumed = MainActor.assumeIsolated {
                self.handle(snapshot)
            }
            return consumed ? nil : event
        }
    }

    func remove() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    private func handle(_ snapshot: MacKeyEventSnapshot) -> Bool {
        if showCatchUpOutcomePrompt {
            return handleCatchUpOutcome(snapshot)
        }

        if isQuickReplyVisible, MacKeyboardShortcutHelper.isOptionOnly(snapshot) {
            switch MacKeyboardShortcutHelper.character(snapshot) {
            case "g":
                if canGenerateQuickReply {
                    onGenerateQuickReply()
                    return true
                }
            case "u":
                if canUpdateQuickReply {
                    onUpdateQuickReply()
                    return true
                }
            case "i":
                if canInsertQuickReply {
                    onInsertQuickReply()
                    return true
                }
            default:
                break
            }
        }

        if MacKeyboardShortcutHelper.isOptionOnly(snapshot),
           MacKeyboardShortcutHelper.character(snapshot) == "q" {
            onToggleQuickReply()
            return true
        }

        let flags = MacKeyboardShortcutHelper.deviceFlags(snapshot)

        if flags == .command, MacKeyboardShortcutHelper.character(snapshot) == "s", canSaveDraft {
            onSaveDraft()
            return true
        }

        if flags == .command,
           snapshot.keyCode == 36, // Return
           canSend {
            onSend()
            return true
        }

        return false
    }

    private func handleCatchUpOutcome(_ snapshot: MacKeyEventSnapshot) -> Bool {
        if snapshot.keyCode == 53 { // Escape
            onOutcomeStay()
            return true
        }

        if MacKeyboardShortcutHelper.hasNoCommandOptionControl(snapshot) {
            switch MacKeyboardShortcutHelper.character(snapshot) {
            case "j":
                onOutcomeMarkRead()
                return true
            case "f":
                onOutcomeReviewLater()
                return true
            default:
                break
            }
        }

        return false
    }
}
#endif
