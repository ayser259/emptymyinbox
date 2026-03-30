//
//  HTMLWebView.swift
//  emptyMyInbox
//
//  WebView wrapper for rendering HTML content
//

import SwiftUI
import WebKit
import UIKit
import EmptyMyInboxShared

struct HTMLWebView: UIViewRepresentable {
    let htmlContent: String
    let isDarkMode: Bool
    var contentWidth: CGFloat? = nil
    var onLoadComplete: (() -> Void)? = nil
    
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.dataDetectorTypes = [.link, .phoneNumber]
        
        // Optimize WebView configuration to reduce process overhead
        configuration.allowsInlineMediaPlayback = false // Reduce resource usage
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        
        // Suppress WebKit console noise
        if #available(iOS 16.0, *) {
            configuration.suppressesIncrementalRendering = false
        }
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        
        // Suppress WebKit logging by setting preferences
        if #available(iOS 14.0, *) {
            let preferences = WKWebpagePreferences()
            preferences.allowsContentJavaScript = true
            // Note: There's no direct way to suppress WebKit process errors in code
            // These are system-level and would need scheme settings
        }
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = true
        // Set background color based on dark mode
        let backgroundColor = isDarkMode 
            ? UIColor(red: 37/255.0, green: 37/255.0, blue: 37/255.0, alpha: 1.0) // Dark grey
            : UIColor.white // Light background
        webView.backgroundColor = backgroundColor
        webView.scrollView.backgroundColor = backgroundColor
        
        // Configure scroll view to prevent horizontal scrolling
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.showsVerticalScrollIndicator = true
        webView.scrollView.bounces = false
        webView.scrollView.alwaysBounceHorizontal = false
        webView.scrollView.alwaysBounceVertical = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        
        // Load HTML content immediately
        loadHTMLContent(into: webView, isDarkMode: isDarkMode, htmlContent: htmlContent)
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // Only update background color, don't reload HTML unless content actually changed
        let backgroundColor = isDarkMode 
            ? UIColor(red: 37/255.0, green: 37/255.0, blue: 37/255.0, alpha: 1.0) // Dark grey
            : UIColor.white // Light background
        webView.backgroundColor = backgroundColor
        webView.scrollView.backgroundColor = backgroundColor
        
        // Store current content in coordinator to detect changes
        if context.coordinator.lastLoadedContent != htmlContent {
            context.coordinator.lastLoadedContent = htmlContent
            loadHTMLContent(into: webView, isDarkMode: isDarkMode, htmlContent: htmlContent)
        }
    }
    
    private func loadHTMLContent(into webView: WKWebView, isDarkMode: Bool, htmlContent: String) {
        var finalHtml = htmlContent.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // robustness: Check if content is HTML-escaped (starts with &lt; or similar)
        // This fixes the issue where raw HTML code is displayed to the user
        // We check for common escaped starts: &lt;html, &lt;!DOCTYPE, or just &lt;
        if finalHtml.hasPrefix("&lt;") || finalHtml.hasPrefix("&#60;") {
            if let unescaped = unescapeHTML(finalHtml) {
                finalHtml = unescaped.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // Check if it's already a full HTML document
        // Case insensitive check
        let lowercased = finalHtml.lowercased()
        let isFullDocument = lowercased.hasPrefix("<!doctype") || lowercased.hasPrefix("<html")
        
        let htmlString: String
        if isFullDocument {
            // BEST PRACTICE: Inject styles into the existing document to preserve original styling (fonts, layout)
            htmlString = injectStylesIntoHTML(finalHtml, isDarkMode: isDarkMode)
        } else {
            // If it's a fragment, wrap it in our container
            htmlString = createWrappedHTML(finalHtml, isDarkMode: isDarkMode)
        }
        
        // Load HTML - use bundle URL as base to allow loading local assets if any
        webView.loadHTMLString(htmlString, baseURL: Bundle.main.bundleURL)
    }
    
    private func unescapeHTML(_ string: String) -> String? {
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
    
    private func createWrappedHTML(_ content: String, isDarkMode: Bool) -> String {
        return "<!DOCTYPE html>" +
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
    
    private func injectStylesIntoHTML(_ html: String, isDarkMode: Bool) -> String {
        // Robust Injection: Insert our critical CSS and Viewport meta tag
        // without destroying the original <head> where the email's styles live.
        
        var modifiedHtml = html
        let styles = "<style>" + getCommonStyles(isDarkMode: isDarkMode) + "</style>"
        let viewport = "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no\">"
        
        // 1. Try to insert into <head>
        if let headEndRange = modifiedHtml.range(of: "</head>", options: .caseInsensitive) {
            // Insert styles before closing head
            modifiedHtml.insert(contentsOf: styles, at: headEndRange.lowerBound)
            
            // Check if we need viewport
            if !modifiedHtml.contains("viewport") {
                 // Insert viewport at start of head
                if let headStartRange = modifiedHtml.range(of: "<head", options: .caseInsensitive),
                   let closingBracket = modifiedHtml[headStartRange.upperBound...].firstIndex(of: ">") {
                    modifiedHtml.insert(contentsOf: viewport, at: modifiedHtml.index(after: closingBracket))
                } else {
                    // Fallback: insert before styles
                    modifiedHtml.insert(contentsOf: viewport, at: headEndRange.lowerBound)
                }
            }
            return modifiedHtml
        }
        
        // 2. If no <head>, try to insert at start of <body>
        if let bodyStartRange = modifiedHtml.range(of: "<body", options: .caseInsensitive) {
            // Find closing bracket of body tag
            if let closingBracket = modifiedHtml[bodyStartRange.upperBound...].firstIndex(of: ">") {
                let insertPoint = modifiedHtml.index(after: closingBracket)
                // Create a head-like block inside body (valid HTML5)
                modifiedHtml.insert(contentsOf: viewport + styles, at: insertPoint)
                return modifiedHtml
            }
        }
        
        // 3. Fallback: Wrap the whole thing if we can't find structure
        // This is a last resort as it might break some relative styles
        return createWrappedHTML(extractBodyContent(from: html) ?? html, isDarkMode: isDarkMode)
    }
    
    private func extractBodyContent(from html: String) -> String? {
        // Try to find <body> tag (case insensitive, with any attributes)
        if let bodyStartRange = html.range(of: "<body", options: .caseInsensitive) {
            // Find the closing > of the <body> tag (could have attributes)
            var searchStart = bodyStartRange.upperBound
            
            // Look for the closing > after <body
            while searchStart < html.endIndex {
                if html[searchStart] == ">" {
                    let bodyContentStart = html.index(after: searchStart)
                    
                    // Now find </body>
                    if let bodyEndRange = html[bodyContentStart...].range(of: "</body>", options: .caseInsensitive) {
                        let bodyContent = String(html[bodyContentStart..<bodyEndRange.lowerBound])
                        let cleaned = bodyContent.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !cleaned.isEmpty {
                            return cleaned
                        }
                    }
                    break
                }
                searchStart = html.index(after: searchStart)
            }
        }
        return nil
    }
    
    private func getCommonStyles(isDarkMode: Bool) -> String {
        return "* { max-width: 100% !important; box-sizing: border-box !important; overflow-wrap: break-word !important; word-wrap: break-word !important; }" +
            "html, body { width: 100% !important; max-width: 100% !important; margin: 0 !important; padding: 0 !important; overflow-x: hidden !important; overflow-y: auto !important; }" +
            "body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 15px; line-height: 1.6; " +
            "color: \(isDarkMode ? "#ffffff" : "#000000"); background-color: \(isDarkMode ? "#252525" : "#ffffff"); " +
            "-webkit-text-size-adjust: 100%; word-wrap: break-word; overflow-wrap: break-word; text-align: center; " +
            "display: flex; justify-content: center; align-items: flex-start; }" +
            "#email-container { width: 100% !important; max-width: 100% !important; margin: 0 auto; padding: 0; text-align: center; overflow-x: hidden !important; }" +
            "img { max-width: 100% !important; width: auto !important; height: auto !important; display: block; margin: 0 auto; }" +
            "table { max-width: 100% !important; width: 100% !important; table-layout: fixed !important; word-wrap: break-word; overflow-wrap: break-word; }" +
            "td, th { max-width: 100% !important; word-wrap: break-word !important; overflow-wrap: break-word !important; }" +
            "div, p, span, section, article, header, footer, main, aside, nav { max-width: 100% !important; overflow-x: hidden !important; word-wrap: break-word !important; overflow-wrap: break-word !important; }" +
            "a { color: \(isDarkMode ? "#667eea" : "#0066cc"); word-break: break-all; max-width: 100% !important; }" +
            "blockquote { border-left: 3px solid \(isDarkMode ? "#666666" : "#cccccc"); margin: 0; padding-left: 12px; " +
            "color: \(isDarkMode ? "#999999" : "#666666"); word-wrap: break-word; max-width: 100% !important; overflow-x: hidden !important; }" +
            "pre { background-color: \(isDarkMode ? "#1a1a1a" : "#f5f5f5"); padding: 8px; border-radius: 4px; overflow-x: auto; " +
            "word-wrap: break-word; white-space: pre-wrap; max-width: 100% !important; }" +
            "code { word-wrap: break-word; overflow-wrap: break-word; max-width: 100% !important; }" +
            "iframe, embed, object { max-width: 100% !important; width: 100% !important; }" +
            "[style*='width'] { max-width: 100% !important; }" +
            "[style*='min-width'] { min-width: 0 !important; }"
    }
    
    private func sanitizeHTML(_ html: String) -> String {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If the content is already a full HTML document, extract just the body content
        if trimmed.hasPrefix("<!DOCTYPE") || trimmed.hasPrefix("<html") {
            // Try to find <body> tag (case insensitive, with any attributes)
            // Use range(of:) to find the start
            if let bodyStartRange = trimmed.range(of: "<body", options: .caseInsensitive) {
                // Find the closing > of the <body> tag (could have attributes)
                var searchStart = bodyStartRange.upperBound
                var foundBodyStart = false
                
                // Look for the closing > after <body
                while searchStart < trimmed.endIndex {
                    if trimmed[searchStart] == ">" {
                        foundBodyStart = true
                        let bodyContentStart = trimmed.index(after: searchStart)
                        
                        // Now find </body>
                        if let bodyEndRange = trimmed[bodyContentStart...].range(of: "</body>", options: .caseInsensitive) {
                            let bodyContent = String(trimmed[bodyContentStart..<bodyEndRange.lowerBound])
                            let cleaned = bodyContent.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !cleaned.isEmpty {
                                logDebug("HTMLWebView: Extracted body content (\(cleaned.prefix(100))...)", category: "UI")
                                return cleaned
                            }
                        }
                        break
                    }
                    searchStart = trimmed.index(after: searchStart)
                }
                
                if !foundBodyStart {
                    logWarning("HTMLWebView: Found <body> tag but couldn't find closing >", category: "UI")
                }
            } else {
                logDebug("HTMLWebView: No <body> tag found in HTML document", category: "UI")
            }
        }
        
        // Return as-is if it's already just HTML fragment
        return html
    }
    
    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        coordinator.parent = self
        return coordinator
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: HTMLWebView?
        var lastLoadedContent: String = ""
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Notify that content is loaded
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.parent?.onLoadComplete?()
            }
            
            // Check if content actually rendered (not showing as plain text)
            // Also check if the body contains raw HTML tags (which would indicate rendering failure)
            webView.evaluateJavaScript("""
                (function() {
                    var bodyText = document.body.innerText || document.body.textContent || '';
                    var bodyHTML = document.body.innerHTML || '';
                    // Check if body text starts with HTML tags (indicating raw HTML display)
                    var startsWithHTML = /^\\s*<[!?]?[a-z]/i.test(bodyText.trim());
                    // Check if we have actual rendered content (not just HTML source)
                    var hasRenderedContent = bodyHTML.length > 0 && !startsWithHTML;
                    return {
                        hasContent: bodyHTML.length > 0,
                        mightBeRawHTML: startsWithHTML,
                        bodyLength: bodyHTML.length
                    };
                })();
            """) { result, error in
                if let error = error {
                    logError("HTMLWebView: Error checking content - \(error.localizedDescription)", category: "UI")
                } else if let dict = result as? [String: Any] {
                    if let mightBeRaw = dict["mightBeRawHTML"] as? Bool, mightBeRaw {
                        logWarning("HTMLWebView: Warning - Content might be displaying as raw HTML", category: "UI")
                    }
                }
            }
            
            // Inject JavaScript to ensure content width matches viewport and prevent overflow
            let script = """
                (function() {
                    // Get the actual viewport width
                    var viewportWidth = window.innerWidth || document.documentElement.clientWidth;
                    
                    // Update viewport meta tag
                    var meta = document.querySelector('meta[name="viewport"]');
                    if (meta) {
                        meta.content = 'width=' + viewportWidth + ', initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
                    }
                    
                    // Force all elements to respect width constraints - more aggressive
                    var allElements = document.querySelectorAll('*');
                    for (var i = 0; i < allElements.length; i++) {
                        var el = allElements[i];
                        // Skip script and style tags
                        if (el.tagName === 'SCRIPT' || el.tagName === 'STYLE' || el.tagName === 'META') {
                            continue;
                        }
                        el.style.maxWidth = '100%';
                        el.style.boxSizing = 'border-box';
                        el.style.overflowX = 'hidden';
                        el.style.wordWrap = 'break-word';
                        el.style.overflowWrap = 'break-word';
                        
                        // Remove any fixed widths that exceed viewport
                        var computedStyle = window.getComputedStyle(el);
                        var width = computedStyle.width;
                        if (width && parseFloat(width) > viewportWidth) {
                            el.style.width = '100%';
                        }
                        
                        // Handle inline styles that might have width
                        if (el.style.width && parseFloat(el.style.width) > viewportWidth) {
                            el.style.width = '100%';
                        }
                        
                        // Handle min-width that might cause issues
                        if (el.style.minWidth && parseFloat(el.style.minWidth) > viewportWidth) {
                            el.style.minWidth = '0';
                        }
                    }
                    
                    // Ensure container respects width
                    var container = document.getElementById('email-container');
                    if (container) {
                        container.style.width = '100%';
                        container.style.maxWidth = '100%';
                        container.style.overflowX = 'hidden';
                    }
                    
                    // Prevent horizontal scrolling
                    document.body.style.overflowX = 'hidden';
                    document.documentElement.style.overflowX = 'hidden';
                    document.body.style.width = '100%';
                    document.documentElement.style.width = '100%';
                    document.body.style.maxWidth = '100%';
                    document.documentElement.style.maxWidth = '100%';
                    
                    // Force WebView to respect width
                    if (window.webkit && window.webkit.messageHandlers) {
                        // WebKit specific handling
                    }
                })();
            """
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Allow navigation within the HTML content
            if navigationAction.navigationType == .linkActivated {
                if let url = navigationAction.request.url {
                    UIApplication.shared.open(url)
                    decisionHandler(.cancel)
                    return
                }
            }
            decisionHandler(.allow)
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            // Only log non-cancellation errors to reduce console noise
            let nsError = error as NSError
            if nsError.code != NSURLErrorCancelled && nsError.domain != "WebKitErrorDomain" {
                logError("HTMLWebView: Failed to load HTML - \(error.localizedDescription)", category: "UI")
            }
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            // Only log non-cancellation errors to reduce console noise
            let nsError = error as NSError
            if nsError.code != NSURLErrorCancelled && nsError.domain != "WebKitErrorDomain" {
                logError("HTMLWebView: Failed provisional navigation - \(error.localizedDescription)", category: "UI")
            }
        }
    }
}

