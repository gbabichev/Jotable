//
//  Jotable
//
//  Created by George Babichev on 9/29/25.
//

import SwiftUI
import SwiftData
import CloudKit

extension Notification.Name {
    static let toggleBoldShortcut = Notification.Name("toggleBoldShortcut")
    static let toggleItalicShortcut = Notification.Name("toggleItalicShortcut")
    static let toggleUnderlineShortcut = Notification.Name("toggleUnderlineShortcut")
    static let importNotesRequested = Notification.Name("importNotesRequested")
    static let exportNotesRequested = Notification.Name("exportNotesRequested")
}

// Environment key for tracking if an editor is active
private struct EditorActiveKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isEditorActive: Bool {
        get { self[EditorActiveKey.self] }
        set { self[EditorActiveKey.self] = newValue }
    }
}

@main
struct JotableApp: App {

    static let sharedModelContainer: ModelContainer = {

        // RESET DATA FIRST - before trying to create container
        //resetDataStore()

        do {
            let schema = Schema([Item.self, Category.self])
            let config = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .automatic
            )
            let container = try ModelContainer(for: schema, configurations: [config])
            print("✅ Model container created successfully with CloudKit")
            return container
        } catch {
            print("❌ Failed to create ModelContainer: \(error)")
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    #if os(macOS)
    @State private var pastePlaintextTrigger: UUID?
    @State private var isAboutPresented = false
    #endif
    @State private var isEditorActive = false

    var body: some Scene {
        WindowGroup {
            #if os(macOS)
            ContentView(pastePlaintextTrigger: $pastePlaintextTrigger, isEditorActive: $isEditorActive)
                .frame(minWidth: 800, minHeight: 400)
                .onAppear {
                    // Debug: Print items on app launch
                    let context = Self.sharedModelContainer.mainContext
                    do {
                        let descriptor = FetchDescriptor<Item>()
                        let items = try context.fetch(descriptor)
                        print("🚀 App launched - Found \(items.count) existing items")
                    } catch {
                        print("❌ Failed to fetch items on launch: \(error)")
                    }
                }
                .overlay {
                    if isAboutPresented {
                        AboutOverlayView(isPresented: $isAboutPresented)
                    }
                }
            #else
            ContentView(isEditorActive: $isEditorActive)
                .onAppear {
                    // Debug: Print items on app launch
                    let context = Self.sharedModelContainer.mainContext
                    do {
                        let descriptor = FetchDescriptor<Item>()
                        let items = try context.fetch(descriptor)
                        print("🚀 App launched - Found \(items.count) existing items")
                    } catch {
                        print("❌ Failed to fetch items on launch: \(error)")
                    }
                }
            #endif
        }
        .modelContainer(Self.sharedModelContainer)
        #if os(macOS)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Jotable") {
                    isAboutPresented = true
                }
            }
            CommandGroup(after: .pasteboard) {
                Button(action: {
                    self.pastePlaintextTrigger = UUID()
                }) {
                    Label("Paste as Plaintext", systemImage: "doc.on.clipboard")
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
                .disabled(!isEditorActive)
            }

            CommandGroup(after: .textFormatting) {
                Button("Bold") {
                    NotificationCenter.default.post(name: .toggleBoldShortcut, object: nil)
                }
                .keyboardShortcut("b", modifiers: [.command])
                .disabled(!isEditorActive)

                Button("Italic") {
                    NotificationCenter.default.post(name: .toggleItalicShortcut, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command])
                .disabled(!isEditorActive)

                Button("Underline") {
                    NotificationCenter.default.post(name: .toggleUnderlineShortcut, object: nil)
                }
                .keyboardShortcut("u", modifiers: [.command])
                .disabled(!isEditorActive)
            }
            CommandGroup(replacing: .importExport) {
                Button(action: {
                    NotificationCenter.default.post(name: .importNotesRequested, object: nil)
                }) {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])

                Button(action: {
                    NotificationCenter.default.post(name: .exportNotesRequested, object: nil)
                }) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
        #endif
    }
}
