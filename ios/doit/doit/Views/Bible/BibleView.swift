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

// MARK: - Placeholder reading view

struct BibleReadingView: View {
    let book: Book
    let chapter: Int

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(book.name) \(chapter)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                Text("Verse content will load here once the HTML parser is complete and the Bible data is available in Supabase.")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }
        }
        .background(AppSemanticColors.screenBackground)
        .navigationTitle("Chapter \(chapter)")
        .navigationBarTitleDisplayMode(.inline)
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
