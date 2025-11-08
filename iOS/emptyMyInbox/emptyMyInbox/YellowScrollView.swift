//
//  YellowScrollView.swift
//  emptyMyInbox
//
//  Custom ScrollView with yellow scrollbar
//

import SwiftUI
import UIKit

struct YellowScrollView<Content: View>: UIViewRepresentable {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        
        // Customize scrollbar appearance
        scrollView.showsVerticalScrollIndicator = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.indicatorStyle = .white
        
        let hostingController = UIHostingController(rootView: content)
        hostingController.view.backgroundColor = .clear
        scrollView.addSubview(hostingController.view)
        
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: scrollView.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            hostingController.view.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])
        
        context.coordinator.hostingController = hostingController
        
        // Customize scrollbar color to yellow
        DispatchQueue.main.async {
            self.customizeScrollbar(scrollView)
        }
        
        return scrollView
    }
    
    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.hostingController?.rootView = content
        customizeScrollbar(scrollView)
    }
    
    private func customizeScrollbar(_ scrollView: UIScrollView) {
        // Find and customize the scroll indicator
        scrollView.subviews.forEach { subview in
            if let imageView = subview as? UIImageView {
                imageView.tintColor = UIColor(AppTheme.accent)
            }
            // Also check nested views
            subview.subviews.forEach { nestedSubview in
                if let imageView = nestedSubview as? UIImageView {
                    imageView.tintColor = UIColor(AppTheme.accent)
                }
            }
        }
        
        // Use appearance API for scroll indicators
        if #available(iOS 13.0, *) {
            scrollView.verticalScrollIndicatorInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, UIScrollViewDelegate {
        var hostingController: UIHostingController<Content>?
    }
}

