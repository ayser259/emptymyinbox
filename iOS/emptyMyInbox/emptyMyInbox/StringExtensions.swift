//
//  StringExtensions.swift
//  emptyMyInbox
//
//  String utility extensions
//

import Foundation

extension String {
    /// Formats a string as a name: first letter of each word capitalized, rest lowercase
    var formattedAsName: String {
        return self
            .split(separator: " ")
            .map { word in
                guard let firstChar = word.first else { return String(word) }
                return String(firstChar).uppercased() + String(word.dropFirst()).lowercased()
            }
            .joined(separator: " ")
    }
}

