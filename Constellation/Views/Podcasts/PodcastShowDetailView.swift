import SwiftUI
import SwiftData

struct PodcastShowDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    let showName: String
    let episodes: [PodcastEpisode]
    @State private var showingAddEpisodes = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ConstellationStarHeroHeader(
                    posterURL: sortedEpisodes.first?.thumbnailURL,
                    symbol: "mic.fill",
                    title: showName,
                    subtitle: hostLine,
                    metrics: heroMetrics,
                    posterSize: CGSize(width: 138, height: 138)
                )

                VStack(alignment: .leading, spacing: 12) {
                    Text("Latest Episodes")
                        .font(ConstellationTypeScale.sectionTitle)

                    if sortedEpisodes.isEmpty {
                        Text("No episodes added yet.")
                            .font(ConstellationTypeScale.body)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sortedEpisodes.prefix(5)) { episode in
                            NavigationLink(destination: PodcastEpisodeDetailView(episode: episode)) {
                                PodcastEpisodeProgressRow(episode: episode)
                            }
                            .buttonStyle(.plain)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(cardBackground)
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

    private var sortedEpisodes: [PodcastEpisode] {
        episodes.sorted { lhs, rhs in
            (lhs.releaseDate ?? lhs.dateAdded) > (rhs.releaseDate ?? rhs.dateAdded)
        }
    }

    private var heroMetrics: [ConstellationHeroMetric] {
        let inProgress = episodes.filter { episode in
            episode.completedAt == nil && episode.currentPositionSeconds > 0
        }.count
        let completed = episodes.filter { $0.completedAt != nil }.count
        return [
            ConstellationHeroMetric(value: "\(episodes.count)", label: "Added Episodes", icon: "plus.circle"),
            ConstellationHeroMetric(value: "\(inProgress)", label: "In Progress", icon: "play.circle"),
            ConstellationHeroMetric(value: "\(completed)", label: "Completed", icon: "checkmark.circle")
        ]
    }

    private var hostLine: String? {
        sortedEpisodes.compactMap(\.showAuthor).first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.86)
    }

    private var scopedShow: PodcastIndexShow {
        PodcastIndexShow(
            id: sortedEpisodes.compactMap(\.podcastIndexFeedID).first ?? -1,
            title: showName,
            author: hostLine,
            description: nil,
            imageURL: URL(string: sortedEpisodes.compactMap(\.thumbnailURL).first ?? ""),
            feedURL: sortedEpisodes.compactMap(\.feedURL).first
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

struct PodcastShowCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let showName: String
    let episodes: [PodcastEpisode]

    var body: some View {
        NavigationLink(destination: PodcastShowDetailView(showName: showName, episodes: episodes)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(showName)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text("\(episodes.count)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.purple.opacity(0.14))
                        .foregroundStyle(.purple)
                        .clipShape(Capsule())
                }

                if let latest = latestEpisode {
                    PodcastEpisodeProgressRow(episode: latest)
                }
            }
            .padding()
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.86)
    }

    private var latestEpisode: PodcastEpisode? {
        episodes.max {
            ($0.releaseDate ?? $0.dateAdded) < ($1.releaseDate ?? $1.dateAdded)
        }
    }
}

struct PodcastEpisodeProgressRow: View {
    let episode: PodcastEpisode

    private var progress: Double {
        guard let duration = episode.durationSeconds, duration > 0 else { return 0 }
        return min(max(episode.currentPositionSeconds / Double(duration), 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(episode.title)
                .font(ConstellationTypeScale.supporting.weight(.semibold))
                .lineLimit(2)

            HStack(spacing: 8) {
                if let date = episode.releaseDate {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(ConstellationTypeScale.caption)
                        .foregroundStyle(.secondary)
                }

                if let minutes = episode.durationMinutes {
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(minutes) min")
                        .font(ConstellationTypeScale.caption)
                        .foregroundStyle(.secondary)
                }

                if episode.completedAt != nil {
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Completed")
                        .font(ConstellationTypeScale.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }

            if episode.completedAt == nil, progress > 0 {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.blue)
            }
        }
    }
}
