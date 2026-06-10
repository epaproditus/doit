import Foundation

/// One labeled row inside an options item (e.g. Depart / Arrive for flights).
struct OptionsField: Hashable, Sendable {
    let label: String
    let value: String
}

/// One row in a comparison / booking-options list (flight, hotel, haircut, …).
struct OptionsItem: Hashable, Sendable, Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let badge: String?
    let url: URL?
    let imageURL: URL?
    let fields: [OptionsField]

    init?(value: JSONValue) {
        guard let obj = value.objectValue else { return nil }
        let rawID = obj["id"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawTitle = obj["title"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let title = rawTitle, !title.isEmpty else { return nil }
        let id = (rawID?.isEmpty == false) ? rawID! : title
        let subtitle = obj["subtitle"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let badge = obj["badge"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let url = obj["url"]?.stringValue.flatMap(URL.init(string:))
        let imageURL = obj["image_url"]?.stringValue.flatMap(URL.init(string:))
        let fields = obj["fields"]?.arrayValue?.compactMap(OptionsField.init(value:)) ?? []
        self.id = id
        self.title = title
        self.subtitle = subtitle?.isEmpty == false ? subtitle : nil
        self.badge = badge?.isEmpty == false ? badge : nil
        self.url = url
        self.imageURL = imageURL
        self.fields = fields
    }
}

extension OptionsField {
    init?(value: JSONValue) {
        guard let obj = value.objectValue else { return nil }
        guard let label = obj["label"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !label.isEmpty else { return nil }
        guard let valueRaw = obj["value"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !valueRaw.isEmpty else { return nil }
        self.label = label
        self.value = valueRaw
    }
}

/// Structured comparison / booking payload shared by choice interactions
/// and `options` artifacts. Domains differ via `category`, not artifact kind.
struct OptionsPayload: Hashable, Sendable {
    let schema: String?
    let category: String?
    let provider: String?
    let summary: String?
    let items: [OptionsItem]
    let selectedID: String?

    init?(json: JSONValue?) {
        guard let obj = json?.objectValue else { return nil }
        let itemsRaw = obj["items"]?.arrayValue ?? []
        let items = itemsRaw.compactMap(OptionsItem.init(value:))
        guard !items.isEmpty else { return nil }
        self.schema = obj["schema"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let category = obj["category"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.category = category?.isEmpty == false ? category : nil
        let provider = obj["provider"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.provider = provider?.isEmpty == false ? provider : nil
        let summary = obj["summary"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.summary = summary?.isEmpty == false ? summary : nil
        self.items = items
        let selected = obj["selected_id"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.selectedID = selected?.isEmpty == false ? selected : nil
    }

    /// Human-readable category label for headers.
    var categoryDisplayName: String {
        guard let category else { return "Options" }
        return category
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}
