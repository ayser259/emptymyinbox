//
//  IOSYellowScrollView.swift
//  EmptyMyInboxShared
//
//  Custom scroll view with accent-tinted scrollbar (iOS only).
//

#if os(iOS)

import SwiftUI
import UIKit

public struct IOSYellowScrollView<Content: View>: UIViewRepresentable {
    let content: Content
    let scrollSignal: Int
    let scrollStepAmount: CGFloat

    public init(
        scrollSignal: Int = 0,
        scrollStepAmount: CGFloat = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.scrollSignal = scrollSignal
        self.scrollStepAmount = scrollStepAmount
        self.content = content()
    }

    public func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
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

        DispatchQueue.main.async {
            self.customizeScrollbar(scrollView)
        }

        return scrollView
    }

    public func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.hostingController?.rootView = content
        if scrollSignal != context.coordinator.lastScrollSignal {
            context.coordinator.lastScrollSignal = scrollSignal
            if scrollStepAmount != 0 {
                let maxOffsetY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
                let nextOffsetY = min(max(scrollView.contentOffset.y + scrollStepAmount, 0), maxOffsetY)
                scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: nextOffsetY), animated: true)
            }
        }
        customizeScrollbar(scrollView)
    }

    private func customizeScrollbar(_ scrollView: UIScrollView) {
        scrollView.subviews.forEach { subview in
            if let imageView = subview as? UIImageView {
                imageView.tintColor = UIColor(SharedAppTheme.accent)
            }
            subview.subviews.forEach { nestedSubview in
                if let imageView = nestedSubview as? UIImageView {
                    imageView.tintColor = UIColor(SharedAppTheme.accent)
                }
            }
        }
        if #available(iOS 13.0, *) {
            scrollView.verticalScrollIndicatorInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public final class Coordinator: NSObject, UIScrollViewDelegate {
        var hostingController: UIHostingController<Content>?
        var lastScrollSignal: Int = 0
    }
}

#endif
