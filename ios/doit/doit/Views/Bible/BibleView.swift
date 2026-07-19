import SwiftUI

/// Root Bible view: book list sectioned by Old / New Testament.
struct BibleView: View {
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            bookList
                .navigationDestination(for: Book.self) { book in
                    if book.chapters == 1 {
                        // Single-chapter books skip the grid
                        BibleReadingView(book: book, chapter: 1)
                    } else {
                        ChapterGridView(book: book, chapters: BibleDataService.chapters(for: book))
                    }
                }
                .navigationDestination(for: BibleDestination.self) { dest in
                    switch dest {
                    case .chapterGrid(let book):
                        ChapterGridView(book: book, chapters: BibleDataService.chapters(for: book))
                    case .reading(let book, let chapter):
                        BibleReadingView(book: book, chapter: chapter)
                    }
                }
        }
    }

    // MARK: - Book List

    private var bookList: some View {
        ScrollView {
            VStack(spacing: 0) {
                header

                testamentSection(title: "Old Testament", books: BibleDataService.oldTestament)
                testamentSection(title: "New Testament", books: BibleDataService.newTestament)
            }
        }
        .background(AppSemanticColors.screenBackground)
        .navigationTitle("Bible")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.automatic)
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("Recovery Version")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Text("66 books")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private func testamentSection(title: String, books: [Book]) -> some View {
        VStack(spacing: 0) {
            BibleSectionLabel(title.uppercased())

            LazyVStack(spacing: 0) {
                ForEach(Array(books.enumerated()), id: \.element.code) { index, book in
                    NavigationLink(value: book) {
                        BookRow(book: book)
                    }
                    .buttonStyle(.plain)

                    if index < books.count - 1 {
                        BibleDivider(leadingPadding: 66)
                    }
                }
            }
            .background(AppSemanticColors.elevatedSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Book Row

struct BookRow: View {
    let book: Book

    var body: some View {
        HStack(spacing: 14) {
            // Book code badge
            Text(book.code)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 40, height: 28)
                .background(book.testament == 0 ? Color.indigo : Color.teal)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(book.name)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                Text("\(book.chapters) \(book.chapters == 1 ? "chapter" : "chapters")")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - Chapter Grid

struct ChapterGridView: View {
    let book: Book
    let chapters: [Int]

    private let columns = [
        GridItem(.adaptive(minimum: 52, maximum: 64), spacing: 10)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Book header
                Text(book.name)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 4)

                Text("\(book.chapters) chapters")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(chapters, id: \.self) { chapter in
                        NavigationLink(value: BibleDestination.reading(book: book, chapter: chapter)) {
                            ChapterCell(number: chapter)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .background(AppSemanticColors.screenBackground)
        .navigationTitle(book.code)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ChapterCell: View {
    let number: Int

    var body: some View {
        Text("\(number)")
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(AppSemanticColors.connectButtonForeground)
            .frame(width: 52, height: 52)
            .background(AppSemanticColors.connectButtonBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppSemanticColors.connectButtonBorder, lineWidth: 1)
            }
    }
}

// MARK: - Verse reading view with VerticalSplit

struct BibleReadingView: View {
    let book: Book
    let chapter: Int

    @State private var verses: [BibleVerse] = []
    @State private var selectedFootnote: BibleFootnote?
    @State private var expandedVerse: Int?
    @State private var isLoading = true
    @State private var splitDetent: SplitDetent = .bottomMini

    var body: some View {
        VerticalSplit(
            detent: $splitDetent,
            topTitle: book.name,
            bottomTitle: "Footnotes",
            topView: {
                VerseScrollView(
                    book: book,
                    chapter: chapter,
                    verses: verses,
                    isLoading: isLoading,
                    copyright: BibleAPIService.copyright(for: book.code),
                    expandedVerse: $expandedVerse,
                    selectedFootnote: $selectedFootnote
                )
            },
            bottomView: {
                if let fn = selectedFootnote {
                    FootnotePanel(
                        footnote: fn,
                        onDismiss: {
                            withAnimation(.spring(response: 0.35)) {
                                selectedFootnote = nil
                            }
                        }
                    )
                    .transition(.opacity)
                } else {
                    FootnotesPlaceholder()
                }
            }
        )
        .background(AppSemanticColors.screenBackground)
        .navigationTitle(book.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            isLoading = true
            BibleAPIService.preload(bookCode: book.code)
            verses = BibleAPIService.verses(for: book.code, chapter: chapter)
            isLoading = false
        }
    }
}

// MARK: - Verse Scroll View

private struct VerseScrollView: View {
    let book: Book
    let chapter: Int
    let verses: [BibleVerse]
    let isLoading: Bool
    let copyright: String
    @Binding var expandedVerse: Int?
    @Binding var selectedFootnote: BibleFootnote?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Chapter header
                Text("\(book.name) \(chapter)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 16)

                if isLoading {
                    VStack(spacing: 12) {
                        ForEach(0..<5, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.15))
                                .frame(height: 14)
                        }
                    }
                    .padding(.horizontal, 20)
                } else if verses.isEmpty {
                    Text("No verses found for \(book.name) \(chapter).")
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(verses, id: \.id) { verse in
                            VerseRow(
                                verse: verse,
                                bookCode: book.code,
                                chapter: chapter,
                                isExpanded: expandedVerse == verse.verse,
                                onToggle: {
                                    withAnimation(.spring(response: 0.3)) {
                                        if expandedVerse == verse.verse {
                                            expandedVerse = nil
                                        } else {
                                            expandedVerse = verse.verse
                                        }
                                    }
                                },
                                onFootnoteTapped: { fn in
                                    selectedFootnote = fn
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                    // LSM copyright attribution
                    Text(copyright)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.visible)
    }
}

// MARK: - Single verse row with expandable footnotes

private struct VerseRow: View {
    let verse: BibleVerse
    let bookCode: String
    let chapter: Int
    let isExpanded: Bool
    let onToggle: () -> Void
    let onFootnoteTapped: (BibleFootnote) -> Void

    @State private var verseFootnotes: [BibleFootnote] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Verse header with number and footnote badge
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(verse.verse)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .frame(minWidth: 24, alignment: .trailing)

                // Verse text
                InlineVerseText(
                    text: verse.text,
                    markers: verse.footnoteMarkers
                )
            }
            .padding(.top, 10)
            .padding(.bottom, isExpanded ? 8 : 6)
            .contentShape(Rectangle())
            .onTapGesture {
                if !verse.footnoteMarkers.isEmpty {
                    onToggle()
                    if verseFootnotes.isEmpty {
                        verseFootnotes = BibleAPIService.footnotes(
                            for: bookCode,
                            chapter: chapter,
                            verse: verse.verse
                        )
                    }
                }
            }

            // Expandable footnote list
            if isExpanded && !verseFootnotes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(verseFootnotes, id: \.id) { fn in
                        FootnotePreview(footnote: fn)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onFootnoteTapped(fn)
                            }
                    }
                }
                .padding(.leading, 30)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Plain-text verse rendering with styled markers

private struct InlineVerseText: View {
    let text: String
    let markers: [FootnoteMarker]

    var body: some View {
        let segments = parseSegments()
        let result = segments.reduce(Text("")) { acc, segment in
            switch segment {
            case .plain(let str):
                return acc + Text(str)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundStyle(.primary)
            case .styledMarker(let markerText):
                return acc + Text("[\(markerText)]")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
                    .baselineOffset(4)
            }
        }
        result.lineSpacing(4)
    }

    private enum Segment {
        case plain(String)
        case styledMarker(String)
    }

    private func parseSegments() -> [Segment] {
        let pattern = try! NSRegularExpression(pattern: "\\[([^\\]]+)\\]")
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = pattern.matches(in: text, range: nsRange)
        guard !matches.isEmpty else { return [.plain(text)] }

        var segments: [Segment] = []
        var lastEnd = text.startIndex
        for match in matches {
            let matchRange = Range(match.range, in: text)!
            let markerRange = Range(match.range(at: 1), in: text)!
            if lastEnd < matchRange.lowerBound {
                segments.append(.plain(String(text[lastEnd..<matchRange.lowerBound])))
            }
            segments.append(.styledMarker(String(text[markerRange])))
            lastEnd = matchRange.upperBound
        }
        if lastEnd < text.endIndex {
            segments.append(.plain(String(text[lastEnd...])))
        }
        return segments
    }
}

// MARK: - Footnote preview card

private struct FootnotePreview: View {
    let footnote: BibleFootnote

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("[\(footnote.marker)]")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.accentColor)
                .baselineOffset(2)

            Text(footnote.text)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
    }
}

// MARK: - Footnote bottom panel

private struct FootnotePanel: View {
    let footnote: BibleFootnote
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header bar
            HStack {
                Text("Footnote \(footnote.marker)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.accentColor)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            // Footnote text
            ScrollView {
                Text(footnote.text)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !footnote.crossReferences.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cross References")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 12)

                        ForEach(footnote.crossReferences, id: \.self) { ref in
                            Text(ref)
                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(AppSemanticColors.elevatedSurface)
    }
}

// MARK: - Footnotes placeholder

private struct FootnotesPlaceholder: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.book.closed")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)

            Text("Footnotes coming in Phase 2")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            Text("Tap a verse with footnote markers to view footnotes here.")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppSemanticColors.elevatedSurface)
    }
}

// MARK: - Reusable components

struct BibleSectionLabel: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }
}

struct BibleDivider: View {
    var leadingPadding: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(AppSemanticColors.neutralFill)
            .frame(height: 1)
            .padding(.leading, leadingPadding)
    }
}
