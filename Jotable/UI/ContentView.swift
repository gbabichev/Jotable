//
//  ContentView.swift
//  SimpleNote
//

import SwiftUI
import SwiftData
import CoreData
import LocalAuthentication

// Selection type for the sidebar
enum SidebarSelection: Hashable {
    case allNotes
    case category(Category)
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    // Changed from timestamp to createdAt for stable sorting based on creation date
    @Query(sort: \Item.createdAt, order: .reverse) private var allItems: [Item]
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    #if os(macOS)
    @Binding var pastePlaintextTrigger: UUID?
    #endif
    @Binding var isEditorActive: Bool

    @State private var selectedItem: Item?
    @State private var sidebarSelection: SidebarSelection? = .allNotes
    @State private var showingAddCategory = false
    @State private var categoryToEdit: Category?
    @State private var searchText = ""
    @State private var authenticatingCategoryID: PersistentIdentifier?
    @State private var showAuthError = false
    @State private var authErrorMessage = ""
    @State private var showingCategoryPickerForItem: Item?

    
    // Computed property to get the selected category for filtering
    private var selectedCategory: Category? {
        switch sidebarSelection {
        case .allNotes, .none:
            return nil
        case .category(let category):
            return category
        }
    }
    
    // Filtered items based on selected category and search
    var filteredItems: [Item] {
        var items = allItems

        // Get locked category IDs for filtering
        let lockedCategoryIDs = Set(categories.filter { $0.isPrivate }.compactMap { $0.id })

        // If searching, ignore category scope (search across all notes)
        if searchText.isEmpty, let selectedCategory = selectedCategory {
            items = items.filter { $0.category == selectedCategory }
        } else {
            // When viewing "All Notes" or searching, hide notes from locked categories
            items = items.filter { item in
                guard let category = item.category else { return true }
                return !lockedCategoryIDs.contains(category.id)
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
        let lockedCategoryIDs = Set(categories.filter { $0.isPrivate }.compactMap { $0.id })
        return allItems.filter { item in
            guard let category = item.category else { return true }
            return !lockedCategoryIDs.contains(category.id)
        }.count
    }
    
    var body: some View {
        NavigationSplitView {
            // Sidebar with categories
            List(selection: $sidebarSelection) {
                sidebarContent
            }
            .listStyle(SidebarListStyle())
            .navigationTitle("Jotable")
            .onChange(of: selectedItem) { _, newSelectedItem in
                // Manage isEditorActive based on whether a note is selected
                isEditorActive = newSelectedItem != nil
            }
            .onChange(of: sidebarSelection) { oldValue, newValue in
                // Check if the newly selected item is a locked category
                if case .category(let category) = newValue, category.isPrivate {
                    // If we just authenticated for this category, allow the selection
                    if authenticatingCategoryID == category.id {
                        authenticatingCategoryID = nil
                        return
                    }

                    // Revert selection while we authenticate
                    sidebarSelection = oldValue
                    authenticatingCategoryID = category.id
                    let categoryID = category.id

                    // Authenticate
                    authenticateWithBiometrics(reason: "Authenticate to access this private category") { success in
                        DispatchQueue.main.async {
                            if success {
                                // Mark as authenticated and allow selection
                                self.authenticatingCategoryID = categoryID
                                self.sidebarSelection = newValue
                            } else {
                                self.authenticatingCategoryID = nil
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
                    Button(action: {
                        print("Debug Print")
                    }) {
                        Label("Debug", systemImage: "ladybug")
                    }
                    Button(role: .destructive, action: deleteEverything) {
                        Image(systemName: "trash.fill")
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
        } content: {
            // Notes list with drag-to-reorder capability
            List(selection: $selectedItem) {
                notesListContent
            }
            .searchable(
                text: $searchText,
                prompt: "Search notes"
            )
            .navigationTitle(selectedCategory?.name ?? "All Notes")
            .navigationSubtitle("\(filteredItems.count) \(filteredItems.count == 1 ? "note" : "notes")")
            .navigationSplitViewColumnWidth(min: 250, ideal: 250, max: 400)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: addItem) {
                        Label("New Note", systemImage: "square.and.pencil")
                    }
                }
            }
        } detail: {
            // Detail view wrapped in NavigationStack for proper navigation
            NavigationStack {
                if let selectedItem {
                    #if os(macOS)
                    NoteEditorView(item: selectedItem, pastePlaintextTrigger: $pastePlaintextTrigger, isEditorActive: $isEditorActive)
                        .id(selectedItem.id) // Force view recreation when switching notes
                    #else
                    NoteEditorView(item: selectedItem, isEditorActive: $isEditorActive)
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
                    .toolbar {
                        Spacer()
                    }
                }
            }
        }
        .onAppear {
            setupCloudKitNotifications()
        }
        .alert("Authentication Failed", isPresented: $showAuthError) {
            Button("OK") {
                showAuthError = false
            }
        } message: {
            Text(authErrorMessage)
        }
    }
    
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
                isPrivate: false
            )
            .tag(SidebarSelection.allNotes)
        }
        
        // Categories section
        Section("Categories") {
            ForEach(categories) { category in
                CategoryRowView(
                    icon: nil,
                    title: category.name,
                    count: category.notes?.count ?? 0,
                    color: category.color,
                    isPrivate: category.isPrivate
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
                        Label(
                            category.isPrivate ? "Disable Privacy" : "Enable Privacy",
                            systemImage: category.isPrivate ? "eye" : "eye.slash"
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
            NoteRowView(item: item)
                .tag(item)
                .id(item.id)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        deleteItem(item)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .contextMenu {
                    Button {
                        // Select the item for editing
                        selectedItem = item
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
                        deleteItem(item)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .categoryPickerPresenter(
                    isPresented: createPresentedBinding(for: item),
                    selectedCategory: createCategoryBinding(for: item)
                )
        }
        .onMove(perform: moveItems)
        .onDelete(perform: deleteItems)
    }
    
    // Delete a single item
    private func deleteItem(_ item: Item) {
        print("Deleting item: '\(item.title)'")
        
        // IMPORTANT: Clear selection BEFORE deleting to prevent crash
        if selectedItem == item {
            selectedItem = nil
            print("Cleared selection")
        }
        
        // Delete after a brief delay to ensure UI updates
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation {
                modelContext.delete(item)
                
                do {
                    try modelContext.save()
                    print("💾 Item deleted and saved successfully - CloudKit sync queued")
                } catch {
                    print("❌ Failed to save after deletion: \(error)")
                }
            }
        }
    }
    
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
        var reorderedCategories = Array(categories)
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
    
    private func deleteCategory(_ category: Category) {
        withAnimation {
            // Move all notes in this category to "no category"
            for note in category.notes ?? [] {
                note.category = nil
            }
            
            // Clear selection if deleting selected category
            if case .category(let selectedCat) = sidebarSelection, selectedCat.id == category.id {
                sidebarSelection = .allNotes
                selectedItem = nil
            }
            
            modelContext.delete(category)
            
            do {
                try modelContext.save()
                print("💾 Category deleted successfully - CloudKit sync queued")
            } catch {
                print("❌ Failed to delete category: \(error)")
            }
        }
    }
    
    private func deleteCategories(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                let category = categories[index]
                
                // Move all notes in this category to "no category"
                for note in category.notes ?? [] {
                    note.category = nil
                }
                
                // Clear selection if deleting selected category
                if case .category(let selectedCat) = sidebarSelection, selectedCat.id == category.id {
                    sidebarSelection = .allNotes
                    selectedItem = nil
                }
                
                modelContext.delete(category)
            }
            
            do {
                try modelContext.save()
            } catch {
                print("Failed to delete category: \(error)")
            }
        }
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
        let actionDescription = category.isPrivate ? "disable privacy for this category" : "enable privacy for this category"
        authenticateWithBiometrics(reason: "Authenticate to \(actionDescription)") { success in
            guard success else { return }

            category.isPrivate.toggle()
            self.saveCategory()
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

    private func authenticateWithBiometrics(reason: String = "Authenticate to continue", completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Password"
        var authError: NSError?

        // Suppress Sendable warning - completion is dispatched to main thread and auth callbacks are safe
        nonisolated(unsafe) let unsafeCompletion = completion

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            authErrorMessage = authError?.localizedDescription ?? "Device authentication not available"
            showAuthError = true
            completion(false)
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
        selectedItem = nil
        sidebarSelection = .allNotes

        // Give SwiftUI a moment to process the selection change
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation {
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

    private func addItem() {
        // Create date formatter for the title
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEEE, M/d/yy"
        let dateTitle = dateFormatter.string(from: Date())

        let newItem = Item(title: dateTitle)

        // Assign to selected category if one is chosen
        if let selectedCategory = selectedCategory {
            newItem.category = selectedCategory
        }

        modelContext.insert(newItem)

        do {
            try modelContext.save()
            print("💾 New item created and saved - CloudKit sync queued")
            // Set selection immediately
            selectedItem = newItem
        } catch {
            print("❌ Failed to save new item: \(error)")
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                let itemToDelete = filteredItems[index]
                deleteItem(itemToDelete)
            }
        }
    }

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
                item.category = $0
                do {
                    try modelContext.save()
                    print("💾 Category updated and saved - CloudKit sync queued")
                } catch {
                    print("❌ Failed to save category: \(error)")
                }
            }
        )
    }

    private func setupCloudKitNotifications() {
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event {
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
}

// Separate view for category rows to ensure proper native behavior
struct CategoryRowView: View {
    let icon: String?
    let title: String
    let count: Int
    let color: String?
    let isPrivate: Bool

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

struct NoteRowView: View {
    let item: Item
    
    private var previewText: String {
        let trimmed = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Start writing..." }
        
        // Use the first non-empty line to avoid blank previews when the note starts with newlines
        let firstNonEmptyLine = trimmed
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        
        return firstNonEmptyLine ?? trimmed
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.title.isEmpty ? "Untitled" : item.title)
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
                
                // Show category indicator
                if let category = item.category {
                    Circle()
                        .fill(Color.fromString(category.color))
                        .frame(width: 8, height: 8)
                }
                
                Text(item.timestamp, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Text(previewText)
                .font(.subheadline)
                .foregroundStyle(previewText == "Start writing..." ? .tertiary : .secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .id(item.persistentModelID)
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
