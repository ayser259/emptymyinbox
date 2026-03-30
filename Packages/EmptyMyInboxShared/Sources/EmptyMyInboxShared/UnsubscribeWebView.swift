//
//  UnsubscribeWebView.swift
//  EmptyMyInboxShared
//

import SwiftUI
import WebKit
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

public struct UnsubscribeWebView: View {
    public let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var webView: WKWebView?

    public init(url: URL) {
        self.url = url
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                SharedAppTheme.primaryBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    UnsubscribeWebViewRepresentable(
                        url: url,
                        isLoading: $isLoading,
                        canGoBack: $canGoBack,
                        canGoForward: $canGoForward,
                        webView: $webView
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if isLoading {
                        VStack {
                            ProgressView()
                                .tint(SharedAppTheme.accent)
                            Text("Loading unsubscribe page...")
                                .font(.system(size: 14))
                                .secondaryText()
                                .padding(.top, 8)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(SharedAppTheme.primaryBackground.opacity(0.9))
                    }
                }
            }
            .navigationTitle("Unsubscribe")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarLeading) {
                    closeButton
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    navButtons
                }
                #else
                ToolbarItem(placement: .cancellationAction) {
                    closeButton
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    navButtons
                }
                #endif
            }
        }
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Text("Close")
                .foregroundColor(SharedAppTheme.accent)
        }
    }

    private var navButtons: some View {
        Group {
            Button {
                webView?.goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .foregroundColor(canGoBack ? SharedAppTheme.accent : SharedAppTheme.secondaryText)
            }
            .disabled(!canGoBack)

            Button {
                webView?.goForward()
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundColor(canGoForward ? SharedAppTheme.accent : SharedAppTheme.secondaryText)
            }
            .disabled(!canGoForward)
        }
    }
}

// MARK: - Cross-platform WKWebView

private struct UnsubscribeWebViewRepresentable: View {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var webView: WKWebView?

    var body: some View {
        #if os(iOS)
        UnsubscribeWebViewIOS(
            url: url,
            isLoading: $isLoading,
            canGoBack: $canGoBack,
            canGoForward: $canGoForward,
            webView: $webView
        )
        #elseif os(macOS)
        UnsubscribeWebViewMac(
            url: url,
            isLoading: $isLoading,
            canGoBack: $canGoBack,
            canGoForward: $canGoForward,
            webView: $webView
        )
        #else
        EmptyView()
        #endif
    }
}

#if os(iOS)
private struct UnsubscribeWebViewIOS: UIViewRepresentable {
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
        let bg = UIColor(SharedAppTheme.primaryBackground)
        webView.backgroundColor = bg
        webView.scrollView.backgroundColor = bg
        DispatchQueue.main.async {
            self.webView = webView
        }
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: UnsubscribeWebViewIOS

        init(_ parent: UnsubscribeWebViewIOS) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async { self.parent.isLoading = true }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.canGoBack = webView.canGoBack
                self.parent.canGoForward = webView.canGoForward
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.parent.isLoading = false }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.parent.isLoading = false }
        }
    }
}
#endif

#if os(macOS)
private struct UnsubscribeWebViewMac: NSViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var webView: WKWebView?

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.black.cgColor
        if let scroll = webView.enclosingScrollView {
            scroll.drawsBackground = true
            scroll.backgroundColor = NSColor.black
        }
        DispatchQueue.main.async {
            self.webView = webView
        }
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: UnsubscribeWebViewMac

        init(_ parent: UnsubscribeWebViewMac) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async { self.parent.isLoading = true }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.canGoBack = webView.canGoBack
                self.parent.canGoForward = webView.canGoForward
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.parent.isLoading = false }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.parent.isLoading = false }
        }
    }
}
#endif
