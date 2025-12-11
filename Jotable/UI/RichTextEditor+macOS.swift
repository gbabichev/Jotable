#if os(macOS)
import SwiftUI
import AppKit

private final class DynamicColorTextView: NSTextView {
    var onAppearanceChange: (() -> Void)?
    var onCheckboxTap: ((Int) -> Void)?
    var onColorChange: (() -> Void)?
    var onFormatChange: (() -> Void)?
    var onImageResize: ((ResizableImageAttachment) -> Void)?
    var isUnderlinedManually = false  // Track underline state for native menu toggles (which don't update typingAttributes)

    // Image resize tracking
    private var selectedImageAttachment: ResizableImageAttachment?
    private var selectedImageCharIndex: Int?
    private var isResizingImage = false
    private var resizeStartPoint: NSPoint = .zero
    private var resizeStartSize: NSSize = .zero

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

        // Check for checkbox tap
        if event.clickCount == 1,
           let charIndex = checkboxCharacterIndex(at: localPoint) {
            onCheckboxTap?(charIndex)
            return
        }

        // Check for image attachment click/resize
        if let (attachment, charIndex, attachmentRect) = imageAttachmentInfo(at: localPoint) {
            selectedImageAttachment = attachment
            selectedImageCharIndex = charIndex

            // Check if click is on resize handle (bottom-right corner)
            let handleSize: CGFloat = 16
            let handleRect = NSRect(x: attachmentRect.maxX - handleSize,
                                   y: attachmentRect.maxY - handleSize,
                                   width: handleSize,
                                   height: handleSize)

            if handleRect.contains(localPoint) {
                isResizingImage = true
                resizeStartPoint = event.locationInWindow
                resizeStartSize = attachmentRect.size
                return
            }

            // Just selecting the image
            needsDisplay = true
            return
        }

        // Clear image selection if clicking elsewhere
        if selectedImageAttachment != nil {
            selectedImageAttachment = nil
            selectedImageCharIndex = nil
            needsDisplay = true
        }

        super.mouseDown(with: event)
    }

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general

        // Check if pasteboard contains an image
        if let image = NSImage(pasteboard: pasteboard) {
            // Create a resizable image attachment
            let attachment = ResizableImageAttachment(image: image)

            // Scale image to reasonable size if needed
            let maxWidth: CGFloat = 400
            let maxHeight: CGFloat = 400
            let imageSize = image.size

            var width = imageSize.width
            var height = imageSize.height

            if width > maxWidth || height > maxHeight {
                let widthRatio = maxWidth / width
                let heightRatio = maxHeight / height
                let ratio = min(widthRatio, heightRatio)

                width = width * ratio
                height = height * ratio
            }

            attachment.customSize = NSSize(width: width, height: height)

            // Create attributed string with the attachment
            let attachmentString = NSAttributedString(attachment: attachment)

            // Insert at current selection
            if let textStorage = textStorage {
                let selectedRange = self.selectedRange
                textStorage.replaceCharacters(in: selectedRange, with: attachmentString)

                // Move cursor after the inserted image
                let newPosition = selectedRange.location + 1
                setSelectedRange(NSRange(location: newPosition, length: 0))

                didChangeText()
            }
        } else {
            // Not an image, use default paste behavior
            super.paste(sender)
        }
    }

    override func changeColor(_ sender: Any?) {
        super.changeColor(sender)
        onColorChange?()
    }

    override func changeFont(_ sender: Any?) {
        let fontManager = NSFontManager.shared
        super.changeFont(sender)

        // Manually update typing attributes to match font manager
        // This is necessary because super.changeFont() doesn't always update typingAttributes properly
        if let selectedFont = fontManager.selectedFont {
            typingAttributes[NSAttributedString.Key.font] = selectedFont
        }

        // The native font panel has updated, so we need to sync
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.onFormatChange?()
        }
    }

    override func underline(_ sender: Any?) {
        // Call super to handle selected text if any
        super.underline(sender)

        // The native underline() only works with selected text
        // For cursor position (no selection), we need to toggle our manual tracking
        if selectedRange.length == 0 {
            // Toggle the manually tracked state
            isUnderlinedManually = !isUnderlinedManually
        }

        // Notify the coordinator to sync state
        onFormatChange?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isResizingImage,
              let attachment = selectedImageAttachment,
              let charIndex = selectedImageCharIndex,
              let layoutManager = layoutManager,
              let textContainer = textContainer,
              textStorage != nil else {
            super.mouseDragged(with: event)
            return
        }

        let currentPoint = event.locationInWindow
        let delta = NSPoint(x: currentPoint.x - resizeStartPoint.x,
                           y: currentPoint.y - resizeStartPoint.y)

        // Calculate new size
        let newWidth = max(50, resizeStartSize.width + delta.x)

        // Maintain aspect ratio
        guard let img = attachment.originalImage ?? attachment.image else {
            super.mouseDragged(with: event)
            return
        }
        let aspectRatio = img.size.height / img.size.width
        let newHeight = newWidth * aspectRatio

        // Update attachment size
        attachment.customSize = NSSize(width: newWidth, height: newHeight)

        // Force layout refresh
        layoutManager.invalidateLayout(forCharacterRange: NSRange(location: charIndex, length: 1),
                                       actualCharacterRange: nil)
        layoutManager.ensureLayout(for: textContainer)

        needsDisplay = true
        didChangeText()
    }

    override func mouseUp(with event: NSEvent) {
        if isResizingImage {
            isResizingImage = false

            // Add a marker attribute to force change detection
            // since NSAttributedString.isEqual won't detect image size changes
            if let storage = textStorage, storage.length > 0 {
                let updatedStorage = NSMutableAttributedString(attributedString: storage)
                updatedStorage.addAttribute(
                    NSAttributedString.Key(rawValue: "imageResizeChanged"),
                    value: NSNumber(value: Date().timeIntervalSince1970),
                    range: NSRange(location: 0, length: 1)
                )

                // Replace the text storage content
                storage.setAttributedString(updatedStorage)

                if let attachment = selectedImageAttachment {
                    onImageResize?(attachment)
                }

                didChangeText()
            }
        }
        super.mouseUp(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Draw resize handles on selected image
        guard selectedImageAttachment != nil,
              let charIndex = selectedImageCharIndex,
              let layoutManager = layoutManager,
              let textContainer = textContainer else {
            return
        }

        let glyphIndex = layoutManager.glyphIndexForCharacter(at: charIndex)
        let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1),
                                                    in: textContainer)
        let textContainerOrigin = self.textContainerOrigin
        let attachmentRect = glyphRect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)

        // Draw selection border
        NSColor.controlAccentColor.setStroke()
        let borderPath = NSBezierPath(rect: attachmentRect)
        borderPath.lineWidth = 2
        borderPath.stroke()

        // Draw resize handle with SF Symbol
        let handleSize: CGFloat = 16
        let handleRect = NSRect(x: attachmentRect.maxX - handleSize,
                               y: attachmentRect.maxY - handleSize,
                               width: handleSize,
                               height: handleSize)

        // Draw background circle
        NSColor.controlAccentColor.withAlphaComponent(0.9).setFill()
        let circlePath = NSBezierPath(ovalIn: handleRect)
        circlePath.fill()

        // Draw resize symbol
        if let symbolImage = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: "Resize") {
            symbolImage.isTemplate = true

            NSGraphicsContext.saveGraphicsState()
            NSColor.white.set()

            // Draw the symbol centered in the handle
            let symbolRect = handleRect.insetBy(dx: 3, dy: 3)
            symbolImage.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1.0)

            NSGraphicsContext.restoreGraphicsState()
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()

        // Add cursor rect for resize handle if image is selected
        guard selectedImageAttachment != nil,
              let charIndex = selectedImageCharIndex,
              let layoutManager = layoutManager,
              let textContainer = textContainer else {
            return
        }

        let glyphIndex = layoutManager.glyphIndexForCharacter(at: charIndex)
        let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1),
                                                    in: textContainer)
        let textContainerOrigin = self.textContainerOrigin
        let attachmentRect = glyphRect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)

        let handleSize: CGFloat = 16
        let handleRect = NSRect(x: attachmentRect.maxX - handleSize,
                               y: attachmentRect.maxY - handleSize,
                               width: handleSize,
                               height: handleSize)

        addCursorRect(handleRect, cursor: .crosshair)
    }

    private func imageAttachmentInfo(at point: NSPoint) -> (attachment: ResizableImageAttachment, charIndex: Int, rect: NSRect)? {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer,
              let storage = textStorage else { return nil }

        let textContainerOrigin = self.textContainerOrigin
        let containerPoint = NSPoint(x: point.x - textContainerOrigin.x,
                                     y: point.y - textContainerOrigin.y)

        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1),
                                                    in: textContainer)
        let adjustedRect = glyphRect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)

        guard adjustedRect.contains(point) else { return nil }

        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard charIndex != NSNotFound, charIndex < storage.length else { return nil }

        if let attachment = storage.attribute(NSAttributedString.Key.attachment,
                                             at: charIndex,
                                             effectiveRange: nil) as? ResizableImageAttachment {
            return (attachment, charIndex, adjustedRect)
        }

        return nil
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
    @Binding var plainTextInsertionRequest: PlainTextInsertionRequest?
    @Binding var presentFormatMenuTrigger: UUID?
    @Binding var resetColorTrigger: UUID?
    @Binding var pastePlaintextTrigger: UUID?

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
        textView.importsGraphics = true
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

        // Initialize manual formatting state tracking for underline
        // (strikethrough is only toggled via toolbar, so it's always read from typingAttributes)
        let underlineValue = textView.typingAttributes[NSAttributedString.Key.underlineStyle] as? Int ?? 0
        textView.isUnderlinedManually = underlineValue != 0
        textView.onAppearanceChange = { [weak coordinator = context.coordinator] in
            coordinator?.handleAppearanceChange()
        }
        textView.onCheckboxTap = { [weak coordinator = context.coordinator] charIndex in
            coordinator?.handleCheckboxTap(at: charIndex)
        }
        textView.onColorChange = { [weak coordinator = context.coordinator] in
            coordinator?.handleColorPanelChange()
        }
        textView.onFormatChange = { [weak coordinator = context.coordinator] in
            coordinator?.handleFormatChange()
        }

        // Mark initialization as complete after the textView is fully set up
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            context.coordinator.isInitializing = false
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

        // Skip format state updates if we're currently syncing formatting from the native menu
        // This prevents a feedback loop where syncFormattingState updates the binding,
        // which triggers updateNSView, which tries to update the text again
        if !context.coordinator.isSyncingFormattingState {
            if context.coordinator.isBold != isBold {
                context.coordinator.isBold = isBold
                context.coordinator.toggleBold(textView)
            }

            if context.coordinator.isItalic != isItalic {
                context.coordinator.isItalic = isItalic
                context.coordinator.toggleItalic(textView)
            }

            if context.coordinator.isUnderlined != isUnderlined {
                context.coordinator.isUnderlined = isUnderlined
                context.coordinator.toggleUnderline(textView)
            }
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

        // Handle time insertion trigger
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

        // Handle plain text insertion trigger (e.g., password generator)
        if plainTextInsertionRequest?.id != context.coordinator.lastPlainTextInsertionRequest?.id {
            context.coordinator.lastPlainTextInsertionRequest = plainTextInsertionRequest
            if let request = plainTextInsertionRequest {
                context.coordinator.insertPlainText(request.text)
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

        // Handle plaintext paste trigger
        // Only trigger when the new value is non-nil (user clicked the button)
        // Ignore transitions to nil (which happen when we reset the trigger)
        if pastePlaintextTrigger != context.coordinator.lastPlaintextPasteTrigger {
            context.coordinator.lastPlaintextPasteTrigger = pastePlaintextTrigger
            if pastePlaintextTrigger != nil {
                context.coordinator.pastePlaintext()
            }
        }

        // Note: Don't sync color state here during updateNSView - it gets called constantly
        // during the view render cycle and causes feedback loops. Only sync in textDidChange
        // and textViewDidChangeSelection which are user-triggered events.
        // Similarly, don't call handleAppearanceChange() here - it's already triggered by
        // viewDidChangeEffectiveAppearance() callback when appearance actually changes.

        context.coordinator.skipNextColorSampling = false  // Reset the flag after syncing
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        var activeColor: RichTextColor
        var activeHighlighter: HighlighterColor
        var activeFontSize: FontSize
        var isBold: Bool
        var isItalic: Bool
        var isUnderlined: Bool
        var isStrikethrough: Bool
        var isProgrammaticUpdate = false
        var isInitializing = true
        var lastUncheckedCheckboxTrigger: UUID?
        var lastDashTrigger: UUID?
        var lastBulletTrigger: UUID?
        var lastNumberingTrigger: UUID?
        var lastDateRequest: DateInsertionRequest?
        var lastTimeRequest: TimeInsertionRequest?
        var lastURLTrigger: URLInsertionRequest?
        var lastFormatMenuTrigger: UUID?
        var lastResetColorTrigger: UUID?
        var lastPlaintextPasteTrigger: UUID?
        var lastPlainTextInsertionRequest: PlainTextInsertionRequest?
        weak var textView: NSTextView?
        var pendingActiveColorFeedback: RichTextColor?
        var customTypingColor: NSColor?
        var hasCustomTypingColor: Bool { customTypingColor != nil }
        var skipNextColorSampling = false
        var isSyncingFormattingState = false  // Prevent applyTypingAttributes during format sync

        private func effectiveColorComponents() -> (color: NSColor, id: String?) {
            if let customTypingColor {
                let identifier = ColorMapping.identifier(for: customTypingColor, preferPaletteMatch: false)
                return (customTypingColor, identifier)
            }
            return (activeColor.nsColor, activeColor.id)
        }

        private func registerUndoSnapshot(for textView: NSTextView,
                                          actionName: String,
                                          textSnapshot: NSAttributedString? = nil,
                                          selectionSnapshot: NSRange? = nil) {
            guard let undoManager = textView.undoManager else { return }

            let snapshot = NSAttributedString(attributedString: textSnapshot ?? textView.attributedString())
            let selection = selectionSnapshot ?? textView.selectedRange
            weak var weakTextView = textView

            undoManager.registerUndo(withTarget: self) { [weak self] _ in
                guard let self = self,
                      let targetTextView = weakTextView,
                      targetTextView.window != nil else { return }
                let currentText = targetTextView.attributedString()
                let currentSelection = targetTextView.selectedRange
                self.registerUndoSnapshot(for: targetTextView,
                                          actionName: actionName,
                                          textSnapshot: currentText,
                                          selectionSnapshot: currentSelection)

                self.isProgrammaticUpdate = true
                targetTextView.textStorage?.setAttributedString(snapshot)
                targetTextView.setSelectedRange(selection)
                self.applyTypingAttributes(to: targetTextView)
                self.updateTypingAttributesHighlight(targetTextView)
                self.parent.text = snapshot
                self.isProgrammaticUpdate = false
            }

            undoManager.setActionName(actionName)
        }

        func syncFormattingState(with textView: NSTextView) {
            isSyncingFormattingState = true
            defer { isSyncingFormattingState = false }

            let selectedRange = textView.selectedRange

            var font: NSFont? = nil

            // First try to get font from selected text
            if selectedRange.length > 0,
               let storage = textView.textStorage,
               selectedRange.location < storage.length {
                let attrs = storage.attributes(at: selectedRange.location, effectiveRange: nil)
                font = attrs[NSAttributedString.Key.font] as? NSFont
            } else {
                // If no selection, try font manager first (which has the most up-to-date state)
                // Then fall back to typing attributes
                let fontManager = NSFontManager.shared
                if let managerFont = fontManager.selectedFont {
                    font = managerFont
                } else {
                    let attrs = textView.typingAttributes
                    font = attrs[NSAttributedString.Key.font] as? NSFont
                }
            }

            guard let font = font else {
                return
            }
            let sampledBold = font.fontDescriptor.symbolicTraits.contains(.bold)
            let sampledItalic = font.fontDescriptor.symbolicTraits.contains(.italic)

            // For underline: use manual tracking when no selection (native menu doesn't update typingAttributes)
            // For strikethrough: always read from text since it's only toggled via toolbar
            var sampledUnderline = false
            var sampledStrikethrough = false

            if selectedRange.length > 0,
               let storage = textView.textStorage,
               selectedRange.location < storage.length {
                // Read from selected text
                let attrs = storage.attributes(at: selectedRange.location, effectiveRange: nil)
                let underlineValue = attrs[NSAttributedString.Key.underlineStyle] as? Int ?? 0
                sampledUnderline = underlineValue != 0
                let strikethroughValue = attrs[NSAttributedString.Key.strikethroughStyle] as? Int ?? 0
                sampledStrikethrough = strikethroughValue != 0
            } else {
                // No selection - use manual tracking for underline (native menu toggle), but read strikethrough from typing attributes
                if let dynamicTextView = textView as? DynamicColorTextView {
                    sampledUnderline = dynamicTextView.isUnderlinedManually
                } else {
                    let underlineValue = textView.typingAttributes[NSAttributedString.Key.underlineStyle] as? Int ?? 0
                    sampledUnderline = underlineValue != 0
                }

                // For strikethrough, read from typing attributes
                let strikethroughValue = textView.typingAttributes[NSAttributedString.Key.strikethroughStyle] as? Int ?? 0
                sampledStrikethrough = strikethroughValue != 0
            }

            // ALWAYS update state to match what we sampled, regardless of previous state
            // This ensures consistency after native menu changes
            if sampledBold != isBold {
                isBold = sampledBold
                parent.isBold = sampledBold
            } else if sampledBold != parent.isBold {
                // Ensure parent binding is in sync even if coordinator state matches
                parent.isBold = sampledBold
            }

            if sampledItalic != isItalic {
                isItalic = sampledItalic
                parent.isItalic = sampledItalic
            } else if sampledItalic != parent.isItalic {
                parent.isItalic = sampledItalic
            }

            if sampledUnderline != isUnderlined {
                isUnderlined = sampledUnderline
                parent.isUnderlined = sampledUnderline
            } else if sampledUnderline != parent.isUnderlined {
                parent.isUnderlined = sampledUnderline
            }

            if sampledStrikethrough != isStrikethrough {
                isStrikethrough = sampledStrikethrough
                parent.isStrikethrough = sampledStrikethrough
            } else if sampledStrikethrough != parent.isStrikethrough {
                parent.isStrikethrough = sampledStrikethrough
            }
        }

        func syncColorState(with textView: NSTextView, sampleFromText: Bool) {
            var colorID = textView.typingAttributes[ColorMapping.colorIDKey] as? String
            var color = textView.typingAttributes[NSAttributedString.Key.foregroundColor] as? NSColor
            var sampledBold: Bool?
            var sampledUnderline: Bool?
            var sampledStrikethrough: Bool?

            let shouldSample = sampleFromText && !skipNextColorSampling

            if shouldSample,
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

                    // Only sample bold, underline, and strikethrough if there's a selection
                    // When no text is selected, we should use typing attributes, not sample from cursor position
                    if textView.selectedRange.length > 0 {
                        let font = attrs[NSAttributedString.Key.font] as? NSFont
                        sampledBold = font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false

                        let underlineValue = attrs[NSAttributedString.Key.underlineStyle] as? Int ?? 0
                        sampledUnderline = underlineValue != 0

                        let strikethroughValue = attrs[NSAttributedString.Key.strikethroughStyle] as? Int ?? 0
                        sampledStrikethrough = strikethroughValue != 0
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

            // Update bold, underline, and strikethrough state if sampled
            if let sampledBold, sampledBold != isBold {
                isBold = sampledBold
                parent.isBold = sampledBold
            }

            if let sampledUnderline, sampledUnderline != isUnderlined {
                isUnderlined = sampledUnderline
                parent.isUnderlined = sampledUnderline
            }

            if let sampledStrikethrough, sampledStrikethrough != isStrikethrough {
                isStrikethrough = sampledStrikethrough
                parent.isStrikethrough = sampledStrikethrough
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

        func textDidChange(_ notification: Notification) {
            guard !isProgrammaticUpdate,
                  let textView = notification.object as? NSTextView,
                  textView === self.textView else {
                return
            }

            // Skip textDidChange during initialization to prevent feedback loops
            guard !isInitializing else {
                return
            }

            syncColorState(with: textView, sampleFromText: true)
            syncFormattingState(with: textView)

            // Convert checkbox patterns to attachments
            if let storage = textView.textStorage {
                let spaceAttrs = currentTypingAttributes(from: textView)
                _ = AutoFormatting.convertCheckboxPatterns(in: storage, spaceAttributes: spaceAttrs)
            }

            let updatedText = textView.attributedString()
            parent.text = updatedText
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  textView === self.textView else { return }

            // Skip selection updates during initialization to prevent feedback loops
            guard !isInitializing else { return }

            syncColorState(with: textView, sampleFromText: true)
            syncFormattingState(with: textView)
            applyTypingAttributes(to: textView)
            syncColorState(with: textView, sampleFromText: false)

            // Only update parent.text if the content has actually changed
            // Selection changes alone should not trigger a binding update
            if !isProgrammaticUpdate {
                let currentText = textView.attributedString()
                if !currentText.isEqual(to: parent.text) {
                    parent.text = currentText
                }
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

        func handleFormatChange() {
            guard let textView = textView else { return }

            // Sync the formatting state after native menu changes
            syncFormattingState(with: textView)

            // Apply the updated formatting to typing attributes so next character uses the new format
            applyTypingAttributes(to: textView)

            // Update text binding to persist the changes
            if !isProgrammaticUpdate {
                let currentText = textView.attributedString()
                parent.text = currentText
            }
        }

        private func updateTypingAttributesHighlight(_ textView: NSTextView, using highlight: HighlighterColor? = nil) {
            applyTypingAttributes(to: textView, highlightOverride: highlight)
        }

        private func currentTypingAttributes(from textView: NSTextView?, highlightOverride: HighlighterColor? = nil) -> [NSAttributedString.Key: Any] {
            let components = effectiveColorComponents()
            let usingAutomatic = customTypingColor == nil && activeColor == .automatic
            let targetHighlight = highlightOverride ?? activeHighlighter

            let styler = TextStyler(
                isBold: isBold,
                isItalic: isItalic,
                fontSize: activeFontSize,
                colorID: components.id,
                color: components.color,
                highlightID: targetHighlight == .none ? nil : targetHighlight.id,
                highlight: targetHighlight.nsColor,
                isUnderlined: isUnderlined,
                isStrikethrough: isStrikethrough
            )

            return styler.buildAttributes(usingAutomatic: usingAutomatic, customColor: customTypingColor)
        }

        func applyTypingAttributes(to textView: NSTextView, highlightOverride: HighlighterColor? = nil) {
            textView.typingAttributes = currentTypingAttributes(from: textView, highlightOverride: highlightOverride)
        }

        func toggleBold(_ textView: NSTextView) {
            let selectedRange = textView.selectedRange
            if selectedRange.length > 0,
               let storage = textView.textStorage {
                isProgrammaticUpdate = true

                let styler = TextStyler(isBold: isBold, isItalic: isItalic, fontSize: activeFontSize)
                let font = styler.buildFont()

                storage.addAttribute(NSAttributedString.Key.font, value: font, range: selectedRange)
                textView.setSelectedRange(selectedRange)

                DispatchQueue.main.async { [weak self] in
                    self?.isProgrammaticUpdate = false
                    self?.parent.text = NSAttributedString(attributedString: storage)
                }
            }

            applyTypingAttributes(to: textView)
        }

        func toggleItalic(_ textView: NSTextView) {
            let selectedRange = textView.selectedRange
            if selectedRange.length > 0,
               let storage = textView.textStorage {
                isProgrammaticUpdate = true

                let styler = TextStyler(isBold: isBold, isItalic: isItalic, fontSize: activeFontSize)
                let font = styler.buildFont()

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

            // Update manual tracking to match coordinator state
            if let dynamicTextView = textView as? DynamicColorTextView {
                dynamicTextView.isUnderlinedManually = isUnderlined
            }
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

            // Clear custom color state FIRST
            customTypingColor = nil
            pendingActiveColorFeedback = nil
            activeColor = .automatic
            skipNextColorSampling = true  // Prevent syncColorState from re-sampling the color

            // Apply automatic color to selected text AND update storage
            let selectedRange = textView.selectedRange
            if selectedRange.length > 0, let storage = textView.textStorage {
                isProgrammaticUpdate = true
                ColorMapping.applyColor(.automatic, to: storage, range: selectedRange)

                // Ensure the storage actually reflects automatic color (remove foreground color)
                // so that syncColorState won't sample a custom color back
                storage.removeAttribute(NSAttributedString.Key.foregroundColor, range: selectedRange)
                storage.addAttribute(ColorMapping.colorIDKey, value: RichTextColor.automatic.id, range: selectedRange)

                textView.setSelectedRange(selectedRange)

                // Defer the parent text update to avoid triggering updateNSView during reset
                DispatchQueue.main.async { [weak self] in
                    self?.isProgrammaticUpdate = false
                    self?.parent.text = NSAttributedString(attributedString: storage)
                }
            }

            // IMPORTANT: Build fresh typing attributes with automatic color
            // Since customTypingColor is now nil and activeColor is .automatic,
            // currentTypingAttributes will return the proper automatic color
            applyTypingAttributes(to: textView)

            // Refresh all existing automatic colors with theme-aware color
            if let storage = textView.textStorage {
                var currentPos = 0
                while currentPos < storage.length {
                    var range = NSRange()
                    let attrs = storage.attributes(at: currentPos, longestEffectiveRange: &range, in: NSRange(location: currentPos, length: storage.length - currentPos))

                    if let colorID = attrs[ColorMapping.colorIDKey] as? String, colorID == "automatic" {
                        storage.addAttribute(NSAttributedString.Key.foregroundColor, value: NSColor.labelColor, range: range)
                    }

                    currentPos = range.location + range.length
                }
            }
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

            // Update the attachment's internal data representation to ensure proper serialization
            // This is critical for checkbox state persistence when archiving
            let stateDict: [String: Any] = ["checkboxID": attachment.checkboxID, "isChecked": attachment.isChecked]
            if let stateData = try? JSONSerialization.data(withJSONObject: stateDict) {
                attachment.contents = stateData
            }

            textView.layoutManager?.invalidateDisplay(forCharacterRange: effectiveRange)

            // Add a marker attribute to force change detection
            // since NSAttributedString.isEqual won't detect checkbox state changes
            let updatedStorage = NSMutableAttributedString(attributedString: storage)
            updatedStorage.addAttribute(NSAttributedString.Key(rawValue: "checkboxStateChanged"), value: NSNumber(value: Date().timeIntervalSince1970), range: NSRange(location: 0, length: 1))

            let updatedText = NSAttributedString(attributedString: updatedStorage)

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

            // If the cursor is at the very start of a line that already has a list marker, let the default newline occur
            let isAtLineStart = range.location == lineInfo.range.location
            if isAtLineStart,
               lineInfo.text.range(of: #"^\s*(?:-\s|•\s)"#, options: .regularExpression) != nil {
                return false
            }

            // If the cursor is at the start of a numbered line, skip auto-numbering
            if isAtLineStart,
               lineInfo.text.range(of: #"^\s*\d+\.\s"#, options: .regularExpression) != nil {
                return false
            }

            // If the cursor is at the start of a line that already has a checkbox attachment, let the default newline occur
            if isAtLineStart,
               lineInfo.range.location < attributedString.length,
               attributedString.attribute(.attachment,
                                          at: lineInfo.range.location,
                                          longestEffectiveRange: nil,
                                          in: lineInfo.range) is CheckboxTextAttachment {
                return false
            }

            // Check for checkbox pattern (attachments at start of line)
            if handleCheckboxLine(in: attributedString, textView: textView, at: range, lineRange: lineInfo.range) {
                return true
            }

            // Check for numbered list pattern with renumbering
            if let result = AutoFormatting.handleNumberedListWithRenumbering(lineText: lineInfo.text, fullText: plainText, insertionIndex: range.location) {
                guard let storage = textView.textStorage else {
                    return false
                }

                registerUndoSnapshot(for: textView, actionName: "Insert Number")
                isProgrammaticUpdate = true

                // If newText is just "\n", replace the entire line (removes formatting)
                let replacementRange = result.newText == "\n" ? lineInfo.range : range
                storage.replaceCharacters(in: replacementRange, with: result.newText)

                // Then renumber subsequent lines if needed
                if !result.renumberPositions.isEmpty {
                    // Adjust positions based on how much text was inserted
                    let textInserted = result.newText.count
                    for (range, newNumber) in result.renumberPositions.reversed() {
                        let adjustedRange = NSRange(location: range.location + textInserted, length: range.length)
                        let newNumberText = "\(newNumber). "
                        let fontAttrs = currentTypingAttributes(from: textView)
                        let newNumberString = NSAttributedString(string: newNumberText, attributes: fontAttrs)
                        storage.replaceCharacters(in: adjustedRange, with: newNumberString)
                    }
                }

                // Position cursor after the inserted text
                let newCursorPosition = replacementRange.location + result.newText.count
                textView.setSelectedRange(NSRange(location: newCursorPosition, length: 0))
                applyTypingAttributes(to: textView)

                parent.text = NSAttributedString(attributedString: storage)
                isProgrammaticUpdate = false

                return true
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
            let contentAfter = attributedString.attributedSubstring(from: remainingRange).string.trimmingCharacters(in: .whitespacesAndNewlines)

            guard let storage = textView.textStorage else { return false }

            registerUndoSnapshot(for: textView, actionName: "Insert Checkbox")
            isProgrammaticUpdate = true

            var newCursorPosition = cursorRange.location

            if contentAfter.isEmpty {
                // Blank line after checkbox - remove the checkbox, just add newline with proper attributes
                let fontAttrs = currentTypingAttributes(from: textView)
                let newlineWithAttrs = NSAttributedString(string: "\n", attributes: fontAttrs)
                storage.replaceCharacters(in: lineRange, with: newlineWithAttrs)

                newCursorPosition = min(lineRange.location, storage.length)
            } else {
                // Content after checkbox - add newline and new checkbox
                let newCheckbox = CheckboxTextAttachment(checkboxID: UUID().uuidString, isChecked: false, fontPointSize: activeFontSize.rawValue)
                let newCheckboxString = NSAttributedString(attachment: newCheckbox)

                // Add font attributes for proper rendering
                let fontAttrs = currentTypingAttributes(from: textView)

                let newLine = NSMutableAttributedString(string: "\n", attributes: fontAttrs)
                newLine.append(newCheckboxString)

                // Add space after checkbox with minimal attributes (just font) to avoid rendering issues
                let baseFont = NSFont.systemFont(ofSize: activeFontSize.rawValue)
                let spaceAttrs: [NSAttributedString.Key: Any] = [.font: baseFont]
                newLine.append(NSAttributedString(string: " ", attributes: spaceAttrs))
                storage.replaceCharacters(in: cursorRange, with: newLine)

                newCursorPosition = min(cursorRange.location + newLine.length, storage.length)
            }

            // Position cursor after the inserted content
            textView.setSelectedRange(NSRange(location: newCursorPosition, length: 0))

            // Ensure typing attributes are set for the next line
            applyTypingAttributes(to: textView)

            parent.text = NSAttributedString(attributedString: storage)
            isProgrammaticUpdate = false

            return true
        }

        private func applyAutoFormat(_ newText: String, to textView: NSTextView, at range: NSRange, lineRange: NSRange) -> Bool {
            registerUndoSnapshot(for: textView, actionName: "Auto Format")
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

        private func renumberLinesInTextView(_ textView: NSTextView, positions: [(range: NSRange, newNumber: Int)]) {
            guard let storage = textView.textStorage else {
                return
            }

            isProgrammaticUpdate = true

            // Process renumbering in reverse order to avoid position shifting
            for (range, newNumber) in positions.reversed() {
                let newNumberText = "\(newNumber). "
                let fontAttrs = currentTypingAttributes(from: textView)
                let newNumberString = NSAttributedString(string: newNumberText, attributes: fontAttrs)
                storage.replaceCharacters(in: range, with: newNumberString)
            }

            parent.text = NSAttributedString(attributedString: storage)
            isProgrammaticUpdate = false
        }

        private func lineInfo(for insertionRange: NSRange, in textView: NSTextView) -> (lineStart: Int, lineRange: NSRange, lineContent: String)? {
            guard let storage = textView.textStorage else {
                return nil
            }

            let fullText = storage.string as NSString
            let boundedLocation = min(insertionRange.location, fullText.length)

            var lineStart = boundedLocation
            while lineStart > 0 &&
                    fullText.character(at: lineStart - 1) != 10 {
                lineStart -= 1
            }

            var lineEnd = lineStart
            while lineEnd < fullText.length &&
                    fullText.character(at: lineEnd) != 10 {
                lineEnd += 1
            }

            let lineRange = NSRange(location: lineStart, length: lineEnd - lineStart)
            guard lineRange.location + lineRange.length <= storage.length else { return nil }

            let lineContent = storage.attributedSubstring(from: lineRange).string
            return (lineStart, lineRange, lineContent)
        }

        private func existingListFormattingLength(at lineStart: Int, lineRange: NSRange, lineContent: String, in storage: NSTextStorage) -> Int {
            var existingFormattingLength = 0

            let whitespaceCount = leadingWhitespaceLength(in: lineContent)
            let attachmentPosition = lineStart + whitespaceCount

            if attachmentPosition < storage.length,
               storage.attribute(.attachment, at: attachmentPosition, longestEffectiveRange: nil, in: lineRange) is CheckboxTextAttachment {
                existingFormattingLength = whitespaceCount + 2 // leading spaces + checkbox + trailing space
            }

            if existingFormattingLength == 0 {
                let contentAfterWhitespace = String(lineContent.dropFirst(whitespaceCount))

                if let dashMatch = contentAfterWhitespace.range(of: #"^-\s"#, options: .regularExpression) {
                    existingFormattingLength = whitespaceCount + contentAfterWhitespace.distance(from: contentAfterWhitespace.startIndex, to: dashMatch.upperBound)
                } else if let bulletMatch = contentAfterWhitespace.range(of: #"^•\s"#, options: .regularExpression) {
                    existingFormattingLength = whitespaceCount + contentAfterWhitespace.distance(from: contentAfterWhitespace.startIndex, to: bulletMatch.upperBound)
                } else if let numberMatch = contentAfterWhitespace.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                    existingFormattingLength = whitespaceCount + contentAfterWhitespace.distance(from: contentAfterWhitespace.startIndex, to: numberMatch.upperBound)
                }
            }

            return existingFormattingLength
        }

        private func leadingWhitespaceLength(in lineContent: String) -> Int {
            var count = 0
            for char in lineContent {
                if char == " " || char == "\t" {
                    count += 1
                } else {
                    break
                }
            }
            return count
        }

        private func skipListInsertionIfFormattingExists(at insertionRange: NSRange, in textView: NSTextView) -> Bool {
            guard let storage = textView.textStorage,
                  let (lineStart, lineRange, lineContent) = lineInfo(for: insertionRange, in: textView) else {
                return false
            }

            let existingFormattingLength = existingListFormattingLength(at: lineStart, lineRange: lineRange, lineContent: lineContent, in: storage)
            guard existingFormattingLength > 0 else { return false }

            let formattingEnd = lineStart + existingFormattingLength
            if insertionRange.location <= formattingEnd {
                textView.setSelectedRange(NSRange(location: formattingEnd, length: 0))
                return true
            }

            return false
        }

        func insertUncheckedCheckbox() {
            guard let textView = textView,
                  let storage = textView.textStorage else {
                return
            }

            let selectedRange = textView.selectedRange

            if selectedRange.length > 0 {
                let selectedText = storage.attributedSubstring(from: selectedRange).string
                let lines = selectedText.components(separatedBy: .newlines)
                if lines.count > 1 {
                    insertCheckboxForMultipleLines(range: selectedRange)
                } else {
                    insertCheckboxAtPosition(insertionRange: selectedRange)
                }
            } else {
                insertCheckboxAtPosition(insertionRange: selectedRange)
            }

            applyTypingAttributes(to: textView)
        }

        private func insertCheckboxAtPosition(insertionRange: NSRange) {
            guard let textView = textView,
                  let storage = textView.textStorage else { return }

            if skipListInsertionIfFormattingExists(at: insertionRange, in: textView) {
                return
            }

            let needsSpace = checkboxNeedsTrailingSpace(after: insertionRange.location, in: storage.string)
            let replacement = checkboxPrefix(includeSpace: needsSpace)
            let insertionPoint = NSRange(location: insertionRange.location, length: 0)

            let insertedLength = replaceText(in: insertionPoint, with: replacement, in: textView)
            let newCursorPosition = insertionRange.location + insertedLength
            textView.setSelectedRange(NSRange(location: newCursorPosition, length: 0))
        }

        private func insertCheckboxForMultipleLines(range: NSRange) {
            guard let textView = textView,
                  let storage = textView.textStorage else {
                return
            }

            let fullText = storage.string as NSString
            let spaceAttrs = checkboxSpaceAttributes()

            let selectedStart = range.location
            let originalSelectedEnd = range.location + range.length

            var lineStartPos = selectedStart
            while lineStartPos > 0 &&
                    fullText.character(at: lineStartPos - 1) != 10 {
                lineStartPos -= 1
            }

            var lineBoundaries: [Int] = [lineStartPos]
            var currentPos = lineStartPos

            while currentPos < originalSelectedEnd {
                if currentPos < fullText.length &&
                    fullText.character(at: currentPos) == 10 &&
                    currentPos + 1 <= originalSelectedEnd {
                    lineBoundaries.append(currentPos + 1)
                }
                currentPos += 1
            }

            var affectedEnd = originalSelectedEnd
            while affectedEnd < fullText.length,
                  fullText.character(at: affectedEnd) != 10 {
                affectedEnd += 1
            }

            guard affectedEnd >= lineStartPos else { return }

            let affectedRange = NSRange(location: lineStartPos, length: affectedEnd - lineStartPos)
            let mutableSelection = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: affectedRange))
            let relativeStarts = lineBoundaries
                .map { max(0, min($0 - lineStartPos, mutableSelection.length)) }
                .filter { $0 < mutableSelection.length }

            for lineStart in relativeStarts.reversed() {
                var lineEnd = lineStart
                let mutableString = mutableSelection.mutableString
                while lineEnd < mutableSelection.length && mutableString.character(at: lineEnd) != 10 {
                    lineEnd += 1
                }

                let lineRange = NSRange(location: lineStart, length: lineEnd - lineStart)
                let lineContent = mutableSelection.attributedSubstring(from: lineRange).string

                if lineContent.trimmingCharacters(in: .whitespaces).isEmpty {
                    continue
                }

                let existingFormattingLength = existingListFormattingLength(at: lineStart,
                                                                            lineRange: lineRange,
                                                                            lineContent: lineContent,
                                                                            in: storage)

                if existingFormattingLength > 0 {
                    continue
                }

                let checkbox = CheckboxTextAttachment(checkboxID: UUID().uuidString, isChecked: false, fontPointSize: activeFontSize.rawValue)
                let checkboxString = NSAttributedString(attachment: checkbox)
                mutableSelection.insert(checkboxString, at: lineStart)

                let charAfterCheckbox = lineStart + checkboxString.length
                if charAfterCheckbox < mutableSelection.length {
                    let nextCharRange = NSRange(location: charAfterCheckbox, length: 1)
                    let nextChar = mutableSelection.attributedSubstring(from: nextCharRange).string
                    if nextChar != " " && nextChar != "\n" {
                        mutableSelection.insert(NSAttributedString(string: " ", attributes: spaceAttrs), at: charAfterCheckbox)
                    }
                } else {
                    mutableSelection.append(NSAttributedString(string: " ", attributes: spaceAttrs))
                }
            }

            let delta = replaceText(in: affectedRange, with: mutableSelection, in: textView)
            let newCursorPos = min(originalSelectedEnd + delta, storage.length)
            textView.setSelectedRange(NSRange(location: newCursorPos, length: 0))
        }

        private func checkboxPrefix(includeSpace: Bool) -> NSAttributedString {
            let checkbox = CheckboxTextAttachment(checkboxID: UUID().uuidString, isChecked: false, fontPointSize: activeFontSize.rawValue)
            let prefix = NSMutableAttributedString(attachment: checkbox)
            if includeSpace {
                prefix.append(NSAttributedString(string: " ", attributes: checkboxSpaceAttributes()))
            }
            return prefix
        }

        private func checkboxSpaceAttributes() -> [NSAttributedString.Key: Any] {
            let baseFont = NSFont.systemFont(ofSize: activeFontSize.rawValue)
            return [.font: baseFont]
        }

        private func checkboxNeedsTrailingSpace(after location: Int, in fullText: String) -> Bool {
            guard location < fullText.count else { return true }
            let index = fullText.index(fullText.startIndex, offsetBy: location)
            let char = fullText[index]
            return char != " " && char != "\n"
        }

        func insertDash() {
            guard let textView = textView,
                  let storage = textView.textStorage else {
                return
            }

            registerUndoSnapshot(for: textView, actionName: "Insert Dash")
            let selectedRange = textView.selectedRange

            // Check if multiple lines are selected
            if selectedRange.length > 0 {
                let selectedText = storage.attributedSubstring(from: selectedRange).string
                let lines = selectedText.components(separatedBy: .newlines)

                if lines.count > 1 {
                    // Multiple lines selected
                    insertDashForMultipleLines(range: selectedRange)
                } else {
                    // Single line selected - use original behavior
                    insertDashAtPosition(insertionRange: selectedRange)
                }
            } else {
                // No selection - insert at cursor position
                insertDashAtPosition(insertionRange: selectedRange)
            }

            applyTypingAttributes(to: textView)
        }

        private func insertDashAtPosition(insertionRange: NSRange) {
            guard let textView = textView else { return }

            if skipListInsertionIfFormattingExists(at: insertionRange, in: textView) {
                return
            }

            let dashText = "- "
            let fontAttrs = currentTypingAttributes(from: textView)
            let dashString = NSAttributedString(string: dashText, attributes: fontAttrs)

            let insertionPoint = NSRange(location: insertionRange.location, length: 0)
            _ = replaceText(in: insertionPoint, with: dashString, in: textView)

            let newCursorPosition = insertionRange.location + dashText.count
            textView.setSelectedRange(NSRange(location: newCursorPosition, length: 0))
        }

        private func insertDashForMultipleLines(range: NSRange) {
            guard let textView = textView,
                  let storage = textView.textStorage else {
                return
            }

            let fontAttrs = currentTypingAttributes(from: textView)
            let dashText = "- "
            let dashString = NSAttributedString(string: dashText, attributes: fontAttrs)
            let fullText = storage.string as NSString

            // Find the start and end positions in the original text
            let selectedStart = range.location
            let selectedEnd = range.location + range.length

            var lineStartPos = selectedStart
            while lineStartPos > 0,
                  fullText.character(at: lineStartPos - 1) != 10 {
                lineStartPos -= 1
            }

            // Find all line starts in the selected range
            var lineBoundaries: [Int] = [lineStartPos]
            var currentPos = lineStartPos

            while currentPos < selectedEnd {
                if currentPos < fullText.length && fullText.character(at: currentPos) == 10 && currentPos + 1 < selectedEnd {
                    lineBoundaries.append(currentPos + 1)
                }
                currentPos += 1
            }

            var affectedEnd = selectedEnd
            while affectedEnd < fullText.length {
                if fullText.character(at: affectedEnd) == 10 {
                    break
                }
                affectedEnd += 1
            }

            guard affectedEnd >= lineStartPos else { return }

            let affectedRange = NSRange(location: lineStartPos, length: affectedEnd - lineStartPos)
            let mutableSelection = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: affectedRange))
            let relativeStarts = lineBoundaries
                .map { max(0, min($0 - lineStartPos, mutableSelection.length)) }
                .filter { $0 < mutableSelection.length }

            // Process lines in reverse to avoid position shifting issues
            for lineStart in relativeStarts.reversed() {
                var lineEnd = lineStart
                let mutableString = mutableSelection.mutableString
                while lineEnd < mutableSelection.length && mutableString.character(at: lineEnd) != 10 {
                    lineEnd += 1
                }

                let lineRange = NSRange(location: lineStart, length: lineEnd - lineStart)
                let lineContent = mutableSelection.attributedSubstring(from: lineRange).string

                // Skip empty lines
                if lineContent.trimmingCharacters(in: .whitespaces).isEmpty {
                    continue
                }

                // Skip lines that already have list-style formatting
                let existingFormattingLength = existingListFormattingLength(at: lineStart,
                                                                            lineRange: lineRange,
                                                                            lineContent: lineContent,
                                                                            in: storage)

                if existingFormattingLength > 0 {
                    continue
                }

                mutableSelection.insert(NSAttributedString(attributedString: dashString), at: lineStart)
            }

            let delta = replaceText(in: affectedRange, with: mutableSelection, in: textView)
            let newCursorPos = min(selectedEnd + delta, textView.textStorage?.length ?? 0)
            textView.setSelectedRange(NSRange(location: newCursorPos, length: 0))
        }

        @discardableResult
        private func replaceText(in range: NSRange,
                                 with replacement: NSAttributedString,
                                 in textView: NSTextView) -> Int {
            guard let storage = textView.textStorage else { return 0 }

            if !textView.shouldChangeText(in: range, replacementString: replacement.string) {
                return 0
            }

            storage.beginEditing()
            storage.replaceCharacters(in: range, with: replacement)
            storage.endEditing()

            textView.didChangeText()
            return replacement.length - range.length
        }

        func insertBullet() {
            guard let textView = textView,
                  let storage = textView.textStorage else {
                return
            }

            registerUndoSnapshot(for: textView, actionName: "Insert Bullet")
            let selectedRange = textView.selectedRange

            if selectedRange.length > 0 {
                let selectedText = storage.attributedSubstring(from: selectedRange).string
                let lines = selectedText.components(separatedBy: .newlines)

                if lines.count > 1 {
                    insertBulletForMultipleLines(range: selectedRange)
                } else {
                    insertBulletAtPosition(insertionRange: selectedRange)
                }
            } else {
                insertBulletAtPosition(insertionRange: selectedRange)
            }

            applyTypingAttributes(to: textView)
        }

        private func insertBulletAtPosition(insertionRange: NSRange) {
            guard let textView = textView else { return }

            if skipListInsertionIfFormattingExists(at: insertionRange, in: textView) {
                return
            }

            let bulletText = "• "
            let fontAttrs = currentTypingAttributes(from: textView)
            let bulletString = NSAttributedString(string: bulletText, attributes: fontAttrs)

            let insertionPoint = NSRange(location: insertionRange.location, length: 0)
            _ = replaceText(in: insertionPoint, with: bulletString, in: textView)

            let newCursorPosition = insertionRange.location + bulletText.count
            textView.setSelectedRange(NSRange(location: newCursorPosition, length: 0))
        }

        private func insertBulletForMultipleLines(range: NSRange) {
            guard let textView = textView,
                  let storage = textView.textStorage else {
                return
            }

            let fontAttrs = currentTypingAttributes(from: textView)
            let bulletText = "• "
            let fullText = storage.string as NSString

            let selectedStart = range.location
            let originalSelectedEnd = range.location + range.length

            var lineStartPos = selectedStart
            while lineStartPos > 0 &&
                    fullText.character(at: lineStartPos - 1) != 10 {
                lineStartPos -= 1
            }

            var lineBoundaries: [Int] = [lineStartPos]
            var currentPos = lineStartPos

            while currentPos < originalSelectedEnd {
                if currentPos < fullText.length &&
                    fullText.character(at: currentPos) == 10 &&
                    currentPos + 1 <= originalSelectedEnd {
                    lineBoundaries.append(currentPos + 1)
                }
                currentPos += 1
            }

            var affectedEnd = originalSelectedEnd
            while affectedEnd < fullText.length,
                  fullText.character(at: affectedEnd) != 10 {
                affectedEnd += 1
            }

            guard affectedEnd >= lineStartPos else { return }

            let affectedRange = NSRange(location: lineStartPos, length: affectedEnd - lineStartPos)
            let mutableSelection = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: affectedRange))
            let relativeStarts = lineBoundaries
                .map { max(0, min($0 - lineStartPos, mutableSelection.length)) }
                .filter { $0 < mutableSelection.length }

            for lineStart in relativeStarts.reversed() {
                var lineEnd = lineStart
                let mutableString = mutableSelection.mutableString
                while lineEnd < mutableSelection.length && mutableString.character(at: lineEnd) != 10 {
                    lineEnd += 1
                }

                let lineRange = NSRange(location: lineStart, length: lineEnd - lineStart)
                let lineContent = mutableSelection.attributedSubstring(from: lineRange).string

                if lineContent.trimmingCharacters(in: .whitespaces).isEmpty {
                    continue
                }

                let existingFormattingLength = existingListFormattingLength(at: lineStart,
                                                                            lineRange: lineRange,
                                                                            lineContent: lineContent,
                                                                            in: storage)

                if existingFormattingLength > 0 {
                    continue
                }

                let bulletString = NSAttributedString(string: bulletText, attributes: fontAttrs)
                mutableSelection.insert(bulletString, at: lineStart)
            }

            let delta = replaceText(in: affectedRange, with: mutableSelection, in: textView)
            let newCursorPos = min(originalSelectedEnd + delta, storage.length)
            textView.setSelectedRange(NSRange(location: newCursorPos, length: 0))
        }

        func insertNumbering() {
            guard let textView = textView,
                  let storage = textView.textStorage else {
                return
            }

            registerUndoSnapshot(for: textView, actionName: "Insert Number")
            let selectedRange = textView.selectedRange

            if selectedRange.length > 0 {
                let selectedText = storage.attributedSubstring(from: selectedRange).string
                let lines = selectedText.components(separatedBy: .newlines)

                if lines.count > 1 {
                    insertNumberingForMultipleLines(range: selectedRange)
                } else {
                    insertNumberingAtPosition(insertionRange: selectedRange)
                }
            } else {
                insertNumberingAtPosition(insertionRange: selectedRange)
            }

            applyTypingAttributes(to: textView)
        }

        private func insertNumberingAtPosition(insertionRange: NSRange) {
            applyNumbering(to: insertionRange, includeFollowingNumberedLines: true)
        }

        private func insertNumberingForMultipleLines(range: NSRange) {
            applyNumbering(to: range, includeFollowingNumberedLines: false)
        }

        private func applyNumbering(to range: NSRange, includeFollowingNumberedLines: Bool) {
            guard let textView = textView,
                  let storage = textView.textStorage else {
                return
            }

            let fontAttrs = currentTypingAttributes(from: textView)
            let fullText = storage.string as NSString

            let selectedStart = range.location
            let originalSelectedEnd = range.location + range.length

            var lineStartPos = selectedStart
            while lineStartPos > 0 &&
                    fullText.character(at: lineStartPos - 1) != 10 {
                lineStartPos -= 1
            }

            var effectiveEnd = max(originalSelectedEnd, selectedStart)
            while effectiveEnd < fullText.length,
                  fullText.character(at: effectiveEnd) != 10 {
                effectiveEnd += 1
            }

            var lineBoundaries: [Int] = [lineStartPos]
            var currentPos = lineStartPos

            while currentPos < effectiveEnd {
                if currentPos < fullText.length &&
                    fullText.character(at: currentPos) == 10 &&
                    currentPos + 1 <= effectiveEnd {
                    lineBoundaries.append(currentPos + 1)
                }
                currentPos += 1
            }

            if includeFollowingNumberedLines {
                var scanPos = effectiveEnd
                while scanPos < fullText.length {
                    if fullText.character(at: scanPos) != 10 {
                        scanPos += 1
                        continue
                    }

                    let nextLineStart = scanPos + 1
                    if nextLineStart >= fullText.length { break }

                    var nextLineEnd = nextLineStart
                    while nextLineEnd < fullText.length &&
                            fullText.character(at: nextLineEnd) != 10 {
                        nextLineEnd += 1
                    }

                    let lineRange = NSRange(location: nextLineStart, length: nextLineEnd - nextLineStart)
                    let lineContent = fullText.substring(with: lineRange)

                    if lineContent.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
                        lineBoundaries.append(nextLineStart)
                        effectiveEnd = nextLineEnd
                        scanPos = nextLineEnd
                    } else {
                        break
                    }
                }
            }

            guard effectiveEnd >= lineStartPos else { return }

            let affectedRange = NSRange(location: lineStartPos, length: effectiveEnd - lineStartPos)
            let mutableSelection = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: affectedRange))
            let relativeStarts = lineBoundaries
                .map { max(0, min($0 - lineStartPos, mutableSelection.length)) }
                .filter { $0 <= mutableSelection.length }

            var lineNumber = relativeStarts.count
            for lineStart in relativeStarts.reversed() {
                guard lineStart <= mutableSelection.length else {
                    lineNumber -= 1
                    continue
                }

                var lineEnd = lineStart
                let mutableString = mutableSelection.mutableString
                while lineEnd < mutableSelection.length && mutableString.character(at: lineEnd) != 10 {
                    lineEnd += 1
                }

                let lineRange = NSRange(location: lineStart, length: lineEnd - lineStart)
                let lineContent = mutableSelection.attributedSubstring(from: lineRange).string
                let isFirstLine = (lineNumber == relativeStarts.count)

                if lineContent.trimmingCharacters(in: .whitespaces).isEmpty &&
                    !(includeFollowingNumberedLines && isFirstLine) {
                    lineNumber -= 1
                    continue
                }

                var existingFormattingLength = 0
                if lineStart < mutableSelection.length,
                   mutableSelection.attribute(NSAttributedString.Key.attachment,
                                             at: lineStart,
                                             longestEffectiveRange: nil,
                                             in: lineRange) is CheckboxTextAttachment {
                    existingFormattingLength = min(2, mutableSelection.length - lineStart)
                }

                if existingFormattingLength == 0 {
                    if let dashMatch = lineContent.range(of: #"^-\s"#, options: .regularExpression) {
                        existingFormattingLength = lineContent.distance(from: lineContent.startIndex, to: dashMatch.upperBound)
                    } else if let bulletMatch = lineContent.range(of: #"^•\s"#, options: .regularExpression) {
                        existingFormattingLength = lineContent.distance(from: lineContent.startIndex, to: bulletMatch.upperBound)
                    } else if let numberMatch = lineContent.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                        existingFormattingLength = lineContent.distance(from: lineContent.startIndex, to: numberMatch.upperBound)
                    }
                }

                if existingFormattingLength > 0 {
                    let removalLength = min(existingFormattingLength, mutableSelection.length - lineStart)
                    mutableSelection.deleteCharacters(in: NSRange(location: lineStart, length: removalLength))
                }

                let numberText = "\(lineNumber). "
                let numberString = NSAttributedString(string: numberText, attributes: fontAttrs)
                mutableSelection.insert(numberString, at: lineStart)

                lineNumber -= 1
            }

            let delta = replaceText(in: affectedRange, with: mutableSelection, in: textView)

            if includeFollowingNumberedLines {
                let cursorPosition = min(lineStartPos + "1. ".count, storage.length)
                textView.setSelectedRange(NSRange(location: cursorPosition, length: 0))
            } else {
                let newCursorPos = min(originalSelectedEnd + delta, storage.length)
                textView.setSelectedRange(NSRange(location: newCursorPos, length: 0))
            }
        }

        func insertDate(using format: DateInsertionFormat) {
            guard let textView = textView else { return }

            isProgrammaticUpdate = true

            textView.breakUndoCoalescing()
            let dateText = format.formattedDate()
            let fontAttrs = currentTypingAttributes(from: textView)
            let dateString = NSAttributedString(string: dateText, attributes: fontAttrs)

            textView.insertText(dateString, replacementRange: textView.selectedRange())
            textView.undoManager?.setActionName("Insert Date")
            textView.breakUndoCoalescing()
            applyTypingAttributes(to: textView)

            let newText = textView.attributedString()
            DispatchQueue.main.async { [weak self] in
                self?.parent.text = newText
                self?.isProgrammaticUpdate = false
            }
        }

        func insertTime(using format: TimeInsertionFormat) {
            guard let textView = textView else { return }

            isProgrammaticUpdate = true

            textView.breakUndoCoalescing()
            let timeText = format.formattedTime()

            let fontAttrs = currentTypingAttributes(from: textView)
            let timeString = NSAttributedString(string: timeText, attributes: fontAttrs)

            textView.insertText(timeString, replacementRange: textView.selectedRange())
            textView.undoManager?.setActionName("Insert Time")
            textView.breakUndoCoalescing()
            applyTypingAttributes(to: textView)

            let newText = textView.attributedString()
            DispatchQueue.main.async { [weak self] in
                self?.parent.text = newText
                self?.isProgrammaticUpdate = false
            }
        }

        func insertURL(using request: URLInsertionRequest) {
            guard let textView = textView,
                  let storage = textView.textStorage else {
                return
            }

            guard let linkURL = URL(string: request.urlString) else {
                return
            }

            registerUndoSnapshot(for: textView, actionName: "Insert Link")
            isProgrammaticUpdate = true

            let baseRange = request.replacementRange?.nsRange ?? textView.selectedRange
            let insertionRange = clampRange(baseRange, length: storage.length)
            let shouldAppendTrailingSpace = request.replacementRange == nil

            // Create link attributes with blue color and underline
            let linkAttrs: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key.font: NSFont.systemFont(ofSize: activeFontSize.rawValue),
                NSAttributedString.Key.foregroundColor: NSColor.systemBlue,
                NSAttributedString.Key.underlineStyle: NSUnderlineStyle.single.rawValue,
                NSAttributedString.Key.link: linkURL,
                ColorMapping.colorIDKey: "blue",
                ColorMapping.fontSizeKey: activeFontSize.rawValue
            ]
            let linkString = NSAttributedString(string: request.displayText, attributes: linkAttrs)

            // Replace the target range or insert at cursor
            storage.replaceCharacters(in: insertionRange, with: linkString)

            var newCursorPosition = insertionRange.location + request.displayText.count

            if shouldAppendTrailingSpace {
                let spaceInsertionPos = newCursorPosition
                if spaceInsertionPos < storage.length {
                    let nextCharRange = NSRange(location: spaceInsertionPos, length: 1)
                    let nextChar = storage.attributedSubstring(from: nextCharRange).string
                    if nextChar != " " {
                        let spaceAttrs = currentTypingAttributes(from: textView)
                        storage.insert(NSAttributedString(string: " ", attributes: spaceAttrs), at: spaceInsertionPos)
                        newCursorPosition += 1
                    } else {
                        newCursorPosition = spaceInsertionPos + 1
                    }
                } else {
                    let spaceAttrs = currentTypingAttributes(from: textView)
                    storage.insert(NSAttributedString(string: " ", attributes: spaceAttrs), at: spaceInsertionPos)
                    newCursorPosition = spaceInsertionPos + 1
                }
            }

            textView.setSelectedRange(NSRange(location: newCursorPosition, length: 0))
            applyTypingAttributes(to: textView)

            // Defer binding update to next runloop to avoid state modification during view update
            let newText = NSAttributedString(attributedString: storage)
            DispatchQueue.main.async { [weak self] in
                self?.parent.text = newText
                self?.isProgrammaticUpdate = false
            }
        }

        func insertPlainText(_ text: String) {
            guard let textView = textView else { return }
            registerUndoSnapshot(for: textView, actionName: "Insert Text")
            isProgrammaticUpdate = true

            let insertionRange = textView.selectedRange()
            let fontAttrs = currentTypingAttributes(from: textView)
            let attributed = NSAttributedString(string: text, attributes: fontAttrs)

            textView.insertText(attributed, replacementRange: insertionRange)
            textView.undoManager?.setActionName("Insert Text")
            applyTypingAttributes(to: textView)

            DispatchQueue.main.async { [weak self] in
                guard let self, let storage = textView.textStorage else { return }
                self.parent.text = NSAttributedString(attributedString: storage)
                self.isProgrammaticUpdate = false
            }
        }

        private func clampRange(_ range: NSRange, length: Int) -> NSRange {
            let clampedLocation = min(max(0, range.location), length)
            let remaining = max(0, length - clampedLocation)
            let clampedLength = min(max(0, range.length), remaining)
            return NSRange(location: clampedLocation, length: clampedLength)
        }

        func pastePlaintext() {
            guard let textView = textView,
                  let storage = textView.textStorage else {
                return
            }

            let pasteboard = NSPasteboard.general
            guard let plainText = pasteboard.string(forType: .string) else {
                return
            }

            // Register undo snapshot BEFORE making changes
            registerUndoSnapshot(for: textView, actionName: "Paste as Plaintext")

            isProgrammaticUpdate = true

            let insertionRange = textView.selectedRange

            // Build plaintext attributes with AUTOMATIC (theme-aware) color, not current color
            // This ensures text appears white in dark mode and black in light mode
            // Strip all formatting: bold, italic, underline, strikethrough, highlight
            let plaintextStyler = TextStyler(
                isBold: false,  // Strip bold in plaintext
                isItalic: false,  // Strip italic in plaintext
                fontSize: activeFontSize,
                colorID: RichTextColor.automatic.id,
                color: RichTextColor.automatic.nsColor,
                highlightID: nil,
                highlight: nil,
                isUnderlined: false,  // Strip underline in plaintext
                isStrikethrough: false  // Strip strikethrough in plaintext
            )

            var plainAttrs = plaintextStyler.buildAttributes(usingAutomatic: true, customColor: nil)

            // Strip out formatting attributes that shouldn't be in "plaintext"
            // Keep: font, size, color (automatic/themed), bold, italic
            // Remove: underline, strikethrough, highlight, any other formatting
            plainAttrs.removeValue(forKey: NSAttributedString.Key.underlineStyle)
            plainAttrs.removeValue(forKey: NSAttributedString.Key.strikethroughStyle)
            // Remove highlight-related attributes
            plainAttrs.removeValue(forKey: NSAttributedString.Key.backgroundColor)
            plainAttrs.removeValue(forKey: ColorMapping.highlightIDKey)

            let plainAttributedString = NSAttributedString(string: plainText, attributes: plainAttrs)

            // Replace selected text or insert at cursor
            if insertionRange.length > 0 {
                storage.replaceCharacters(in: insertionRange, with: plainAttributedString)
                let newCursorPosition = insertionRange.location + plainText.count
                textView.setSelectedRange(NSRange(location: newCursorPosition, length: 0))
            } else {
                storage.insert(plainAttributedString, at: insertionRange.location)
                let newCursorPosition = insertionRange.location + plainText.count
                textView.setSelectedRange(NSRange(location: newCursorPosition, length: 0))
            }

            applyTypingAttributes(to: textView)

            // Defer binding update to next runloop to avoid state modification during view update
            let newText = NSAttributedString(attributedString: storage)
            DispatchQueue.main.async { [weak self] in
                self?.parent.text = newText
                self?.isProgrammaticUpdate = false
            }

            // Reset trigger SYNCHRONOUSLY to prevent it from triggering on note switches.
            // This must happen synchronously (not in the async block) to ensure the trigger
            // is cleared before a user can switch notes. If a new Coordinator is created
            // before the trigger is reset, it will see the old UUID as a "change" and trigger again.
            parent.pastePlaintextTrigger = nil
        }
    }
}

#endif
