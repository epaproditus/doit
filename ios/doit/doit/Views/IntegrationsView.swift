import AuthenticationServices
import SwiftUI

struct IntegrationsView: View {
    @State private var toolkits: [Toolkit] = []
    @State private var loading = true
    @State private var error: String?
    @State private var busySlug: String?
    @State private var oauthSession: ASWebAuthenticationSession?

    var body: some View {
        List {
            if loading && toolkits.isEmpty {
                Section { ProgressView() }
            }
            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
            if !toolkits.isEmpty {
                Section {
                    ForEach(toolkits) { tk in
                        ToolkitRow(
                            toolkit: tk,
                            busy: busySlug == tk.slug,
                            onConnect: { Task { await connect(tk) } },
                            onDisconnect: { Task { await disconnect(tk) } }
                        )
                    }
                } header: {
                    Text("Connect your accounts")
                } footer: {
                    Text("Connected accounts let the agent act on your behalf. We never see your password - Composio manages secure OAuth tokens.")
                }
            }
        }
        .navigationTitle("Connections")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            toolkits = try await IntegrationsAPI.list()
            error = nil
        } catch {
            self.error = "Couldn't load integrations: \(error.localizedDescription)"
        }
    }

    private func connect(_ tk: Toolkit) async {
        busySlug = tk.slug
        defer { busySlug = nil }
        do {
            let result = try await IntegrationsAPI.connect(toolkit: tk.slug)
            guard let url = URL(string: result.redirect_url) else {
                self.error = "Got an invalid authorization URL."
                return
            }
            await runOAuth(url: url)
            await load()
        } catch {
            self.error = "Couldn't start connection: \(error.localizedDescription)"
        }
    }

    private func disconnect(_ tk: Toolkit) async {
        guard let cid = tk.connection_id else { return }
        busySlug = tk.slug
        defer { busySlug = nil }
        do {
            try await IntegrationsAPI.disconnect(connectionID: cid)
            await load()
        } catch {
            self.error = "Couldn't disconnect: \(error.localizedDescription)"
        }
    }

    private func runOAuth(url: URL) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: nil) { _, _ in
                cont.resume()
            }
            session.prefersEphemeralWebBrowserSession = false
            session.presentationContextProvider = PresentationContextProvider.shared
            self.oauthSession = session
            if !session.start() {
                cont.resume()
            }
        }
    }
}

private struct ToolkitRow: View {
    let toolkit: Toolkit
    let busy: Bool
    let onConnect: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(toolkit.name).font(.headline)
                    if toolkit.connected {
                        Text("Connected")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15), in: Capsule())
                            .foregroundStyle(Color.green)
                    }
                }
                Text(toolkit.description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if busy {
                ProgressView()
            } else if toolkit.connected {
                Button("Disconnect", role: .destructive, action: onDisconnect)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                Button("Connect", action: onConnect)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
