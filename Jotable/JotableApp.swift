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
    static let toggleEditorFocusRequested = Notification.Name("toggleEditorFocusRequested")
    #endif
    static let createNewNoteRequested = Notification.Name("createNewNoteRequested")
    static let openPasswordGeneratorRequested = Notification.Name("openPasswordGeneratorRequested")
}

private enum AppActionRouter {
    static let newNoteURL = URL(string: "jotable://newNote")!
    static let generatePasswordURL = URL(string: "jotable://generatePassword")!

    private static func postPasswordGeneratorRequest(after delay: TimeInterval = 0.15) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            NotificationCenter.default.post(name: .openPasswordGeneratorRequested, object: nil)
        }
    }

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

    static func requestPasswordGenerator() {
        #if os(macOS)
        NSApp.activate(ignoringOtherApps: true)

        if let existingWindow = NSApp.windows.first(where: { $0.canBecomeMain }) {
            existingWindow.makeKeyAndOrderFront(nil)
            postPasswordGeneratorRequest()
            return
        }

        if !NSWorkspace.shared.open(generatePasswordURL) {
            postPasswordGeneratorRequest()
        }
        #else
        postPasswordGeneratorRequest()
        #endif
    }

    static func handleIncomingURL(_ url: URL) {
        if url.absoluteString == newNoteURL.absoluteString {
            NotificationCenter.default.post(name: .createNewNoteRequested, object: nil)
        } else if url.absoluteString == generatePasswordURL.absoluteString {
            postPasswordGeneratorRequest()
        }
    }
}

#if os(macOS)
class MacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(configureMainWindow(_:)),
            name: NSWindow.didBecomeMainNotification,
            object: nil
        )

        DispatchQueue.main.async { [weak self] in
            NSApp.windows.forEach { self?.configureCloseButton(for: $0) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag,
              let window = sender.windows.first(where: isJotableDocumentWindow) else {
            return true
        }

        window.makeKeyAndOrderFront(nil)
        return true
    }

    @objc private func configureMainWindow(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        configureCloseButton(for: window)
    }

    private func configureCloseButton(for window: NSWindow) {
        guard isJotableDocumentWindow(window),
              let closeButton = window.standardWindowButton(.closeButton) else { return }

        closeButton.target = self
        closeButton.action = #selector(hideApplication(_:))
    }

    private func isJotableDocumentWindow(_ window: NSWindow) -> Bool {
        window.canBecomeMain && !(window is NSPanel)
    }

    @objc private func hideApplication(_ sender: NSButton) {
        NSApp.hide(sender)
    }

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

        let generatePasswordItem = NSMenuItem(
            title: "Generate Password",
            action: #selector(openPasswordGenerator),
            keyEquivalent: ""
        )
        generatePasswordItem.target = self
        generatePasswordItem.image = NSImage(
            systemSymbolName: "key.fill",
            accessibilityDescription: "Generate Password"
        )
        dockMenu.addItem(generatePasswordItem)

        return dockMenu
    }

    @objc func createNewNote() {
        AppActionRouter.requestNewNote()
    }

    @objc func openPasswordGenerator() {
        AppActionRouter.requestPasswordGenerator()
    }
}
#endif

#if !os(macOS)
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Handle shortcut item when app launches
        if let shortcutItem = options.shortcutItem {
            handleShortcutItem(shortcutItem)
        }

        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    private func handleShortcutItem(_ shortcutItem: UIApplicationShortcutItem) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            switch shortcutItem.type {
            case "com.jotable.newNote":
                AppActionRouter.requestNewNote()
            case "com.jotable.generatePassword":
                AppActionRouter.requestPasswordGenerator()
            default:
                break
            }
        }
    }
}

class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        switch shortcutItem.type {
        case "com.jotable.newNote":
            AppActionRouter.requestNewNote()
            completionHandler(true)
        case "com.jotable.generatePassword":
            AppActionRouter.requestPasswordGenerator()
            completionHandler(true)
        default:
            completionHandler(false)
        }
    }
}
#endif

@main
struct JotableApp: App {
    #if DEBUG
    // Use with a Development-signed build on both devices. This keeps the
    // reproduction's local stores separate from the installed app's cache.
    static let isLegacySyncTestMode = ProcessInfo.processInfo.arguments.contains("--legacy-sync-test")

    private static var legacySyncTestDirectory: URL {
        let directory = URL.applicationSupportDirectory.appending(path: "LegacySyncTest", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            fatalError("Could not create legacy sync test directory: \(error)")
        }
        return directory
    }
    #endif

    init() {
        CloudSyncDiagnostics.startObserving()
        // Start both mirroring stacks at launch. Bodies must be able to import
        // even if the user stays in the note list and never opens an editor.
        _ = Self.sharedModelContainer
        _ = Self.sharedDocumentContainer
    }

    #if os(macOS)
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) var macAppDelegate
    #else
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    static let sharedModelContainer: ModelContainer = {

        // RESET DATA FIRST - before trying to create container
        //resetDataStore()

        do {
            let schema = Schema([Item.self, Category.self, TodoItem.self])
            var config = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .automatic
            )
            #if DEBUG
            if isLegacySyncTestMode {
                config = ModelConfiguration(
                    schema: schema,
                    url: legacySyncTestDirectory.appending(path: "metadata.store"),
                    cloudKitDatabase: .automatic
                )
            }
            #endif
            let container = try ModelContainer(for: schema, configurations: [config])
            print("✅ Model container created successfully with CloudKit")
            return container
        } catch {
            print("❌ Failed to create ModelContainer: \(error)")
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    // Note bodies use a distinct store and context so their high-frequency
    // saves cannot advance the metadata container's history observer.
    static let sharedDocumentContainer: ModelContainer = {
        do {
            let schema = Schema([NoteDocument.self])
            var storeURL = URL.applicationSupportDirectory
                .appending(path: "JotableDocuments.store")
            #if DEBUG
            if isLegacySyncTestMode {
                storeURL = legacySyncTestDirectory.appending(path: "documents.store")
            }
            #endif
            let config = ModelConfiguration(
                "JotableDocuments",
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .automatic
            )

            let container = try ModelContainer(for: schema, configurations: [config])
            return container
        } catch {
            print("❌ Failed to create NoteDocument container: \(error)")
            fatalError("Could not create NoteDocument container: \(error)")
        }
    }()

    #if os(macOS)
    @State private var pastePlaintextTrigger: UUID?
    @State private var isAboutPresented = false
    #endif
    @State private var isEditorExpanded = false
    @State private var isEditorActive = false
    @State private var isAuthenticatedForPrivateAccess = false
    @State private var lastAuthenticationTime: Date?

    var body: some Scene {
        WindowGroup {
            #if os(macOS)
            ContentView(
                pastePlaintextTrigger: $pastePlaintextTrigger,
                isEditorExpanded: $isEditorExpanded,
                isEditorActive: $isEditorActive,
                isAuthenticatedForPrivateAccess: $isAuthenticatedForPrivateAccess,
                lastAuthenticationTime: $lastAuthenticationTime
            )
                .onOpenURL { url in
                    AppActionRouter.handleIncomingURL(url)
                }
                .frame(minWidth: 800, minHeight: 400)
                .onAppear {
                    // Debug: Print items on app launch
                    let context = Self.sharedModelContainer.mainContext
                    do {
                        let descriptor = FetchDescriptor<Item>()
                        let items = try context.fetch(descriptor)
                        print("🚀 App launched - Found \(items.count) existing items")
                        CheckboxMigrator.runIfNeeded(context: context)
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
            ContentView(
                isEditorExpanded: $isEditorExpanded,
                isEditorActive: $isEditorActive,
                isAuthenticatedForPrivateAccess: $isAuthenticatedForPrivateAccess,
                lastAuthenticationTime: $lastAuthenticationTime
            )
                .onOpenURL { url in
                    AppActionRouter.handleIncomingURL(url)
                }
                .onAppear {
                    // Debug: Print items on app launch
                    let context = Self.sharedModelContainer.mainContext
                    do {
                        let descriptor = FetchDescriptor<Item>()
                        let items = try context.fetch(descriptor)
                        print("🚀 App launched - Found \(items.count) existing items")
                        CheckboxMigrator.runIfNeeded(context: context)
                    } catch {
                        print("❌ Failed to fetch items on launch: \(error)")
                    }
                }
            #endif
        }
        #if os(macOS)
        .handlesExternalEvents(matching: Set(arrayLiteral: "newNote", "generatePassword"))
        #endif
        .modelContainer(Self.sharedModelContainer)
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
            CommandGroup(after: .sidebar) {
                Button(isEditorExpanded ? "Show Note List" : "Focus Editor") {
                    NotificationCenter.default.post(name: .toggleEditorFocusRequested, object: nil)
                }
                .disabled(!isEditorActive)
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
