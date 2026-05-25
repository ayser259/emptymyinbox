//
//  MacCatchUpKeyboardMonitor.swift
//  emptymyinboxMacApp
//

import AppKit
import Combine
import EmptyMyInboxShared

/// Holds fresh catch-up shortcut handlers; avoids stale `self` capture from SwiftUI struct monitors.
@MainActor
final class MacCatchUpKeyboardMonitor: ObservableObject {
    private var monitor: Any?

    var isReplyComposerOpen = false
    var isButtonsDisabled = true
    var hasMoreEmails = false
    var isAnimating = false
    var hasUnsubscribe = false
    var isReplyAllMeaningful = false

    var onReply: () -> Void = {}
    var onReplyAll: () -> Void = {}
    var onKeepUnread: () -> Void = {}
    var onStar: () -> Void = {}
    var onMarkAsRead: () -> Void = {}
    var onUnsubscribe: () -> Void = {}
    var onScrollUp: () -> Void = {}
    var onScrollDown: () -> Void = {}

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

    /// Returns `true` when the event was handled (consumed).
    private func handle(_ snapshot: MacKeyEventSnapshot) -> Bool {
        guard hasMoreEmails, !isAnimating else { return false }

        // Let the reply composer handle its own shortcuts (e.g. ⌥Q).
        if isReplyComposerOpen {
            return false
        }

        if MacKeyboardShortcutHelper.isCommandShift(snapshot),
           MacKeyboardShortcutHelper.character(snapshot) == "u",
           hasUnsubscribe,
           !isButtonsDisabled {
            onUnsubscribe()
            return true
        }

        if MacKeyboardShortcutHelper.hasNoCommandOptionControl(snapshot) {
            let ch = MacKeyboardShortcutHelper.character(snapshot) ?? ""

            if MacKeyboardShortcutHelper.isShiftOnly(snapshot), ch == "r",
               isReplyAllMeaningful, !isButtonsDisabled {
                onReplyAll()
                return true
            }

            if !snapshot.hasShift, ch == "r", !isButtonsDisabled {
                onReply()
                return true
            }

            if ch == "f", !isButtonsDisabled {
                onKeepUnread()
                return true
            }
            if ch == "s", !isButtonsDisabled {
                onStar()
                return true
            }
            if ch == "j", !isButtonsDisabled {
                onMarkAsRead()
                return true
            }
        }

        switch snapshot.keyCode {
        case 125:
            onScrollDown()
            return true
        case 126:
            onScrollUp()
            return true
        default:
            return false
        }
    }
}
