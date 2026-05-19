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
    var canSend = false
    var canSaveDraft = false

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
}
#endif
