//
//  ResizableImageAttachment.swift
//  Jotable
//
//  Custom text attachment for resizable images with drag handles
//

import Foundation

enum ImageAttachmentPasteboard {
    private struct Payload: Codable {
        let imageID: String
        let imageData: Data
        let customWidth: Double?
        let customHeight: Double?
    }

    static let attachmentType = "com.georgebabichev.jotable.resizable-image-attachment"

    static func archivedData(for attachment: ResizableImageAttachment) -> Data? {
        #if canImport(AppKit)
        guard let image = attachment.originalImage ?? attachment.image,
              let imageData = image.tiffRepresentation else {
            return nil
        }

        let payload = Payload(
            imageID: attachment.imageID,
            imageData: imageData,
            customWidth: attachment.customSize.map { Double($0.width) },
            customHeight: attachment.customSize.map { Double($0.height) }
        )
        #else
        guard let image = attachment.originalImage ?? attachment.image,
              let imageData = image.pngData() else {
            return nil
        }

        let payload = Payload(
            imageID: attachment.imageID,
            imageData: imageData,
            customWidth: attachment.customSize.map { Double($0.width) },
            customHeight: attachment.customSize.map { Double($0.height) }
        )
        #endif

        return try? JSONEncoder().encode(payload)
    }

    static func attachment(from data: Data) -> ResizableImageAttachment? {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return nil
        }

        #if canImport(AppKit)
        guard let image = NSImage(data: payload.imageData) else {
            return nil
        }

        let customSize = payload.customWidth.flatMap { width in
            payload.customHeight.map { height in
                NSSize(width: CGFloat(width), height: CGFloat(height))
            }
        } ?? ResizableImageAttachment.fittedDisplaySize(for: image.size)

        return ResizableImageAttachment(
            image: image,
            imageID: payload.imageID,
            customSize: customSize
        )
        #else
        guard let image = UIImage(data: payload.imageData) else {
            return nil
        }

        let customSize = payload.customWidth.flatMap { width in
            payload.customHeight.map { height in
                CGSize(width: CGFloat(width), height: CGFloat(height))
            }
        } ?? ResizableImageAttachment.fittedDisplaySize(for: image.size)

        return ResizableImageAttachment(
            image: image,
            imageID: payload.imageID,
            customSize: customSize
        )
        #endif
    }
}

#if canImport(AppKit)
import AppKit

class ResizableImageAttachment: NSTextAttachment {
    nonisolated override static var supportsSecureCoding: Bool { return true }
    nonisolated static let minimumDisplayWidth: CGFloat = 80
    nonisolated static let maximumDisplayWidth: CGFloat = 640
    nonisolated static let maximumDisplayHeight: CGFloat = 640

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

    nonisolated func preferredDisplaySize(maxWidth: CGFloat? = nil) -> NSSize {
        guard let img = originalImage ?? image else {
            return NSSize(width: 100, height: 100)
        }

        return Self.fittedSize(
            for: img.size,
            maxWidth: Self.effectiveMaximumWidth(using: maxWidth),
            maxHeight: Self.maximumDisplayHeight
        )
    }

    nonisolated static func fittedDisplaySize(for imageSize: NSSize, maxWidth: CGFloat? = nil) -> NSSize {
        Self.fittedSize(
            for: imageSize,
            maxWidth: Self.effectiveMaximumWidth(using: maxWidth),
            maxHeight: Self.maximumDisplayHeight
        )
    }

    nonisolated func resizedDisplaySize(for proposedWidth: CGFloat, maxWidth: CGFloat? = nil) -> NSSize {
        guard let img = originalImage ?? image else {
            let fallbackWidth = max(Self.minimumDisplayWidth, proposedWidth)
            return NSSize(width: fallbackWidth, height: fallbackWidth)
        }

        let boundedWidth = min(max(Self.minimumDisplayWidth, proposedWidth), Self.effectiveMaximumWidth(using: maxWidth))
        let aspectRatio = img.size.height / max(img.size.width, 1)
        let proposedSize = NSSize(width: boundedWidth, height: boundedWidth * aspectRatio)

        return Self.fittedSize(
            for: proposedSize,
            maxWidth: Self.effectiveMaximumWidth(using: maxWidth),
            maxHeight: Self.maximumDisplayHeight
        )
    }

    nonisolated override func attachmentBounds(for textContainer: NSTextContainer?,
                                              proposedLineFragment lineFrag: NSRect,
                                              glyphPosition position: NSPoint,
                                              characterIndex charIndex: Int) -> NSRect {
        let availableWidth = textContainer.map {
            max(Self.minimumDisplayWidth, $0.size.width - ($0.lineFragmentPadding * 2))
        }
        let size = customSize.map { Self.fittedSize(for: $0, maxWidth: Self.effectiveMaximumWidth(using: availableWidth), maxHeight: Self.maximumDisplayHeight) }
            ?? preferredDisplaySize(maxWidth: availableWidth)
        return NSRect(origin: .zero, size: size)
    }

    private nonisolated static func effectiveMaximumWidth(using proposedWidth: CGFloat?) -> CGFloat {
        let fallback = Self.maximumDisplayWidth
        guard let proposedWidth else { return fallback }
        return max(Self.minimumDisplayWidth, min(Self.maximumDisplayWidth, proposedWidth))
    }

    private nonisolated static func fittedSize(for size: NSSize, maxWidth: CGFloat, maxHeight: CGFloat) -> NSSize {
        let safeWidth = max(size.width, 1)
        let safeHeight = max(size.height, 1)
        var width = safeWidth
        var height = safeHeight

        let widthRatio = maxWidth / safeWidth
        let heightRatio = maxHeight / safeHeight
        let downscaleRatio = min(widthRatio, heightRatio, 1)
        width *= downscaleRatio
        height *= downscaleRatio

        if width < Self.minimumDisplayWidth {
            let upscaleRatio = Self.minimumDisplayWidth / width
            width *= upscaleRatio
            height *= upscaleRatio
        }

        if height > maxHeight {
            let finalRatio = maxHeight / height
            width *= finalRatio
            height *= finalRatio
        }

        return NSSize(width: width, height: height)
    }
}

#elseif canImport(UIKit)
import UIKit

class ResizableImageAttachment: NSTextAttachment {
    nonisolated override static var supportsSecureCoding: Bool { return true }
    nonisolated static let minimumDisplayWidth: CGFloat = 80
    nonisolated static let maximumDisplayWidth: CGFloat = 640
    nonisolated static let maximumDisplayHeight: CGFloat = 640

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

    nonisolated func preferredDisplaySize(maxWidth: CGFloat? = nil) -> CGSize {
        guard let img = originalImage ?? image else {
            return CGSize(width: 100, height: 100)
        }

        return Self.fittedSize(
            for: img.size,
            maxWidth: Self.effectiveMaximumWidth(using: maxWidth),
            maxHeight: Self.maximumDisplayHeight
        )
    }

    nonisolated static func fittedDisplaySize(for imageSize: CGSize, maxWidth: CGFloat? = nil) -> CGSize {
        Self.fittedSize(
            for: imageSize,
            maxWidth: Self.effectiveMaximumWidth(using: maxWidth),
            maxHeight: Self.maximumDisplayHeight
        )
    }

    nonisolated func resizedDisplaySize(for proposedWidth: CGFloat, maxWidth: CGFloat? = nil) -> CGSize {
        guard let img = originalImage ?? image else {
            let fallbackWidth = max(Self.minimumDisplayWidth, proposedWidth)
            return CGSize(width: fallbackWidth, height: fallbackWidth)
        }

        let boundedWidth = min(max(Self.minimumDisplayWidth, proposedWidth), Self.effectiveMaximumWidth(using: maxWidth))
        let aspectRatio = img.size.height / max(img.size.width, 1)
        let proposedSize = CGSize(width: boundedWidth, height: boundedWidth * aspectRatio)

        return Self.fittedSize(
            for: proposedSize,
            maxWidth: Self.effectiveMaximumWidth(using: maxWidth),
            maxHeight: Self.maximumDisplayHeight
        )
    }

    nonisolated override func attachmentBounds(for textContainer: NSTextContainer?,
                                              proposedLineFragment lineFrag: CGRect,
                                              glyphPosition position: CGPoint,
                                              characterIndex charIndex: Int) -> CGRect {
        let availableWidth = textContainer.map {
            max(Self.minimumDisplayWidth, $0.size.width - ($0.lineFragmentPadding * 2))
        }
        let size = customSize.map { Self.fittedSize(for: $0, maxWidth: Self.effectiveMaximumWidth(using: availableWidth), maxHeight: Self.maximumDisplayHeight) }
            ?? preferredDisplaySize(maxWidth: availableWidth)
        return CGRect(origin: .zero, size: size)
    }

    private nonisolated static func effectiveMaximumWidth(using proposedWidth: CGFloat?) -> CGFloat {
        let fallback = Self.maximumDisplayWidth
        guard let proposedWidth else { return fallback }
        return max(Self.minimumDisplayWidth, min(Self.maximumDisplayWidth, proposedWidth))
    }

    private nonisolated static func fittedSize(for size: CGSize, maxWidth: CGFloat, maxHeight: CGFloat) -> CGSize {
        let safeWidth = max(size.width, 1)
        let safeHeight = max(size.height, 1)
        var width = safeWidth
        var height = safeHeight

        let widthRatio = maxWidth / safeWidth
        let heightRatio = maxHeight / safeHeight
        let downscaleRatio = min(widthRatio, heightRatio, 1)
        width *= downscaleRatio
        height *= downscaleRatio

        if width < Self.minimumDisplayWidth {
            let upscaleRatio = Self.minimumDisplayWidth / width
            width *= upscaleRatio
            height *= upscaleRatio
        }

        if height > maxHeight {
            let finalRatio = maxHeight / height
            width *= finalRatio
            height *= finalRatio
        }

        return CGSize(width: width, height: height)
    }
}

#endif
