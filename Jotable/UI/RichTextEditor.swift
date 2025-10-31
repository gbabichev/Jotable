import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum FontSize: CGFloat, Equatable, Identifiable, CaseIterable {
    case small = 12
    case normal = 16
    case large = 18
    case extraLarge = 20
    case huge = 24

    var id: CGFloat { self.rawValue }

    var displayName: String {
        switch self {
        case .small: return "Small (12pt)"
        case .normal: return "Normal (16pt)"
        case .large: return "Large (18pt)"
        case .extraLarge: return "Extra Large (20pt)"
        case .huge: return "Huge (24pt)"
        }
    }
}

enum RichTextColor: Equatable, Identifiable {
    case automatic
    case red
    case green
    case orange
    case yellow
    case purple
    case blue

    var id: String {
        switch self {
        case .automatic: return "automatic"
        case .red: return "red"
        case .green: return "green"
        case .orange: return "orange"
        case .yellow: return "yellow"
        case .purple: return "purple"
        case .blue: return "blue"
        }
    }

    var emoji: String {
        switch self {
        case .automatic: return "⚫"
        case .red: return "🔴"
        case .green: return "🟢"
        case .orange: return "🟠"
        case .yellow: return "🟡"
        case .purple: return "🟣"
        case .blue: return "🔵"
        }
    }

    #if os(macOS)
    var nsColor: NSColor {
        switch self {
        case .automatic:
            return NSColor.labelColor
        case .red:
            return NSColor.systemRed
        case .green:
            return NSColor.systemGreen
        case .orange:
            return NSColor.systemOrange
        case .yellow:
            return NSColor.systemYellow
        case .purple:
            return NSColor.systemPurple
        case .blue:
            return NSColor.systemBlue
        }
    }
    #else
    var uiColor: UIColor {
        switch self {
        case .automatic:
            return UIColor.label
        case .red:
            return UIColor.systemRed
        case .green:
            return UIColor.systemGreen
        case .orange:
            return UIColor.systemOrange
        case .yellow:
            return UIColor.systemYellow
        case .purple:
            return UIColor.systemPurple
        case .blue:
            return UIColor.systemBlue
        }
    }
    #endif

    /// Initializes from a color ID string
    static func from(id: String) -> RichTextColor {
        switch id {
        case "red": return .red
        case "green": return .green
        case "orange": return .orange
        case "yellow": return .yellow
        case "purple": return .purple
        case "blue": return .blue
        default: return .automatic
        }
    }
}

#if os(macOS)

private final class DynamicColorTextView: NSTextView {
    var onAppearanceChange: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }
}

struct RichTextEditor: NSViewRepresentable {
    @Binding var text: NSAttributedString
    @Binding var activeColor: RichTextColor
    @Binding var activeFontSize: FontSize
    @Binding var isBold: Bool
    @Binding var isUnderlined: Bool
    @Binding var isStrikethrough: Bool
    @Binding var insertUncheckedCheckboxTrigger: UUID?
    @Binding var insertCheckedCheckboxTrigger: UUID?
    @Binding var insertBulletTrigger: UUID?
    @Binding var insertNumberingTrigger: UUID?
    @Binding var insertURLTrigger: (UUID, String, String)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        let textView = DynamicColorTextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.font = NSFont.systemFont(ofSize: activeFontSize.rawValue)
        textView.allowsUndo = true
        textView.typingAttributes[NSAttributedString.Key.foregroundColor] = activeColor.nsColor
        textView.typingAttributes[ColorMapping.colorIDKey] = activeColor.id
        textView.typingAttributes[NSAttributedString.Key.font] = NSFont.systemFont(ofSize: activeFontSize.rawValue)
        textView.typingAttributes[ColorMapping.fontSizeKey] = activeFontSize.rawValue
        textView.textStorage?.setAttributedString(text)

        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [NSView.AutoresizingMask.width]
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        context.coordinator.textView = textView
        textView.onAppearanceChange = { [weak coordinator = context.coordinator] in
            coordinator?.handleAppearanceChange()
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        let currentText = textView.attributedString()
        if !context.coordinator.isProgrammaticUpdate,
           !text.isEqual(to: currentText) {
            context.coordinator.isProgrammaticUpdate = true

            textView.textStorage?.setAttributedString(text)

            context.coordinator.isProgrammaticUpdate = false
        }

        if context.coordinator.activeColor != activeColor {
            context.coordinator.activeColor = activeColor
            context.coordinator.apply(color: activeColor, to: textView)
        }

        if context.coordinator.activeFontSize != activeFontSize {
            context.coordinator.activeFontSize = activeFontSize
            context.coordinator.apply(fontSize: activeFontSize, to: textView)
        }

        if context.coordinator.isBold != isBold {
            context.coordinator.isBold = isBold
            context.coordinator.toggleBold(textView)
        }

        if context.coordinator.isUnderlined != isUnderlined {
            context.coordinator.isUnderlined = isUnderlined
            context.coordinator.toggleUnderline(textView)
        }

        if context.coordinator.isStrikethrough != isStrikethrough {
            context.coordinator.isStrikethrough = isStrikethrough
            context.coordinator.toggleStrikethrough(textView)
        }

        // Handle unchecked checkbox insertion trigger
        if insertUncheckedCheckboxTrigger != context.coordinator.lastUncheckedCheckboxTrigger {
            context.coordinator.lastUncheckedCheckboxTrigger = insertUncheckedCheckboxTrigger
            context.coordinator.insertUncheckedCheckbox()
        }

        // Handle checked checkbox insertion trigger
        if insertCheckedCheckboxTrigger != context.coordinator.lastCheckedCheckboxTrigger {
            context.coordinator.lastCheckedCheckboxTrigger = insertCheckedCheckboxTrigger
            context.coordinator.insertCheckedCheckbox()
        }

        // Handle bullet insertion trigger
        if insertBulletTrigger != context.coordinator.lastBulletTrigger {
            context.coordinator.lastBulletTrigger = insertBulletTrigger
            context.coordinator.insertBullet()
        }

        // Handle numbering insertion trigger
        if insertNumberingTrigger != context.coordinator.lastNumberingTrigger {
            context.coordinator.lastNumberingTrigger = insertNumberingTrigger
            context.coordinator.insertNumbering()
        }

        // Handle URL insertion trigger
        if insertURLTrigger?.0 != context.coordinator.lastURLTrigger?.0 {
            context.coordinator.lastURLTrigger = insertURLTrigger
            if let (_, urlString, displayText) = insertURLTrigger {
                context.coordinator.insertURL(urlString: urlString, displayText: displayText)
            }
        }

        context.coordinator.handleAppearanceChange()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        var activeColor: RichTextColor
        var activeFontSize: FontSize
        var isBold: Bool
        var isUnderlined: Bool
        var isStrikethrough: Bool
        var isProgrammaticUpdate = false
        var lastUncheckedCheckboxTrigger: UUID?
        var lastCheckedCheckboxTrigger: UUID?
        var lastBulletTrigger: UUID?
        var lastNumberingTrigger: UUID?
        var lastURLTrigger: (UUID, String, String)?
        weak var textView: NSTextView?

        init(_ parent: RichTextEditor) {
            self.parent = parent
            self.activeColor = parent.activeColor
            self.activeFontSize = parent.activeFontSize
            self.isBold = parent.isBold
            self.isUnderlined = parent.isUnderlined
            self.isStrikethrough = parent.isStrikethrough
        }

        func textDidChange(_ notification: Notification) {
            guard !isProgrammaticUpdate,
                  let textView = notification.object as? NSTextView,
                  textView === self.textView else { return }

            // Convert checkbox patterns to attachments
            if let storage = textView.textStorage {
                let spaceAttrs: [NSAttributedString.Key: Any] = [
                    NSAttributedString.Key.font: NSFont.systemFont(ofSize: activeFontSize.rawValue),
                    NSAttributedString.Key.foregroundColor: activeColor.nsColor,
                    ColorMapping.colorIDKey: activeColor.id,
                    ColorMapping.fontSizeKey: activeFontSize.rawValue
                ]
                if AutoFormatting.convertCheckboxPatterns(in: storage, spaceAttributes: spaceAttrs) {
                    // Layout needs to be invalidated after replacing attachments
                }
            }

            let updatedText = textView.attributedString()
            parent.text = updatedText
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  textView === self.textView else { return }
            let font = NSFont.systemFont(ofSize: activeFontSize.rawValue, weight: isBold ? .bold : .regular)
            textView.typingAttributes[NSAttributedString.Key.font] = font
            textView.typingAttributes[NSAttributedString.Key.foregroundColor] = activeColor.nsColor
            textView.typingAttributes[ColorMapping.colorIDKey] = activeColor.id
            textView.typingAttributes[ColorMapping.fontSizeKey] = activeFontSize.rawValue

            let underlineValue = isUnderlined ? NSUnderlineStyle.single.rawValue : 0
            textView.typingAttributes[NSAttributedString.Key.underlineStyle] = underlineValue

            let strikethroughValue = isStrikethrough ? NSUnderlineStyle.single.rawValue : 0
            textView.typingAttributes[NSAttributedString.Key.strikethroughStyle] = strikethroughValue

            // Force update the parent binding to ensure color changes are captured
            if !isProgrammaticUpdate {
                let currentText = textView.attributedString()
                parent.text = currentText
            }
        }

        func apply(color: RichTextColor, to textView: NSTextView) {
            let nsColor = color.nsColor
            let selectedRange = textView.selectedRange

            if selectedRange.length > 0,
               let storage = textView.textStorage {
                isProgrammaticUpdate = true
                ColorMapping.applyColor(color, to: storage, range: selectedRange)
                textView.setSelectedRange(selectedRange)

                // Defer the binding update to avoid "Modifying state during view update" warning
                DispatchQueue.main.async { [weak self] in
                    self?.isProgrammaticUpdate = false
                    self?.parent.text = NSAttributedString(attributedString: storage)
                }
            }

            textView.typingAttributes[NSAttributedString.Key.foregroundColor] = nsColor
            textView.typingAttributes[ColorMapping.colorIDKey] = color.id
        }

        func apply(fontSize: FontSize, to textView: NSTextView) {
            let selectedRange = textView.selectedRange

            if selectedRange.length > 0,
               let storage = textView.textStorage {
                isProgrammaticUpdate = true
                let fontAttrs: [NSAttributedString.Key: Any] = [
                    NSAttributedString.Key.font: NSFont.systemFont(ofSize: fontSize.rawValue),
                    ColorMapping.fontSizeKey: fontSize.rawValue
                ]
                storage.addAttributes(fontAttrs, range: selectedRange)
                textView.setSelectedRange(selectedRange)

                // Defer the binding update to avoid "Modifying state during view update" warning
                DispatchQueue.main.async { [weak self] in
                    self?.isProgrammaticUpdate = false
                    self?.parent.text = NSAttributedString(attributedString: storage)
                }
            }

            textView.typingAttributes[NSAttributedString.Key.font] = NSFont.systemFont(ofSize: fontSize.rawValue)
            textView.typingAttributes[ColorMapping.fontSizeKey] = fontSize.rawValue
        }

        func toggleBold(_ textView: NSTextView) {
            let selectedRange = textView.selectedRange
            if selectedRange.length > 0,
               let storage = textView.textStorage {
                isProgrammaticUpdate = true

                let font = NSFont.systemFont(ofSize: activeFontSize.rawValue, weight: isBold ? .bold : .regular)
                storage.addAttribute(NSAttributedString.Key.font, value: font, range: selectedRange)
                textView.setSelectedRange(selectedRange)

                DispatchQueue.main.async { [weak self] in
                    self?.isProgrammaticUpdate = false
                    self?.parent.text = NSAttributedString(attributedString: storage)
                }
            }

            let boldFont = NSFont.systemFont(ofSize: activeFontSize.rawValue, weight: isBold ? .bold : .regular)
            textView.typingAttributes[NSAttributedString.Key.font] = boldFont
        }

        func toggleUnderline(_ textView: NSTextView) {
            let selectedRange = textView.selectedRange
            if selectedRange.length > 0,
               let storage = textView.textStorage {
                isProgrammaticUpdate = true

                let underlineValue = isUnderlined ? NSUnderlineStyle.single.rawValue : 0
                storage.addAttribute(NSAttributedString.Key.underlineStyle, value: underlineValue, range: selectedRange)
                textView.setSelectedRange(selectedRange)

                DispatchQueue.main.async { [weak self] in
                    self?.isProgrammaticUpdate = false
                    self?.parent.text = NSAttributedString(attributedString: storage)
                }
            }

            let underlineValue = isUnderlined ? NSUnderlineStyle.single.rawValue : 0
            textView.typingAttributes[NSAttributedString.Key.underlineStyle] = underlineValue
        }

        func toggleStrikethrough(_ textView: NSTextView) {
            let selectedRange = textView.selectedRange
            if selectedRange.length > 0,
               let storage = textView.textStorage {
                isProgrammaticUpdate = true

                let strikethroughValue = isStrikethrough ? NSUnderlineStyle.single.rawValue : 0
                storage.addAttribute(NSAttributedString.Key.strikethroughStyle, value: strikethroughValue, range: selectedRange)
                textView.setSelectedRange(selectedRange)

                DispatchQueue.main.async { [weak self] in
                    self?.isProgrammaticUpdate = false
                    self?.parent.text = NSAttributedString(attributedString: storage)
                }
            }

            let strikethroughValue = isStrikethrough ? NSUnderlineStyle.single.rawValue : 0
            textView.typingAttributes[NSAttributedString.Key.strikethroughStyle] = strikethroughValue
        }

        func handleAppearanceChange() {
            guard let textView = textView else { return }
            // Only update typing attributes, don't override the text view's rendering of existing text
            if activeColor == .automatic {
                textView.typingAttributes[NSAttributedString.Key.foregroundColor] = activeColor.nsColor
                textView.typingAttributes[ColorMapping.colorIDKey] = activeColor.id
            }
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Handle return key for auto-numbering
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                return handleReturnKey(textView: textView)
            }
            return false
        }

        private func handleReturnKey(textView: NSTextView) -> Bool {
            let range = textView.selectedRange
            let plainText = textView.string
            let attributedString = textView.attributedString()

            guard let lineInfo = AutoFormatting.getLineInfo(for: range, in: plainText) else {
                return false
            }

            // Check for checkbox pattern (attachments at start of line)
            if handleCheckboxLine(in: attributedString, textView: textView, at: range, lineRange: lineInfo.range) {
                return true
            }

            // Check for numbered list pattern
            if let newText = AutoFormatting.handleNumberedList(lineText: lineInfo.text) {
                return applyAutoFormat(newText, to: textView, at: range, lineRange: lineInfo.range)
            }

            // Check for bullet point pattern
            if let newText = AutoFormatting.handleBulletPoint(lineText: lineInfo.text) {
                return applyAutoFormat(newText, to: textView, at: range, lineRange: lineInfo.range)
            }

            return false
        }

        private func handleCheckboxLine(in attributedString: NSAttributedString, textView: NSTextView, at cursorRange: NSRange, lineRange: NSRange) -> Bool {
            // Find if there's a checkbox attachment at the start of the line
            guard lineRange.location < attributedString.length else { return false }

            var hasCheckboxAtStart = false
            var contentStartsAfter = lineRange.location

            // Look for attachment at the start of the line
            if attributedString.attribute(NSAttributedString.Key.attachment, at: lineRange.location, longestEffectiveRange: nil, in: lineRange) is CheckboxTextAttachment {
                hasCheckboxAtStart = true
                contentStartsAfter = lineRange.location + 1
            }

            guard hasCheckboxAtStart else { return false }

            // Check if there's content after the checkbox
            let remainingRange = NSRange(location: contentStartsAfter, length: lineRange.location + lineRange.length - contentStartsAfter)
            let contentAfter = attributedString.attributedSubstring(from: remainingRange).string.trimmingCharacters(in: .whitespaces)

            guard let storage = textView.textStorage else { return false }

            isProgrammaticUpdate = true

            if contentAfter.isEmpty {
                // Blank line after checkbox - remove the checkbox, just add newline with proper attributes
                let fontAttrs: [NSAttributedString.Key: Any] = [
                    NSAttributedString.Key.font: NSFont.systemFont(ofSize: activeFontSize.rawValue),
                    NSAttributedString.Key.foregroundColor: activeColor.nsColor,
                    ColorMapping.colorIDKey: activeColor.id,
                    ColorMapping.fontSizeKey: activeFontSize.rawValue
                ]
                let newlineWithAttrs = NSAttributedString(string: "\n", attributes: fontAttrs)
                storage.replaceCharacters(in: lineRange, with: newlineWithAttrs)
            } else {
                // Content after checkbox - add newline and new checkbox
                let newCheckbox = CheckboxTextAttachment(checkboxID: UUID().uuidString, isChecked: false)
                let newCheckboxString = NSAttributedString(attachment: newCheckbox)

                // Add font attributes for proper rendering
                let fontAttrs: [NSAttributedString.Key: Any] = [
                    NSAttributedString.Key.font: NSFont.systemFont(ofSize: activeFontSize.rawValue),
                    NSAttributedString.Key.foregroundColor: activeColor.nsColor,
                    ColorMapping.colorIDKey: activeColor.id,
                    ColorMapping.fontSizeKey: activeFontSize.rawValue
                ]

                let newLine = NSMutableAttributedString(string: "\n", attributes: fontAttrs)
                newLine.append(newCheckboxString)

                // Add space after checkbox with proper font attributes
                newLine.append(NSAttributedString(string: " ", attributes: fontAttrs))
                storage.replaceCharacters(in: cursorRange, with: newLine)
            }

            // Position cursor after the inserted content
            let newCursorPosition = cursorRange.location + (contentAfter.isEmpty ? 1 : 3)  // +3 for "\n" + checkbox + space
            textView.setSelectedRange(NSRange(location: newCursorPosition, length: 0))

            // Ensure typing attributes are set for the next line
            textView.typingAttributes[NSAttributedString.Key.font] = NSFont.systemFont(ofSize: activeFontSize.rawValue)
            textView.typingAttributes[NSAttributedString.Key.foregroundColor] = activeColor.nsColor
            textView.typingAttributes[ColorMapping.colorIDKey] = activeColor.id
            textView.typingAttributes[ColorMapping.fontSizeKey] = activeFontSize.rawValue

            parent.text = NSAttributedString(attributedString: storage)
            isProgrammaticUpdate = false

            return true
        }

        private func applyAutoFormat(_ newText: String, to textView: NSTextView, at range: NSRange, lineRange: NSRange) -> Bool {
            isProgrammaticUpdate = true

            guard let storage = textView.textStorage else {
                isProgrammaticUpdate = false
                return false
            }

            // If newText is just "\n", replace the entire line (removes formatting)
            let replacementRange = newText == "\n" ? lineRange : range
            storage.replaceCharacters(in: replacementRange, with: newText)

            // Position cursor after the inserted text
            let newCursorPosition = replacementRange.location + newText.count
            textView.setSelectedRange(NSRange(location: newCursorPosition, length: 0))

            parent.text = NSAttributedString(attributedString: storage)
            isProgrammaticUpdate = false

            return true
        }

        func insertUncheckedCheckbox() {
            guard let textView = textView,
                  let storage = textView.textStorage else {
                return
            }

            isProgrammaticUpdate = true

            let checkbox = CheckboxTextAttachment(checkboxID: UUID().uuidString, isChecked: false)
            let checkboxString = NSAttributedString(attachment: checkbox)
            let insertionRange = textView.selectedRange

            // Insert checkbox
            storage.insert(checkboxString, at: insertionRange.location)

            // Insert space after checkbox if next character is not already a space
            let spaceInsertionPos = insertionRange.location + 1
            if spaceInsertionPos < storage.length {
                let nextCharRange = NSRange(location: spaceInsertionPos, length: 1)
                let nextChar = storage.attributedSubstring(from: nextCharRange).string
                if nextChar != " " {
                    let spaceAttrs: [NSAttributedString.Key: Any] = [
                        NSAttributedString.Key.font: NSFont.systemFont(ofSize: activeFontSize.rawValue),
                        NSAttributedString.Key.foregroundColor: activeColor.nsColor,
                        ColorMapping.colorIDKey: activeColor.id,
                        ColorMapping.fontSizeKey: activeFontSize.rawValue
                    ]
                    storage.insert(NSAttributedString(string: " ", attributes: spaceAttrs), at: spaceInsertionPos)
                }
            } else {
                // End of text, just add space
                let spaceAttrs: [NSAttributedString.Key: Any] = [
                    NSAttributedString.Key.font: NSFont.systemFont(ofSize: activeFontSize.rawValue),
                    NSAttributedString.Key.foregroundColor: activeColor.nsColor,
                    ColorMapping.colorIDKey: activeColor.id,
                    ColorMapping.fontSizeKey: activeFontSize.rawValue
                ]
                storage.insert(NSAttributedString(string: " ", attributes: spaceAttrs), at: spaceInsertionPos)
            }

            let newCursorPosition = spaceInsertionPos + 1
            textView.setSelectedRange(NSRange(location: newCursorPosition, length: 0))

            // Defer binding update to next runloop to avoid state modification during view update
            let newText = NSAttributedString(attributedString: storage)
            DispatchQueue.main.async { [weak self] in
                self?.parent.text = newText
                self?.isProgrammaticUpdate = false
            }
        }

        func insertCheckedCheckbox() {
            guard let textView = textView,
                  let storage = textView.textStorage else {
                return
            }

            isProgrammaticUpdate = true

            let cursorPosition = textView.selectedRange.location
            let plainText = storage.string as NSString
            let lineRange = plainText.lineRange(for: NSRange(location: cursorPosition, length: 0))

            // Search for an unchecked checkbox on this line
            var foundCheckbox = false
            var searchPos = lineRange.location

            while searchPos < lineRange.location + lineRange.length {
                var effectiveRange = NSRange()
                if let attachment = storage.attribute(NSAttributedString.Key.attachment, at: searchPos, longestEffectiveRange: &effectiveRange, in: lineRange) as? CheckboxTextAttachment {
                    if !attachment.isChecked {
                        // Found an unchecked checkbox - toggle it to checked
                        attachment.isChecked = true
                        foundCheckbox = true
                    }
                    searchPos = effectiveRange.location + effectiveRange.length
                } else {
                    searchPos += 1
                }
            }

            // If no unchecked checkbox found, insert a new checked one
            if !foundCheckbox {
                let checkbox = CheckboxTextAttachment(checkboxID: UUID().uuidString, isChecked: true)
                let checkboxString = NSAttributedString(attachment: checkbox)
                let insertionRange = textView.selectedRange

                // Insert checkbox
                storage.insert(checkboxString, at: insertionRange.location)

                // Insert space after checkbox if next character is not already a space
                let spaceInsertionPos = insertionRange.location + 1
                if spaceInsertionPos < storage.length {
                    let nextCharRange = NSRange(location: spaceInsertionPos, length: 1)
                    let nextChar = storage.attributedSubstring(from: nextCharRange).string
                    if nextChar != " " {
                        let spaceAttrs: [NSAttributedString.Key: Any] = [
                            NSAttributedString.Key.font: NSFont.systemFont(ofSize: activeFontSize.rawValue),
                            NSAttributedString.Key.foregroundColor: activeColor.nsColor,
                            ColorMapping.colorIDKey: activeColor.id,
                            ColorMapping.fontSizeKey: activeFontSize.rawValue
                        ]
                        storage.insert(NSAttributedString(string: " ", attributes: spaceAttrs), at: spaceInsertionPos)
                    }
                } else {
                    // End of text, just add space
                    let spaceAttrs: [NSAttributedString.Key: Any] = [
                        NSAttributedString.Key.font: NSFont.systemFont(ofSize: activeFontSize.rawValue),
                        NSAttributedString.Key.foregroundColor: activeColor.nsColor,
                        ColorMapping.colorIDKey: activeColor.id,
                        ColorMapping.fontSizeKey: activeFontSize.rawValue
                    ]
                    storage.insert(NSAttributedString(string: " ", attributes: spaceAttrs), at: spaceInsertionPos)
                }

                let newCursorPosition = spaceInsertionPos + 1
                textView.setSelectedRange(NSRange(location: newCursorPosition, length: 0))
            }

            // Defer binding update to next runloop to avoid state modification during view update
            let newText = NSAttributedString(attributedString: storage)
            DispatchQueue.main.async { [weak self] in
                self?.parent.text = newText
                self?.isProgrammaticUpdate = false
            }
        }

        func insertBullet() {
            guard let textView = textView,
                  let storage = textView.textStorage else {
                return
            }

            isProgrammaticUpdate = true

            let insertionRange = textView.selectedRange
            let bulletText = "- "

            // Create attributed string with proper font attributes
            let fontAttrs: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key.font: NSFont.systemFont(ofSize: activeFontSize.rawValue),
                NSAttributedString.Key.foregroundColor: activeColor.nsColor,
                ColorMapping.colorIDKey: activeColor.id,
                ColorMapping.fontSizeKey: activeFontSize.rawValue
            ]
            let bulletString = NSAttributedString(string: bulletText, attributes: fontAttrs)
            storage.insert(bulletString, at: insertionRange.location)

            let newCursorPosition = insertionRange.location + bulletText.count
            textView.setSelectedRange(NSRange(location: newCursorPosition, length: 0))

            let newText = NSAttributedString(attributedString: storage)
            DispatchQueue.main.async { [weak self] in
                self?.parent.text = newText
                self?.isProgrammaticUpdate = false
            }
        }

        func insertNumbering() {
            guard let textView = textView,
                  let storage = textView.textStorage else {
                return
            }

            isProgrammaticUpdate = true

            let insertionRange = textView.selectedRange
            let numberText = "1. "

            // Create attributed string with proper font attributes
            let fontAttrs: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key.font: NSFont.systemFont(ofSize: activeFontSize.rawValue),
                NSAttributedString.Key.foregroundColor: activeColor.nsColor,
                ColorMapping.colorIDKey: activeColor.id,
                ColorMapping.fontSizeKey: activeFontSize.rawValue
            ]
            let numberString = NSAttributedString(string: numberText, attributes: fontAttrs)
            storage.insert(numberString, at: insertionRange.location)

            let newCursorPosition = insertionRange.location + numberText.count
            textView.setSelectedRange(NSRange(location: newCursorPosition, length: 0))

            let newText = NSAttributedString(attributedString: storage)
            DispatchQueue.main.async { [weak self] in
                self?.parent.text = newText
                self?.isProgrammaticUpdate = false
            }
        }

        func insertURL(urlString: String, displayText: String) {
            guard let textView = textView,
                  let storage = textView.textStorage else {
                return
            }

            isProgrammaticUpdate = true

            let insertionRange = textView.selectedRange

            guard let linkURL = URL(string: urlString) else {
                isProgrammaticUpdate = false
                return
            }

            // Create link attributes with blue color and underline
            let linkAttrs: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key.font: NSFont.systemFont(ofSize: activeFontSize.rawValue),
                NSAttributedString.Key.foregroundColor: NSColor.systemBlue,
                NSAttributedString.Key.underlineStyle: NSUnderlineStyle.single.rawValue,
                NSAttributedString.Key.link: linkURL,
                ColorMapping.colorIDKey: "blue",
                ColorMapping.fontSizeKey: activeFontSize.rawValue
            ]
            let linkString = NSAttributedString(string: displayText, attributes: linkAttrs)

            // Insert link text at cursor position
            storage.insert(linkString, at: insertionRange.location)

            // Insert space after link if next character is not already a space
            let spaceInsertionPos = insertionRange.location + displayText.count
            if spaceInsertionPos < storage.length {
                let nextCharRange = NSRange(location: spaceInsertionPos, length: 1)
                let nextChar = storage.attributedSubstring(from: nextCharRange).string
                if nextChar != " " {
                    let spaceAttrs: [NSAttributedString.Key: Any] = [
                        NSAttributedString.Key.font: NSFont.systemFont(ofSize: activeFontSize.rawValue),
                        NSAttributedString.Key.foregroundColor: activeColor.nsColor,
                        ColorMapping.colorIDKey: activeColor.id,
                        ColorMapping.fontSizeKey: activeFontSize.rawValue
                    ]
                    storage.insert(NSAttributedString(string: " ", attributes: spaceAttrs), at: spaceInsertionPos)
                }
            } else {
                // End of text, just add space
                let spaceAttrs: [NSAttributedString.Key: Any] = [
                    NSAttributedString.Key.font: NSFont.systemFont(ofSize: activeFontSize.rawValue),
                    NSAttributedString.Key.foregroundColor: activeColor.nsColor,
                    ColorMapping.colorIDKey: activeColor.id,
                    ColorMapping.fontSizeKey: activeFontSize.rawValue
                ]
                storage.insert(NSAttributedString(string: " ", attributes: spaceAttrs), at: spaceInsertionPos)
            }

            let newCursorPosition = spaceInsertionPos + 1
            textView.setSelectedRange(NSRange(location: newCursorPosition, length: 0))

            // Defer binding update to next runloop to avoid state modification during view update
            let newText = NSAttributedString(attributedString: storage)
            DispatchQueue.main.async { [weak self] in
                self?.parent.text = newText
                self?.isProgrammaticUpdate = false
            }
        }
    }
}
#else
struct RichTextEditor: UIViewRepresentable {
    @Binding var text: NSAttributedString
    @Binding var activeColor: RichTextColor
    @Binding var activeFontSize: FontSize
    @Binding var isBold: Bool
    @Binding var isUnderlined: Bool
    @Binding var isStrikethrough: Bool
    @Binding var insertUncheckedCheckboxTrigger: UUID?
    @Binding var insertCheckedCheckboxTrigger: UUID?
    @Binding var insertBulletTrigger: UUID?
    @Binding var insertNumberingTrigger: UUID?
    @Binding var insertURLTrigger: (UUID, String, String)?
    @Environment(\.colorScheme) var colorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isScrollEnabled = true
        textView.backgroundColor = .clear
        textView.allowsEditingTextAttributes = true
        textView.keyboardDismissMode = .interactive
        textView.font = UIFont.systemFont(ofSize: activeFontSize.rawValue)
        textView.textColor = UIColor.label  // Set default to dynamic label color
        textView.textContainerInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        textView.attributedText = text
        textView.typingAttributes[NSAttributedString.Key.foregroundColor] = activeColor.uiColor
        textView.typingAttributes[ColorMapping.colorIDKey] = activeColor.id
        textView.typingAttributes[NSAttributedString.Key.font] = UIFont.systemFont(ofSize: activeFontSize.rawValue)
        textView.typingAttributes[ColorMapping.fontSizeKey] = activeFontSize.rawValue
        context.coordinator.textView = textView

        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.textView = uiView

        if !context.coordinator.isProgrammaticUpdate {
            let currentText = uiView.attributedText ?? NSAttributedString()
            if !text.isEqual(to: currentText) {
                context.coordinator.isProgrammaticUpdate = true
                uiView.attributedText = text
                context.coordinator.isProgrammaticUpdate = false
            }
        }

        if context.coordinator.activeColor != activeColor {
            context.coordinator.activeColor = activeColor
            context.coordinator.apply(color: activeColor, to: uiView)
        }

        if context.coordinator.activeFontSize != activeFontSize {
            context.coordinator.activeFontSize = activeFontSize
            context.coordinator.apply(fontSize: activeFontSize, to: uiView)
        }

        if context.coordinator.isBold != isBold {
            context.coordinator.isBold = isBold
            context.coordinator.toggleBold(uiView)
        }

        if context.coordinator.isUnderlined != isUnderlined {
            context.coordinator.isUnderlined = isUnderlined
            context.coordinator.toggleUnderline(uiView)
        }

        if context.coordinator.isStrikethrough != isStrikethrough {
            context.coordinator.isStrikethrough = isStrikethrough
            context.coordinator.toggleStrikethrough(uiView)
        }

        // Handle unchecked checkbox insertion trigger
        if insertUncheckedCheckboxTrigger != context.coordinator.lastUncheckedCheckboxTrigger {
            context.coordinator.lastUncheckedCheckboxTrigger = insertUncheckedCheckboxTrigger
            context.coordinator.insertUncheckedCheckbox()
        }

        // Handle checked checkbox insertion trigger
        if insertCheckedCheckboxTrigger != context.coordinator.lastCheckedCheckboxTrigger {
            context.coordinator.lastCheckedCheckboxTrigger = insertCheckedCheckboxTrigger
            context.coordinator.insertCheckedCheckbox()
        }

        // Handle bullet insertion trigger
        if insertBulletTrigger != context.coordinator.lastBulletTrigger {
            context.coordinator.lastBulletTrigger = insertBulletTrigger
            context.coordinator.insertBullet()
        }

        // Handle numbering insertion trigger
        if insertNumberingTrigger != context.coordinator.lastNumberingTrigger {
            context.coordinator.lastNumberingTrigger = insertNumberingTrigger
            context.coordinator.insertNumbering()
        }

        // Handle URL insertion trigger
        if insertURLTrigger?.0 != context.coordinator.lastURLTrigger?.0 {
            context.coordinator.lastURLTrigger = insertURLTrigger
            if let (_, urlString, displayText) = insertURLTrigger {
                context.coordinator.insertURL(urlString: urlString, displayText: displayText)
            }
        }

        // Handle appearance changes (dark/light mode)
        context.coordinator.handleAppearanceChange(to: uiView)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: RichTextEditor
        var activeColor: RichTextColor
        var activeFontSize: FontSize
        var isBold: Bool
        var isUnderlined: Bool
        var isStrikethrough: Bool
        var isProgrammaticUpdate = false
        var lastUncheckedCheckboxTrigger: UUID?
        var lastCheckedCheckboxTrigger: UUID?
        var lastBulletTrigger: UUID?
        var lastNumberingTrigger: UUID?
        var lastURLTrigger: (UUID, String, String)?
        weak var textView: UITextView?

        init(_ parent: RichTextEditor) {
            self.parent = parent
            self.activeColor = parent.activeColor
            self.activeFontSize = parent.activeFontSize
            self.isBold = parent.isBold
            self.isUnderlined = parent.isUnderlined
            self.isStrikethrough = parent.isStrikethrough
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isProgrammaticUpdate else { return }

            // Fix text that lost color due to autocorrect or other system changes
            // This runs on every text change and scans for uncolored text
            fixUncoloredText(in: textView)
        }

        private func fixUncoloredText(in textView: UITextView) {
            // Scan for text missing the colorIDKey (what autocorrect strips) and apply the active color
            if let mutableText = textView.attributedText?.mutableCopy() as? NSMutableAttributedString {
                var fixed = false
                let length = mutableText.length
                var i = 0
                var uncoloredCount = 0

                while i < length {
                    var effectiveRange = NSRange()
                    let attrs = mutableText.attributes(at: i, effectiveRange: &effectiveRange)

                    // If this range has no colorIDKey, it lost its color info (autocorrect stripped it)
                    // Apply the active color with its colorIDKey
                    if attrs[ColorMapping.colorIDKey] == nil {
                        uncoloredCount += 1
                        print("DEBUG: Found uncolored text at \(effectiveRange)")
                        let colorAttrs: [NSAttributedString.Key: Any] = [
                            NSAttributedString.Key.foregroundColor: activeColor.uiColor,
                            ColorMapping.colorIDKey: activeColor.id
                        ]
                        mutableText.addAttributes(colorAttrs, range: effectiveRange)
                        fixed = true
                    }
                    i = effectiveRange.location + effectiveRange.length
                }

                print("DEBUG: fixUncoloredText - found \(uncoloredCount) uncolored ranges, fixed=\(fixed), activeColor=\(activeColor)")

                if fixed {
                    isProgrammaticUpdate = true
                    textView.attributedText = mutableText
                    isProgrammaticUpdate = false
                }

                // Convert checkbox patterns to attachments
                let spaceAttrs: [NSAttributedString.Key: Any] = [
                    NSAttributedString.Key.font: UIFont.systemFont(ofSize: activeFontSize.rawValue),
                    NSAttributedString.Key.foregroundColor: activeColor.uiColor,
                    ColorMapping.colorIDKey: activeColor.id,
                    ColorMapping.fontSizeKey: activeFontSize.rawValue
                ]
                if AutoFormatting.convertCheckboxPatterns(in: mutableText, spaceAttributes: spaceAttrs) {
                    isProgrammaticUpdate = true
                    textView.attributedText = mutableText
                    isProgrammaticUpdate = false
                }
            }

            // Restore typing attributes after text changes
            textView.typingAttributes[NSAttributedString.Key.foregroundColor] = activeColor.uiColor
            textView.typingAttributes[ColorMapping.colorIDKey] = activeColor.id

            let updatedText = textView.attributedText ?? NSAttributedString()
            parent.text = updatedText
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            let font = UIFont.systemFont(ofSize: activeFontSize.rawValue, weight: isBold ? .bold : .regular)
            textView.typingAttributes[NSAttributedString.Key.font] = font
            textView.typingAttributes[NSAttributedString.Key.foregroundColor] = activeColor.uiColor
            textView.typingAttributes[ColorMapping.colorIDKey] = activeColor.id
            textView.typingAttributes[ColorMapping.fontSizeKey] = activeFontSize.rawValue

            let underlineValue = isUnderlined ? NSUnderlineStyle.single.rawValue : 0
            textView.typingAttributes[NSAttributedString.Key.underlineStyle] = underlineValue

            let strikethroughValue = isStrikethrough ? NSUnderlineStyle.single.rawValue : 0
            textView.typingAttributes[NSAttributedString.Key.strikethroughStyle] = strikethroughValue
        }

        func apply(color: RichTextColor, to textView: UITextView) {
            let uiColor = color.uiColor
            let selectedRange = textView.selectedRange

            if selectedRange.length > 0,
               let currentText = textView.attributedText?.mutableCopy() as? NSMutableAttributedString {
                isProgrammaticUpdate = true
                ColorMapping.applyColor(color, to: currentText, range: selectedRange)
                textView.attributedText = currentText
                textView.selectedRange = selectedRange
                parent.text = currentText
                isProgrammaticUpdate = false
            }

            textView.typingAttributes[NSAttributedString.Key.foregroundColor] = uiColor
            textView.typingAttributes[ColorMapping.colorIDKey] = color.id
        }

        func apply(fontSize: FontSize, to textView: UITextView) {
            let selectedRange = textView.selectedRange

            if selectedRange.length > 0,
               let currentText = textView.attributedText?.mutableCopy() as? NSMutableAttributedString {
                isProgrammaticUpdate = true
                let fontAttrs: [NSAttributedString.Key: Any] = [
                    NSAttributedString.Key.font: UIFont.systemFont(ofSize: fontSize.rawValue),
                    ColorMapping.fontSizeKey: fontSize.rawValue
                ]
                currentText.addAttributes(fontAttrs, range: selectedRange)
                textView.attributedText = currentText
                textView.selectedRange = selectedRange
                parent.text = currentText
                isProgrammaticUpdate = false
            }

            textView.typingAttributes[NSAttributedString.Key.font] = UIFont.systemFont(ofSize: fontSize.rawValue)
            textView.typingAttributes[ColorMapping.fontSizeKey] = fontSize.rawValue
        }

        func toggleBold(_ textView: UITextView) {
            let selectedRange = textView.selectedRange
            if selectedRange.length > 0,
               let currentText = textView.attributedText?.mutableCopy() as? NSMutableAttributedString {
                isProgrammaticUpdate = true

                let font = UIFont.systemFont(ofSize: activeFontSize.rawValue, weight: isBold ? .bold : .regular)
                currentText.addAttribute(NSAttributedString.Key.font, value: font, range: selectedRange)
                textView.attributedText = currentText
                textView.selectedRange = selectedRange
                parent.text = currentText
                isProgrammaticUpdate = false
            }

            let boldFont = UIFont.systemFont(ofSize: activeFontSize.rawValue, weight: isBold ? .bold : .regular)
            textView.typingAttributes[NSAttributedString.Key.font] = boldFont
        }

        func toggleUnderline(_ textView: UITextView) {
            let selectedRange = textView.selectedRange
            if selectedRange.length > 0,
               let currentText = textView.attributedText?.mutableCopy() as? NSMutableAttributedString {
                isProgrammaticUpdate = true

                let underlineValue = isUnderlined ? NSUnderlineStyle.single.rawValue : 0
                currentText.addAttribute(NSAttributedString.Key.underlineStyle, value: underlineValue, range: selectedRange)
                textView.attributedText = currentText
                textView.selectedRange = selectedRange
                parent.text = currentText
                isProgrammaticUpdate = false
            }

            let underlineValue = isUnderlined ? NSUnderlineStyle.single.rawValue : 0
            textView.typingAttributes[NSAttributedString.Key.underlineStyle] = underlineValue
        }

        func toggleStrikethrough(_ textView: UITextView) {
            let selectedRange = textView.selectedRange
            if selectedRange.length > 0,
               let currentText = textView.attributedText?.mutableCopy() as? NSMutableAttributedString {
                isProgrammaticUpdate = true

                let strikethroughValue = isStrikethrough ? NSUnderlineStyle.single.rawValue : 0
                currentText.addAttribute(NSAttributedString.Key.strikethroughStyle, value: strikethroughValue, range: selectedRange)
                textView.attributedText = currentText
                textView.selectedRange = selectedRange
                parent.text = currentText
                isProgrammaticUpdate = false
            }

            let strikethroughValue = isStrikethrough ? NSUnderlineStyle.single.rawValue : 0
            textView.typingAttributes[NSAttributedString.Key.strikethroughStyle] = strikethroughValue
        }

        func handleAppearanceChange(to textView: UITextView) {
            // Only update typing attributes when appearance changes if using automatic color
            if activeColor == .automatic {
                textView.typingAttributes[NSAttributedString.Key.foregroundColor] = activeColor.uiColor
                textView.typingAttributes[ColorMapping.colorIDKey] = activeColor.id
            }
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            // Handle return key for auto-numbering and auto-formatting
            if text == "\n" {
                return handleReturnKey(textView: textView, range: range)
            }
            return true
        }

        private func handleReturnKey(textView: UITextView, range: NSRange) -> Bool {
            guard let plainText = textView.text else {
                return true
            }

            guard let attributedText = textView.attributedText else {
                return true
            }

            guard let lineInfo = AutoFormatting.getLineInfo(for: range, in: plainText) else {
                return true
            }

            // Check for checkbox pattern (attachments at start of line)
            if handleCheckboxLine(in: attributedText, textView: textView, at: range, lineRange: lineInfo.range) {
                return false
            }

            // Check for numbered list pattern
            if let newText = AutoFormatting.handleNumberedList(lineText: lineInfo.text) {
                return applyAutoFormat(newText, to: textView, at: range, lineRange: lineInfo.range)
            }

            // Check for bullet point pattern
            if let newText = AutoFormatting.handleBulletPoint(lineText: lineInfo.text) {
                return applyAutoFormat(newText, to: textView, at: range, lineRange: lineInfo.range)
            }

            return true
        }

        private func handleCheckboxLine(in attributedString: NSAttributedString, textView: UITextView, at cursorRange: NSRange, lineRange: NSRange) -> Bool {
            // Find if there's a checkbox attachment at the start of the line
            guard lineRange.location < attributedString.length else { return false }

            var hasCheckboxAtStart = false
            var contentStartsAfter = lineRange.location

            // Look for attachment at the start of the line
            if attributedString.attribute(NSAttributedString.Key.attachment, at: lineRange.location, longestEffectiveRange: nil, in: lineRange) != nil {
                hasCheckboxAtStart = true
                contentStartsAfter = lineRange.location + 1
            }

            guard hasCheckboxAtStart else { return false }

            // Check if there's content after the checkbox
            let remainingRange = NSRange(location: contentStartsAfter, length: lineRange.location + lineRange.length - contentStartsAfter)
            let contentAfter = attributedString.attributedSubstring(from: remainingRange).string.trimmingCharacters(in: .whitespaces)

            isProgrammaticUpdate = true

            if contentAfter.isEmpty {
                // Blank line after checkbox - remove the checkbox, just add newline with proper attributes
                let fontAttrs: [NSAttributedString.Key: Any] = [
                    NSAttributedString.Key.font: UIFont.systemFont(ofSize: activeFontSize.rawValue),
                    NSAttributedString.Key.foregroundColor: activeColor.uiColor,
                    ColorMapping.colorIDKey: activeColor.id,
                    ColorMapping.fontSizeKey: activeFontSize.rawValue
                ]
                let newlineWithAttrs = NSAttributedString(string: "\n", attributes: fontAttrs)
                textView.textStorage.replaceCharacters(in: lineRange, with: newlineWithAttrs)
            } else {
                // Content after checkbox - add newline and new checkbox
                let newCheckbox = CheckboxTextAttachment(checkboxID: UUID().uuidString, isChecked: false)
                let newCheckboxString = NSAttributedString(attachment: newCheckbox)

                // Add font attributes for proper rendering
                let fontAttrs: [NSAttributedString.Key: Any] = [
                    NSAttributedString.Key.font: UIFont.systemFont(ofSize: activeFontSize.rawValue),
                    NSAttributedString.Key.foregroundColor: activeColor.uiColor,
                    ColorMapping.colorIDKey: activeColor.id,
                    ColorMapping.fontSizeKey: activeFontSize.rawValue
                ]

                let newLine = NSMutableAttributedString(string: "\n", attributes: fontAttrs)
                newLine.append(newCheckboxString)

                // Add space after checkbox with proper font attributes
                newLine.append(NSAttributedString(string: " ", attributes: fontAttrs))
                textView.textStorage.replaceCharacters(in: cursorRange, with: newLine)
            }

            // Position cursor after the inserted content
            let newCursorPosition = cursorRange.location + (contentAfter.isEmpty ? 1 : 3)  // +3 for "\n" + checkbox + space
            textView.selectedRange = NSRange(location: newCursorPosition, length: 0)

            // Ensure typing attributes are set for the next line
            textView.typingAttributes[NSAttributedString.Key.font] = UIFont.systemFont(ofSize: activeFontSize.rawValue)
            textView.typingAttributes[NSAttributedString.Key.foregroundColor] = activeColor.uiColor
            textView.typingAttributes[ColorMapping.colorIDKey] = activeColor.id
            textView.typingAttributes[ColorMapping.fontSizeKey] = activeFontSize.rawValue

            parent.text = textView.attributedText ?? NSAttributedString()
            isProgrammaticUpdate = false

            return true
        }

        private func applyAutoFormat(_ newText: String, to textView: UITextView, at range: NSRange, lineRange: NSRange) -> Bool {
            isProgrammaticUpdate = true

            // If newText is just "\n", replace the entire line (removes formatting)
            let replacementRange = newText == "\n" ? lineRange : range
            textView.textStorage.replaceCharacters(in: replacementRange, with: newText)

            // Position cursor after the inserted text
            let newCursorPosition = replacementRange.location + newText.count
            textView.selectedRange = NSRange(location: newCursorPosition, length: 0)

            parent.text = textView.attributedText ?? NSAttributedString()
            isProgrammaticUpdate = false

            return false  // We handled it
        }

        func insertUncheckedCheckbox() {
            guard let textView = textView,
                  let attributedText = textView.attributedText?.mutableCopy() as? NSMutableAttributedString else {
                return
            }

            isProgrammaticUpdate = true

            let checkbox = CheckboxTextAttachment(checkboxID: UUID().uuidString, isChecked: false)
            let checkboxString = NSAttributedString(attachment: checkbox)
            let insertionRange = textView.selectedRange

            // Insert checkbox
            attributedText.insert(checkboxString, at: insertionRange.location)

            // Insert space after checkbox if next character is not already a space
            let spaceInsertionPos = insertionRange.location + 1
            if spaceInsertionPos < attributedText.length {
                let nextCharRange = NSRange(location: spaceInsertionPos, length: 1)
                let nextChar = attributedText.attributedSubstring(from: nextCharRange).string
                if nextChar != " " {
                    let spaceAttrs: [NSAttributedString.Key: Any] = [
                        NSAttributedString.Key.font: UIFont.systemFont(ofSize: activeFontSize.rawValue),
                        NSAttributedString.Key.foregroundColor: activeColor.uiColor,
                        ColorMapping.colorIDKey: activeColor.id,
                        ColorMapping.fontSizeKey: activeFontSize.rawValue
                    ]
                    attributedText.insert(NSAttributedString(string: " ", attributes: spaceAttrs), at: spaceInsertionPos)
                }
            } else {
                // End of text, just add space
                let spaceAttrs: [NSAttributedString.Key: Any] = [
                    NSAttributedString.Key.font: UIFont.systemFont(ofSize: activeFontSize.rawValue),
                    NSAttributedString.Key.foregroundColor: activeColor.uiColor,
                    ColorMapping.colorIDKey: activeColor.id,
                    ColorMapping.fontSizeKey: activeFontSize.rawValue
                ]
                attributedText.insert(NSAttributedString(string: " ", attributes: spaceAttrs), at: spaceInsertionPos)
            }

            let newCursorPosition = spaceInsertionPos + 1
            textView.attributedText = attributedText
            textView.selectedRange = NSRange(location: newCursorPosition, length: 0)

            // Defer binding update to next runloop to avoid state modification during view update
            DispatchQueue.main.async { [weak self] in
                self?.parent.text = attributedText
                self?.isProgrammaticUpdate = false
            }
        }

        func insertCheckedCheckbox() {
            guard let textView = textView,
                  let attributedText = textView.attributedText?.mutableCopy() as? NSMutableAttributedString else {
                return
            }

            isProgrammaticUpdate = true

            let cursorPosition = textView.selectedRange.location
            let plainText = attributedText.string as NSString
            let lineRange = plainText.lineRange(for: NSRange(location: cursorPosition, length: 0))

            // Search for an unchecked checkbox on this line
            var foundCheckbox = false
            var searchPos = lineRange.location

            while searchPos < lineRange.location + lineRange.length {
                var effectiveRange = NSRange()
                if let attachment = attributedText.attribute(NSAttributedString.Key.attachment, at: searchPos, longestEffectiveRange: &effectiveRange, in: lineRange) as? CheckboxTextAttachment {
                    if !attachment.isChecked {
                        // Found an unchecked checkbox - toggle it to checked
                        attachment.isChecked = true
                        foundCheckbox = true
                    }
                    searchPos = effectiveRange.location + effectiveRange.length
                } else {
                    searchPos += 1
                }
            }

            // If no unchecked checkbox found, insert a new checked one
            if !foundCheckbox {
                let checkbox = CheckboxTextAttachment(checkboxID: UUID().uuidString, isChecked: true)
                let checkboxString = NSAttributedString(attachment: checkbox)
                let insertionRange = textView.selectedRange

                // Insert checkbox
                attributedText.insert(checkboxString, at: insertionRange.location)

                // Insert space after checkbox if next character is not already a space
                let spaceInsertionPos = insertionRange.location + 1
                if spaceInsertionPos < attributedText.length {
                    let nextCharRange = NSRange(location: spaceInsertionPos, length: 1)
                    let nextChar = attributedText.attributedSubstring(from: nextCharRange).string
                    if nextChar != " " {
                        let spaceAttrs: [NSAttributedString.Key: Any] = [
                            NSAttributedString.Key.font: UIFont.systemFont(ofSize: activeFontSize.rawValue),
                            NSAttributedString.Key.foregroundColor: activeColor.uiColor,
                            ColorMapping.colorIDKey: activeColor.id,
                            ColorMapping.fontSizeKey: activeFontSize.rawValue
                        ]
                        attributedText.insert(NSAttributedString(string: " ", attributes: spaceAttrs), at: spaceInsertionPos)
                    }
                } else {
                    // End of text, just add space
                    let spaceAttrs: [NSAttributedString.Key: Any] = [
                        NSAttributedString.Key.font: UIFont.systemFont(ofSize: activeFontSize.rawValue),
                        NSAttributedString.Key.foregroundColor: activeColor.uiColor,
                        ColorMapping.colorIDKey: activeColor.id,
                        ColorMapping.fontSizeKey: activeFontSize.rawValue
                    ]
                    attributedText.insert(NSAttributedString(string: " ", attributes: spaceAttrs), at: spaceInsertionPos)
                }

                let newCursorPosition = spaceInsertionPos + 1
                textView.selectedRange = NSRange(location: newCursorPosition, length: 0)
            }

            // Reassign attributedText to trigger redraw
            textView.attributedText = attributedText

            // Defer binding update to next runloop to avoid state modification during view update
            DispatchQueue.main.async { [weak self] in
                self?.parent.text = attributedText
                self?.isProgrammaticUpdate = false
            }
        }

        func insertBullet() {
            guard let textView = textView else { return }

            isProgrammaticUpdate = true

            let insertionRange = textView.selectedRange
            let bulletText = "- "
            let mutableText = (textView.attributedText?.mutableCopy() as? NSMutableAttributedString) ?? NSMutableAttributedString()

            // Create attributed string with proper font attributes
            let fontAttrs: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key.font: UIFont.systemFont(ofSize: activeFontSize.rawValue),
                NSAttributedString.Key.foregroundColor: activeColor.uiColor,
                ColorMapping.colorIDKey: activeColor.id,
                ColorMapping.fontSizeKey: activeFontSize.rawValue
            ]
            let bulletString = NSAttributedString(string: bulletText, attributes: fontAttrs)
            mutableText.insert(bulletString, at: insertionRange.location)

            let newCursorPosition = insertionRange.location + bulletText.count
            textView.attributedText = mutableText
            textView.selectedRange = NSRange(location: newCursorPosition, length: 0)

            let updatedText = NSAttributedString(attributedString: mutableText)
            DispatchQueue.main.async { [weak self] in
                self?.parent.text = updatedText
                self?.isProgrammaticUpdate = false
            }
        }

        func insertNumbering() {
            guard let textView = textView else { return }

            isProgrammaticUpdate = true

            let insertionRange = textView.selectedRange
            let numberText = "1. "
            let mutableText = (textView.attributedText?.mutableCopy() as? NSMutableAttributedString) ?? NSMutableAttributedString()

            // Create attributed string with proper font attributes
            let fontAttrs: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key.font: UIFont.systemFont(ofSize: activeFontSize.rawValue),
                NSAttributedString.Key.foregroundColor: activeColor.uiColor,
                ColorMapping.colorIDKey: activeColor.id,
                ColorMapping.fontSizeKey: activeFontSize.rawValue
            ]
            let numberString = NSAttributedString(string: numberText, attributes: fontAttrs)
            mutableText.insert(numberString, at: insertionRange.location)

            let newCursorPosition = insertionRange.location + numberText.count
            textView.attributedText = mutableText
            textView.selectedRange = NSRange(location: newCursorPosition, length: 0)

            let updatedText = NSAttributedString(attributedString: mutableText)
            DispatchQueue.main.async { [weak self] in
                self?.parent.text = updatedText
                self?.isProgrammaticUpdate = false
            }
        }

        func insertURL(urlString: String, displayText: String) {
            guard let textView = textView else { return }

            isProgrammaticUpdate = true

            let insertionRange = textView.selectedRange
            let mutableText = (textView.attributedText?.mutableCopy() as? NSMutableAttributedString) ?? NSMutableAttributedString()

            guard let linkURL = URL(string: urlString) else {
                isProgrammaticUpdate = false
                return
            }

            // Create link attributes with blue color and underline
            let linkAttrs: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key.font: UIFont.systemFont(ofSize: activeFontSize.rawValue),
                NSAttributedString.Key.foregroundColor: UIColor.systemBlue,
                NSAttributedString.Key.underlineStyle: NSUnderlineStyle.single.rawValue,
                NSAttributedString.Key.link: linkURL,
                ColorMapping.colorIDKey: "blue",
                ColorMapping.fontSizeKey: activeFontSize.rawValue
            ]
            let linkString = NSAttributedString(string: displayText, attributes: linkAttrs)

            // Insert link text at cursor position
            mutableText.insert(linkString, at: insertionRange.location)

            // Insert space after link if next character is not already a space
            let spaceInsertionPos = insertionRange.location + displayText.count
            if spaceInsertionPos < mutableText.length {
                let nextCharRange = NSRange(location: spaceInsertionPos, length: 1)
                let nextChar = mutableText.attributedSubstring(from: nextCharRange).string
                if nextChar != " " {
                    let spaceAttrs: [NSAttributedString.Key: Any] = [
                        NSAttributedString.Key.font: UIFont.systemFont(ofSize: activeFontSize.rawValue),
                        NSAttributedString.Key.foregroundColor: activeColor.uiColor,
                        ColorMapping.colorIDKey: activeColor.id,
                        ColorMapping.fontSizeKey: activeFontSize.rawValue
                    ]
                    mutableText.insert(NSAttributedString(string: " ", attributes: spaceAttrs), at: spaceInsertionPos)
                }
            } else {
                // End of text, just add space
                let spaceAttrs: [NSAttributedString.Key: Any] = [
                    NSAttributedString.Key.font: UIFont.systemFont(ofSize: activeFontSize.rawValue),
                    NSAttributedString.Key.foregroundColor: activeColor.uiColor,
                    ColorMapping.colorIDKey: activeColor.id,
                    ColorMapping.fontSizeKey: activeFontSize.rawValue
                ]
                mutableText.insert(NSAttributedString(string: " ", attributes: spaceAttrs), at: spaceInsertionPos)
            }

            let newCursorPosition = spaceInsertionPos + 1
            textView.attributedText = mutableText
            textView.selectedRange = NSRange(location: newCursorPosition, length: 0)

            let updatedText = NSAttributedString(attributedString: mutableText)
            DispatchQueue.main.async { [weak self] in
                self?.parent.text = updatedText
                self?.isProgrammaticUpdate = false
            }
        }
    }
}
#endif

struct FontToolbar: View {
    @Binding var activeColor: RichTextColor
    @Binding var activeFontSize: FontSize
    @Binding var isBold: Bool
    @Binding var isUnderlined: Bool
    @Binding var isStrikethrough: Bool

    var body: some View {
        Menu {
            // MARK: - Colors Section
            Menu {
                Button {
                    activeColor = .automatic
                } label: {
                    Text("\(RichTextColor.automatic.emoji) Default")
                }

                Divider()

                Button {
                    activeColor = .red
                } label: {
                    Text("\(RichTextColor.red.emoji) Red")
                }

                Button {
                    activeColor = .green
                } label: {
                    Text("\(RichTextColor.green.emoji) Green")
                }

                Button {
                    activeColor = .orange
                } label: {
                    Text("\(RichTextColor.orange.emoji) Orange")
                }

                Button {
                    activeColor = .yellow
                } label: {
                    Text("\(RichTextColor.yellow.emoji) Yellow")
                }

                Button {
                    activeColor = .purple
                } label: {
                    Text("\(RichTextColor.purple.emoji) Purple")
                }

                Button {
                    activeColor = .blue
                } label: {
                    Text("\(RichTextColor.blue.emoji) Blue")
                }
            } label: {
                Label("Text Color", systemImage: "paintbrush")
            }

            Divider()

            // MARK: - Font Size Section
            Menu {
                ForEach(FontSize.allCases, id: \.self) { size in
                    Button {
                        activeFontSize = size
                    } label: {
                        HStack {
                            Text(size.displayName)
                            if activeFontSize == size {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label("Font Size", systemImage: "textformat.size")
            }

            Divider()

            // MARK: - Text Formatting Section
            Button {
                isBold.toggle()
            } label: {
                HStack {
                    Image(systemName: isBold ? "checkmark" : "bold")
                    Text("Bold")
                }
            }

            Button {
                isUnderlined.toggle()
            } label: {
                HStack {
                    Image(systemName: isUnderlined ? "checkmark" : "underline")
                    Text("Underline")
                }
            }

            Button {
                isStrikethrough.toggle()
            } label: {
                HStack {
                    Image(systemName: isStrikethrough ? "checkmark" : "strikethrough")
                    Text("Strikethrough")
                }
            }
        } label: {
            Image(systemName: "character.circle")
        }
    }
}

struct ListToolbar: View {
    @Binding var insertUncheckedCheckboxTrigger: UUID?
    @Binding var insertCheckedCheckboxTrigger: UUID?
    @Binding var insertBulletTrigger: UUID?
    @Binding var insertNumberingTrigger: UUID?
    @Binding var showingAddURLDialog: Bool
    @Binding var tempURLData: (String, String)?

    var body: some View {
#if os(macOS)
        HStack(spacing: 8) {
            Menu {
                Button {
                    insertUncheckedCheckboxTrigger = UUID()
                } label: {
                    Label("Unchecked Checkbox", systemImage: "square")
                }

                Button {
                    insertCheckedCheckboxTrigger = UUID()
                } label: {
                    Label("Checked Checkbox", systemImage: "checkmark.square.fill")
                }

                Divider()

                Button {
                    insertBulletTrigger = UUID()
                } label: {
                    Label("Bullet Point", systemImage: "minus")
                }

                Button {
                    insertNumberingTrigger = UUID()
                } label: {
                    Label("Numbering", systemImage: "list.number")
                }

                Button {
                    showingAddURLDialog = true
                } label: {
                    Label("Add URL", systemImage: "link")
                }

            } label: {
                Image(systemName: "list.bullet")
            }
            .sheet(isPresented: $showingAddURLDialog) {
                NavigationStack {
                    AddURLView(
                        tempURLData: $tempURLData,
                        onDismiss: {
                            showingAddURLDialog = false
                        }
                    )
                        .frame(width: 320, height: 260)
                        .padding()
                }
                .frame(width: 360, height: 320)
            }
        }
#else
        Menu {
            Button {
                insertUncheckedCheckboxTrigger = UUID()
            } label: {
                Label("Unchecked Checkbox", systemImage: "square")
            }

            Button {
                insertCheckedCheckboxTrigger = UUID()
            } label: {
                Label("Checked Checkbox", systemImage: "checkmark.square.fill")
            }

            Divider()

            Button {
                insertBulletTrigger = UUID()
            } label: {
                Label("Bullet Point", systemImage: "minus")
            }

            Button {
                insertNumberingTrigger = UUID()
            } label: {
                Label("Numbering", systemImage: "list.number")
            }

            Divider()

            Button {
                withAnimation(.easeInOut) {
                    showingAddURLDialog = true
                }
            } label: {
                Label("Add URL", systemImage: "link")
            }
        } label: {
            Image(systemName: "list.bullet")
        }
#endif
    }
}
