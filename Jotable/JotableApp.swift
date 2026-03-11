//
//  Jotable
//
//  Created by George Babichev on 9/29/25.
//

import SwiftUI
import SwiftData
import CloudKit
#if os(macOS)
import AppKit
#endif

extension Notification.Name {
    #if os(macOS)
    static let toggleBoldShortcut = Notification.Name("toggleBoldShortcut")
    static let toggleItalicShortcut = Notification.Name("toggleItalicShortcut")
    static let toggleUnderlineShortcut = Notification.Name("toggleUnderlineShortcut")
    static let importNotesRequested = Notification.Name("importNotesRequested")
    static let exportNotesRequested = Notification.Name("exportNotesRequested")
    #endif
    static let createNewNoteRequested = Notification.Name("createNewNoteRequested")
}

private enum AppActionRouter {
    static let newNoteURL = URL(string: "jotable://newNote")!

    static func requestNewNote() {
        #if os(macOS)
        NSApp.activate(ignoringOtherApps: true)

        if let existingWindow = NSApp.windows.first(where: { $0.canBecomeMain }) {
            existingWindow.makeKeyAndOrderFront(nil)
            NotificationCenter.default.post(name: .createNewNoteRequested, object: nil)
            return
        }

        if !NSWorkspace.shared.open(newNoteURL) {
            NotificationCenter.default.post(name: .createNewNoteRequested, object: nil)
        }
        #else
        NotificationCenter.default.post(name: .createNewNoteRequested, object: nil)
        #endif
    }

    static func handleIncomingURL(_ url: URL) {
        guard url.absoluteString == newNoteURL.absoluteString else { return }
        NotificationCenter.default.post(name: .createNewNoteRequested, object: nil)
    }
}

#if os(macOS)
class MacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let dockMenu = NSMenu()

        let newNoteItem = NSMenuItem(
            title: "New Note",
            action: #selector(createNewNote),
            keyEquivalent: ""
        )
        newNoteItem.target = self
        newNoteItem.image = NSImage(
            systemSymbolName: "square.and.pencil",
            accessibilityDescription: "New Note"
        )
        dockMenu.addItem(newNoteItem)

        return dockMenu
    }

    @objc func createNewNote() {
        AppActionRouter.requestNewNote()
    }
}
#endif

#if !os(macOS)
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Handle shortcut item when app launches
        if let shortcutItem = options.shortcutItem {
            if shortcutItem.type == "com.jotable.newNote" {
                // Post notification after a short delay to ensure ContentView is ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    AppActionRouter.requestNewNote()
                }
            }
        }

        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        if shortcutItem.type == "com.jotable.newNote" {
            AppActionRouter.requestNewNote()
            completionHandler(true)
        } else {
            completionHandler(false)
        }
    }
}
#endif

@main
struct JotableApp: App {
    private enum ModelContainerLoadState {
        case available(ModelContainer)
        case failed(String)
    }

    #if os(macOS)
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) var macAppDelegate
    #else
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    private static let modelContainerLoadState: ModelContainerLoadState = {

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
            return .available(container)
        } catch {
            print("❌ Failed to create ModelContainer: \(error)")
            return .failed(error.localizedDescription)
        }
    }()

    #if os(macOS)
    @State private var pastePlaintextTrigger: UUID?
    @State private var isAboutPresented = false
    #endif
    @State private var isEditorActive = false

    var body: some Scene {
        WindowGroup {
            rootView(for: Self.modelContainerLoadState)
        }
        #if os(macOS)
        .handlesExternalEvents(matching: Set(arrayLiteral: "newNote"))
        #endif
        #if os(macOS)
        .commands {
            SidebarCommands()
            CommandGroup(replacing: .appInfo) {
                Button("About Jotable") {
                    isAboutPresented = true
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("New Note") {
                    AppActionRouter.requestNewNote()
                }
                .keyboardShortcut("n", modifiers: [.command])
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

    @ViewBuilder
    private func rootView(for state: ModelContainerLoadState) -> some View {
        switch state {
        case .available(let container):
            mainContentView(container: container)
        case .failed(let errorMessage):
            ModelContainerFailureView(errorMessage: errorMessage)
                .frame(minWidth: 480, minHeight: 320)
        }
    }

    @ViewBuilder
    private func mainContentView(container: ModelContainer) -> some View {
        #if os(macOS)
        ContentView(pastePlaintextTrigger: $pastePlaintextTrigger, isEditorActive: $isEditorActive)
            .onOpenURL { url in
                AppActionRouter.handleIncomingURL(url)
            }
            .frame(minWidth: 800, minHeight: 400)
            .onAppear {
                runStartupDiagnostics(using: container)
            }
            .overlay {
                if isAboutPresented {
                    AboutOverlayView(isPresented: $isAboutPresented)
                }
            }
            .modelContainer(container)
        #else
        ContentView(isEditorActive: $isEditorActive)
            .onOpenURL { url in
                AppActionRouter.handleIncomingURL(url)
            }
            .onAppear {
                runStartupDiagnostics(using: container)
            }
            .modelContainer(container)
        #endif
    }

    private func runStartupDiagnostics(using container: ModelContainer) {
        let context = container.mainContext
        do {
            let descriptor = FetchDescriptor<Item>()
            let items = try context.fetch(descriptor)
            print("🚀 App launched - Found \(items.count) existing items")
            CheckboxMigrator.runIfNeeded(context: context)
        } catch {
            print("❌ Failed to fetch items on launch: \(error)")
        }
    }
}

private struct ModelContainerFailureView: View {
    let errorMessage: String

    private var backgroundColor: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.icloud")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            Text("Jotable couldn’t open your library.")
                .font(.title3.weight(.semibold))

            Text("The local SwiftData or iCloud-backed store failed to load. Your app didn’t crash, but editing is unavailable until the store opens successfully.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            Text(errorMessage)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: 420, alignment: .leading)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundColor)
    }
}
