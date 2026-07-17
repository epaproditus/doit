import Foundation

/// Response from GET {baseURL}/v1/agent/config on a remote Hermes API server.
struct BYOHermesConfig: Codable, Sendable {
    /// Active provider ID (e.g. "opencode-go", "openai").
    let provider: String
    /// Active model name (e.g. "deepseek-v4-flash").
    let model: String
    /// Optional base URL override (null when not set).
    let base_url: String?
    /// Whether a provider API key is configured on the remote Hermes.
    let has_api_key: Bool
}

/// Fetches model configuration from a remote Hermes API server (BYO/self-managed).
enum BYOModelSettingsAPI {
    /// Fetch the current Hermes agent config from the remote API server.
    /// - Parameter baseURL: The base URL of the remote Hermes API server (e.g. "http://100.113.47.24:8642").
    /// - Returns: ``BYOHermesConfig`` with the provider, model, and key presence.
    /// - Throws: A user-friendly error on network failure, timeout, or non-200 response.
    static func getConfig(baseURL: String) async throws -> BYOHermesConfig {
        guard let url = URL(string: baseURL)?.appendingPathComponent("/v1/agent/config") else {
            throw URLError(.badURL, userInfo: [NSLocalizedDescriptionKey: "Invalid Hermes API server URL."])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        // If a stored API key exists for BYO, use it.
        // For self-managed setups, the API_SERVER_KEY may not be needed if
        // the user's gateway is configured without auth (internal network).
        let apiKey = UserDefaults.standard.string(forKey: "settings.byo.apiKey") ?? ""
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "No HTTP response from Hermes API server."])
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            throw URLError(.badServerResponse, userInfo: [
                NSLocalizedDescriptionKey: "Hermes API server returned HTTP \(httpResponse.statusCode): \(body)"
            ])
        }

        let decoder = JSONDecoder()
        return try decoder.decode(BYOHermesConfig.self, from: data)
    }
}
