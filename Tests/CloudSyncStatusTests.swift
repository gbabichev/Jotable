import Foundation

@main
struct CloudSyncStatusTests {
    @MainActor
    static func main() {
        let status = CloudSyncStatus()
        precondition(!status.isBusy && !status.hasFailure)
        let metadata = UUID()
        let documents = UUID()
        status.record(eventID: metadata, storeID: "metadata", operation: .setup, hasEnded: false, succeeded: false)
        // A view that first reads status now must see the earlier setup start.
        precondition(status.isBusy && status.isConnecting)
        status.record(eventID: documents, storeID: "documents", operation: .setup, hasEnded: false, succeeded: false)
        status.record(eventID: metadata, storeID: "metadata", operation: .setup, hasEnded: true, succeeded: true)
        precondition(status.isBusy && status.isConnecting)
        print("PASS: setup is visible to late readers and tracks both stores")

        status.record(eventID: documents, storeID: "documents", operation: .setup, hasEnded: true, succeeded: false)
        precondition(!status.isBusy && status.hasFailure)
        print("PASS: failed setup ends activity and retains a failure state")

        let retry = UUID()
        status.record(eventID: retry, storeID: "documents", operation: .setup, hasEnded: false, succeeded: false)
        precondition(status.isBusy && status.isConnecting)
        status.record(eventID: retry, storeID: "documents", operation: .setup, hasEnded: true, succeeded: true)
        precondition(!status.isBusy && !status.hasFailure)
        print("PASS: successful setup retry clears its failure")

        let failedUpload = UUID()
        status.record(eventID: failedUpload, storeID: "documents", operation: .upload, hasEnded: true, succeeded: false)
        status.record(eventID: UUID(), storeID: "metadata", operation: .upload, hasEnded: true, succeeded: true)
        status.record(eventID: UUID(), storeID: "documents", operation: .download, hasEnded: true, succeeded: true)
        precondition(status.hasFailure)
        status.record(eventID: UUID(), storeID: "documents", operation: .upload, hasEnded: true, succeeded: true)
        precondition(!status.hasFailure)
        print("PASS: another store or operation cannot mask a failed upload")

        let completed = UUID()
        status.record(eventID: completed, storeID: "documents", operation: .download, hasEnded: true, succeeded: true)
        status.record(eventID: completed, storeID: "documents", operation: .download, hasEnded: false, succeeded: false)
        precondition(!status.isBusy)
        print("PASS: a late start cannot resurrect a completed operation")

        let download = UUID()
        let upload = UUID()
        status.record(eventID: download, storeID: "metadata", operation: .download, hasEnded: false, succeeded: false)
        status.record(eventID: upload, storeID: "documents", operation: .upload, hasEnded: false, succeeded: false)
        precondition(status.isBusy && !status.isConnecting)
        status.record(eventID: download, storeID: "metadata", operation: .download, hasEnded: true, succeeded: true)
        precondition(status.isBusy)
        status.record(eventID: upload, storeID: "documents", operation: .upload, hasEnded: true, succeeded: true)
        precondition(!status.isBusy && !status.hasFailure)
        print("PASS: overlapping import and export remain active until both finish")
    }
}
