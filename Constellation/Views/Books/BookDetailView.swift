import SwiftUI
import SwiftData

struct BookDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var book: Book

    @State private var ratingValue: Double = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AsyncImage(url: URL(string: book.coverURL ?? "")) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .aspectRatio(2/3, contentMode: .fit)
                        .overlay { Image(systemName: "book.closed") }
                }
                .frame(height: 300)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Text(book.title)
                    .font(.title2.bold())

                if let author = book.author {
                    Text(author)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    if let year = book.year {
                        Text(String(year)).font(.caption).foregroundStyle(.secondary)
                    }
                    if let pages = book.pageCount {
                        Text("\(pages) pages").font(.caption).foregroundStyle(.secondary)
                    }
                }

                if let overview = book.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                if !book.themes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Themes").font(.headline)
                        Text(book.themes.map { $0.replacingOccurrences(of: "-", with: " ").capitalized }.joined(separator: " • "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if let notes = book.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes").font(.headline)
                        Text(notes).font(.body)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Rating").font(.headline)
                    HStack(spacing: 8) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= Int(ratingValue) ? "star.fill" : "star")
                                .foregroundStyle(.yellow)
                                .onTapGesture {
                                    ratingValue = Double(star)
                                    book.rating = ratingValue
                                    try? modelContext.save()
                                }
                        }
                    }
                    .font(.title3)
                }
            }
            .padding()
        }
        .navigationTitle("Book")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            ratingValue = book.rating ?? 0
        }
    }
}
