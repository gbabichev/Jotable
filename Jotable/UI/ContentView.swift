//
//  ContentView.swift
//  SimpleNote
//

import SwiftUI
import SwiftData
import CoreData
import LocalAuthentication
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

// Selection type for the sidebar
enum SidebarSelection: Hashable {
    case allNotes
    case todoList
    case trash
    case category(Category)
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    // Changed from timestamp to createdAt for stable sorting based on creation date
    @Query(sort: \Item.createdAt, order: .reverse) private var allItems: [Item]
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query(sort: \TodoItem.createdAt, order: .reverse) private var allTodos: [TodoItem]
    @AppStorage("lastSelectedNoteID") private var lastSelectedNoteID: String = ""

    #if os(macOS)
    @Binding var pastePlaintextTrigger: UUID?
    #endif
    @Binding var isEditorExpanded: Bool
    @Binding var isEditorActive: Bool

    @State private var selectedItemIDs: Set<PersistentIdentifier> = []
    @State private var categoryAssignmentPreservedSelectionID: PersistentIdentifier?
    #if os(iOS)
    @State private var splitViewVisibility: NavigationSplitViewVisibility = UIDevice.current.userInterfaceIdiom == .pad ? .all : .automatic
    #else
    @State private var splitViewVisibility: NavigationSplitViewVisibility = .automatic
    #endif
    @State private var sidebarSelection: SidebarSelection? = .allNotes
    @State private var showingAddCategory = false
    @State private var showingAddTodo = false
    @State private var categoryToEdit: Category?
    @State private var searchText = ""
    @State private var authenticatingCategoryID: PersistentIdentifier?
    @State private var isRevertingSelection = false
    @State private var isAuthenticatedForPrivateAccess = false
    @State private var lastAuthenticationTime: Date?
    @State private var hasShownNoAuthWarning = false
    @State private var showAuthError = false
    @State private var authErrorMessage = ""
    @State private var showingCategoryPickerForItem: Item?
    @State private var activeCloudSyncEventIDs: Set<UUID> = []
    @State private var cloudKitEventObserver: NSObjectProtocol?
    @State private var isCloudSyncIndicatorVisible = false
    @State private var cloudSyncHideWorkItem: DispatchWorkItem?
    @State private var passwordGeneratorTargetNoteID: UUID?
    @State private var showingExternalPasswordGenerator = false
    #if os(macOS)
    @State private var isExporting = false
    @State private var exportDocument = NotesExportDocument(data: Data())
    @State private var showExportAlert = false
    @State private var exportError: String?
    @State private var isImporting = false
    @State private var importError: String?
    @State private var importResultMessage: String?
    #endif
    #if os(iOS)
    @State private var editMode: EditMode = .inactive
    @State private var todoSourceNavigationPath: [UUID] = []
    #endif
    private var isEditing: Bool {
        #if os(iOS)
        return editMode.isEditing
        #else
        return false
        #endif
    }

    // Authentication timeout: 5 minutes
    private let authenticationTimeoutInterval: TimeInterval = 5 * 60

    // Check if authentication is still valid
    private var isAuthenticationValid: Bool {
        guard isAuthenticatedForPrivateAccess,
              let lastAuthTime = lastAuthenticationTime else {
            return false
        }
        return Date().timeIntervalSince(lastAuthTime) < authenticationTimeoutInterval
    }

    // Computed property to get the selected category for filtering
    private var selectedCategory: Category? {
        switch sidebarSelection {
        case .allNotes, .todoList, .trash, .none:
            return nil
        case .category(let category):
            return category
        }
    }

    private var visibleCategories: [Category] {
        categories.filter { !$0.isSystemTrash }
    }

    private var isViewingTrash: Bool {
        if case .trash = sidebarSelection {
            return true
        }
        return false
    }

    private var isViewingTodoList: Bool {
        if case .todoList = sidebarSelection {
            return true
        }
        return false
    }

    private var visibleTodos: [TodoItem] {
        allTodos.filter { todo in
            if let linkedNote = linkedSourceNote(for: todo) {
                guard !linkedNote.isInTrash else { return false }

                guard let category = linkedNote.category else { return true }
                return !category.isPrivate && !category.isHiddenFromHome
            }

            return true
        }
    }

    private var openTodoCount: Int {
        visibleTodos.filter { !$0.isCompleted }.count
    }

    private var filteredTodos: [TodoItem] {
        var todos = visibleTodos

        if !searchText.isEmpty {
            todos = todos.filter { todo in
                todo.text.localizedCaseInsensitiveContains(searchText) ||
                sourceTitle(for: todo).localizedCaseInsensitiveContains(searchText) ||
                sourceCategoryName(for: todo)?.localizedCaseInsensitiveContains(searchText) == true
            }
        }

        return todos.sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted {
                return !lhs.isCompleted
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private var trashItemCount: Int {
        allItems.filter { $0.isInTrash }.count
    }

    private var trashItems: [Item] {
        allItems.filter { $0.isInTrash }
    }

    private var currentNavigationTitle: String {
        switch sidebarSelection {
        case .todoList:
            return "Todo List"
        case .trash:
            return Category.trashName
        case .category(let category):
            return category.name
        case .allNotes, .none:
            return "All Notes"
        }
    }

    // Filtered items based on selected category and search
    var filteredItems: [Item] {
        var items = allItems

        // Get locked/hidden category IDs for filtering
        let lockedCategoryIDs = Set(visibleCategories.filter { $0.isPrivate }.compactMap { $0.id })
        let hiddenCategoryIDs = Set(visibleCategories.filter { $0.isHiddenFromHome }.compactMap { $0.id })

        if isViewingTrash {
            items = items.filter { $0.isInTrash }
        } else {
            items = items.filter { !$0.isInTrash }

            // When a category is explicitly selected, keep search scoped to that category.
            if let selectedCategory = selectedCategory {
                items = items.filter { $0.category == selectedCategory }
            } else {
                // In All Notes, hide notes from locked/hidden categories.
                items = items.filter { item in
                    guard let category = item.category else { return true }
                    return !lockedCategoryIDs.contains(category.id) &&
                        !hiddenCategoryIDs.contains(category.id)
                }
            }
        }

        // Filter by search text
        if !searchText.isEmpty {
            items = items.filter { item in
                item.title.localizedCaseInsensitiveContains(searchText) ||
                item.content.localizedCaseInsensitiveContains(searchText)
            }
        }

        return items
    }

    // Count of notes visible without authenticating into locked categories
    private var unlockedNoteCount: Int {
        let lockedCategoryIDs = Set(visibleCategories.filter { $0.isPrivate }.compactMap { $0.id })
        let hiddenCategoryIDs = Set(visibleCategories.filter { $0.isHiddenFromHome }.compactMap { $0.id })
        return allItems.filter { item in
            guard !item.isInTrash else { return false }
            guard let category = item.category else { return true }
            return !lockedCategoryIDs.contains(category.id) &&
                !hiddenCategoryIDs.contains(category.id)
        }.count
    }
    
    private var primarySelectedItem: Item? {
        #if os(iOS)
        guard !isEditing, selectedItemIDs.count == 1, let selectedID = selectedItemIDs.first else { return nil }
        #else
        guard selectedItemIDs.count == 1, let selectedID = selectedItemIDs.first else { return nil }
        #endif
        if isViewingTodoList {
            return allItems.first { $0.persistentModelID == selectedID && !$0.isInTrash }
        }

        if let visibleItem = filteredItems.first(where: { $0.persistentModelID == selectedID }) {
            return visibleItem
        }

        guard categoryAssignmentPreservedSelectionID == selectedID else { return nil }
        return allItems.first { $0.persistentModelID == selectedID && !$0.isInTrash }
    }

    private var listSelectionBinding: Binding<Set<PersistentIdentifier>> { $selectedItemIDs }

    private var canExpandEditor: Bool {
        #if os(macOS)
        return true
        #elseif os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad
        #else
        return false
        #endif
    }

    private var shouldUseExpandedEditorLayout: Bool {
        canExpandEditor && isEditorExpanded
    }

    #if os(iOS)
    private var shouldPushTodoSourceInTodoList: Bool {
        horizontalSizeClass == .compact || UIDevice.current.userInterfaceIdiom == .phone
    }

    private var addTodoSheetHeight: CGFloat {
        260
    }
    #endif

    private var notesListMinimumColumnWidth: CGFloat {
        switch splitViewVisibility {
        case .doubleColumn, .detailOnly:
            return 450
        default:
            return 250
        }
    }

    private var notesListIdealColumnWidth: CGFloat {
        return max(250, notesListMinimumColumnWidth)
    }

    @ViewBuilder
    private var navigationContent: some View {
        if shouldUseExpandedEditorLayout {
            detailColumn
        } else {
            standardNavigationSplitView
        }
    }

    private var standardNavigationSplitView: some View {
        NavigationSplitView(columnVisibility: $splitViewVisibility) {
            sidebarColumn
        } content: {
            if isViewingTodoList {
                todoListColumn
            } else {
                notesListColumn
            }
        } detail: {
            detailColumn
        }
    }

    private var sidebarColumn: some View {
        List(selection: $sidebarSelection) {
            sidebarContent
        }
        .listStyle(SidebarListStyle())
        .navigationTitle("Jotable")
        .onChange(of: selectedItemIDs) { _, _ in
            if let preservedID = categoryAssignmentPreservedSelectionID,
               !selectedItemIDs.contains(preservedID) {
                if selectedItemIDs.isEmpty,
                   allItems.contains(where: { $0.persistentModelID == preservedID && !$0.isInTrash }) {
                    selectedItemIDs = [preservedID]
                    return
                }

                categoryAssignmentPreservedSelectionID = nil
            }

            let newSelectedItem = primarySelectedItem
            // Manage isEditorActive based on whether a single note is selected
            isEditorActive = newSelectedItem != nil
            #if os(macOS) || os(iOS)
            if newSelectedItem == nil {
                setEditorExpanded(false)
            }
            #endif
            if let id = newSelectedItem?.id {
                lastSelectedNoteID = id.uuidString
            } else {
                lastSelectedNoteID = ""
            }
        }
        .onChange(of: sidebarSelection) { oldValue, newValue in
            #if os(iOS)
            switch newValue {
            case .todoList:
                break
            default:
                todoSourceNavigationPath.removeAll()
            }
            #endif

            // Check if the newly selected item is a locked category
            if case .category(let category) = newValue, category.isPrivate {
                // If we're reverting to a previous selection, skip authentication
                if isRevertingSelection {
                    isRevertingSelection = false
                    return
                }

                // If we just authenticated for this category, allow the selection
                if authenticatingCategoryID == category.id {
                    authenticatingCategoryID = nil
                    return
                }

                // If already authenticated and within timeout period, allow navigation
                if isAuthenticationValid {
                    return
                }

                // Authentication expired or not authenticated - clear state and require auth
                isAuthenticatedForPrivateAccess = false
                lastAuthenticationTime = nil

                // Revert selection while we authenticate
                isRevertingSelection = true
                sidebarSelection = oldValue
                authenticatingCategoryID = category.id
                let categoryID = category.id

                // Authenticate
                authenticateWithBiometrics(reason: "Authenticate to access private categories") { success in
                    DispatchQueue.main.async {
                        if success {
                            // Mark as authenticated for private access and record time
                            self.isAuthenticatedForPrivateAccess = true
                            self.lastAuthenticationTime = Date()
                            self.authenticatingCategoryID = categoryID
                            self.sidebarSelection = newValue
                        } else {
                            self.authenticatingCategoryID = nil
                            self.isRevertingSelection = false
                        }
                    }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction)
            {
                Button(action: { showingAddCategory = true }) {
                    Image(systemName: "folder.badge.plus")
                }
                #if DEBUG
                Menu {
                    Button {
                        createFormattingTestNote()
                    } label: {
                        Label("Formatting Test Note", systemImage: "textformat")
                    }

                    Divider()

                    Button(role: .destructive, action: deleteEverything) {
                        Label("Delete Everything", systemImage: "trash.fill")
                    }
                } label: {
                    Label("Debug", systemImage: "ladybug")
                }
                #endif
            }
        }
        .sheet(isPresented: $showingAddCategory) {
            AddCategoryView()
        }
        .sheet(item: $categoryToEdit) { category in
            AddCategoryView(categoryToEdit: category)
        }
    }

    private var notesListColumn: some View {
        List(selection: listSelectionBinding) {
            notesListContent
        }
        .searchable(
            text: $searchText,
            prompt: "Search notes"
        )
        .navigationTitle(currentNavigationTitle)
        .navigationSubtitle("\(filteredItems.count) \(filteredItems.count == 1 ? "note" : "notes")")
        .navigationSplitViewColumnWidth(min: notesListMinimumColumnWidth, ideal: notesListIdealColumnWidth, max: 800)
        .toolbar {
            #if !os(macOS)
            if isCloudSyncIndicatorVisible {
                ToolbarItem(placement: .automatic) {
                    CloudSyncToolbarIndicator()
                }
            }
            #endif

            #if os(iOS)
            NotesToolbar(
                isEditing: isEditing,
                filteredItems: filteredItems,
                selectedItemIDs: selectedItemIDs,
                allItemsIsEmpty: allItems.isEmpty,
                allFilteredItemsSelected: allFilteredItemsSelected,
                deleteSelectedLabel: isViewingTrash ? "Delete Forever" : "Trash Selected",
                deleteSelectedSystemImage: isViewingTrash ? "trash.slash" : "trash",
                deleteSelectedItems: deleteSelectedItems,
                addItem: addItem,
                selectAllItems: selectAllItems,
                deselectAllItems: deselectAllItems
            )
            #else
            NotesToolbar(
                isEditing: isEditing,
                filteredItems: filteredItems,
                selectedItemIDs: selectedItemIDs,
                deleteSelectedLabel: isViewingTrash ? "Delete Forever" : "Trash Selected",
                deleteSelectedSystemImage: isViewingTrash ? "trash.slash" : "trash",
                deleteSelectedItems: deleteSelectedItems,
                addItem: addItem
            )
            #endif
        }
        #if os(iOS)
        .environment(\.editMode, $editMode)
        #endif
    }

    @ViewBuilder
    private var todoListColumn: some View {
        #if os(iOS)
        if shouldPushTodoSourceInTodoList {
            NavigationStack(path: $todoSourceNavigationPath) {
                todoListColumnContent
                    .navigationDestination(for: UUID.self) { noteID in
                        todoSourceDestination(for: noteID)
                    }
            }
        } else {
            todoListColumnContent
        }
        #else
        todoListColumnContent
        #endif
    }

    private var todoListColumnContent: some View {
        todoListBody
        .searchable(
            text: $searchText,
            prompt: "Search todos"
        )
        .navigationTitle("Todo List")
        .navigationSubtitle("\(openTodoCount) \(openTodoCount == 1 ? "open todo" : "open todos")")
        .navigationSplitViewColumnWidth(min: notesListMinimumColumnWidth, ideal: notesListIdealColumnWidth, max: 800)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showingAddTodo = true
                } label: {
                    Label("New Todo", systemImage: "plus")
                }

                if isCloudSyncIndicatorVisible {
                    CloudSyncToolbarIndicator()
                }
            }
        }
    }

    @ViewBuilder
    private var todoListBody: some View {
        if filteredTodos.isEmpty {
            ScrollView {
                todoEmptyState
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 360)
            }
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif
        } else {
            List {
                todoListContent
            }
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif
        }
    }

    private var todoEmptyState: some View {
        ContentUnavailableView {
            Label("No Todos", systemImage: "checklist")
        } description: {
            Text(searchText.isEmpty ? "No todo items yet." : "No matching todos.")
        }
    }

    #if os(iOS)
    @ViewBuilder
    private func todoSourceDestination(for noteID: UUID) -> some View {
        if let note = allItems.first(where: { $0.id == noteID && !$0.isInTrash }) {
            NoteEditorView(
                item: note,
                isEditorActive: $isEditorActive,
                isEditorExpanded: $isEditorExpanded,
                passwordGeneratorTargetNoteID: $passwordGeneratorTargetNoteID,
                onCategoryAssignment: prepareSelectionForCategoryAssignment,
                onToggleEditorFocus: {
                    setEditorExpanded(!isEditorExpanded)
                }
            )
            .id(note.id)
        } else {
            ContentUnavailableView {
                Label("Note Unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text("The source note for this todo could not be opened.")
            }
        }
    }
    #endif

    private var detailColumn: some View {
        NavigationStack {
            if let selectedItem = primarySelectedItem {
                #if os(macOS)
                NoteEditorView(
                    item: selectedItem,
                    pastePlaintextTrigger: $pastePlaintextTrigger,
                    isEditorActive: $isEditorActive,
                    passwordGeneratorTargetNoteID: $passwordGeneratorTargetNoteID,
                    onCategoryAssignment: prepareSelectionForCategoryAssignment
                )
                    .id(selectedItem.id) // Force view recreation when switching notes
                #else
                NoteEditorView(
                    item: selectedItem,
                    isEditorActive: $isEditorActive,
                    isEditorExpanded: $isEditorExpanded,
                    passwordGeneratorTargetNoteID: $passwordGeneratorTargetNoteID,
                    onCategoryAssignment: prepareSelectionForCategoryAssignment,
                    onToggleEditorFocus: {
                        setEditorExpanded(!isEditorExpanded)
                    }
                )
                    .id(selectedItem.id) // Force view recreation when switching notes
                #endif
            } else {
                ContentUnavailableView {
                    Label("Select a Note", systemImage: "note.text")
                } description: {
                    Text("Choose a note from the sidebar to view and edit it, or create a new note.")
                } actions: {
                    Button("New Note", action: addItem)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
    
    var body: some View {
        navigationContent
#if DEBUG
        .overlay(alignment: .bottomTrailing) {
            BetaTag()
                .padding(12)
        }
#endif
        #if os(macOS)
        .overlay(alignment: .bottomLeading) {
            if isCloudSyncIndicatorVisible {
                CloudSyncToolbarIndicator()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(16)
                    .transition(.opacity)
            }
        }
        #endif
        .onAppear {
            cleanupLegacyTrashCategories()
            purgeExpiredTrash()
            setupCloudKitNotifications()
            restoreLastSelectedNoteIfNeeded()
            disableFocusModeIfEditorIsEmpty()
            DispatchQueue.main.async {
                disableFocusModeIfEditorIsEmpty()
            }
        }
        .onDisappear {
            tearDownCloudKitNotifications()
        }
        .onReceive(NotificationCenter.default.publisher(for: .createNewNoteRequested)) { _ in
            handleExternalNewNoteRequest()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openPasswordGeneratorRequested)) { _ in
            handleExternalPasswordGeneratorRequest()
        }
        .sheet(isPresented: $showingExternalPasswordGenerator) {
            PasswordGeneratorView { password in
                insertPasswordIntoNewNote(password)
                showingExternalPasswordGenerator = false
            }
        }
        .sheet(isPresented: $showingAddTodo) {
            AddTodoView { text in
                createStandaloneTodo(from: text)
            }
            #if os(iOS)
            .presentationCompactAdaptation(.sheet)
            .presentationDetents([.height(addTodoSheetHeight)])
            .presentationDragIndicator(.visible)
            #endif
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: .toggleEditorFocusRequested)) { _ in
            setEditorExpanded(!isEditorExpanded)
        }
        .toolbar {
            if canExpandEditor {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        setEditorExpanded(!isEditorExpanded)
                    } label: {
                        Label(
                            isEditorExpanded ? "Show Note List" : "Focus Editor",
                            systemImage: isEditorExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
                        )
                    }
                    .disabled(primarySelectedItem == nil)
                    .help(isEditorExpanded ? "Show the note list" : "Hide the note list and focus the editor")
                }
            }
        }
        .onChange(of: isEditorExpanded) { _, expanded in
            setEditorExpanded(expanded)
        }
        #endif
        #if os(iOS)
        .onChange(of: isEditorExpanded) { _, expanded in
            setEditorExpanded(expanded)
        }
        #endif
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: .exportNotesRequested)) { _ in
            showExportAlert = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .importNotesRequested)) { _ in
            isImporting = true
        }
        #endif
        .onChange(of: allItems) { _, _ in
            // Trim selection to still-present items
            selectedItemIDs = Set(selectedItemIDs.filter { id in
                allItems.contains(where: { $0.persistentModelID == id })
            })

            #if os(iOS)
            if allItems.isEmpty {
                editMode = .inactive
            }
            #endif

            // If no selection (e.g., after app relaunch) try to restore it
            if primarySelectedItem == nil {
                restoreLastSelectedNoteIfNeeded()
            }
            disableFocusModeIfEditorIsEmpty()
        }
        .onChange(of: filteredItems) { _, _ in
            if isViewingTodoList {
                disableFocusModeIfEditorIsEmpty()
                return
            }

            let visibleIDs = Set(filteredItems.map(\.persistentModelID))

            // Trim selection to visible list items, except for the note just moved
            // into a hidden/private category while it is open in the editor.
            selectedItemIDs = Set(selectedItemIDs.filter { id in
                if visibleIDs.contains(id) {
                    return true
                }

                guard id == categoryAssignmentPreservedSelectionID,
                      let item = allItems.first(where: { $0.persistentModelID == id }) else {
                    return false
                }
                return !item.isInTrash
            })

            if let preservedID = categoryAssignmentPreservedSelectionID,
               visibleIDs.contains(preservedID) {
                categoryAssignmentPreservedSelectionID = nil
            }
            disableFocusModeIfEditorIsEmpty()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // When app becomes active, check if authentication has expired
            if newPhase == .active {
                cleanupLegacyTrashCategories()
                purgeExpiredTrash()
                if !isAuthenticationValid {
                    // Authentication expired - clear it and revert to All Notes if viewing private category
                    isAuthenticatedForPrivateAccess = false
                    lastAuthenticationTime = nil

                    if case .category(let category) = sidebarSelection, category.isPrivate {
                        sidebarSelection = .allNotes
                        selectedItemIDs.removeAll()
                    }
                }
            }
        }
        #if os(iOS)
        .onChange(of: isEditing) { _, editing in
            if !editing {
                selectedItemIDs.removeAll()
            }
        }
        #endif
        .alert("Authentication", isPresented: $showAuthError) {
            Button("OK") {
                showAuthError = false
            }
        } message: {
            Text(authErrorMessage)
        }
        #if os(macOS)
        .macImportExportPresentation(
            showExportAlert: $showExportAlert,
            isExporting: $isExporting,
            exportDocument: exportDocument,
            exportError: $exportError,
            isImporting: $isImporting,
            importError: $importError,
            importResultMessage: $importResultMessage,
            startExport: startExport,
            handleImport: handleImport
        )
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        #endif
    }

    #if os(macOS) || os(iOS)
    private func disableFocusModeIfEditorIsEmpty() {
        guard isEditorExpanded, primarySelectedItem == nil else {
            return
        }

        isEditorExpanded = false
    }

    private func setEditorExpanded(_ expanded: Bool) {
        if expanded && (!canExpandEditor || primarySelectedItem == nil) {
            isEditorExpanded = false
            return
        }

        guard expanded != isEditorExpanded else {
            return
        }

        if expanded {
            withAnimation(.easeInOut(duration: 0.2)) {
                isEditorExpanded = true
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                isEditorExpanded = false
            }
        }
    }
    #endif
    
    // Shared sidebar content
    @ViewBuilder
    private var sidebarContent: some View {
        // All Notes section
        Section("All Notes") {
            CategoryRowView(
                icon: "note.text",
                title: "All Notes",
                count: unlockedNoteCount,
                color: nil,
                isPrivate: false,
                isHiddenFromHome: false
            )
            .tag(SidebarSelection.allNotes)

            CategoryRowView(
                icon: "checklist",
                title: "Todo List",
                count: openTodoCount,
                color: nil,
                isPrivate: false,
                isHiddenFromHome: false
            )
            .tag(SidebarSelection.todoList)

            CategoryRowView(
                icon: "trash",
                title: Category.trashName,
                count: trashItemCount,
                color: nil,
                isPrivate: false,
                isHiddenFromHome: false
            )
            .tag(SidebarSelection.trash)
            .contextMenu {
                Button(role: .destructive) {
                    emptyTrash()
                } label: {
                    Label("Empty Trash", systemImage: "trash.slash")
                }
                .disabled(trashItems.isEmpty)
            }
        }
        
        // Categories section
        Section("Categories") {
            ForEach(visibleCategories) { category in
                CategoryRowView(
                    icon: nil,
                    title: category.name,
                    count: category.notes?.count ?? 0,
                    color: category.color,
                    isPrivate: category.isPrivate,
                    isHiddenFromHome: category.isHiddenFromHome
                )
                .tag(SidebarSelection.category(category))
                .contextMenu {
                    Button {
                        beginEditing(category)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }

                    Divider()

                    Button {
                        togglePrivacy(for: category)
                    } label: {
                        let biometricUI = biometricToggleUI
                        Label(
                            category.isPrivate ? biometricUI.disableTitle : biometricUI.enableTitle,
                            systemImage: category.isPrivate ? biometricUI.disableIcon : biometricUI.enableIcon
                        )
                    }

                    Button {
                        toggleHiddenFromHome(for: category)
                    } label: {
                        Label(
                            category.isHiddenFromHome ? "Show in Home" : "Hide from Home",
                            systemImage: category.isHiddenFromHome ? "eye" : "eye.slash"
                        )
                    }

                    Button(role: .destructive) {
                        deleteCategory(category)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .onMove(perform: moveCategories)
            .onDelete(perform: deleteCategories)
        }
        
    }
    
    // Shared notes list content with drag-to-reorder support
    @ViewBuilder
    private var notesListContent: some View {
        ForEach(filteredItems) { item in
            NoteRowView(item: item, isTrashContext: isViewingTrash)
                .tag(item.persistentModelID)
                .id(item.id)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        deleteItem(item)
                    } label: {
                        Label(item.isInTrash ? "Delete Forever" : "Move to Trash", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    if item.isInTrash {
                        Button {
                            restoreItemFromTrash(item)
                        } label: {
                            Label("Restore", systemImage: "arrow.uturn.backward")
                        }
                        .tint(.green)
                    }
                }
                .contextMenu {
                    if item.isInTrash {
                        Button {
                            restoreItemFromTrash(item)
                        } label: {
                            Label("Restore", systemImage: "arrow.uturn.backward")
                        }

                        Divider()

                        Button(role: .destructive) {
                            permanentlyDeleteItem(item)
                        } label: {
                            Label("Delete Forever", systemImage: "trash")
                        }
                    } else {
                        Button {
                            // Select the item for editing
                            selectedItemIDs = [item.persistentModelID]
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }

                        Button {
                            showingCategoryPickerForItem = item
                        } label: {
                            Label("Edit Category", systemImage: "folder")
                        }

                        Divider()

                        Button(role: .destructive) {
                            moveItemToTrash(item)
                        } label: {
                            Label("Move to Trash", systemImage: "trash")
                        }
                    }
                }
                .categoryPickerPresenter(
                    isPresented: createPresentedBinding(for: item),
                    selectedCategory: createCategoryBinding(for: item)
                )
        }
        .onMove(perform: moveItems)
        #if os(macOS)
        .onDelete(perform: deleteItems)
        #endif
    }

    @ViewBuilder
    private var todoListContent: some View {
        ForEach(filteredTodos) { todo in
            TodoRowView(
                todo: todo,
                sourceTitle: sourceTitle(for: todo),
                sourceCategoryName: sourceCategoryName(for: todo),
                isLinkedToNote: !isStandaloneTodo(todo),
                sourceTextAvailable: todo.isSourceTextAvailable,
                canOpenSource: sourceNote(for: todo) != nil,
                toggleCompletion: {
                    toggleTodoCompletion(todo)
                },
                updateText: { text in
                    updateStandaloneTodo(todo, text: text)
                },
                openSource: {
                    openSourceNote(for: todo)
                }
            )
            .contextMenu {
                if !isStandaloneTodo(todo) {
                    Button {
                        openSourceNote(for: todo)
                    } label: {
                        Label("Open Source Note", systemImage: "arrow.up.forward.square")
                    }
                    .disabled(sourceNote(for: todo) == nil)

                    Divider()
                }

                Button {
                    toggleTodoCompletion(todo)
                } label: {
                    Label(todo.isCompleted ? "Mark Open" : "Mark Done", systemImage: todo.isCompleted ? "square" : "checkmark.square")
                }

                Divider()

                Button(role: .destructive) {
                    deleteTodo(todo)
                } label: {
                    Label("Delete Todo", systemImage: "trash")
                }
            }
        }
        .onDelete(perform: deleteTodos)
    }
    
    // Delete a single item
    private func deleteItem(_ item: Item) {
        if item.isInTrash {
            permanentlyDeleteItem(item)
        } else {
            moveItemToTrash(item)
        }
    }

    private func isStandaloneTodo(_ todo: TodoItem) -> Bool {
        todo.sourceNote == nil && todo.sourceNoteID.isEmpty
    }

    private func createStandaloneTodo(from text: String) {
        let todoText = normalizedStandaloneTodoText(from: text)
        guard !todoText.isEmpty else { return }

        let todo = TodoItem(
            text: todoText,
            sourceText: "",
            sourceNote: nil
        )
        todo.isSourceTextAvailable = false
        modelContext.insert(todo)

        do {
            try modelContext.save()
            print("💾 Standalone todo created - CloudKit sync queued")
        } catch {
            print("❌ Failed to create standalone todo: \(error)")
        }
    }

    private func normalizedStandaloneTodoText(from text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    @discardableResult
    private func updateStandaloneTodo(_ todo: TodoItem, text: String) -> String {
        guard isStandaloneTodo(todo) else { return todo.text }

        let todoText = normalizedStandaloneTodoText(from: text)
        guard !todoText.isEmpty else { return todo.text }
        guard todo.text != todoText else { return todo.text }

        todo.text = todoText
        todo.updatedAt = Date()

        do {
            try modelContext.save()
            print("💾 Standalone todo updated - CloudKit sync queued")
        } catch {
            print("❌ Failed to update standalone todo: \(error)")
        }

        return todo.text
    }

    private func sourceNote(for todo: TodoItem) -> Item? {
        guard let note = linkedSourceNote(for: todo), !note.isInTrash else {
            return nil
        }

        return note
    }

    private func linkedSourceNote(for todo: TodoItem) -> Item? {
        if let sourceNote = todo.sourceNote {
            return sourceNote
        }

        guard !todo.sourceNoteID.isEmpty else { return nil }
        return allItems.first { $0.id.uuidString == todo.sourceNoteID }
    }

    private func sourceTitle(for todo: TodoItem) -> String {
        if isStandaloneTodo(todo) {
            return "Standalone todo"
        }

        if let note = sourceNote(for: todo) {
            return note.title.isEmpty ? "Untitled" : note.title
        }

        return todo.sourceNoteTitleSnapshot.isEmpty ? "Missing note" : todo.sourceNoteTitleSnapshot
    }

    private func sourceCategoryName(for todo: TodoItem) -> String? {
        guard !isStandaloneTodo(todo) else { return nil }

        if let categoryName = sourceNote(for: todo)?.category?.name, !categoryName.isEmpty {
            return categoryName
        }

        return todo.sourceCategoryNameSnapshot.isEmpty ? nil : todo.sourceCategoryNameSnapshot
    }

    private func openSourceNote(for todo: TodoItem) {
        guard let note = sourceNote(for: todo) else { return }
        selectedItemIDs = [note.persistentModelID]
        lastSelectedNoteID = note.id.uuidString
        isEditorActive = true

        #if os(iOS)
        if shouldPushTodoSourceInTodoList {
            todoSourceNavigationPath = [note.id]
        } else if UIDevice.current.userInterfaceIdiom == .phone {
            splitViewVisibility = .detailOnly
        }
        #endif
    }

    private func toggleTodoCompletion(_ todo: TodoItem) {
        todo.isCompleted.toggle()
        todo.completedAt = todo.isCompleted ? Date() : nil
        todo.updatedAt = Date()

        do {
            try modelContext.save()
            print("💾 Todo updated - CloudKit sync queued")
        } catch {
            print("❌ Failed to update todo: \(error)")
        }
    }

    private func deleteTodo(_ todo: TodoItem) {
        modelContext.delete(todo)

        do {
            try modelContext.save()
            print("💾 Todo deleted - CloudKit sync queued")
        } catch {
            print("❌ Failed to delete todo: \(error)")
        }
    }

    private func deleteTodos(offsets: IndexSet) {
        let todosToDelete = offsets.map { filteredTodos[$0] }
        guard !todosToDelete.isEmpty else { return }

        for todo in todosToDelete {
            modelContext.delete(todo)
        }

        do {
            try modelContext.save()
            print("💾 Deleted \(todosToDelete.count) todos - CloudKit sync queued")
        } catch {
            print("❌ Failed to delete todos: \(error)")
        }
    }

    private func deleteTodosLinked(to item: Item) {
        for todo in allTodos where todo.sourceNote == item || todo.sourceNoteID == item.id.uuidString {
            modelContext.delete(todo)
        }
    }

    private func deleteSelectedItems() {
        let itemsToProcess = filteredItems.filter { selectedItemIDs.contains($0.persistentModelID) }
        guard !itemsToProcess.isEmpty else { return }

        if isViewingTrash {
            permanentlyDeleteItems(itemsToProcess)
        } else {
            moveItemsToTrash(itemsToProcess)
        }
    }

    #if os(iOS)
    private func selectAllItems() {
        selectedItemIDs = Set(filteredItems.map { $0.persistentModelID })
    }

    private func deselectAllItems() {
        selectedItemIDs.removeAll()
    }

    private var allFilteredItemsSelected: Bool {
        guard !filteredItems.isEmpty else { return false }
        let selectedIDs = selectedItemIDs
        return filteredItems.count == selectedIDs.count
            && filteredItems.allSatisfy { selectedIDs.contains($0.persistentModelID) }
    }
    #endif

    // Manual reordering function - updates createdAt dates to maintain new order
    private func moveItems(from source: IndexSet, to destination: Int) {
        var reorderedItems = Array(filteredItems)
        reorderedItems.move(fromOffsets: source, toOffset: destination)
        
        // Update the createdAt dates to reflect the new order
        let baseDate = Date()
        for (index, item) in reorderedItems.enumerated() {
            // Set creation dates in reverse chronological order (newest first)
            item.createdAt = baseDate.addingTimeInterval(-Double(index))
        }
        
        do {
            try modelContext.save()
            print("💾 Items reordered successfully - CloudKit sync queued")
        } catch {
            print("❌ Failed to save reordered items: \(error)")
        }
    }
    
    // Manual category reordering function
    private func moveCategories(from source: IndexSet, to destination: Int) {
        var reorderedCategories = Array(visibleCategories)
        reorderedCategories.move(fromOffsets: source, toOffset: destination)
        
        // Update sort order for all categories
        for (index, category) in reorderedCategories.enumerated() {
            category.sortOrder = index
        }
        
        do {
            try modelContext.save()
            print("💾 Categories reordered successfully - CloudKit sync queued")
        } catch {
            print("❌ Failed to save reordered categories: \(error)")
        }
    }
    
    private func deleteCategoryInternal(_ category: Category) {
        // Move all notes in this category to "no category"
        for note in category.notes ?? [] {
            note.category = nil
        }

        for note in allItems where note.previousCategory == category {
            note.previousCategory = nil
        }

        // Clear selection if deleting selected category
        if case .category(let selectedCat) = sidebarSelection, selectedCat.id == category.id {
            sidebarSelection = .allNotes
            selectedItemIDs.removeAll()
        }

        modelContext.delete(category)
    }

    private func performCategoryDeletes(_ categoriesToDelete: [Category]) {
        withAnimation {
            for category in categoriesToDelete {
                deleteCategoryInternal(category)
            }

            do {
                try modelContext.save()
                print("💾 Category deleted successfully - CloudKit sync queued")
            } catch {
                print("❌ Failed to delete category: \(error)")
            }
        }
    }

    private func deleteCategory(_ category: Category) {
        deleteCategories([category])
    }

    private func deleteCategories(_ categoriesToDelete: [Category]) {
        guard !categoriesToDelete.isEmpty else { return }
        let requiresAuth = categoriesToDelete.contains(where: { $0.isPrivate })
        if requiresAuth {
            authenticateWithBiometrics(reason: "Authenticate to delete private categories") { success in
                guard success else { return }
                self.performCategoryDeletes(categoriesToDelete)
            }
        } else {
            performCategoryDeletes(categoriesToDelete)
        }
    }

    private func deleteCategories(offsets: IndexSet) {
        let categoriesToDelete = offsets.map { visibleCategories[$0] }
        deleteCategories(categoriesToDelete)
    }

    private func beginEditing(_ category: Category) {
        if category.isPrivate {
            authenticateWithBiometrics(reason: "Authenticate to edit this private category") { success in
                if success {
                    self.categoryToEdit = category
                }
            }
        } else {
            categoryToEdit = category
        }
    }

    private func togglePrivacy(for category: Category) {
        let ui = biometricToggleUI
        let actionDescription = category.isPrivate ? ui.disableTitle.lowercased() : ui.enableTitle.lowercased()
        authenticateWithBiometrics(reason: "Authenticate to \(actionDescription)") { success in
            guard success else { return }

            category.isPrivate.toggle()
            self.saveCategory()
        }
    }

    private var biometricToggleUI: (enableTitle: String, disableTitle: String, enableIcon: String, disableIcon: String) {
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)

        switch context.biometryType {
        case .faceID:
            return ("Require Face ID", "Turn Off Face ID", "faceid", "faceid")
        case .touchID:
            return ("Require Touch ID", "Turn Off Touch ID", "touchid", "touchid")
        default:
            return ("Require Authentication", "Turn Off Authentication", "lock", "lock.open")
        }
    }

    private func saveCategory() {
        withAnimation {
            do {
                try modelContext.save()
                print("✅ Category privacy setting updated - CloudKit sync queued")
            } catch {
                print("❌ Failed to save category: \(error)")
                authErrorMessage = "Failed to save privacy setting"
                showAuthError = true
            }
        }
    }

    private func toggleHiddenFromHome(for category: Category) {
        category.isHiddenFromHome.toggle()
        do {
            try modelContext.save()
            print("✅ Category hidden-from-home setting updated - CloudKit sync queued")
        } catch {
            print("❌ Failed to save hidden-from-home setting: \(error)")
        }
    }

    private func authenticateWithBiometrics(reason: String = "Authenticate to continue", completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Password"
        var authError: NSError?

        // Suppress Sendable warning - completion is dispatched to main thread and auth callbacks are safe
        nonisolated(unsafe) let unsafeCompletion = completion

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            // Device authentication not available - show warning once and allow access
            if !hasShownNoAuthWarning {
                authErrorMessage = "Device authentication is not set up. Private categories will be accessible without protection."
                showAuthError = true
                hasShownNoAuthWarning = true
            }
            // Allow access even without authentication
            completion(true)
            return
        }

        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
            if success {
                DispatchQueue.main.async {
                    unsafeCompletion(true)
                }
                return
            }

            let errorMessage: String
            if let laError = error as? LAError {
                switch laError.code {
                case .userCancel:
                    errorMessage = "Authentication cancelled"
                case .userFallback:
                    errorMessage = "Authentication failed"
                case .authenticationFailed:
                    errorMessage = "Authentication failed"
                case .biometryNotAvailable:
                    errorMessage = "Biometric authentication not available"
                case .biometryNotEnrolled:
                    errorMessage = "No biometric data enrolled"
                case .biometryLockout:
                    errorMessage = "Too many failed attempts. Try again later."
                case .passcodeNotSet:
                    errorMessage = "No passcode configured on this device"
                default:
                    errorMessage = laError.localizedDescription
                }
            } else {
                errorMessage = error?.localizedDescription ?? "Authentication failed"
            }

            DispatchQueue.main.async {
                self.authErrorMessage = errorMessage
                self.showAuthError = true
                unsafeCompletion(false)
            }
        }
    }

    private func deleteEverything() {
        // Clear selection IMMEDIATELY and SYNCHRONOUSLY before any deletion
        selectedItemIDs.removeAll()
        sidebarSelection = .allNotes

        // Give SwiftUI a moment to process the selection change
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation {
                for todo in self.allTodos {
                    self.modelContext.delete(todo)
                }

                // Delete all items
                for item in self.allItems {
                    self.modelContext.delete(item)
                }

                // Delete all categories
                for category in self.categories {
                    self.modelContext.delete(category)
                }

                do {
                    try self.modelContext.save()
                } catch {
                    print("Failed to delete all data: \(error)")
                }
            }
        }
    }

    private func prepareExternalEditorPresentation() {
        if isViewingTrash {
            sidebarSelection = .allNotes
        }

        if !searchText.isEmpty {
            searchText = ""
        }

        #if os(iOS)
        editMode = .inactive
        #endif
    }

    private func handleExternalNewNoteRequest() {
        prepareExternalEditorPresentation()
        addItem()
    }

    private func handleExternalPasswordGeneratorRequest() {
        prepareExternalEditorPresentation()
        if let selectedItem = primarySelectedItem {
            passwordGeneratorTargetNoteID = selectedItem.id
        } else {
            showingExternalPasswordGenerator = true
        }
    }

    private func insertPasswordIntoNewNote(_ password: String) {
        guard !password.isEmpty else { return }
        let attributedPassword = defaultAttributedContent(for: password)
        _ = createItem(
            content: password,
            attributedContent: archiveDefaultAttributedContent(attributedPassword)
        )
    }

    @discardableResult
    private func createItem(content: String = "", attributedContent: Data? = nil) -> Item? {
        // Create date formatter for the title
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEEE, M/d/yy"
        let dateTitle = dateFormatter.string(from: Date())

        let newItem = Item(title: dateTitle, content: content)
        newItem.attributedContent = attributedContent

        // Assign to selected category if one is chosen
        if let selectedCategory = selectedCategory {
            newItem.category = selectedCategory
        }

        modelContext.insert(newItem)

        do {
            try modelContext.save()
            print("💾 New item created and saved - CloudKit sync queued")
            // Set selection immediately
            selectedItemIDs = [newItem.persistentModelID]
            return newItem
        } catch {
            print("❌ Failed to save new item: \(error)")
            return nil
        }
    }

    private func addItem() {
        _ = createItem()
    }

    #if DEBUG
    private func createFormattingTestNote() {
        let attributedContent = formattingTestAttributedContent()
        let note = Item(
            title: "Formatting Sync Test",
            content: formattingTestPlainText()
        )
        note.attributedContent = archiveDefaultAttributedContent(attributedContent)
        note.timestamp = Date()

        if let selectedCategory = selectedCategory {
            note.category = selectedCategory
        }

        modelContext.insert(note)

        do {
            try modelContext.save()
            selectedItemIDs = [note.persistentModelID]
        } catch {
            print("Failed to create formatting test note: \(error)")
        }
    }

    private func formattingTestAttributedContent() -> NSAttributedString {
        let content = NSMutableAttributedString()
        let baseAttributes = debugTextAttributes()
        let boldAttributes = debugTextAttributes(isBold: true)
        let boldItalicAttributes = debugTextAttributes(isBold: true, isItalic: true)
        let boldItalicUnderlineAttributes = debugTextAttributes(isBold: true, isItalic: true, isUnderlined: true)
        let boldItalicStrikethroughAttributes = debugTextAttributes(isBold: true, isItalic: true, isStrikethrough: true)
        let colorAttributes = debugTextAttributes(color: .red)
        let highlightAttributes = debugTextAttributes(highlight: .yellow)

        append("1. Basic word: ", to: content, attributes: baseAttributes)
        append("Plain", to: content, attributes: baseAttributes)
        append("\n\n2. Bold word: ", to: content, attributes: baseAttributes)
        append("Bold", to: content, attributes: boldAttributes)
        append("\n\n3. Bold + Italics word: ", to: content, attributes: baseAttributes)
        append("BoldItalic", to: content, attributes: boldItalicAttributes)
        append("\n\n4. Bold + Italics + Underline word: ", to: content, attributes: baseAttributes)
        append("BoldItalicUnderline", to: content, attributes: boldItalicUnderlineAttributes)
        append("\n\n5. Bold + Italics + Strikethrough word: ", to: content, attributes: baseAttributes)
        append("BoldItalicStrike", to: content, attributes: boldItalicStrikethroughAttributes)
        append("\n\n6. Colored word: ", to: content, attributes: baseAttributes)
        append("Red", to: content, attributes: colorAttributes)
        append("\n\n7. Highlighted word: ", to: content, attributes: baseAttributes)
        append("Highlighted", to: content, attributes: highlightAttributes)
        append("\n\n8. Bullet items:\n", to: content, attributes: baseAttributes)
        append("• Bullet item one\n• Bullet item two", to: content, attributes: baseAttributes)
        append("\n\n9. Checkbox items:\n", to: content, attributes: baseAttributes)
        appendCheckboxLine("Checkbox item one", isChecked: false, to: content, attributes: baseAttributes)
        appendCheckboxLine("Checkbox item two", isChecked: true, to: content, attributes: baseAttributes)
        append("\n10. Numbered items:\n", to: content, attributes: baseAttributes)
        append("1. Numbered item one\n2. Numbered item two", to: content, attributes: baseAttributes)

        return content
    }

    private func formattingTestPlainText() -> String {
        """
        1. Basic word: Plain

        2. Bold word: Bold

        3. Bold + Italics word: BoldItalic

        4. Bold + Italics + Underline word: BoldItalicUnderline

        5. Bold + Italics + Strikethrough word: BoldItalicStrike

        6. Colored word: Red

        7. Highlighted word: Highlighted

        8. Bullet items:
        • Bullet item one
        • Bullet item two

        9. Checkbox items:
        Checkbox item one
        Checkbox item two

        10. Numbered items:
        1. Numbered item one
        2. Numbered item two
        """
    }

    private func debugTextAttributes(
        isBold: Bool = false,
        isItalic: Bool = false,
        isUnderlined: Bool = false,
        isStrikethrough: Bool = false,
        color: RichTextColor = .automatic,
        highlight: HighlighterColor = .none
    ) -> [NSAttributedString.Key: Any] {
        #if os(macOS)
        let platformColor = color.nsColor
        let platformHighlight = highlight.nsColor
        #else
        let platformColor = color.uiColor
        let platformHighlight = highlight.uiColor
        #endif

        return TextStyler(
            isBold: isBold,
            isItalic: isItalic,
            fontSize: .normal,
            colorID: color.id,
            color: platformColor,
            highlightID: highlight == .none ? nil : highlight.id,
            highlight: platformHighlight,
            isUnderlined: isUnderlined,
            isStrikethrough: isStrikethrough
        ).buildAttributes(usingAutomatic: color == .automatic)
    }

    private func append(_ text: String, to content: NSMutableAttributedString, attributes: [NSAttributedString.Key: Any]) {
        content.append(NSAttributedString(string: text, attributes: attributes))
    }

    private func appendCheckboxLine(
        _ text: String,
        isChecked: Bool,
        to content: NSMutableAttributedString,
        attributes: [NSAttributedString.Key: Any]
    ) {
        let checkbox = CheckboxTextAttachment(
            checkboxID: UUID().uuidString,
            isChecked: isChecked,
            fontPointSize: FontSize.normal.rawValue
        )
        content.append(NSAttributedString(attachment: checkbox))
        append(" \(text)\n", to: content, attributes: attributes)
    }
    #endif

    private func defaultAttributedContent(for text: String) -> NSAttributedString {
        let styler = TextStyler(
            fontSize: .normal,
            colorID: RichTextColor.automatic.id,
            color: nil
        )
        return NSAttributedString(
            string: text,
            attributes: styler.buildAttributes(usingAutomatic: true)
        )
    }

    private func archiveDefaultAttributedContent(_ attributedString: NSAttributedString) -> Data? {
        let processedString = ColorMapping.preprocessForArchiving(attributedString)
        return try? NSKeyedArchiver.archivedData(
            withRootObject: processedString,
            requiringSecureCoding: false
        )
    }

    #if os(macOS)
    private func deleteItems(offsets: IndexSet) {
        let itemsToDelete = offsets.map { filteredItems[$0] }
        if isViewingTrash {
            permanentlyDeleteItems(itemsToDelete)
        } else {
            moveItemsToTrash(itemsToDelete)
        }
    }
    #endif

    private func createPresentedBinding(for item: Item) -> Binding<Bool> {
        Binding(
            get: { showingCategoryPickerForItem == item },
            set: { if !$0 { showingCategoryPickerForItem = nil } }
        )
    }

    private func createCategoryBinding(for item: Item) -> Binding<Category?> {
        Binding(
            get: { item.category },
            set: {
                let assignedCategory = $0
                prepareSelectionForCategoryAssignment(item: item, category: assignedCategory)
                item.category = assignedCategory
                do {
                    try modelContext.save()
                    print("💾 Category updated and saved - CloudKit sync queued")
                } catch {
                    print("❌ Failed to save category: \(error)")
                }
            }
        )
    }

    private func prepareSelectionForCategoryAssignment(item: Item, category: Category?) {
        guard selectedItemIDs.count == 1,
              selectedItemIDs.contains(item.persistentModelID) else {
            return
        }

        if categoryIsHiddenFromAllNotes(category) {
            categoryAssignmentPreservedSelectionID = item.persistentModelID
        } else {
            categoryAssignmentPreservedSelectionID = nil
        }
    }

    private func categoryIsHiddenFromAllNotes(_ category: Category?) -> Bool {
        guard let category else { return false }
        return category.isPrivate || category.isHiddenFromHome
    }

    private func restoreLastSelectedNoteIfNeeded() {
        guard selectedItemIDs.isEmpty, !lastSelectedNoteID.isEmpty else { return }

        if let match = filteredItems.first(where: { $0.id.uuidString == lastSelectedNoteID }) ??
            allItems.first(where: { $0.id.uuidString == lastSelectedNoteID }) {
            selectedItemIDs = [match.persistentModelID]
        }
    }

    private func setupCloudKitNotifications() {
        guard cloudKitEventObserver == nil else { return }

        cloudKitEventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event {
                if event.type == .import || event.type == .export {
                    let eventIdentifier = event.identifier
                    let eventHasEnded = event.endDate != nil
                    Task { @MainActor in
                        updateCloudSyncIndicator(for: eventIdentifier, hasEnded: eventHasEnded)
                    }
                }

                //print("📱 CloudKit Event: \(event.type)")

                switch event.type {
                case .setup:
                    print("   ☁️ CloudKit setup completed")
                case .import:
                    print("   ⬇️ CloudKit import completed - Data imported from iCloud")
                case .export:
                    print("   ⬆️ CloudKit export completed - Data saved to iCloud")
                @unknown default:
                    print("   ❓ Unknown CloudKit event")
                }

                if let error = event.error {
                    print("   ⚠️ CloudKit error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func tearDownCloudKitNotifications() {
        guard let cloudKitEventObserver else { return }
        NotificationCenter.default.removeObserver(cloudKitEventObserver)
        self.cloudKitEventObserver = nil
        activeCloudSyncEventIDs.removeAll()
        cloudSyncHideWorkItem?.cancel()
        cloudSyncHideWorkItem = nil
        isCloudSyncIndicatorVisible = false
    }

    private func updateCloudSyncIndicator(for eventIdentifier: UUID, hasEnded: Bool) {
        if hasEnded {
            activeCloudSyncEventIDs.remove(eventIdentifier)
        } else {
            activeCloudSyncEventIDs.insert(eventIdentifier)
        }

        cloudSyncHideWorkItem?.cancel()
        cloudSyncHideWorkItem = nil

        if activeCloudSyncEventIDs.isEmpty {
            let workItem = DispatchWorkItem {
                guard self.activeCloudSyncEventIDs.isEmpty else { return }
                self.isCloudSyncIndicatorVisible = false
            }
            cloudSyncHideWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
        } else {
            isCloudSyncIndicatorVisible = true
        }
    }

    private func cleanupLegacyTrashCategories() {
        let legacyTrashCategories = categories.filter { $0.isSystemTrash }
        guard !legacyTrashCategories.isEmpty else { return }

        let legacyTrashIDs = Set(legacyTrashCategories.map(\.id))

        if case .category(let selectedCategory) = sidebarSelection, legacyTrashIDs.contains(selectedCategory.id) {
            sidebarSelection = .allNotes
            selectedItemIDs.removeAll()
        }

        for item in allItems {
            if let category = item.category, legacyTrashIDs.contains(category.id) {
                item.category = nil
            }

            if let previousCategory = item.previousCategory, legacyTrashIDs.contains(previousCategory.id) {
                item.previousCategory = nil
            }
        }

        for category in legacyTrashCategories {
            modelContext.delete(category)
        }

        do {
            try modelContext.save()
            print("💾 Removed \(legacyTrashCategories.count) legacy Trash categories")
        } catch {
            print("❌ Failed to remove legacy Trash categories: \(error)")
        }
    }

    private func moveItemToTrash(_ item: Item) {
        guard !item.isInTrash else { return }

        if selectedItemIDs.contains(item.persistentModelID) {
            selectedItemIDs.remove(item.persistentModelID)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation {
                item.previousCategory = item.category
                item.category = nil
                item.trashedAt = Date()
                item.timestamp = Date()

                do {
                    try modelContext.save()
                    print("💾 Item moved to Trash and saved successfully - CloudKit sync queued")
                } catch {
                    print("❌ Failed to move item to Trash: \(error)")
                }
            }
        }
    }

    private func moveItemsToTrash(_ items: [Item]) {
        guard !items.isEmpty else { return }

        selectedItemIDs.removeAll()

        withAnimation {
            for item in items where !item.isInTrash {
                item.previousCategory = item.category
                item.category = nil
                item.trashedAt = Date()
                item.timestamp = Date()
            }

            do {
                try modelContext.save()
                print("💾 Moved \(items.count) items to Trash - CloudKit sync queued")
                #if os(iOS)
                editMode = .inactive
                #endif
            } catch {
                print("❌ Failed to move selected items to Trash: \(error)")
            }
        }
    }

    private func permanentlyDeleteItem(_ item: Item) {
        if selectedItemIDs.contains(item.persistentModelID) {
            selectedItemIDs.remove(item.persistentModelID)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation {
                deleteTodosLinked(to: item)
                modelContext.delete(item)

                do {
                    try modelContext.save()
                    print("💾 Item permanently deleted and saved successfully - CloudKit sync queued")
                } catch {
                    print("❌ Failed to permanently delete item: \(error)")
                }
            }
        }
    }

    private func permanentlyDeleteItems(_ items: [Item]) {
        guard !items.isEmpty else { return }

        selectedItemIDs.removeAll()

        withAnimation {
            for item in items {
                deleteTodosLinked(to: item)
                modelContext.delete(item)
            }

            do {
                try modelContext.save()
                print("💾 Permanently deleted \(items.count) items - CloudKit sync queued")
                #if os(iOS)
                editMode = .inactive
                #endif
            } catch {
                print("❌ Failed to permanently delete selected items: \(error)")
            }
        }
    }

    private func emptyTrash() {
        permanentlyDeleteItems(trashItems)
    }

    private func restoreItemFromTrash(_ item: Item) {
        guard item.isInTrash else { return }

        withAnimation {
            item.category = item.previousCategory
            item.previousCategory = nil
            item.trashedAt = nil
            item.timestamp = Date()

            do {
                try modelContext.save()
                print("💾 Item restored from Trash - CloudKit sync queued")
            } catch {
                print("❌ Failed to restore item from Trash: \(error)")
            }
        }
    }

    private func purgeExpiredTrash() {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date.distantPast
        let expiredItems = allItems.filter { item in
            guard let trashedAt = item.trashedAt else { return false }
            return trashedAt <= cutoffDate
        }

        guard !expiredItems.isEmpty else { return }

        for item in expiredItems {
            if selectedItemIDs.contains(item.persistentModelID) {
                selectedItemIDs.remove(item.persistentModelID)
            }
            deleteTodosLinked(to: item)
            modelContext.delete(item)
        }

        do {
            try modelContext.save()
            print("💾 Purged \(expiredItems.count) expired Trash items")
        } catch {
            print("❌ Failed to purge expired Trash items: \(error)")
        }
    }

    #if os(macOS)
    private func startExport() {
        do {
            let data = try DataExportImport.exportAll(from: modelContext)
            exportDocument = NotesExportDocument(data: data)
            isExporting = true
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func handleImport(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            importError = "Unable to access selected file."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let data = try Data(contentsOf: url)
            let result = try DataExportImport.importPackage(from: data, into: modelContext)
            importResultMessage = "Imported \(result.importedCategories) categories, \(result.importedNotes) notes, and \(result.importedTodos) todos."
        } catch {
            importError = error.localizedDescription
        }
    }
    #endif
}

#if os(macOS)
private struct MacImportExportPresentationModifier: ViewModifier {
    @Binding var showExportAlert: Bool
    @Binding var isExporting: Bool
    let exportDocument: NotesExportDocument
    @Binding var exportError: String?
    @Binding var isImporting: Bool
    @Binding var importError: String?
    @Binding var importResultMessage: String?
    let startExport: () -> Void
    let handleImport: (URL) -> Void

    private var isExportErrorPresented: Binding<Bool> {
        Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )
    }

    private var isImportResultPresented: Binding<Bool> {
        Binding(
            get: { importResultMessage != nil },
            set: { if !$0 { importResultMessage = nil } }
        )
    }

    private var isImportErrorPresented: Binding<Bool> {
        Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )
    }

    func body(content: Content) -> some View {
        content
            .alert("Export Notes", isPresented: $showExportAlert) {
                Button("Export", role: .none) {
                    startExport()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Everything will be exported as plain text, including private notes.")
            }
            .alert("Export Failed", isPresented: isExportErrorPresented) {
                Button("OK", role: .cancel) { exportError = nil }
            } message: {
                Text(exportError ?? "Unknown error")
            }
            .alert("Import Result", isPresented: isImportResultPresented) {
                Button("OK", role: .cancel) { importResultMessage = nil }
            } message: {
                Text(importResultMessage ?? "")
            }
            .alert("Import Failed", isPresented: isImportErrorPresented) {
                Button("OK", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "Unknown error")
            }
            .fileExporter(
                isPresented: $isExporting,
                document: exportDocument,
                contentType: .json,
                defaultFilename: "Jotable-Export"
            ) { result in
                if case let .failure(error) = result {
                    exportError = error.localizedDescription
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    handleImport(url)
                case .failure(let error):
                    importError = error.localizedDescription
                }
            }
    }
}

private extension View {
    func macImportExportPresentation(
        showExportAlert: Binding<Bool>,
        isExporting: Binding<Bool>,
        exportDocument: NotesExportDocument,
        exportError: Binding<String?>,
        isImporting: Binding<Bool>,
        importError: Binding<String?>,
        importResultMessage: Binding<String?>,
        startExport: @escaping () -> Void,
        handleImport: @escaping (URL) -> Void
    ) -> some View {
        modifier(
            MacImportExportPresentationModifier(
                showExportAlert: showExportAlert,
                isExporting: isExporting,
                exportDocument: exportDocument,
                exportError: exportError,
                isImporting: isImporting,
                importError: importError,
                importResultMessage: importResultMessage,
                startExport: startExport,
                handleImport: handleImport
            )
        )
    }
}
#endif

private struct NotesToolbar: ToolbarContent {
    let isEditing: Bool
    let filteredItems: [Item]
    let selectedItemIDs: Set<PersistentIdentifier>
    #if os(iOS)
    let allItemsIsEmpty: Bool
    let allFilteredItemsSelected: Bool
    #endif
    let deleteSelectedLabel: String
    let deleteSelectedSystemImage: String
    let deleteSelectedItems: () -> Void
    let addItem: () -> Void
    #if os(iOS)
    let selectAllItems: () -> Void
    let deselectAllItems: () -> Void
    #endif

    var body: some ToolbarContent {
        let showSelectAll = isEditing && !filteredItems.isEmpty
        let showDeleteSelected = isEditing && !selectedItemIDs.isEmpty
        let showNewNote = !isEditing

        ToolbarItemGroup(placement: .primaryAction) {
            #if os(macOS)
            if !selectedItemIDs.isEmpty {
                Button(role: .destructive, action: deleteSelectedItems) {
                    Label(deleteSelectedLabel, systemImage: deleteSelectedSystemImage)
                }
            }
            #endif
            #if os(iOS)
            if showSelectAll {
                let title = allFilteredItemsSelected ? "Deselect All" : "Select All"
                let icon = allFilteredItemsSelected ? "minus.circle" : "checkmark.circle"
                let action = allFilteredItemsSelected ? deselectAllItems : selectAllItems
                Button(action: action) {
                    Label(title, systemImage: icon)
                }
            }
            if showDeleteSelected {
                Button(role: .destructive, action: deleteSelectedItems) {
                    Label(deleteSelectedLabel, systemImage: deleteSelectedSystemImage)
                }
            }
            if showNewNote {
                Button(action: addItem) {
                    Label("New Note", systemImage: "square.and.pencil")
                }
            }
            if !allItemsIsEmpty {
                EditButton()
            }
            #else
            Button(action: addItem) {
                Label("New Note", systemImage: "square.and.pencil")
            }
            #endif
        }
    }
}

// Separate view for category rows to ensure proper native behavior
struct CategoryRowView: View {
    let icon: String?
    let title: String
    let count: Int
    let color: String?
    let isPrivate: Bool
    let isHiddenFromHome: Bool

    var body: some View {
        HStack {
            if let icon = icon {
                Image(systemName: icon)
                    .foregroundColor(.primary)
            } else if let color = color {
                Circle()
                    .fill(Color.fromString(color))
                    .frame(width: 12, height: 12)
            }

            if isPrivate {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if isHiddenFromHome {
                Image(systemName: "eye.slash.fill")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Text(title)

            Spacer()

            Text("\(count)")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .contentShape(Rectangle())
    }
}

struct TodoRowView: View {
    let todo: TodoItem
    let sourceTitle: String
    let sourceCategoryName: String?
    let isLinkedToNote: Bool
    let sourceTextAvailable: Bool
    let canOpenSource: Bool
    let toggleCompletion: () -> Void
    let updateText: (String) -> String
    let openSource: () -> Void

    @State private var draftText = ""
    @State private var isInfoPresented = false
    @FocusState private var isTextFocused: Bool

    private var sourceLabel: String {
        guard isLinkedToNote else {
            return "Standalone todo"
        }

        let title = sourceTextAvailable ? sourceTitle : "\(sourceTitle) - source text removed"
        if let sourceCategoryName {
            return "\(sourceCategoryName) / \(title)"
        }
        return title
    }

    private var sourceIcon: String {
        guard isLinkedToNote else {
            return "checklist"
        }

        return canOpenSource ? "arrow.up.forward.square" : "exclamationmark.triangle"
    }

    private var sourceHelp: String {
        if canOpenSource {
            return "Open source note"
        }

        return isLinkedToNote ? "Source note is unavailable" : "Standalone todo"
    }

    @ViewBuilder
    private var titleContent: some View {
        if isLinkedToNote {
            Text(todo.text)
                .font(.body)
                .foregroundStyle(todo.isCompleted ? .secondary : .primary)
                .strikethrough(todo.isCompleted)
                .lineLimit(3)
        } else {
            TextField("Todo", text: $draftText, axis: .vertical)
                .font(.body)
                .foregroundStyle(todo.isCompleted ? .secondary : .primary)
                .strikethrough(todo.isCompleted)
                .lineLimit(1...3)
                .textFieldStyle(.plain)
                .focused($isTextFocused)
                .onSubmit {
                    commitStandaloneEdit()
                }
                .onChange(of: isTextFocused) { _, isFocused in
                    if !isFocused {
                        commitStandaloneEdit()
                    }
                }
                #if os(iOS)
                .textInputAutocapitalization(.sentences)
                #endif
        }
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                titleContent

                HStack(spacing: 4) {
                    Image(systemName: sourceIcon)
                        .font(.caption)
                    Text(sourceLabel)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(canOpenSource ? .secondary : .tertiary)
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var infoButton: some View {
        Button {
            isInfoPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.body)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Todo info")
        .help("Show todo dates")
        .popover(isPresented: $isInfoPresented) {
            todoInfoPopover
                #if os(iOS)
                .presentationCompactAdaptation(.sheet)
                .presentationDetents([.height(todoInfoSheetHeight)])
                .presentationDragIndicator(.visible)
                #endif
        }
    }

    private var todoInfoSheetHeight: CGFloat {
        todo.completedAt == nil ? 170 : 220
    }

    private var todoInfoPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Todo Info")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                dateRow(title: "Created", date: todo.createdAt)

                if let completedAt = todo.completedAt {
                    dateRow(title: "Completed", date: completedAt)
                }
            }
        }
        .padding(16)
        #if os(iOS)
        .frame(maxWidth: .infinity, alignment: .leading)
        #else
        .frame(minWidth: 220, alignment: .leading)
        #endif
    }

    private func dateRow(title: String, date: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(formattedDate(date))
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: toggleCompletion) {
                Image(systemName: todo.isCompleted ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(todo.isCompleted ? "Mark todo open" : "Mark todo done")

            if canOpenSource {
                Button(action: openSource) {
                    rowContent
                }
                .buttonStyle(.plain)
                .help(sourceHelp)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                rowContent
                    .help(sourceHelp)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            infoButton
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onAppear {
            draftText = todo.text
        }
        .onChange(of: todo.text) { _, newValue in
            if !isTextFocused {
                draftText = newValue
            }
        }
    }

    private func commitStandaloneEdit() {
        guard !isLinkedToNote else { return }

        let savedText = updateText(draftText)
        if draftText != savedText {
            draftText = savedText
        }
    }
}

struct NoteRowView: View {
    let item: Item
    let isTrashContext: Bool
    private let attachmentPreviewToken = "Image"
    private let trashRetentionDays = 30
    
    private var previewText: String {
        let normalized = item.content.replacingOccurrences(
            of: "\u{FFFC}+",
            with: attachmentPreviewToken,
            options: .regularExpression
        )
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Start writing..." }
        
        // Use the first non-empty line to avoid blank previews when the note starts with newlines
        let firstNonEmptyLine = trimmed
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        
        return firstNonEmptyLine ?? trimmed
    }

    private var trashExpiryDate: Date? {
        guard let trashedAt = item.trashedAt else { return nil }
        return Calendar.current.date(byAdding: .day, value: trashRetentionDays, to: trashedAt)
    }

    private var trashCountdownText: String? {
        guard let trashExpiryDate else { return nil }
        let today = Calendar.current.startOfDay(for: Date())
        let expiryDay = Calendar.current.startOfDay(for: trashExpiryDate)
        let remainingDays = Calendar.current.dateComponents([.day], from: today, to: expiryDay).day ?? 0

        if remainingDays <= 0 {
            return "Expires today"
        }
        if remainingDays == 1 {
            return "1 day left"
        }
        return "\(remainingDays)d left"
    }

    private var trashDeletionDateText: String? {
        guard let trashExpiryDate else { return nil }
        return "Deletes \(trashExpiryDate.formatted(.dateTime.month(.abbreviated).day()))"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.title.isEmpty ? "Untitled" : item.title)
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()

                if isTrashContext, let trashCountdownText {
                    Text(trashCountdownText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.orange.opacity(0.12))
                        )
                } else {
                    Text(item.timestamp, format: .relative(presentation: .named))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // Show category indicator
                if !isTrashContext, let category = item.category {
                    Circle()
                        .fill(Color.fromString(category.color))
                        .frame(width: 8, height: 8)
                        .padding(.leading, 4)
                }
            }
            
            Text(previewText)
                .font(.subheadline)
                .foregroundStyle(previewText == "Start writing..." ? .tertiary : .secondary)
                .lineLimit(1)

            if isTrashContext, let trashDeletionDateText {
                Text(trashDeletionDateText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .id(item.persistentModelID)
    }
}

private struct CloudSyncToolbarIndicator: View {
    #if os(macOS)
    @State private var isRotating = false
    #endif

    var body: some View {
        Group {
            #if os(macOS)
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 17, weight: .medium))
                .rotationEffect(.degrees(isRotating ? 360 : 0))
                .frame(width: 24, height: 24, alignment: .center)
                .padding(.horizontal, 4)
                .onAppear {
                    guard !isRotating else { return }
                    withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                        isRotating = true
                    }
                }
                .onDisappear {
                    isRotating = false
                }
            #else
            ProgressView()
                .progressViewStyle(.circular)
            #endif
        }
        .help("Syncing with iCloud")
        .accessibilityLabel("Syncing with iCloud")
    }
}

#if os(macOS)
private extension View {
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
    func categoryPickerPresenter(isPresented: Binding<Bool>, selectedCategory: Binding<Category?>) -> some View {
        sheet(isPresented: isPresented) {
            CategoryPickerView(selectedCategory: selectedCategory)
        }
    }
}
#endif
