import Foundation

/// Small, user-scoped disk snapshot for the list surface. It exists only to
/// make cold launches feel warm; Supabase remains authoritative after refresh.
enum TodoStoreSnapshotCache {
    struct Snapshot: Codable, Sendable {
        let savedAt: Date
        let todos: [Todo]
        let cronJobs: [CronJob]
        let openInteractions: [TodoInteraction]
        let artifacts: [TodoArtifact]
        let agentActivities: [AgentActivity]
        let memories: [AgentMemory]
    }

    private static let directoryName = "TodoStoreSnapshots"
    private static let fileExtension = "json"

    static func load(userID: UUID) -> Snapshot? {
        let url: URL
        do {
            url = try snapshotURL(userID: userID, createDirectory: false)
        } catch {
            print("[store][snapshot] resolve failed: \(error)")
            return nil
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(Snapshot.self, from: data)
        } catch {
            print("[store][snapshot] load failed: \(error)")
            return nil
        }
    }

    static func save(_ snapshot: Snapshot, userID: UUID) {
        do {
            let url = try snapshotURL(userID: userID, createDirectory: true)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: [.atomic])
        } catch {
            print("[store][snapshot] save failed: \(error)")
        }
    }

    private static func snapshotURL(userID: UUID, createDirectory: Bool) throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directoryURL = baseURL.appendingPathComponent(directoryName, isDirectory: true)
        if createDirectory {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        let filename = "\(userID.uuidString.lowercased()).\(fileExtension)"
        return directoryURL.appendingPathComponent(filename, isDirectory: false)
    }
}
