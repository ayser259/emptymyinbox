//
//  EmailThreadConversationWebView.swift
//  EmptyMyInboxShared
//
//  Single WKWebView for reading a thread as one scrollable HTML document.
//

import SwiftUI
import WebKit

public struct EmailThreadConversationWebView: View {
    let messages: [EmailDetail]
    let selectedId: Int
    let isDarkMode: Bool
    let scrollSignal: Int
    let scrollStepAmount: CGFloat
    let onSelectMessage: (Int) -> Void
    let onLoadComplete: (() -> Void)?

    public init(
        messages: [EmailDetail],
        selectedId: Int,
        isDarkMode: Bool = false,
        scrollSignal: Int = 0,
        scrollStepAmount: CGFloat = 0,
        onSelectMessage: @escaping (Int) -> Void,
        onLoadComplete: (() -> Void)? = nil
    ) {
        self.messages = messages
        self.selectedId = selectedId
        self.isDarkMode = isDarkMode
        self.scrollSignal = scrollSignal
        self.scrollStepAmount = scrollStepAmount
        self.onSelectMessage = onSelectMessage
        self.onLoadComplete = onLoadComplete
    }

    private var documentSignature: String {
        let ids = messages.map(\.id).map(String.init).joined(separator: ",")
        return "\(ids)|\(selectedId)"
    }

    public var body: some View {
        #if os(iOS)
        EmailThreadConversationWebViewIOS(
            messages: messages,
            selectedId: selectedId,
            isDarkMode: isDarkMode,
            documentSignature: documentSignature,
            onSelectMessage: onSelectMessage,
            onLoadComplete: onLoadComplete
        )
        #elseif os(macOS)
        EmailThreadConversationWebViewMac(
            messages: messages,
            selectedId: selectedId,
            isDarkMode: isDarkMode,
            documentSignature: documentSignature,
            scrollSignal: scrollSignal,
            scrollStepAmount: scrollStepAmount,
            onSelectMessage: onSelectMessage,
            onLoadComplete: onLoadComplete
        )
        #else
        EmptyView()
        #endif
    }
}

#if os(iOS)
private struct EmailThreadConversationWebViewIOS: UIViewRepresentable {
    let messages: [EmailDetail]
    let selectedId: Int
    let isDarkMode: Bool
    let documentSignature: String
    let onSelectMessage: (Int) -> Void
    let onLoadComplete: (() -> Void)?

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.dataDetectorTypes = [.link, .phoneNumber]
        configuration.allowsInlineMediaPlayback = false
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.userContentController.add(context.coordinator, name: "thread")

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
        webView.scrollView.showsVerticalScrollIndicator = true
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.bounces = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        loadDocument(in: webView, coordinator: context.coordinator)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onSelectMessage = onSelectMessage
        context.coordinator.onLoadComplete = onLoadComplete
        EmailHTMLRenderer.applyWebViewChrome(webView, isDarkMode: isDarkMode)
        if context.coordinator.lastDocumentSignature != documentSignature {
            loadDocument(in: webView, coordinator: context.coordinator)
        }
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        coordinator.onSelectMessage = onSelectMessage
        coordinator.onLoadComplete = onLoadComplete
        return coordinator
    }

    private func loadDocument(in webView: WKWebView, coordinator: Coordinator) {
        coordinator.lastDocumentSignature = documentSignature
        let html = EmailThreadHTMLBuilder.buildDocument(
            messages: messages,
            selectedId: selectedId,
            isDarkMode: isDarkMode
        )
        webView.loadHTMLString(html, baseURL: Bundle.main.bundleURL)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var onSelectMessage: ((Int) -> Void)?
        var onLoadComplete: (() -> Void)?
        var lastDocumentSignature: String = ""

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "thread",
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String,
                  type == "target",
                  let id = body["id"] as? Int else { return }
            DispatchQueue.main.async {
                self.onSelectMessage?(id)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript(EmailHTMLRenderer.widthInjectionScript) { _, _ in }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.onLoadComplete?()
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                EmailHTMLRenderer.openExternalURL(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
#endif

#if os(macOS)
private struct EmailThreadConversationWebViewMac: NSViewRepresentable {
    let messages: [EmailDetail]
    let selectedId: Int
    let isDarkMode: Bool
    let documentSignature: String
    let scrollSignal: Int
    let scrollStepAmount: CGFloat
    let onSelectMessage: (Int) -> Void
    let onLoadComplete: (() -> Void)?

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "thread")

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

        loadDocument(in: webView, coordinator: context.coordinator)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onSelectMessage = onSelectMessage
        context.coordinator.onLoadComplete = onLoadComplete
        EmailHTMLRenderer.applyWebViewChrome(webView, isDarkMode: isDarkMode)
        if context.coordinator.lastDocumentSignature != documentSignature {
            loadDocument(in: webView, coordinator: context.coordinator)
        }
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
        let coordinator = Coordinator()
        coordinator.onSelectMessage = onSelectMessage
        coordinator.onLoadComplete = onLoadComplete
        return coordinator
    }

    private func loadDocument(in webView: WKWebView, coordinator: Coordinator) {
        coordinator.lastDocumentSignature = documentSignature
        let html = EmailThreadHTMLBuilder.buildDocument(
            messages: messages,
            selectedId: selectedId,
            isDarkMode: isDarkMode
        )
        webView.loadHTMLString(html, baseURL: Bundle.main.bundleURL)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var onSelectMessage: ((Int) -> Void)?
        var onLoadComplete: (() -> Void)?
        var lastDocumentSignature: String = ""
        var lastScrollSignal: Int = 0

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "thread",
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String,
                  type == "target",
                  let id = body["id"] as? Int else { return }
            DispatchQueue.main.async {
                self.onSelectMessage?(id)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript(EmailHTMLRenderer.viewportFixScript) { _, _ in }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.onLoadComplete?()
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                EmailHTMLRenderer.openExternalURL(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
#endif
