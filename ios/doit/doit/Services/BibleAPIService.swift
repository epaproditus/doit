import Foundation

/// Service that loads and caches Recovery Version Bible content
/// from per-book JSON files bundled with the app.
@MainActor
enum BibleAPIService {

    // MARK: - Cache

    private static var cache: [String: BookContent] = [:]

    // MARK: - Public API

    /// Fetch verses for a given book and chapter.
    /// Returns an empty array if the book/chapter isn't found.
    static func verses(for bookCode: String, chapter: Int) -> [BibleVerse] {
        guard let content = getContent(for: bookCode) else { return [] }
        let chKey = "\(chapter)"
        guard let rawVerses = content.verses[chKey] else { return [] }
        return rawVerses
    }

    /// Fetch a single footnote by its id within a book.
    static func footnote(id: String, in bookCode: String) -> BibleFootnote? {
        guard let content = getContent(for: bookCode) else { return nil }
        guard let fn = content.footnotes[id] else { return nil }
        return BibleFootnote(
            id: fn.id,
            bookCode: bookCode,
            chapter: 0, // resolved from the footnote ID later if needed
            verse: 0,
            marker: fn.marker,
            text: fn.paragraphs.first ?? fn.text,
            crossReferences: fn.references
        )
    }

    /// Fetch all footnotes for a given verse.
    static func footnotes(for bookCode: String, chapter: Int, verse: Int) -> [BibleFootnote] {
        // First get the verse to see which footnote markers it has
        let verseList = verses(for: bookCode, chapter: chapter)
        guard let target = verseList.first(where: { $0.verse == verse }) else { return [] }

        return target.footnoteMarkers.compactMap { marker in
            footnote(id: marker.footnoteID, in: bookCode)
        }
    }

    /// Return the LSM copyright attribution string for a given book.
    /// Falls back to the standard LSM copyright text if the JSON doesn't
    /// carry a per‑book copyright field.
    static func copyright(for bookCode: String) -> String {
        guard let content = getContent(for: bookCode),
              !content.copyright.isEmpty
        else {
            return "Recovery Version. \u{00A9} 2025 Living Stream Ministry. Used by permission."
        }
        return content.copyright
    }

    /// Preload a book's content into cache (call from the reading view on appear).
    static func preload(bookCode: String) {
        _ = getContent(for: bookCode)
    }

    // MARK: - Loading

    private static func getContent(for bookCode: String) -> BookContent? {
        if let cached = cache[bookCode] { return cached }

        // Load from the per-book JSON file
        // Primary: subdirectory "BibleData/books/" (folder reference preserves hierarchy)
        // Fallback: flat bundle (if files were added individually)
        let primary = Bundle.main.url(
            forResource: bookCode,
            withExtension: "json",
            subdirectory: "BibleData/books"
        )
        let secondary = Bundle.main.url(
            forResource: "BibleData/books/\(bookCode)",
            withExtension: "json"
        )
        let tertiary = Bundle.main.url(
            forResource: bookCode,
            withExtension: "json"
        )
        guard let url = primary ?? secondary ?? tertiary else {
            print("[BibleAPIService] Missing resource: BibleData/books/\(bookCode).json")
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let raw = try decoder.decode(RawBookContent.self, from: data)
            let content = BookContent(
                verses: raw.verses,
                footnotes: raw.footnotes,
                copyright: raw.copyright
            )
            cache[bookCode] = content
            return content
        } catch {
            print("[BibleAPIService] Failed to load \(bookCode): \(error)")
            return nil
        }
    }

    /// Clear the memory cache (e.g. on memory warning).
    static func clearCache() {
        cache.removeAll()
    }
}

// MARK: - Internal types (mirrors the JSON structure)

private struct RawBookContent: Decodable {
    let verses: [String: [RawVerse]]
    let footnotes: [String: RawFootnote]
    /// Copyright attribution from the LSM source; often absent in older JSON.
    let copyright: String?

    enum CodingKeys: String, CodingKey {
        case verses, footnotes, copyright
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        verses = try container.decode([String: [RawVerse]].self, forKey: .verses)
        footnotes = try container.decode([String: RawFootnote].self, forKey: .footnotes)
        copyright = try container.decodeIfPresent(String.self, forKey: .copyright)
    }
}

private struct RawVerse: Decodable {
    let verse: Int
    let text: String
    let footnoteMarkers: [RawFootnoteMarker]
}

private struct RawFootnoteMarker: Decodable {
    let marker: String
    let footnoteId: String

    enum CodingKeys: String, CodingKey {
        case marker
        case footnoteId
    }
}

private struct RawFootnote: Decodable {
    let id: String
    let marker: String
    let lemma: String
    let references: [String]
    let text: String
    let paragraphs: [String]
}

private struct BookContent {
    let verses: [String: [BibleVerse]]
    let footnotes: [String: BibleFootnote]
    let copyright: String

    init(verses: [String: [RawVerse]], footnotes: [String: RawFootnote], copyright: String?) {
        var vDict: [String: [BibleVerse]] = [:]
        for (chKey, rawVerses) in verses {
            vDict[chKey] = rawVerses.map { raw in
                BibleVerse(
                    id: "\(chKey)_\(raw.verse)",
                    bookCode: "",
                    chapter: Int(chKey) ?? 0,
                    verse: raw.verse,
                    text: raw.text,
                    footnoteMarkers: raw.footnoteMarkers.map { m in
                        FootnoteMarker(marker: m.marker, footnoteID: m.footnoteId)
                    }
                )
            }
        }
        self.verses = vDict

        var fnDict: [String: BibleFootnote] = [:]
        for (fnId, raw) in footnotes {
            fnDict[fnId] = BibleFootnote(
                id: raw.id,
                bookCode: "",
                chapter: 0,
                verse: 0,
                marker: raw.marker,
                text: raw.paragraphs.first ?? raw.text,
                crossReferences: raw.references
            )
        }
        self.footnotes = fnDict
        self.copyright = copyright ?? "Recovery Version. \u{00A9} 2025 Living Stream Ministry. Used by permission."
    }
}
