#if !os(macOS)
import SwiftUI
import UIKit

struct RichTextEditor: UIViewRepresentable {
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
        context.coordinator.textView = textView
        context.coordinator.applyTypingAttributes(to: textView)

        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.textView = uiView

        if !context.coordinator.isProgrammaticUpdate {
            let currentText = uiView.attributedText ?? NSAttributedString()
            if !text.isEqual(to: currentText) {
                context.coordinator.isProgrammaticUpdate = true
                // Save cursor position before updating text
                let cursorPosition = uiView.selectedRange
                uiView.attributedText = text
                // Restore cursor position after updating text, with bounds validation
                context.coordinator.setCursorPosition(cursorPosition, in: uiView)
                context.coordinator.isProgrammaticUpdate = false
                context.coordinator.applyTypingAttributes(to: uiView)
            }
        }

        if context.coordinator.activeColor != activeColor {
            context.coordinator.activeColor = activeColor
            context.coordinator.apply(color: activeColor, to: uiView)
        }

        if context.coordinator.activeHighlighter != activeHighlighter {
            context.coordinator.activeHighlighter = activeHighlighter
            context.coordinator.apply(highlighter: activeHighlighter, to: uiView)
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

        // Handle appearance changes (dark/light mode)
        context.coordinator.handleAppearanceChange(to: uiView)
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
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
        weak var textView: UITextView?
        private var fixTextTimer: Timer?
        private var pendingReplacementAttributes: (range: NSRange, newLength: Int, color: UIColor?, colorID: String?)?

        init(_ parent: RichTextEditor) {
            self.parent = parent
            self.activeColor = parent.activeColor
            self.activeHighlighter = parent.activeHighlighter
            self.activeFontSize = parent.activeFontSize
            self.isBold = parent.isBold
            self.isUnderlined = parent.isUnderlined
            self.isStrikethrough = parent.isStrikethrough
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isProgrammaticUpdate else { return }

            // Push latest text to the SwiftUI binding immediately so SwiftUI does not overwrite user edits
            let updatedText = textView.attributedText ?? NSAttributedString()
            parent.text = updatedText

            _ = applyPendingReplacementAttributesIfNeeded(to: textView)
            fixAutoPeriodColorIfNeeded(in: textView)

            // Cancel any pending timer to debounce rapid text changes (like holding delete key)
            fixTextTimer?.invalidate()
            fixTextTimer = nil

            // Debounce fixUncoloredText to execute AFTER rapid changes stop
            // This prevents interference with word/line deletion on iOS when holding delete key
            scheduleDeferredTextFix(for: textView)
        }

        private func scheduleDeferredTextFix(for textView: UITextView, delay: TimeInterval = 0.15) {
            fixTextTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self, weak textView] _ in
                Task { @MainActor [weak self, weak textView] in
                    guard let self = self else { return }
                    self.fixTextTimer = nil

                    guard let textView = textView else { return }

                    // If iOS is still managing marked text (autocorrect/composition), postpone the fix again
                    if textView.markedTextRange != nil {
                        self.scheduleDeferredTextFix(for: textView, delay: delay)
                        return
                    }

                    self.fixUncoloredText(in: textView)
                }
            }
        }

        @discardableResult
        private func applyPendingReplacementAttributesIfNeeded(to textView: UITextView) -> Bool {
            guard textView.markedTextRange == nil,
                  let pending = pendingReplacementAttributes else {
                return false
            }
            pendingReplacementAttributes = nil

            guard pending.newLength > 0 else { return false }
            let maxLength = textView.attributedText?.length ?? 0
            guard pending.range.location <= maxLength else { return false }
            let availableLength = max(0, maxLength - pending.range.location)
            guard availableLength > 0 else { return false }

            var effectiveLength = min(pending.newLength, availableLength)

            if pending.range.length == 0,
               pending.newLength == 1,
               availableLength >= 2,
               let attributedText = textView.attributedText {
                let checkRange = NSRange(location: pending.range.location, length: 2)
                if checkRange.upperBound <= attributedText.length {
                    let substring = attributedText.attributedSubstring(from: checkRange).string
                    if substring == ". " {
                        effectiveLength = 2
                    }
                }
            }

            let resolvedColorID: String
            let resolvedColor: UIColor

            if let colorID = pending.colorID {
                resolvedColorID = colorID
                resolvedColor = RichTextColor.from(id: colorID).uiColor
            } else if let color = pending.color {
                resolvedColor = color
                resolvedColorID = activeColor.id
            } else {
                resolvedColor = activeColor.uiColor
                resolvedColorID = activeColor.id
            }

            let attrs: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key.foregroundColor: resolvedColor,
                ColorMapping.colorIDKey: resolvedColorID
            ]

            let currentSelection = textView.selectedRange
            isProgrammaticUpdate = true
            textView.textStorage.addAttributes(attrs, range: NSRange(location: pending.range.location, length: effectiveLength))
            isProgrammaticUpdate = false
            textView.selectedRange = currentSelection

            parent.text = textView.attributedText ?? NSAttributedString()

            return true
        }

        private func fixAutoPeriodColorIfNeeded(in textView: UITextView) {
            guard pendingReplacementAttributes == nil else { return }
            guard textView.markedTextRange == nil else { return }
            let selection = textView.selectedRange
            guard selection.length == 0 else { return }
            guard let attributed = textView.attributedText else { return }
            let cursorLocation = selection.location
            guard cursorLocation >= 2, cursorLocation <= attributed.length else { return }
            let rangeStart = cursorLocation - 2
            let autoPeriodRange = NSRange(location: rangeStart, length: min(2, attributed.length - rangeStart))
            guard autoPeriodRange.length == 2 else { return }

            let substring = attributed.attributedSubstring(from: autoPeriodRange).string
            guard substring == ". " else { return }

            var needsFix = false
            for offset in 0..<autoPeriodRange.length {
                let index = autoPeriodRange.location + offset
                if attributed.attribute(NSAttributedString.Key.foregroundColor, at: index, effectiveRange: nil) == nil ||
                    attributed.attribute(ColorMapping.colorIDKey, at: index, effectiveRange: nil) == nil {
                    needsFix = true
                    break
                }
            }
            if !needsFix { return }

            let sampleIndex = max(0, autoPeriodRange.location - 1)
            let clampedSampleIndex = min(sampleIndex, max(0, attributed.length - 1))
            let sampleAttrs = attributed.attributes(at: clampedSampleIndex, effectiveRange: nil)

            let resolvedColorID = (sampleAttrs[ColorMapping.colorIDKey] as? String) ?? activeColor.id
            let resolvedColor = (sampleAttrs[NSAttributedString.Key.foregroundColor] as? UIColor) ?? RichTextColor.from(id: resolvedColorID).uiColor

            let attrs: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key.foregroundColor: resolvedColor,
                ColorMapping.colorIDKey: resolvedColorID
            ]

            isProgrammaticUpdate = true
            textView.textStorage.addAttributes(attrs, range: autoPeriodRange)
            isProgrammaticUpdate = false
            parent.text = textView.attributedText ?? NSAttributedString()
        }

        /// Validates and constrains a cursor position to valid bounds
        func validateCursorPosition(_ position: NSRange, for textView: UITextView) -> NSRange {
            let maxLength = textView.attributedText?.length ?? 0
            let validLocation = min(max(0, position.location), maxLength)
            let remainingLength = max(0, maxLength - validLocation)
            let validLength = min(max(0, position.length), remainingLength)
            return NSRange(location: validLocation, length: validLength)
        }

        /// Safely sets the cursor position with bounds checking
        func setCursorPosition(_ position: NSRange, in textView: UITextView) {
            let validPosition = validateCursorPosition(position, for: textView)
            textView.selectedRange = validPosition
        }

        private func fixUncoloredText(in textView: UITextView) {
            // Save the current cursor position to restore it after modifications
            let cursorPosition = textView.selectedRange

            // Scan for text missing the colorIDKey (what autocorrect strips) and apply the active color
            if let mutableText = textView.attributedText?.mutableCopy() as? NSMutableAttributedString {
                var textChanged = false
                let length = mutableText.length
                var i = 0

                while i < length {
                    var effectiveRange = NSRange()
                    let attrs = mutableText.attributes(at: i, effectiveRange: &effectiveRange)

                    let storedColorID = attrs[ColorMapping.colorIDKey] as? String
                    let expectedColor: UIColor
                    let expectedColorID: String

                    if let storedColorID = storedColorID {
                        let color = RichTextColor.from(id: storedColorID)
                        expectedColor = color.uiColor
                        expectedColorID = storedColorID
                    } else {
                        expectedColor = activeColor.uiColor
                        expectedColorID = activeColor.id
                    }

                    let currentColor = attrs[NSAttributedString.Key.foregroundColor] as? UIColor
                    let needsColorFix = currentColor == nil || !currentColor!.isEqual(expectedColor)
                    let needsIDFix = storedColorID == nil

                    if needsColorFix || needsIDFix {
                        var colorAttrs: [NSAttributedString.Key: Any] = [:]
                        colorAttrs[NSAttributedString.Key.foregroundColor] = expectedColor
                        colorAttrs[ColorMapping.colorIDKey] = expectedColorID
                        mutableText.addAttributes(colorAttrs, range: effectiveRange)
                        textChanged = true
                    }
                    i = effectiveRange.location + effectiveRange.length
                }

                // Convert checkbox patterns to attachments
                let spaceAttrs = currentTypingAttributes(from: textView)
                if AutoFormatting.convertCheckboxPatterns(in: mutableText, spaceAttributes: spaceAttrs) {
                    textChanged = true
                }

                // Only update UI if we actually changed something
                if textChanged {
                    isProgrammaticUpdate = true
                    textView.attributedText = mutableText
                    setCursorPosition(cursorPosition, in: textView)
                    isProgrammaticUpdate = false
                    applyTypingAttributes(to: textView)
                }
            }

            // Always update binding to ensure text is saved
            isProgrammaticUpdate = true
            let updatedText = textView.attributedText ?? NSAttributedString()
            DispatchQueue.main.async { [weak self] in
                self?.parent.text = updatedText
                self?.isProgrammaticUpdate = false
            }

            // Restore typing attributes after text changes
            applyTypingAttributes(to: textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            applyTypingAttributes(to: textView)
        }

        func apply(color: RichTextColor, to textView: UITextView) {
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

            applyTypingAttributes(to: textView)
            updateTypingAttributesHighlight(textView)
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

            applyTypingAttributes(to: textView)
            updateTypingAttributesHighlight(textView)
        }

        func apply(highlighter: HighlighterColor, to textView: UITextView) {
            let selectedRange = textView.selectedRange

            if selectedRange.length > 0,
               let currentText = textView.attributedText?.mutableCopy() as? NSMutableAttributedString {
                isProgrammaticUpdate = true
                ColorMapping.applyHighlight(highlighter, to: currentText, range: selectedRange)
                textView.attributedText = currentText
                textView.selectedRange = selectedRange
                parent.text = currentText
                isProgrammaticUpdate = false
            }

            updateTypingAttributesHighlight(textView, using: highlighter)
            applyTypingAttributes(to: textView)
        }

        private func updateTypingAttributesHighlight(_ textView: UITextView, using highlight: HighlighterColor? = nil) {
            let targetHighlight = highlight ?? activeHighlighter
            if targetHighlight == .none {
                textView.typingAttributes.removeValue(forKey: NSAttributedString.Key.backgroundColor)
                textView.typingAttributes.removeValue(forKey: ColorMapping.highlightIDKey)
            } else if let color = targetHighlight.uiColor {
                textView.typingAttributes[NSAttributedString.Key.backgroundColor] = color
                textView.typingAttributes[ColorMapping.highlightIDKey] = targetHighlight.id
            }
        }

        private func currentTypingAttributes(from textView: UITextView?) -> [NSAttributedString.Key: Any] {
            var attrs = textView?.typingAttributes ?? [:]

            let font = UIFont.systemFont(ofSize: activeFontSize.rawValue, weight: isBold ? .bold : .regular)
            attrs[NSAttributedString.Key.font] = font
            attrs[ColorMapping.fontSizeKey] = activeFontSize.rawValue
            attrs[NSAttributedString.Key.foregroundColor] = activeColor.uiColor
            attrs[ColorMapping.colorIDKey] = activeColor.id
            attrs[NSAttributedString.Key.underlineStyle] = isUnderlined ? NSUnderlineStyle.single.rawValue : 0
            attrs[NSAttributedString.Key.strikethroughStyle] = isStrikethrough ? NSUnderlineStyle.single.rawValue : 0

            if activeHighlighter == .none {
                attrs.removeValue(forKey: NSAttributedString.Key.backgroundColor)
                attrs.removeValue(forKey: ColorMapping.highlightIDKey)
            } else if let color = activeHighlighter.uiColor {
                attrs[NSAttributedString.Key.backgroundColor] = color
                attrs[ColorMapping.highlightIDKey] = activeHighlighter.id
            }

            return attrs
        }

        func applyTypingAttributes(to textView: UITextView) {
            textView.typingAttributes = currentTypingAttributes(from: textView)
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

            applyTypingAttributes(to: textView)
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

            applyTypingAttributes(to: textView)
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

            applyTypingAttributes(to: textView)
        }

        func handleAppearanceChange(to textView: UITextView) {
            applyTypingAttributes(to: textView)
            updateTypingAttributesHighlight(textView)
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if handleAutoPeriodReplacement(in: textView, range: range, replacementText: text) {
                return false
            }

            // Handle return key for auto-numbering and auto-formatting
            if text == "\n" {
                return handleReturnKey(textView: textView, range: range)
            }

            if !text.isEmpty {
                let isAutoPeriod = (range.length == 0 && text == ". " && range.location > 0)
                let shouldCapture = range.length > 0 || isAutoPeriod

                if shouldCapture {
                    let attributedLength = textView.attributedText?.length ?? 0
                    var attributeLocation = range.location
                    if isAutoPeriod {
                        attributeLocation = max(0, range.location - 1)
                    }
                    attributeLocation = min(attributeLocation, max(0, attributedLength - 1))

                    var existingColor: UIColor?
                    var existingColorID: String?

                    if attributedLength > 0 && attributeLocation < attributedLength {
                        let attrs = textView.attributedText?.attributes(at: attributeLocation, effectiveRange: nil)
                        existingColor = attrs?[NSAttributedString.Key.foregroundColor] as? UIColor
                        existingColorID = attrs?[ColorMapping.colorIDKey] as? String
                    }

                    let newLength = (text as NSString).length
                    pendingReplacementAttributes = (range: range, newLength: newLength, color: existingColor, colorID: existingColorID)
                } else {
                    pendingReplacementAttributes = nil
                }
            } else {
                pendingReplacementAttributes = nil
            }
            return true
        }

        func textView(_ textView: UITextView, shouldInteractWith attachment: NSTextAttachment, in characterRange: NSRange) -> Bool {
            return handleCheckboxInteraction(attachment: attachment, range: characterRange, textView: textView)
        }

        private func handleCheckboxInteraction(attachment: NSTextAttachment, range: NSRange, textView: UITextView) -> Bool {
            guard let checkbox = attachment as? CheckboxTextAttachment else {
                return true
            }

            isProgrammaticUpdate = true
            checkbox.isChecked.toggle()

            textView.layoutManager.invalidateDisplay(forCharacterRange: range)

            let updatedText = textView.attributedText ?? NSAttributedString()
            DispatchQueue.main.async { [weak self] in
                self?.parent.text = updatedText
                self?.isProgrammaticUpdate = false
            }

            return false
        }

        private func handleAutoPeriodReplacement(in textView: UITextView, range: NSRange, replacementText text: String) -> Bool {
            guard text == ". ",
                  range.location > 0,
                  let mutableText = textView.attributedText?.mutableCopy() as? NSMutableAttributedString else {
                return false
            }

            var attributes = textView.typingAttributes
            let attributedLength = mutableText.length

            if attributedLength > 0 {
                let sampleIndex = min(max(range.location - 1, 0), attributedLength - 1)
                if sampleIndex < attributedLength {
                    let sampleAttrs = mutableText.attributes(at: sampleIndex, effectiveRange: nil)
                    for (key, value) in sampleAttrs {
                        attributes[key] = value
                    }
                }
            }

            if attributes[NSAttributedString.Key.foregroundColor] == nil {
                attributes[NSAttributedString.Key.foregroundColor] = activeColor.uiColor
            }
            if attributes[ColorMapping.colorIDKey] == nil {
                attributes[ColorMapping.colorIDKey] = activeColor.id
            }
            if attributes[ColorMapping.fontSizeKey] == nil {
                attributes[ColorMapping.fontSizeKey] = activeFontSize.rawValue
            }
            if attributes[ColorMapping.highlightIDKey] == nil, activeHighlighter != .none {
                attributes[ColorMapping.highlightIDKey] = activeHighlighter.id
            }
            if attributes[NSAttributedString.Key.backgroundColor] == nil,
               activeHighlighter != .none,
               let highlightColor = activeHighlighter.uiColor {
                attributes[NSAttributedString.Key.backgroundColor] = highlightColor
            }

            let replacement = NSAttributedString(string: text, attributes: attributes)

            let newCursorLocation = range.location + replacement.length

            isProgrammaticUpdate = true
            mutableText.replaceCharacters(in: range, with: replacement)
            textView.attributedText = mutableText
            textView.selectedRange = NSRange(location: newCursorLocation, length: 0)
            applyTypingAttributes(to: textView)
            parent.text = mutableText
            isProgrammaticUpdate = false

            pendingReplacementAttributes = nil
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
                let fontAttrs = currentTypingAttributes(from: textView)
                let newlineWithAttrs = NSAttributedString(string: "\n", attributes: fontAttrs)
                textView.textStorage.replaceCharacters(in: lineRange, with: newlineWithAttrs)
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
                textView.textStorage.replaceCharacters(in: cursorRange, with: newLine)
            }

            // Position cursor after the inserted content
            let newCursorPosition = cursorRange.location + (contentAfter.isEmpty ? 1 : 3)  // +3 for "\n" + checkbox + space
            textView.selectedRange = NSRange(location: newCursorPosition, length: 0)

            // Ensure typing attributes are set for the next line
            applyTypingAttributes(to: textView)
            updateTypingAttributesHighlight(textView)

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
                    let spaceAttrs = currentTypingAttributes(from: textView)
                    attributedText.insert(NSAttributedString(string: " ", attributes: spaceAttrs), at: spaceInsertionPos)
                }
            } else {
                // End of text, just add space
                let spaceAttrs = currentTypingAttributes(from: textView)
                attributedText.insert(NSAttributedString(string: " ", attributes: spaceAttrs), at: spaceInsertionPos)
            }

            let newCursorPosition = spaceInsertionPos + 1
            textView.attributedText = attributedText
            textView.selectedRange = NSRange(location: newCursorPosition, length: 0)
            applyTypingAttributes(to: textView)

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
            let fontAttrs = currentTypingAttributes(from: textView)
            let bulletString = NSAttributedString(string: bulletText, attributes: fontAttrs)
            mutableText.insert(bulletString, at: insertionRange.location)

            let newCursorPosition = insertionRange.location + bulletText.count
            textView.attributedText = mutableText
            setCursorPosition(NSRange(location: newCursorPosition, length: 0), in: textView)
            applyTypingAttributes(to: textView)

            // Update binding synchronously while isProgrammaticUpdate is true to prevent race conditions
            let updatedText = NSAttributedString(attributedString: mutableText)
            parent.text = updatedText

            isProgrammaticUpdate = false
        }

        func insertNumbering() {
            guard let textView = textView else { return }

            isProgrammaticUpdate = true

            let insertionRange = textView.selectedRange
            let numberText = "1. "
            let mutableText = (textView.attributedText?.mutableCopy() as? NSMutableAttributedString) ?? NSMutableAttributedString()

            // Create attributed string with proper font attributes
            let fontAttrs = currentTypingAttributes(from: textView)
            let numberString = NSAttributedString(string: numberText, attributes: fontAttrs)
            mutableText.insert(numberString, at: insertionRange.location)

            let newCursorPosition = insertionRange.location + numberText.count
            textView.attributedText = mutableText
            setCursorPosition(NSRange(location: newCursorPosition, length: 0), in: textView)
            applyTypingAttributes(to: textView)

            // Update binding synchronously while isProgrammaticUpdate is true to prevent race conditions
            let updatedText = NSAttributedString(attributedString: mutableText)
            parent.text = updatedText

            isProgrammaticUpdate = false
        }

        func insertDate() {
            guard let textView = textView else { return }

            isProgrammaticUpdate = true

            let insertionRange = textView.selectedRange
            let mutableText = (textView.attributedText?.mutableCopy() as? NSMutableAttributedString) ?? NSMutableAttributedString()

            // Format the date as "Wednesday, 11/5/25"
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, M/d/yy"
            let dateText = formatter.string(from: Date())

            // Create attributed string with proper font attributes
            let fontAttrs = currentTypingAttributes(from: textView)
            let dateString = NSAttributedString(string: dateText, attributes: fontAttrs)
            mutableText.insert(dateString, at: insertionRange.location)

            let newCursorPosition = insertionRange.location + dateText.count
            textView.attributedText = mutableText
            setCursorPosition(NSRange(location: newCursorPosition, length: 0), in: textView)
            applyTypingAttributes(to: textView)

            // Update binding synchronously while isProgrammaticUpdate is true to prevent race conditions
            let updatedText = NSAttributedString(attributedString: mutableText)
            parent.text = updatedText

            isProgrammaticUpdate = false
        }

        func insertTime() {
            guard let textView = textView else { return }

            isProgrammaticUpdate = true

            let insertionRange = textView.selectedRange
            let mutableText = (textView.attributedText?.mutableCopy() as? NSMutableAttributedString) ?? NSMutableAttributedString()

            // Format the time as "HH:mm" in 24-hour format
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            let timeText = formatter.string(from: Date())

            // Create attributed string with proper font attributes
            let fontAttrs = currentTypingAttributes(from: textView)
            let timeString = NSAttributedString(string: timeText, attributes: fontAttrs)
            mutableText.insert(timeString, at: insertionRange.location)

            let newCursorPosition = insertionRange.location + timeText.count
            textView.attributedText = mutableText
            setCursorPosition(NSRange(location: newCursorPosition, length: 0), in: textView)
            applyTypingAttributes(to: textView)

            // Update binding synchronously while isProgrammaticUpdate is true to prevent race conditions
            let updatedText = NSAttributedString(attributedString: mutableText)
            parent.text = updatedText

            isProgrammaticUpdate = false
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
                    let spaceAttrs = currentTypingAttributes(from: textView)
                    mutableText.insert(NSAttributedString(string: " ", attributes: spaceAttrs), at: spaceInsertionPos)
                }
            } else {
                // End of text, just add space
                let spaceAttrs = currentTypingAttributes(from: textView)
                mutableText.insert(NSAttributedString(string: " ", attributes: spaceAttrs), at: spaceInsertionPos)
            }

            let newCursorPosition = spaceInsertionPos + 1
            textView.attributedText = mutableText
            setCursorPosition(NSRange(location: newCursorPosition, length: 0), in: textView)
            applyTypingAttributes(to: textView)

            // Update binding synchronously while isProgrammaticUpdate is true to prevent race conditions
            let updatedText = NSAttributedString(attributedString: mutableText)
            parent.text = updatedText

            isProgrammaticUpdate = false
        }
    }
}

#endif
