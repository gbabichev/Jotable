import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct NoteEditorView: View {
    @Bindable var item: Item
    @Environment(\.modelContext) private var modelContext
    @FocusState private var isTitleFocused: Bool
    @State private var showingCategoryPicker = false
    #if os(macOS)
    @Binding var pastePlaintextTrigger: UUID?
    #endif
    @Binding var isEditorActive: Bool
    @State private var richText = AttributedTextWrapper(value: NSAttributedString(string: ""))
    @State private var activeColor: RichTextColor = .automatic
    @State private var activeHighlighter: HighlighterColor = .none
    @State private var activeFontSize: FontSize = .normal
    @State private var isBold: Bool = false
    @State private var isItalic: Bool = false
    @State private var isUnderlined: Bool = false
    @State private var isStrikethrough: Bool = false
    @State private var insertUncheckedCheckboxTrigger: UUID?
    @State private var insertDashTrigger: UUID?
    @State private var insertBulletTrigger: UUID?
    @State private var insertNumberingTrigger: UUID?
    @State private var dateInsertionFormat: DateInsertionFormat = .monthDayYear
    @State private var dateInsertionRequest: DateInsertionRequest?
    @State private var timeInsertionFormat: TimeInsertionFormat = .twentyFourHour
    @State private var timeInsertionRequest: TimeInsertionRequest?
    @State private var insertURLTrigger: URLInsertionRequest?
    @State private var plainTextInsertionRequest: PlainTextInsertionRequest?
    @State private var presentFormatMenuTrigger: UUID?
    @State private var resetColorTrigger: UUID?
    @State private var tempURLData: (String, String)? = nil
    @State private var showingAddURLDialog: Bool = false
    @State private var showingPasswordGenerator: Bool = false
    @State private var headerHeight: CGFloat = 0
    @State private var lastSyncedRichText: NSAttributedString?
    @State private var skipNextAttributedContentChange = false
    @State private var isLoadingContent = false
#if !os(macOS)
    @State private var linkEditRequest: LinkEditContext?
#endif

    var body: some View {
        editorContent
#if os(macOS)
            .addURLSheet(isPresented: $showingAddURLDialog, tempURLData: $tempURLData)
#else
            .addURLSheet(
                isPresented: $showingAddURLDialog,
                tempURLData: $tempURLData,
                editingContext: linkEditRequest
            ) {
                if tempURLData == nil {
                    linkEditRequest = nil
                }
            }
#endif
            .sheet(isPresented: $showingPasswordGenerator) {
                PasswordGeneratorView { password in
                    plainTextInsertionRequest = PlainTextInsertionRequest(text: password)
                    showingPasswordGenerator = false
                }
            }
            .onChange(of: tempURLData != nil) { _, hasData in
                guard hasData else { return }
            handlePendingURLData(tempURLData)
        }
#if !os(macOS)
            .onChange(of: linkEditRequest) { _, newValue in
                guard newValue != nil else { return }
                showingAddURLDialog = true
            }
#endif
#if os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: .toggleBoldShortcut)) { _ in
                isBold.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleItalicShortcut)) { _ in
                isItalic.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleUnderlineShortcut)) { _ in
                isUnderlined.toggle()
            }
#endif
    }

    private var richTextEditorView: some View {
        let textBinding = Binding(
            get: { richText.value },
            set: { newValue in
                // Check if content actually changed by comparing string content AND attachment states
                let stringChanged = richText.value.string != newValue.string
                let hasChanged = lastSyncedRichText == nil || stringChanged

                if hasChanged {
                    let snapshot = NSAttributedString(attributedString: newValue)
                    richText = AttributedTextWrapper(value: snapshot)
                    lastSyncedRichText = snapshot
                } else if !newValue.isEqual(to: richText.value) {
                    // Even if string is the same, if attachments differ (e.g., checkbox state), update
                    let snapshot = NSAttributedString(attributedString: newValue)
                    richText = AttributedTextWrapper(value: snapshot)
                    lastSyncedRichText = snapshot
                }
            }
        )

        #if os(macOS)
        return RichTextEditor(
            text: textBinding,
            activeColor: $activeColor,
            activeHighlighter: $activeHighlighter,
            activeFontSize: $activeFontSize,
            isBold: $isBold,
            isItalic: $isItalic,
            isUnderlined: $isUnderlined,
            isStrikethrough: $isStrikethrough,
            insertUncheckedCheckboxTrigger: $insertUncheckedCheckboxTrigger,
            insertDashTrigger: $insertDashTrigger,
            insertBulletTrigger: $insertBulletTrigger,
            insertNumberingTrigger: $insertNumberingTrigger,
            dateInsertionRequest: $dateInsertionRequest,
            timeInsertionRequest: $timeInsertionRequest,
            insertURLTrigger: $insertURLTrigger,
            plainTextInsertionRequest: $plainTextInsertionRequest,
            presentFormatMenuTrigger: $presentFormatMenuTrigger,
            resetColorTrigger: $resetColorTrigger,
            pastePlaintextTrigger: $pastePlaintextTrigger
        )
        #else
        return RichTextEditor(
            text: textBinding,
            activeColor: $activeColor,
            activeHighlighter: $activeHighlighter,
            activeFontSize: $activeFontSize,
            isBold: $isBold,
            isItalic: $isItalic,
            isUnderlined: $isUnderlined,
            isStrikethrough: $isStrikethrough,
            insertUncheckedCheckboxTrigger: $insertUncheckedCheckboxTrigger,
            insertDashTrigger: $insertDashTrigger,
            insertBulletTrigger: $insertBulletTrigger,
            insertNumberingTrigger: $insertNumberingTrigger,
            dateInsertionRequest: $dateInsertionRequest,
            timeInsertionRequest: $timeInsertionRequest,
            insertURLTrigger: $insertURLTrigger,
            plainTextInsertionRequest: $plainTextInsertionRequest,
            presentFormatMenuTrigger: $presentFormatMenuTrigger,
            resetColorTrigger: $resetColorTrigger,
            linkEditRequest: $linkEditRequest
        )
        #endif
    }

    private var editorContent: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    NoteHeaderView(
                        item: item,
                        onHeaderHeightChange: { height in
                            headerHeight = height
                        }
                    )
                    .padding(.horizontal)

                    //Divider()
                    
                    richTextEditorView
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: max(proxy.size.height - headerHeight - 12, 0))
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear {
            loadContentIfNeeded()
            lastSyncedRichText = richText.value
            if item.title.isEmpty && item.content.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isTitleFocused = true
                }
            }
        }
        .onChange(of: item.attributedContent) { _, _ in
            // Skip if we just saved this content ourselves
            if skipNextAttributedContentChange {
                skipNextAttributedContentChange = false
                return
            }
            loadContentIfNeeded()
        }
        .onChange(of: richText) { _, newWrapper in
            if isLoadingContent {
                return
            }
            item.content = newWrapper.value.string
            item.attributedContent = archiveAttributedString(newWrapper.value)
            item.timestamp = Date()
            skipNextAttributedContentChange = true
            saveChanges()
        }
        .onDisappear {
            saveChanges()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ListToolbar(
                    insertUncheckedCheckboxTrigger: $insertUncheckedCheckboxTrigger,
                    insertDashTrigger: $insertDashTrigger,
                    insertBulletTrigger: $insertBulletTrigger,
                    insertNumberingTrigger: $insertNumberingTrigger,
                    dateInsertionRequest: $dateInsertionRequest,
                    dateInsertionFormat: $dateInsertionFormat,
                    timeInsertionRequest: $timeInsertionRequest,
                    timeInsertionFormat: $timeInsertionFormat,
                    showingAddURLDialog: $showingAddURLDialog,
                    tempURLData: $tempURLData,
                    showingPasswordGenerator: $showingPasswordGenerator
                )

                FontToolbar(
                    activeColor: $activeColor,
                    activeHighlighter: $activeHighlighter,
                    activeFontSize: $activeFontSize,
                    isBold: $isBold,
                    isItalic: $isItalic,
                    isUnderlined: $isUnderlined,
                    isStrikethrough: $isStrikethrough,
                    presentFormatMenuTrigger: $presentFormatMenuTrigger,
                    resetColorTrigger: $resetColorTrigger
                )
            }
            
            ToolbarItem(placement: .primaryAction) {

            }
            
        }
    }


    private func loadContentIfNeeded() {
        if let data = item.attributedContent, let attributed = unarchiveAttributedString(data) {
            if !attributed.isEqual(to: richText.value) {
                isLoadingContent = true
                richText = AttributedTextWrapper(value: attributed)
                DispatchQueue.main.async {
                    isLoadingContent = false
                }
            }
        } else if richText.value.string != item.content {
            isLoadingContent = true
            richText = AttributedTextWrapper(value: NSAttributedString(string: item.content))
            DispatchQueue.main.async {
                isLoadingContent = false
            }
        }
    }

    private func archiveAttributedString(_ attributedString: NSAttributedString) -> Data? {
        // First, remove the temporary marker attribute used for change detection
        let cleanedString = removeCheckboxMarkerAttribute(attributedString)

        // Extract checkbox states before archiving
        // because NSKeyedArchiver may not properly serialize CheckboxTextAttachment
        let stringToArchive = extractAndStoreCheckboxStates(cleanedString)

        // Preprocess: ensure all colors have color IDs stored for cross-platform sync
        let processedString = ColorMapping.preprocessForArchiving(stringToArchive)

        do {
            let data = try NSKeyedArchiver.archivedData(
                withRootObject: processedString,
                requiringSecureCoding: false  // Disable secure coding for NSTextAttachment compatibility
            )
            return data
        } catch {
            return nil
        }
    }

    private func removeCheckboxMarkerAttribute(_ attributedString: NSAttributedString) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: attributedString)
        let checkboxMarkerKey = NSAttributedString.Key(rawValue: "checkboxStateChanged")
        let imageResizeMarkerKey = NSAttributedString.Key(rawValue: "imageResizeChanged")

        var pos = 0
        while pos < mutable.length {
            var range = NSRange()
            let attrs = mutable.attributes(at: pos, longestEffectiveRange: &range, in: NSRange(location: pos, length: mutable.length - pos))

            if attrs[checkboxMarkerKey] != nil {
                mutable.removeAttribute(checkboxMarkerKey, range: range)
            }

            if attrs[imageResizeMarkerKey] != nil {
                mutable.removeAttribute(imageResizeMarkerKey, range: range)
            }

            pos = range.location + range.length
        }

        return mutable
    }

    private func extractAndStoreCheckboxStates(_ attributedString: NSAttributedString) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: attributedString)

        var pos = 0
        while pos < mutable.length {
            var range = NSRange()
            let attrs = mutable.attributes(at: pos, longestEffectiveRange: &range, in: NSRange(location: pos, length: mutable.length - pos))

            // Check if this position has a checkbox attachment
            if let checkbox = attrs[NSAttributedString.Key.attachment] as? CheckboxTextAttachment {
                // Store checkbox state as attributes so they survive archiving
                let checkboxIDKey = NSAttributedString.Key(rawValue: "checkboxID")
                let checkboxIsCheckedKey = NSAttributedString.Key(rawValue: "checkboxIsChecked")
                mutable.addAttribute(checkboxIDKey, value: checkbox.checkboxID, range: range)
                mutable.addAttribute(checkboxIsCheckedKey, value: NSNumber(value: checkbox.isChecked), range: range)
            }

            // Check if this position has a resizable image attachment
            if let imageAttachment = attrs[NSAttributedString.Key.attachment] as? ResizableImageAttachment {
                // Store image size as attributes so they survive archiving
                if let customSize = imageAttachment.customSize {
                    let imageSizeWidthKey = NSAttributedString.Key(rawValue: "imageSizeWidth")
                    let imageSizeHeightKey = NSAttributedString.Key(rawValue: "imageSizeHeight")
                    mutable.addAttribute(imageSizeWidthKey, value: NSNumber(value: Double(customSize.width)), range: range)
                    mutable.addAttribute(imageSizeHeightKey, value: NSNumber(value: Double(customSize.height)), range: range)
                }

                let imageIDKey = NSAttributedString.Key(rawValue: "imageID")
                mutable.addAttribute(imageIDKey, value: imageAttachment.imageID, range: range)
            }

            pos = range.location + range.length
        }

        return mutable
    }

    private func unarchiveAttributedString(_ data: Data) -> NSAttributedString? {
        do {
            // Use the modern decoding API for better NSTextAttachment support
            let result = try NSKeyedUnarchiver.unarchivedObject(ofClass: NSAttributedString.self, from: data)

            // Postprocess: restore colors and checkbox states
            if let resultValue = result {
                let colored = ColorMapping.postprocessAfterUnarchiving(resultValue)
                return restoreCheckboxStates(colored)
            }

            return result
        } catch {
            return nil
        }
    }

    private func restoreCheckboxStates(_ attributedString: NSAttributedString) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: attributedString)

        let checkboxIDKey = NSAttributedString.Key(rawValue: "checkboxID")
        let checkboxIsCheckedKey = NSAttributedString.Key(rawValue: "checkboxIsChecked")
        let imageSizeWidthKey = NSAttributedString.Key(rawValue: "imageSizeWidth")
        let imageSizeHeightKey = NSAttributedString.Key(rawValue: "imageSizeHeight")

        var pos = 0
        while pos < mutable.length {
            var range = NSRange()
            let attrs = mutable.attributes(at: pos, longestEffectiveRange: &range, in: NSRange(location: pos, length: mutable.length - pos))

            // Check if this position has checkbox state attributes
            if let checkboxID = attrs[checkboxIDKey] as? String,
               let isCheckedNum = attrs[checkboxIsCheckedKey] as? NSNumber {
                let isChecked = isCheckedNum.boolValue

                // Check if there's an attachment at this position
                if let checkbox = attrs[NSAttributedString.Key.attachment] as? CheckboxTextAttachment {
                    // Restore the checkbox state
                    checkbox.isChecked = isChecked
                    let stateDict: [String: Any] = ["checkboxID": checkboxID, "isChecked": isChecked]
                    if let stateData = try? JSONSerialization.data(withJSONObject: stateDict) {
                        checkbox.contents = stateData
                    }
                }
            }

            // Check if this position has image size attributes
            if let widthNum = attrs[imageSizeWidthKey] as? NSNumber,
               let heightNum = attrs[imageSizeHeightKey] as? NSNumber {
                let width = CGFloat(widthNum.doubleValue)
                let height = CGFloat(heightNum.doubleValue)

                // Check if there's a resizable image attachment at this position
                if let imageAttachment = attrs[NSAttributedString.Key.attachment] as? ResizableImageAttachment {
                    // Restore the custom size
                    #if os(macOS)
                    imageAttachment.customSize = NSSize(width: width, height: height)
                    #else
                    imageAttachment.customSize = CGSize(width: width, height: height)
                    #endif
                }
            }

            pos = range.location + range.length
        }

        return mutable
    }

    private func saveChanges() {
        do {
            try modelContext.save()
        } catch {
        }
    }

    private func handlePendingURLData(_ data: (String, String)?) {
        guard let (urlString, displayText) = data else { return }
        var replacementRange: LinkRangeSnapshot?
#if !os(macOS)
        replacementRange = linkEditRequest?.range
#endif
        DispatchQueue.main.async {
            insertURLTrigger = URLInsertionRequest(
                id: UUID(),
                urlString: urlString,
                displayText: displayText,
                replacementRange: replacementRange
            )
            showingAddURLDialog = false
            tempURLData = nil
#if !os(macOS)
            linkEditRequest = nil
#endif
        }
    }
}

private struct HeaderHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct AttributedTextWrapper: Equatable {
    var value: NSAttributedString

    static func == (lhs: AttributedTextWrapper, rhs: AttributedTextWrapper) -> Bool {
        lhs.value.isEqual(to: rhs.value)
    }
}

// MARK: - Separate Header View
// Extracted to a separate view to prevent state cascade from title TextEditor to RichTextEditor
// This isolation is critical for preventing the native format sheet freeze
private struct NoteHeaderView: View {
    @Bindable var item: Item
    @State private var showingCategoryPicker = false
    @State private var headerHeight: CGFloat = 0

    var onHeaderHeightChange: (CGFloat) -> Void

    init(
        item: Item,
        onHeaderHeightChange: @escaping (CGFloat) -> Void
    ) {
        self._item = Bindable(item)
        self.onHeaderHeightChange = onHeaderHeightChange
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            TextField("Note Title", text: $item.title)
                .font(.title2.weight(.medium))
                .textFieldStyle(.plain)
                //.lineLimit(2)
                // NO onChange handler - this was the root cause of the freeze
                // Title changes are saved on app exit only

            Button(action: { showingCategoryPicker = true }) {
                HStack(spacing: 6) {
                    if let category = item.category {
                        Circle()
                            .fill(Color.fromString(category.color))
                            .frame(width: 12, height: 12)
                        Text(category.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else {
                        Image(systemName: "folder")
                            .foregroundColor(.secondary)
                        Text("No Category")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            //.buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .cornerRadius(6)
            .categoryPickerPresenter(isPresented: $showingCategoryPicker, selectedCategory: $item.category)
        }
        .background(
            GeometryReader { geometry in
                Color.clear.preference(key: HeaderHeightPreferenceKey.self, value: geometry.size.height)
            }
        )
        .onPreferenceChange(HeaderHeightPreferenceKey.self) { height in
            headerHeight = height
            onHeaderHeightChange(height)
        }
    }
}

#if os(macOS)
private extension View {
    func addURLSheet(isPresented: Binding<Bool>, tempURLData: Binding<(String, String)?>) -> some View {
        self
    }

    func categoryPickerPresenter(isPresented: Binding<Bool>, selectedCategory: Binding<Category?>) -> some View {
        popover(
            isPresented: isPresented,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .bottom
        ) {
            CategoryPickerView(selectedCategory: selectedCategory)
                .frame(width: 280, height: 320)
        }
    }
}

#else
private extension View {
    func addURLSheet(
        isPresented: Binding<Bool>,
        tempURLData: Binding<(String, String)?>,
        editingContext: LinkEditContext?,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        sheet(isPresented: isPresented, onDismiss: {
            onDismiss?()
        }) {
            NavigationStack {
                AddURLView(
                    tempURLData: tempURLData,
                    editingContext: editingContext
                )
            }
        }
    }

    func categoryPickerPresenter(isPresented: Binding<Bool>, selectedCategory: Binding<Category?>) -> some View {
        sheet(isPresented: isPresented) {
            CategoryPickerView(selectedCategory: selectedCategory)
        }
    }
}
#endif
