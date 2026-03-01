import Foundation

/// Hybrid retriever + ranker for cross-media recommendations.
/// Phase 1 supports movie and TV candidates from TMDB, with scoring designed
/// to remain stable as additional media sources (podcasts/books/articles) are added.
final class RecommendationEngineV2 {
    static let shared = RecommendationEngineV2()
    private let minimumMovieVoteCount = 180
    private let minimumTVVoteCount = 120
    private let documentaryGenreID = 99
    
    private let seedCatalog: [String: [String]] = [
        "space": ["Interstellar", "The Martian", "Apollo 13", "Gravity", "The Expanse", "For All Mankind", "Contact"],
        "space exploration": ["Interstellar", "The Martian", "Apollo 13", "Gravity", "The Expanse", "For All Mankind"],
        "astronaut": ["Interstellar", "The Martian", "Apollo 13", "First Man", "For All Mankind"],
        "sci fi": ["Blade Runner 2049", "Arrival", "Dune", "The Expanse", "Foundation"],
        "science fiction": ["Blade Runner 2049", "Arrival", "Dune", "The Expanse", "Foundation"],
        "time travel": ["Dark", "Looper", "12 Monkeys", "Predestination", "Edge of Tomorrow"],
        "ai": ["Ex Machina", "Her", "Blade Runner 2049", "Westworld", "Person of Interest"],
        "artificial intelligence": ["Ex Machina", "Her", "Blade Runner 2049", "Westworld", "Person of Interest"],
        "murder mystery": ["Knives Out", "Se7en", "True Detective", "Sherlock", "Zodiac"],
        "mystery": ["Knives Out", "Sherlock", "True Detective", "Prisoners", "The Girl with the Dragon Tattoo"],
        "political intrigue": ["House of Cards", "The West Wing", "The Ides of March", "Tinker Tailor Soldier Spy"],
        "fantasy": ["The Lord of the Rings", "Game of Thrones", "The Witcher", "House of the Dragon"]
    ]
    
    private let genericTerms: Set<String> = [
        "action", "adventure", "fantasy", "drama", "thriller", "horror", "comedy", "romance",
        "science fiction", "sci fi", "documentary", "mystery", "crime", "animation", "family",
        "war", "western", "history", "movie", "movies", "show", "tv"
    ]
    private let intentStopTokens: Set<String> = [
        "refine", "more", "another", "anything", "else", "same", "style", "options",
        "preference", "only", "movie", "movies", "tv", "show", "shows", "series",
        "suggestion", "suggestions", "focus", "keep", "going", "format", "new", "topic"
    ]
    
    private init() {}
    
    func recommend(
        query: String,
        understanding: QueryUnderstanding,
        userMovies: [Movie],
        userTVShows: [TVShow]
    ) async -> RecommendationResult {
        let intent = parseIntent(from: query)
        let candidateQueries = buildCandidateQueries(query: query, understanding: understanding)
        
        let movieCandidates = await fetchMovieCandidates(queries: candidateQueries)
        let tvCandidates = await fetchTVCandidates(queries: candidateQueries)
        
        let movieLibraryIDs = Set(userMovies.compactMap(\.tmdbID))
        let tvLibraryIDs = Set(userTVShows.compactMap(\.tmdbID))
        
        let filteredMovies = dedupeMovies(movieCandidates)
            .filter { !movieLibraryIDs.contains($0.id) }
            .filter { ($0.voteCount ?? 0) >= minimumMovieVoteCount || ($0.voteAverage ?? 0) >= 7.9 }
            .filter { satisfiesMovieIntent($0, intent: intent) }
        let filteredTVShows = dedupeTVShows(tvCandidates)
            .filter { !tvLibraryIDs.contains($0.id) }
            .filter { ($0.voteCount ?? 0) >= minimumTVVoteCount || ($0.voteAverage ?? 0) >= 8.0 }
            .filter { satisfiesTVIntent($0, intent: intent) }
        
        let movieRanks = rankMovies(
            filteredMovies,
            query: query,
            understanding: understanding,
            userMovies: userMovies
        )
        let tvRanks = rankTVShows(
            filteredTVShows,
            query: query,
            understanding: understanding,
            userTVShows: userTVShows
        )
        
        return RecommendationResult(
            movies: Array(movieRanks.prefix(10)),
            tvShows: Array(tvRanks.prefix(10))
        )
    }
    
    // MARK: - Retrieval
    
    private func buildCandidateQueries(query: String, understanding: QueryUnderstanding) -> [String] {
        var candidates: [String] = []
        candidates.append(query)
        
        let cleanSuggestions = understanding.suggestions
            .compactMap(cleanSuggestion)
            .filter(isConcreteSuggestion)
        candidates.append(contentsOf: cleanSuggestions.prefix(8))
        
        let topicQueries = (understanding.themes + understanding.genres)
            .map { $0.replacingOccurrences(of: "-", with: " ") }
            .map(normalize)
            .filter { !$0.isEmpty }
        candidates.append(contentsOf: topicQueries.prefix(8))
        
        let normalizedQuery = normalize(query)
        let seedKeys = [normalizedQuery] + topicQueries
        for key in seedKeys {
            if let seeds = seedCatalog[key] {
                candidates.append(contentsOf: seeds)
                continue
            }
            if let partialKey = seedCatalog.keys.first(where: { key.contains($0) || $0.contains(key) }),
               let seeds = seedCatalog[partialKey] {
                candidates.append(contentsOf: seeds)
            }
        }
        
        let deduped = Array(NSOrderedSet(array: candidates.compactMap(cleanSuggestion))) as? [String] ?? []
        return Array(deduped.prefix(14))
    }
    
    private func fetchMovieCandidates(queries: [String]) async -> [TMDBMovie] {
        await withTaskGroup(of: [TMDBMovie].self) { group in
            for query in queries {
                group.addTask {
                    (try? await TMDBService.shared.searchMovies(query: query)) ?? []
                }
            }
            
            var results: [TMDBMovie] = []
            for await chunk in group {
                results.append(contentsOf: chunk.prefix(5))
            }
            
            if results.count < 12, let popular = try? await TMDBService.shared.getPopularMovies() {
                results.append(contentsOf: popular.prefix(15))
            }
            
            return results
        }
    }
    
    private func fetchTVCandidates(queries: [String]) async -> [TMDBTVShow] {
        await withTaskGroup(of: [TMDBTVShow].self) { group in
            for query in queries {
                group.addTask {
                    (try? await TMDBService.shared.searchTVShows(query: query)) ?? []
                }
            }
            
            var results: [TMDBTVShow] = []
            for await chunk in group {
                results.append(contentsOf: chunk.prefix(5))
            }
            
            if results.count < 12, let popular = try? await TMDBService.shared.getPopularTVShows() {
                results.append(contentsOf: popular.prefix(15))
            }
            
            return results
        }
    }
    
    private func dedupeMovies(_ candidates: [TMDBMovie]) -> [TMDBMovie] {
        Dictionary(grouping: candidates, by: \.id).compactMap { $0.value.first }
    }
    
    private func dedupeTVShows(_ candidates: [TMDBTVShow]) -> [TMDBTVShow] {
        Dictionary(grouping: candidates, by: \.id).compactMap { $0.value.first }
    }
    
    // MARK: - Ranking
    
    private func rankMovies(
        _ candidates: [TMDBMovie],
        query: String,
        understanding: QueryUnderstanding,
        userMovies: [Movie]
    ) -> [RankedMovieRecommendation] {
        let config = RecommendationRankingConfig.current
        let intentTokens = focusedIntentTokens(query: query, understanding: understanding)
        let hasIntentSignal = !intentTokens.isEmpty
        let suggestionTitleTokens = understanding.suggestions.map(tokenize)
        let libraryTitleTokens = userMovies.map { tokenize($0.title) }
        
        let scored = candidates.map { movie -> RankedMovieRecommendation in
            let text = [movie.title, movie.overview ?? ""].joined(separator: " ")
            let itemTokens = tokenize(text)
            
            let semanticBase = jaccard(intentTokens, itemTokens)
            let suggestionMatch = suggestionTitleTokens
                .map { jaccard($0, tokenize(movie.title)) }
                .max() ?? 0
            let semantic = max(semanticBase, suggestionMatch * 0.95)
            let quality = min(1.0, max(0.0, (movie.voteAverage ?? 0) / 10.0))
            
            let maxSeenSimilarity = libraryTitleTokens
                .map { jaccard($0, tokenize(movie.title)) }
                .max() ?? 0
            let novelty = 1.0 - maxSeenSimilarity
            
            let popularity = normalizedPopularity(voteCount: movie.voteCount)
            var rawScore =
                config.semanticWeight * semantic +
                config.qualityWeight * quality +
                config.popularityWeight * popularity +
                config.noveltyWeight * novelty
            
            if (movie.voteCount ?? 0) < minimumMovieVoteCount {
                rawScore -= 0.12
            }
            if hasIntentSignal && semantic < 0.02 {
                rawScore -= 0.30
            }
            
            let reasons = buildReasons(
                semantic: semantic,
                quality: quality,
                popularity: popularity,
                novelty: novelty,
                voteCount: movie.voteCount ?? 0
            )
            
            return RankedMovieRecommendation(movie: movie, score: rawScore, reasons: reasons, semanticEvidence: semantic)
        }

        let constrained: [RankedMovieRecommendation]
        if hasIntentSignal {
            let semanticMatches = scored.filter { $0.semanticEvidence >= 0.02 }
            constrained = semanticMatches.count >= 4 ? semanticMatches : scored
        } else {
            constrained = scored
        }

        return rerankMoviesForDiversity(constrained, balance: config.diversityBalance)
    }
    
    private func rankTVShows(
        _ candidates: [TMDBTVShow],
        query: String,
        understanding: QueryUnderstanding,
        userTVShows: [TVShow]
    ) -> [RankedTVRecommendation] {
        let config = RecommendationRankingConfig.current
        let intentTokens = focusedIntentTokens(query: query, understanding: understanding)
        let hasIntentSignal = !intentTokens.isEmpty
        let suggestionTitleTokens = understanding.suggestions.map(tokenize)
        let libraryTitleTokens = userTVShows.map { tokenize($0.title) }
        
        let scored = candidates.map { show -> RankedTVRecommendation in
            let text = [show.title, show.overview ?? ""].joined(separator: " ")
            let itemTokens = tokenize(text)
            
            let semanticBase = jaccard(intentTokens, itemTokens)
            let suggestionMatch = suggestionTitleTokens
                .map { jaccard($0, tokenize(show.title)) }
                .max() ?? 0
            let semantic = max(semanticBase, suggestionMatch * 0.95)
            let quality = min(1.0, max(0.0, (show.voteAverage ?? 0) / 10.0))
            
            let maxSeenSimilarity = libraryTitleTokens
                .map { jaccard($0, tokenize(show.title)) }
                .max() ?? 0
            let novelty = 1.0 - maxSeenSimilarity
            
            let popularity = normalizedPopularity(voteCount: show.voteCount)
            var rawScore =
                config.semanticWeight * semantic +
                config.qualityWeight * quality +
                config.popularityWeight * popularity +
                config.noveltyWeight * novelty
            
            if (show.voteCount ?? 0) < minimumTVVoteCount {
                rawScore -= 0.12
            }
            if hasIntentSignal && semantic < 0.02 {
                rawScore -= 0.30
            }
            
            let reasons = buildReasons(
                semantic: semantic,
                quality: quality,
                popularity: popularity,
                novelty: novelty,
                voteCount: show.voteCount ?? 0
            )
            
            return RankedTVRecommendation(show: show, score: rawScore, reasons: reasons, semanticEvidence: semantic)
        }

        let constrained: [RankedTVRecommendation]
        if hasIntentSignal {
            let semanticMatches = scored.filter { $0.semanticEvidence >= 0.02 }
            constrained = semanticMatches.count >= 4 ? semanticMatches : scored
        } else {
            constrained = scored
        }

        return rerankTVForDiversity(constrained, balance: config.diversityBalance)
    }
    
    private func rerankMoviesForDiversity(_ ranked: [RankedMovieRecommendation], balance: Double) -> [RankedMovieRecommendation] {
        var pool = ranked.sorted { $0.score > $1.score }
        var selected: [RankedMovieRecommendation] = []
        
        while !pool.isEmpty && selected.count < min(12, ranked.count) {
            var bestIndex = 0
            var bestValue = -Double.greatestFiniteMagnitude
            
            for (index, candidate) in pool.enumerated() {
                let candidateTokens = tokenize([candidate.movie.title, candidate.movie.overview ?? ""].joined(separator: " "))
                let redundancy = selected.map { chosen in
                    let chosenTokens = tokenize([chosen.movie.title, chosen.movie.overview ?? ""].joined(separator: " "))
                    return jaccard(candidateTokens, chosenTokens)
                }.max() ?? 0
                
                let mmr = balance * candidate.score - (1.0 - balance) * redundancy
                if mmr > bestValue {
                    bestValue = mmr
                    bestIndex = index
                }
            }
            
            selected.append(pool.remove(at: bestIndex))
        }
        
        return selected
    }
    
    private func rerankTVForDiversity(_ ranked: [RankedTVRecommendation], balance: Double) -> [RankedTVRecommendation] {
        var pool = ranked.sorted { $0.score > $1.score }
        var selected: [RankedTVRecommendation] = []
        
        while !pool.isEmpty && selected.count < min(12, ranked.count) {
            var bestIndex = 0
            var bestValue = -Double.greatestFiniteMagnitude
            
            for (index, candidate) in pool.enumerated() {
                let candidateTokens = tokenize([candidate.show.title, candidate.show.overview ?? ""].joined(separator: " "))
                let redundancy = selected.map { chosen in
                    let chosenTokens = tokenize([chosen.show.title, chosen.show.overview ?? ""].joined(separator: " "))
                    return jaccard(candidateTokens, chosenTokens)
                }.max() ?? 0
                
                let mmr = balance * candidate.score - (1.0 - balance) * redundancy
                if mmr > bestValue {
                    bestValue = mmr
                    bestIndex = index
                }
            }
            
            selected.append(pool.remove(at: bestIndex))
        }
        
        return selected
    }
    
    // MARK: - Helpers
    
    private func buildReasons(
        semantic: Double,
        quality: Double,
        popularity: Double,
        novelty: Double,
        voteCount: Int
    ) -> [String] {
        var reasons: [(String, Double)] = [
            ("Strong thematic match", semantic),
            ("High audience rating", quality),
            ("Well-known pick", popularity),
            ("Novel versus your library", novelty)
        ]
        reasons.sort { $0.1 > $1.1 }
        var selected = reasons.prefix(2).map(\.0)
        if selected.contains("Well-known pick") {
            selected = selected.map { value in
                value == "Well-known pick" ? "Well-known pick (\(voteCount) ratings)" : value
            }
        }
        return selected
    }
    
    private func tokenize(_ text: String) -> Set<String> {
        let normalized = normalize(text)
        let tokens = normalized.split(separator: " ").map(String.init)
        return Set(tokens.filter { $0.count > 1 && !$0.allSatisfy(\.isNumber) })
    }
    
    private func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func parseIntent(from query: String) -> RecommendationIntent {
        let normalized = normalize(query)
        
        let documentaryOnly = normalized.contains("documentary")
            || normalized.contains("documentaries")
            || normalized.contains("docuseries")
            || normalized.contains("non fiction")
            || normalized.contains("nonfiction")
        
        let movieOnly = normalized.contains("movie only")
            || normalized.contains("movies only")
            || normalized.contains("films only")
        
        let tvOnly = normalized.contains("tv only")
            || normalized.contains("show only")
            || normalized.contains("series only")
            || normalized.contains("tv shows only")
        
        let mediaMode: RecommendationMediaMode
        if movieOnly && !tvOnly {
            mediaMode = .movieOnly
        } else if tvOnly && !movieOnly {
            mediaMode = .tvOnly
        } else {
            mediaMode = .any
        }
        
        return RecommendationIntent(mediaMode: mediaMode, documentaryOnly: documentaryOnly)
    }
    
    private func satisfiesMovieIntent(_ movie: TMDBMovie, intent: RecommendationIntent) -> Bool {
        if intent.mediaMode == .tvOnly { return false }
        guard intent.documentaryOnly else { return true }
        if let genreIDs = movie.genreIDs {
            return genreIDs.contains(documentaryGenreID)
        }
        let haystack = normalize([movie.title, movie.overview ?? ""].joined(separator: " "))
        return haystack.contains("documentary") || haystack.contains("docuseries")
    }

    private func satisfiesTVIntent(_ show: TMDBTVShow, intent: RecommendationIntent) -> Bool {
        if intent.mediaMode == .movieOnly { return false }
        guard intent.documentaryOnly else { return true }
        if let genreIDs = show.genreIDs {
            return genreIDs.contains(documentaryGenreID)
        }
        let haystack = normalize([show.title, show.overview ?? ""].joined(separator: " "))
        return haystack.contains("documentary") || haystack.contains("docuseries")
    }
    
    private func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty || !b.isEmpty else { return 0 }
        let intersection = a.intersection(b).count
        let union = a.union(b).count
        return union == 0 ? 0 : Double(intersection) / Double(union)
    }
    
    private func normalizedPopularity(voteCount: Int?) -> Double {
        let count = max(0, voteCount ?? 0)
        guard count > 0 else { return 0 }
        // Log-scaling keeps major titles ahead without letting popularity fully dominate.
        let scaled = log(Double(count) + 1.0) / log(6000.0)
        return min(1.0, max(0.0, scaled))
    }
    
    private func cleanSuggestion(_ suggestion: String) -> String? {
        let cleaned = normalize(suggestion)
        guard !cleaned.isEmpty else { return nil }
        return cleaned
            .split(separator: " ")
            .map { String($0).capitalized }
            .joined(separator: " ")
    }
    
    private func isConcreteSuggestion(_ suggestion: String) -> Bool {
        let normalized = normalize(suggestion)
        guard normalized.count >= 4 else { return false }
        if genericTerms.contains(normalized) { return false }
        return true
    }

    private func focusedIntentTokens(query: String, understanding: QueryUnderstanding) -> Set<String> {
        let candidateText = [query, understanding.themes.joined(separator: " "), understanding.genres.joined(separator: " ")]
            .joined(separator: " ")
        let raw = tokenize(candidateText)
        return raw.filter { !intentStopTokens.contains($0) }
    }
}

struct RankedMovieRecommendation {
    let movie: TMDBMovie
    let score: Double
    let reasons: [String]
    let semanticEvidence: Double
}

struct RankedTVRecommendation {
    let show: TMDBTVShow
    let score: Double
    let reasons: [String]
    let semanticEvidence: Double
}

struct RecommendationResult {
    let movies: [RankedMovieRecommendation]
    let tvShows: [RankedTVRecommendation]
}

private struct RecommendationIntent {
    let mediaMode: RecommendationMediaMode
    let documentaryOnly: Bool
}

private enum RecommendationMediaMode {
    case any
    case movieOnly
    case tvOnly
}

struct RecommendationRankingConfig {
    let semanticWeight: Double
    let qualityWeight: Double
    let popularityWeight: Double
    let noveltyWeight: Double
    let diversityBalance: Double
    
    private static let semanticKey = "recommend.semanticWeight"
    private static let qualityKey = "recommend.qualityWeight"
    private static let popularityKey = "recommend.popularityWeight"
    private static let noveltyKey = "recommend.noveltyWeight"
    private static let diversityKey = "recommend.diversityBalance"
    
    static var current: RecommendationRankingConfig {
        let defaults = UserDefaults.standard
        return RecommendationRankingConfig(
            semanticWeight: defaults.object(forKey: semanticKey) as? Double ?? 0.58,
            qualityWeight: defaults.object(forKey: qualityKey) as? Double ?? 0.28,
            popularityWeight: defaults.object(forKey: popularityKey) as? Double ?? 0.20,
            noveltyWeight: defaults.object(forKey: noveltyKey) as? Double ?? 0.10,
            diversityBalance: defaults.object(forKey: diversityKey) as? Double ?? 0.78
        )
    }
}
