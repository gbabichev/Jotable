//
//  ContentView.swift
//  SimpleNote
//

import SwiftUI
import SwiftData
import CoreData
import LocalAuthentication
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// Selection type for the sidebar
enum SidebarSelection: Hashable {
    case allNotes
    case todoList
    case trash
    case category(Category)
}

private enum RestorableSidebarDestination: String {
    case allNotes
    case todoList

    var sidebarSelection: SidebarSelection {
        switch self {
        case .allNotes: .allNotes
        case .todoList: .todoList
        }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif
    // Changed from timestamp to createdAt for stable sorting based on creation date
    @Query(sort: \Item.createdAt, order: .reverse) private var allItems: [Item]
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @AppStorage("lastSelectedNoteID") private var lastSelectedNoteID: String = ""
    @AppStorage("lastSidebarDestination") private var lastSidebarDestination = RestorableSidebarDestination.allNotes.rawValue
    @AppStorage("isCompletedTodoSectionExpanded") private var isCompletedTodoSectionExpanded = true

    #if os(macOS)
    @Binding var pastePlaintextTrigger: UUID?
    #endif
    @Binding var isEditorExpanded: Bool
    @Binding var isEditorActive: Bool

    // Use Jotable's model UUIDs for UI selection. SwiftData persistent
    // identifiers can be refaulted while CloudKit applies a merge, which can
    // make List briefly select a different row and reconstruct the editor's
    // toolbar even though the logical note selection did not change.
    @State private var selectedItemIDs: Set<UUID> = []
    @State private var offListPreservedSelectionID: UUID?
    #if os(iOS)
    @State private var splitViewVisibility: NavigationSplitViewVisibility = UIDevice.current.userInterfaceIdiom == .pad ? .all : .automatic
    #endif
    @State private var sidebarSelection: SidebarSelection? = .allNotes
    @State private var showingAddCategory = false
    @State private var showingAddTodo = false
    @State private var showingClearCompletedTodosConfirmation = false
    @State private var selectedTodoIDs: Set<UUID> = []
    @State private var showingClearTrashConfirmation = false
    @State private var categoryToEdit: Category?
    @State private var searchText = ""
    @State private var authenticatingCategoryID: PersistentIdentifier?
    @State private var isRevertingSelection = false
    // The unlock session belongs to the app, rather than an individual window.
    // Bindings keep it alive when the last macOS window is closed and reopened,
    // while still resetting it when the app process exits.
    @Binding var isAuthenticatedForPrivateAccess: Bool
    @Binding var lastAuthenticationTime: Date?
    @State private var hasShownNoAuthWarning = false
    @State private var showAuthError = false
    @State private var authErrorMessage = ""
    @State private var showingCategoryPickerForItem: Item?
    @State private var todoSnapshot: [TodoItem]?
    #if !os(macOS)
    @State private var activeCloudSyncEventIDs: Set<UUID> = []
    @State private var cloudKitEventObserver: NSObjectProtocol?
    @State private var isCloudSyncIndicatorVisible = false
    @State private var cloudSyncHideWorkItem: DispatchWorkItem?
    #endif
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

    #if os(macOS)
    init(
        pastePlaintextTrigger: Binding<UUID?>,
        isEditorExpanded: Binding<Bool>,
        isEditorActive: Binding<Bool>,
        isAuthenticatedForPrivateAccess: Binding<Bool>,
        lastAuthenticationTime: Binding<Date?>
    ) {
        _pastePlaintextTrigger = pastePlaintextTrigger
        _isEditorExpanded = isEditorExpanded
        _isEditorActive = isEditorActive
        _isAuthenticatedForPrivateAccess = isAuthenticatedForPrivateAccess
        _lastAuthenticationTime = lastAuthenticationTime
        let initialDestination = Self.initialSidebarDestination()
        let initialSelection: (ids: Set<UUID>, offListID: UUID?) = initialDestination == .todoList
            ? (ids: Set<UUID>(), offListID: nil)
            : Self.initialSelectionState()
        _selectedItemIDs = State(initialValue: initialSelection.ids)
        _offListPreservedSelectionID = State(initialValue: initialSelection.offListID)
        _sidebarSelection = State(initialValue: initialDestination.sidebarSelection)
    }
    #else
    init(
        isEditorExpanded: Binding<Bool>,
        isEditorActive: Binding<Bool>,
        isAuthenticatedForPrivateAccess: Binding<Bool>,
        lastAuthenticationTime: Binding<Date?>
    ) {
        _isEditorExpanded = isEditorExpanded
        _isEditorActive = isEditorActive
        _isAuthenticatedForPrivateAccess = isAuthenticatedForPrivateAccess
        _lastAuthenticationTime = lastAuthenticationTime
        let initialDestination = Self.initialSidebarDestination()
        let initialSelection: (ids: Set<UUID>, offListID: UUID?) = initialDestination == .todoList
            ? (ids: Set<UUID>(), offListID: nil)
            : Self.initialSelectionState()
        _selectedItemIDs = State(initialValue: initialSelection.ids)
        _offListPreservedSelectionID = State(initialValue: initialSelection.offListID)
        _sidebarSelection = State(initialValue: initialDestination.sidebarSelection)
    }
    #endif

    // Restore the editor selection before NavigationSplitView builds its first
    // toolbar. Restoring in onAppear inserts the editor's toolbar contributors
    // after the window is visible, which macOS animates as a conspicuous blink.
    private static func initialSelectionState() -> (ids: Set<UUID>, offListID: UUID?) {
        let context = JotableApp.sharedModelContainer.mainContext
        guard let items = try? context.fetch(FetchDescriptor<Item>()) else {
            return ([], nil)
        }

        if let storedID = UserDefaults.standard.string(forKey: "lastSelectedNoteID"),
           !storedID.isEmpty,
           let item = items.first(where: { $0.id.uuidString == storedID && !$0.isInTrash }) {
            let category = item.category
            let isOffList = category?.isHiddenFromHome == true || category?.isPrivate == true
            return ([item.id], isOffList ? item.id : nil)
        }

        return ([], nil)
    }

    private static func initialSidebarDestination() -> RestorableSidebarDestination {
        let storedValue = UserDefaults.standard.string(forKey: "lastSidebarDestination")
        return RestorableSidebarDestination(rawValue: storedValue ?? "") ?? .allNotes
    }

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

    // TodoItem is intentionally not a root @Query. Its CloudKit merges should
    // not invalidate the notes window and reconstruct the native toolbar.
    private var allTodos: [TodoItem] {
        if let todoSnapshot {
            return todoSnapshot
        }

        var descriptor = FetchDescriptor<TodoItem>(
            sortBy: [SortDescriptor(\TodoItem.createdAt, order: .reverse)]
        )
        descriptor.includePendingChanges = true
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private var todoListTodos: [TodoItem] {
        allTodos.filter { todo in
            guard let linkedNote = linkedSourceNote(for: todo) else { return true }
            return !linkedNote.isInTrash
        }
    }

    private var hasHiddenPrivateTodos: Bool {
        !isAuthenticationValid && todoListTodos.contains(where: isPrivateTodo)
    }

    private var visibleTodos: [TodoItem] {
        todoListTodos.filter { todo in
            !isPrivateTodo(todo) || isAuthenticationValid
        }
    }

    private var openTodoCount: Int {
        visibleTodos.filter { !$0.isCompleted }.count
    }

    private var overdueTodoCount: Int {
        let today = Calendar.current.startOfDay(for: Date())
        return visibleTodos.filter { todo in
            guard !todo.isCompleted, let dueDate = todo.dueDate else { return false }
            return dueDate < today
        }.count
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

            return todoSortPrecedes(lhs, rhs)
        }
    }

    private func todoSortPrecedes(_ lhs: TodoItem, _ rhs: TodoItem) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder > rhs.sortOrder
        }

        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }

        return lhs.id.uuidString < rhs.id.uuidString
    }

    private var filteredOpenTodos: [TodoItem] {
        filteredTodos.filter { !$0.isCompleted }
    }

    private var filteredCompletedTodos: [TodoItem] {
        filteredTodos.filter(\.isCompleted)
    }

    #if os(iOS)
    private var todosAvailableForSelection: [TodoItem] {
        shouldUseTwoColumnTodoLayout ? filteredOpenTodos : filteredTodos
    }

    private var allAvailableTodosSelected: Bool {
        guard !todosAvailableForSelection.isEmpty else { return false }
        return todosAvailableForSelection.allSatisfy { selectedTodoIDs.contains($0.id) }
    }
    #endif

    private var clearCompletedTodosButtonTitle: String {
        let count = filteredCompletedTodos.count
        return "Clear \(count) Completed \(count == 1 ? "Todo" : "Todos")"
    }

    private var clearCompletedTodosConfirmationMessage: String {
        if searchText.isEmpty {
            return "This deletes every completed todo currently visible in the Todo List."
        }

        return "This deletes the completed todos matching the current search."
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
            return allItems.first { item in
                item.id == selectedID &&
                    !item.isInTrash &&
                    canAccessNoteFromTodoList(item)
            }
        }

        if let visibleItem = filteredItems.first(where: { $0.id == selectedID }) {
            return visibleItem
        }

        guard let selectedItem = allItems.first(where: { $0.id == selectedID && !$0.isInTrash }) else {
            return nil
        }

        if offListPreservedSelectionID == selectedID {
            return selectedItem.category?.isPrivate == true && !isAuthenticationValid
                ? nil
                : selectedItem
        }

        return canPresentOffListSelection(selectedItem) ? selectedItem : nil
    }

    /// Hidden notes are intentionally absent from All Notes, but that should
    /// not prevent an already-selected note from reopening in the editor.
    /// Private notes follow the same path only while the in-memory unlock
    /// session is still valid.
    private func canPresentOffListSelection(_ item: Item) -> Bool {
        guard !item.isInTrash, let category = item.category else { return false }
        if category.isPrivate {
            return isAuthenticationValid
        }
        return category.isHiddenFromHome
    }

    private var listSelectionBinding: Binding<Set<UUID>> { $selectedItemIDs }

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
        canExpandEditor && isEditorExpanded && !isViewingTodoList && !isViewingTrash
    }

    #if os(iOS)
    private var shouldUseTwoColumnTodoLayout: Bool {
        horizontalSizeClass == .regular ||
            (UIDevice.current.userInterfaceIdiom == .phone && verticalSizeClass == .compact)
    }

    private var shouldPushTodoSourceInTodoList: Bool {
        !shouldUseTwoColumnTodoLayout
    }

    private var addTodoSheetHeight: CGFloat {
        360
    }

    private var addCategorySheetHeight: CGFloat {
        420
    }
    #endif

    @ViewBuilder
    private var navigationContent: some View {
        if shouldUseExpandedEditorLayout {
            detailColumn
        } else {
            standardNavigationSplitView
        }
    }

    private var standardNavigationSplitView: some View {
        #if os(macOS)
        // Keep one stable split-view hierarchy so AppKit can restore the
        // user-adjusted divider positions when the window is recreated.
        NavigationSplitView {
            sidebarColumn
        } content: {
            Group {
                if isViewingTodoList {
                    todoListColumn
                } else {
                    notesListColumn
                }
            }
            .navigationSplitViewColumnWidth(min: 350, ideal: 350, max: 400)
        } detail: {
            detailColumn
        }
        #else
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
        #endif
    }

    private var sidebarColumn: some View {
        List(selection: $sidebarSelection) {
            sidebarContent
        }
        .listStyle(SidebarListStyle())
        .navigationTitle("Jotable")
        .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
        .onChange(of: selectedItemIDs) { _, _ in
            if let preservedID = offListPreservedSelectionID,
               !selectedItemIDs.contains(preservedID) {
                #if os(macOS)
                // AppKit may clear a selection whose row is filtered out.
                // On iOS, Back also clears selection; respect that navigation
                // instead of immediately reopening the hidden note.
                if selectedItemIDs.isEmpty,
                   allItems.contains(where: { $0.id == preservedID && !$0.isInTrash }) {
                    selectedItemIDs = [preservedID]
                    return
                }
                #endif

                offListPreservedSelectionID = nil
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
            persistSidebarDestination(newValue)

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
                            self.beginPrivateAccessSession()
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

                    Button {
                        fillTodosForDebug()
                    } label: {
                        Label("Fill Todos", systemImage: "checklist")
                    }

                    Divider()

                    Button {
                        createDebugCategories()
                    } label: {
                        Label("Create Categories", systemImage: "folder.badge.plus")
                    }

                    Button {
                        createDebugNotes()
                    } label: {
                        Label("Create Notes", systemImage: "doc.badge.plus")
                    }

                    if JotableApp.isLegacySyncTestMode {
                        Button {
                            createLegacySyncTestNotes()
                        } label: {
                            Label("Create Legacy Sync Test Notes", systemImage: "clock.arrow.circlepath")
                        }
                    }

                    Button {
                        createDebugCategoriesWithNotes()
                    } label: {
                        Label("Create Categories with Notes", systemImage: "rectangle.stack.badge.plus")
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
            #if os(iOS)
            .presentationCompactAdaptation(.sheet)
            .presentationDetents([.height(addCategorySheetHeight)])
            .presentationDragIndicator(.visible)
            #endif
        }
        .sheet(item: $categoryToEdit) { category in
            AddCategoryView(categoryToEdit: category)
            #if os(iOS)
            .presentationCompactAdaptation(.sheet)
            .presentationDetents([.height(addCategorySheetHeight)])
            .presentationDragIndicator(.visible)
            #endif
        }
    }

    private var notesListColumn: some View {
        notesListBody
        .searchable(
            text: $searchText,
            prompt: "Search notes"
        )
        .navigationTitle(currentNavigationTitle)
        .navigationSubtitle("\(filteredItems.count) \(filteredItems.count == 1 ? "note" : "notes")")
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

            if isViewingTrash {
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) {
                        showingClearTrashConfirmation = true
                    } label: {
                        Label("Clear Trash", systemImage: "trash.slash")
                    }
                    .help("Permanently delete everything in Trash")
                    .disabled(trashItems.isEmpty)
                }
            }
        }
        #if os(iOS)
        .environment(\.editMode, $editMode)
        #endif
    }

    @ViewBuilder
    private var notesListBody: some View {
        if filteredItems.isEmpty {
            #if os(macOS)
            notesEmptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            #else
            ScrollView {
                notesEmptyState
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 360)
            }
            #endif
        } else {
            List(selection: listSelectionBinding) {
                notesListContent
            }
            #if os(macOS)
            // Keep AppKit's cached table-row estimate in sync with the actual
            // two-line SwiftUI row. macOS otherwise uses its compact default
            // for short, non-scrolling lists and clips the preview until the
            // split view or window forces a native row-height recalculation.
            .environment(\.defaultMinListRowHeight, 56)
            #endif
        }
    }

    private var notesEmptyState: some View {
        ContentUnavailableView {
            Label("No Notes", systemImage: "note.text")
        } description: {
            Text(notesEmptyStateDescription)
        }
    }

    private var notesEmptyStateDescription: String {
        if !searchText.isEmpty {
            return "No matching notes."
        }

        if isViewingTrash {
            return "Trash is empty."
        }

        if selectedCategory != nil {
            return "No notes in this category yet."
        }

        return "No notes yet."
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
            .onChange(of: todoSourceNavigationPath) { _, path in
                if path.isEmpty {
                    selectedItemIDs.removeAll()
                    isEditorActive = false
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
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                #if os(iOS)
                if isEditing && !todosAvailableForSelection.isEmpty {
                    Button(
                        allAvailableTodosSelected ? "Deselect All" : "Select All",
                        systemImage: allAvailableTodosSelected ? "minus.circle" : "checkmark.circle"
                    ) {
                        if allAvailableTodosSelected {
                            selectedTodoIDs.removeAll()
                        } else {
                            selectedTodoIDs = Set(todosAvailableForSelection.map(\.id))
                        }
                    }
                }

                if isEditing && !selectedTodoIDs.isEmpty {
                    Button(role: .destructive) {
                        deleteSelectedTodos()
                    } label: {
                        Label("Delete Selected", systemImage: "trash")
                    }
                }
                #endif

                if !isEditing {
                    Button {
                        showingAddTodo = true
                    } label: {
                        Label("New Todo", systemImage: "plus")
                    }
                }

                if hasHiddenPrivateTodos {
                    Button {
                        unlockPrivateTodos()
                    } label: {
                        Label("Show Private Todos", systemImage: biometricToggleUI.enableIcon)
                    }
                    .accessibilityLabel("Show private todos")
                    .help("Authenticate to show todos from private notes")
                }

                #if !os(macOS)
                if !filteredTodos.isEmpty {
                    EditButton()
                }

                if isCloudSyncIndicatorVisible {
                    CloudSyncToolbarIndicator()
                }
                #endif
            }
        }
        #if os(iOS)
        .environment(\.editMode, $editMode)
        #endif
    }

    private var completedTodoListColumn: some View {
        Group {
            if filteredCompletedTodos.isEmpty {
                ContentUnavailableView {
                    Label("No Completed Todos", systemImage: "checkmark.square")
                } description: {
                    Text(searchText.isEmpty ? "Completed todos will appear here." : "No completed todos match your search.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                #if os(iOS)
                if isEditing {
                    List(selection: $selectedTodoIDs) {
                        completedTodoListContent
                    }
                    .contentMargins(.top, 0, for: .scrollContent)
                    .listStyle(.plain)
                    .scrollDismissesKeyboard(.interactively)
                } else {
                    List {
                        completedTodoListContent
                    }
                    .contentMargins(.top, 0, for: .scrollContent)
                    .listStyle(.plain)
                    .scrollDismissesKeyboard(.interactively)
                }
                #else
                List {
                    completedTodoListContent
                }
                .contentMargins(.top, 0, for: .scrollContent)
                #endif
            }
        }
        .safeAreaBar(edge: .top, spacing: 0) {
            todoColumnHeader("Completed", count: filteredCompletedTodos.count)
        }
        .toolbar {
            if !filteredCompletedTodos.isEmpty {
                #if os(macOS)
                ToolbarItemGroup(placement: .automatic) {
                    Spacer()

                    Button(role: .destructive) {
                        showingClearCompletedTodosConfirmation = true
                    } label: {
                        Label("Clear Completed", systemImage: "trash")
                    }
                    .help("Clear completed todos")
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) {
                        showingClearCompletedTodosConfirmation = true
                    } label: {
                        Label("Clear Completed", systemImage: "trash")
                    }
                    .help("Clear completed todos")
                }
                #endif
            }
        }
        #if os(iOS)
        .environment(\.editMode, $editMode)
        #endif
    }

    @ViewBuilder
    private var todoListBody: some View {
        #if os(macOS)
        openTodoColumnBody
        #else
        if shouldUseTwoColumnTodoLayout {
            openTodoColumnBody
        } else if filteredTodos.isEmpty {
            ScrollView {
                todoEmptyState
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 360)
            }
            .scrollDismissesKeyboard(.interactively)
        } else {
            if isEditing {
                List(selection: $selectedTodoIDs) {
                    todoListContent
                }
                .listStyle(.plain)
                .listSectionSpacing(.compact)
                .contentMargins(.top, 0, for: .scrollContent)
                .scrollDismissesKeyboard(.interactively)
            } else {
                List {
                    todoListContent
                }
                .listStyle(.plain)
                .listSectionSpacing(.compact)
                .contentMargins(.top, 0, for: .scrollContent)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        #endif
    }

    private var openTodoColumnBody: some View {
        Group {
            if filteredOpenTodos.isEmpty {
                todoEmptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                #if os(iOS)
                if isEditing {
                    List(selection: $selectedTodoIDs) {
                        openTodoListContent
                    }
                    .contentMargins(.top, 0, for: .scrollContent)
                    .listStyle(.plain)
                    .scrollDismissesKeyboard(.interactively)
                } else {
                    List {
                        openTodoListContent
                    }
                    .contentMargins(.top, 0, for: .scrollContent)
                    .listStyle(.plain)
                    .scrollDismissesKeyboard(.interactively)
                }
                #else
                List {
                    openTodoListContent
                }
                .contentMargins(.top, 0, for: .scrollContent)
                #endif
            }
        }
        .safeAreaBar(edge: .top, spacing: 0) {
            todoColumnHeader("Open", count: filteredOpenTodos.count)
        }
    }

    private func todoColumnHeader(_ title: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.headline)

            Spacer(minLength: 8)

            Text(count, format: .number)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var todoEmptyState: some View {
        ContentUnavailableView {
            Label("No Todos", systemImage: "checklist")
        } description: {
            Text(todoEmptyStateDescription)
        }
    }

    private var todoEmptyStateDescription: String {
        if !searchText.isEmpty {
            return "No matching todos."
        }

        if hasHiddenPrivateTodos {
            return privateTodoHiddenMessage
        }

        #if os(macOS)
        return "No open todos."
        #else
        return "No todo items yet."
        #endif
    }

    private var privateTodoHiddenMessage: String {
        "Some todos from private notes are hidden. Use the toolbar button to show them."
    }

    #if os(iOS)
    @ViewBuilder
    private func todoSourceDestination(for noteID: UUID) -> some View {
        if let note = allItems.first(where: { $0.id == noteID && !$0.isInTrash }),
           canAccessNoteFromTodoList(note) {
            NoteEditorView(
                item: note,
                itemID: note.id,
                isEditorActive: $isEditorActive,
                isEditorExpanded: $isEditorExpanded,
                passwordGeneratorTargetNoteID: $passwordGeneratorTargetNoteID,
                onCategoryAssignment: prepareSelectionForCategoryAssignment,
                onToggleEditorFocus: {
                    setEditorExpanded(!isEditorExpanded)
                }
            )
            .equatable()
            .id(note.id)
        } else {
            ContentUnavailableView {
                Label("Note Unavailable", systemImage: "lock")
            } description: {
                Text("The source note for this todo is unavailable or requires authentication.")
            }
        }
    }
    #endif

    private var detailColumn: some View {
        NavigationStack {
            if isViewingTodoList {
                #if os(macOS)
                completedTodoListColumn
                #else
                if shouldUseTwoColumnTodoLayout {
                    completedTodoListColumn
                } else {
                    noteDetailContent
                }
                #endif
            } else {
                noteDetailContent
            }
        }
    }

    @ViewBuilder
    private var noteDetailContent: some View {
        if let selectedItem = primarySelectedItem {
            #if os(macOS)
            NoteEditorView(
                item: selectedItem,
                itemID: selectedItem.id,
                pastePlaintextTrigger: $pastePlaintextTrigger,
                isEditorActive: $isEditorActive,
                isEditorExpanded: $isEditorExpanded,
                passwordGeneratorTargetNoteID: $passwordGeneratorTargetNoteID,
                onCategoryAssignment: prepareSelectionForCategoryAssignment
            )
                .equatable()
                .id(selectedItem.id) // Force view recreation when switching notes
            #else
            NoteEditorView(
                item: selectedItem,
                itemID: selectedItem.id,
                isEditorActive: $isEditorActive,
                isEditorExpanded: $isEditorExpanded,
                passwordGeneratorTargetNoteID: $passwordGeneratorTargetNoteID,
                onCategoryAssignment: prepareSelectionForCategoryAssignment,
                onToggleEditorFocus: {
                    setEditorExpanded(!isEditorExpanded)
                }
            )
                .equatable()
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
    
    var body: some View {
        navigationContent
        .background {
            if isViewingTodoList {
                TodoQueryBridge { todos in
                    todoSnapshot = todos
                }
            }
        }
#if DEBUG
        .overlay(alignment: .bottomTrailing) {
            BetaTag()
                .padding(12)
        }
#endif
        #if os(macOS)
        .overlay(alignment: .bottomLeading) {
            CloudSyncStatusOverlay()
        }
        #endif
        .onAppear {
            cleanupLegacyTrashCategories()
            purgeExpiredTrash()
            #if !os(macOS)
            setupCloudKitNotifications()
            #endif
            enforceAuthenticationState()
            restoreLastSelectedNoteIfNeeded()
            disableFocusModeIfEditorIsEmpty()
            DispatchQueue.main.async {
                disableFocusModeIfEditorIsEmpty()
            }
        }
        .onDisappear {
            #if !os(macOS)
            tearDownCloudKitNotifications()
            #endif
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
            AddTodoView { draft in
                createStandaloneTodo(from: draft)
            }
            #if os(iOS)
            .presentationCompactAdaptation(.sheet)
            .presentationDetents([.height(addTodoSheetHeight)])
            .presentationDragIndicator(.visible)
            #endif
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: .toggleEditorFocusRequested)) { _ in
            guard !isViewingTodoList && !isViewingTrash else { return }
            setEditorExpanded(!isEditorExpanded)
        }
        .toolbar {
            if canExpandEditor && !isViewingTodoList && !isViewingTrash {
                ToolbarItem(
                    id: "contentView.editorFocus",
                    placement: isEditorExpanded ? .navigation : .primaryAction
                ) {
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
                allItems.contains(where: { $0.id == id })
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

            let visibleIDs = Set(filteredItems.map(\.id))

            // Trim selection to visible list items. An intentionally hidden note
            // may remain open, as may a private note during a valid unlock session.
            selectedItemIDs = Set(selectedItemIDs.filter { id in
                if visibleIDs.contains(id) {
                    return true
                }

                guard let item = allItems.first(where: { $0.id == id }) else {
                    return false
                }
                return id == offListPreservedSelectionID
                    ? !item.isInTrash && (item.category?.isPrivate != true || isAuthenticationValid)
                    : canPresentOffListSelection(item)
            })

            if let preservedID = offListPreservedSelectionID,
               visibleIDs.contains(preservedID) {
                offListPreservedSelectionID = nil
            }
            disableFocusModeIfEditorIsEmpty()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // When app becomes active, check if authentication has expired
            if newPhase == .active {
                cleanupLegacyTrashCategories()
                purgeExpiredTrash()
                enforceAuthenticationState()
                restoreLastSelectedNoteIfNeeded()
            }
        }
        .task(id: lastAuthenticationTime) {
            guard isAuthenticatedForPrivateAccess,
                  let lastAuthenticationTime else {
                return
            }

            let remaining = authenticationTimeoutInterval - Date().timeIntervalSince(lastAuthenticationTime)
            if remaining > 0 {
                try? await Task.sleep(for: .seconds(remaining))
            }
            guard !Task.isCancelled else { return }
            enforceAuthenticationState()
        }
        .onChange(of: isViewingTodoList) { _, isViewing in
            if isViewing {
                isEditorActive = false
                setEditorExpanded(false)
            } else {
                todoSnapshot = nil
                isEditorActive = primarySelectedItem != nil
            }
        }
        #if os(macOS)
        .onChange(of: isViewingTrash) { _, isViewing in
            if isViewing {
                isEditorActive = false
                setEditorExpanded(false)
            } else if !isViewingTodoList {
                isEditorActive = primarySelectedItem != nil
            }
        }
        #endif
        #if os(iOS)
        .onChange(of: isEditing) { _, editing in
            if !editing {
                selectedItemIDs.removeAll()
                selectedTodoIDs.removeAll()
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
        .confirmationDialog("Clear Completed Todos?", isPresented: $showingClearCompletedTodosConfirmation, titleVisibility: .visible) {
            Button(clearCompletedTodosButtonTitle, role: .destructive) {
                clearCompletedTodos()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(clearCompletedTodosConfirmationMessage)
        }
        .confirmationDialog("Clear Trash?", isPresented: $showingClearTrashConfirmation, titleVisibility: .visible) {
            Button("Permanently Delete \(trashItemCount) \(trashItemCount == 1 ? "Note" : "Notes")", role: .destructive) {
                emptyTrash()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes everything in Trash. This action cannot be undone.")
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
                isHiddenFromHome: false,
                warningCount: overdueTodoCount
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
                .modelContainer(JotableApp.sharedDocumentContainer)
                .tag(item.id)
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
                            selectedItemIDs = [item.id]
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
    private var openTodoListContent: some View {
        if hasHiddenPrivateTodos {
            privateTodoHiddenNotice
        }

        ForEach(filteredOpenTodos) { todo in
            todoRow(for: todo)
        }
        .onMove { offsets, destination in
            moveTodos(in: filteredOpenTodos, from: offsets, to: destination)
        }
        .onDelete { offsets in
            deleteTodos(from: filteredOpenTodos, offsets: offsets)
        }
    }

    @ViewBuilder
    private var completedTodoListContent: some View {
        ForEach(filteredCompletedTodos) { todo in
            todoRow(for: todo)
        }
        .onMove { offsets, destination in
            moveTodos(in: filteredCompletedTodos, from: offsets, to: destination)
        }
        .onDelete { offsets in
            deleteTodos(from: filteredCompletedTodos, offsets: offsets)
        }
    }

    @ViewBuilder
    private var todoListContent: some View {

        #if os(iOS)
        if !filteredOpenTodos.isEmpty {
            Section {
                if hasHiddenPrivateTodos {
                    privateTodoHiddenNotice
                }

                ForEach(filteredOpenTodos) { todo in
                    todoRow(for: todo)
                }
                .onMove { offsets, destination in
                    moveTodos(in: filteredOpenTodos, from: offsets, to: destination)
                }
                .onDelete { offsets in
                    deleteTodos(from: filteredOpenTodos, offsets: offsets)
                }
            } header: {
                todoSectionHeaderLabel("Open")
            }
        }

        if !filteredCompletedTodos.isEmpty {
            Section {
                if hasHiddenPrivateTodos && filteredOpenTodos.isEmpty {
                    privateTodoHiddenNotice
                }

                if isCompletedTodoSectionExpanded {
                    ForEach(filteredCompletedTodos) { todo in
                        todoRow(for: todo)
                    }
                    .onMove { offsets, destination in
                        moveTodos(in: filteredCompletedTodos, from: offsets, to: destination)
                    }
                    .onDelete { offsets in
                        deleteTodos(from: filteredCompletedTodos, offsets: offsets)
                    }
                }
            } header: {
                completedTodoSectionHeader(isFirstSection: filteredOpenTodos.isEmpty)
            }
        }
        #else
        openTodoListContent
        #endif
    }

    private var privateTodoHiddenNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock")
                .font(.caption)
                .frame(width: 18, height: 18)

            Text(privateTodoHiddenMessage)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        #if os(iOS)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .listRowInsets(EdgeInsets(top: 2, leading: 20, bottom: 6, trailing: 20))
        .listRowSeparator(.hidden)
        #else
        .padding(.vertical, 4)
        .listRowSeparator(.hidden)
        #endif
    }

    private func todoSectionHeaderLabel(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            #if os(iOS)
            .foregroundStyle(Color.primary.opacity(0.72))
            #else
            .foregroundStyle(.secondary)
            #endif
            .textCase(nil)
    }

    private func todoSectionHeader(_ title: String, isFirstSection: Bool) -> some View {
        todoSectionHeaderLabel(title)
            .padding(.top, isFirstSection ? 0 : 16)
            .padding(.bottom, 4)
            .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private func completedTodoSectionHeader(isFirstSection: Bool) -> some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isCompletedTodoSectionExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isCompletedTodoSectionExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .frame(width: 12)
                    todoSectionHeaderLabel("Completed")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isCompletedTodoSectionExpanded ? "Collapse completed todos" : "Expand completed todos")

            Spacer(minLength: 8)

            Button {
                showingClearCompletedTodosConfirmation = true
            } label: {
                Label("Clear", systemImage: "trash")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.red)
            .accessibilityLabel("Clear completed todos")
            .help("Clear completed todos")
        }
        #if os(macOS)
        .padding(.top, isFirstSection ? 0 : 16)
        .padding(.bottom, 4)
        .listRowSeparator(.hidden)
        #endif
    }

    private func todoRow(for todo: TodoItem) -> some View {
        let row = TodoRowView(
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
            updateMetadata: { dueDate, priority in
                updateTodoMetadata(todo, dueDate: dueDate, priority: priority)
            },
            openSource: {
                openSourceNote(for: todo)
            }
        )

        #if os(iOS)
        return row
            .tag(todo.id)
        #else
        return row
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
        #endif
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
        todo.sourceNoteID.isEmpty
    }

    private func isPrivateTodo(_ todo: TodoItem) -> Bool {
        linkedSourceNote(for: todo)?.category?.isPrivate == true
    }

    private func createStandaloneTodo(from draft: StandaloneTodoDraft) {
        let todoText = normalizedStandaloneTodoText(from: draft.text)
        guard !todoText.isEmpty else { return }

        let todo = TodoItem(
            text: todoText,
            sourceText: "",
            sourceNote: nil,
            sortOrder: nextTodoSortOrder(),
            dueDate: normalizedDueDate(draft.dueDate),
            priority: draft.priority
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

    private func fillTodosForDebug() {
        let now = Date()
        let calendar = Calendar.current
        let openTodoSeeds = [
            "Review launch checklist",
            "Follow up on onboarding notes",
            "Draft customer recap",
            "Confirm release owner",
            "Clean up meeting action items",
            "Check dashboard numbers",
            "Write QA handoff",
            "Prepare hiring feedback",
            "Update roadmap notes",
            "Send pricing answer"
        ]
        let completedTodoSeeds = [
            "Archived sprint notes",
            "Closed support follow-up",
            "Resolved copy review",
            "Filed analytics summary",
            "Sent design feedback",
            "Updated account notes",
            "Finished weekly planning",
            "Logged customer request",
            "Reviewed changelog",
            "Closed release task"
        ]
        let openDueOffsets = [-3, -1, 0, 1, 2, 5, 7, 14]
        let completedDueOffsets = [-21, -14, -7, -3, -1, 0, 2]
        let startingSortOrder = nextTodoSortOrder() + 50

        for index in 1...25 {
            let todo = TodoItem(
                text: "\(openTodoSeeds.randomElement() ?? "Debug open todo") #\(index)",
                sourceText: "",
                sourceNote: nil
            )
            todo.createdAt = now.addingTimeInterval(TimeInterval(-index))
            todo.updatedAt = todo.createdAt
            todo.sortOrder = startingSortOrder - index
            todo.priority = TodoPriority.allCases.randomElement() ?? .normal
            if index % 3 != 0,
               let dueDate = calendar.date(byAdding: .day, value: openDueOffsets.randomElement() ?? 0, to: now) {
                todo.dueDate = calendar.startOfDay(for: dueDate)
            }
            todo.isSourceTextAvailable = false
            modelContext.insert(todo)
        }

        for index in 1...25 {
            let todo = TodoItem(
                text: "\(completedTodoSeeds.randomElement() ?? "Debug completed todo") #\(index)",
                sourceText: "",
                sourceNote: nil
            )
            todo.createdAt = now.addingTimeInterval(TimeInterval(-(index + 25)))
            todo.updatedAt = todo.createdAt
            todo.sortOrder = startingSortOrder - 25 - index
            todo.priority = TodoPriority.allCases.randomElement() ?? .normal
            if index % 4 != 0,
               let dueDate = calendar.date(byAdding: .day, value: completedDueOffsets.randomElement() ?? 0, to: now) {
                todo.dueDate = calendar.startOfDay(for: dueDate)
            }
            todo.isCompleted = true
            todo.completedAt = now.addingTimeInterval(TimeInterval(-index))
            todo.isSourceTextAvailable = false
            modelContext.insert(todo)
        }

        do {
            try modelContext.save()
            isCompletedTodoSectionExpanded = true
            sidebarSelection = .todoList
            print("💾 Filled debug todos - CloudKit sync queued")
        } catch {
            print("❌ Failed to fill debug todos: \(error)")
        }
    }

    private func normalizedStandaloneTodoText(from text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func nextTodoSortOrder() -> Int {
        (allTodos.map(\.sortOrder).max() ?? 0) + 1
    }

    private func normalizedDueDate(_ dueDate: Date?) -> Date? {
        dueDate.map { Calendar.current.startOfDay(for: $0) }
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

    private func updateTodoMetadata(_ todo: TodoItem, dueDate: Date?, priority: TodoPriority) {
        let normalizedDate = normalizedDueDate(dueDate)
        guard todo.dueDate != normalizedDate || todo.priority != priority else { return }

        todo.dueDate = normalizedDate
        todo.priority = priority
        todo.updatedAt = Date()

        do {
            try modelContext.save()
            print("💾 Todo metadata updated - CloudKit sync queued")
        } catch {
            print("❌ Failed to update todo metadata: \(error)")
        }
    }

    private func sourceNote(for todo: TodoItem) -> Item? {
        guard let note = linkedSourceNote(for: todo), !note.isInTrash else {
            return nil
        }

        return note
    }

    private func linkedSourceNote(for todo: TodoItem) -> Item? {
        guard !todo.sourceNoteID.isEmpty else { return nil }
        return allItems.first { $0.id.uuidString == todo.sourceNoteID }
    }

    private func sourceTitle(for todo: TodoItem) -> String {
        if isStandaloneTodo(todo) {
            return ""
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

        guard canAccessNoteFromTodoList(note) else {
            authenticateWithBiometrics(reason: "Authenticate to access this private note") { success in
                guard success else { return }
                self.beginPrivateAccessSession()
                self.openSourceNoteAfterAccessCheck(note)
            }
            return
        }

        openSourceNoteAfterAccessCheck(note)
    }

    private func unlockPrivateTodos() {
        authenticateWithBiometrics(reason: "Authenticate to show private todos") { success in
            guard success else { return }
            self.beginPrivateAccessSession()
        }
    }

    private func canAccessNoteFromTodoList(_ note: Item) -> Bool {
        guard note.category?.isPrivate == true else { return true }
        return isAuthenticationValid
    }

    private func openSourceNoteAfterAccessCheck(_ note: Item) {
        #if os(iOS)
        if shouldPushTodoSourceInTodoList {
            selectedItemIDs.removeAll()
            offListPreservedSelectionID = nil
            lastSelectedNoteID = ""
            isEditorActive = true
            todoSourceNavigationPath = [note.id]
            return
        }

        if UIDevice.current.userInterfaceIdiom == .phone {
            splitViewVisibility = .detailOnly
        }
        #endif

        // Leaving the dedicated Todo workspace is intentional: source-note
        // actions return to the note's category (or All Notes) and open it in
        // the normal browser/editor workspace.
        searchText = ""
        if let category = note.category, !category.isSystemTrash {
            sidebarSelection = .category(category)
        } else {
            sidebarSelection = .allNotes
        }
        selectedItemIDs = [note.id]
        lastSelectedNoteID = note.id.uuidString
        isEditorActive = true
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

    #if os(iOS)
    private func deleteSelectedTodos() {
        let todosToDelete = filteredTodos.filter { selectedTodoIDs.contains($0.id) }
        guard !todosToDelete.isEmpty else { return }

        for todo in todosToDelete {
            modelContext.delete(todo)
        }
        selectedTodoIDs.removeAll()

        do {
            try modelContext.save()
            print("💾 Deleted \(todosToDelete.count) selected todos - CloudKit sync queued")
        } catch {
            print("❌ Failed to delete selected todos: \(error)")
        }
    }
    #endif

    private func deleteTodos(from todos: [TodoItem], offsets: IndexSet) {
        let todosToDelete = offsets.map { todos[$0] }
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

    private func clearCompletedTodos() {
        let todosToDelete = filteredCompletedTodos
        guard !todosToDelete.isEmpty else { return }

        for todo in todosToDelete {
            modelContext.delete(todo)
        }

        do {
            try modelContext.save()
            print("💾 Cleared \(todosToDelete.count) completed todos - CloudKit sync queued")
        } catch {
            print("❌ Failed to clear completed todos: \(error)")
        }
    }

    private func deleteTodosLinked(to item: Item) {
        for todo in allTodos where todo.sourceNoteID == item.id.uuidString {
            modelContext.delete(todo)
        }
    }

    private func deleteSelectedItems() {
        let itemsToProcess = filteredItems.filter { selectedItemIDs.contains($0.id) }
        guard !itemsToProcess.isEmpty else { return }

        if isViewingTrash {
            permanentlyDeleteItems(itemsToProcess)
        } else {
            moveItemsToTrash(itemsToProcess)
        }
    }

    #if os(iOS)
    private func selectAllItems() {
        selectedItemIDs = Set(filteredItems.map(\.id))
    }

    private func deselectAllItems() {
        selectedItemIDs.removeAll()
    }

    private var allFilteredItemsSelected: Bool {
        guard !filteredItems.isEmpty else { return false }
        let selectedIDs = selectedItemIDs
        return filteredItems.count == selectedIDs.count
            && filteredItems.allSatisfy { selectedIDs.contains($0.id) }
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

    private func moveTodos(in todos: [TodoItem], from source: IndexSet, to destination: Int) {
        var reorderedTodos = Array(todos)
        reorderedTodos.move(fromOffsets: source, toOffset: destination)

        let topSortOrder = max(reorderedTodos.count, allTodos.map(\.sortOrder).max() ?? 0)
        for (index, todo) in reorderedTodos.enumerated() {
            todo.sortOrder = topSortOrder - index
            todo.updatedAt = Date()
        }

        do {
            try modelContext.save()
            print("💾 Todos reordered successfully - CloudKit sync queued")
        } catch {
            print("❌ Failed to save reordered todos: \(error)")
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

            // Cancellation is an expected way to dismiss the system prompt,
            // not an authentication error that needs a second alert.
            if let laError = error as? LAError,
               [.userCancel, .systemCancel, .appCancel].contains(laError.code) {
                DispatchQueue.main.async {
                    unsafeCompletion(false)
                }
                return
            }

            let errorMessage: String
            if let laError = error as? LAError {
                switch laError.code {
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
        if isViewingTrash || isViewingTodoList {
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

        // A note and its document are one logical object even though their
        // persistence is split across stores. Insert the document first so a
        // newly rendered row can query its empty body immediately.
        let documentContext = JotableApp.sharedDocumentContainer.mainContext
        let newDocument = NoteDocument(
            noteID: newItem.id.uuidString,
            plainText: content,
            attributedContent: attributedContent,
            updatedAt: newItem.timestamp
        )
        documentContext.insert(newDocument)
        modelContext.insert(newItem)

        do {
            try modelContext.save()
        } catch {
            documentContext.delete(newDocument)
            print("❌ Failed to save new item: \(error)")
            return nil
        }

        do {
            try documentContext.save()
        } catch {
            // The editor can recreate the document from Item's fallback fields.
            print("❌ Failed to save new note document: \(error)")
        }

        print("💾 New item created and saved - CloudKit sync queued")
        // Set selection immediately
        selectedItemIDs = [newItem.id]
        return newItem
    }

    private func addItem() {
        _ = createItem()
    }

    #if DEBUG
    private func createLegacySyncTestNotes() {
        guard JotableApp.isLegacySyncTestMode else { return }
        let category = Category(name: "Legacy Sync Test \(debugBatchName())")
        modelContext.insert(category)
        let oldDate = Date(timeIntervalSinceNow: -30 * 24 * 60 * 60)
        let samples: [(String, String, Bool)] = [
            ("Legacy plain text", "Original old-format plain text. Edit this body on Mac, then open it on iOS.", false),
            ("Legacy rich text", "Original old-format rich text. Edit this body on iOS, then open it on Mac.", true),
            ("Legacy large body", String(repeating: "Legacy content with formatting and multiple lines.\n", count: 4_000), true)
        ]
        for (title, content, rich) in samples {
            let note = Item(timestamp: oldDate, title: title, content: content)
            note.createdAt = oldDate
            note.category = category
            if rich {
                let text = NSMutableAttributedString(attributedString: defaultAttributedContent(for: content))
                text.addAttribute(.underlineStyle, value: 1, range: NSRange(location: 0, length: min(8, text.length)))
                note.attributedContent = archiveDefaultAttributedContent(text)
            }
            // Deliberately insert Item only, exactly as pre-split notes were
            // stored. Do not use createItem(), which creates a NoteDocument.
            modelContext.insert(note)
        }
        saveDebugSeedData(successMessage: "Created legacy sync test notes (Item only)") {
            sidebarSelection = .category(category)
        }
    }

    private func createDebugCategories() {
        let createdCategories = makeDebugCategories(
            count: Int.random(in: 3...6),
            prefix: "Debug"
        )

        saveDebugSeedData(successMessage: "Created debug categories") {
            if let firstCategory = createdCategories.first {
                sidebarSelection = .category(firstCategory)
            }
        }
    }

    private func createDebugNotes() {
        let notes = makeDebugNotes(
            count: Int.random(in: 8...14),
            category: selectedCategory
        )

        saveDebugSeedData(successMessage: "Created debug notes") {
            if let firstNote = notes.first {
                selectedItemIDs = [firstNote.id]
            }
        }
    }

    private func createDebugCategoriesWithNotes() {
        let createdCategories = makeDebugCategories(
            count: Int.random(in: 3...5),
            prefix: "Debug Filled"
        )
        var firstNote: Item?

        for category in createdCategories {
            let notes = makeDebugNotes(
                count: Int.random(in: 4...9),
                category: category
            )
            firstNote = firstNote ?? notes.first
        }

        saveDebugSeedData(successMessage: "Created debug categories with notes") {
            if let firstCategory = createdCategories.first {
                sidebarSelection = .category(firstCategory)
            }
            if let firstNote {
                selectedItemIDs = [firstNote.id]
            }
        }
    }

    private func makeDebugCategories(count: Int, prefix: String) -> [Category] {
        let batchName = debugBatchName()
        let categorySeeds: [(name: String, color: String)] = [
            ("1:1s", "blue"),
            ("Hiring Loop", "green"),
            ("Product Ideas", "orange"),
            ("Release Prep", "purple"),
            ("Customer Calls", "pink"),
            ("Operations", "teal"),
            ("Research", "mint"),
            ("Personal Admin", "yellow"),
            ("Bug Triage", "red"),
            ("Reading List", "brown")
        ]
        let selectedSeeds = categorySeeds.shuffled().prefix(count)
        let nextSortOrder = ((categories.map(\.sortOrder).max() ?? -1) + 1)

        return selectedSeeds.enumerated().map { index, seed in
            let category = Category(
                name: "\(prefix) \(seed.name) \(batchName)",
                color: seed.color,
                sortOrder: nextSortOrder + index
            )
            modelContext.insert(category)
            return category
        }
    }

    private func makeDebugNotes(
        count: Int,
        category: Category?
    ) -> [Item] {
        let now = Date()
        let categoryName = category?.name

        return (1...count).map { index in
            let title = debugNoteTitle(index: index, categoryName: categoryName)
            let content = debugNoteContent(index: index, title: title, categoryName: categoryName)
            let note = Item(title: title, content: content)
            note.category = category
            note.createdAt = now.addingTimeInterval(-TimeInterval.random(in: 60...2_592_000))
            note.timestamp = note.createdAt
            note.attributedContent = archiveDefaultAttributedContent(defaultAttributedContent(for: content))
            modelContext.insert(note)
            return note
        }
    }

    private func debugBatchName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private func debugNoteTitle(index: Int, categoryName: String?) -> String {
        let subjects = [
            "Avery follow-up",
            "Launch checklist",
            "Hiring debrief",
            "Customer call",
            "Onboarding plan",
            "Incident review",
            "Roadmap pass",
            "Budget notes",
            "Design critique",
            "Weekly planning",
            "API cleanup",
            "Store listing",
            "Retention ideas",
            "Metrics review",
            "Support queue"
        ]
        let formats = [
            "\(subjects.randomElement() ?? "Debug note")",
            "\(subjects.randomElement() ?? "Debug note") - next steps",
            "\(subjects.randomElement() ?? "Debug note") / draft",
            "Follow up: \(subjects.randomElement() ?? "debug note")",
            "Notes from \(subjects.randomElement() ?? "debug note")"
        ]

        if let categoryName, Bool.random() {
            return "\(formats.randomElement() ?? "Debug note") (\(categoryName))"
        }

        return formats.randomElement() ?? "Debug note \(index)"
    }

    private func debugNoteContent(index: Int, title: String, categoryName: String?) -> String {
        let owners = ["Avery", "Morgan", "Riley", "Jordan", "Casey", "Taylor", "Sam", "Quinn"]
        let statuses = ["Open", "Waiting", "Blocked", "Ready for review", "Needs a second pass", "Parked"]
        let nextSteps = [
            "Confirm the owner before Friday",
            "Move the notes into the right category",
            "Turn the rough bullets into todos",
            "Send a short recap",
            "Check whether this belongs in the roadmap",
            "Compare against the last customer conversation",
            "Add screenshots when testing on iOS",
            "Validate the edge case on macOS"
        ].shuffled()
        let observations = [
            "The interesting part is the handoff between notes and todos.",
            "There is enough detail here to test search, previews, and sorting.",
            "This should look different from the surrounding generated notes.",
            "The title is intentionally not date-shaped so list scanning feels real.",
            "Some lines are short while others have enough length to wrap in compact views."
        ]
        let context = categoryName.map { "Category: \($0)" } ?? "Uncategorized debug note"
        let owner = owners.randomElement() ?? "Avery"
        let status = statuses.randomElement() ?? "Open"
        let pickedSteps = nextSteps.prefix(Int.random(in: 2...4))

        return """
        \(title)

        \(context)
        Owner: \(owner)
        Status: \(status)

        \(observations.randomElement() ?? "Generated note body.")

        \(pickedSteps.map { "- \($0)" }.joined(separator: "\n"))

        Reference: debug seed \(index)-\(Int.random(in: 100...999))
        """
    }

    private func saveDebugSeedData(successMessage: String, afterSave: () -> Void = {}) {
        do {
            try modelContext.save()
            afterSave()
            print("\(successMessage) - CloudKit sync queued")
        } catch {
            print("Failed to seed debug data: \(error)")
        }
    }

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
            selectedItemIDs = [note.id]
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
              selectedItemIDs.contains(item.id) else {
            return
        }

        if categoryIsHiddenFromAllNotes(category) {
            offListPreservedSelectionID = item.id
        } else {
            offListPreservedSelectionID = nil
        }
    }

    private func categoryIsHiddenFromAllNotes(_ category: Category?) -> Bool {
        guard let category else { return false }
        return category.isPrivate || category.isHiddenFromHome
    }

    private func restoreLastSelectedNoteIfNeeded() {
        guard !isViewingTodoList,
              selectedItemIDs.isEmpty,
              !lastSelectedNoteID.isEmpty else { return }

        guard let match = allItems.first(where: {
            $0.id.uuidString == lastSelectedNoteID && !$0.isInTrash
        }) else { return }

        guard filteredItems.contains(where: { $0.id == match.id }) ||
                canPresentOffListSelection(match) else {
            return
        }

        if !filteredItems.contains(where: { $0.id == match.id }) {
            offListPreservedSelectionID = match.id
        }
        selectedItemIDs = [match.id]
    }

    private func persistSidebarDestination(_ selection: SidebarSelection?) {
        switch selection {
        case .todoList:
            lastSidebarDestination = RestorableSidebarDestination.todoList.rawValue
        case .allNotes, .category, .trash:
            // Trash is intentionally temporary. Categories continue to reopen
            // through their selected note, while the stable fallback is All Notes.
            lastSidebarDestination = RestorableSidebarDestination.allNotes.rawValue
        case .none:
            break
        }
    }

    private func beginPrivateAccessSession() {
        isAuthenticatedForPrivateAccess = true
        lastAuthenticationTime = Date()
    }

    /// Relock private content without affecting an ordinary hidden note. This
    /// runs both when the scene becomes active and when the five-minute session
    /// timer expires while the app remains open.
    private func enforceAuthenticationState() {
        guard !isAuthenticationValid else { return }

        isAuthenticatedForPrivateAccess = false
        lastAuthenticationTime = nil

        let selectedPrivateNote = selectedItemIDs.contains { selectedID in
            allItems.contains { $0.id == selectedID && $0.category?.isPrivate == true }
        }
        let storedPrivateNote = allItems.contains {
            $0.id.uuidString == lastSelectedNoteID && $0.category?.isPrivate == true
        }
        let isViewingPrivateCategory: Bool
        if case .category(let category) = sidebarSelection {
            isViewingPrivateCategory = category.isPrivate
        } else {
            isViewingPrivateCategory = false
        }

        guard selectedPrivateNote || storedPrivateNote || isViewingPrivateCategory else {
            return
        }

        sidebarSelection = .allNotes
        selectedItemIDs.removeAll()
        offListPreservedSelectionID = nil
        lastSelectedNoteID = ""
        setEditorExpanded(false)
    }

    #if !os(macOS)
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
    #endif

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

        if selectedItemIDs.contains(item.id) {
            selectedItemIDs.remove(item.id)
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
        if selectedItemIDs.contains(item.id) {
            selectedItemIDs.remove(item.id)
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
            if selectedItemIDs.contains(item.id) {
                selectedItemIDs.remove(item.id)
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
    let selectedItemIDs: Set<UUID>
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
    var warningCount: Int = 0

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

            if warningCount > 0 {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("\(warningCount) overdue \(warningCount == 1 ? "todo" : "todos")")
                    .help("\(warningCount) overdue \(warningCount == 1 ? "todo" : "todos")")
            }

            Text("\(count)")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .contentShape(Rectangle())
    }
}

struct TodoRowView: View {
    #if os(iOS)
    @Environment(\.editMode) private var editMode
    #endif

    let todo: TodoItem
    let sourceTitle: String
    let sourceCategoryName: String?
    let isLinkedToNote: Bool
    let sourceTextAvailable: Bool
    let canOpenSource: Bool
    let toggleCompletion: () -> Void
    let updateText: (String) -> String
    let updateMetadata: (Date?, TodoPriority) -> Void
    let openSource: () -> Void

    @State private var draftText = ""
    @State private var hasDueDate = false
    @State private var draftDueDate = Date()
    @State private var draftPriority: TodoPriority = .normal
    @State private var isInfoPresented = false
    @State private var isEditingText = false
    @State private var originalText = ""
    @FocusState private var isTextFocused: Bool

    private var sourceLabel: String {
        let title = sourceTextAvailable ? sourceTitle : "\(sourceTitle) - source text removed"
        if let sourceCategoryName {
            return "\(sourceCategoryName) • \(title)"
        }
        return title
    }

    private var sourceIcon: String {
        return canOpenSource ? "arrow.up.forward.square" : "exclamationmark.triangle"
    }

    private var sourceHelp: String {
        if canOpenSource {
            return "Open source note"
        }

        return isLinkedToNote ? "Source note is unavailable" : "Edit todo"
    }

    @ViewBuilder
    private var titleContent: some View {
        if isLinkedToNote {
            Text(todo.text)
                .font(.body)
                .foregroundStyle(todo.isCompleted ? .secondary : .primary)
                .strikethrough(todo.isCompleted)
                .lineLimit(3)
        } else if isEditingText {
            TextField("Todo", text: $draftText, axis: .vertical)
                .font(.body)
                .foregroundStyle(todo.isCompleted ? .secondary : .primary)
                .strikethrough(todo.isCompleted)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)
                .focused($isTextFocused)
                .onSubmit {
                    finishStandaloneEdit()
                }
                .onChange(of: isTextFocused) { _, isFocused in
                    if !isFocused && isEditingText {
                        finishStandaloneEdit()
                    }
                }
                #if os(macOS)
                .background {
                    MacClickOutsideMonitor {
                        finishStandaloneEdit()
                    }
                }
                .onExitCommand {
                    cancelStandaloneEdit()
                }
                #endif
        } else {
            Text(todo.text)
                .font(.body)
                .foregroundStyle(todo.isCompleted ? .secondary : .primary)
                .strikethrough(todo.isCompleted)
                .lineLimit(3)
                #if os(macOS)
                .onTapGesture(count: 2) {
                    beginStandaloneEdit()
                }
                .help("Double-click to edit")
                #endif
        }
    }

    @ViewBuilder
    private var metadataContent: some View {
        if todo.priority != .normal || todo.dueDate != nil {
            HStack(spacing: 8) {
                if todo.priority != .normal {
                    Label(todo.priority.title, systemImage: priorityIcon(for: todo.priority))
                        .foregroundStyle(priorityColor(for: todo.priority))
                }

                if let dueDate = todo.dueDate {
                    Label(dueDateLabel(for: dueDate), systemImage: "calendar")
                        .foregroundStyle(dueDateColor(for: dueDate))
                }
            }
            .font(.caption)
        }
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                titleContent
                metadataContent

                if isLinkedToNote {
                    HStack(spacing: 4) {
                        Image(systemName: sourceIcon)
                            .font(.caption)
                        Text(sourceLabel)
                            .lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundStyle(canOpenSource ? .secondary : .tertiary)
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var infoButton: some View {
        Button {
            if isInfoPresented {
                isInfoPresented = false
            } else {
                presentTodoDetails()
            }
        } label: {
            Image(systemName: "info.circle")
                .font(.body)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Todo details")
        .help("Show todo details")
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
        todo.completedAt == nil ? 340 : 390
    }

    private var todoInfoPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Todo Details")
                .font(.headline)

            if !isLinkedToNote {
                TextField("Todo", text: $draftText, axis: .vertical)
                    .lineLimit(1...3)
                    #if os(iOS)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.sentences)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .overlay {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(.secondary.opacity(0.28), lineWidth: 0.5)
                    }
                    #else
                    .textFieldStyle(.roundedBorder)
                    #endif

                Divider()
            }

            VStack(alignment: .leading, spacing: 10) {
                Picker("Priority", selection: $draftPriority) {
                    ForEach(TodoPriority.allCases) { priority in
                        Text(priority.title).tag(priority)
                    }
                }
                .pickerStyle(.segmented)

                #if os(macOS)
                SettingsRow("Due Date") {
                    Toggle("", isOn: $hasDueDate)
                        .toggleStyle(.switch)
                }
                #else
                Toggle("Due Date", isOn: $hasDueDate)
                #endif

                if hasDueDate {
                    DatePicker("Due", selection: $draftDueDate, displayedComponents: .date)
                        #if os(macOS)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(.separator.opacity(0.55), lineWidth: 0.5)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 4)
                        #else
                        .datePickerStyle(.compact)
                        #endif
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                dateRow(title: "Created", date: todo.createdAt)

                if let dueDate = todo.dueDate {
                    dateRow(title: "Due", date: dueDate, includesTime: false)
                }

                if let completedAt = todo.completedAt {
                    dateRow(title: "Completed", date: completedAt)
                }
            }
        }
        .padding(16)
        #if os(iOS)
        .frame(maxWidth: .infinity, alignment: .leading)
        #else
        .frame(minWidth: 320, alignment: .leading)
        #endif
    }

    private func dateRow(title: String, date: Date, includesTime: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(formattedDate(date, includesTime: includesTime))
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formattedDate(_ date: Date, includesTime: Bool = true) -> String {
        if includesTime {
            return date.formatted(date: .abbreviated, time: .shortened)
        }

        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func priorityIcon(for priority: TodoPriority) -> String {
        switch priority {
        case .low: "arrow.down.circle"
        case .normal: "minus.circle"
        case .high: "exclamationmark.circle.fill"
        }
    }

    private func priorityColor(for priority: TodoPriority) -> Color {
        switch priority {
        case .low: .secondary
        case .normal: .secondary
        case .high: .red
        }
    }

    private func dueDateLabel(for dueDate: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(dueDate) {
            return "Today"
        }
        if calendar.isDateInTomorrow(dueDate) {
            return "Tomorrow"
        }
        if !todo.isCompleted && dueDate < calendar.startOfDay(for: Date()) {
            return "Overdue"
        }
        return dueDate.formatted(date: .abbreviated, time: .omitted)
    }

    private func dueDateColor(for dueDate: Date) -> Color {
        let calendar = Calendar.current
        if !todo.isCompleted && dueDate < calendar.startOfDay(for: Date()) {
            return .red
        }
        if calendar.isDateInToday(dueDate) {
            return .orange
        }
        return .secondary
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
                    #if os(iOS)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if editMode?.wrappedValue.isEditing != true {
                            presentTodoDetails()
                        }
                    }
                    #endif
            }

            infoButton
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onAppear {
            draftText = todo.text
            syncMetadataDrafts()
        }
        .onChange(of: todo.text) { _, newValue in
            if !isTextFocused {
                draftText = newValue
            }
        }
        .onChange(of: todo.dueDate) { _, _ in
            syncMetadataDrafts()
        }
        .onChange(of: todo.priorityRawValue) { _, _ in
            syncMetadataDrafts()
        }
        .onChange(of: hasDueDate) { _, _ in
            commitMetadataEdit()
        }
        .onChange(of: draftDueDate) { _, _ in
            guard hasDueDate else { return }
            commitMetadataEdit()
        }
        .onChange(of: draftPriority) { _, _ in
            commitMetadataEdit()
        }
        .onChange(of: isInfoPresented) { _, isPresented in
            if !isPresented {
                commitStandaloneEdit()
            }
        }
    }

    private func beginStandaloneEdit() {
        guard !isLinkedToNote else { return }
        originalText = todo.text
        draftText = todo.text
        isEditingText = true
        DispatchQueue.main.async {
            isTextFocused = true
        }
    }

    private func presentTodoDetails() {
        syncMetadataDrafts()
        draftText = todo.text
        isInfoPresented = true
    }

    private func finishStandaloneEdit() {
        guard isEditingText else { return }
        commitStandaloneEdit()
        isEditingText = false
        isTextFocused = false
    }

    private func cancelStandaloneEdit() {
        guard isEditingText else { return }
        draftText = originalText
        isEditingText = false
        isTextFocused = false
    }

    private func commitStandaloneEdit() {
        guard !isLinkedToNote else { return }

        let savedText = updateText(draftText)
        if draftText != savedText {
            draftText = savedText
        }
    }

    private func syncMetadataDrafts() {
        draftDueDate = todo.dueDate ?? Date()
        draftPriority = todo.priority
        hasDueDate = todo.dueDate != nil
    }

    private func commitMetadataEdit() {
        guard isInfoPresented else { return }
        updateMetadata(hasDueDate ? draftDueDate : nil, draftPriority)
    }
}

struct NoteRowView: View {
    let item: Item
    let isTrashContext: Bool
    @Query private var documents: [NoteDocument]
    private let attachmentPreviewToken = "Image"
    private let trashRetentionDays = 30

    init(item: Item, isTrashContext: Bool) {
        self.item = item
        self.isTrashContext = isTrashContext

        let noteID = item.id.uuidString
        _documents = Query(
            filter: #Predicate<NoteDocument> { document in
                document.noteID == noteID
            },
            sort: [SortDescriptor(\NoteDocument.updatedAt, order: .reverse)]
        )

    }

    private var document: NoteDocument? {
        NoteDocumentStore.latest(in: documents)
    }

    private var bodyText: String {
        document?.plainText ?? item.content
    }

    private var modifiedAt: Date {
        document?.updatedAt ?? item.timestamp
    }
    
    private var previewText: String? {
        let normalized = bodyText.replacingOccurrences(
            of: "\u{FFFC}+",
            with: attachmentPreviewToken,
            options: .regularExpression
        )
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        // Use the first non-empty line to avoid blank previews when the note starts with newlines
        let firstNonEmptyLine = trimmed
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        
        return firstNonEmptyLine ?? trimmed
    }

    private var preview: some View {
        ZStack(alignment: .leading) {
            Text("Start writing...")
                .foregroundStyle(.secondary.opacity(0.65))
                .opacity(previewText == nil ? 1 : 0)

            Text(previewText ?? "Start writing...")
                .foregroundStyle(.secondary)
                .opacity(previewText == nil ? 0 : 1)
        }
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
                    Text(modifiedAt, format: .relative(presentation: .named))
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
            
            preview
                .font(.subheadline)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)

            if isTrashContext, let trashDeletionDateText {
                Text(trashDeletionDateText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(minHeight: 48, alignment: .top)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .id(item.id)
    }
}

private struct TodoQueryBridge: View {
    @Query(sort: \TodoItem.createdAt, order: .reverse) private var todos: [TodoItem]
    let update: ([TodoItem]) -> Void

    private var revision: String {
        todos.map { todo in
            [
                todo.id.uuidString,
                todo.text,
                todo.updatedAt.timeIntervalSinceReferenceDate.description,
                todo.isCompleted.description,
                todo.sortOrder.description,
                todo.sourceNoteID,
                todo.isSourceTextAvailable.description
            ].joined(separator: ":")
        }
        .joined(separator: "|")
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                update(todos)
            }
            .onChange(of: revision) { _, _ in
                update(todos)
            }
    }
}

#if os(macOS)
// CloudKit events are intentionally observed below ContentView's state boundary.
// Sync-status changes should update this overlay, not the window toolbar hierarchy.
private struct CloudSyncStatusOverlay: View {
    private enum BadgeState: Equatable {
        case idle, syncing, interrupted
    }

    @State private var status = CloudSyncStatus.shared
    @State private var presentation: BadgeState = .idle
    @State private var showingDetails = false
    @State private var isHovered = false

    private var requestedState: BadgeState {
        if status.isBusy { return .syncing }
        if status.hasFailure { return .interrupted }
        return .idle
    }

    private var indicatorColor: Color {
        switch presentation {
        case .idle: .secondary
        case .syncing: .accentColor
        case .interrupted: .orange
        }
    }

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .overlay(alignment: .bottomLeading) {
                // Keep one recognizable button; details are shown on demand.
                Button {
                    showingDetails.toggle()
                } label: {
                    Image(systemName: "icloud")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(indicatorColor)
                        .frame(width: 32, height: 24)
                        .padding(8)
                        .background(Color.primary.opacity(isHovered ? 0.10 : 0.04), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .onHover { isHovered = $0 }
                .help(Text("\(status.message)\nClick for details"))
                .accessibilityIdentifier("icloud-sync-status")
                .accessibilityLabel("iCloud sync status")
                .accessibilityValue(status.message)
                .accessibilityHint("Show sync details")
                .popover(isPresented: $showingDetails, arrowEdge: .bottom) {
                    CloudSyncDetails(status: status)
                }
                .padding(16)
            }
            .task(id: requestedState) {
                let target = requestedState
                do {
                    switch target {
                    case .syncing:
                        break
                    case .interrupted:
                        // Give automatic retries time to recover before warning.
                        try await Task.sleep(for: .seconds(5))
                    case .idle:
                        // Coalesce short gaps before returning to the quiet cloud.
                        try await Task.sleep(for: .milliseconds(1200))
                    }
                } catch {
                    return
                }
                guard !Task.isCancelled, requestedState == target else { return }
                presentation = target
            }
    }
}

private struct CloudSyncDetails: View {
    let status: CloudSyncStatus

    private var explanation: LocalizedStringKey {
        if status.isConnecting {
            return "Preparing the connection used to sync your notes."
        }
        if status.isBusy {
            return "Sending or receiving changes to your notes."
        }
        if status.hasFailure {
            return "iCloud couldn’t finish the last sync attempt. Some changes may not be available on your other devices yet."
        }
        return "No uploads or downloads are currently in progress."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("iCloud Sync", systemImage: "icloud")
                .font(.headline)
            Text(status.message)
                .font(.subheadline.weight(.medium))
            Text(explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if status.hasFailure && status.isBusy {
                Text("An earlier sync attempt was interrupted.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .frame(width: 280, alignment: .leading)
    }
}
#endif

private struct CloudSyncToolbarIndicator: View {
    var isActive = true
    var hasFailure = false
    var isIdle = false
    var message = String(localized: "Syncing with iCloud")

    #if os(macOS)
    @State private var isRotating = false
    #endif

    var body: some View {
        Group {
            #if os(macOS)
            Image(systemName: hasFailure ? "exclamationmark.icloud" : (isIdle ? "icloud" : "arrow.triangle.2.circlepath"))
                .foregroundStyle(hasFailure ? Color.orange : (isIdle ? Color.secondary : Color.primary))
                .font(.system(size: 17, weight: .medium))
                .rotationEffect(.degrees(isRotating ? 360 : 0))
                .frame(width: 24, height: 24, alignment: .center)
                .padding(.horizontal, 4)
                .onAppear {
                    updateRotation(isActive: isActive)
                }
                .onChange(of: isActive) { _, newValue in
                    updateRotation(isActive: newValue)
                }
            #else
            ProgressView()
                .progressViewStyle(.circular)
            #endif
        }
        .help(message)
        .accessibilityLabel(message)
    }

    #if os(macOS)
    private func updateRotation(isActive: Bool) {
        if isActive {
            guard !isRotating else { return }
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                isRotating = true
            }
        } else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isRotating = false
            }
        }
    }
    #endif
}

#if os(macOS)
private struct MacClickOutsideMonitor: NSViewRepresentable {
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.monitoredView = view
        context.coordinator.startMonitoring()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.monitoredView = nsView
        context.coordinator.action = action
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
    }

    final class Coordinator {
        weak var monitoredView: NSView?
        var action: () -> Void
        private var eventMonitor: Any?

        init(action: @escaping () -> Void) {
            self.action = action
        }

        func startMonitoring() {
            guard eventMonitor == nil else { return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self,
                      let monitoredView,
                      let monitoredWindow = monitoredView.window else {
                    return event
                }

                let clickedInside: Bool
                if event.window === monitoredWindow {
                    let localPoint = monitoredView.convert(event.locationInWindow, from: nil)
                    clickedInside = monitoredView.bounds.contains(localPoint)
                } else {
                    clickedInside = false
                }

                if !clickedInside {
                    DispatchQueue.main.async { [weak self] in
                        self?.action()
                    }
                }
                return event
            }
        }

        func stopMonitoring() {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
                self.eventMonitor = nil
            }
        }
    }
}

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
