import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Platform-specific app icon changes.
public enum AppIconService {
    #if os(iOS)
    public static var supportsAlternateIcons: Bool {
        UIApplication.shared.supportsAlternateIcons
    }

    public static func setIOSAlternateIcon(name: String?) {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        guard UIApplication.shared.alternateIconName != name else { return }

        UIApplication.shared.setAlternateIconName(name) { error in
            if let error {
                logWarning("Failed to set alternate app icon: \(error.localizedDescription)", category: "Appearance")
            }
        }
    }
    #endif

    #if os(macOS)
    public static func processedThemeIconImage(_ image: NSImage) -> NSImage {
        prepareDockIconImage(image)
    }

    public static func setMacDockIcon(assetName: String?) {
        if let assetName, let image = NSImage(named: assetName) {
            NSApplication.shared.applicationIconImage = prepareDockIconImage(image)
        } else {
            NSApplication.shared.applicationIconImage = nil
        }
    }

    /// App Store-style icons include a white matte around the artwork. macOS masks bundled
    /// icons automatically, but runtime `applicationIconImage` values need edge-connected
    /// white removed so the Dock background shows through.
    private static func prepareDockIconImage(_ image: NSImage) -> NSImage {
        guard let source = rasterizeThemeIcon(image) else { return image }

        let width = source.pixelsWide
        let height = source.pixelsHigh
        let bytesPerRow = source.bytesPerRow
        let bytesPerPixel = 4
        guard width > 0, height > 0, let sourceData = source.bitmapData else { return image }

        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        pixels.withUnsafeMutableBytes { buffer in
            guard let destination = buffer.baseAddress else { return }
            memcpy(destination, sourceData, bytesPerRow * height)
        }

        removeEdgeConnectedNearWhite(
            from: &pixels,
            width: width,
            height: height,
            bytesPerRow: bytesPerRow,
            bytesPerPixel: bytesPerPixel,
            threshold: 250
        )

        guard let output = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: bytesPerRow,
            bitsPerPixel: 32
        ), let outputData = output.bitmapData else {
            return image
        }

        pixels.withUnsafeBytes { buffer in
            guard let source = buffer.baseAddress else { return }
            memcpy(outputData, source, bytesPerRow * height)
        }

        output.size = NSSize(width: width, height: height)

        let result = NSImage(size: output.size)
        result.addRepresentation(output)
        return result
    }

    /// Rasterize through AppKit so pixel row 0 is the top of the image.
    private static func rasterizeThemeIcon(_ image: NSImage) -> NSBitmapImageRep? {
        let pixelWidth = max(
            image.representations.compactMap { ($0 as? NSBitmapImageRep)?.pixelsWide }.max() ?? 0,
            Int(image.size.width.rounded())
        )
        let pixelHeight = max(
            image.representations.compactMap { ($0 as? NSBitmapImageRep)?.pixelsHigh }.max() ?? 0,
            Int(image.size.height.rounded())
        )
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        rep.size = NSSize(width: pixelWidth, height: pixelHeight)

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.current = context

        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight).fill()

        image.draw(
            in: NSRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight),
            from: NSRect.zero,
            operation: .copy,
            fraction: 1.0,
            respectFlipped: true,
            hints: nil
        )

        return rep
    }

    private static func removeEdgeConnectedNearWhite(
        from pixels: inout [UInt8],
        width: Int,
        height: Int,
        bytesPerRow: Int,
        bytesPerPixel: Int,
        threshold: UInt8
    ) {
        var visited = [Bool](repeating: false, count: width * height)
        var queue: [(Int, Int)] = []

        func pixelIndex(x: Int, y: Int) -> Int {
            y * bytesPerRow + x * bytesPerPixel
        }

        func visitIndex(x: Int, y: Int) -> Int {
            y * width + x
        }

        func isNearWhite(x: Int, y: Int) -> Bool {
            let index = pixelIndex(x: x, y: y)
            return pixels[index] >= threshold
                && pixels[index + 1] >= threshold
                && pixels[index + 2] >= threshold
        }

        func makeTransparent(x: Int, y: Int) {
            let index = pixelIndex(x: x, y: y)
            pixels[index] = 0
            pixels[index + 1] = 0
            pixels[index + 2] = 0
            pixels[index + 3] = 0
        }

        func enqueueIfNeeded(x: Int, y: Int) {
            guard x >= 0, y >= 0, x < width, y < height else { return }
            let visit = visitIndex(x: x, y: y)
            guard !visited[visit], isNearWhite(x: x, y: y) else { return }
            visited[visit] = true
            queue.append((x, y))
        }

        for x in 0..<width {
            enqueueIfNeeded(x: x, y: 0)
            enqueueIfNeeded(x: x, y: height - 1)
        }
        for y in 0..<height {
            enqueueIfNeeded(x: 0, y: y)
            enqueueIfNeeded(x: width - 1, y: y)
        }

        while !queue.isEmpty {
            let (x, y) = queue.removeFirst()
            makeTransparent(x: x, y: y)

            enqueueIfNeeded(x: x - 1, y: y)
            enqueueIfNeeded(x: x + 1, y: y)
            enqueueIfNeeded(x: x, y: y - 1)
            enqueueIfNeeded(x: x, y: y + 1)
        }
    }
    #endif
}
