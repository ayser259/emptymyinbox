//
//  EmailHTMLWebView.swift
//  EmptyMyInboxShared
//
//  Cross-platform WKWebView for rendering email HTML (iOS + macOS).
//

import SwiftUI
import WebKit
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Renders sanitized email HTML inside a `WKWebView` on both iOS and macOS.
public struct EmailHTMLWebView: View {
    public let htmlContent: String
    public let isDarkMode: Bool
    public var contentWidth: CGFloat?
    public var onLoadComplete: (() -> Void)?
    /// macOS only: each time this counter increments the web view scrolls by `scrollStepAmount` points.
    /// Positive = scroll down, negative = scroll up.
    public var scrollSignal: Int = 0
    public var scrollStepAmount: CGFloat = 0

    public init(
        htmlContent: String,
        isDarkMode: Bool,
        contentWidth: CGFloat? = nil,
        onLoadComplete: (() -> Void)? = nil,
        scrollSignal: Int = 0,
        scrollStepAmount: CGFloat = 0
    ) {
        self.htmlContent = htmlContent
        self.isDarkMode = isDarkMode
        self.contentWidth = contentWidth
        self.onLoadComplete = onLoadComplete
        self.scrollSignal = scrollSignal
        self.scrollStepAmount = scrollStepAmount
    }

    public var body: some View {
        #if os(iOS)
        EmailHTMLWebViewIOS(
            htmlContent: htmlContent,
            isDarkMode: isDarkMode,
            onLoadComplete: onLoadComplete
        )
        #elseif os(macOS)
        EmailHTMLWebViewMac(
            htmlContent: htmlContent,
            isDarkMode: isDarkMode,
            scrollSignal: scrollSignal,
            scrollStepAmount: scrollStepAmount,
            onLoadComplete: onLoadComplete
        )
        #else
        EmptyView()
        #endif
    }
}

// MARK: - Shared HTML pipeline

enum EmailHTMLRenderer {
    static func loadHTMLContent(into webView: WKWebView, isDarkMode: Bool, htmlContent: String) {
        var finalHtml = htmlContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if finalHtml.hasPrefix("&lt;") || finalHtml.hasPrefix("&#60;") {
            if let unescaped = unescapeHTML(finalHtml) {
                finalHtml = unescaped.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        let lowercased = finalHtml.lowercased()
        let isFullDocument = lowercased.hasPrefix("<!doctype") || lowercased.hasPrefix("<html")
        let htmlString: String
        if isFullDocument {
            htmlString = injectStylesIntoHTML(finalHtml, isDarkMode: isDarkMode)
        } else {
            htmlString = createWrappedHTML(finalHtml, isDarkMode: isDarkMode)
        }
        webView.loadHTMLString(htmlString, baseURL: Bundle.main.bundleURL)
    }

    private static func unescapeHTML(_ string: String) -> String? {
        guard let data = string.data(using: .utf8) else { return nil }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        if let attributedString = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
            return attributedString.string
        }
        return nil
    }

    private static func createWrappedHTML(_ content: String, isDarkMode: Bool) -> String {
        "<!DOCTYPE html>" +
            "<html>" +
            "<head>" +
            "<meta charset=\"UTF-8\">" +
            "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no\">" +
            "<style>" +
            getCommonStyles(isDarkMode: isDarkMode) +
            "</style>" +
            "</head>" +
            "<body>" +
            "<div id=\"email-container\">" +
            content +
            "</div>" +
            "</body>" +
            "</html>"
    }

    private static func injectStylesIntoHTML(_ html: String, isDarkMode: Bool) -> String {
        var modifiedHtml = html
        let styles = "<style>" + getCommonStyles(isDarkMode: isDarkMode) + "</style>"
        let viewport = "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no\">"
        if let headEndRange = modifiedHtml.range(of: "</head>", options: .caseInsensitive) {
            modifiedHtml.insert(contentsOf: styles, at: headEndRange.lowerBound)
            if !modifiedHtml.contains("viewport") {
                if let headStartRange = modifiedHtml.range(of: "<head", options: .caseInsensitive),
                   let closingBracket = modifiedHtml[headStartRange.upperBound...].firstIndex(of: ">") {
                    modifiedHtml.insert(contentsOf: viewport, at: modifiedHtml.index(after: closingBracket))
                } else {
                    modifiedHtml.insert(contentsOf: viewport, at: headEndRange.lowerBound)
                }
            }
            return modifiedHtml
        }
        if let bodyStartRange = modifiedHtml.range(of: "<body", options: .caseInsensitive) {
            if let closingBracket = modifiedHtml[bodyStartRange.upperBound...].firstIndex(of: ">") {
                let insertPoint = modifiedHtml.index(after: closingBracket)
                modifiedHtml.insert(contentsOf: viewport + styles, at: insertPoint)
                return modifiedHtml
            }
        }
        return createWrappedHTML(extractBodyContent(from: html) ?? html, isDarkMode: isDarkMode)
    }

    private static func extractBodyContent(from html: String) -> String? {
        if let bodyStartRange = html.range(of: "<body", options: .caseInsensitive) {
            var searchStart = bodyStartRange.upperBound
            while searchStart < html.endIndex {
                if html[searchStart] == ">" {
                    let bodyContentStart = html.index(after: searchStart)
                    if let bodyEndRange = html[bodyContentStart...].range(of: "</body>", options: .caseInsensitive) {
                        let bodyContent = String(html[bodyContentStart..<bodyEndRange.lowerBound])
                        let cleaned = bodyContent.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !cleaned.isEmpty { return cleaned }
                    }
                    break
                }
                searchStart = html.index(after: searchStart)
            }
        }
        return nil
    }

    private static func getCommonStyles(isDarkMode: Bool) -> String {
        // Use box-sizing universally but avoid blanket max-width/overflow-x overrides that clip
        // embedded images and break table-based email layouts.
        "*, *::before, *::after { box-sizing: border-box; }" +
            "html { overflow-x: hidden; }" +
            "html, body { width: 100%; margin: 0 !important; padding: 0 !important; }" +
            "body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; " +
            "font-size: 15px; line-height: 1.6; " +
            "color: \(isDarkMode ? "#ffffff" : "#000000"); background-color: \(isDarkMode ? "#252525" : "#ffffff"); " +
            "-webkit-text-size-adjust: 100%; word-wrap: break-word; overflow-wrap: break-word; overflow-x: hidden; }" +
            "#email-container { width: 100%; margin: 0 auto; padding: 0; overflow-x: hidden; }" +
            // Images: constrain to container width, preserve aspect ratio, never clip
            "img { max-width: 100% !important; height: auto !important; display: inline-block; }" +
            // Tables: fit container without forcing fixed-layout (fixed breaks column widths in marketing emails)
            "table { max-width: 100% !important; border-collapse: collapse; word-wrap: break-word; overflow-wrap: break-word; }" +
            "td, th { word-wrap: break-word; overflow-wrap: break-word; }" +
            // Block-level elements: prevent horizontal scrollbar but don't clip inline/table children
            "div, p, section, article, header, footer, main, aside, nav, blockquote { max-width: 100%; word-wrap: break-word; overflow-wrap: break-word; }" +
            "a { color: \(isDarkMode ? "#667eea" : "#0066cc"); word-break: break-all; }" +
            "blockquote { border-left: 3px solid \(isDarkMode ? "#666666" : "#cccccc"); margin: 0; padding-left: 12px; " +
            "color: \(isDarkMode ? "#999999" : "#666666"); }" +
            "pre { background-color: \(isDarkMode ? "#1a1a1a" : "#f5f5f5"); padding: 8px; border-radius: 4px; " +
            "overflow-x: auto; white-space: pre-wrap; max-width: 100%; }" +
            "code { word-wrap: break-word; overflow-wrap: break-word; }" +
            "iframe, embed, object { max-width: 100% !important; }" +
            // Prevent absurdly wide min-width declarations from forcing horizontal scroll
            "* { min-width: 0 !important; }"
    }

    static func applyWebViewChrome(_ webView: WKWebView, isDarkMode: Bool) {
        #if os(iOS)
        let backgroundColor = isDarkMode
            ? UIColor(red: 37 / 255, green: 37 / 255, blue: 37 / 255, alpha: 1)
            : UIColor.white
        webView.backgroundColor = backgroundColor
        webView.scrollView.backgroundColor = backgroundColor
        #elseif os(macOS)
        let nsColor: NSColor = isDarkMode
            ? NSColor(red: 37 / 255, green: 37 / 255, blue: 37 / 255, alpha: 1)
            : .white
        webView.wantsLayer = true
        webView.layer?.backgroundColor = nsColor.cgColor
        if let scroll = webView.enclosingScrollView {
            scroll.drawsBackground = true
            scroll.backgroundColor = nsColor
        }
        #endif
    }

    static func openExternalURL(_ url: URL) {
        #if os(iOS)
        UIApplication.shared.open(url)
        #elseif os(macOS)
        NSWorkspace.shared.open(url)
        #endif
    }
}

#if os(iOS)
private struct EmailHTMLWebViewIOS: UIViewRepresentable {
    let htmlContent: String
    let isDarkMode: Bool
    var onLoadComplete: (() -> Void)?

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.dataDetectorTypes = [.link, .phoneNumber]
        configuration.allowsInlineMediaPlayback = false
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        if #available(iOS 16.0, *) {
            configuration.suppressesIncrementalRendering = false
        }
        let webView = WKWebView(frame: .zero, configuration: configuration)
        if #available(iOS 14.0, *) {
            let preferences = WKWebpagePreferences()
            preferences.allowsContentJavaScript = true
            webView.configuration.defaultWebpagePreferences = preferences
        }
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = true
        EmailHTMLRenderer.applyWebViewChrome(webView, isDarkMode: isDarkMode)
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.showsVerticalScrollIndicator = true
        webView.scrollView.bounces = false
        webView.scrollView.alwaysBounceHorizontal = false
        webView.scrollView.alwaysBounceVertical = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        EmailHTMLRenderer.loadHTMLContent(into: webView, isDarkMode: isDarkMode, htmlContent: htmlContent)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onLoadComplete = onLoadComplete
        EmailHTMLRenderer.applyWebViewChrome(webView, isDarkMode: isDarkMode)
        if context.coordinator.lastLoadedContent != htmlContent {
            context.coordinator.lastLoadedContent = htmlContent
            EmailHTMLRenderer.loadHTMLContent(into: webView, isDarkMode: isDarkMode, htmlContent: htmlContent)
        }
    }

    func makeCoordinator() -> Coordinator {
        let c = Coordinator()
        c.onLoadComplete = onLoadComplete
        return c
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onLoadComplete: (() -> Void)?
        var lastLoadedContent: String = ""

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.onLoadComplete?()
            }
            let script = Self.widthInjectionScript
            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                EmailHTMLRenderer.openExternalURL(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            logHTMLFailure(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            logHTMLFailure(error)
        }

        private func logHTMLFailure(_ error: Error) {
            let nsError = error as NSError
            if nsError.code != NSURLErrorCancelled && nsError.domain != "WebKitErrorDomain" {
                logError("EmailHTMLWebView: \(error.localizedDescription)", category: "UI")
            }
        }

        private static let widthInjectionScript = """
        (function() {
            var viewportWidth = window.innerWidth || document.documentElement.clientWidth;
            // Pin the viewport to the actual view width so emails with narrow mobile viewports
            // (e.g. width=320) are not scaled up to fill the container.
            var meta = document.querySelector('meta[name="viewport"]');
            if (meta) {
                meta.content = 'width=' + viewportWidth + ', initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
            }
            // Scale images down to fit; keep aspect ratio intact.
            var images = document.querySelectorAll('img');
            for (var i = 0; i < images.length; i++) {
                images[i].style.maxWidth = '100%';
                images[i].style.height = 'auto';
            }
            // Remove hard-coded pixel widths on tables that would cause horizontal overflow.
            var tables = document.querySelectorAll('table');
            for (var i = 0; i < tables.length; i++) {
                var tw = tables[i].getAttribute('width');
                if (tw && parseInt(tw, 10) > viewportWidth) {
                    tables[i].removeAttribute('width');
                    tables[i].style.maxWidth = '100%';
                }
            }
            // Prevent horizontal scrollbar at root only — not on every element, which clips images.
            document.body.style.overflowX = 'hidden';
            document.documentElement.style.overflowX = 'hidden';
        })();
        """
    }
}
#endif

#if os(macOS)
private struct EmailHTMLWebViewMac: NSViewRepresentable {
    let htmlContent: String
    let isDarkMode: Bool
    var scrollSignal: Int = 0
    var scrollStepAmount: CGFloat = 0
    var onLoadComplete: (() -> Void)?

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        if #available(macOS 11.0, *) {
            let preferences = WKWebpagePreferences()
            preferences.allowsContentJavaScript = true
            webView.configuration.defaultWebpagePreferences = preferences
        }
        webView.navigationDelegate = context.coordinator
        webView.magnification = 1.0
        webView.allowsMagnification = false
        EmailHTMLRenderer.applyWebViewChrome(webView, isDarkMode: isDarkMode)
        if let scroll = webView.enclosingScrollView {
            scroll.hasHorizontalScroller = false
        }
        EmailHTMLRenderer.loadHTMLContent(into: webView, isDarkMode: isDarkMode, htmlContent: htmlContent)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onLoadComplete = onLoadComplete
        EmailHTMLRenderer.applyWebViewChrome(webView, isDarkMode: isDarkMode)
        if context.coordinator.lastLoadedContent != htmlContent {
            context.coordinator.lastLoadedContent = htmlContent
            webView.magnification = 1.0
            EmailHTMLRenderer.loadHTMLContent(into: webView, isDarkMode: isDarkMode, htmlContent: htmlContent)
        }
        // Arrow-key scroll: fire when the signal counter increments
        if scrollSignal != context.coordinator.lastScrollSignal {
            context.coordinator.lastScrollSignal = scrollSignal
            if scrollStepAmount != 0 {
                webView.evaluateJavaScript(
                    "window.scrollBy({top: \(scrollStepAmount), behavior: 'smooth'})",
                    completionHandler: nil
                )
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        let c = Coordinator()
        c.onLoadComplete = onLoadComplete
        return c
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onLoadComplete: (() -> Void)?
        var lastLoadedContent: String = ""
        var lastScrollSignal: Int = 0

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript(Self.viewportFixScript, completionHandler: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.onLoadComplete?()
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                EmailHTMLRenderer.openExternalURL(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            logHTMLFailure(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            logHTMLFailure(error)
        }

        private func logHTMLFailure(_ error: Error) {
            let nsError = error as NSError
            if nsError.code != NSURLErrorCancelled && nsError.domain != "WebKitErrorDomain" {
                logError("EmailHTMLWebView: \(error.localizedDescription)", category: "UI")
            }
        }

        // Pin the viewport to the actual view width so emails that declare a narrow
        // mobile viewport (e.g. width=320) are not scaled up to fill the card.
        // Surgically targets images and oversized tables only — avoids blasting
        // overflow:hidden onto every element, which clips embedded images.
        private static let viewportFixScript = """
        (function() {
            var viewportWidth = window.innerWidth || document.documentElement.clientWidth;
            var meta = document.querySelector('meta[name="viewport"]');
            if (meta) {
                meta.content = 'width=' + viewportWidth + ', initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
            }
            // Scale images down to fit; keep aspect ratio intact.
            var images = document.querySelectorAll('img');
            for (var i = 0; i < images.length; i++) {
                images[i].style.maxWidth = '100%';
                images[i].style.height = 'auto';
            }
            // Remove hard-coded pixel widths on tables wider than the viewport.
            var tables = document.querySelectorAll('table');
            for (var i = 0; i < tables.length; i++) {
                var tw = tables[i].getAttribute('width');
                if (tw && parseInt(tw, 10) > viewportWidth) {
                    tables[i].removeAttribute('width');
                    tables[i].style.maxWidth = '100%';
                }
            }
            // Prevent horizontal scrollbar at root only.
            document.body.style.overflowX = 'hidden';
            document.documentElement.style.overflowX = 'hidden';
        })();
        """
    }
}
#endif
