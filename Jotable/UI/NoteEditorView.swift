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
    @State private var richText = AttributedTextWrapper(value: NSAttributedString(string: ""))
    @State private var activeColor: RichTextColor = .automatic
    @State private var activeFontSize: FontSize = .normal
    @State private var isBold: Bool = false
    @State private var isUnderlined: Bool = false
    @State private var isStrikethrough: Bool = false
    @State private var insertUncheckedCheckboxTrigger: UUID?
    @State private var insertCheckedCheckboxTrigger: UUID?
    @State private var insertBulletTrigger: UUID?
    @State private var insertNumberingTrigger: UUID?
    @State private var insertURLTrigger: (UUID, String, String)?
    @State private var tempURLData: (String, String)? = nil
    @State private var showingAddURLDialog: Bool = false
    @State private var headerHeight: CGFloat = 0

    @ViewBuilder
    var body: some View {
#if os(iOS)
        editorContent
            .sheet(isPresented: $showingAddURLDialog) {
                NavigationStack {
                    AddURLView(tempURLData: $tempURLData)
                }
            }
            .onChange(of: tempURLData != nil) { _, hasData in
                guard hasData, let (urlString, displayText) = tempURLData else { return }
                DispatchQueue.main.async {
                    insertURLTrigger = (UUID(), urlString, displayText)
                    showingAddURLDialog = false
                    tempURLData = nil
                }
            }
#else
        editorContent
            .onChange(of: tempURLData != nil) { _, hasData in
                guard hasData, let (urlString, displayText) = tempURLData else { return }
                DispatchQueue.main.async {
                    insertURLTrigger = (UUID(), urlString, displayText)
                    showingAddURLDialog = false
                    tempURLData = nil
                }
            }
#endif
    }

    private var editorContent: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                        .background(
                            GeometryReader { geometry in
                                Color.clear.preference(key: HeaderHeightPreferenceKey.self, value: geometry.size.height)
                            }
                        )

                    RichTextEditor(
                        text: Binding(
                            get: { richText.value },
                            set: { newValue in
                                let snapshot = NSAttributedString(attributedString: newValue)
                                richText = AttributedTextWrapper(value: snapshot)
                            }
                        ),
                        activeColor: $activeColor,
                        activeFontSize: $activeFontSize,
                        isBold: $isBold,
                        isUnderlined: $isUnderlined,
                        isStrikethrough: $isStrikethrough,
                        insertUncheckedCheckboxTrigger: $insertUncheckedCheckboxTrigger,
                        insertCheckedCheckboxTrigger: $insertCheckedCheckboxTrigger,
                        insertBulletTrigger: $insertBulletTrigger,
                        insertNumberingTrigger: $insertNumberingTrigger,
                        insertURLTrigger: $insertURLTrigger
                    )
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: max(proxy.size.height - headerHeight - 12, 0))
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
            .scrollDismissesKeyboard(.interactively)
            .onPreferenceChange(HeaderHeightPreferenceKey.self) { headerHeight = $0 }
        }
#if !os(macOS)
        .sheet(isPresented: $showingCategoryPicker) {
            CategoryPickerView(selectedCategory: $item.category)
        }
#endif
        .onAppear {
            loadContentIfNeeded()
            if item.title.isEmpty && item.content.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isTitleFocused = true
                }
            }
        }
        .onChange(of: item.attributedContent) { _, _ in
            loadContentIfNeeded()
        }
        .onChange(of: richText) { _, wrapper in
            item.content = wrapper.value.string
            item.attributedContent = archiveAttributedString(wrapper.value)
            item.timestamp = Date()
            saveChanges()
        }
        .onChange(of: item.title) { _, _ in
            item.timestamp = Date()
            saveChanges()
        }
        .onDisappear {
            saveChanges()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ListToolbar(
                    insertUncheckedCheckboxTrigger: $insertUncheckedCheckboxTrigger,
                    insertCheckedCheckboxTrigger: $insertCheckedCheckboxTrigger,
                    insertBulletTrigger: $insertBulletTrigger,
                    insertNumberingTrigger: $insertNumberingTrigger,
                    showingAddURLDialog: $showingAddURLDialog,
                    tempURLData: $tempURLData
                )

                FontToolbar(
                    activeColor: $activeColor,
                    activeFontSize: $activeFontSize,
                    isBold: $isBold,
                    isUnderlined: $isUnderlined,
                    isStrikethrough: $isStrikethrough
                )
            }
            
            ToolbarItem(placement: .primaryAction) {

            }
            
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            TextField("Title", text: $item.title, axis: .vertical)
                .font(.title2.weight(.medium))
                .textFieldStyle(.plain)
                .focused($isTitleFocused)
                .onChange(of: isTitleFocused) { _, newValue in
                    if !newValue {
                        saveChanges()
                    }
                }

            Button(action: { showingCategoryPicker = true }) {
                HStack(spacing: 6) {
                    if let category = item.category {
                        Circle()
                            .fill(Color.fromString(category.color))
                            .frame(width: 12, height: 12)
                        Text(category.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Image(systemName: "folder")
                            .foregroundColor(.secondary)
                        Text("No Category")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(6)
#if os(macOS)
            .popover(
                isPresented: $showingCategoryPicker,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .bottom
            ) {
                CategoryPickerView(selectedCategory: $item.category)
                    .frame(width: 280, height: 320)
            }
#endif
        }
    }

    private func loadContentIfNeeded() {
        if let data = item.attributedContent, let attributed = unarchiveAttributedString(data) {
            if !attributed.isEqual(to: richText.value) {
                richText = AttributedTextWrapper(value: attributed)
            }
        } else if richText.value.string != item.content {
            richText = AttributedTextWrapper(value: NSAttributedString(string: item.content))
        }
    }

    private func archiveAttributedString(_ attributedString: NSAttributedString) -> Data? {
        // Preprocess: ensure all colors have color IDs stored for cross-platform sync
        let stringToArchive = ColorMapping.preprocessForArchiving(attributedString)

        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        archiver.encode(stringToArchive, forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()
        let data = archiver.encodedData
        return data
    }

    private func unarchiveAttributedString(_ data: Data) -> NSAttributedString? {
        do {
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
            unarchiver.requiresSecureCoding = true

            #if !os(macOS)
            // On iOS, map NSColor to UIColor so macOS colors work on iOS
            unarchiver.setClass(UIColor.self, forClassName: "NSColor")
            #endif

            // Register CheckboxTextAttachment so it can be decoded
            unarchiver.setClass(CheckboxTextAttachment.self, forClassName: "CheckboxTextAttachment")

            defer { unarchiver.finishDecoding() }
            var result = unarchiver.decodeObject(of: NSAttributedString.self, forKey: NSKeyedArchiveRootObjectKey)

            // Postprocess: restore colors from color IDs for cross-platform compatibility
            if let resultValue = result {
                result = ColorMapping.postprocessAfterUnarchiving(resultValue)
            }

            return result
        } catch {
            return nil
        }
    }

    private func saveChanges() {
        do {
            try modelContext.save()
        } catch {
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
