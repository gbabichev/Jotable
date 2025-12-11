//
//  CheckboxAttachment.swift
//  Jotable
//
//  Custom text attachment for interactive checkboxes
//

import Foundation

#if canImport(UIKit)
import UIKit

class CheckboxTextAttachment: NSTextAttachment {
    nonisolated override static var supportsSecureCoding: Bool { return true }

    nonisolated(unsafe) var checkboxID: String
    nonisolated(unsafe) var isChecked: Bool
    nonisolated(unsafe) var fontPointSize: CGFloat?

    init(checkboxID: String, isChecked: Bool, fontPointSize: CGFloat? = nil) {
        self.checkboxID = checkboxID
        self.isChecked = isChecked
        self.fontPointSize = fontPointSize

        // Store state as data so it survives serialization
        let stateDict: [String: Any] = [
            "checkboxID": checkboxID,
            "isChecked": isChecked,
            "fontPointSize": fontPointSize as Any
        ]
        let stateData = try? JSONSerialization.data(withJSONObject: stateDict)

        super.init(data: stateData, ofType: "com.betternotes.checkbox")
    }

    nonisolated override init(data contentData: Data?, ofType uti: String?) {

        // Try to decode checkbox state from the data
        if let data = contentData,
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let id = dict["checkboxID"] as? String,
           let checked = dict["isChecked"] as? Bool {
            self.checkboxID = id
            self.isChecked = checked
            self.fontPointSize = dict["fontPointSize"] as? CGFloat
        } else {
            self.checkboxID = UUID().uuidString
            self.isChecked = false
            self.fontPointSize = nil
        }

        super.init(data: contentData, ofType: uti)
    }

    nonisolated required init?(coder: NSCoder) {
        // Decode our custom properties
        self.checkboxID = coder.decodeObject(of: NSString.self, forKey: "checkboxID") as String? ?? UUID().uuidString
        self.isChecked = coder.decodeBool(forKey: "isChecked")
        if let decodedSize = coder.decodeObject(of: NSNumber.self, forKey: "fontPointSize") {
            let value = CGFloat(decodedSize.doubleValue)
            self.fontPointSize = value > 0 ? value : nil
        } else {
            self.fontPointSize = nil
        }


        // Create state data to pass to super
        let stateDict: [String: Any] = [
            "checkboxID": checkboxID,
            "isChecked": isChecked,
            "fontPointSize": fontPointSize as Any
        ]
        let stateData = try? JSONSerialization.data(withJSONObject: stateDict)

        // Initialize with our data instead of letting super.init(coder:) call init(data:ofType:) with nil
        super.init(data: stateData, ofType: "com.betternotes.checkbox")
    }

    nonisolated override func encode(with coder: NSCoder) {
        // Encode our custom properties first
        coder.encode(checkboxID as NSString, forKey: "checkboxID")
        coder.encode(isChecked, forKey: "isChecked")
        if let size = fontPointSize {
            coder.encode(NSNumber(value: Double(size)), forKey: "fontPointSize")
        }

        // Store state as data
        let stateDict: [String: Any] = [
            "checkboxID": checkboxID,
            "isChecked": isChecked,
            "fontPointSize": fontPointSize as Any
        ]
        if let stateData = try? JSONSerialization.data(withJSONObject: stateDict) {
            contents = stateData
        }

        // Temporarily clear the image before encoding to avoid CGImage errors
        let tempImage = image
        image = nil

        // Call super.encode - the image is nil so it won't try to encode it
        super.encode(with: coder)

        // Restore the image after encoding
        image = tempImage
    }

    // Compute checkbox image on-demand without storing
    private nonisolated func computeCheckboxImage(size: CGSize) -> UIImage? {
        let systemName = isChecked ? "checkmark.square.fill" : "square"

        // Snap to whole pixels to avoid blurry rendering when fonts are fractional
        let snappedSide = max(10, floor(size.width))
        let config = UIImage.SymbolConfiguration(pointSize: snappedSide - 2, weight: .regular, scale: .medium)
        guard let symbolImage = UIImage(systemName: systemName, withConfiguration: config) else {
            return nil
        }

        // Apply the adaptive label color to the symbol
        let tintedSymbol = symbolImage.withTintColor(.label, renderingMode: .alwaysOriginal)

        // Create a renderer and draw the tinted symbol
        let renderer = UIGraphicsImageRenderer(size: size)
        let newImage = renderer.image { context in
            tintedSymbol.draw(in: CGRect(origin: .zero, size: size))
        }

        return newImage
    }

    // Override to provide image during layout - compute on-demand with proper bounds
    nonisolated override func image(forBounds imageBounds: CGRect, textContainer: NSTextContainer?, characterIndex charIndex: Int) -> UIImage? {
        return computeCheckboxImage(size: imageBounds.size)
    }

    private nonisolated func checkboxMetrics(for lineFrag: CGRect) -> (side: CGFloat, baselineOffset: CGFloat) {
        // Default values roughly match previous fixed sizing
        let defaultSide: CGFloat = 20
        let defaultOffset: CGFloat = -4

        if let fontPointSize {
            // Scale relative to stored point size; keep a cushion to look like a square glyph
            let side = round(max(14, min(fontPointSize * 1.05, 34)))
            let offset = -side * 0.2
            return (side, offset)
        }

        // Use the proposed line fragment height as a proxy for the current font size.
        // This avoids touching layout/text storage that may be incompatible with legacy notes.
        if lineFrag.height > 0 {
            let side = round(max(14, min(lineFrag.height, 28)))
            let offset = -side * 0.2  // keep similar visual baseline as before
            return (side, offset)
        }

        return (defaultSide, defaultOffset)
    }

    // Override attachmentBounds to control the size and vertical alignment
    nonisolated override func attachmentBounds(for textContainer: NSTextContainer?, proposedLineFragment lineFrag: CGRect, glyphPosition position: CGPoint, characterIndex charIndex: Int) -> CGRect {
        let metrics = checkboxMetrics(for: lineFrag)
        return CGRect(x: 0, y: metrics.baselineOffset, width: metrics.side, height: metrics.side)
    }
}

#elseif canImport(AppKit)
import AppKit

class CheckboxTextAttachment: NSTextAttachment {
    nonisolated override static var supportsSecureCoding: Bool { return true }

    nonisolated(unsafe) var checkboxID: String
    nonisolated(unsafe) var isChecked: Bool
    nonisolated(unsafe) var fontPointSize: CGFloat?

    init(checkboxID: String, isChecked: Bool, fontPointSize: CGFloat? = nil) {
        self.checkboxID = checkboxID
        self.isChecked = isChecked
        self.fontPointSize = fontPointSize

        // Store state as data so it survives serialization
        let stateDict: [String: Any] = [
            "checkboxID": checkboxID,
            "isChecked": isChecked,
            "fontPointSize": fontPointSize as Any
        ]
        let stateData = try? JSONSerialization.data(withJSONObject: stateDict)

        super.init(data: stateData, ofType: "com.betternotes.checkbox")
    }

    nonisolated override init(data contentData: Data?, ofType uti: String?) {

        // Try to decode checkbox state from the data
        if let data = contentData,
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let id = dict["checkboxID"] as? String,
           let checked = dict["isChecked"] as? Bool {
            self.checkboxID = id
            self.isChecked = checked
            self.fontPointSize = dict["fontPointSize"] as? CGFloat
        } else {
            self.checkboxID = UUID().uuidString
            self.isChecked = false
            self.fontPointSize = nil
        }

        super.init(data: contentData, ofType: uti)
    }

    nonisolated required init?(coder: NSCoder) {
        // Decode our custom properties
        self.checkboxID = coder.decodeObject(of: NSString.self, forKey: "checkboxID") as String? ?? UUID().uuidString
        self.isChecked = coder.decodeBool(forKey: "isChecked")
        if let decodedNumber = coder.decodeObject(of: NSNumber.self, forKey: "fontPointSize") {
            let value = CGFloat(decodedNumber.doubleValue)
            self.fontPointSize = value > 0 ? value : nil
        } else {
            self.fontPointSize = nil
        }


        // Create state data to pass to super
        let stateDict: [String: Any] = [
            "checkboxID": checkboxID,
            "isChecked": isChecked,
            "fontPointSize": fontPointSize as Any
        ]
        let stateData = try? JSONSerialization.data(withJSONObject: stateDict)

        // Initialize with our data instead of letting super.init(coder:) call init(data:ofType:) with nil
        super.init(data: stateData, ofType: "com.betternotes.checkbox")
    }

    nonisolated override func encode(with coder: NSCoder) {
        // Encode our custom properties first
        coder.encode(checkboxID as NSString, forKey: "checkboxID")
        coder.encode(isChecked, forKey: "isChecked")
        if let size = fontPointSize {
            coder.encode(NSNumber(value: Double(size)), forKey: "fontPointSize")
        }

        // Store state as data
        let stateDict: [String: Any] = [
            "checkboxID": checkboxID,
            "isChecked": isChecked,
            "fontPointSize": fontPointSize as Any
        ]
        if let stateData = try? JSONSerialization.data(withJSONObject: stateDict) {
            contents = stateData
        }

        // Temporarily clear the image before encoding to avoid CGImage errors
        let tempImage = image
        image = nil

        // Call super.encode - the image is nil so it won't try to encode it
        super.encode(with: coder)

        // Restore the image after encoding
        image = tempImage
    }

    nonisolated override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? CheckboxTextAttachment else {
            return super.isEqual(object)
        }
        // Two checkboxes are equal if they have the same ID and checked state
        return self.checkboxID == other.checkboxID && self.isChecked == other.isChecked
    }

    nonisolated override var hash: Int {
        // Hash based on checkboxID and isChecked state
        var hasher = Hasher()
        hasher.combine(checkboxID)
        hasher.combine(isChecked)
        return hasher.finalize()
    }

    // Compute checkbox image on-demand without storing
    private nonisolated func computeCheckboxImage(size: NSSize) -> NSImage? {
        let systemName = isChecked ? "checkmark.square.fill" : "square"
        let scale: CGFloat = 2.0  // Use 2x resolution for retina displays


        // Create a proper bitmap image with actual pixel data at 2x resolution
        if let symbolImage = NSImage(systemSymbolName: systemName, accessibilityDescription: nil) {
            // Create a bitmap representation at 2x resolution
            let snappedSide = max(10, floor(size.width))
            let pixelSize = NSSize(width: snappedSide * scale, height: snappedSide * scale)
            let bitmapRep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(pixelSize.width),
                pixelsHigh: Int(pixelSize.height),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )!

            // Set the size in points (not pixels) for proper scaling
            bitmapRep.size = size

            // Draw into the bitmap context
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)

            NSColor.clear.setFill()
            NSRect(origin: .zero, size: size).fill()

            // Draw the symbol as a template, then colorize it with adaptive label color
            symbolImage.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1.0)

            // Apply the adaptive label color using source-in compositing
            NSColor.labelColor.setFill()
            NSRect(origin: .zero, size: size).fill(using: .sourceIn)

            NSGraphicsContext.restoreGraphicsState()

            // Create final image with the bitmap rep
            let finalImage = NSImage(size: size)
            // Clear any existing representations
            finalImage.representations.forEach { finalImage.removeRepresentation($0) }
            finalImage.addRepresentation(bitmapRep)
            // Ensure the image is not cached incorrectly
            finalImage.cacheMode = .never

            return finalImage
        } else {
            return nil
        }
    }

    // Override to provide image during layout - compute on-demand
    nonisolated override func image(forBounds imageBounds: NSRect, textContainer: NSTextContainer?, characterIndex charIndex: Int) -> NSImage? {
        return computeCheckboxImage(size: imageBounds.size)
    }

    private nonisolated func checkboxMetrics(for lineFrag: NSRect) -> (side: CGFloat, baselineOffset: CGFloat) {
        // Defaults mirror the previous fixed sizing
        let defaultSide: CGFloat = 15
        let defaultOffset: CGFloat = -2

        if let fontPointSize {
            let side = round(max(12, min(fontPointSize * 1.05, 32)))
            let offset = -side * 0.15
            return (side, offset)
        }

        if lineFrag.height > 0 {
            let side = round(max(12, min(lineFrag.height, 26)))
            let offset = -side * 0.15  // roughly aligns like the previous -2 on 15pt
            return (side, offset)
        }

        return (defaultSide, defaultOffset)
    }

    // Override attachmentBounds to control the size and vertical alignment
    nonisolated override func attachmentBounds(for textContainer: NSTextContainer?, proposedLineFragment lineFrag: NSRect, glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        let metrics = checkboxMetrics(for: lineFrag)
        return NSRect(x: 0, y: metrics.baselineOffset, width: metrics.side, height: metrics.side)
    }
}

#endif
