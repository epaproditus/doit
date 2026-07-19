import Foundation

// MARK: - Book Catalogue

struct BibleCatalogue: Decodable {
    let books: [Book]
    let count: Int
}

struct Book: Identifiable, Decodable, Hashable {
    var id: String { code }
    let code: String
    let name: String
    let chapters: Int
    /// 0 = Old Testament, 1 = New Testament
    let testament: Int
    let order: Int

    var testamentName: String { testament == 0 ? "Old Testament" : "New Testament" }

    static func == (lhs: Book, rhs: Book) -> Bool { lhs.code == rhs.code }
    func hash(into hasher: inout Hasher) { hasher.combine(code) }
}

// MARK: - Verse / Chapter display models

struct BibleVerse: Identifiable, Hashable {
    let id: String  // e.g. "1Co_1_1"
    let bookCode: String
    let chapter: Int
    let verse: Int
    let text: String
    /// Footnote marker strings extracted from the HTML, e.g. ["1a", "2b"]
    var footnoteMarkers: [FootnoteMarker] = []

    var displayReference: String { "\(bookCode) \(chapter):\(verse)" }
}

struct FootnoteMarker: Hashable {
    let marker: String
    let footnoteID: String  // e.g. "n1_1x1a"
}

struct BibleFootnote: Identifiable, Hashable {
    let id: String  // e.g. "n1_1x1a"
    let bookCode: String
    let chapter: Int
    let verse: Int
    let marker: String
    let text: String
    /// Cross-references extracted from footnote HTML, e.g. "Rom. 1:1"
    var crossReferences: [String] = []
}

// MARK: - Navigation destinations

enum BibleDestination: Hashable {
    case chapterGrid(book: Book)
    case reading(book: Book, chapter: Int)
}
