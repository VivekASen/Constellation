import SwiftUI
import SwiftData

struct PodcastLibraryShowDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var existingEpisodes: [PodcastEpisode]
    @State private var showingAddEpisodes = false

    let group: PodcastLibraryShowGroup

    private var episodesForShow: [PodcastEpisode] {
        existingEpisodes.filter {
            $0.showName.caseInsensitiveCompare(group.name) == .orderedSame
        }
        .sorted(by: sortEpisodesNewestFirst)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ConstellationStarHeroHeader(
                    posterURL: group.artworkURL ?? episodesForShow.first?.thumbnailURL,
                    symbol: "mic.fill",
                    title: group.name,
                    subtitle: hostLine,
                    metrics: heroMetrics,
                    posterSize: CGSize(width: 138, height: 138)
                )

                VStack(alignment: .leading, spacing: 12) {
                    Text("Added Episodes")
                        .font(ConstellationTypeScale.sectionTitle)

                    if episodesForShow.isEmpty {
                        Text("Add episodes from search to populate this show.")
                            .font(ConstellationTypeScale.body)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(episodesForShow) { episode in
                            NavigationLink(destination: PodcastEpisodeDetailView(episode: episode)) {
                                PodcastEpisodeProgressRow(episode: episode)
                            }
                            .buttonStyle(.plain)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white.opacity(0.86))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .contextMenu {
                                Button {
                                    toggleCompletion(for: episode)
                                } label: {
                                    Label(
                                        episode.completedAt == nil ? "Mark Complete" : "Mark Incomplete",
                                        systemImage: episode.completedAt == nil ? "checkmark.circle" : "arrow.uturn.backward.circle"
                                    )
                                }
                                Button(role: .destructive) {
                                    removeEpisode(episode)
                                } label: {
                                    Label("Remove Episode", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(episode.completedAt == nil ? "Complete" : "Incomplete") {
                                    toggleCompletion(for: episode)
                                }
                                .tint(episode.completedAt == nil ? .green : .orange)
                                Button(role: .destructive) { removeEpisode(episode) } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ConstellationPalette.surfaceStrong)
            }
        }
        .ignoresSafeArea(edges: .top)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddEpisodes = true
                } label: {
                    Label("Add Episodes", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddEpisodes) {
            PodcastShowAddSheet(show: scopedShow)
        }
    }

    private func sortEpisodesNewestFirst(_ lhs: PodcastEpisode, _ rhs: PodcastEpisode) -> Bool {
        (lhs.releaseDate ?? lhs.dateAdded) > (rhs.releaseDate ?? rhs.dateAdded)
    }

    private var heroMetrics: [ConstellationHeroMetric] {
        let inProgress = episodesForShow.filter { episode in
            episode.completedAt == nil && episode.currentPositionSeconds > 0
        }.count
        let completed = episodesForShow.filter { $0.completedAt != nil }.count
        return [
            ConstellationHeroMetric(value: "\(episodesForShow.count)", label: "Added Episodes", icon: "plus.circle"),
            ConstellationHeroMetric(value: "\(inProgress)", label: "In Progress", icon: "play.circle"),
            ConstellationHeroMetric(value: "\(completed)", label: "Completed", icon: "checkmark.circle")
        ]
    }

    private var hostLine: String? {
        episodesForShow.compactMap(\.showAuthor).first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    private var scopedShow: PodcastIndexShow {
        PodcastIndexShow(
            id: group.feedID ?? episodesForShow.compactMap(\.podcastIndexFeedID).first ?? -1,
            title: group.name,
            author: hostLine,
            description: nil,
            imageURL: URL(string: group.artworkURL ?? ""),
            feedURL: group.feedURL ?? episodesForShow.compactMap(\.feedURL).first
        )
    }

    private func removeEpisode(_ episode: PodcastEpisode) {
        modelContext.delete(episode)
        try? modelContext.save()
    }

    private func toggleCompletion(for episode: PodcastEpisode) {
        if episode.completedAt == nil {
            episode.completedAt = Date()
        } else {
            episode.completedAt = nil
        }
        try? modelContext.save()
    }
}
