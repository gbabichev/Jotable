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
    @Binding var presentFormatMenuTrigger: UUID?
    @Binding var resetColorTrigger: UUID?
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
        textView.textStorage.delegate = context.coordinator
        context.coordinator.textView = textView
        context.coordinator.applyTypingAttributes(to: textView)

        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.textView = uiView

        if !context.coordinator.isProgrammaticUpdate {
            let currentText = uiView.attributedText ?? NSAttributedString()

            // Always ensure the textStorage delegate is set
            uiView.textStorage.delegate = context.coordinator

            // Skip update if textViewDidChange was just called (within 10ms)
            // This prevents cursor jumping from the rapid round-trip cycle:
            // textViewDidChange -> pushTextToParent -> updateUIView
            let timeSinceLastChange = Date().timeIntervalSinceReferenceDate - context.coordinator.lastTextViewDidChangeTime
            let isRapidFeedback = timeSinceLastChange < 0.01

            if isRapidFeedback && text.string == currentText.string {
                // Text content is the same and this is a rapid feedback cycle
                // Skip the update to avoid cursor repositioning
                context.coordinator.syncColorState(with: uiView, sampleFromText: false)
                context.coordinator.applyTypingAttributes(to: uiView)
            } else if text.string != currentText.string {
                // String content actually changed, must update
                context.coordinator.isProgrammaticUpdate = true
                // Save cursor position before updating text
                let cursorPosition = uiView.selectedRange
                uiView.attributedText = text
                uiView.textStorage.delegate = context.coordinator
                // Restore cursor position after updating text, with bounds validation
                context.coordinator.setCursorPosition(cursorPosition, in: uiView)
                context.coordinator.isProgrammaticUpdate = false
                context.coordinator.applyTypingAttributes(to: uiView)
            }
            // If only attributes differ and it's a different text object, skip to avoid cursor jumping
        }

        if context.coordinator.activeColor != activeColor {
            context.coordinator.activeColor = activeColor
            if context.coordinator.pendingActiveColorFeedback == activeColor {
                context.coordinator.pendingActiveColorFeedback = nil
            } else {
                context.coordinator.customTypingColor = nil
                context.coordinator.apply(color: activeColor, to: uiView)
            }
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

        if resetColorTrigger != context.coordinator.lastResetColorTrigger {
            context.coordinator.lastResetColorTrigger = resetColorTrigger
            context.coordinator.handleColorReset(in: uiView)
        }

        // Handle appearance changes (dark/light mode)
        context.coordinator.handleAppearanceChange(to: uiView)
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate, NSTextStorageDelegate {
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
        var lastResetColorTrigger: UUID?
        weak var textView: UITextView?
        var pendingActiveColorFeedback: RichTextColor?
        private var caretColorLockID: String?
        private var releaseColorLockOnTextChange = false
        private var automaticColorCache: (style: UIUserInterfaceStyle, color: UIColor)?
        private var fixTextTimer: Timer?
        private var isProcessingExternalAttributes = false
        var customTypingColor: UIColor?
        var lastTextViewDidChangeTime: TimeInterval = 0
        private var hadMarkedTextInLastChange = false
        
        private func pushTextToParent(_ text: NSAttributedString) {
            let snapshot = NSAttributedString(attributedString: text)
            DispatchQueue.main.async { [weak self] in
                self?.parent.text = snapshot
            }
        }

        private func effectiveColorComponents() -> (color: UIColor?, id: String?) {
            if let customTypingColor {
                let identifier = ColorMapping.identifier(for: customTypingColor, preferPaletteMatch: false)
                return (customTypingColor, identifier)
            }
            if activeColor == .automatic {
                return (nil, RichTextColor.automatic.id)
            }
            return (activeColor.uiColor, activeColor.id)
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

        func textViewDidChange(_ textView: UITextView) {
            guard !isProgrammaticUpdate else { return }
            lastTextViewDidChangeTime = Date().timeIntervalSinceReferenceDate

            syncColorState(with: textView, sampleFromText: true)
            if releaseColorLockOnTextChange {
                releaseColorLockOnTextChange = false
                caretColorLockID = nil
            }

            // CRITICAL: Don't update the binding while iOS is managing marked text (autocorrect in progress)
            // When attachments (checkboxes) are present, premature binding updates can cause iOS to
            // misalculate text ranges and insert multiple words or corrupt the text
            hadMarkedTextInLastChange = textView.markedTextRange != nil

            if textView.markedTextRange == nil {
                // Push latest text to the SwiftUI binding only after autocorrect is complete
                let updatedText = textView.attributedText ?? NSAttributedString()
                pushTextToParent(updatedText)
            }

            // Cancel any pending timer to debounce rapid text changes (like holding delete key)
            fixTextTimer?.invalidate()
            fixTextTimer = nil
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

        func textViewDidChangeSelection(_ textView: UITextView) {
            if textView.selectedRange.length > 0 {
                caretColorLockID = nil
                releaseColorLockOnTextChange = false
            }
            syncColorState(with: textView, sampleFromText: true)
            applyTypingAttributes(to: textView)
        }

        func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorage.EditActions, range editedRange: NSRange, changeInLength delta: Int) {
            let isCharacterEdit = editedMask.contains(.editedCharacters) || delta != 0
            let canHandleAutomaticFix = isCharacterEdit
            let canHandleAttributeChange = editedMask.contains(.editedAttributes)
            guard (canHandleAutomaticFix || canHandleAttributeChange),
                  !isProgrammaticUpdate,
                  !isProcessingExternalAttributes else { return }

            let storageLength = textStorage.length
            guard storageLength > 0 else { return }

            let intersection = NSIntersectionRange(editedRange, NSRange(location: 0, length: storageLength))
            guard intersection.length > 0 else { return }

            isProcessingExternalAttributes = true
            textStorage.beginEditing()
            defer {
                textStorage.endEditing()
                isProcessingExternalAttributes = false
            }
            var textChanged = false
            textStorage.enumerateAttributes(in: intersection, options: []) { attrs, range, _ in
                if let color = attrs[NSAttributedString.Key.foregroundColor] as? UIColor {
                    if matchesAutomaticColor(color, in: textView) {
                        textStorage.addAttribute(ColorMapping.colorIDKey, value: RichTextColor.automatic.id, range: range)
                        textChanged = true
                    } else if canHandleAttributeChange {
                        let identifier = ColorMapping.identifier(for: color, preferPaletteMatch: false)
                        if attrs[ColorMapping.colorIDKey] as? String != identifier {
                            textStorage.addAttribute(ColorMapping.colorIDKey, value: identifier, range: range)
                            textChanged = true
                        }
                    }
                } else if canHandleAttributeChange,
                          attrs[ColorMapping.colorIDKey] == nil {
                    textStorage.removeAttribute(ColorMapping.colorIDKey, range: range)
                    textChanged = true
                }
            }

            guard textChanged else { return }

            if let textView = textView {
                caretColorLockID = nil
                releaseColorLockOnTextChange = false
                syncColorState(with: textView, sampleFromText: true)
            }
            let snapshot = NSAttributedString(attributedString: textStorage)
            pushTextToParent(snapshot)
        }

        func syncColorState(with textView: UITextView, sampleFromText: Bool) {
            var shouldSampleFromText = sampleFromText
            var colorID = textView.typingAttributes[ColorMapping.colorIDKey] as? String
            var color = textView.typingAttributes[NSAttributedString.Key.foregroundColor] as? UIColor

            if let directColor = color {
                let identifier = ColorMapping.identifier(for: directColor, preferPaletteMatch: false)
                if colorID != identifier {
                    colorID = identifier
                    textView.typingAttributes[ColorMapping.colorIDKey] = identifier
                }
                if textView.selectedRange.length == 0 {
                    caretColorLockID = identifier
                    releaseColorLockOnTextChange = true
                }
            }

            if let lockID = caretColorLockID,
               textView.selectedRange.length == 0 {
                colorID = lockID
                if ColorMapping.isCustomColorID(lockID) {
                    color = ColorMapping.color(from: lockID)
                } else if color == nil {
                    color = ColorMapping.color(from: lockID)
                }
                shouldSampleFromText = false
            }

            if shouldSampleFromText,
               (colorID == nil || color == nil),
               let attributed = textView.attributedText,
               attributed.length > 0 {
                var sampleIndex = textView.selectedRange.location
            if sampleIndex >= attributed.length {
                sampleIndex = attributed.length - 1
            }
            if sampleIndex >= 0 && sampleIndex < attributed.length {
                let attrs = attributed.attributes(at: sampleIndex, effectiveRange: nil)
                    if colorID == nil {
                        colorID = attrs[ColorMapping.colorIDKey] as? String
                    }
                    if color == nil {
                        color = attrs[NSAttributedString.Key.foregroundColor] as? UIColor
                    }
                }
            }

            if let colorID {
                if ColorMapping.isCustomColorID(colorID),
                   let resolvedColor = ColorMapping.color(from: colorID) {
                    customTypingColor = resolvedColor
                } else {
                    let paletteColor = RichTextColor.from(id: colorID)
                    customTypingColor = nil
                    if paletteColor != activeColor {
                        activeColor = paletteColor
                        pendingActiveColorFeedback = paletteColor
                        DispatchQueue.main.async { [weak self] in
                            self?.parent.activeColor = paletteColor
                        }
                    }
                }
            } else if let color {
                customTypingColor = color
            } else {
                customTypingColor = nil
            }

            if textView.selectedRange.length == 0 {
                caretColorLockID = colorID
            } else {
                caretColorLockID = nil
                releaseColorLockOnTextChange = false
            }
        }

        func apply(color: RichTextColor, to textView: UITextView) {
            let selectedRange = textView.selectedRange

            if selectedRange.length > 0,
               let currentText = textView.attributedText?.mutableCopy() as? NSMutableAttributedString {
                isProgrammaticUpdate = true
                ColorMapping.applyColor(color, to: currentText, range: selectedRange)
                textView.attributedText = currentText
                textView.selectedRange = selectedRange
                // Defer binding update to avoid modifying state during view update
                pushTextToParent(currentText)
                isProgrammaticUpdate = false
            } else {
                isProgrammaticUpdate = false
            }

            customTypingColor = nil
            caretColorLockID = color.id
            releaseColorLockOnTextChange = selectedRange.length == 0
            if color == .automatic {
                textView.typingAttributes.removeValue(forKey: NSAttributedString.Key.foregroundColor)
                textView.typingAttributes[ColorMapping.colorIDKey] = color.id
            } else {
                textView.typingAttributes[NSAttributedString.Key.foregroundColor] = color.uiColor
                textView.typingAttributes[ColorMapping.colorIDKey] = color.id
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
                // Defer binding update to avoid modifying state during view update
                pushTextToParent(currentText)
                isProgrammaticUpdate = false
            } else {
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
                // Defer binding update to avoid modifying state during view update
                pushTextToParent(currentText)
                isProgrammaticUpdate = false
            } else {
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

            let components = effectiveColorComponents()
            let usingAutomatic = customTypingColor == nil && activeColor == .automatic
            if usingAutomatic {
                // For automatic color, explicitly set UIColor.label for theme-aware text
                attrs[NSAttributedString.Key.foregroundColor] = UIColor.label
                attrs[ColorMapping.colorIDKey] = RichTextColor.automatic.id
            } else if let color = components.color {
                attrs[NSAttributedString.Key.foregroundColor] = color
                if let id = components.id {
                    attrs[ColorMapping.colorIDKey] = id
                } else {
                    attrs.removeValue(forKey: ColorMapping.colorIDKey)
                }
            } else {
                attrs.removeValue(forKey: NSAttributedString.Key.foregroundColor)
                attrs.removeValue(forKey: ColorMapping.colorIDKey)
            }

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

        private func matchesAutomaticColor(_ color: UIColor, in textView: UITextView?) -> Bool {
            let trait = textView?.traitCollection ?? UIScreen.main.traitCollection
            let style = trait.userInterfaceStyle
            if automaticColorCache?.style != style {
                automaticColorCache = (style: style, color: UIColor.label.resolvedColor(with: trait))
            }
            guard let reference = automaticColorCache?.color else { return false }
            let resolvedCandidate = color.resolvedColor(with: trait)
            return colorsEqual(resolvedCandidate, reference)
        }

        private func colorsEqual(_ lhs: UIColor, _ rhs: UIColor) -> Bool {
            var lr: CGFloat = 0, lg: CGFloat = 0, lb: CGFloat = 0, la: CGFloat = 0
            var rr: CGFloat = 0, rg: CGFloat = 0, rb: CGFloat = 0, ra: CGFloat = 0
            guard lhs.getRed(&lr, green: &lg, blue: &lb, alpha: &la),
                  rhs.getRed(&rr, green: &rg, blue: &rb, alpha: &ra) else {
                return lhs == rhs
            }
            let tolerance: CGFloat = 0.002
            return abs(lr - rr) < tolerance &&
                abs(lg - rg) < tolerance &&
                abs(lb - rb) < tolerance &&
                abs(la - ra) < tolerance
        }

        func applyTypingAttributes(to textView: UITextView) {
            syncColorState(with: textView, sampleFromText: false)
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
                pushTextToParent(currentText)
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
                pushTextToParent(currentText)
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
                pushTextToParent(currentText)
                isProgrammaticUpdate = false
            }

            applyTypingAttributes(to: textView)
        }

        func handleAppearanceChange(to textView: UITextView) {
            applyTypingAttributes(to: textView)
            updateTypingAttributesHighlight(textView)
        }

        func handleColorReset(in textView: UITextView) {
            customTypingColor = nil
            caretColorLockID = nil
            releaseColorLockOnTextChange = false
            pendingActiveColorFeedback = nil
            activeColor = .automatic
            apply(color: .automatic, to: textView)
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if handleAutoPeriodReplacement(in: textView, range: range, replacementText: text) {
                return false
            }

            // Handle return key for auto-numbering and auto-formatting
            if text == "\n" {
                return handleReturnKey(textView: textView, range: range)
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
                self?.pushTextToParent(updatedText)
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

            let fallback = effectiveColorComponents()
            if attributes[NSAttributedString.Key.foregroundColor] == nil {
                if let color = fallback.color {
                    attributes[NSAttributedString.Key.foregroundColor] = color
                } else {
                    attributes.removeValue(forKey: NSAttributedString.Key.foregroundColor)
                }
            }
            if attributes[ColorMapping.colorIDKey] == nil {
                if let id = fallback.id {
                    attributes[ColorMapping.colorIDKey] = id
                } else {
                    attributes.removeValue(forKey: ColorMapping.colorIDKey)
                }
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
            pushTextToParent(mutableText)
            isProgrammaticUpdate = false

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

            if let updated = textView.attributedText {
                pushTextToParent(updated)
            }
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

            if let updated = textView.attributedText {
                pushTextToParent(updated)
            }
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

            // Push update to parent synchronously to ensure binding is updated before isProgrammaticUpdate is reset
            pushTextToParent(attributedText)
            isProgrammaticUpdate = false
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
            pushTextToParent(updatedText)
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
            pushTextToParent(updatedText)
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
            pushTextToParent(updatedText)
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
            pushTextToParent(updatedText)
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
            pushTextToParent(updatedText)
            isProgrammaticUpdate = false
        }

    }
}

#endif
