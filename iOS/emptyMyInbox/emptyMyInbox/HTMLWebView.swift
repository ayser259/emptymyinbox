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
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = true
        // Set grey background to match the email box (#252525)
        let greyColor = UIColor(red: 37/255.0, green: 37/255.0, blue: 37/255.0, alpha: 1.0)
        webView.backgroundColor = greyColor
        webView.scrollView.backgroundColor = greyColor
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // Create HTML with dark mode support
        let htmlString = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
                    font-size: 15px;
                    line-height: 1.6;
                    margin: 0;
                    padding: 0;
                    color: \(isDarkMode ? "#ffffff" : "#000000");
                    background-color: #252525;
                    -webkit-text-size-adjust: 100%;
                }
                img {
                    max-width: 100%;
                    height: auto;
                }
                a {
                    color: \(isDarkMode ? "#667eea" : "#0066cc");
                }
                blockquote {
                    border-left: 3px solid \(isDarkMode ? "#666666" : "#cccccc");
                    margin: 0;
                    padding-left: 12px;
                    color: \(isDarkMode ? "#999999" : "#666666");
                }
                pre {
                    background-color: \(isDarkMode ? "#1a1a1a" : "#f5f5f5");
                    padding: 8px;
                    border-radius: 4px;
                    overflow-x: auto;
                }
            </style>
        </head>
        <body>
            \(htmlContent)
        </body>
        </html>
        """
        
        webView.loadHTMLString(htmlString, baseURL: nil)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
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

