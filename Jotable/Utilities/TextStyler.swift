import Foundation
import SwiftUI

#if os(macOS)
import AppKit
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
#else
import UIKit
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
#endif

/// Universal text styling struct that works across iOS and macOS
/// Eliminates platform-specific branching for font and text attribute handling
struct TextStyler: Equatable {
    let isBold: Bool
    let isItalic: Bool
    let fontSize: FontSize
    let colorID: String?
    let color: PlatformColor?
    let highlightID: String?
    let highlight: PlatformColor?
    let isUnderlined: Bool
    let isStrikethrough: Bool

    // MARK: - Initialization

    init(
        isBold: Bool = false,
        isItalic: Bool = false,
        fontSize: FontSize = .normal,
        colorID: String? = nil,
        color: PlatformColor? = nil,
        highlightID: String? = nil,
        highlight: PlatformColor? = nil,
        isUnderlined: Bool = false,
        isStrikethrough: Bool = false
    ) {
        self.isBold = isBold
        self.isItalic = isItalic
        self.fontSize = fontSize
        self.colorID = colorID
        self.color = color
        self.highlightID = highlightID
        self.highlight = highlight
        self.isUnderlined = isUnderlined
        self.isStrikethrough = isStrikethrough
    }

    // MARK: - Font Building (Platform-Agnostic)

    /// Builds a platform font from current styling state
    func buildFont() -> PlatformFont {
        let weight: PlatformFont.Weight = isBold ? .bold : .regular
        var font = PlatformFont.systemFont(ofSize: fontSize.rawValue, weight: weight)

        // Build symbolic traits for combined bold + italic
        #if os(macOS)
        var traits: NSFontDescriptor.SymbolicTraits = isBold ? .bold : []
        if isItalic {
            traits.insert(.italic)
        }

        if !traits.isEmpty {
            let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
            font = NSFont(descriptor: descriptor, size: fontSize.rawValue) ?? font
        }
        #else
        var traits: UIFontDescriptor.SymbolicTraits = isBold ? .traitBold : []
        if isItalic {
            traits.insert(.traitItalic)
        }

        if !traits.isEmpty {
            if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
                font = UIFont(descriptor: descriptor, size: fontSize.rawValue)
            }
        }
        #endif

        return font
    }

    // MARK: - Attribute Building

    /// Builds complete typing attributes dictionary from current state
    func buildAttributes(
        usingAutomatic: Bool = false,
        customColor: PlatformColor? = nil
    ) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [:]

        // Font
        attrs[NSAttributedString.Key.font] = buildFont()
        attrs[ColorMapping.fontSizeKey] = fontSize.rawValue

        // Color
        if usingAutomatic {
            #if os(macOS)
            attrs[NSAttributedString.Key.foregroundColor] = NSColor.labelColor
            #else
            attrs[NSAttributedString.Key.foregroundColor] = UIColor.label
            #endif
            attrs[ColorMapping.colorIDKey] = RichTextColor.automatic.id
        } else if let customColor = customColor {
            attrs[NSAttributedString.Key.foregroundColor] = customColor
            let identifier = ColorMapping.identifier(for: customColor, preferPaletteMatch: false)
            attrs[ColorMapping.colorIDKey] = identifier
        } else if let color = color {
            attrs[NSAttributedString.Key.foregroundColor] = color
            if let colorID = colorID {
                attrs[ColorMapping.colorIDKey] = colorID
            }
        }

        // Underline and strikethrough
        attrs[NSAttributedString.Key.underlineStyle] = isUnderlined ? NSUnderlineStyle.single.rawValue : 0
        attrs[NSAttributedString.Key.strikethroughStyle] = isStrikethrough ? NSUnderlineStyle.single.rawValue : 0

        // Highlight
        if let highlight = highlight, let highlightID = highlightID {
            attrs[NSAttributedString.Key.backgroundColor] = highlight
            attrs[ColorMapping.highlightIDKey] = highlightID
        }

        return attrs
    }

}
