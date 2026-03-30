//
//  ULID.swift
//  EmptyMyInboxShared
//
//  Lexicographically sortable 128-bit identifiers (48-bit ms timestamp + 80-bit random).
//

import Foundation
import Security

/// Generates ULID strings (Crockford base32, 26 characters).
public enum ULID {
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    public static func generate() -> String {
        let ms = UInt64(Date().timeIntervalSince1970 * 1_000)
        var random = [UInt8](repeating: 0, count: 10)
        let status = SecRandomCopyBytes(kSecRandomDefault, 10, &random)
        if status != errSecSuccess {
            for i in random.indices {
                random[i] = UInt8.random(in: 0 ... 255)
            }
        }
        return encodeTime(ms) + encodeRandom(random)
    }

    /// Time component: 48 bits → 10 Crockford base32 characters (LSB-first encoding per ULID spec).
    private static func encodeTime(_ ms: UInt64) -> String {
        var n = ms
        var s = ""
        for _ in 0 ..< 10 {
            let mod = n % 32
            s = String(alphabet[Int(mod)]) + s
            n = (n - mod) / 32
        }
        return s
    }

    /// Random component: 80 bits (10 bytes) → 16 Crockford base32 characters.
    private static func encodeRandom(_ bytes: [UInt8]) -> String {
        precondition(bytes.count == 10)
        var chars: [Character] = []
        chars.reserveCapacity(16)
        var bitBuffer = 0
        var bitBufferLength = 0
        for byte in bytes {
            bitBuffer = (bitBuffer << 8) | Int(byte)
            bitBufferLength += 8
            while bitBufferLength >= 5, chars.count < 16 {
                bitBufferLength -= 5
                let idx = (bitBuffer >> bitBufferLength) & 0x1F
                chars.append(alphabet[idx])
            }
        }
        if chars.count < 16, bitBufferLength > 0 {
            let idx = (bitBuffer << (5 - bitBufferLength)) & 0x1F
            chars.append(alphabet[idx])
        }
        return String(chars.prefix(16))
    }
}
