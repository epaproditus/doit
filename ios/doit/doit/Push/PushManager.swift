import Foundation
import Observation
import Supabase
import UIKit
import UserNotifications

/// Owns APNs registration and the device-token round-trip with Supabase.
/// Also publishes the most recent `todo_id` from a tapped push so the UI can
/// route to it.
@MainActor
@Observable
final class PushManager {
    /// Set when the user taps a notification; consumed by the UI then cleared.
    var pendingTodoID: UUID?
    private var userID: UUID?

    func register(userID: UUID) {
        self.userID = userID
        print("[push] requesting notification authorization")
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            print("[push] notification authorization granted=\(granted)")
            guard granted else { return }
            DispatchQueue.main.async {
                print("[push] registering for remote notifications")
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    func handleAPNsToken(_ data: Data) async {
        let token = data.map { String(format: "%02x", $0) }.joined()
        print("[push] received APNs token prefix=\(token.prefix(12)) length=\(token.count)")
        guard let userID else {
            print("[push] skipping device upsert; no signed-in user id")
            return
        }
        struct Row: Encodable {
            let user_id: UUID
            let apns_token: String
            let apns_environment: String
        }
        do {
            // Upsert keyed on (user_id, apns_token) — duplicate inserts are
            // a no-op thanks to the composite PK.
            _ = try await Supa.client
                .from("devices")
                .upsert(
                    Row(
                        user_id: userID,
                        apns_token: token,
                        apns_environment: APNSEnvironment.current.rawValue
                    ),
                    onConflict: "user_id,apns_token"
                )
                .execute()
            print("[push] device token upsert succeeded environment=\(APNSEnvironment.current.rawValue)")
        } catch {
            print("[push] device upsert failed: \(error)")
        }
    }

    func handleNotificationTap(userInfo: [AnyHashable: Any]) {
        print("[push] notification tapped userInfo=\(userInfo)")
        if let s = userInfo["todo_id"] as? String, let id = UUID(uuidString: s) {
            self.pendingTodoID = id
        }
    }
}
