import PhotosUI
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthModel.self) private var auth
    @Environment(TodoStore.self) private var store
    @State private var selectedModelName: String?

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack(alignment: .top) {
                    ScrollView {
                        VStack(spacing: 0) {
                            VStack(spacing: 0) {
                                NavigationLink {
                                    UserProfileView()
                                } label: {
                                    PersonRow(
                                        avatar: .user(
                                            initials: auth.initials,
                                            imageData: auth.avatarImageData,
                                            url: auth.avatarURL
                                        ),
                                        title: auth.displayName,
                                        subtitle: joinedSubtitle
                                    )
                                }
                                .buttonStyle(.plain)
                                SettingsDivider(leadingPadding: 90)

                                NavigationLink {
                                    AgentProfileView(lastRunText: agentLastRunSubtitle)
                                } label: {
                                    PersonRow(
                                        avatar: .agent,
                                        title: "doit",
                                        subtitle: agentLastRunSubtitle
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                            SectionLabel("Settings")
                                .padding(.top, 30)

                            SettingsGroup {
                                NavigationLink {
                                    ModelSettingsView()
                                } label: {
                                    SettingsRow(
                                        icon: "square.3.layers.3d.middle.filled",
                                        title: "Model",
                                        value: selectedModelName
                                    )
                                }
                                SettingsDivider(leadingPadding: 76)

                                NavigationLink {
                                    IntegrationsView()
                                } label: {
                                    SettingsRow(
                                        icon: "arrow.left.arrow.right",
                                        title: "Connections"
                                    )
                                }
                                SettingsDivider(leadingPadding: 76)

                                NavigationLink {
                                    MemoryView()
                                } label: {
                                    SettingsRow(
                                        icon: "book.pages",
                                        title: "Memory"
                                    )
                                }
                            }

                            Spacer()
                                .frame(height: 52)

                            Button {
                                Task {
                                    await auth.signOut()
                                    dismiss()
                                }
                            } label: {
                                SettingsRow(
                                    icon: "rectangle.portrait.and.arrow.right",
                                    title: "Sign out",
                                    showsChevron: false
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(minHeight: proxy.size.height - 96, alignment: .top)
                        .padding(.top, 72)
                        .padding(.bottom, 32)
                    }
                    .scrollContentBackground(.hidden)

                    settingsHeader
                }
            }
            .background(Color.white)
            .toolbar(.hidden, for: .navigationBar)
            .task { await loadSelectedModelName() }
        }
    }

    private var settingsHeader: some View {
        ZStack {
            Text("Settings")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(white: 0.08))

            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(white: 0.58))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close settings")

                Spacer()
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 60)
        .padding(.bottom, 12)
        .background(Color.white)
        .zIndex(1)
    }

    private func loadSelectedModelName() async {
        do {
            let response = try await AgentSettingsAPI.getModelSettings()
            guard let setting = response.setting else {
                selectedModelName = nil
                return
            }

            selectedModelName = response.catalog
                .first { $0.id == setting.provider }?
                .models
                .first { $0.id == setting.model }?
                .name ?? setting.model
        } catch {
            selectedModelName = nil
        }
    }

    private var joinedSubtitle: String {
        guard let joinedAt = auth.joinedAt else { return "Joined doit" }
        return "Joined \(joinedAt.formatted(.dateTime.month(.abbreviated).day().year()))"
    }

    private var agentLastRunSubtitle: String {
        let todoDates = store.todos.map(\.updated_at)
        let cronDates = store.cronJobs.flatMap { [$0.last_run_at, Optional($0.updated_at)].compactMap { $0 } }
        let activityDates = store.agentActivityByTodoID.values.map(\.updated_at)
        guard let latest = (todoDates + cronDates + activityDates).max() else {
            return "No runs yet"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Last run \(formatter.localizedString(for: latest, relativeTo: Date()))"
    }
}

private struct SettingsRow: View {
    let icon: String
    let title: String
    var value: String?
    var showsChevron = true

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 23, weight: .regular))
                .foregroundStyle(Color(white: 0.58))
                .frame(width: 40, height: 44)

            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(white: 0.18))

            Spacer(minLength: 12)

            if let value, !value.isEmpty {
                Text(value)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(white: 0.42))
                    .lineLimit(1)
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(white: 0.72))
            }
        }
        .frame(minHeight: 62)
        .padding(.horizontal, 20)
        .contentShape(Rectangle())
    }
}

private struct PersonRow: View {
    let avatar: ProfileAvatar.Kind
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            ProfileAvatar(kind: avatar, size: 54)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(white: 0.16))
                Text(subtitle)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(white: 0.58))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(white: 0.72))
        }
        .frame(minHeight: 78)
        .padding(.horizontal, 20)
    }
}

struct ProfileAvatar: View {
    enum Kind {
        case user(initials: String?, imageData: Data?, url: URL?)
        case agent
    }

    let kind: Kind
    let size: CGFloat

    var body: some View {
        Group {
            switch kind {
            case .user(let initials, let imageData, let url):
                if let imageData, let image = UIImage(data: imageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else if let url {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .scaledToFill()
                        } else {
                            initialsFallback(initials)
                        }
                    }
                } else {
                    initialsFallback(initials)
                }
            case .agent:
                Image("doit_pofile")
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(Color(white: 0.9), lineWidth: 1)
        }
    }

    private func initialsFallback(_ initials: String?) -> some View {
        ZStack {
            Circle()
                .fill(Color.black)

            if let initials, !initials.isEmpty {
                Text(initials)
                    .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }
}

private struct UserProfileView: View {
    @Environment(AuthModel.self) private var auth
    @State private var displayName = ""
    @State private var avatarImageData: Data?
    @State private var originalAvatarURL: URL?
    @State private var photoSelection: PhotosPickerItem?
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 28) {
            PhotosPicker(selection: $photoSelection, matching: .images, photoLibrary: .shared()) {
                VStack(spacing: 10) {
                    ProfileAvatar(
                        kind: .user(
                            initials: initials(for: displayName),
                            imageData: avatarImageData,
                            url: avatarImageData == nil ? originalAvatarURL : nil
                        ),
                        size: 92
                    )
                    Text("Change Photo")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(white: 0.36))
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 28)

            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(white: 0.58))
                TextField("Your name", text: $displayName)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .textInputAutocapitalization(.words)
                    .padding(.vertical, 12)
                SettingsDivider(leadingPadding: 0)
            }
            .padding(.horizontal, 20)

            if let error {
                Text(error)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .navigationTitle("You")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(saving ? "Saving" : "Save") {
                    Task { await save() }
                }
                .disabled(saving)
            }
        }
        .onAppear {
            displayName = auth.displayName
            avatarImageData = auth.avatarImageData
            originalAvatarURL = auth.avatarURL
        }
        .onChange(of: photoSelection) { _, newValue in
            guard let newValue else { return }
            Task { await loadPhoto(newValue) }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let resized = image.resizedToFill(maxDimension: 320),
                  let jpegData = resized.jpegData(compressionQuality: 0.72)
            else {
                error = "Couldn't load that photo."
                return
            }
            avatarImageData = jpegData
            error = nil
        } catch {
            self.error = "Couldn't load that photo."
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            try await auth.updateProfile(displayName: displayName, avatarImageData: avatarImageData)
            error = nil
        } catch {
            self.error = "Couldn't save your profile."
        }
    }

    private func initials(for name: String) -> String? {
        let parts = name.split(separator: " ")
        let first = parts.first?.first.map { String($0).uppercased() } ?? ""
        let last = parts.dropFirst().first?.first.map { String($0).uppercased() } ?? ""
        let combined = first + last
        return combined.isEmpty ? nil : combined
    }
}

private struct AgentProfileView: View {
    let lastRunText: String

    var body: some View {
        VStack(spacing: 18) {
            ProfileAvatar(kind: .agent, size: 92)
                .padding(.top, 28)
            Text("doit")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(white: 0.14))
            Text(lastRunText)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color(white: 0.58))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .navigationTitle("doit")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SettingsGroup<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsDivider(leadingPadding: 76)
            content
                .buttonStyle(.plain)
            SettingsDivider(leadingPadding: 76)
        }
    }
}

private struct SectionLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(white: 0.68))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }
}

private struct SettingsDivider: View {
    var leadingPadding: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Color(white: 0.94))
            .frame(height: 1)
            .padding(.leading, leadingPadding)
    }
}

private extension UIImage {
    func resizedToFill(maxDimension: CGFloat) -> UIImage? {
        let longestSide = max(size.width, size.height)
        guard longestSide > 0 else { return nil }
        let scale = min(1, maxDimension / longestSide)
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
