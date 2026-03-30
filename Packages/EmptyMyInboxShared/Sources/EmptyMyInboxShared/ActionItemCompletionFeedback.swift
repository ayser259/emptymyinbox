//
//  ActionItemCompletionFeedback.swift
//  EmptyMyInboxShared
//

import Foundation
#if canImport(AudioToolbox)
import AudioToolbox
#endif
#if canImport(UIKit)
import UIKit
#endif

public enum ActionItemCompletionFeedback {
    /// Haptics (iOS) + short system sound on both platforms.
    public static func playCompletion() {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
        #endif
        #if canImport(AudioToolbox)
        AudioServicesPlaySystemSound(1057)
        #endif
    }
}
