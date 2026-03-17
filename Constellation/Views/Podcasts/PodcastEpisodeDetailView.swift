import SwiftData
import SwiftUI

struct PodcastEpisodeDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var playerStore: PodcastPlayerStore
    @Bindable var episode: PodcastEpisode
    @Query private var allHighlights: [PodcastHighlight]

    @State private var showingNotesWorkspace = false
    @State private var isGeneratingSummary = false
    @State private var isGeneratingChapters = false
    @State private var autoChapters: [PodcastAutoChapter] = []
    @State private var summaryError: String?

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

                    Button {
                        Task { await generateSummaryFromTranscriptOrNotes() }
                    } label: {
                        HStack(spacing: 10) {
                            if isGeneratingSummary {
                                ProgressView()
                                    .tint(ConstellationPalette.accent)
                            } else {
                                Image(systemName: "text.badge.star")
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Generate Episode Summary")
                                    .font(ConstellationTypeScale.sectionTitle)
                                Text("Use transcript first, fallback to your notes.")
                                    .font(ConstellationTypeScale.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(surfaceFill)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isGeneratingSummary)

                    if let summaryError, !summaryError.isEmpty {
                        Text(summaryError)
                            .font(ConstellationTypeScale.caption)
                            .foregroundStyle(.red)
                    }

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
                                            Text(note.detailText?.isEmpty == false ? note.detailText! : note.highlight)
                                                .font(ConstellationTypeScale.caption)
                                                .foregroundStyle(.primary)
                                                .lineLimit(2)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(surfaceFill)
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

                    if !autoChapters.isEmpty {
                        ConstellationDetailSection("Auto Chapters") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(autoChapters) { chapter in
                                    Button {
                                        playerStore.seek(to: chapter.timestampSeconds)
                                    } label: {
                                        HStack(alignment: .top, spacing: 10) {
                                            Text(formatTime(chapter.timestampSeconds))
                                                .font(ConstellationTypeScale.caption.monospacedDigit().weight(.semibold))
                                                .foregroundStyle(ConstellationPalette.accent)
                                                .padding(.horizontal, 9)
                                                .padding(.vertical, 6)
                                                .background(ConstellationPalette.accent.opacity(0.14))
                                                .clipShape(Capsule())
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(chapter.title)
                                                    .font(ConstellationTypeScale.supporting.weight(.semibold))
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(1)
                                                Text(chapter.detail)
                                                    .font(ConstellationTypeScale.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(2)
                                            }
                                            Spacer()
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    } else {
                        Button {
                            Task { await generateAutoChapters() }
                        } label: {
                            HStack {
                                if isGeneratingChapters {
                                    ProgressView().tint(ConstellationPalette.accent)
                                } else {
                                    Image(systemName: "list.bullet.rectangle")
                                }
                                Text("Generate Auto Chapters")
                                    .font(ConstellationTypeScale.supporting.weight(.semibold))
                                Spacer()
                            }
                            .padding(12)
                            .background(surfaceFill)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(isGeneratingChapters)
                    }

                    if let summaryText = episode.aiSummary ?? episode.overview, !summaryText.isEmpty {
                        ConstellationDetailSection("Episode Summary") {
                            Text(summaryText)
                                .font(ConstellationTypeScale.body)
                                .foregroundStyle(.secondary)
                            if let source = episode.summarySource, !source.isEmpty {
                                Text("Source: \(source.capitalized)")
                                    .font(ConstellationTypeScale.caption)
                                    .foregroundStyle(.secondary)
                            }
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
        .task {
            await generateAutoChapters()
        }
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
                            .background(chipFill)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(14)
        .background(controlFill)
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
                .background(primary ? ConstellationPalette.accent : chipFill)
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

    private func generateSummaryFromTranscriptOrNotes() async {
        summaryError = nil
        isGeneratingSummary = true
        defer { isGeneratingSummary = false }

        let result = await PodcastEpisodeSummarizerService.shared.summarizeEpisode(
            episode: episode,
            notes: episodeHighlights
        )
        guard let result else {
            summaryError = "Could not generate summary yet. Add notes or a transcript and retry."
            return
        }

        episode.aiSummary = result.summary
        episode.summarySource = result.sourceLabel
        episode.summaryUpdatedAt = Date()
        if episode.transcriptText?.isEmpty != false, let transcript = result.transcriptText, !transcript.isEmpty {
            episode.transcriptText = transcript
        }
        try? modelContext.save()
        await generateAutoChapters()
    }

    private func generateAutoChapters() async {
        guard !isGeneratingChapters else { return }
        isGeneratingChapters = true
        defer { isGeneratingChapters = false }
        autoChapters = await PodcastEpisodeSummarizerService.shared.generateChapters(
            episode: episode,
            notes: episodeHighlights
        )
    }

    private var surfaceFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.74)
    }

    private var controlFill: Color {
        colorScheme == .dark ? Color.black.opacity(0.42) : Color.white.opacity(0.52)
    }

    private var chipFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.92)
    }
}

private struct PodcastNotesWorkspaceView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var playerStore: PodcastPlayerStore
    @Bindable var episode: PodcastEpisode
    let currentTimestamp: () -> Double
    @Query private var allHighlights: [PodcastHighlight]

    @State private var draftTitle: String = ""
    @State private var draftBody: String = ""
    @State private var isGeneratingThemes = false
    @State private var isGeneratingSummary = false
    @State private var editingNote: PodcastHighlight?
    @State private var summaryError: String?
    @State private var notesQuery = ""
    @State private var noteFilter: NoteFilter = .all
    @State private var selectedNoteIDs: Set<UUID> = []

    private var isCurrentEpisode: Bool {
        playerStore.currentEpisode?.id == episode.id
    }

    private var notes: [PodcastHighlight] {
        allHighlights
            .filter { $0.episodeID == episode.id.uuidString }
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned {
                    return lhs.isPinned && !rhs.isPinned
                }
                if lhs.timestampSeconds == rhs.timestampSeconds {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.timestampSeconds < rhs.timestampSeconds
            }
    }

    private var filteredNotes: [PodcastHighlight] {
        let base: [PodcastHighlight]
        switch noteFilter {
        case .all:
            base = notes
        case .pinned:
            base = notes.filter(\.isPinned)
        case .unpinned:
            base = notes.filter { !$0.isPinned }
        }

        let trimmed = notesQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return base }
        return base.filter { note in
            let haystack = [
                note.highlight,
                note.detailText ?? "",
                note.timestampFormatted
            ].joined(separator: " ").lowercased()
            return haystack.contains(trimmed)
        }
    }

    private var selectedNotesForGeneration: [PodcastHighlight] {
        let selected = notes.filter { selectedNoteIDs.contains($0.id) }
        return selected.isEmpty ? filteredNotes : selected
    }

    var body: some View {
        VStack(spacing: 0) {
            playerToolbar
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(ConstellationPalette.surface)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("New Timestamp Note")
                        .font(ConstellationTypeScale.supporting.weight(.semibold))
                    Spacer()
                    Text(formatTime(currentTimestamp()))
                        .font(ConstellationTypeScale.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                TextField("Title (optional)", text: $draftTitle)
                    .textFieldStyle(.roundedBorder)

                TextEditor(text: $draftBody)
                    .frame(minHeight: 84, maxHeight: 130)
                    .padding(8)
                    .background(surfaceFill)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                HStack(spacing: 8) {
                    formatInsertButton("• ", icon: "list.bullet")
                    formatInsertButton("## ", icon: "textformat.size")
                    formatInsertButton("- [ ] ", icon: "checklist")
                    formatInsertButton("**", icon: "bold")
                    Spacer()
                    Button {
                        addTimestampNote()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                            Text("Save Note")
                                .font(ConstellationTypeScale.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(.white)
                        .background(ConstellationPalette.accent)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(trimmedDraftBody.isEmpty)
                }
            }
            .padding(14)
            .background(panelFill)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            HStack(spacing: 8) {
                TextField("Search notes", text: $notesQuery)
                    .textFieldStyle(.roundedBorder)

                Picker("Filter", selection: $noteFilter) {
                    ForEach(NoteFilter.allCases, id: \.self) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
                .pickerStyle(.menu)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            if filteredNotes.isEmpty {
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
                        ForEach(filteredNotes) { note in
                            HStack(alignment: .top, spacing: 8) {
                                Button {
                                    playerStore.seek(to: note.timestampSeconds)
                                } label: {
                                    HStack(spacing: 6) {
                                        if note.isPinned {
                                            Image(systemName: "pin.fill")
                                        }
                                        Text(note.timestampFormatted)
                                    }
                                    .font(ConstellationTypeScale.caption.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(ConstellationPalette.accent)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(ConstellationPalette.accent.opacity(0.14))
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(note.highlight)
                                        .font(ConstellationTypeScale.supporting.weight(.semibold))
                                        .lineLimit(1)
                                    if let detail = note.detailText, !detail.isEmpty {
                                        Text(detail)
                                            .font(ConstellationTypeScale.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Button {
                                    toggleSelection(note)
                                } label: {
                                    Image(systemName: selectedNoteIDs.contains(note.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)

                                Button {
                                    editingNote = note
                                } label: {
                                    Image(systemName: "square.and.pencil")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)

                                Button(role: .destructive) {
                                    delete(note)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(10)
                            .background(surfaceFill)
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
                    Text("\(selectedNotesForGeneration.count)")
                        .font(ConstellationTypeScale.caption.monospacedDigit())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(ConstellationPalette.accent.opacity(0.18))
                        .clipShape(Capsule())
                }
                .padding()
                .background(ConstellationPalette.accent.opacity(0.12))
                .foregroundStyle(ConstellationPalette.accent)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding()
            }
            .disabled(selectedNotesForGeneration.isEmpty || isGeneratingThemes)

            Button {
                Task { await generateSummaryFromTranscriptOrNotes() }
            } label: {
                HStack {
                    if isGeneratingSummary {
                        ProgressView().tint(ConstellationPalette.accent)
                    } else {
                        Image(systemName: "text.badge.star")
                    }
                    Text("Generate Episode Summary")
                        .font(ConstellationTypeScale.supporting.weight(.semibold))
                    Spacer()
                }
                .padding()
                .background(ConstellationPalette.accent.opacity(0.08))
                .foregroundStyle(ConstellationPalette.accent)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal)
                .padding(.bottom, 10)
            }
            .disabled(selectedNotesForGeneration.isEmpty || isGeneratingSummary)

            if let summaryError, !summaryError.isEmpty {
                Text(summaryError)
                    .font(ConstellationTypeScale.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
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
        .sheet(item: $editingNote) { note in
            PodcastNoteEditorView(note: note) {
                try? modelContext.save()
            }
        }
    }

    private var playerToolbar: some View {
        HStack(spacing: 12) {
            if isCurrentEpisode {
                Button { playerStore.skip(by: -15) } label: {
                    Image(systemName: "gobackward.15")
                        .frame(width: 34, height: 34)
                        .background(chipFill)
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
                        .background(chipFill)
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
                .background(chipFill)
                .clipShape(Capsule())
        }
    }

    private func addTimestampNote() {
        let body = trimmedDraftBody
        guard !body.isEmpty else { return }
        let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = title.isEmpty ? String(body.prefix(90)) : title
        let highlight = PodcastHighlight(
            episodeID: episode.id.uuidString,
            timestampSeconds: currentTimestamp(),
            highlight: preview,
            detailText: body,
            isPinned: false
        )
        modelContext.insert(highlight)
        draftTitle = ""
        draftBody = ""
        try? modelContext.save()
    }

    private func delete(_ note: PodcastHighlight) {
        selectedNoteIDs.remove(note.id)
        modelContext.delete(note)
        try? modelContext.save()
    }

    private func saveAndClose() {
        if isCurrentEpisode, playerStore.isPlaying { playerStore.togglePlayPause() }
        dismiss()
    }

    private func generateThemesFromNotes() async {
        let combined = selectedNotesForGeneration.map {
            if let detail = $0.detailText, !detail.isEmpty {
                return "[\($0.timestampFormatted)] \($0.highlight)\n\(detail)"
            }
            return "[\($0.timestampFormatted)] \($0.highlight)"
        }.joined(separator: "\n")
        let cleaned = combined.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        isGeneratingThemes = true
        defer { isGeneratingThemes = false }

        let context = "\(episode.showName)\n\(episode.title)"
        let themes = await ThemeExtractor.shared.extractThemesFromText(cleaned, context: context)
        episode.themes = themes
        try? modelContext.save()
    }

    private func generateSummaryFromTranscriptOrNotes() async {
        summaryError = nil
        isGeneratingSummary = true
        defer { isGeneratingSummary = false }

        let result = await PodcastEpisodeSummarizerService.shared.summarizeEpisode(
            episode: episode,
            notes: selectedNotesForGeneration
        )
        guard let result else {
            summaryError = "Could not generate summary yet. Add richer notes and retry."
            return
        }
        episode.aiSummary = result.summary
        episode.summarySource = result.sourceLabel
        episode.summaryUpdatedAt = Date()
        if episode.transcriptText?.isEmpty != false, let transcript = result.transcriptText, !transcript.isEmpty {
            episode.transcriptText = transcript
        }
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

    private var trimmedDraftBody: String {
        draftBody.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func formatInsertButton(_ token: String, icon: String) -> some View {
        Button {
            draftBody = insertToken(token, into: draftBody)
        } label: {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ConstellationPalette.accent)
                .frame(width: 30, height: 30)
                .background(ConstellationPalette.accent.opacity(0.12))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func insertToken(_ token: String, into text: String) -> String {
        if token == "**" {
            return text + (text.hasSuffix(" ") || text.isEmpty ? "**bold** " : " **bold** ")
        }
        if text.isEmpty { return token }
        if text.hasSuffix("\n") { return text + token }
        return text + "\n" + token
    }

    private func toggleSelection(_ note: PodcastHighlight) {
        if selectedNoteIDs.contains(note.id) {
            selectedNoteIDs.remove(note.id)
        } else {
            selectedNoteIDs.insert(note.id)
        }
    }

    private enum NoteFilter: CaseIterable {
        case all
        case pinned
        case unpinned

        var label: String {
            switch self {
            case .all: return "All"
            case .pinned: return "Pinned"
            case .unpinned: return "Unpinned"
            }
        }
    }

    private var panelFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.62)
    }

    private var surfaceFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.86)
    }

    private var chipFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.9)
    }
}

private struct PodcastNoteEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var note: PodcastHighlight
    let onSave: () -> Void

    @State private var title: String = ""
    @State private var bodyText: String = ""
    @State private var pinned = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Note") {
                    TextField("Title", text: $title)
                    TextEditor(text: $bodyText)
                        .frame(minHeight: 180)
                    Toggle("Pin this note", isOn: $pinned)
                }
            }
            .navigationTitle(note.timestampFormatted)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let normalizedBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
                        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        note.highlight = normalizedTitle.isEmpty ? String(normalizedBody.prefix(90)) : normalizedTitle
                        note.detailText = normalizedBody
                        note.isPinned = pinned
                        note.updatedAt = Date()
                        onSave()
                        dismiss()
                    }
                    .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                title = note.highlight
                bodyText = note.detailText ?? note.highlight
                pinned = note.isPinned
            }
        }
    }
}
