//
//  StableID.swift
//  emptyMyInbox
//
//  Deterministic IDs for accounts and Gmail messages.
//

import Foundation
import CryptoKit

public enum StableID {
    public static func accountId(email: String) -> Int {
        stablePositiveInt(for: "account:\(email.lowercased())")
    }
    
    public static func emailId(gmailId: String) -> Int {
        stablePositiveInt(for: "email:\(gmailId)")
    }
    
    private static func stablePositiveInt(for value: String) -> Int {
        let digest = SHA256.hash(data: Data(value.utf8))
        let prefix = digest.prefix(8)
        
        var number: UInt64 = 0
        for byte in prefix {
            number = (number << 8) | UInt64(byte)
        }
        
        let maxValue = UInt64(Int.max - 1)
        let bounded = (number % maxValue) + 1
        return Int(bounded)
    }
}
