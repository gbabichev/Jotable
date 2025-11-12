#if os(macOS)
import SwiftUI
import AppKit

private final class DynamicColorTextView: NSTextView {
    var onAppearanceChange: (() -> Void)?
    var onCheckboxTap: ((Int) -> Void)?
    var onColorChange: (() -> Void)?
    var onFormatChange: (() -> Void)?
    var isUnderlinedManually = false  // Track underline state for native menu toggles (which don't update typingAttributes)

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

    override func changeFont(_ sender: Any?) {
        print("[DEBUG] changeFont called, typing attributes before: \(String(describing: typingAttributes[NSAttributedString.Key.font]))")
        let fontManager = NSFontManager.shared
        print("[DEBUG] Font manager selected font: \(String(describing: fontManager.selectedFont))")
        super.changeFont(sender)
        print("[DEBUG] changeFont done, typing attributes after super: \(String(describing: typingAttributes[NSAttributedString.Key.font]))")
        print("[DEBUG] Font manager selected font after super: \(String(describing: fontManager.selectedFont))")

        // Manually update typing attributes to match font manager
        // This is necessary because super.changeFont() doesn't always update typingAttributes properly
        if let selectedFont = fontManager.selectedFont {
            print("[DEBUG] Manually updating typingAttributes with font manager's selected font: \(selectedFont)")
            typingAttributes[NSAttributedString.Key.font] = selectedFont
        }

        // The native font panel has updated, so we need to sync
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            print("[DEBUG] changeFont delayed callback, font manager font: \(String(describing: fontManager.selectedFont))")
            print("[DEBUG] changeFont delayed callback, typing attributes now: \(String(describing: self?.typingAttributes[NSAttributedString.Key.font]))")
            self?.onFormatChange?()
        }
    }

    override func underline(_ sender: Any?) {
        // Track the state before toggle
        let beforeUnderline = isUnderlinedManually

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
        var skipNextColorSampling = false
        var isSyncingFormattingState = false  // Prevent applyTypingAttributes during format sync

        private func effectiveColorComponents() -> (color: NSColor, id: String?) {
            if let customTypingColor {
                let identifier = ColorMapping.identifier(for: customTypingColor, preferPaletteMatch: false)
                return (customTypingColor, identifier)
            }
            return (activeColor.nsColor, activeColor.id)
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
                print("[DEBUG] syncFormattingState: Getting attributes from selected text at location \(selectedRange.location), length \(selectedRange.length)")
                let attrs = storage.attributes(at: selectedRange.location, effectiveRange: nil)
                font = attrs[NSAttributedString.Key.font] as? NSFont
            } else {
                // If no selection, try font manager first (which has the most up-to-date state)
                // Then fall back to typing attributes
                print("[DEBUG] syncFormattingState: No selection (range length: \(selectedRange.length)), checking font manager")
                let fontManager = NSFontManager.shared
                if let managerFont = fontManager.selectedFont {
                    print("[DEBUG] syncFormattingState: Using font manager's selected font: \(managerFont)")
                    font = managerFont
                } else {
                    print("[DEBUG] syncFormattingState: Font manager has no selected font, using typing attributes")
                    let attrs = textView.typingAttributes
                    font = attrs[NSAttributedString.Key.font] as? NSFont
                }
            }

            guard let font = font else {
                print("[DEBUG] syncFormattingState: No font found!")
                return
            }

            print("[DEBUG] syncFormattingState: Font object: \(String(describing: font))")
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
                print("[DEBUG] syncFormattingState: Reading underline/strikethrough from selected text: underline=\(sampledUnderline), strikethrough=\(sampledStrikethrough)")
            } else {
                // No selection - use manual tracking for underline (native menu toggle), but read strikethrough from typing attributes
                if let dynamicTextView = textView as? DynamicColorTextView {
                    sampledUnderline = dynamicTextView.isUnderlinedManually
                    print("[DEBUG] syncFormattingState: Using manually tracked underline: \(sampledUnderline)")
                } else {
                    let underlineValue = textView.typingAttributes[NSAttributedString.Key.underlineStyle] as? Int ?? 0
                    sampledUnderline = underlineValue != 0
                    print("[DEBUG] syncFormattingState: Using typingAttributes for underline: \(sampledUnderline)")
                }

                // For strikethrough, read from typing attributes
                let strikethroughValue = textView.typingAttributes[NSAttributedString.Key.strikethroughStyle] as? Int ?? 0
                sampledStrikethrough = strikethroughValue != 0
                print("[DEBUG] syncFormattingState: Reading strikethrough from typingAttributes: \(sampledStrikethrough)")
            }

            print("[DEBUG] syncFormattingState: Sampled values - bold: \(sampledBold), italic: \(sampledItalic), underline: \(sampledUnderline), strikethrough: \(sampledStrikethrough)")
            print("[DEBUG] syncFormattingState: Current state - isBold: \(isBold), isItalic: \(isItalic), isUnderlined: \(isUnderlined), isStrikethrough: \(isStrikethrough)")
            print("[DEBUG] syncFormattingState: Parent bindings - isBold: \(parent.isBold), isItalic: \(parent.isItalic), isUnderlined: \(parent.isUnderlined), isStrikethrough: \(parent.isStrikethrough)")

            // ALWAYS update state to match what we sampled, regardless of previous state
            // This ensures consistency after native menu changes
            if sampledBold != isBold {
                print("[DEBUG] syncFormattingState: Bold coordinator changed from \(isBold) to \(sampledBold)")
                isBold = sampledBold
                parent.isBold = sampledBold
            } else if sampledBold != parent.isBold {
                // Ensure parent binding is in sync even if coordinator state matches
                print("[DEBUG] syncFormattingState: Bold parent binding out of sync: coordinator=\(isBold), sampled=\(sampledBold), parent was \(parent.isBold), syncing to \(sampledBold)")
                parent.isBold = sampledBold
            }

            if sampledItalic != isItalic {
                print("[DEBUG] syncFormattingState: Italic coordinator changed from \(isItalic) to \(sampledItalic)")
                isItalic = sampledItalic
                parent.isItalic = sampledItalic
            } else if sampledItalic != parent.isItalic {
                print("[DEBUG] syncFormattingState: Italic parent binding out of sync: coordinator=\(isItalic), sampled=\(sampledItalic), parent was \(parent.isItalic), syncing to \(sampledItalic)")
                parent.isItalic = sampledItalic
            }

            if sampledUnderline != isUnderlined {
                print("[DEBUG] syncFormattingState: Underline coordinator changed from \(isUnderlined) to \(sampledUnderline)")
                isUnderlined = sampledUnderline
                parent.isUnderlined = sampledUnderline
            } else if sampledUnderline != parent.isUnderlined {
                print("[DEBUG] syncFormattingState: Underline parent binding out of sync: coordinator=\(isUnderlined), sampled=\(sampledUnderline), parent was \(parent.isUnderlined), syncing to \(sampledUnderline)")
                parent.isUnderlined = sampledUnderline
            }

            if sampledStrikethrough != isStrikethrough {
                print("[DEBUG] syncFormattingState: Strikethrough coordinator changed from \(isStrikethrough) to \(sampledStrikethrough)")
                isStrikethrough = sampledStrikethrough
                parent.isStrikethrough = sampledStrikethrough
            } else if sampledStrikethrough != parent.isStrikethrough {
                print("[DEBUG] syncFormattingState: Strikethrough parent binding out of sync: coordinator=\(isStrikethrough), sampled=\(sampledStrikethrough), parent was \(parent.isStrikethrough), syncing to \(sampledStrikethrough)")
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
                  textView === self.textView else { return }

            // Skip textDidChange during initialization to prevent feedback loops
            guard !isInitializing else { return }

            syncColorState(with: textView, sampleFromText: true)
            syncFormattingState(with: textView)

            // Convert checkbox patterns to attachments
            if let storage = textView.textStorage {
                let spaceAttrs = currentTypingAttributes(from: textView)
                AutoFormatting.convertCheckboxPatterns(in: storage, spaceAttributes: spaceAttrs)
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
            let contentAfter = attributedString.attributedSubstring(from: remainingRange).string.trimmingCharacters(in: .whitespacesAndNewlines)

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

                // Add space after checkbox with minimal attributes (just font) to avoid rendering issues
                let baseFont = NSFont.systemFont(ofSize: activeFontSize.rawValue)
                let spaceAttrs: [NSAttributedString.Key: Any] = [.font: baseFont]
                newLine.append(NSAttributedString(string: " ", attributes: spaceAttrs))
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
                    // Space after attachment should have minimal attributes to avoid rendering issues
                    // Only include font to ensure proper baseline alignment
                    let baseFont = NSFont.systemFont(ofSize: activeFontSize.rawValue)
                    let spaceAttrs: [NSAttributedString.Key: Any] = [.font: baseFont]
                    storage.insert(NSAttributedString(string: " ", attributes: spaceAttrs), at: spaceInsertionPos)
                }
            } else {
                // End of text, just add space with minimal attributes
                let baseFont = NSFont.systemFont(ofSize: activeFontSize.rawValue)
                let spaceAttrs: [NSAttributedString.Key: Any] = [.font: baseFont]
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
