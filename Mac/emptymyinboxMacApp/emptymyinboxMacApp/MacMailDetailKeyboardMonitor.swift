//
//  MacMailDetailKeyboardMonitor.swift
//  emptymyinboxMacApp
//

import AppKit
import Combine
import EmptyMyInboxShared

/// Keyboard shortcuts while reading a message in the mailbox detail pane.
@MainActor
final class MacMailDetailKeyboardMonitor: ObservableObject {
    private var monitor: Any?

    var isReplyComposerOpen = false
    var isEnabled = false
    var isReplyAllMeaningful = false
    var hasUnsubscribe = false

    var onReply: () -> Void = {}
    var onReplyAll: () -> Void = {}
    var onKeepUnread: () -> Void = {}
    var onStar: () -> Void = {}
    var onMarkAsRead: () -> Void = {}
    var onUnsubscribe: () -> Void = {}

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
        guard isEnabled, !isReplyComposerOpen else { return false }

        if MacKeyboardShortcutHelper.isCommandShift(snapshot),
           MacKeyboardShortcutHelper.character(snapshot) == "u",
           hasUnsubscribe {
            onUnsubscribe()
            return true
        }

        guard MacKeyboardShortcutHelper.hasNoCommandOptionControl(snapshot) else { return false }
        let ch = MacKeyboardShortcutHelper.character(snapshot) ?? ""

        if MacKeyboardShortcutHelper.isShiftOnly(snapshot), ch == "r", isReplyAllMeaningful {
            onReplyAll()
            return true
        }

        if !snapshot.hasShift, ch == "r" {
            onReply()
            return true
        }

        if ch == "f" {
            onKeepUnread()
            return true
        }
        if ch == "s" {
            onStar()
            return true
        }
        if ch == "j" {
            onMarkAsRead()
            return true
        }

        return false
    }
}
