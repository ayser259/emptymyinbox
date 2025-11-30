//
//  UnsubscribeWebView.swift
//  emptyMyInbox
//
//  Web view for loading unsubscribe URLs in-app
//

import SwiftUI
import WebKit

struct UnsubscribeWebView: View {
    let url: URL
    @Environment(\.dismiss) var dismiss
    @State private var isLoading = true
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var webView: WKWebView?
    
    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.primaryBackground
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Web view
                    WebViewRepresentable(
                        url: url,
                        isLoading: $isLoading,
                        canGoBack: $canGoBack,
                        canGoForward: $canGoForward,
                        webView: $webView
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    // Loading indicator
                    if isLoading {
                        VStack {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.accent))
                            Text("Loading unsubscribe page...")
                                .font(.system(size: 14))
                                .secondaryText()
                                .padding(.top, 8)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(AppTheme.primaryBackground.opacity(0.9))
                    }
                }
            }
            .navigationTitle("Unsubscribe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Close")
                            .foregroundColor(AppTheme.accent)
                    }
                }
                
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    // Back button
                    Button {
                        webView?.goBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .foregroundColor(canGoBack ? AppTheme.accent : AppTheme.secondaryText)
                    }
                    .disabled(!canGoBack)
                    
                    // Forward button
                    Button {
                        webView?.goForward()
                    } label: {
                        Image(systemName: "chevron.right")
                            .foregroundColor(canGoForward ? AppTheme.accent : AppTheme.secondaryText)
                    }
                    .disabled(!canGoForward)
                }
            }
        }
    }
}

// MARK: - WebView Representable

struct WebViewRepresentable: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var webView: WKWebView?
    
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.dataDetectorTypes = [.link, .phoneNumber]
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.backgroundColor = AppTheme.primaryBackground.uiColor
        webView.scrollView.backgroundColor = AppTheme.primaryBackground.uiColor
        
        // Store reference
        DispatchQueue.main.async {
            self.webView = webView
        }
        
        // Load the URL
        let request = URLRequest(url: url)
        webView.load(request)
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // Update navigation state
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: WebViewRepresentable
        
        init(parent: WebViewRepresentable) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = true
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.canGoBack = webView.canGoBack
                self.parent.canGoForward = webView.canGoForward
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }
        }
    }
}

// MARK: - Color Extension

extension Color {
    var uiColor: UIColor {
        UIColor(self)
    }
}

