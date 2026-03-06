import SwiftData
import SwiftUI

struct PodcastEpisodeDetailView: View {
    @EnvironmentObject private var playerStore: PodcastPlayerStore
    @Bindable var episode: PodcastEpisode
    @Query private var allHighlights: [PodcastHighlight]

    @State private var showingNotesWorkspace = false

    private var isCurrentEpisode: Bool {
        playerStore.currentEpisode?.id == episode.id
    }

    private var playbackSeconds: Double {
        if isCurrentEpisode { return playerStore.currentTime }
        return episode.currentPositionSeconds
    }

    private var playbackDuration: Double {
        if isCurrentEpisode, playerStore.duration > 0 { return playerStore.duration }
        return Double(episode.durationSeconds ?? 0)
    }

    private var episodeHighlights: [PodcastHighlight] {
        allHighlights
            .filter { $0.episodeID == episode.id.uuidString }
            .sorted { lhs, rhs in
                if lhs.timestampSeconds == rhs.timestampSeconds {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.timestampSeconds < rhs.timestampSeconds
            }
    }

    private var notesCount: Int { episodeHighlights.count }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ConstellationStarHeroHeader(
                    posterURL: episode.thumbnailURL,
                    symbol: "mic.fill",
                    title: episode.title,
                    subtitle: episode.showName,
                    metrics: heroMetrics,
                    posterSize: CGSize(width: 136, height: 136)
                )

                VStack(alignment: .leading, spacing: 20) {
                    playerSection

                    Button {
                        showingNotesWorkspace = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "note.text.badge.plus")
                                .font(.title3.weight(.semibold))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Open Notes Workspace")
                                    .font(ConstellationTypeScale.sectionTitle)
                                Text("Add timestamped notes while listening.")
                                    .font(ConstellationTypeScale.caption)
                                    .foregroundStyle(.white.opacity(0.86))
                            }
                            Spacer()
                            Text("\(notesCount)")
                                .font(ConstellationTypeScale.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.2))
                                .clipShape(Capsule())
                        }
                        .foregroundStyle(.white)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            LinearGradient(
                                colors: [ConstellationPalette.accent, ConstellationPalette.accentSoft],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    if !episodeHighlights.isEmpty {
                        ConstellationDetailSection("Timestamp Notes") {
                            FlowLayout(spacing: 8) {
                                ForEach(episodeHighlights.prefix(24)) { note in
                                    Button {
                                        playerStore.seek(to: note.timestampSeconds)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(note.timestampFormatted)
                                                .font(ConstellationTypeScale.caption.weight(.semibold))
                                                .foregroundStyle(ConstellationPalette.accent)
                                            Text(note.highlight)
                                                .font(ConstellationTypeScale.caption)
                                                .foregroundStyle(.primary)
                                                .lineLimit(2)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(Color.white.opacity(0.86))
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    if !episode.themes.isEmpty {
                        ConstellationDetailSection("Generated Themes") {
                            FlowLayout(spacing: 8) {
                                ForEach(episode.themes, id: \.self) { theme in
                                    NavigationLink(destination: ThemeDetailView(themeName: theme)) {
                                        ConstellationTagPill(text: theme.replacingOccurrences(of: "-", with: " ").capitalized)
                                    }
                                }
                            }
                        }
                    }

                    if let summaryText = episode.aiSummary ?? episode.overview, !summaryText.isEmpty {
                        ConstellationDetailSection("Episode Summary") {
                            Text(summaryText)
                                .font(ConstellationTypeScale.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ConstellationPalette.surfaceStrong)
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .ignoresSafeArea(edges: .top)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle("Episode")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingNotesWorkspace) {
            NavigationStack {
                PodcastNotesWorkspaceView(episode: episode, currentTimestamp: { playbackSeconds })
            }
        }
        .onAppear { playerStore.suppressFloatingMiniPlayer = true }
        .onDisappear { playerStore.suppressFloatingMiniPlayer = false }
    }

    private var playerSection: some View {
        VStack(spacing: 12) {
            Slider(
                value: Binding(
                    get: { playbackSeconds },
                    set: { playerStore.seek(to: $0) }
                ),
                in: 0...max(playbackDuration, 1)
            )
            .tint(ConstellationPalette.accent)

            HStack {
                Text(formatTime(playbackSeconds))
                    .font(ConstellationTypeScale.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatTime(playbackDuration))
                    .font(ConstellationTypeScale.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ZStack {
                HStack(spacing: 28) {
                    controlButton("gobackward.15", size: 42) { playerStore.skip(by: -15) }
                    controlButton(isCurrentEpisode && playerStore.isPlaying ? "pause.fill" : "play.fill", size: 62, primary: true) {
                        if isCurrentEpisode { playerStore.togglePlayPause() } else { playerStore.play(episode) }
                    }
                    controlButton("goforward.15", size: 42) { playerStore.skip(by: 15) }
                }

                HStack {
                    Spacer()
                    Menu {
                        speedButton(1.0)
                        speedButton(1.25)
                        speedButton(1.5)
                        speedButton(2.0)
                    } label: {
                        Text("\(playerStore.playbackRate, specifier: "%.2gx")")
                            .font(ConstellationTypeScale.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.9))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.52))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(ConstellationPalette.border.opacity(0.6), lineWidth: 0.7)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var heroMetrics: [ConstellationHeroMetric] {
        let progressValue: String = {
            guard playbackDuration > 0 else { return "0%" }
            let percent = Int((playbackSeconds / playbackDuration) * 100)
            return "\(min(max(percent, 0), 100))%"
        }()

        return [
            ConstellationHeroMetric(value: episode.durationMinutes.map { "\($0)m" } ?? "—", label: "Duration", icon: "clock"),
            ConstellationHeroMetric(value: episode.completedAt != nil ? "Done" : progressValue, label: "Progress", icon: "waveform"),
            ConstellationHeroMetric(value: "\(notesCount)", label: "Notes", icon: "note.text")
        ]
    }

    private func controlButton(_ systemName: String, size: CGFloat, primary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(primary ? .title2.weight(.bold) : .title3.weight(.semibold))
                .foregroundStyle(primary ? .white : ConstellationPalette.deepIndigo)
                .frame(width: size, height: size)
                .background(primary ? ConstellationPalette.accent : Color.white.opacity(0.92))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func speedButton(_ value: Float) -> some View {
        Button {
            playerStore.playbackRate = value
            if isCurrentEpisode && playerStore.isPlaying { playerStore.play(episode) }
        } label: {
            if value == playerStore.playbackRate {
                Label("\(value, specifier: "%.2gx")", systemImage: "checkmark")
            } else {
                Text("\(value, specifier: "%.2gx")")
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainingSeconds = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

private struct PodcastNotesWorkspaceView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var playerStore: PodcastPlayerStore
    @Bindable var episode: PodcastEpisode
    let currentTimestamp: () -> Double
    @Query private var allHighlights: [PodcastHighlight]

    @State private var draftText: String = ""
    @State private var isGeneratingThemes = false

    private var isCurrentEpisode: Bool {
        playerStore.currentEpisode?.id == episode.id
    }

    private var notes: [PodcastHighlight] {
        allHighlights
            .filter { $0.episodeID == episode.id.uuidString }
            .sorted { lhs, rhs in
                if lhs.timestampSeconds == rhs.timestampSeconds {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.timestampSeconds < rhs.timestampSeconds
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            playerToolbar
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(ConstellationPalette.surface)

            Divider()

            HStack(spacing: 10) {
                TextField("Write note", text: $draftText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)

                Button {
                    addTimestampNote()
                } label: {
                    VStack(spacing: 2) {
                        Text("Add")
                            .font(ConstellationTypeScale.caption.weight(.semibold))
                        Text(formatTime(currentTimestamp()))
                            .font(ConstellationTypeScale.caption.monospacedDigit())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .foregroundStyle(.white)
                    .background(ConstellationPalette.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()

            Divider()

            if notes.isEmpty {
                VStack(spacing: 8) {
                    Text("No timestamp notes yet")
                        .font(ConstellationTypeScale.supporting.weight(.semibold))
                    Text("Pause or keep listening, then add notes at the exact moment.")
                        .font(ConstellationTypeScale.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(notes) { note in
                            HStack(alignment: .top, spacing: 8) {
                                Button {
                                    playerStore.seek(to: note.timestampSeconds)
                                } label: {
                                    Text(note.timestampFormatted)
                                        .font(ConstellationTypeScale.caption.monospacedDigit().weight(.semibold))
                                        .foregroundStyle(ConstellationPalette.accent)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                        .background(ConstellationPalette.accent.opacity(0.14))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)

                                Text(note.highlight)
                                    .font(ConstellationTypeScale.supporting)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Button(role: .destructive) {
                                    delete(note)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(10)
                            .background(Color.white.opacity(0.82))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    .padding()
                }
            }

            Divider()

            Button {
                Task { await generateThemesFromNotes() }
            } label: {
                HStack {
                    if isGeneratingThemes {
                        ProgressView().tint(ConstellationPalette.accent)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text("Generate Themes Based on Your Notes")
                        .font(ConstellationTypeScale.supporting.weight(.semibold))
                    Spacer()
                }
                .padding()
                .background(ConstellationPalette.accent.opacity(0.12))
                .foregroundStyle(ConstellationPalette.accent)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding()
            }
            .disabled(notes.isEmpty || isGeneratingThemes)
        }
        .navigationTitle("Notes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveAndClose()
                }
            }
        }
    }

    private var playerToolbar: some View {
        HStack(spacing: 12) {
            if isCurrentEpisode {
                Button { playerStore.skip(by: -15) } label: {
                    Image(systemName: "gobackward.15")
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.9))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Button { playerStore.togglePlayPause() } label: {
                    Image(systemName: playerStore.isPlaying ? "pause.fill" : "play.fill")
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(ConstellationPalette.accent)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Button { playerStore.skip(by: 15) } label: {
                    Image(systemName: "goforward.15")
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.9))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            } else {
                Button { playerStore.play(episode) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                        Text("Play Episode")
                            .font(ConstellationTypeScale.caption.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(ConstellationPalette.accent)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Text(formatTime(currentTimestamp()))
                .font(ConstellationTypeScale.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.9))
                .clipShape(Capsule())
        }
    }

    private func addTimestampNote() {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let highlight = PodcastHighlight(
            episodeID: episode.id.uuidString,
            timestampSeconds: currentTimestamp(),
            highlight: trimmed
        )
        modelContext.insert(highlight)
        draftText = ""
        try? modelContext.save()
    }

    private func delete(_ note: PodcastHighlight) {
        modelContext.delete(note)
        try? modelContext.save()
    }

    private func saveAndClose() {
        if isCurrentEpisode, playerStore.isPlaying { playerStore.togglePlayPause() }
        dismiss()
    }

    private func generateThemesFromNotes() async {
        let combined = notes.map(\.highlight).joined(separator: "\n")
        let cleaned = combined.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        isGeneratingThemes = true
        defer { isGeneratingThemes = false }

        let context = "\(episode.showName)\n\(episode.title)"
        let themes = await ThemeExtractor.shared.extractThemesFromText(cleaned, context: context)
        episode.themes = themes
        try? modelContext.save()
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainingSeconds = total % 60

        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds) }
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}
