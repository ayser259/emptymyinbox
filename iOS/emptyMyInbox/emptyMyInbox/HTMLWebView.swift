//
//  HTMLWebView.swift
//  emptyMyInbox
//
//  WebView wrapper for rendering HTML content
//

import SwiftUI
import WebKit
import UIKit

struct HTMLWebView: UIViewRepresentable {
    let htmlContent: String
    let isDarkMode: Bool
    var contentWidth: CGFloat? = nil
    var onLoadComplete: (() -> Void)? = nil
    
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.dataDetectorTypes = [.link, .phoneNumber]
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
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
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // Update background color based on dark mode
        let backgroundColor = isDarkMode 
            ? UIColor(red: 37/255.0, green: 37/255.0, blue: 37/255.0, alpha: 1.0) // Dark grey
            : UIColor.white // Light background
        webView.backgroundColor = backgroundColor
        webView.scrollView.backgroundColor = backgroundColor
        
        // Create HTML with dark mode support
        // Use device-width to let the WebView determine its own width
        let htmlString = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                * {
                    max-width: 100% !important;
                    box-sizing: border-box !important;
                }
                html, body {
                    width: 100% !important;
                    margin: 0 !important;
                    padding: 0 !important;
                    overflow-x: hidden !important;
                }
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
                    font-size: 15px;
                    line-height: 1.6;
                    color: \(isDarkMode ? "#ffffff" : "#000000");
                    background-color: \(isDarkMode ? "#252525" : "#ffffff");
                    -webkit-text-size-adjust: 100%;
                    word-wrap: break-word;
                    overflow-wrap: break-word;
                    text-align: center;
                    display: flex;
                    justify-content: center;
                    align-items: flex-start;
                }
                #email-container {
                    width: 100% !important;
                    max-width: 100% !important;
                    margin: 0 auto;
                    padding: 0;
                    text-align: center;
                }
                img {
                    max-width: 100% !important;
                    height: auto !important;
                    display: block;
                    margin: 0 auto;
                }
                table {
                    max-width: 100% !important;
                    table-layout: fixed;
                    word-wrap: break-word;
                }
                td, th {
                    word-wrap: break-word;
                    overflow-wrap: break-word;
                }
                a {
                    color: \(isDarkMode ? "#667eea" : "#0066cc");
                    word-break: break-all;
                }
                blockquote {
                    border-left: 3px solid \(isDarkMode ? "#666666" : "#cccccc");
                    margin: 0;
                    padding-left: 12px;
                    color: \(isDarkMode ? "#999999" : "#666666");
                    word-wrap: break-word;
                }
                pre {
                    background-color: \(isDarkMode ? "#1a1a1a" : "#f5f5f5");
                    padding: 8px;
                    border-radius: 4px;
                    overflow-x: auto;
                    word-wrap: break-word;
                    white-space: pre-wrap;
                }
                code {
                    word-wrap: break-word;
                    overflow-wrap: break-word;
                }
            </style>
        </head>
        <body>
            <div id="email-container">
                \(htmlContent)
            </div>
        </body>
        </html>
        """
        
        webView.loadHTMLString(htmlString, baseURL: nil)
    }
    
    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        coordinator.parent = self
        return coordinator
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: HTMLWebView?
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Notify that content is loaded
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.parent?.onLoadComplete?()
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
                    
                    // Force all elements to respect width constraints
                    var allElements = document.querySelectorAll('*');
                    for (var i = 0; i < allElements.length; i++) {
                        var el = allElements[i];
                        el.style.maxWidth = '100%';
                        el.style.boxSizing = 'border-box';
                        // Remove any fixed widths that exceed viewport
                        var computedStyle = window.getComputedStyle(el);
                        var width = computedStyle.width;
                        if (width && parseFloat(width) > viewportWidth) {
                            el.style.width = '100%';
                        }
                    }
                    
                    // Ensure container respects width
                    var container = document.getElementById('email-container');
                    if (container) {
                        container.style.width = '100%';
                        container.style.maxWidth = '100%';
                    }
                    
                    // Prevent horizontal scrolling
                    document.body.style.overflowX = 'hidden';
                    document.documentElement.style.overflowX = 'hidden';
                    document.body.style.width = '100%';
                    document.documentElement.style.width = '100%';
                    
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
    }
}

