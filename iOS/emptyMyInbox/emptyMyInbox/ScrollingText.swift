//
//  ScrollingText.swift
//  emptyMyInbox
//
//  Text component that scrolls horizontally when content exceeds container width
//

import SwiftUI

struct ScrollingText: View {
    let text: String
    let font: Font
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var opacity: Double = 1.0
    @State private var hasScrolled = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Hidden text to measure width
                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .background(
                        GeometryReader { textGeometry in
                            Color.clear.preference(
                                key: TextWidthPreferenceKey.self,
                                value: textGeometry.size.width
                            )
                        }
                    )
                    .opacity(0)
                
                // Visible scrolling text
                Text(text)
                    .font(font)
                    .primaryText()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(x: calculateOffset())
                    .opacity(opacity)
            }
            .frame(maxWidth: .infinity)
            .clipped()
            .onPreferenceChange(TextWidthPreferenceKey.self) { width in
                textWidth = width
                containerWidth = geometry.size.width
                checkIfScrollingNeeded()
            }
            .onAppear {
                containerWidth = geometry.size.width
                // Measure text width after a brief delay to ensure layout is complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    checkIfScrollingNeeded()
                }
            }
            .onChange(of: geometry.size.width) { oldValue, newWidth in
                containerWidth = newWidth
                checkIfScrollingNeeded()
            }
        }
        .frame(height: 22) // Fixed height for headline font
    }
    
    private func calculateOffset() -> CGFloat {
        // If text fits, center it
        if textWidth <= containerWidth {
            return (containerWidth - textWidth) / 2
        }
        // Otherwise, use the scroll offset
        return offset
    }
    
    private func checkIfScrollingNeeded() {
        guard !hasScrolled && textWidth > containerWidth && containerWidth > 0 && textWidth > 0 else {
            return
        }
        
        hasScrolled = true
        
        // Start from center position
        let startOffset = (containerWidth - textWidth) / 2
        offset = startOffset
        
        // Calculate scroll distance (scroll until the end of text is visible)
        let scrollDistance = textWidth - containerWidth + 40 // Add padding
        
        // Wait a moment before starting scroll
        let scrollDuration = Double(scrollDistance) / 25.0
        
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            // Scroll animation (slow scroll - about 25 points per second)
            withAnimation(.linear(duration: scrollDuration)) {
                offset = startOffset - scrollDistance
            }
            
            // Fade out after scrolling completes
            try? await Task.sleep(nanoseconds: UInt64(scrollDuration * 1_000_000_000))
            
            withAnimation(.easeOut(duration: 0.5)) {
                opacity = 0
            }
        }
    }
}

struct TextWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
