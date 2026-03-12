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
    #if os(macOS)
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) var macAppDelegate
    #else
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

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
            ContentView(isEditorActive: $isEditorActive)
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
