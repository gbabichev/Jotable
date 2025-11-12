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

    init(checkboxID: String, isChecked: Bool) {
        self.checkboxID = checkboxID
        self.isChecked = isChecked

        // Store state as data so it survives serialization
        let stateDict: [String: Any] = ["checkboxID": checkboxID, "isChecked": isChecked]
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
        } else {
            self.checkboxID = UUID().uuidString
            self.isChecked = false
        }

        super.init(data: contentData, ofType: uti)
    }

    nonisolated required init?(coder: NSCoder) {
        // Decode our custom properties
        self.checkboxID = coder.decodeObject(of: NSString.self, forKey: "checkboxID") as String? ?? UUID().uuidString
        self.isChecked = coder.decodeBool(forKey: "isChecked")


        // Create state data to pass to super
        let stateDict: [String: Any] = ["checkboxID": checkboxID, "isChecked": isChecked]
        let stateData = try? JSONSerialization.data(withJSONObject: stateDict)

        // Initialize with our data instead of letting super.init(coder:) call init(data:ofType:) with nil
        super.init(data: stateData, ofType: "com.betternotes.checkbox")
    }

    nonisolated override func encode(with coder: NSCoder) {
        // Encode our custom properties first
        coder.encode(checkboxID as NSString, forKey: "checkboxID")
        coder.encode(isChecked, forKey: "isChecked")

        // Store state as data
        let stateDict: [String: Any] = ["checkboxID": checkboxID, "isChecked": isChecked]
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

        // Create the symbol image with proper configuration and adaptive color
        let config = UIImage.SymbolConfiguration(pointSize: size.width - 2, weight: .regular, scale: .medium)
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

    // Override attachmentBounds to control the size and vertical alignment
    nonisolated override func attachmentBounds(for textContainer: NSTextContainer?, proposedLineFragment lineFrag: CGRect, glyphPosition position: CGPoint, characterIndex charIndex: Int) -> CGRect {
        // Use a fixed checkbox size that's consistent and visible
        let checkboxSize: CGFloat = 20

        // Align to the baseline - negative offset moves it down
        let verticalOffset: CGFloat = -4

        return CGRect(x: 0, y: verticalOffset, width: checkboxSize, height: checkboxSize)
    }
}

#elseif canImport(AppKit)
import AppKit

class CheckboxTextAttachment: NSTextAttachment {
    nonisolated override static var supportsSecureCoding: Bool { return true }

    nonisolated(unsafe) var checkboxID: String
    nonisolated(unsafe) var isChecked: Bool

    init(checkboxID: String, isChecked: Bool) {
        self.checkboxID = checkboxID
        self.isChecked = isChecked

        // Store state as data so it survives serialization
        let stateDict: [String: Any] = ["checkboxID": checkboxID, "isChecked": isChecked]
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
        } else {
            self.checkboxID = UUID().uuidString
            self.isChecked = false
        }

        super.init(data: contentData, ofType: uti)
    }

    nonisolated required init?(coder: NSCoder) {
        // Decode our custom properties
        self.checkboxID = coder.decodeObject(of: NSString.self, forKey: "checkboxID") as String? ?? UUID().uuidString
        self.isChecked = coder.decodeBool(forKey: "isChecked")


        // Create state data to pass to super
        let stateDict: [String: Any] = ["checkboxID": checkboxID, "isChecked": isChecked]
        let stateData = try? JSONSerialization.data(withJSONObject: stateDict)

        // Initialize with our data instead of letting super.init(coder:) call init(data:ofType:) with nil
        super.init(data: stateData, ofType: "com.betternotes.checkbox")
    }

    nonisolated override func encode(with coder: NSCoder) {
        // Encode our custom properties first
        coder.encode(checkboxID as NSString, forKey: "checkboxID")
        coder.encode(isChecked, forKey: "isChecked")

        // Store state as data
        let stateDict: [String: Any] = ["checkboxID": checkboxID, "isChecked": isChecked]
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
    private nonisolated func computeCheckboxImage(size: NSSize) -> NSImage? {
        let systemName = isChecked ? "checkmark.square.fill" : "square"
        let scale: CGFloat = 2.0  // Use 2x resolution for retina displays


        // Create a proper bitmap image with actual pixel data at 2x resolution
        if let symbolImage = NSImage(systemSymbolName: systemName, accessibilityDescription: nil) {
            // Create a bitmap representation at 2x resolution
            let pixelSize = NSSize(width: size.width * scale, height: size.height * scale)
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

    // Override attachmentBounds to control the size and vertical alignment
    nonisolated override func attachmentBounds(for textContainer: NSTextContainer?, proposedLineFragment lineFrag: NSRect, glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        // Use a fixed checkbox size that's consistent and visible
        let checkboxSize: CGFloat = 15

        // Align to the baseline - negative offset moves it down
        let verticalOffset: CGFloat = -2

        return NSRect(x: 0, y: verticalOffset, width: checkboxSize, height: checkboxSize)
    }
}

#endif
