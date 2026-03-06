import SwiftUI
import SwiftData

struct BookSearchView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var searchResults: [HardcoverBooksService.SearchBook] = []
    @State private var isSearching = false
    @State private var selectedBook: HardcoverBooksService.SearchBook?
    @State private var searchErrorMessage: String?

    var body: some View {
        NavigationStack {
            VStack {
                if isSearching {
                    ProgressView("Searching books...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let searchErrorMessage {
                    ContentUnavailableView(
                        "Search Error",
                        systemImage: "exclamationmark.triangle",
                        description: Text(searchErrorMessage)
                    )
                } else if searchResults.isEmpty && !searchText.isEmpty {
                    ContentUnavailableView(
                        "No Results",
                        systemImage: "book",
                        description: Text("Try another title or author")
                    )
                } else if searchResults.isEmpty {
                    ContentUnavailableView(
                        "Search for Books",
                        systemImage: "books.vertical",
                        description: Text("Powered by Hardcover")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(searchResults) { book in
                                BookSearchCard(book: book)
                                    .onTapGesture { selectedBook = book }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Add Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .searchable(text: $searchText, prompt: "Search books")
            .onChange(of: searchText) { _, value in
                Task { await performSearch(query: value) }
            }
            .sheet(item: $selectedBook) { book in
                BookDetailSheet(book: book)
            }
        }
    }

    private func performSearch(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            searchErrorMessage = nil
            return
        }

        isSearching = true
        searchErrorMessage = nil
        defer { isSearching = false }

        do {
            try await Task.sleep(nanoseconds: 320_000_000)
            guard trimmed == searchText.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            searchResults = try await HardcoverBooksService.shared.searchBooks(query: trimmed)
        } catch {
            searchResults = []
            searchErrorMessage = error.localizedDescription
        }
    }
}

private struct BookSearchCard: View {
    let book: HardcoverBooksService.SearchBook

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: book.coverURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.25))
                    .overlay { Image(systemName: "book.closed") }
            }
            .frame(width: 60, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(2)

                if let author = book.author {
                    Text(author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    if let year = book.year {
                        Text(String(year))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let pages = book.pageCount {
                        Text("\(pages) pages")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let rating = book.rating {
                        Text("★ \(String(format: "%.1f", rating))")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct BookDetailSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var existingBooks: [Book]

    let book: HardcoverBooksService.SearchBook
    @State private var addStatus: AddStatus = .planned
    @State private var readDate = Date()
    @State private var notes = ""
    @State private var showDuplicateAlert = false

    private enum AddStatus: String, CaseIterable, Identifiable {
        case planned
        case completed
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AsyncImage(url: book.coverURL) { image in
                        image.resizable().aspectRatio(contentMode: .fit)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.25))
                            .aspectRatio(2/3, contentMode: .fit)
                            .overlay { Image(systemName: "book.closed") }
                    }
                    .frame(height: 300)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Text(book.title)
                        .font(.title2.bold())
                    if let author = book.author {
                        Text(author).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 10) {
                        if let year = book.year {
                            Text(String(year)).font(.caption).foregroundStyle(.secondary)
                        }
                        if let pages = book.pageCount {
                            Text("\(pages) pages").font(.caption).foregroundStyle(.secondary)
                        }
                        if let rating = book.rating {
                            if let count = book.ratingCount {
                                Text("★ \(String(format: "%.1f", rating)) (\(count))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("★ \(String(format: "%.1f", rating))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if !book.subjects.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(book.subjects.prefix(5), id: \.self) { subject in
                                    Text(subject)
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.orange.opacity(0.18))
                                        .foregroundStyle(.orange)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }

                    Divider()

                    Picker("Status", selection: $addStatus) {
                        Text("Planned").tag(AddStatus.planned)
                        Text("Completed").tag(AddStatus.completed)
                    }
                    .pickerStyle(.segmented)

                    if addStatus == .completed {
                        DatePicker("Completed Date", selection: $readDate, displayedComponents: .date)
                    }

                    TextEditor(text: $notes)
                        .frame(height: 120)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding()
            }
            .navigationTitle("Book Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addBook() }
                }
            }
            .alert("Already Added", isPresented: $showDuplicateAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This book is already in your library.")
            }
        }
    }

    private func addBook() {
        let normalizedTitle = book.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let duplicateExists = existingBooks.contains { existing in
            if let isbn = book.isbn, !isbn.isEmpty, existing.isbn == isbn { return true }
            return existing.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedTitle
        }

        if duplicateExists {
            showDuplicateAlert = true
            return
        }

        let thriftLink: String?
        if let isbn = book.isbn {
            let cleaned = isbn.filter { $0.isNumber || $0 == "X" || $0 == "x" }
            if cleaned.isEmpty {
                thriftLink = nil
            } else {
                let encoded = cleaned.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cleaned
                thriftLink = "https://www.thriftbooks.com/browse/?b.search=\(encoded)"
            }
        } else {
            thriftLink = nil
        }

        let newBook = Book(
            title: book.title,
            year: book.year,
            author: book.author,
            coverURL: book.coverURL?.absoluteString,
            overview: book.description,
            genres: book.primaryGenre.map { [$0] } ?? book.subjects,
            pageCount: book.pageCount,
            rating: book.rating,
            ratingCount: book.ratingCount,
            watchedDate: addStatus == .completed ? readDate : nil,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes,
            isbn: book.isbn,
            infoURL: book.slug.flatMap { "https://hardcover.app/books/\($0)" },
            thriftBooksURL: thriftLink,
            hasAudiobook: book.hasAudiobook,
            hasEbook: book.hasEbook
        )

        modelContext.insert(newBook)
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    BookSearchView()
        .modelContainer(for: Book.self, inMemory: true)
}
