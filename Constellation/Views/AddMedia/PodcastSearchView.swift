import SwiftUI
import SwiftData

struct PodcastSearchView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var searchResults: [PodcastIndexShow] = []
    @State private var isSearching = false
    @State private var selectedShow: PodcastIndexShow?
    @State private var searchErrorMessage: String?

    var body: some View {
        NavigationStack {
            VStack {
                if isSearching {
                    ProgressView("Searching podcasts...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let searchErrorMessage {
                    ContentUnavailableView(
                        "Search Error",
                        systemImage: "exclamationmark.triangle",
                        description: Text(searchErrorMessage)
                    )
                } else if searchResults.isEmpty && !searchText.isEmpty {
                    ContentUnavailableView(
                        "No Shows Found",
                        systemImage: "mic",
                        description: Text("Try a different podcast show query")
                    )
                } else if searchResults.isEmpty {
                    ContentUnavailableView(
                        "Search Podcast Shows",
                        systemImage: "waveform.circle",
                        description: Text("Find a show, then add episodes or add the whole show")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(searchResults) { show in
                                PodcastShowSearchCard(show: show)
                                    .onTapGesture { selectedShow = show }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Add Podcast")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .searchable(text: $searchText, prompt: "Search shows")
            .onChange(of: searchText) { _, value in
                Task { await performSearch(query: value) }
            }
            .sheet(item: $selectedShow) { show in
                PodcastShowAddSheet(show: show)
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
            try await Task.sleep(nanoseconds: 400_000_000)
            guard trimmed == searchText.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            searchResults = try await PodcastIndexService.shared.searchShows(query: trimmed, limit: 30)
        } catch {
            searchResults = []
            searchErrorMessage = error.localizedDescription
        }
    }
}

private struct PodcastShowSearchCard: View {
    let show: PodcastIndexShow

    var body: some View {
        HStack(spacing: 12) {
            if let imageURL = show.imageURL {
                AsyncImage(url: imageURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.25))
                        .overlay { Image(systemName: "mic.fill") }
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.25))
                    .frame(width: 64, height: 64)
                    .overlay { Image(systemName: "mic.fill") }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(show.title)
                    .font(.headline)
                    .lineLimit(2)

                if let author = show.author, !author.isEmpty {
                    Text(author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct PodcastShowAddSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var existingEpisodes: [PodcastEpisode]

    let show: PodcastIndexShow

    @State private var episodes: [PodcastIndexEpisode] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var didAddCount: Int?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                Divider()

                if isLoading {
                    ProgressView("Loading episodes...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    ContentUnavailableView(
                        "Load Error",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else if episodes.isEmpty {
                    ContentUnavailableView(
                        "No Episodes",
                        systemImage: "waveform",
                        description: Text("No episodes returned for this show")
                    )
                } else {
                    List {
                        ForEach(episodes) { episode in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(episode.title)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(2)

                                HStack(spacing: 8) {
                                    if let duration = episode.durationMinutes {
                                        Text("\(duration) min")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if let published = episode.datePublished {
                                        Text("•")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(published.formatted(date: .abbreviated, time: .omitted))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                HStack {
                                    Spacer()
                                    Button(isExisting(episode) ? "Added" : "Add Episode") {
                                        addEpisode(episode)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(isExisting(episode))
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(show.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add Show") {
                        addWholeShow()
                    }
                    .disabled(episodes.isEmpty)
                }
            }
            .task {
                await loadEpisodes()
            }
            .alert("Added Episodes", isPresented: Binding(
                get: { didAddCount != nil },
                set: { if !$0 { didAddCount = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Added \(didAddCount ?? 0) new episodes.")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                if let imageURL = show.imageURL {
                    AsyncImage(url: imageURL) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(show.title)
                        .font(.headline)
                        .lineLimit(2)
                    if let author = show.author, !author.isEmpty {
                        Text(author)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            if let description = show.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding()
    }

    private func loadEpisodes() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            if show.id > 0 {
                episodes = try await PodcastIndexService.shared.fetchEpisodes(for: show, max: 60)
            } else {
                let candidates = try await PodcastIndexService.shared.searchShows(query: show.title, limit: 10)
                let normalizedTitle = show.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let preferred = candidates.first(where: { candidate in
                    candidate.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedTitle
                    || (show.feedURL != nil && candidate.feedURL == show.feedURL)
                }) ?? candidates.first

                if let preferred {
                    episodes = try await PodcastIndexService.shared.fetchEpisodes(for: preferred, max: 60)
                } else {
                    episodes = []
                }
            }
        } catch {
            episodes = []
            errorMessage = error.localizedDescription
        }
    }

    private func addWholeShow() {
        var addCount = 0
        for episode in episodes {
            guard !isExisting(episode) else { continue }
            modelContext.insert(makeEpisode(episode))
            addCount += 1
        }
        try? modelContext.save()
        didAddCount = addCount
    }

    private func addEpisode(_ episode: PodcastIndexEpisode) {
        guard !isExisting(episode) else { return }
        modelContext.insert(makeEpisode(episode))
        try? modelContext.save()
    }

    private func makeEpisode(_ episode: PodcastIndexEpisode) -> PodcastEpisode {
        PodcastEpisode(
            title: episode.title,
            showName: show.title,
            showAuthor: show.author,
            episodeNumber: nil,
            releaseDate: episode.datePublished,
            durationSeconds: episode.durationMinutes.map { $0 * 60 },
            overview: episode.description,
            audioURL: episode.enclosureURL?.absoluteString,
            thumbnailURL: episode.imageURL?.absoluteString ?? show.imageURL?.absoluteString,
            feedURL: episode.feedURL ?? show.feedURL,
            episodeGUID: episode.guid,
            podcastIndexEpisodeID: episode.id,
            podcastIndexFeedID: episode.feedID ?? show.id,
            genres: [],
            transcriptURL: episode.transcriptURL
        )
    }

    private func isExisting(_ episode: PodcastIndexEpisode) -> Bool {
        let normalizedTitle = episode.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedShow = show.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return existingEpisodes.contains { existing in
            if let existingID = existing.podcastIndexEpisodeID, existingID == episode.id {
                return true
            }

            if let guid = episode.guid, !guid.isEmpty,
               let existingGUID = existing.episodeGUID, existingGUID == guid,
               (existing.podcastIndexFeedID == (episode.feedID ?? show.id) || existing.feedURL == (episode.feedURL ?? show.feedURL)) {
                return true
            }

            return existing.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedTitle
                && existing.showName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedShow
                && sameDay(existing.releaseDate, episode.datePublished)
        }
    }

    private func sameDay(_ lhs: Date?, _ rhs: Date?) -> Bool {
        guard let lhs, let rhs else { return false }
        return Calendar.current.isDate(lhs, inSameDayAs: rhs)
    }
}

#Preview {
    PodcastSearchView()
        .modelContainer(for: PodcastEpisode.self, inMemory: true)
}
