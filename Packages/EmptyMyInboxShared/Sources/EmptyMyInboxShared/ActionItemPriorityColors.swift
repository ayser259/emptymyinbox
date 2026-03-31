//
//  ActionItemPriorityColors.swift
//  EmptyMyInboxShared
//

import SwiftUI

/// Priority levels map to stored `VaultActionItemRecord.priority` 0...4 (`p0` highest urgency).
public enum ActionItemPriorityColors {
    public static let p0 = "#D52D00"
    public static let p1 = "#D95301"
    public static let p2 = "#FFA300"
    public static let p3 = "#FFBE63"
    public static let p4 = "#CBB927"

    public static func hex(forStoredPriority p: Int) -> String {
        switch p {
        case 0: return p0
        case 1: return p1
        case 2: return p2
        case 3: return p3
        case 4: return p4
        default: return p4
        }
    }

    public static func color(forStoredPriority p: Int) -> Color {
        Color(hex: hex(forStoredPriority: p))
    }
}
