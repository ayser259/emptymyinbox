//
//  GIFImageView.swift
//  emptyMyInbox
//
//  Lightweight view for rendering bundled GIFs in SwiftUI
//

import SwiftUI
import WebKit

struct GIFImageView: UIViewRepresentable {
    let resourceName: String
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.backgroundColor = .clear
        webView.isUserInteractionEnabled = false
        loadGIF(into: webView)
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // No-op. GIFs loop automatically once loaded.
    }
    
    private func loadGIF(into webView: WKWebView) {
        // Try multiple paths to find the GIF
        var url: URL?
        
        // First, try loading from the asset catalog imageset directory
        if let assetPath = Bundle.main.resourcePath {
            let imagesetPath = "\(assetPath)/Assets.xcassets/CelebrationGifs.imageset/\(resourceName).gif"
            url = URL(fileURLWithPath: imagesetPath)
            if let url = url, FileManager.default.fileExists(atPath: url.path) {
                // Found it
            } else {
                url = nil
            }
        }
        
        // If not found, try direct bundle resource
        if url == nil {
            url = Bundle.main.url(forResource: resourceName, withExtension: "gif")
        }
        
        guard let url = url, FileManager.default.fileExists(atPath: url.path) else {
            print("GIFImageView: Missing resource \(resourceName).gif")
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            webView.load(
                data,
                mimeType: "image/gif",
                characterEncodingName: "UTF-8",
                baseURL: url.deletingLastPathComponent()
            )
        } catch {
            print("GIFImageView: Failed to load \(resourceName).gif - \(error.localizedDescription)")
        }
    }
}

