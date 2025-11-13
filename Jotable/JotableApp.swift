//
//  Jotable
//
//  Created by George Babichev on 9/29/25.
//

import SwiftUI
import SwiftData
import CloudKit

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

    @State private var pastePlaintextTrigger: UUID?
    @State private var isEditorActive = false

    var body: some Scene {
        WindowGroup {
            ContentView(pastePlaintextTrigger: $pastePlaintextTrigger, isEditorActive: $isEditorActive)
            #if os(macOS)
                .frame(minWidth: 800, minHeight: 400)
            #endif
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
        }
        .modelContainer(Self.sharedModelContainer)
        #if os(macOS)
        .commands {
            CommandGroup(after: .pasteboard) {
                Button(action: {
                    self.pastePlaintextTrigger = UUID()
                }) {
                    Label("Paste as Plaintext", systemImage: "doc.on.clipboard")
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
                .disabled(!isEditorActive)
            }
        }
        #endif
    }
}
