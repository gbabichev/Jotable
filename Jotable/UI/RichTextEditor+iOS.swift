#if !os(macOS)
import SwiftUI
import UIKit

// Custom UITextView subclass to handle image pasting
private class PastableTextView: UITextView {
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)) {
            return UIPasteboard.general.image != nil || UIPasteboard.general.hasStrings
        }
        return super.canPerformAction(action, withSender: sender)
    }

    override func paste(_ sender: Any?) {
        let pasteboard = UIPasteboard.general

        // Handle image paste
        if let image = pasteboard.image {
            let attachment = NSTextAttachment()
            attachment.image = image

            // Scale image to reasonable size
            let maxWidth: CGFloat = 400
            let maxHeight: CGFloat = 400
            var imageSize = image.size
            if imageSize.width > maxWidth {
                let scale = maxWidth / imageSize.width
                imageSize = CGSize(width: maxWidth, height: imageSize.height * scale)
            }
            if imageSize.height > maxHeight {
                let scale = maxHeight / imageSize.height
                imageSize = CGSize(width: imageSize.width * scale, height: maxHeight)
            }

            attachment.bounds = CGRect(origin: .zero, size: imageSize)

            let attributedString = NSAttributedString(attachment: attachment)
            let range = selectedRange

            if let mutableText = attributedText?.mutableCopy() as? NSMutableAttributedString {
                mutableText.insert(attributedString, at: range.location)
                attributedText = mutableText

                let newCursorPosition = range.location + 1
                selectedRange = NSRange(location: newCursorPosition, length: 0)

                // Notify delegates of the change
                delegate?.textViewDidChange?(self)
            }
            return
        }

        // Fall back to default paste for text
        super.paste(sender)
    }
}

struct RichTextEditor: UIViewRepresentable {
    @Binding var text: NSAttributedString
    @Binding var activeColor: RichTextColor
    @Binding var activeHighlighter: HighlighterColor
    @Binding var activeFontSize: FontSize
    @Binding var isBold: Bool
    @Binding var isItalic: Bool
    @Binding var isUnderlined: Bool
    @Binding var isStrikethrough: Bool
    @Binding var insertUncheckedCheckboxTrigger: UUID?
    @Binding var insertDashTrigger: UUID?
    @Binding var insertBulletTrigger: UUID?
    @Binding var insertNumberingTrigger: UUID?
    @Binding var dateInsertionRequest: DateInsertionRequest?
    @Binding var timeInsertionRequest: TimeInsertionRequest?
    @Binding var insertURLTrigger: URLInsertionRequest?
    @Binding var presentFormatMenuTrigger: UUID?
    @Binding var resetColorTrigger: UUID?
    @Binding var linkEditRequest: LinkEditContext?
    @Environment(\.colorScheme) var colorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = PastableTextView()
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
        textView.allowsEditingTextAttributes = false
        context.coordinator.textView = textView
        context.coordinator.applyTypingAttributes(to: textView)

        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.textView = uiView

        // CRITICAL: Skip most updateUIView calls during rapid feedback to prevent native format sheet freeze
        // The native color/font sheet causes SwiftUI to call updateUIView thousands of times per second
        // Only process significant updates, not every state change
        let now = Date()
        let timeSinceLastUpdate = now.timeIntervalSince(context.coordinator.lastUpdateUIViewTime)

        // During native sheet interaction, only update every 50ms
        // This dramatically reduces redundant work while keeping the UI responsive
        if timeSinceLastUpdate < 0.05 && context.coordinator.lastUpdateUIViewText == text {
            // Skip this update - it's a duplicate within the throttle window
            return
        }

        context.coordinator.lastUpdateUIViewTime = now
        context.coordinator.lastUpdateUIViewText = text

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

        if context.coordinator.isItalic != isItalic {
            context.coordinator.isItalic = isItalic
            context.coordinator.toggleItalic(uiView)
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

        // Handle dash insertion trigger
        if insertDashTrigger != context.coordinator.lastDashTrigger {
            context.coordinator.lastDashTrigger = insertDashTrigger
            context.coordinator.insertDash()
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
        if dateInsertionRequest?.id != context.coordinator.lastDateRequest?.id {
            context.coordinator.lastDateRequest = dateInsertionRequest
            if let request = dateInsertionRequest {
                context.coordinator.insertDate(using: request.format)
            }
        }

        // Handle time insertion request
        if timeInsertionRequest?.id != context.coordinator.lastTimeRequest?.id {
            context.coordinator.lastTimeRequest = timeInsertionRequest
            if let request = timeInsertionRequest {
                context.coordinator.insertTime(using: request.format)
            }
        }

        // Handle URL insertion trigger
        if insertURLTrigger?.id != context.coordinator.lastURLTrigger?.id {
            context.coordinator.lastURLTrigger = insertURLTrigger
            if let request = insertURLTrigger {
                context.coordinator.insertURL(using: request)
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
        var isItalic: Bool
        var isUnderlined: Bool
        var isStrikethrough: Bool
        var isProgrammaticUpdate = false
        var lastUncheckedCheckboxTrigger: UUID?
        var lastDashTrigger: UUID?
        var lastBulletTrigger: UUID?
        var lastNumberingTrigger: UUID?
        var lastDateRequest: DateInsertionRequest?
        var lastTimeRequest: TimeInsertionRequest?
        var lastURLTrigger: URLInsertionRequest?
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
        var lastUpdateUIViewTime: Date = Date.distantPast
        var lastUpdateUIViewText: NSAttributedString = NSAttributedString()

        private func pushTextToParent(_ text: NSAttributedString) {
            let snapshot = NSAttributedString(attributedString: text)
            DispatchQueue.main.async { [weak self] in
                self?.parent.text = snapshot
            }
        }

        private func registerUndoSnapshot(for textView: UITextView,
                                          actionName: String,
                                          textSnapshot: NSAttributedString? = nil,
                                          selectionSnapshot: NSRange? = nil) {
            guard let undoManager = textView.undoManager else { return }

            let snapshot = NSAttributedString(attributedString: textSnapshot ?? (textView.attributedText ?? NSAttributedString()))
            let selection = selectionSnapshot ?? textView.selectedRange
            let targetTextView = textView

            undoManager.registerUndo(withTarget: self) { [weak self] _ in
                guard let self = self else { return }
                let currentText = NSAttributedString(attributedString: targetTextView.attributedText ?? NSAttributedString())
                let currentSelection = targetTextView.selectedRange
                self.registerUndoSnapshot(for: targetTextView,
                                          actionName: actionName,
                                          textSnapshot: currentText,
                                          selectionSnapshot: currentSelection)

                self.isProgrammaticUpdate = true
                targetTextView.attributedText = snapshot
                targetTextView.selectedRange = selection
                self.applyTypingAttributes(to: targetTextView)
                self.updateTypingAttributesHighlight(targetTextView)
                self.pushTextToParent(snapshot)
                self.isProgrammaticUpdate = false
            }

            undoManager.setActionName(actionName)
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

        func syncFormattingState(with textView: UITextView) {
            let selectedRange = textView.selectedRange

            var attrs: [NSAttributedString.Key: Any]? = nil

            // First try to get attributes from selected text
            if selectedRange.length > 0,
               let attributed = textView.attributedText,
               selectedRange.location < attributed.length {
                attrs = attributed.attributes(at: selectedRange.location, effectiveRange: nil)
            } else {
                // If no selection, use typing attributes (which will have been updated by the native menu)
                attrs = textView.typingAttributes
            }

            guard let attrs = attrs else { return }

            let font = attrs[NSAttributedString.Key.font] as? UIFont
            let sampledBold = font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false
            let sampledItalic = font?.fontDescriptor.symbolicTraits.contains(.traitItalic) ?? false

            let underlineValue = attrs[NSAttributedString.Key.underlineStyle] as? Int ?? 0
            let sampledUnderline = underlineValue != 0

            let strikethroughValue = attrs[NSAttributedString.Key.strikethroughStyle] as? Int ?? 0
            let sampledStrikethrough = strikethroughValue != 0

            // ALWAYS update state to match what we sampled, regardless of previous state
            // This ensures consistency after native menu changes
            if sampledBold != isBold {
                isBold = sampledBold
                DispatchQueue.main.async { [weak self] in
                    self?.parent.isBold = sampledBold
                }
            } else if sampledBold != parent.isBold {
                // Ensure parent binding is in sync even if coordinator state matches
                DispatchQueue.main.async { [weak self] in
                    self?.parent.isBold = sampledBold
                }
            }

            if sampledItalic != isItalic {
                isItalic = sampledItalic
                DispatchQueue.main.async { [weak self] in
                    self?.parent.isItalic = sampledItalic
                }
            } else if sampledItalic != parent.isItalic {
                DispatchQueue.main.async { [weak self] in
                    self?.parent.isItalic = sampledItalic
                }
            }

            if sampledUnderline != isUnderlined {
                isUnderlined = sampledUnderline
                DispatchQueue.main.async { [weak self] in
                    self?.parent.isUnderlined = sampledUnderline
                }
            } else if sampledUnderline != parent.isUnderlined {
                DispatchQueue.main.async { [weak self] in
                    self?.parent.isUnderlined = sampledUnderline
                }
            }

            if sampledStrikethrough != isStrikethrough {
                isStrikethrough = sampledStrikethrough
                DispatchQueue.main.async { [weak self] in
                    self?.parent.isStrikethrough = sampledStrikethrough
                }
            } else if sampledStrikethrough != parent.isStrikethrough {
                DispatchQueue.main.async { [weak self] in
                    self?.parent.isStrikethrough = sampledStrikethrough
                }
            }
        }

        init(_ parent: RichTextEditor) {
            self.parent = parent
            self.activeColor = parent.activeColor
            self.activeHighlighter = parent.activeHighlighter
            self.activeFontSize = parent.activeFontSize
            self.isBold = parent.isBold
            self.isItalic = parent.isItalic
            self.isUnderlined = parent.isUnderlined
            self.isStrikethrough = parent.isStrikethrough
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isProgrammaticUpdate else { return }
            lastTextViewDidChangeTime = Date().timeIntervalSinceReferenceDate

            syncColorState(with: textView, sampleFromText: true)
            syncFormattingState(with: textView)
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
            syncFormattingState(with: textView)
            applyTypingAttributes(to: textView)
        }

        @available(iOS 16.0, *)
        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            return buildEditMenu(for: [range], in: textView, suggestedActions: suggestedActions)
        }

        @available(iOS 26.0, *)
        func textView(_ textView: UITextView, editMenuForTextInRanges ranges: [NSValue], suggestedActions: [UIMenuElement]) -> UIMenu? {
            let nsRanges = ranges.map { $0.rangeValue }
            return buildEditMenu(for: nsRanges, in: textView, suggestedActions: suggestedActions)
        }

        private func buildEditMenu(for ranges: [NSRange], in textView: UITextView, suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard let context = linkContext(for: ranges, in: textView) else {
                return UIMenu(children: suggestedActions)
            }

            var elements = suggestedActions
            let editAction = UIAction(title: "Edit Link", image: UIImage(systemName: "link")) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.parent.linkEditRequest = context
                }
            }
            elements.append(editAction)
            return UIMenu(children: elements)
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
            var sampledBold: Bool?
            var sampledUnderline: Bool?
            var sampledStrikethrough: Bool?

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

                    // Only sample bold, underline, and strikethrough if there's a selection
                    // When no text is selected, we should use typing attributes, not sample from cursor position
                    if textView.selectedRange.length > 0 {
                        let font = attrs[NSAttributedString.Key.font] as? UIFont
                        sampledBold = font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false

                        let underlineValue = attrs[NSAttributedString.Key.underlineStyle] as? Int ?? 0
                        sampledUnderline = underlineValue != 0

                        let strikethroughValue = attrs[NSAttributedString.Key.strikethroughStyle] as? Int ?? 0
                        sampledStrikethrough = strikethroughValue != 0
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

            // Update bold, underline, and strikethrough state if sampled
            if let sampledBold, sampledBold != isBold {
                isBold = sampledBold
                DispatchQueue.main.async { [weak self] in
                    self?.parent.isBold = sampledBold
                }
            }

            if let sampledUnderline, sampledUnderline != isUnderlined {
                isUnderlined = sampledUnderline
                DispatchQueue.main.async { [weak self] in
                    self?.parent.isUnderlined = sampledUnderline
                }
            }

            if let sampledStrikethrough, sampledStrikethrough != isStrikethrough {
                isStrikethrough = sampledStrikethrough
                DispatchQueue.main.async { [weak self] in
                    self?.parent.isStrikethrough = sampledStrikethrough
                }
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
            let components = effectiveColorComponents()
            let usingAutomatic = customTypingColor == nil && activeColor == .automatic

            let styler = TextStyler(
                isBold: isBold,
                isItalic: isItalic,
                fontSize: activeFontSize,
                colorID: components.id,
                color: components.color,
                highlightID: activeHighlighter == .none ? nil : activeHighlighter.id,
                highlight: activeHighlighter.uiColor,
                isUnderlined: isUnderlined,
                isStrikethrough: isStrikethrough
            )

            return styler.buildAttributes(usingAutomatic: usingAutomatic, customColor: customTypingColor)
        }

        private func matchesAutomaticColor(_ color: UIColor, in textView: UITextView?) -> Bool {
            let trait: UITraitCollection
            if let textView = textView {
                trait = textView.traitCollection
            } else {
                trait = UITraitCollection(userInterfaceStyle: .unspecified)
            }
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

                let styler = TextStyler(isBold: isBold, isItalic: isItalic, fontSize: activeFontSize)
                let font = styler.buildFont()

                currentText.addAttribute(NSAttributedString.Key.font, value: font, range: selectedRange)
                textView.attributedText = currentText
                textView.selectedRange = selectedRange
                pushTextToParent(currentText)
                isProgrammaticUpdate = false
            }

            applyTypingAttributes(to: textView)
        }

        func toggleItalic(_ textView: UITextView) {
            let selectedRange = textView.selectedRange
            if selectedRange.length > 0,
               let currentText = textView.attributedText?.mutableCopy() as? NSMutableAttributedString {
                isProgrammaticUpdate = true

                let styler = TextStyler(isBold: isBold, isItalic: isItalic, fontSize: activeFontSize)
                let font = styler.buildFont()

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

            // Update the attachment's internal data representation to ensure proper serialization
            // This is critical for checkbox state persistence when archiving
            let stateDict: [String: Any] = ["checkboxID": checkbox.checkboxID, "isChecked": checkbox.isChecked]
            if let stateData = try? JSONSerialization.data(withJSONObject: stateDict) {
                checkbox.contents = stateData
            }

            // Notify the text storage that attributes changed to trigger a layout update
            textView.textStorage.edited(.editedAttributes, range: range, changeInLength: 0)

            // Add a marker attribute to force change detection
            // since NSAttributedString.isEqual won't detect checkbox state changes
            let textStorage = textView.textStorage
            if textStorage.length > 0 {
                textStorage.addAttribute(NSAttributedString.Key(rawValue: "checkboxStateChanged"), value: NSNumber(value: Date().timeIntervalSince1970), range: NSRange(location: 0, length: 1))
            }

            // Sync the updated text to parent state
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

            // Check for numbered list pattern with renumbering
            if let result = AutoFormatting.handleNumberedListWithRenumbering(lineText: lineInfo.text, fullText: plainText, insertionIndex: range.location) {
                registerUndoSnapshot(for: textView, actionName: "Insert Number")
                isProgrammaticUpdate = true

                // If newText is just "\n", replace the entire line (removes formatting)
                let replacementRange = result.newText == "\n" ? lineInfo.range : range
                textView.textStorage.replaceCharacters(in: replacementRange, with: result.newText)

                // Then renumber subsequent lines if needed
                if !result.renumberPositions.isEmpty {
                    // Adjust positions based on how much text was inserted
                    let textInserted = result.newText.count
                    for (range, newNumber) in result.renumberPositions.reversed() {
                        let adjustedRange = NSRange(location: range.location + textInserted, length: range.length)
                        let newNumberText = "\(newNumber). "
                        let fontAttrs = currentTypingAttributes(from: textView)
                        let newNumberString = NSAttributedString(string: newNumberText, attributes: fontAttrs)
                        textView.textStorage.replaceCharacters(in: adjustedRange, with: newNumberString)
                    }
                }

                // Position cursor after the inserted text
                let newCursorPosition = replacementRange.location + result.newText.count
                textView.selectedRange = NSRange(location: newCursorPosition, length: 0)

                if let updated = textView.attributedText {
                    pushTextToParent(updated)
                }
                isProgrammaticUpdate = false

                return false  // We handled it
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
            if attributedString.attribute(NSAttributedString.Key.attachment, at: lineRange.location, longestEffectiveRange: nil, in: lineRange) is CheckboxTextAttachment {
                hasCheckboxAtStart = true
                contentStartsAfter = lineRange.location + 1
            }

            guard hasCheckboxAtStart else { return false }

            // Check if there's content after the checkbox
            let remainingRange = NSRange(location: contentStartsAfter, length: lineRange.location + lineRange.length - contentStartsAfter)
            let contentAfter = attributedString.attributedSubstring(from: remainingRange).string
                .trimmingCharacters(in: .whitespacesAndNewlines)

            registerUndoSnapshot(for: textView, actionName: "Insert Checkbox")
            isProgrammaticUpdate = true

            var newCursorPosition = cursorRange.location

            if contentAfter.isEmpty {
                // Blank line after checkbox - remove the checkbox, just add newline with proper attributes
                let fontAttrs = currentTypingAttributes(from: textView)
                let newlineWithAttrs = NSAttributedString(string: "\n", attributes: fontAttrs)
                textView.textStorage.replaceCharacters(in: lineRange, with: newlineWithAttrs)

                newCursorPosition = min(lineRange.location, textView.textStorage.length)
            } else {
                // Content after checkbox - insert newline and new checkbox at cursor position
                let newCheckbox = CheckboxTextAttachment(checkboxID: UUID().uuidString, isChecked: false)
                let newCheckboxString = NSAttributedString(attachment: newCheckbox)

                // Add font attributes for proper rendering
                let fontAttrs = currentTypingAttributes(from: textView)

                let newLine = NSMutableAttributedString(string: "\n", attributes: fontAttrs)
                newLine.append(newCheckboxString)

                // Add space after checkbox with minimal attributes (just font) to avoid rendering issues
                let baseFont = UIFont.systemFont(ofSize: activeFontSize.rawValue)
                let spaceAttrs: [NSAttributedString.Key: Any] = [.font: baseFont]
                newLine.append(NSAttributedString(string: " ", attributes: spaceAttrs))

                // Insert the newline + checkbox + space at the cursor location so the existing newline stays intact
                textView.textStorage.replaceCharacters(in: cursorRange, with: newLine)

                newCursorPosition = min(cursorRange.location + newLine.length, textView.textStorage.length)
            }

            // Position cursor after the inserted content
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
            registerUndoSnapshot(for: textView, actionName: "Auto Format")
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

        private func renumberLinesInTextView(_ textView: UITextView, positions: [(range: NSRange, newNumber: Int)]) {
            guard let mutableText = textView.attributedText?.mutableCopy() as? NSMutableAttributedString else {
                return
            }

            isProgrammaticUpdate = true

            // Process renumbering in reverse order to avoid position shifting
            for (range, newNumber) in positions.reversed() {
                let newNumberText = "\(newNumber). "
                let fontAttrs = currentTypingAttributes(from: textView)
                let newNumberString = NSAttributedString(string: newNumberText, attributes: fontAttrs)
                mutableText.replaceCharacters(in: range, with: newNumberString)
            }

            textView.attributedText = mutableText
            pushTextToParent(mutableText)
            isProgrammaticUpdate = false
        }

        func insertUncheckedCheckbox() {
            guard let textView = textView else {
                return
            }

            isProgrammaticUpdate = true

            let selectedRange = textView.selectedRange

            // Check if multiple lines are selected
            if selectedRange.length > 0 {
                // Multiple lines selected - add checkbox to start of each line
                let selectedText = textView.textStorage.attributedSubstring(from: selectedRange).string
                let lines = selectedText.components(separatedBy: .newlines)

                if lines.count > 1 {
                    // We have multiple lines - process each one
                    insertCheckboxForMultipleLines(range: selectedRange, lines: lines)
                } else {
                    // Single line selected - use original behavior
                    insertCheckboxAtPosition(insertionRange: selectedRange)
                }
            } else {
                // No selection - insert at cursor position
                insertCheckboxAtPosition(insertionRange: selectedRange)
            }

            applyTypingAttributes(to: textView)
            pushTextToParent(textView.attributedText ?? NSAttributedString())
            isProgrammaticUpdate = false
        }

        private func insertCheckboxAtPosition(insertionRange: NSRange) {
            guard let textView = textView else { return }
            let checkbox = CheckboxTextAttachment(checkboxID: UUID().uuidString, isChecked: false)
            let checkboxString = NSAttributedString(attachment: checkbox)

            // Use textStorage to properly register with undo manager
            textView.textStorage.insert(checkboxString, at: insertionRange.location)

            // Insert space after checkbox if next character is not already a space
            let spaceInsertionPos = insertionRange.location + 1
            if spaceInsertionPos < textView.textStorage.length {
                let nextCharRange = NSRange(location: spaceInsertionPos, length: 1)
                let nextChar = textView.textStorage.attributedSubstring(from: nextCharRange).string
                if nextChar != " " {
                    // Space after attachment should have minimal attributes to avoid rendering issues
                    // Only include font to ensure proper baseline alignment
                    let baseFont = UIFont.systemFont(ofSize: activeFontSize.rawValue)
                    let spaceAttrs: [NSAttributedString.Key: Any] = [.font: baseFont]
                    textView.textStorage.insert(NSAttributedString(string: " ", attributes: spaceAttrs), at: spaceInsertionPos)
                }
            } else {
                // End of text, just add space with minimal attributes
                let baseFont = UIFont.systemFont(ofSize: activeFontSize.rawValue)
                let spaceAttrs: [NSAttributedString.Key: Any] = [.font: baseFont]
                textView.textStorage.insert(NSAttributedString(string: " ", attributes: spaceAttrs), at: spaceInsertionPos)
            }

            let newCursorPosition = spaceInsertionPos + 1
            textView.selectedRange = NSRange(location: newCursorPosition, length: 0)
        }

        private func insertCheckboxForMultipleLines(range: NSRange, lines: [String]) {
            guard let textView = textView else { return }
            let baseFont = UIFont.systemFont(ofSize: activeFontSize.rawValue)
            let spaceAttrs: [NSAttributedString.Key: Any] = [.font: baseFont]
            let fullText = textView.textStorage.string

            // Find the start and end positions in the original text
            let selectedStart = range.location
            let selectedEnd = range.location + range.length

            // Find line boundaries in the selected range
            // First, find the start of the line containing selectedStart
            var lineStartPos = selectedStart
            while lineStartPos > 0 && fullText[fullText.index(fullText.startIndex, offsetBy: lineStartPos - 1)] != "\n" {
                lineStartPos -= 1
            }

            // Find all line starts in the selected range
            var lineBoundaries: [Int] = [lineStartPos]
            var currentPos = lineStartPos

            while currentPos < selectedEnd {
                let charIndex = fullText.index(fullText.startIndex, offsetBy: currentPos)
                if currentPos < fullText.count && fullText[charIndex] == "\n" && currentPos + 1 < selectedEnd {
                    lineBoundaries.append(currentPos + 1)
                }
                currentPos += 1
            }

            // Track total insertions
            var totalInserted = 0

            // Group all edits into a single undo action
            textView.textStorage.beginEditing()

            // Process lines in reverse to avoid position shifting issues
            for i in stride(from: lineBoundaries.count - 1, through: 0, by: -1) {
                let lineStart = lineBoundaries[i]

                // Find line end (newline or end of string)
                var lineEnd = lineStart
                while lineEnd < fullText.count && fullText[fullText.index(fullText.startIndex, offsetBy: lineEnd)] != "\n" {
                    lineEnd += 1
                }

                // Get the line content (without newline)
                let lineRange = NSRange(location: lineStart, length: lineEnd - lineStart)
                let lineContent = textView.textStorage.attributedSubstring(from: lineRange).string

                // Skip empty lines
                if lineContent.trimmingCharacters(in: .whitespaces).isEmpty {
                    continue
                }

                // Check for and remove existing formatting at the start of the line
                var existingFormattingLength = 0

                // Check for existing checkbox attachment
                if lineStart < textView.textStorage.length {
                    if textView.textStorage.attribute(NSAttributedString.Key.attachment, at: lineStart, longestEffectiveRange: nil, in: lineRange) is CheckboxTextAttachment {
                        // Remove the checkbox and the space after it
                        existingFormattingLength = 2 // checkbox + space
                    }
                }

                // If no checkbox, check for dash, bullet, or number patterns
                if existingFormattingLength == 0 {
                    if let dashMatch = lineContent.range(of: #"^-\s"#, options: .regularExpression) {
                        existingFormattingLength = lineContent.distance(from: lineContent.startIndex, to: dashMatch.upperBound)
                    } else if let bulletCharMatch = lineContent.range(of: #"^•\s"#, options: .regularExpression) {
                        existingFormattingLength = lineContent.distance(from: lineContent.startIndex, to: bulletCharMatch.upperBound)
                    } else if let numberMatch = lineContent.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                        existingFormattingLength = lineContent.distance(from: lineContent.startIndex, to: numberMatch.upperBound)
                    }
                }

                // Remove existing formatting if found
                if existingFormattingLength > 0 {
                    textView.textStorage.deleteCharacters(in: NSRange(location: lineStart, length: existingFormattingLength))
                    totalInserted -= existingFormattingLength
                }

                // Insert checkbox at the beginning of this line
                let checkbox = CheckboxTextAttachment(checkboxID: UUID().uuidString, isChecked: false)
                let checkboxString = NSAttributedString(attachment: checkbox)

                guard lineStart <= textView.textStorage.length else { continue }
                textView.textStorage.insert(checkboxString, at: lineStart)
                totalInserted += 1

                // Check what character comes after the checkbox
                let charAfterCheckbox = lineStart + 1
                if charAfterCheckbox < textView.textStorage.length {
                    let nextCharRange = NSRange(location: charAfterCheckbox, length: 1)
                    let nextChar = textView.textStorage.attributedSubstring(from: nextCharRange).string
                    if nextChar != " " && nextChar != "\n" {
                        textView.textStorage.insert(NSAttributedString(string: " ", attributes: spaceAttrs), at: charAfterCheckbox)
                        totalInserted += 1
                    }
                }
            }

            textView.textStorage.endEditing()

            // Place cursor at the end of the selected range plus all insertions
            let newCursorPos = selectedEnd + totalInserted
            textView.selectedRange = NSRange(location: newCursorPos, length: 0)
        }

        func insertDash() {
            guard let textView = textView else {
                return
            }

            registerUndoSnapshot(for: textView, actionName: "Insert Dash")
            isProgrammaticUpdate = true

            print("[DEBUG insertDash] Starting - textStorage length: \(textView.textStorage.length)")
            print("[DEBUG insertDash] textStorage content: '\(textView.textStorage.string)'")
            print("[DEBUG insertDash] selectedRange: \(textView.selectedRange)")
            if let undoManager = textView.undoManager {
                print("[DEBUG insertDash] undoManager: \(undoManager)")
            } else {
                print("[DEBUG insertDash] undoManager: nil")
            }
            print("[DEBUG insertDash] undoManager?.isUndoing: \(textView.undoManager?.isUndoing ?? false)")
            print("[DEBUG insertDash] undoManager?.isRedoing: \(textView.undoManager?.isRedoing ?? false)")

            let selectedRange = textView.selectedRange

            // Check if multiple lines are selected
            if selectedRange.length > 0 {
                let selectedText = textView.textStorage.attributedSubstring(from: selectedRange).string
                let lines = selectedText.components(separatedBy: .newlines)

                print("[DEBUG insertDash] Selected text: '\(selectedText)'")
                print("[DEBUG insertDash] Number of lines: \(lines.count)")

                if lines.count > 1 {
                    // Multiple lines selected
                    print("[DEBUG insertDash] Calling insertDashForMultipleLines")
                    insertDashForMultipleLines(range: selectedRange, lines: lines)
                } else {
                    // Single line selected - use original behavior
                    print("[DEBUG insertDash] Calling insertDashAtPosition")
                    insertDashAtPosition(insertionRange: selectedRange)
                }
            } else {
                // No selection - insert at cursor position
                print("[DEBUG insertDash] No selection - calling insertDashAtPosition")
                insertDashAtPosition(insertionRange: selectedRange)
            }

            print("[DEBUG insertDash] After insertion - textStorage length: \(textView.textStorage.length)")
            print("[DEBUG insertDash] After insertion - textStorage content: '\(textView.textStorage.string)'")
            print("[DEBUG insertDash] undoManager?.canUndo: \(textView.undoManager?.canUndo ?? false)")
            print("[DEBUG insertDash] undoManager?.undoCount: \(textView.undoManager?.undoCount ?? 0)")

            applyTypingAttributes(to: textView)
            pushTextToParent(textView.attributedText ?? NSAttributedString())

            print("[DEBUG insertDash] After pushTextToParent - textStorage content: '\(textView.textStorage.string)'")
            print("[DEBUG insertDash] After pushTextToParent - undoManager?.canUndo: \(textView.undoManager?.canUndo ?? false)")
            isProgrammaticUpdate = false
        }

        private func insertDashAtPosition(insertionRange: NSRange) {
            guard let textView = textView else { return }
            let dashText = "- "
            let fontAttrs = currentTypingAttributes(from: textView)
            let dashString = NSAttributedString(string: dashText, attributes: fontAttrs)

            // Use textStorage to properly register with undo manager
            textView.textStorage.insert(dashString, at: insertionRange.location)

            let newCursorPosition = insertionRange.location + dashText.count
            setCursorPosition(NSRange(location: newCursorPosition, length: 0), in: textView)
        }

        private func insertDashForMultipleLines(range: NSRange, lines: [String]) {
            guard let textView = textView else { return }
            let fontAttrs = currentTypingAttributes(from: textView)
            let dashText = "- "
            let fullText = textView.textStorage.string

            print("[DEBUG insertDashForMultipleLines] Starting - textStorage length: \(textView.textStorage.length)")
            print("[DEBUG insertDashForMultipleLines] fullText: '\(fullText)'")
            print("[DEBUG insertDashForMultipleLines] range: \(range)")
            print("[DEBUG insertDashForMultipleLines] lines: \(lines)")

            // Find the start and end positions in the original text
            let selectedStart = range.location
            let selectedEnd = range.location + range.length

            // Find line boundaries
            var lineStartPos = selectedStart
            while lineStartPos > 0 && fullText[fullText.index(fullText.startIndex, offsetBy: lineStartPos - 1)] != "\n" {
                lineStartPos -= 1
            }

            // Find all line starts in the selected range
            var lineBoundaries: [Int] = [lineStartPos]
            var currentPos = lineStartPos

            while currentPos < selectedEnd {
                let charIndex = fullText.index(fullText.startIndex, offsetBy: currentPos)
                if currentPos < fullText.count && fullText[charIndex] == "\n" && currentPos + 1 < selectedEnd {
                    lineBoundaries.append(currentPos + 1)
                }
                currentPos += 1
            }

            print("[DEBUG insertDashForMultipleLines] lineBoundaries: \(lineBoundaries)")

            // Track total insertions
            var totalInserted = 0

            // Group all edits into a single undo action
            print("[DEBUG insertDashForMultipleLines] Calling beginEditing()")
            textView.textStorage.beginEditing()

            // Process lines in reverse to avoid position shifting issues
            for i in stride(from: lineBoundaries.count - 1, through: 0, by: -1) {
                let lineStart = lineBoundaries[i]
                print("[DEBUG insertDashForMultipleLines] Processing line \(i) - lineStart: \(lineStart)")

                // Find line end (newline or end of string)
                var lineEnd = lineStart
                while lineEnd < fullText.count && fullText[fullText.index(fullText.startIndex, offsetBy: lineEnd)] != "\n" {
                    lineEnd += 1
                }

                // Get the line content
                let lineRange = NSRange(location: lineStart, length: lineEnd - lineStart)
                let lineContent = textView.textStorage.attributedSubstring(from: lineRange).string
                print("[DEBUG insertDashForMultipleLines] lineContent: '\(lineContent)'")

                // Skip empty lines
                if lineContent.trimmingCharacters(in: .whitespaces).isEmpty {
                    print("[DEBUG insertDashForMultipleLines] Skipping empty line")
                    continue
                }

                // Check for and remove existing formatting at the start of the line
                var existingFormattingLength = 0

                // Check for checkbox attachment
                if lineStart < textView.textStorage.length {
                    if textView.textStorage.attribute(NSAttributedString.Key.attachment, at: lineStart, longestEffectiveRange: nil, in: lineRange) is CheckboxTextAttachment {
                        // Remove the checkbox and the space after it
                        existingFormattingLength = 2 // checkbox + space
                        print("[DEBUG insertDashForMultipleLines] Found checkbox attachment")
                    }
                }

                // If no checkbox, check for dash, bullet, or number patterns
                if existingFormattingLength == 0 {
                    if let dashMatch = lineContent.range(of: #"^-\s"#, options: .regularExpression) {
                        existingFormattingLength = lineContent.distance(from: lineContent.startIndex, to: dashMatch.upperBound)
                        print("[DEBUG insertDashForMultipleLines] Found dash pattern, length: \(existingFormattingLength)")
                    } else if let bulletCharMatch = lineContent.range(of: #"^•\s"#, options: .regularExpression) {
                        existingFormattingLength = lineContent.distance(from: lineContent.startIndex, to: bulletCharMatch.upperBound)
                        print("[DEBUG insertDashForMultipleLines] Found bullet pattern, length: \(existingFormattingLength)")
                    } else if let numberMatch = lineContent.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                        existingFormattingLength = lineContent.distance(from: lineContent.startIndex, to: numberMatch.upperBound)
                        print("[DEBUG insertDashForMultipleLines] Found number pattern, length: \(existingFormattingLength)")
                    }
                }

                // Remove existing formatting if found
                if existingFormattingLength > 0 {
                    print("[DEBUG insertDashForMultipleLines] Removing \(existingFormattingLength) chars of existing formatting")
                    textView.textStorage.deleteCharacters(in: NSRange(location: lineStart, length: existingFormattingLength))
                    totalInserted -= existingFormattingLength
                }

                // Insert dash at the beginning of this line
                guard lineStart <= textView.textStorage.length else {
                    print("[DEBUG insertDashForMultipleLines] lineStart \(lineStart) > textStorage.length \(textView.textStorage.length)")
                    continue
                }
                print("[DEBUG insertDashForMultipleLines] Inserting dash at \(lineStart)")
                let dashString = NSAttributedString(string: dashText, attributes: fontAttrs)
                textView.textStorage.insert(dashString, at: lineStart)
                totalInserted += dashText.count
                print("[DEBUG insertDashForMultipleLines] totalInserted now: \(totalInserted), textStorage now: '\(textView.textStorage.string)'")
            }

            print("[DEBUG insertDashForMultipleLines] Calling endEditing()")
            textView.textStorage.endEditing()
            print("[DEBUG insertDashForMultipleLines] After endEditing() - textStorage: '\(textView.textStorage.string)'")

            // Place cursor at the end of the selected range plus all insertions
            let newCursorPos = selectedEnd + totalInserted
            print("[DEBUG insertDashForMultipleLines] Setting cursor to \(newCursorPos)")
            textView.selectedRange = NSRange(location: newCursorPos, length: 0)
            print("[DEBUG insertDashForMultipleLines] Final textStorage: '\(textView.textStorage.string)'")
        }

        func insertBullet() {
            guard let textView = textView else {
                return
            }

            registerUndoSnapshot(for: textView, actionName: "Insert Bullet")
            isProgrammaticUpdate = true

            let selectedRange = textView.selectedRange

            // Check if multiple lines are selected
            if selectedRange.length > 0 {
                let selectedText = textView.textStorage.attributedSubstring(from: selectedRange).string
                let lines = selectedText.components(separatedBy: .newlines)

                if lines.count > 1 {
                    // Multiple lines selected
                    insertBulletForMultipleLines(range: selectedRange, lines: lines)
                } else {
                    // Single line selected - use original behavior
                    insertBulletAtPosition(insertionRange: selectedRange)
                }
            } else {
                // No selection - insert at cursor position
                insertBulletAtPosition(insertionRange: selectedRange)
            }

            applyTypingAttributes(to: textView)
            pushTextToParent(textView.attributedText ?? NSAttributedString())
            isProgrammaticUpdate = false
        }

        private func insertBulletAtPosition(insertionRange: NSRange) {
            guard let textView = textView else { return }
            let bulletText = "• "
            let fontAttrs = currentTypingAttributes(from: textView)
            let bulletString = NSAttributedString(string: bulletText, attributes: fontAttrs)

            // Use textStorage to properly register with undo manager
            textView.textStorage.insert(bulletString, at: insertionRange.location)

            let newCursorPosition = insertionRange.location + bulletText.count
            setCursorPosition(NSRange(location: newCursorPosition, length: 0), in: textView)
        }

        private func insertBulletForMultipleLines(range: NSRange, lines: [String]) {
            guard let textView = textView else { return }
            let fontAttrs = currentTypingAttributes(from: textView)
            let bulletText = "• "
            let fullText = textView.textStorage.string

            // Find the start and end positions in the original text
            let selectedStart = range.location
            let selectedEnd = range.location + range.length

            // Find line boundaries
            var lineStartPos = selectedStart
            while lineStartPos > 0 && fullText[fullText.index(fullText.startIndex, offsetBy: lineStartPos - 1)] != "\n" {
                lineStartPos -= 1
            }

            // Find all line starts in the selected range
            var lineBoundaries: [Int] = [lineStartPos]
            var currentPos = lineStartPos

            while currentPos < selectedEnd {
                let charIndex = fullText.index(fullText.startIndex, offsetBy: currentPos)
                if currentPos < fullText.count && fullText[charIndex] == "\n" && currentPos + 1 < selectedEnd {
                    lineBoundaries.append(currentPos + 1)
                }
                currentPos += 1
            }

            // Track total insertions
            var totalInserted = 0

            // Group all edits into a single undo action
            textView.textStorage.beginEditing()

            // Process lines in reverse to avoid position shifting issues
            for i in stride(from: lineBoundaries.count - 1, through: 0, by: -1) {
                let lineStart = lineBoundaries[i]

                // Find line end (newline or end of string)
                var lineEnd = lineStart
                while lineEnd < fullText.count && fullText[fullText.index(fullText.startIndex, offsetBy: lineEnd)] != "\n" {
                    lineEnd += 1
                }

                // Get the line content
                let lineRange = NSRange(location: lineStart, length: lineEnd - lineStart)
                let lineContent = textView.textStorage.attributedSubstring(from: lineRange).string

                // Skip empty lines
                if lineContent.trimmingCharacters(in: .whitespaces).isEmpty {
                    continue
                }

                // Check for and remove existing formatting at the start of the line
                var existingFormattingLength = 0

                // Check for checkbox attachment
                if lineStart < textView.textStorage.length {
                    if textView.textStorage.attribute(NSAttributedString.Key.attachment, at: lineStart, longestEffectiveRange: nil, in: lineRange) is CheckboxTextAttachment {
                        // Remove the checkbox and the space after it
                        existingFormattingLength = 2 // checkbox + space
                    }
                }

                // If no checkbox, check for dash, bullet, or number patterns
                if existingFormattingLength == 0 {
                    if let dashMatch = lineContent.range(of: #"^-\s"#, options: .regularExpression) {
                        existingFormattingLength = lineContent.distance(from: lineContent.startIndex, to: dashMatch.upperBound)
                    } else if let bulletCharMatch = lineContent.range(of: #"^•\s"#, options: .regularExpression) {
                        existingFormattingLength = lineContent.distance(from: lineContent.startIndex, to: bulletCharMatch.upperBound)
                    } else if let numberMatch = lineContent.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                        existingFormattingLength = lineContent.distance(from: lineContent.startIndex, to: numberMatch.upperBound)
                    }
                }

                // Remove existing formatting if found
                if existingFormattingLength > 0 {
                    textView.textStorage.deleteCharacters(in: NSRange(location: lineStart, length: existingFormattingLength))
                    totalInserted -= existingFormattingLength
                }

                // Insert bullet at the beginning of this line
                guard lineStart <= textView.textStorage.length else { continue }
                let bulletString = NSAttributedString(string: bulletText, attributes: fontAttrs)
                textView.textStorage.insert(bulletString, at: lineStart)
                totalInserted += bulletText.count
            }

            textView.textStorage.endEditing()

            // Place cursor at the end of the selected range plus all insertions
            let newCursorPos = selectedEnd + totalInserted
            textView.selectedRange = NSRange(location: newCursorPos, length: 0)
        }

        func insertNumbering() {
            guard let textView = textView else {
                return
            }

            registerUndoSnapshot(for: textView, actionName: "Insert Number")
            isProgrammaticUpdate = true

            let selectedRange = textView.selectedRange

            // Check if multiple lines are selected
            if selectedRange.length > 0 {
                let selectedText = textView.textStorage.attributedSubstring(from: selectedRange).string
                let lines = selectedText.components(separatedBy: .newlines)

                if lines.count > 1 {
                    // Multiple lines selected
                    insertNumberingForMultipleLines(range: selectedRange, lines: lines)
                } else {
                    // Single line selected - use original behavior
                    insertNumberingAtPosition(insertionRange: selectedRange)
                }
            } else {
                // No selection - insert at cursor position
                insertNumberingAtPosition(insertionRange: selectedRange)
            }

            applyTypingAttributes(to: textView)
            pushTextToParent(textView.attributedText ?? NSAttributedString())
            isProgrammaticUpdate = false
        }

        private func insertNumberingAtPosition(insertionRange: NSRange) {
            guard let textView = textView else { return }
            let numberText = "1. "
            let fontAttrs = currentTypingAttributes(from: textView)
            let numberString = NSAttributedString(string: numberText, attributes: fontAttrs)

            // Use textStorage to properly register with undo manager
            textView.textStorage.insert(numberString, at: insertionRange.location)

            // Find the start of the current line to renumber from the next line
            let fullText = textView.textStorage.string
            var lineStartPos = insertionRange.location
            while lineStartPos > 0 && fullText[fullText.index(fullText.startIndex, offsetBy: lineStartPos - 1)] != "\n" {
                lineStartPos -= 1
            }

            // Find the end of the current line
            var lineEndPos = insertionRange.location + numberText.count
            while lineEndPos < fullText.count && fullText[fullText.index(fullText.startIndex, offsetBy: lineEndPos)] != "\n" {
                lineEndPos += 1
            }

            // Renumber any subsequent numbered lines starting from the next line
            if lineEndPos < fullText.count {
                renumberSubsequentLines(in: textView.textStorage, startingAfter: lineEndPos + 1, fontAttrs: fontAttrs)
            }

            let newCursorPosition = insertionRange.location + numberText.count
            setCursorPosition(NSRange(location: newCursorPosition, length: 0), in: textView)
        }

        private func renumberSubsequentLines(in attributedText: NSMutableAttributedString, startingAfter position: Int, fontAttrs: [NSAttributedString.Key: Any]) {
            var currentPosition = position
            var currentNumber = 2

            // Process subsequent lines
            while currentPosition < attributedText.length {
                let fullText = attributedText.string

                // Find the end of the current line
                var lineEnd = currentPosition
                while lineEnd < fullText.count && fullText[fullText.index(fullText.startIndex, offsetBy: lineEnd)] != "\n" {
                    lineEnd += 1
                }

                let lineContent = attributedText.attributedSubstring(from: NSRange(location: currentPosition, length: lineEnd - currentPosition)).string

                // Check if this line starts with a number pattern
                if let match = lineContent.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                    let numberPrefixLength = lineContent.distance(from: lineContent.startIndex, to: match.upperBound)
                    let oldNumberRange = NSRange(location: currentPosition, length: numberPrefixLength)

                    // Replace with the new number
                    let newNumberText = "\(currentNumber). "
                    let newNumberString = NSAttributedString(string: newNumberText, attributes: fontAttrs)
                    attributedText.replaceCharacters(in: oldNumberRange, with: newNumberString)

                    // Adjust currentPosition based on the difference in length
                    let lengthDifference = newNumberText.count - numberPrefixLength
                    currentNumber += 1
                    currentPosition = lineEnd + lengthDifference + 1 // +1 for the newline
                } else {
                    // Line doesn't have a number pattern, stop renumbering
                    break
                }
            }
        }

        private func insertNumberingForMultipleLines(range: NSRange, lines: [String]) {
            guard let textView = textView else { return }
            let fontAttrs = currentTypingAttributes(from: textView)
            let fullText = textView.textStorage.string

            // Find the start and end positions in the original text
            let selectedStart = range.location
            let selectedEnd = range.location + range.length

            // Find line boundaries
            var lineStartPos = selectedStart
            while lineStartPos > 0 && fullText[fullText.index(fullText.startIndex, offsetBy: lineStartPos - 1)] != "\n" {
                lineStartPos -= 1
            }

            // Find all line starts in the selected range
            var lineBoundaries: [Int] = [lineStartPos]
            var currentPos = lineStartPos

            while currentPos < selectedEnd {
                let charIndex = fullText.index(fullText.startIndex, offsetBy: currentPos)
                if currentPos < fullText.count && fullText[charIndex] == "\n" && currentPos + 1 < selectedEnd {
                    lineBoundaries.append(currentPos + 1)
                }
                currentPos += 1
            }

            // Process lines in reverse to avoid position shifting issues
            var lineNumber = lineBoundaries.count
            var totalInserted = 0

            // Group all edits into a single undo action
            textView.textStorage.beginEditing()

            for i in stride(from: lineBoundaries.count - 1, through: 0, by: -1) {
                let lineStart = lineBoundaries[i]

                // Find line end (newline or end of string)
                var lineEnd = lineStart
                while lineEnd < fullText.count && fullText[fullText.index(fullText.startIndex, offsetBy: lineEnd)] != "\n" {
                    lineEnd += 1
                }

                // Get the line content
                let lineRange = NSRange(location: lineStart, length: lineEnd - lineStart)
                let lineContent = textView.textStorage.attributedSubstring(from: lineRange).string

                // Skip empty lines
                if lineContent.trimmingCharacters(in: .whitespaces).isEmpty {
                    lineNumber -= 1
                    continue
                }

                // Check for and remove existing formatting at the start of the line
                var existingFormattingLength = 0

                // Check for checkbox attachment
                if lineStart < textView.textStorage.length {
                    if textView.textStorage.attribute(NSAttributedString.Key.attachment, at: lineStart, longestEffectiveRange: nil, in: lineRange) is CheckboxTextAttachment {
                        // Remove the checkbox and the space after it
                        existingFormattingLength = 2 // checkbox + space
                    }
                }

                // If no checkbox, check for dash, bullet, or number patterns
                if existingFormattingLength == 0 {
                    if let dashMatch = lineContent.range(of: #"^-\s"#, options: .regularExpression) {
                        existingFormattingLength = lineContent.distance(from: lineContent.startIndex, to: dashMatch.upperBound)
                    } else if let bulletCharMatch = lineContent.range(of: #"^•\s"#, options: .regularExpression) {
                        existingFormattingLength = lineContent.distance(from: lineContent.startIndex, to: bulletCharMatch.upperBound)
                    } else if let numberMatch = lineContent.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                        existingFormattingLength = lineContent.distance(from: lineContent.startIndex, to: numberMatch.upperBound)
                    }
                }

                // Remove existing formatting if found
                if existingFormattingLength > 0 {
                    textView.textStorage.deleteCharacters(in: NSRange(location: lineStart, length: existingFormattingLength))
                    totalInserted -= existingFormattingLength
                }

                // Insert number at the beginning of this line
                guard lineStart <= textView.textStorage.length else {
                    lineNumber -= 1
                    continue
                }
                let numberText = "\(lineNumber). "
                let numberString = NSAttributedString(string: numberText, attributes: fontAttrs)
                textView.textStorage.insert(numberString, at: lineStart)
                totalInserted += numberText.count

                lineNumber -= 1
            }

            textView.textStorage.endEditing()

            // Place cursor at the end of the selected range plus all insertions
            let newCursorPos = selectedEnd + totalInserted
            textView.selectedRange = NSRange(location: newCursorPos, length: 0)
        }

        func insertDate(using format: DateInsertionFormat) {
            guard let textView = textView else { return }

            isProgrammaticUpdate = true
            defer { isProgrammaticUpdate = false }

            let dateText = format.formattedDate()
            let fontAttrs = currentTypingAttributes(from: textView)
            let previousTypingAttributes = textView.typingAttributes
            applyAttributesWithoutUndo(fontAttrs, to: textView)

            if let selectedTextRange = textView.selectedTextRange {
                textView.replace(selectedTextRange, withText: dateText)
            } else {
                textView.insertText(dateText)
            }
            textView.undoManager?.setActionName("Insert Date")

            applyAttributesWithoutUndo(previousTypingAttributes, to: textView)
            applyTypingAttributes(to: textView)
            pushTextToParent(textView.attributedText ?? NSAttributedString())
        }

        func insertTime(using format: TimeInsertionFormat) {
            guard let textView = textView else { return }

            isProgrammaticUpdate = true
            defer { isProgrammaticUpdate = false }

            let timeText = format.formattedTime()

            let fontAttrs = currentTypingAttributes(from: textView)
            let previousTypingAttributes = textView.typingAttributes
            applyAttributesWithoutUndo(fontAttrs, to: textView)

            if let selectedTextRange = textView.selectedTextRange {
                textView.replace(selectedTextRange, withText: timeText)
            } else {
                textView.insertText(timeText)
            }
            textView.undoManager?.setActionName("Insert Time")

            applyAttributesWithoutUndo(previousTypingAttributes, to: textView)
            applyTypingAttributes(to: textView)
            pushTextToParent(textView.attributedText ?? NSAttributedString())
        }

        private func applyAttributesWithoutUndo(_ attributes: [NSAttributedString.Key: Any], to textView: UITextView) {
            guard let undoManager = textView.undoManager else {
                textView.typingAttributes = attributes
                return
            }

            let wasEnabled = undoManager.isUndoRegistrationEnabled
            if wasEnabled {
                undoManager.disableUndoRegistration()
            }
            textView.typingAttributes = attributes
            if wasEnabled {
                undoManager.enableUndoRegistration()
            }
        }

        func insertURL(using request: URLInsertionRequest) {
            guard let textView = textView else { return }

            isProgrammaticUpdate = true

            let mutableText = (textView.attributedText?.mutableCopy() as? NSMutableAttributedString) ?? NSMutableAttributedString()

            guard let linkURL = URL(string: request.urlString) else {
                isProgrammaticUpdate = false
                return
            }

            let baseRange = request.replacementRange?.nsRange ?? textView.selectedRange
            let insertionRange = validateCursorPosition(baseRange, for: textView)
            let shouldAppendTrailingSpace = request.replacementRange == nil

            // Create link attributes with blue color and underline
            let linkAttrs: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key.font: UIFont.systemFont(ofSize: activeFontSize.rawValue),
                NSAttributedString.Key.foregroundColor: UIColor.systemBlue,
                NSAttributedString.Key.underlineStyle: NSUnderlineStyle.single.rawValue,
                NSAttributedString.Key.link: linkURL,
                ColorMapping.colorIDKey: "blue",
                ColorMapping.fontSizeKey: activeFontSize.rawValue
            ]
            let linkString = NSAttributedString(string: request.displayText, attributes: linkAttrs)

            // Replace the selected text (or insert at cursor)
            mutableText.replaceCharacters(in: insertionRange, with: linkString)

            var newCursorPosition = insertionRange.location + request.displayText.count

            if shouldAppendTrailingSpace {
                let spaceInsertionPos = newCursorPosition
                if spaceInsertionPos < mutableText.length {
                    let nextCharRange = NSRange(location: spaceInsertionPos, length: 1)
                    let nextChar = mutableText.attributedSubstring(from: nextCharRange).string
                    if nextChar != " " {
                        let spaceAttrs = currentTypingAttributes(from: textView)
                        mutableText.insert(NSAttributedString(string: " ", attributes: spaceAttrs), at: spaceInsertionPos)
                        newCursorPosition += 1
                    } else {
                        newCursorPosition = spaceInsertionPos + 1
                    }
                } else {
                    // End of text, just add space
                    let spaceAttrs = currentTypingAttributes(from: textView)
                    mutableText.insert(NSAttributedString(string: " ", attributes: spaceAttrs), at: spaceInsertionPos)
                    newCursorPosition = spaceInsertionPos + 1
                }
            }

            textView.attributedText = mutableText
            setCursorPosition(NSRange(location: newCursorPosition, length: 0), in: textView)
            applyTypingAttributes(to: textView)

            // Update binding synchronously while isProgrammaticUpdate is true to prevent race conditions
            let updatedText = NSAttributedString(attributedString: mutableText)
            pushTextToParent(updatedText)
            isProgrammaticUpdate = false
        }

        private func linkContext(for ranges: [NSRange], in textView: UITextView) -> LinkEditContext? {
            guard let attributed = textView.attributedText, attributed.length > 0 else {
                return nil
            }

            var probeLocations: [Int] = []
            if ranges.isEmpty {
                let selection = validateCursorPosition(textView.selectedRange, for: textView)
                if selection.length > 0 {
                    probeLocations.append(selection.location)
                    let end = max(selection.location + selection.length - 1, 0)
                    probeLocations.append(end)
                } else {
                    probeLocations.append(selection.location)
                    probeLocations.append(max(selection.location - 1, 0))
                }
            } else {
                for range in ranges {
                    if range.length > 0 {
                        probeLocations.append(range.location)
                        let end = max(range.location + range.length - 1, 0)
                        probeLocations.append(end)
                    } else {
                        probeLocations.append(range.location)
                        probeLocations.append(max(range.location - 1, 0))
                    }
                }
            }

            for location in probeLocations {
                guard attributed.length > 0,
                      location >= 0,
                      location < attributed.length else { continue }

                var effectiveRange = NSRange(location: 0, length: 0)
                if let url = attributed.attribute(NSAttributedString.Key.link, at: location, effectiveRange: &effectiveRange) as? URL,
                   effectiveRange.length > 0 {
                    let displayText = attributed.attributedSubstring(from: effectiveRange).string
                    let snapshot = LinkEditContext(
                        id: UUID(),
                        range: LinkRangeSnapshot(location: effectiveRange.location, length: effectiveRange.length),
                        urlString: url.absoluteString,
                        displayText: displayText
                    )
                    return snapshot
                }
            }

            return nil
        }

    }
}

#endif
