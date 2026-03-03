import SwiftUI
import SwiftData

struct BookSearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var existingBooks: [Book]

    @State private var searchText = ""
    @State private var searchResults: [OpenLibraryBook] = []
    @State private var isSearching = false
    @State private var selectedBook: OpenLibraryBook?

    var body: some View {
        NavigationStack {
            VStack {
                if isSearching {
                    ProgressView("Searching books...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if searchResults.isEmpty && !searchText.isEmpty {
                    ContentUnavailableView(
                        "No Results",
                        systemImage: "book",
                        description: Text("Try a different query")
                    )
                } else if searchResults.isEmpty {
                    ContentUnavailableView(
                        "Search for Books",
                        systemImage: "books.vertical",
                        description: Text("Find and add books to your constellation")
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
            return
        }

        isSearching = true
        defer { isSearching = false }

        do {
            try await Task.sleep(nanoseconds: 350_000_000)
            guard trimmed == searchText.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            searchResults = try await OpenLibraryService.shared.searchBooks(query: trimmed)
        } catch {
            searchResults = []
        }
    }
}

private struct BookSearchCard: View {
    let book: OpenLibraryBook

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

    let book: OpenLibraryBook
    @State private var addStatus: AddStatus = .watchlist
    @State private var readDate = Date()
    @State private var notes = ""
    @State private var rating: Double = 0
    @State private var showDuplicateAlert = false

    private enum AddStatus: String, CaseIterable, Identifiable {
        case watchlist
        case watched
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
                    }

                    if !book.subjects.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(book.subjects, id: \.self) { subject in
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
                        Text("To Read").tag(AddStatus.watchlist)
                        Text("Read").tag(AddStatus.watched)
                    }
                    .pickerStyle(.segmented)

                    if addStatus == .watched {
                        DatePicker("Read Date", selection: $readDate, displayedComponents: .date)
                        HStack(spacing: 8) {
                            ForEach(1...5, id: \.self) { star in
                                Image(systemName: star <= Int(rating) ? "star.fill" : "star")
                                    .foregroundStyle(.yellow)
                                    .onTapGesture { rating = Double(star) }
                            }
                        }
                        .font(.title3)
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
                    Button(addStatus == .watchlist ? "Add to Readlist" : "Add as Read") {
                        addBook()
                    }
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
            if let existingWorkKey = existing.openLibraryWorkKey, existingWorkKey == book.key { return true }
            let yearMatches = existing.year == nil || book.year == nil || existing.year == book.year
            return existing.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedTitle && yearMatches
        }
        if duplicateExists {
            showDuplicateAlert = true
            return
        }

        let isRead = addStatus == .watched
        let newBook = Book(
            title: book.title,
            year: book.year,
            author: book.author,
            coverURL: book.coverURL?.absoluteString,
            overview: nil,
            genres: book.subjects,
            pageCount: book.pageCount,
            rating: isRead && rating > 0 ? rating : nil,
            watchedDate: isRead ? readDate : nil,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes,
            openLibraryWorkKey: book.key,
            isbn: book.isbn
        )

        modelContext.insert(newBook)

        Task {
            let themes = await ThemeExtractor.shared.extractThemes(from: newBook)
            newBook.themes = themes
            try? modelContext.save()
        }

        dismiss()
    }
}

#Preview {
    BookSearchView()
        .modelContainer(for: Book.self, inMemory: true)
}
