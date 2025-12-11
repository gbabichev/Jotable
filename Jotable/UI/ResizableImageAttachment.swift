//
//  ResizableImageAttachment.swift
//  Jotable
//
//  Custom text attachment for resizable images with drag handles
//

import Foundation

#if canImport(AppKit)
import AppKit

class ResizableImageAttachment: NSTextAttachment {
    nonisolated override static var supportsSecureCoding: Bool { return true }

    nonisolated(unsafe) var imageID: String
    nonisolated(unsafe) var customSize: NSSize?
    nonisolated(unsafe) var originalImage: NSImage?

    init(image: NSImage, imageID: String = UUID().uuidString, customSize: NSSize? = nil) {
        self.imageID = imageID
        self.originalImage = image
        self.customSize = customSize

        // Store image data for serialization
        if let tiffData = image.tiffRepresentation {
            super.init(data: tiffData, ofType: "public.tiff")
        } else {
            super.init(data: nil, ofType: nil)
        }

        self.image = image
    }

    nonisolated override init(data contentData: Data?, ofType uti: String?) {
        if let data = contentData, let image = NSImage(data: data) {
            self.originalImage = image
        } else {
            self.originalImage = nil
        }
        self.imageID = UUID().uuidString
        self.customSize = nil

        super.init(data: contentData, ofType: uti)
    }

    nonisolated required init?(coder: NSCoder) {
        self.imageID = coder.decodeObject(of: NSString.self, forKey: "imageID") as String? ?? UUID().uuidString

        if let widthNumber = coder.decodeObject(of: NSNumber.self, forKey: "customWidth"),
           let heightNumber = coder.decodeObject(of: NSNumber.self, forKey: "customHeight") {
            self.customSize = NSSize(width: CGFloat(widthNumber.doubleValue),
                                    height: CGFloat(heightNumber.doubleValue))
        } else {
            self.customSize = nil
        }

        if let imageData = coder.decodeObject(of: NSData.self, forKey: "imageData") as Data?,
           let image = NSImage(data: imageData) {
            self.originalImage = image
        } else {
            self.originalImage = nil
        }

        super.init(data: nil, ofType: nil)

        if let img = originalImage {
            self.image = img
        }
    }

    nonisolated override func encode(with coder: NSCoder) {
        coder.encode(imageID as NSString, forKey: "imageID")

        if let size = customSize {
            coder.encode(NSNumber(value: Double(size.width)), forKey: "customWidth")
            coder.encode(NSNumber(value: Double(size.height)), forKey: "customHeight")
        }

        if let img = originalImage ?? image, let tiffData = img.tiffRepresentation {
            coder.encode(tiffData as NSData, forKey: "imageData")
        }

        let tempImage = image
        image = nil
        super.encode(with: coder)
        image = tempImage
    }

    nonisolated override func attachmentBounds(for textContainer: NSTextContainer?,
                                              proposedLineFragment lineFrag: NSRect,
                                              glyphPosition position: NSPoint,
                                              characterIndex charIndex: Int) -> NSRect {
        guard let img = originalImage ?? image else {
            return NSRect(x: 0, y: 0, width: 100, height: 100)
        }

        let imageSize = img.size

        // Use custom size if set, otherwise calculate a reasonable default
        if let customSize = customSize {
            return NSRect(x: 0, y: 0, width: customSize.width, height: customSize.height)
        }

        // Default: scale image to fit width with max dimensions
        let maxWidth: CGFloat = 400
        let maxHeight: CGFloat = 400

        var width = imageSize.width
        var height = imageSize.height

        if width > maxWidth || height > maxHeight {
            let widthRatio = maxWidth / width
            let heightRatio = maxHeight / height
            let ratio = min(widthRatio, heightRatio)

            width = width * ratio
            height = height * ratio
        }

        return NSRect(x: 0, y: 0, width: width, height: height)
    }
}

// Custom view provider to add resize handles
@available(macOS 11.0, *)
class ResizableImageView: NSView {
    var attachment: ResizableImageAttachment
    var onResize: ((NSSize) -> Void)?

    private var imageView: NSImageView!
    private var isDragging = false
    private var dragStartPoint: NSPoint = .zero
    private var dragStartSize: NSSize = .zero
    private let handleSize: CGFloat = 12

    init(attachment: ResizableImageAttachment, frame: NSRect) {
        self.attachment = attachment
        super.init(frame: frame)
        setupImageView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupImageView() {
        imageView = NSImageView(frame: bounds)
        imageView.image = attachment.originalImage ?? attachment.image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.autoresizingMask = [.width, .height]
        addSubview(imageView)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Draw resize handle in bottom-right corner
        let handleRect = NSRect(x: bounds.width - handleSize,
                               y: 0,
                               width: handleSize,
                               height: handleSize)

        NSColor.controlAccentColor.withAlphaComponent(0.7).setFill()
        let path = NSBezierPath(roundedRect: handleRect, xRadius: 2, yRadius: 2)
        path.fill()

        // Draw grip lines
        NSColor.white.setStroke()
        let line1 = NSBezierPath()
        line1.move(to: NSPoint(x: handleRect.maxX - 3, y: handleRect.minY + 3))
        line1.line(to: NSPoint(x: handleRect.maxX - 3, y: handleRect.maxY - 3))
        line1.lineWidth = 1
        line1.stroke()

        let line2 = NSBezierPath()
        line2.move(to: NSPoint(x: handleRect.maxX - 6, y: handleRect.minY + 3))
        line2.line(to: NSPoint(x: handleRect.maxX - 6, y: handleRect.maxY - 3))
        line2.lineWidth = 1
        line2.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        let handleRect = NSRect(x: bounds.width - handleSize,
                               y: 0,
                               width: handleSize,
                               height: handleSize)

        if handleRect.contains(localPoint) {
            isDragging = true
            dragStartPoint = event.locationInWindow
            dragStartSize = bounds.size
        } else {
            super.mouseDown(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else {
            super.mouseDragged(with: event)
            return
        }

        let currentPoint = event.locationInWindow
        let delta = NSPoint(x: currentPoint.x - dragStartPoint.x,
                           y: currentPoint.y - dragStartPoint.y)

        // Calculate new size (width changes with horizontal drag, maintain aspect ratio)
        let newWidth = max(50, dragStartSize.width + delta.x)

        // Maintain aspect ratio
        guard let img = attachment.originalImage ?? attachment.image else { return }
        let aspectRatio = img.size.height / img.size.width
        let newHeight = newWidth * aspectRatio

        let newSize = NSSize(width: newWidth, height: newHeight)
        attachment.customSize = newSize

        // Update frame
        var newFrame = frame
        newFrame.size = newSize
        frame = newFrame

        onResize?(newSize)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            isDragging = false
        } else {
            super.mouseUp(with: event)
        }
    }

    override func resetCursorRects() {
        let handleRect = NSRect(x: bounds.width - handleSize,
                               y: 0,
                               width: handleSize,
                               height: handleSize)
        addCursorRect(handleRect, cursor: NSCursor.crosshair)
    }
}

#elseif canImport(UIKit)
import UIKit

class ResizableImageAttachment: NSTextAttachment {
    nonisolated override static var supportsSecureCoding: Bool { return true }

    nonisolated(unsafe) var imageID: String
    nonisolated(unsafe) var customSize: CGSize?
    nonisolated(unsafe) var originalImage: UIImage?

    init(image: UIImage, imageID: String = UUID().uuidString, customSize: CGSize? = nil) {
        self.imageID = imageID
        self.originalImage = image
        self.customSize = customSize

        // Store image data for serialization
        if let pngData = image.pngData() {
            super.init(data: pngData, ofType: "public.png")
        } else {
            super.init(data: nil, ofType: nil)
        }

        self.image = image
    }

    nonisolated override init(data contentData: Data?, ofType uti: String?) {
        if let data = contentData, let image = UIImage(data: data) {
            self.originalImage = image
        } else {
            self.originalImage = nil
        }
        self.imageID = UUID().uuidString
        self.customSize = nil

        super.init(data: contentData, ofType: uti)
    }

    nonisolated required init?(coder: NSCoder) {
        self.imageID = coder.decodeObject(of: NSString.self, forKey: "imageID") as String? ?? UUID().uuidString

        if let widthNumber = coder.decodeObject(of: NSNumber.self, forKey: "customWidth"),
           let heightNumber = coder.decodeObject(of: NSNumber.self, forKey: "customHeight") {
            self.customSize = CGSize(width: CGFloat(widthNumber.doubleValue),
                                    height: CGFloat(heightNumber.doubleValue))
        } else {
            self.customSize = nil
        }

        if let imageData = coder.decodeObject(of: NSData.self, forKey: "imageData") as Data?,
           let image = UIImage(data: imageData) {
            self.originalImage = image
        } else {
            self.originalImage = nil
        }

        super.init(data: nil, ofType: nil)

        if let img = originalImage {
            self.image = img
        }
    }

    nonisolated override func encode(with coder: NSCoder) {
        coder.encode(imageID as NSString, forKey: "imageID")

        if let size = customSize {
            coder.encode(NSNumber(value: Double(size.width)), forKey: "customWidth")
            coder.encode(NSNumber(value: Double(size.height)), forKey: "customHeight")
        }

        if let img = originalImage ?? image, let pngData = img.pngData() {
            coder.encode(pngData as NSData, forKey: "imageData")
        }

        let tempImage = image
        image = nil
        super.encode(with: coder)
        image = tempImage
    }

    nonisolated override func attachmentBounds(for textContainer: NSTextContainer?,
                                              proposedLineFragment lineFrag: CGRect,
                                              glyphPosition position: CGPoint,
                                              characterIndex charIndex: Int) -> CGRect {
        guard let img = originalImage ?? image else {
            return CGRect(x: 0, y: 0, width: 100, height: 100)
        }

        let imageSize = img.size

        // Use custom size if set, otherwise calculate a reasonable default
        if let customSize = customSize {
            return CGRect(x: 0, y: 0, width: customSize.width, height: customSize.height)
        }

        // Default: scale image to fit width with max dimensions
        let maxWidth: CGFloat = 400
        let maxHeight: CGFloat = 400

        var width = imageSize.width
        var height = imageSize.height

        if width > maxWidth || height > maxHeight {
            let widthRatio = maxWidth / width
            let heightRatio = maxHeight / height
            let ratio = min(widthRatio, heightRatio)

            width = width * ratio
            height = height * ratio
        }

        return CGRect(x: 0, y: 0, width: width, height: height)
    }
}

#endif
