import Foundation

struct AgentModelCatalogResponse: Codable, Sendable {
    let catalog: [AgentModelProviderOption]
    let setting: AgentModelSetting?
    let default_selection: AgentModelSelection?
}

struct AgentModelSelection: Codable, Hashable, Sendable {
    let provider: String
    let model: String
}

struct AgentModelProviderOption: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let models: [AgentModelOption]
}

struct AgentModelOption: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let label: String
    let description: String
    let locked: Bool?

    var isLocked: Bool { locked ?? false }
}

struct AgentModelSetting: Codable, Hashable, Sendable {
    let user_id: UUID
    var provider: String
    var model: String
    var base_url: String?
    var apply_status: AgentModelApplyStatus
    var apply_error: String?
    var last_applied_at: String?
    var updated_at: String
}

extension AgentModelCatalogResponse {
    /// Create a single-provider catalog from a remote Hermes agent config.
    /// Used in self-managed mode to drive the provider/model pickers.
    init(from remoteConfig: BYOHermesConfig) {
        let option = AgentModelProviderOption(
            id: remoteConfig.provider,
            name: remoteConfig.provider,
            models: [
                AgentModelOption(
                    id: remoteConfig.model,
                    name: remoteConfig.model,
                    label: "Active",
                    description: "Currently configured on the remote Hermes agent.",
                    locked: false
                )
            ]
        )
        self.catalog = [option]
        self.setting = nil
        self.default_selection = AgentModelSelection(
            provider: remoteConfig.provider,
            model: remoteConfig.model
        )
    }
}

enum AgentModelApplyStatus: String, Codable, Sendable {
    case pending
    case applied
    case failed

    var label: String {
        switch self {
        case .pending: return "Pending"
        case .applied: return "Applied"
        case .failed: return "Failed"
        }
    }
}
