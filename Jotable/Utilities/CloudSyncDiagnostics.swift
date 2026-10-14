import CoreData
import Foundation
import OSLog

/// Observe both stores for the lifetime of the app, including setup events
/// that occur before a note editor or sync indicator has appeared.
enum CloudSyncDiagnostics {
    private static var observer: NSObjectProtocol?
    nonisolated private static let logger = Logger(
        subsystem: "com.georgebabichev.jotable",
        category: "Persistence"
    )

    static func startObserving() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            log(event)
        }
    }

    nonisolated private static func log(_ event: NSPersistentCloudKitContainer.Event) {
        let operation: String
        switch event.type {
        case .setup: operation = "setup"
        case .import: operation = "import"
        case .export: operation = "export"
        @unknown default: operation = "unknown"
        }

        let store = event.storeIdentifier
        let identifier = event.identifier.uuidString
        guard event.endDate != nil else {
            logger.notice("CloudKit \(operation, privacy: .public) started; store=\(store, privacy: .public) event=\(identifier, privacy: .public)")
            return
        }

        if event.succeeded {
            logger.notice("CloudKit \(operation, privacy: .public) succeeded; store=\(store, privacy: .public) event=\(identifier, privacy: .public)")
        } else if let error = event.error {
            let error = error as NSError
            logger.error("CloudKit \(operation, privacy: .public) failed; store=\(store, privacy: .public) event=\(identifier, privacy: .public) error=\(error.domain, privacy: .public)/\(error.code) details=\(String(reflecting: error), privacy: .private)")
        } else {
            logger.error("CloudKit \(operation, privacy: .public) failed without an error; store=\(store, privacy: .public) event=\(identifier, privacy: .public)")
        }
    }

    nonisolated static func logSaveFailure(_ error: Error, store: String) {
        let error = error as NSError
        logger.error("Local save failed; store=\(store, privacy: .public) error=\(error.domain, privacy: .public)/\(error.code) details=\(String(reflecting: error), privacy: .private)")
    }
}
