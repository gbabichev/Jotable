import Foundation
import Observation

/// App-lifetime status, recorded before the stores initialize. Views can join
/// an already-running setup/import without losing its start notification.
@MainActor
@Observable
final class CloudSyncStatus {
    static let shared = CloudSyncStatus()

    enum Operation: Hashable, Sendable {
        case setup, download, upload
    }

    private struct Activity {
        let storeID: String
        let operation: Operation
    }

    private struct FailureKey: Hashable {
        let storeID: String
        let operation: Operation
    }

    private var activities: [UUID: Activity] = [:]
    private var failures: Set<FailureKey> = []
    @ObservationIgnored private var completedIDs: Set<UUID> = []
    @ObservationIgnored private var completionOrder: [UUID] = []

    var isBusy: Bool { !activities.isEmpty }
    var hasFailure: Bool { !failures.isEmpty }
    var isConnecting: Bool { activities.values.contains { $0.operation == .setup } }

    var message: String {
        if isConnecting { return String(localized: "Preparing iCloud sync") }
        if isBusy { return String(localized: "Syncing with iCloud") }
        if hasFailure { return String(localized: "iCloud sync interrupted") }
        return String(localized: "No sync activity")
    }

    func record(eventID: UUID, storeID: String, operation: Operation,
                hasEnded: Bool, succeeded: Bool) {
        let failureKey = FailureKey(storeID: storeID, operation: operation)
        if hasEnded {
            activities.removeValue(forKey: eventID)
            // A late start notification must not resurrect a finished event.
            if completedIDs.insert(eventID).inserted {
                completionOrder.append(eventID)
                if completionOrder.count > 256 {
                    completedIDs.remove(completionOrder.removeFirst())
                }
            }
            if succeeded {
                failures.remove(failureKey)
            } else {
                failures.insert(failureKey)
            }
        } else if !completedIDs.contains(eventID) {
            activities[eventID] = Activity(storeID: storeID, operation: operation)
        }
    }
}
