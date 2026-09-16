import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct NoteEditorView: View, Equatable {
    let item: Item
    // Keep identity outside SwiftData observation. Reading identity through the
    // model can subscribe this toolbar-owning view to metadata refreshes.
    let itemID: UUID
    #if os(macOS)
    @Binding var pastePlaintextTrigger: UUID?
    @Binding var isEditorActive: Bool
    @State private var isEditorExpanded = false
    #else
    @State private var pastePlaintextTrigger: UUID?
    @Binding var isEditorActive: Bool
    @Binding var isEditorExpanded: Bool
    #endif
    @Binding var passwordGeneratorTargetNoteID: UUID?
    var onCategoryAssignment: (Item, Category?) -> Void = { _, _ in }
    var onToggleEditorFocus: () -> Void = {}

    // Keep toolbar state above the document editor. Text changes then invalidate
    // only NoteEditorDocumentView instead of rebuilding the window toolbar.
    @State private var activeColor: RichTextColor = .automatic
    @State private var activeHighlighter: HighlighterColor = .none
    @State private var activeFontSize: FontSize = .normal
    @State private var isBold = false
    @State private var isItalic = false
    @State private var isUnderlined = false
    @State private var isStrikethrough = false
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
    @State private var tempURLData: (String, String)?
    @State private var showingAddURLDialog = false
    @State private var showingPasswordGenerator = false

    static func == (lhs: NoteEditorView, rhs: NoteEditorView) -> Bool {
        lhs.itemID == rhs.itemID
    }

    var body: some View {
        NoteEditorDocumentView(
            item: item,
            pastePlaintextTrigger: $pastePlaintextTrigger,
            passwordGeneratorTargetNoteID: $passwordGeneratorTargetNoteID,
            onCategoryAssignment: onCategoryAssignment,
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
            tempURLData: $tempURLData,
            showingAddURLDialog: $showingAddURLDialog,
            showingPasswordGenerator: $showingPasswordGenerator
        )
        .toolbar {
#if os(iOS)
            if UIDevice.current.userInterfaceIdiom == .pad {
                ToolbarItem(id: "noteEditor.focus", placement: .topBarTrailing) {
                    Button {
                        onToggleEditorFocus()
                    } label: {
                        Label(
                            isEditorExpanded ? "Show Note List" : "Focus Editor",
                            systemImage: isEditorExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
                        )
                    }
                }
            }
#endif

            ToolbarItem(id: "noteEditor.insert", placement: .primaryAction) {
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
            }

            ToolbarItem(id: "noteEditor.format", placement: .primaryAction) {
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
        }
    }
}

private struct NoteDocumentSnapshot: Equatable {
    let plainText: String
    let attributedContent: Data?
    let updatedAt: Date
}

// NoteEditorDocumentView must keep the metadata ModelContext for Item and
// TodoItem. This child reads the separate document container and forwards value
// snapshots, allowing CloudKit imports to refresh an already-mounted editor.
private struct NoteDocumentQueryBridge: View {
    @Query private var documents: [NoteDocument]
    let update: (NoteDocumentSnapshot) -> Void

    init(noteID: String, update: @escaping (NoteDocumentSnapshot) -> Void) {
        self.update = update
        _documents = Query(
            filter: #Predicate<NoteDocument> { document in
                document.noteID == noteID
            },
            sort: [SortDescriptor(\NoteDocument.updatedAt, order: .reverse)]
        )
    }

    private var snapshot: NoteDocumentSnapshot? {
        guard let document = documents.first else { return nil }
        return NoteDocumentSnapshot(
            plainText: document.plainText,
            attributedContent: document.attributedContent,
            updatedAt: document.updatedAt
        )
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                if let snapshot {
                    update(snapshot)
                }
            }
            .onChange(of: snapshot) { _, newSnapshot in
                if let newSnapshot {
                    update(newSnapshot)
                }
            }
    }
}

private struct NoteEditorDocumentView: View {
    @Bindable var item: Item
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var isTitleFocused: Bool
    @Binding var pastePlaintextTrigger: UUID?
    @Binding var passwordGeneratorTargetNoteID: UUID?
    var onCategoryAssignment: (Item, Category?) -> Void = { _, _ in }
    @State private var richText = AttributedTextWrapper(value: NSAttributedString(string: ""))
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
    @Binding var tempURLData: (String, String)?
    @Binding var showingAddURLDialog: Bool
    @Binding var showingPasswordGenerator: Bool
    @State private var draftTitle: String?
    @State private var headerHeight: CGFloat = 0
    @State private var lastSyncedRichText: NSAttributedString?
    @State private var skipNextAttributedContentChange = false
    @State private var isLoadingContent = false
    @State private var isApplyingTodoRendering = false
    @State private var pendingPersistenceWorkItem: DispatchWorkItem?
    @State private var pendingTodoSync = false
    @State private var lastObservedDocumentUpdate: Date?
    @State private var lastLocalDocumentUpdate: Date?
    @State private var externalContentUpdateToken: UUID?
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
            .onAppear {
                presentPasswordGeneratorIfNeeded()
            }
            .onChange(of: passwordGeneratorTargetNoteID) { _, _ in
                presentPasswordGeneratorIfNeeded()
            }
            .onChange(of: todoRenderSignature) { _, _ in
                applyTodoCompletionRenderingIfNeeded()
            }
            .background {
                NoteDocumentQueryBridge(
                    noteID: item.id.uuidString,
                    update: applyDocumentSnapshot
                )
                .modelContainer(JotableApp.sharedDocumentContainer)
            }
    }

    private func presentPasswordGeneratorIfNeeded() {
        guard passwordGeneratorTargetNoteID == item.id else { return }
        showingPasswordGenerator = true
        passwordGeneratorTargetNoteID = nil
    }

    private func createTodoFromSelection(_ request: TodoCreationRequest) {
        let todoText = normalizedTodoText(from: request.text)
        guard !todoText.isEmpty else { return }

        let todo = TodoItem(
            text: todoText,
            sourceText: request.text,
            sourceNote: item,
            sourceRangeLocation: request.selectedRangeLocation,
            sourceRangeLength: request.selectedRangeLength,
            sortOrder: nextTodoSortOrder()
        )
        modelContext.insert(todo)
        applyTodoMarker(todo, range: NSRange(location: request.selectedRangeLocation, length: request.selectedRangeLength))

        do {
            try modelContext.save()
            print("💾 Todo created from note selection - CloudKit sync queued")
        } catch {
            print("❌ Failed to create todo: \(error)")
        }
    }

    private func normalizedTodoText(from selectedText: String) -> String {
        selectedText
            .replacingOccurrences(of: "\u{FFFC}", with: "Image")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private var allTodos: [TodoItem] {
        var descriptor = FetchDescriptor<TodoItem>(
            sortBy: [SortDescriptor(\TodoItem.createdAt, order: .reverse)]
        )
        descriptor.includePendingChanges = true
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private var currentTodos: [TodoItem] {
        allTodos.filter { todo in
            todo.sourceNoteID == item.id.uuidString
        }
    }

    private func nextTodoSortOrder() -> Int {
        (allTodos.map(\.sortOrder).max() ?? 0) + 1
    }

    private var todoRenderSignature: String {
        return currentTodos
            .map { "\($0.id.uuidString):\($0.isCompleted):\($0.isSourceTextAvailable)" }
            .sorted()
            .joined(separator: "|")
    }

    private func applyTodoMarker(_ todo: TodoItem, range: NSRange) {
        let currentText = NSMutableAttributedString(attributedString: richText.value)
        guard range.location >= 0,
              range.length > 0,
              NSMaxRange(range) <= currentText.length else {
            return
        }

        currentText.addAttribute(TodoTextAttributes.todoIDKey, value: todo.id.uuidString, range: range)
        currentText.removeAttribute(TodoTextAttributes.completionRenderedKey, range: range)
        currentText.removeAttribute(TodoTextAttributes.originalStrikethroughStyleKey, range: range)
        pendingPersistenceWorkItem?.cancel()
        pendingPersistenceWorkItem = nil
        pendingTodoSync = false
        richText = AttributedTextWrapper(value: currentText)
        lastSyncedRichText = currentText
        persist(currentText)
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
                    scheduleRichTextStateSync(snapshot)
                } else if !newValue.isEqual(to: richText.value) {
                    // Even if string is the same, if attachments differ (e.g., checkbox state), update
                    let snapshot = NSAttributedString(attributedString: newValue)
                    scheduleRichTextStateSync(snapshot)
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
            pastePlaintextTrigger: $pastePlaintextTrigger,
            externalUpdateToken: externalContentUpdateToken,
            onAddSelectedTextToTodo: createTodoFromSelection
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
            linkEditRequest: $linkEditRequest,
            externalUpdateToken: externalContentUpdateToken,
            onAddSelectedTextToTodo: createTodoFromSelection
        )
        #endif
    }

    private var editorContent: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    NoteHeaderView(
                        item: item,
                        title: Binding(
                            get: { draftTitle ?? item.title },
                            set: { draftTitle = $0 }
                        ),
                        onCategoryAssignment: onCategoryAssignment,
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
            applyTodoCompletionRenderingIfNeeded()
            lastSyncedRichText = richText.value
            if item.title.isEmpty && richText.value.string.isEmpty {
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
            applyTodoCompletionRenderingIfNeeded()
        }
        .onChange(of: item.title) { _, newTitle in
            guard pendingPersistenceWorkItem == nil else { return }
            if draftTitle != newTitle {
                draftTitle = newTitle
            }
        }
        .onChange(of: draftTitle) { _, newTitle in
            guard let newTitle else { return }
            guard newTitle != item.title else { return }
            schedulePersistence(of: richText.value, syncTodos: false)
        }
        .onChange(of: richText) { _, newWrapper in
            if isLoadingContent {
                return
            }
            let shouldSyncTodos = !isApplyingTodoRendering
            isApplyingTodoRendering = false
            schedulePersistence(of: newWrapper.value, syncTodos: shouldSyncTodos)
        }
        .onDisappear {
            flushPendingPersistence()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                flushPendingPersistence()
            }
        }
    }


    private func loadContentIfNeeded() {
        let document = fetchNoteDocument()
        if let document {
            lastObservedDocumentUpdate = document.updatedAt
        }
        let attributedData = document?.attributedContent ?? item.attributedContent
        let plainText = document?.plainText ?? item.content

        if let data = attributedData, let attributed = unarchiveAttributedString(data) {
            if !attributed.isEqual(to: richText.value) {
                isLoadingContent = true
                richText = AttributedTextWrapper(value: attributed)
                DispatchQueue.main.async {
                    isLoadingContent = false
                }
            }
        } else if richText.value.string != plainText {
            isLoadingContent = true
            richText = AttributedTextWrapper(value: NSAttributedString(string: plainText))
            DispatchQueue.main.async {
                isLoadingContent = false
            }
        }
    }

    private func applyDocumentSnapshot(_ snapshot: NoteDocumentSnapshot) {
        guard snapshot.updatedAt != lastObservedDocumentUpdate else { return }
        lastObservedDocumentUpdate = snapshot.updatedAt

        // Query notifications also include this editor's own writes. They are
        // acknowledgements, not remote edits, and must not reset the selection.
        if snapshot.updatedAt == lastLocalDocumentUpdate {
            return
        }

        // Preserve an in-flight local keystroke. Its scheduled save is the
        // user's newest edit and will produce a subsequent document revision.
        guard pendingPersistenceWorkItem == nil else { return }

        let incoming: NSAttributedString
        if let data = snapshot.attributedContent,
           let attributed = unarchiveAttributedString(data) {
            incoming = attributed
        } else {
            incoming = NSAttributedString(string: snapshot.plainText)
        }

        guard !incoming.isEqual(to: richText.value) else {
            lastSyncedRichText = incoming
            return
        }

        isLoadingContent = true
        externalContentUpdateToken = UUID()
        richText = AttributedTextWrapper(value: incoming)
        lastSyncedRichText = incoming
        DispatchQueue.main.async {
            isLoadingContent = false
            applyTodoCompletionRenderingIfNeeded()
        }
    }

    private func scheduleRichTextStateSync(_ snapshot: NSAttributedString) {
        DispatchQueue.main.async {
            richText = AttributedTextWrapper(value: snapshot)
            lastSyncedRichText = snapshot
        }
    }

    private func schedulePersistence(of attributedString: NSAttributedString, syncTodos: Bool) {
        pendingPersistenceWorkItem?.cancel()
        pendingTodoSync = pendingTodoSync || syncTodos

        let snapshot = NSAttributedString(attributedString: attributedString)
        let workItem = DispatchWorkItem {
            persist(snapshot)
        }
        pendingPersistenceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func flushPendingPersistence() {
        guard pendingPersistenceWorkItem != nil else {
            saveChanges()
            return
        }

        pendingPersistenceWorkItem?.cancel()
        pendingPersistenceWorkItem = nil
        persist(richText.value)
    }

    private func persist(_ attributedString: NSAttributedString) {
        let document = noteDocumentForEditing()
        let archivedContent = archiveAttributedString(attributedString)
        let now = Date()
        var metadataChanged = false
        var persistenceTransaction = Transaction(animation: nil)
        persistenceTransaction.disablesAnimations = true
        withTransaction(persistenceTransaction) {
            if pendingTodoSync {
                syncTodosFromAttributedText(attributedString)
                pendingTodoSync = false
            }

            if let draftTitle {
                if item.title != draftTitle {
                    item.title = draftTitle
                    item.timestamp = now
                    metadataChanged = true
                }
            }
            document.plainText = attributedString.string
            document.attributedContent = archivedContent
            document.updatedAt = now
            lastLocalDocumentUpdate = now
            lastObservedDocumentUpdate = now
            pendingPersistenceWorkItem = nil
            saveDocumentChanges()
            if metadataChanged {
                saveChanges()
            }
        }

    }

    private func fetchNoteDocument() -> NoteDocument? {
        let noteID = item.id.uuidString
        var descriptor = FetchDescriptor<NoteDocument>(
            predicate: #Predicate { document in
                document.noteID == noteID
            },
            sortBy: [SortDescriptor(\NoteDocument.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? JotableApp.sharedDocumentContainer.mainContext.fetch(descriptor).first
    }

    private func noteDocumentForEditing() -> NoteDocument {
        if let document = fetchNoteDocument() {
            return document
        }

        let document = NoteDocument(
            noteID: item.id.uuidString,
            plainText: item.content,
            attributedContent: item.attributedContent,
            updatedAt: item.timestamp
        )
        JotableApp.sharedDocumentContainer.mainContext.insert(document)
        return document
    }

    private func saveDocumentChanges() {
        do {
            try JotableApp.sharedDocumentContainer.mainContext.save()
        } catch {
            print("❌ Failed to save note document: \(error.localizedDescription)")
        }
    }

    private struct TodoSourceSnapshot {
        var text: String
        var location: Int
        var length: Int
    }

    private func todoSourceSnapshots(in attributedString: NSAttributedString) -> [String: TodoSourceSnapshot] {
        var fragmentsByID: [String: [(range: NSRange, text: String)]] = [:]
        let fullRange = NSRange(location: 0, length: attributedString.length)

        attributedString.enumerateAttribute(TodoTextAttributes.todoIDKey, in: fullRange, options: []) { value, range, _ in
            guard let todoID = value as? String,
                  !todoID.isEmpty,
                  range.length > 0 else {
                return
            }

            let text = attributedString.attributedSubstring(from: range).string
            fragmentsByID[todoID, default: []].append((range, text))
        }

        return fragmentsByID.reduce(into: [:]) { result, entry in
            let fragments = entry.value.sorted { $0.range.location < $1.range.location }
            guard let firstRange = fragments.first?.range,
                  let lastRange = fragments.last?.range else {
                return
            }

            let text = fragments.map(\.text).joined()
            result[entry.key] = TodoSourceSnapshot(
                text: text,
                location: firstRange.location,
                length: NSMaxRange(lastRange) - firstRange.location
            )
        }
    }

    private func syncTodosFromAttributedText(_ attributedString: NSAttributedString) {
        let snapshots = todoSourceSnapshots(in: attributedString)
        var hasChanges = false

        for todo in currentTodos {
            if let snapshot = snapshots[todo.id.uuidString] {
                let todoText = normalizedTodoText(from: snapshot.text)
                guard !todoText.isEmpty else {
                    if todo.isSourceTextAvailable {
                        todo.isSourceTextAvailable = false
                        todo.sourceRangeLength = 0
                        todo.updatedAt = Date()
                        hasChanges = true
                    }
                    continue
                }

                if todo.text != todoText ||
                    todo.sourceText != snapshot.text ||
                    todo.sourceRangeLocation != snapshot.location ||
                    todo.sourceRangeLength != snapshot.length ||
                    !todo.isSourceTextAvailable ||
                    todo.sourceNoteTitleSnapshot != item.title ||
                    todo.sourceCategoryNameSnapshot != (item.category?.name ?? "") {
                    todo.text = todoText
                    todo.sourceText = snapshot.text
                    todo.sourceRangeLocation = snapshot.location
                    todo.sourceRangeLength = snapshot.length
                    todo.isSourceTextAvailable = true
                    todo.sourceNoteTitleSnapshot = item.title
                    todo.sourceCategoryNameSnapshot = item.category?.name ?? ""
                    todo.updatedAt = Date()
                    hasChanges = true
                }
            } else if todo.isSourceTextAvailable {
                todo.isSourceTextAvailable = false
                todo.sourceRangeLength = 0
                todo.updatedAt = Date()
                hasChanges = true
            }
        }

        if hasChanges {
            saveChanges()
        }
    }

    private func applyTodoCompletionRenderingIfNeeded() {
        guard !isLoadingContent else {
            DispatchQueue.main.async {
                applyTodoCompletionRenderingIfNeeded()
            }
            return
        }

        let completionByID = Dictionary(uniqueKeysWithValues: currentTodos.map { ($0.id.uuidString, $0.isCompleted) })
        guard !completionByID.isEmpty, richText.value.length > 0 else { return }

        let rendered = NSMutableAttributedString(attributedString: richText.value)
        var changed = false
        let fullRange = NSRange(location: 0, length: rendered.length)

        var markedRanges: [(todoID: String, range: NSRange)] = []
        richText.value.enumerateAttribute(TodoTextAttributes.todoIDKey, in: fullRange, options: []) { value, range, _ in
            guard let todoID = value as? String,
                  range.length > 0 else {
                return
            }

            markedRanges.append((todoID, range))
        }

        for markedRange in markedRanges {
            guard let isCompleted = completionByID[markedRange.todoID] else { continue }
            let range = markedRange.range

            if isCompleted {
                let isRendered = (rendered.attribute(TodoTextAttributes.completionRenderedKey, at: range.location, effectiveRange: nil) as? NSNumber)?.boolValue ?? false
                if !isRendered {
                    if let existingStyle = rendered.attribute(.strikethroughStyle, at: range.location, effectiveRange: nil) as? NSNumber {
                        rendered.addAttribute(TodoTextAttributes.originalStrikethroughStyleKey, value: existingStyle, range: range)
                    }
                    rendered.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                    rendered.addAttribute(TodoTextAttributes.completionRenderedKey, value: NSNumber(value: true), range: range)
                    changed = true
                }
            } else {
                let isRendered = (rendered.attribute(TodoTextAttributes.completionRenderedKey, at: range.location, effectiveRange: nil) as? NSNumber)?.boolValue ?? false
                guard isRendered else { continue }

                if let originalStyle = rendered.attribute(TodoTextAttributes.originalStrikethroughStyleKey, at: range.location, effectiveRange: nil) {
                    rendered.addAttribute(.strikethroughStyle, value: originalStyle, range: range)
                } else {
                    rendered.removeAttribute(.strikethroughStyle, range: range)
                }
                rendered.removeAttribute(TodoTextAttributes.completionRenderedKey, range: range)
                rendered.removeAttribute(TodoTextAttributes.originalStrikethroughStyleKey, range: range)
                changed = true
            }
        }

        guard changed else { return }
        isApplyingTodoRendering = true
        richText = AttributedTextWrapper(value: rendered)
        lastSyncedRichText = rendered
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
    let item: Item
    @Binding var title: String
    @State private var showingCategoryPicker = false
    @State private var headerHeight: CGFloat = 0

    var onCategoryAssignment: (Item, Category?) -> Void
    var onHeaderHeightChange: (CGFloat) -> Void

    init(
        item: Item,
        title: Binding<String>,
        onCategoryAssignment: @escaping (Item, Category?) -> Void,
        onHeaderHeightChange: @escaping (CGFloat) -> Void
    ) {
        self.item = item
        self._title = title
        self.onCategoryAssignment = onCategoryAssignment
        self.onHeaderHeightChange = onHeaderHeightChange
    }

    private var categorySelectionBinding: Binding<Category?> {
        Binding(
            get: { item.category },
            set: { newCategory in
                onCategoryAssignment(item, newCategory)
                item.category = newCategory

                if item.isInTrash {
                    item.previousCategory = nil
                    item.trashedAt = nil
                    item.timestamp = Date()
                }
            }
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            TextField("Note Title", text: $title)
                .font(.title2.weight(.medium))
                .textFieldStyle(.plain)
                //.lineLimit(2)

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
            .categoryPickerPresenter(isPresented: $showingCategoryPicker, selectedCategory: categorySelectionBinding)
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
    func addURLSheet(isPresented _: Binding<Bool>, tempURLData _: Binding<(String, String)?>) -> some View {
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
