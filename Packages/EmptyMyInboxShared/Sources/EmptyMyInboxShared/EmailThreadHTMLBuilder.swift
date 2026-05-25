//
//  EmailThreadHTMLBuilder.swift
//  EmptyMyInboxShared
//
//  Builds a single HTML document for multi-message thread reading in one WKWebView.
//

import Foundation

public enum EmailThreadHTMLBuilder {
    public static func buildDocument(
        messages: [EmailDetail],
        selectedId: Int,
        isDarkMode: Bool = false
    ) -> String {
        let accent = isDarkMode ? "#667eea" : "#d4a012"
        let sectionBackground = isDarkMode ? "#252525" : "#ffffff"
        let dividerBackground = isDarkMode ? "#171717" : "#f0f0f0"

        var sectionsHTML = ""
        for (index, message) in messages.enumerated() {
            if index > 0 {
                let dividerLabel = index == 1 ? "Earlier message" : "Older message"
                sectionsHTML += dividerHTML(title: dividerLabel, background: dividerBackground, accent: accent)
            }
            sectionsHTML += messageSectionHTML(
                message: message,
                isSelected: message.id == selectedId,
                sectionBackground: sectionBackground,
                accent: accent
            )
        }

        let bridgeScript = """
        document.addEventListener('click', function(e) {
            var t = e.target.closest('[data-target-id]');
            if (!t) return;
            e.preventDefault();
            var id = Number(t.getAttribute('data-target-id'));
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.thread) {
                window.webkit.messageHandlers.thread.postMessage({ type: 'target', id: id });
            }
        });
        """

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <style>
        \(EmailHTMLRenderer.getCommonStyles(isDarkMode: isDarkMode))
        \(threadLayoutStyles(accent: accent, sectionBackground: sectionBackground, dividerBackground: dividerBackground))
        </style>
        </head>
        <body>
        <div id="thread-container">
        \(sectionsHTML)
        </div>
        <script>\(bridgeScript)</script>
        </body>
        </html>
        """
    }

    // MARK: - Section assembly

    private static func messageSectionHTML(
        message: EmailDetail,
        isSelected: Bool,
        sectionBackground: String,
        accent: String
    ) -> String {
        let sender = escapeHTML(message.sender_name ?? message.sender)
        let date = escapeHTML(EmailListItemDisplay.relativeListDate(from: message.received_at))
        let subject = escapeHTML(message.subject.isEmpty ? "(No Subject)" : message.subject)
        let selectedClass = isSelected ? " thread-msg-selected" : ""
        let targetLabel = isSelected ? "Targeted" : "Target"
        let unreadBadge = message.is_read ? "" : "<span class=\"thread-unread-dot\"></span>"

        let rawHTML = messageBodyHTML(for: message)
        let scopedStyles = extractStyleBlocks(from: rawHTML)
        let bodyFragment = stripDocumentWrapper(rawHTML)

        return """
        <section class="thread-msg\(selectedClass)" id="msg-\(message.id)" data-msg-id="\(message.id)">
        \(scopedStyles)
        <header class="thread-msg-header">
            <div class="thread-msg-meta">
                <div class="thread-msg-sender">\(sender)\(unreadBadge)</div>
                <div class="thread-msg-date">\(date)</div>
                <div class="thread-msg-subject">\(subject)</div>
            </div>
            <button type="button" class="thread-target-btn" data-target-id="\(message.id)">\(targetLabel)</button>
        </header>
        <div class="thread-msg-body">
        \(bodyFragment)
        </div>
        </section>
        """
    }

    private static func dividerHTML(title: String, background: String, accent: String) -> String {
        let label = escapeHTML(title.uppercased())
        return """
        <div class="thread-divider" style="background:\(background);">
            <span class="thread-divider-line" style="background:\(accent);"></span>
            <span class="thread-divider-label" style="color:\(accent);">\(label)</span>
            <span class="thread-divider-line" style="background:\(accent);"></span>
        </div>
        """
    }

    private static func threadLayoutStyles(
        accent: String,
        sectionBackground: String,
        dividerBackground: String
    ) -> String {
        """
        #thread-container { width: 100%; }
        .thread-msg {
            background: \(sectionBackground);
            border-bottom: 1px solid rgba(128,128,128,0.2);
        }
        .thread-msg-selected .thread-msg-header {
            background: rgba(212, 160, 18, 0.12);
        }
        .thread-msg-header {
            display: flex;
            align-items: flex-start;
            justify-content: space-between;
            gap: 12px;
            padding: 14px 16px;
            border-bottom: 1px solid rgba(128,128,128,0.15);
        }
        .thread-msg-meta { flex: 1; min-width: 0; }
        .thread-msg-sender {
            font-size: 15px;
            font-weight: 600;
            line-height: 1.3;
        }
        .thread-msg-date {
            font-size: 12px;
            opacity: 0.7;
            margin-top: 2px;
        }
        .thread-msg-subject {
            font-size: 13px;
            margin-top: 4px;
            opacity: 0.85;
            word-wrap: break-word;
        }
        .thread-unread-dot {
            display: inline-block;
            width: 8px;
            height: 8px;
            border-radius: 50%;
            background: \(accent);
            margin-left: 6px;
            vertical-align: middle;
        }
        .thread-target-btn {
            flex-shrink: 0;
            font-size: 11px;
            font-weight: 700;
            padding: 6px 10px;
            border: none;
            border-radius: 999px;
            cursor: pointer;
            background: \(accent);
            color: #000;
        }
        .thread-msg-selected .thread-target-btn {
            opacity: 0.95;
        }
        .thread-msg-body {
            padding: 0;
            overflow-x: hidden;
        }
        .thread-divider {
            display: flex;
            align-items: center;
            gap: 10px;
            padding: 14px 16px;
        }
        .thread-divider-line {
            flex: 1;
            height: 1px;
            opacity: 0.55;
        }
        .thread-divider-label {
            font-size: 10px;
            font-weight: 700;
            letter-spacing: 0.6px;
            white-space: nowrap;
        }
        """
    }

    // MARK: - Body extraction

    private static func messageBodyHTML(for message: EmailDetail) -> String {
        if let html = message.body_html, !html.isEmpty {
            return html
        }
        if !message.body_text.isEmpty {
            if looksLikeHTML(message.body_text) {
                return message.body_text
            }
            return "<pre style=\"white-space:pre-wrap;padding:16px;margin:0;\">\(escapeHTML(message.body_text))</pre>"
        }
        return "<p style=\"padding:16px;margin:0;opacity:0.7;font-style:italic;\">\(escapeHTML(message.snippet))</p>"
    }

    private static func stripDocumentWrapper(_ html: String) -> String {
        var content = html.trimmingCharacters(in: .whitespacesAndNewlines)
        if let extracted = EmailHTMLRenderer.extractBodyContent(from: content) {
            content = extracted
        }
        return content
    }

    private static func extractStyleBlocks(from html: String) -> String {
        var styles = ""
        var searchRange = html.startIndex..<html.endIndex
        while let styleStart = html.range(of: "<style", options: .caseInsensitive, range: searchRange),
              let styleEnd = html.range(of: "</style>", options: .caseInsensitive, range: styleStart.upperBound..<html.endIndex) {
            styles += String(html[styleStart.lowerBound..<styleEnd.upperBound])
            searchRange = styleEnd.upperBound..<html.endIndex
        }
        guard !styles.isEmpty else { return "" }
        return styles
    }

    private static func looksLikeHTML(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("<!doctype") || trimmed.hasPrefix("<html") { return true }
        if trimmed.hasPrefix("<") && (
            trimmed.contains("<head") ||
            trimmed.contains("<body") ||
            trimmed.contains("<div") ||
            trimmed.contains("<table") ||
            trimmed.contains("<style") ||
            trimmed.contains("<meta")
        ) {
            return true
        }
        return false
    }

    private static func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
