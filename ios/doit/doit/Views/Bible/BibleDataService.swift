import Foundation

/// Static data provider for the 66-book Recovery Version Bible.
/// In v1 this serves a local catalogue; verse content will be loaded
/// from Supabase once the HTML parser is built.
@MainActor
enum BibleDataService {

    // MARK: - Book catalogue

    /// 66 canonical books of the Bible in canonical order,
    /// with standard chapter counts for the Recovery Version.
    static let books: [Book] = [
        // — OLD TESTAMENT (39 books) —
        Book(code: "Gen", name: "Genesis", chapters: 50, testament: 0, order: 0),
        Book(code: "Exo", name: "Exodus", chapters: 40, testament: 0, order: 1),
        Book(code: "Lev", name: "Leviticus", chapters: 27, testament: 0, order: 2),
        Book(code: "Num", name: "Numbers", chapters: 36, testament: 0, order: 3),
        Book(code: "Deu", name: "Deuteronomy", chapters: 34, testament: 0, order: 4),
        Book(code: "Jos", name: "Joshua", chapters: 24, testament: 0, order: 5),
        Book(code: "Jdg", name: "Judges", chapters: 21, testament: 0, order: 6),
        Book(code: "Rut", name: "Ruth", chapters: 4, testament: 0, order: 7),
        Book(code: "1Sa", name: "1 Samuel", chapters: 31, testament: 0, order: 8),
        Book(code: "2Sa", name: "2 Samuel", chapters: 24, testament: 0, order: 9),
        Book(code: "1Ki", name: "1 Kings", chapters: 22, testament: 0, order: 10),
        Book(code: "2Ki", name: "2 Kings", chapters: 25, testament: 0, order: 11),
        Book(code: "1Ch", name: "1 Chronicles", chapters: 29, testament: 0, order: 12),
        Book(code: "2Ch", name: "2 Chronicles", chapters: 36, testament: 0, order: 13),
        Book(code: "Ezr", name: "Ezra", chapters: 10, testament: 0, order: 14),
        Book(code: "Neh", name: "Nehemiah", chapters: 13, testament: 0, order: 15),
        Book(code: "Est", name: "Esther", chapters: 10, testament: 0, order: 16),
        Book(code: "Job", name: "Job", chapters: 42, testament: 0, order: 17),
        Book(code: "Psa", name: "Psalms", chapters: 150, testament: 0, order: 18),
        Book(code: "Prv", name: "Proverbs", chapters: 31, testament: 0, order: 19),
        Book(code: "Ecc", name: "Ecclesiastes", chapters: 12, testament: 0, order: 20),
        Book(code: "SoS", name: "Song of Songs", chapters: 8, testament: 0, order: 21),
        Book(code: "Isa", name: "Isaiah", chapters: 66, testament: 0, order: 22),
        Book(code: "Jer", name: "Jeremiah", chapters: 52, testament: 0, order: 23),
        Book(code: "Lam", name: "Lamentations", chapters: 5, testament: 0, order: 24),
        Book(code: "Ezk", name: "Ezekiel", chapters: 48, testament: 0, order: 25),
        Book(code: "Dan", name: "Daniel", chapters: 12, testament: 0, order: 26),
        Book(code: "Hos", name: "Hosea", chapters: 14, testament: 0, order: 27),
        Book(code: "Joe", name: "Joel", chapters: 3, testament: 0, order: 28),
        Book(code: "Amo", name: "Amos", chapters: 9, testament: 0, order: 29),
        Book(code: "Oba", name: "Obadiah", chapters: 1, testament: 0, order: 30),
        Book(code: "Jon", name: "Jonah", chapters: 4, testament: 0, order: 31),
        Book(code: "Mic", name: "Micah", chapters: 7, testament: 0, order: 32),
        Book(code: "Nah", name: "Nahum", chapters: 3, testament: 0, order: 33),
        Book(code: "Hab", name: "Habakkuk", chapters: 3, testament: 0, order: 34),
        Book(code: "Zep", name: "Zephaniah", chapters: 3, testament: 0, order: 35),
        Book(code: "Hag", name: "Haggai", chapters: 2, testament: 0, order: 36),
        Book(code: "Zec", name: "Zechariah", chapters: 14, testament: 0, order: 37),
        Book(code: "Mal", name: "Malachi", chapters: 4, testament: 0, order: 38),

        // — NEW TESTAMENT (27 books) —
        Book(code: "Mat", name: "Matthew", chapters: 28, testament: 1, order: 39),
        Book(code: "Mrk", name: "Mark", chapters: 16, testament: 1, order: 40),
        Book(code: "Luk", name: "Luke", chapters: 24, testament: 1, order: 41),
        Book(code: "Joh", name: "John", chapters: 21, testament: 1, order: 42),
        Book(code: "Act", name: "Acts", chapters: 28, testament: 1, order: 43),
        Book(code: "Rom", name: "Romans", chapters: 16, testament: 1, order: 44),
        Book(code: "1Co", name: "1 Corinthians", chapters: 16, testament: 1, order: 45),
        Book(code: "2Co", name: "2 Corinthians", chapters: 13, testament: 1, order: 46),
        Book(code: "Gal", name: "Galatians", chapters: 6, testament: 1, order: 47),
        Book(code: "Eph", name: "Ephesians", chapters: 6, testament: 1, order: 48),
        Book(code: "Phi", name: "Philippians", chapters: 4, testament: 1, order: 49),
        Book(code: "Col", name: "Colossians", chapters: 4, testament: 1, order: 50),
        Book(code: "1Th", name: "1 Thessalonians", chapters: 5, testament: 1, order: 51),
        Book(code: "2Th", name: "2 Thessalonians", chapters: 3, testament: 1, order: 52),
        Book(code: "1Ti", name: "1 Timothy", chapters: 6, testament: 1, order: 53),
        Book(code: "2Ti", name: "2 Timothy", chapters: 4, testament: 1, order: 54),
        Book(code: "Tit", name: "Titus", chapters: 3, testament: 1, order: 55),
        Book(code: "Phm", name: "Philemon", chapters: 1, testament: 1, order: 56),
        Book(code: "Heb", name: "Hebrews", chapters: 13, testament: 1, order: 57),
        Book(code: "Jam", name: "James", chapters: 5, testament: 1, order: 58),
        Book(code: "1Pe", name: "1 Peter", chapters: 5, testament: 1, order: 59),
        Book(code: "2Pe", name: "2 Peter", chapters: 3, testament: 1, order: 60),
        Book(code: "1Jo", name: "1 John", chapters: 5, testament: 1, order: 61),
        Book(code: "2Jo", name: "2 John", chapters: 1, testament: 1, order: 62),
        Book(code: "3Jo", name: "3 John", chapters: 1, testament: 1, order: 63),
        Book(code: "Jud", name: "Jude", chapters: 1, testament: 1, order: 64),
        Book(code: "Rev", name: "Revelation", chapters: 22, testament: 1, order: 65),
    ]

    static var oldTestament: [Book] { books.filter { $0.testament == 0 } }
    static var newTestament: [Book] { books.filter { $0.testament == 1 } }

    static func book(for code: String) -> Book? { books.first { $0.code == code } }

    /// Chapter labels for display (e.g. "1", "2", … "N").
    static func chapters(for book: Book) -> [Int] {
        Array(1...book.chapters)
    }
}
