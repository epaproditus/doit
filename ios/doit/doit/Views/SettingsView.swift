import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthModel.self) private var auth

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        IntegrationsView()
                    } label: {
                        SettingsRow(
                            icon: "link",
                            title: "Connections",
                            subtitle: "Google, Gmail, Docs, Sheets, Calendar, and more"
                        )
                    }

                    NavigationLink {
                        MemoryView()
                    } label: {
                        SettingsRow(
                            icon: "brain.head.profile",
                            title: "Memory",
                            subtitle: "Facts the agent should remember about you"
                        )
                    }
                } header: {
                    Text("Agent")
                }

                Section {
                    Button(role: .destructive) {
                        Task { await auth.signOut() }
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct SettingsRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
