#if os(macOS)
import SwiftUI
import AppKit

private final class DynamicColorTextView: NSTextView {
    var onAppearanceChange: (() -> Void)?
    var onCheckboxTap: ((Int) -> Void)?
    var onColorChange: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }

    override func mouseDown(with event: NSEvent) {
        guard event.type == .leftMouseDown else {
            super.mouseDown(with: event)
            return
        }

        let localPoint = convert(event.locationInWindow, from: nil)
        if event.clickCount == 1,
           let charIndex = checkboxCharacterIndex(at: localPoint) {
            onCheckboxTap?(charIndex)
            return
        }

        super.mouseDown(with: event)
    }

    override func changeColor(_ sender: Any?) {
        super.changeColor(sender)
        onColorChange?()
    }

    private func checkboxCharacterIndex(at point: NSPoint) -> Int? {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer else { return nil }

        let textContainerOrigin = textContainerOrigin
        let containerPoint = NSPoint(x: point.x - textContainerOrigin.x,
                                     y: point.y - textContainerOrigin.y)

        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)
        let adjustedRect = glyphRect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)

        guard adjustedRect.contains(point) else { return nil }

        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard charIndex != NSNotFound,
              let storage = textStorage,
              charIndex < storage.length else { return nil }

        if storage.attribute(NSAttributedString.Key.attachment, at: charIndex, effectiveRange: nil) is CheckboxTextAttachment {
            return charIndex
        }

        return nil
    }
}

struct RichTextEditor: NSViewRepresentable {
    @Binding var text: NSAttributedString
    @Binding var activeColor: RichTextColor
    @Binding var activeHighlighter: HighlighterColor
    @Binding var activeFontSize: FontSize
    @Binding var isBold: Bool
    @Binding var isUnderlined: Bool
    @Binding var isStrikethrough: Bool
    @Binding var insertUncheckedCheckboxTrigger: UUID?
    @Binding var insertBulletTrigger: UUID?
    @Binding var insertNumberingTrigger: UUID?
    @Binding var insertDateTrigger: UUID?
    @Binding var insertTimeTrigger: UUID?
    @Binding var insertURLTrigger: (UUID, String, String)?
    @Binding var presentFormatMenuTrigger: UUID?
    @Binding var resetColorTrigger: UUID?

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
        textView.textStorage?.setAttributedString(text)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [NSView.AutoresizingMask.width]
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.applyTypingAttributes(to: textView)
        textView.onAppearanceChange = { [weak coordinator = context.coordinator] in
            coordinator?.handleAppearanceChange()
        }
        textView.onCheckboxTap = { [weak coordinator = context.coordinator] charIndex in
            coordinator?.handleCheckboxTap(at: charIndex)
        }
        textView.onColorChange = { [weak coordinator = context.coordinator] in
            coordinator?.handleColorPanelChange()
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        let currentText = textView.attributedString()
        if !context.coordinator.isProgrammaticUpdate,
           !text.isEqual(to: currentText) {
            context.coordinator.isProgrammaticUpdate = true

            // Save cursor position before updating text
            let cursorPosition = textView.selectedRange
            textView.textStorage?.setAttributedString(text)
            // Restore cursor position after updating text
            textView.setSelectedRange(cursorPosition)

            context.coordinator.isProgrammaticUpdate = false
            context.coordinator.applyTypingAttributes(to: textView)
        }

        if context.coordinator.activeColor != activeColor {
            context.coordinator.activeColor = activeColor
            if context.coordinator.pendingActiveColorFeedback == activeColor {
                context.coordinator.pendingActiveColorFeedback = nil
            } else {
                context.coordinator.customTypingColor = nil
                context.coordinator.apply(color: activeColor, to: textView)
            }
        }

        if context.coordinator.activeHighlighter != activeHighlighter {
            context.coordinator.activeHighlighter = activeHighlighter
            context.coordinator.apply(highlighter: activeHighlighter, to: textView)
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

        // Handle date insertion trigger
        if insertDateTrigger != context.coordinator.lastDateTrigger {
            context.coordinator.lastDateTrigger = insertDateTrigger
            context.coordinator.insertDate()
        }

        // Handle time insertion trigger
        if insertTimeTrigger != context.coordinator.lastTimeTrigger {
            context.coordinator.lastTimeTrigger = insertTimeTrigger
            context.coordinator.insertTime()
        }

        // Handle URL insertion trigger
        if insertURLTrigger?.0 != context.coordinator.lastURLTrigger?.0 {
            context.coordinator.lastURLTrigger = insertURLTrigger
            if let (_, urlString, displayText) = insertURLTrigger {
                context.coordinator.insertURL(urlString: urlString, displayText: displayText)
            }
        }

        if presentFormatMenuTrigger != context.coordinator.lastFormatMenuTrigger {
            context.coordinator.lastFormatMenuTrigger = presentFormatMenuTrigger
            context.coordinator.presentNativeFormatPanel()
        }

        // Handle reset trigger BEFORE syncing color state, so reset takes priority
        if resetColorTrigger != context.coordinator.lastResetColorTrigger {
            context.coordinator.lastResetColorTrigger = resetColorTrigger
            context.coordinator.handleColorReset()
        }

        // Sync color state AFTER reset, so the reset isn't overwritten by sampling
        context.coordinator.syncColorState(with: textView, sampleFromText: true)

        context.coordinator.handleAppearanceChange()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        var activeColor: RichTextColor
        var activeHighlighter: HighlighterColor
        var activeFontSize: FontSize
        var isBold: Bool
        var isUnderlined: Bool
        var isStrikethrough: Bool
        var isProgrammaticUpdate = false
        var lastUncheckedCheckboxTrigger: UUID?
        var lastBulletTrigger: UUID?
        var lastNumberingTrigger: UUID?
        var lastDateTrigger: UUID?
        var lastTimeTrigger: UUID?
        var lastURLTrigger: (UUID, String, String)?
        var lastFormatMenuTrigger: UUID?
        var lastResetColorTrigger: UUID?
        weak var textView: NSTextView?
        var pendingActiveColorFeedback: RichTextColor?
        var customTypingColor: NSColor?
        var hasCustomTypingColor: Bool { customTypingColor != nil }

        private func effectiveColorComponents() -> (color: NSColor, id: String?) {
            if let customTypingColor {
                let identifier = ColorMapping.identifier(for: customTypingColor, preferPaletteMatch: false)
                return (customTypingColor, identifier)
            }
            return (activeColor.nsColor, activeColor.id)
        }

        func syncColorState(with textView: NSTextView, sampleFromText: Bool) {
            var colorID = textView.typingAttributes[ColorMapping.colorIDKey] as? String
            var color = textView.typingAttributes[NSAttributedString.Key.foregroundColor] as? NSColor

            if sampleFromText,
               (colorID == nil || color == nil),
               let storage = textView.textStorage,
               storage.length > 0 {
                var sampleIndex = textView.selectedRange.location
                if sampleIndex >= storage.length {
                    sampleIndex = max(storage.length - 1, 0)
                }
                if sampleIndex >= 0 && sampleIndex < storage.length {
                    let attrs = storage.attributes(at: sampleIndex, effectiveRange: nil)
                    if colorID == nil {
                        colorID = attrs[ColorMapping.colorIDKey] as? String
                    }
                    if color == nil {
                        color = attrs[NSAttributedString.Key.foregroundColor] as? NSColor
                    }
                }
            }

            if let colorID {
                if ColorMapping.isCustomColorID(colorID),
                   let resolved = ColorMapping.color(from: colorID) {
                    customTypingColor = resolved
                } else {
                    let paletteColor = RichTextColor.from(id: colorID)
                    customTypingColor = nil
                    if paletteColor != activeColor {
                        activeColor = paletteColor
                        pendingActiveColorFeedback = paletteColor
                        parent.activeColor = paletteColor
                    }
                }
            } else if let color {
                customTypingColor = color
            } else {
                customTypingColor = nil
            }
        }

        init(_ parent: RichTextEditor) {
            self.parent = parent
            self.activeColor = parent.activeColor
            self.activeHighlighter = parent.activeHighlighter
            self.activeFontSize = parent.activeFontSize
            self.isBold = parent.isBold
            self.isUnderlined = parent.isUnderlined
            self.isStrikethrough = parent.isStrikethrough
        }

        func textDidChange(_ notification: Notification) {
            guard !isProgrammaticUpdate,
                  let textView = notification.object as? NSTextView,
                  textView === self.textView else { return }
            syncColorState(with: textView, sampleFromText: true)

            // Convert checkbox patterns to attachments
            if let storage = textView.textStorage {
                let spaceAttrs = currentTypingAttributes(from: textView)
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
            syncColorState(with: textView, sampleFromText: true)
            applyTypingAttributes(to: textView)
            syncColorState(with: textView, sampleFromText: false)

            // Force update the parent binding to ensure color changes are captured
            if !isProgrammaticUpdate {
                let currentText = textView.attributedString()
                parent.text = currentText
            }
        }

        func apply(color: RichTextColor, to textView: NSTextView) {
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

            customTypingColor = nil
            applyTypingAttributes(to: textView)
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

            applyTypingAttributes(to: textView)
        }

        func apply(highlighter: HighlighterColor, to textView: NSTextView) {
            let selectedRange = textView.selectedRange

            if selectedRange.length > 0,
               let storage = textView.textStorage {
                isProgrammaticUpdate = true
                ColorMapping.applyHighlight(highlighter, to: storage, range: selectedRange)
                textView.setSelectedRange(selectedRange)

                DispatchQueue.main.async { [weak self] in
                    self?.isProgrammaticUpdate = false
                    self?.parent.text = NSAttributedString(attributedString: storage)
                }
            }

            applyTypingAttributes(to: textView, highlightOverride: highlighter)
        }

        func presentNativeFormatPanel() {
            guard let textView = textView else { return }
            textView.window?.makeFirstResponder(textView)
            NSApp.sendAction(#selector(NSApplication.orderFrontColorPanel(_:)), to: nil, from: textView)
            NSFontManager.shared.orderFrontFontPanel(textView)
        }

        func handleColorPanelChange() {
            guard let textView = textView else { return }

            let selectedRange = textView.selectedRange
            var resolvedColor: NSColor?

            if selectedRange.length > 0,
               let storage = textView.textStorage,
               selectedRange.location < storage.length,
               NSMaxRange(selectedRange) <= storage.length {
                let attrs = storage.attributes(at: selectedRange.location, effectiveRange: nil)
                if let color = attrs[NSAttributedString.Key.foregroundColor] as? NSColor {
                    resolvedColor = color
                    let identifier = ColorMapping.identifier(for: color, preferPaletteMatch: false)
                    storage.addAttribute(ColorMapping.colorIDKey, value: identifier, range: selectedRange)
                }
                parent.text = NSAttributedString(attributedString: storage)
            }

            if resolvedColor == nil {
                resolvedColor = textView.typingAttributes[NSAttributedString.Key.foregroundColor] as? NSColor
            }

            if resolvedColor == nil {
                resolvedColor = NSColorPanel.shared.color
            }

            let color = resolvedColor ?? NSColorPanel.shared.color

            customTypingColor = color

            if let paletteMatch = ColorMapping.matchingRichTextColor(for: color),
               paletteMatch != activeColor {
                activeColor = paletteMatch
                pendingActiveColorFeedback = paletteMatch
                parent.activeColor = paletteMatch
            }

            applyTypingAttributes(to: textView)
        }

        private func updateTypingAttributesHighlight(_ textView: NSTextView, using highlight: HighlighterColor? = nil) {
            applyTypingAttributes(to: textView, highlightOverride: highlight)
        }

        private func currentTypingAttributes(from textView: NSTextView?, highlightOverride: HighlighterColor? = nil) -> [NSAttributedString.Key: Any] {
            var attrs = textView?.typingAttributes ?? [:]

            let font = NSFont.systemFont(ofSize: activeFontSize.rawValue, weight: isBold ? .bold : .regular)
            attrs[NSAttributedString.Key.font] = font
            attrs[ColorMapping.fontSizeKey] = activeFontSize.rawValue
            let components = effectiveColorComponents()
            let usingAutomatic = customTypingColor == nil && activeColor == .automatic
            if usingAutomatic {
                // Set NSColor.labelColor which is theme-aware (black in light mode, white in dark mode)
                // This prevents text from inheriting color from previous text, while staying dynamic
                attrs[NSAttributedString.Key.foregroundColor] = NSColor.labelColor
                attrs[ColorMapping.colorIDKey] = RichTextColor.automatic.id
            } else {
                attrs[NSAttributedString.Key.foregroundColor] = components.color
                if let id = components.id {
                    attrs[ColorMapping.colorIDKey] = id
                } else {
                    attrs.removeValue(forKey: ColorMapping.colorIDKey)
                }
            }

            let underlineValue = isUnderlined ? NSUnderlineStyle.single.rawValue : 0
            attrs[NSAttributedString.Key.underlineStyle] = underlineValue

            let strikethroughValue = isStrikethrough ? NSUnderlineStyle.single.rawValue : 0
            attrs[NSAttributedString.Key.strikethroughStyle] = strikethroughValue

            let targetHighlight = highlightOverride ?? activeHighlighter
            if targetHighlight == .none {
                attrs.removeValue(forKey: NSAttributedString.Key.backgroundColor)
                attrs.removeValue(forKey: ColorMapping.highlightIDKey)
            } else if let color = targetHighlight.nsColor {
                attrs[NSAttributedString.Key.backgroundColor] = color
                attrs[ColorMapping.highlightIDKey] = targetHighlight.id
            }

            return attrs
        }

        func applyTypingAttributes(to textView: NSTextView, highlightOverride: HighlighterColor? = nil) {
            textView.typingAttributes = currentTypingAttributes(from: textView, highlightOverride: highlightOverride)
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

            applyTypingAttributes(to: textView)
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

            applyTypingAttributes(to: textView)
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

            applyTypingAttributes(to: textView)
        }

        func handleAppearanceChange() {
            guard let textView = textView else { return }

            // Refresh automatic colors in the text storage when theme changes
            if let storage = textView.textStorage {
                var currentPos = 0
                while currentPos < storage.length {
                    var range = NSRange()
                    let attrs = storage.attributes(at: currentPos, longestEffectiveRange: &range, in: NSRange(location: currentPos, length: storage.length - currentPos))

                    // If this text has automatic color ID, refresh it with the current theme-aware labelColor
                    if let colorID = attrs[ColorMapping.colorIDKey] as? String, colorID == "automatic" {
                        storage.addAttribute(NSAttributedString.Key.foregroundColor, value: NSColor.labelColor, range: range)
                    }

                    currentPos = range.location + range.length
                }
            }

            applyTypingAttributes(to: textView)
        }

        func handleColorReset() {
            guard let textView = textView else { return }
            customTypingColor = nil
            pendingActiveColorFeedback = nil
            activeColor = .automatic
            apply(color: .automatic, to: textView)
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Handle return key for auto-numbering
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                return handleReturnKey(textView: textView)
            }
            return false
        }

        func handleCheckboxTap(at charIndex: Int) {
            guard let textView = textView,
                  let storage = textView.textStorage,
                  charIndex >= 0,
                  charIndex < storage.length else { return }

            var effectiveRange = NSRange(location: charIndex, length: 1)
            guard let attachment = storage.attribute(NSAttributedString.Key.attachment,
                                                     at: charIndex,
                                                     effectiveRange: &effectiveRange) as? CheckboxTextAttachment else {
                return
            }

            isProgrammaticUpdate = true
            attachment.isChecked.toggle()
            textView.layoutManager?.invalidateDisplay(forCharacterRange: effectiveRange)

            let updatedText = NSAttributedString(attributedString: storage)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.parent.text = updatedText
                self.isProgrammaticUpdate = false
            }
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
                let fontAttrs = currentTypingAttributes(from: textView)
                let newlineWithAttrs = NSAttributedString(string: "\n", attributes: fontAttrs)
                storage.replaceCharacters(in: lineRange, with: newlineWithAttrs)
            } else {
                // Content after checkbox - add newline and new checkbox
                let newCheckbox = CheckboxTextAttachment(checkboxID: UUID().uuidString, isChecked: false)
                let newCheckboxString = NSAttributedString(attachment: newCheckbox)

                // Add font attributes for proper rendering
                let fontAttrs = currentTypingAttributes(from: textView)

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
            applyTypingAttributes(to: textView)

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
            applyTypingAttributes(to: textView)

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
                    let spaceAttrs = currentTypingAttributes(from: textView)
                    storage.insert(NSAttributedString(string: " ", attributes: spaceAttrs), at: spaceInsertionPos)
                }
            } else {
                // End of text, just add space
                let spaceAttrs = currentTypingAttributes(from: textView)
                storage.insert(NSAttributedString(string: " ", attributes: spaceAttrs), at: spaceInsertionPos)
            }

            let newCursorPosition = spaceInsertionPos + 1
            textView.setSelectedRange(NSRange(location: newCursorPosition, length: 0))
            applyTypingAttributes(to: textView)

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
            let fontAttrs = currentTypingAttributes(from: textView)
            let bulletString = NSAttributedString(string: bulletText, attributes: fontAttrs)
            storage.insert(bulletString, at: insertionRange.location)

            let newCursorPosition = insertionRange.location + bulletText.count
            textView.setSelectedRange(NSRange(location: newCursorPosition, length: 0))
            applyTypingAttributes(to: textView)

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
            let fontAttrs = currentTypingAttributes(from: textView)
            let numberString = NSAttributedString(string: numberText, attributes: fontAttrs)
            storage.insert(numberString, at: insertionRange.location)

            let newCursorPosition = insertionRange.location + numberText.count
            textView.setSelectedRange(NSRange(location: newCursorPosition, length: 0))
            applyTypingAttributes(to: textView)

            let newText = NSAttributedString(attributedString: storage)
            DispatchQueue.main.async { [weak self] in
                self?.parent.text = newText
                self?.isProgrammaticUpdate = false
            }
        }

        func insertDate() {
            guard let textView = textView,
                  let storage = textView.textStorage else {
                return
            }

            isProgrammaticUpdate = true

            let insertionRange = textView.selectedRange

            // Format the date as "Wednesday, 11/5/25"
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, M/d/yy"
            let dateText = formatter.string(from: Date())

            // Create attributed string with proper font attributes
            let fontAttrs = currentTypingAttributes(from: textView)
            let dateString = NSAttributedString(string: dateText, attributes: fontAttrs)
            storage.insert(dateString, at: insertionRange.location)

            let newCursorPosition = insertionRange.location + dateText.count
            textView.setSelectedRange(NSRange(location: newCursorPosition, length: 0))
            applyTypingAttributes(to: textView)

            let newText = NSAttributedString(attributedString: storage)
            DispatchQueue.main.async { [weak self] in
                self?.parent.text = newText
                self?.isProgrammaticUpdate = false
            }
        }

        func insertTime() {
            guard let textView = textView,
                  let storage = textView.textStorage else {
                return
            }

            isProgrammaticUpdate = true

            let insertionRange = textView.selectedRange

            // Format the time as "HH:mm" in 24-hour format
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            let timeText = formatter.string(from: Date())

            // Create attributed string with proper font attributes
            let fontAttrs = currentTypingAttributes(from: textView)
            let timeString = NSAttributedString(string: timeText, attributes: fontAttrs)
            storage.insert(timeString, at: insertionRange.location)

            let newCursorPosition = insertionRange.location + timeText.count
            textView.setSelectedRange(NSRange(location: newCursorPosition, length: 0))
            applyTypingAttributes(to: textView)

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
                    let spaceAttrs = currentTypingAttributes(from: textView)
                    storage.insert(NSAttributedString(string: " ", attributes: spaceAttrs), at: spaceInsertionPos)
                }
            } else {
                // End of text, just add space
                let spaceAttrs = currentTypingAttributes(from: textView)
                storage.insert(NSAttributedString(string: " ", attributes: spaceAttrs), at: spaceInsertionPos)
            }

            let newCursorPosition = spaceInsertionPos + 1
            textView.setSelectedRange(NSRange(location: newCursorPosition, length: 0))
            applyTypingAttributes(to: textView)

            // Defer binding update to next runloop to avoid state modification during view update
            let newText = NSAttributedString(attributedString: storage)
            DispatchQueue.main.async { [weak self] in
                self?.parent.text = newText
                self?.isProgrammaticUpdate = false
            }
        }
    }
}

#endif
