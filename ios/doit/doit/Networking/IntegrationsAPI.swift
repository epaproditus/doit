import Foundation
import Supabase

struct Toolkit: Codable, Identifiable, Hashable, Sendable {
    var id: String { slug }
    let slug: String
    let name: String
    let description: String
    let connected: Bool
    let connection_id: String?
    let status: String?
}

struct ConnectResult: Codable, Sendable {
    let redirect_url: String
    let connection_id: String
}

@MainActor
enum IntegrationsAPI {
    static func list() async throws -> [Toolkit] {
        struct Body: Codable { let action: String }
        struct Resp: Codable { let toolkits: [Toolkit] }
        let resp: Resp = try await Supa.client.functions
            .invoke("integrations", options: .init(body: Body(action: "list")))
        return resp.toolkits
    }

    static func connect(toolkit: String) async throws -> ConnectResult {
        struct Body: Codable { let action: String; let toolkit: String }
        return try await Supa.client.functions
            .invoke(
                "integrations",
                options: .init(body: Body(action: "connect", toolkit: toolkit))
            )
    }

    static func disconnect(connectionID: String) async throws {
        struct Body: Codable { let action: String; let connection_id: String }
        struct Resp: Codable { let ok: Bool }
        let _: Resp = try await Supa.client.functions
            .invoke(
                "integrations",
                options: .init(body: Body(action: "disconnect", connection_id: connectionID))
            )
    }
}
