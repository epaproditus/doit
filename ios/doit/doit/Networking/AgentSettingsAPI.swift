import Foundation
import Supabase

@MainActor
enum AgentSettingsAPI {
    static func getModelSettings() async throws -> AgentModelCatalogResponse {
        struct Body: Codable { let action: String }
        return try await Supa.client.functions
            .invoke("agent-settings", options: .init(body: Body(action: "get")))
    }

    static func getConnectorConfig() async throws -> BYOHermesConfig? {
        struct Body: Codable { let action: String }
        struct Resp: Codable { let hermes_config: BYOHermesConfig? }
        let resp: Resp = try await Supa.client.functions
            .invoke("agent-settings", options: .init(body: Body(action: "get_connector_config")))
        return resp.hermes_config
    }

    static func updateModelSettings(
        provider: String,
        model: String,
        base_url: String? = nil
    ) async throws -> AgentModelSetting {
        struct Body: Codable {
            let action: String
            let provider: String
            let model: String
            let base_url: String?
        }
        struct Resp: Codable { let setting: AgentModelSetting }

        let body = Body(
            action: "update",
            provider: provider,
            model: model,
            base_url: base_url
        )
        let resp: Resp = try await Supa.client.functions
            .invoke("agent-settings", options: .init(body: body))
        return resp.setting
    }
}
