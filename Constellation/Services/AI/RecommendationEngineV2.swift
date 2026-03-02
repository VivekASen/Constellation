import Foundation

/// Hybrid retriever + ranker for cross-media recommendations.
/// Phase 1 supports movie and TV candidates from TMDB, with scoring designed
/// to remain stable as additional media sources (podcasts/books/articles) are added.
final class RecommendationEngineV2 {
    static let shared = RecommendationEngineV2()
    private let minimumMovieVoteCount = 180
    private let minimumTVVoteCount = 120
    private let documentaryGenreID = 99
    private let vectorRetriever = LibraryVectorRetriever.shared
    private let topicKnowledgeService = TopicKnowledgeService.shared
    private let maxCandidateQueries = 12
    private let perQueryTake = 5
    private let targetCandidatePool = 26
    private let popularFallbackThreshold = 10
    
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
    private let topicStopTokens: Set<String> = [
        "movie", "movies", "film", "films", "tv", "show", "shows", "series",
        "best", "good", "great", "strong", "suggest", "suggestion", "suggestions",
        "about", "with", "for", "and", "the", "a", "an", "more",
        "physical", "social", "cultural", "political", "historical", "modern",
        "process", "study", "general", "practice", "field", "theory"
    ]
    private init() {}
    
    func recommend(
        query: String,
        understanding: QueryUnderstanding,
        userMovies: [Movie],
        userTVShows: [TVShow],
        excludedMovieIDs: Set<Int> = [],
        excludedTVIDs: Set<Int> = []
    ) async -> RecommendationResult {
        let intent = parseIntent(from: query)
        let expandedTopicTerms = await topicKnowledgeService.expandTerms(for: query)
        let topicConstraint = buildTopicConstraint(query: query, understanding: understanding, expandedTerms: expandedTopicTerms)
        let retrievalSnapshot = vectorRetriever.retrieve(
            query: query,
            understanding: understanding,
            userMovies: userMovies,
            userTVShows: userTVShows
        )
        let candidateQueries = buildCandidateQueries(
            query: query,
            understanding: understanding,
            topicConstraint: topicConstraint,
            expandedTerms: expandedTopicTerms
        )
        let keywordIDs = await resolveKeywordIDs(from: candidateQueries + expandedTopicTerms)
        
        async let movieCandidates = fetchMovieCandidates(
            queries: candidateQueries,
            understanding: understanding,
            userMovies: userMovies,
            keywordIDs: keywordIDs
        )
        async let tvCandidates = fetchTVCandidates(
            queries: candidateQueries,
            understanding: understanding,
            userTVShows: userTVShows,
            keywordIDs: keywordIDs
        )
        let (movieCandidatesResolved, tvCandidatesResolved) = await (movieCandidates, tvCandidates)
        
        let movieLibraryIDs = Set(userMovies.compactMap(\.tmdbID))
        let tvLibraryIDs = Set(userTVShows.compactMap(\.tmdbID))
        
        var filteredMovies = dedupeMovies(movieCandidatesResolved)
            .filter { !movieLibraryIDs.contains($0.id) }
            .filter { !excludedMovieIDs.contains($0.id) }
            .filter { ($0.voteCount ?? 0) >= minimumMovieVoteCount || ($0.voteAverage ?? 0) >= 7.9 }
            .filter { satisfiesMovieIntent($0, intent: intent) }
            .filter { satisfiesMovieTopicConstraint($0, topicConstraint: topicConstraint) }
        var filteredTVShows = dedupeTVShows(tvCandidatesResolved)
            .filter { !tvLibraryIDs.contains($0.id) }
            .filter { !excludedTVIDs.contains($0.id) }
            .filter { ($0.voteCount ?? 0) >= minimumTVVoteCount || ($0.voteAverage ?? 0) >= 8.0 }
            .filter { satisfiesTVIntent($0, intent: intent) }
            .filter { satisfiesTVTopicConstraint($0, topicConstraint: topicConstraint) }

        // If strict topical guards eliminate everything, fall back to a relaxed topical pass
        // so users still get meaningful results instead of a dead end.
        if filteredMovies.isEmpty && filteredTVShows.isEmpty && topicConstraint.isActive {
            filteredMovies = dedupeMovies(movieCandidatesResolved)
                .filter { !movieLibraryIDs.contains($0.id) }
                .filter { !excludedMovieIDs.contains($0.id) }
                .filter { ($0.voteCount ?? 0) >= 20 || ($0.voteAverage ?? 0) >= 6.2 }
                .filter { satisfiesMovieIntent($0, intent: intent) }
                .filter { satisfiesMovieTopicConstraintRelaxed($0, topicConstraint: topicConstraint) }

            filteredTVShows = dedupeTVShows(tvCandidatesResolved)
                .filter { !tvLibraryIDs.contains($0.id) }
                .filter { !excludedTVIDs.contains($0.id) }
                .filter { ($0.voteCount ?? 0) >= 20 || ($0.voteAverage ?? 0) >= 6.2 }
                .filter { satisfiesTVIntent($0, intent: intent) }
                .filter { satisfiesTVTopicConstraintRelaxed($0, topicConstraint: topicConstraint) }
        }

        let stableMovies = filteredMovies
        let stableTVShows = filteredTVShows
        async let movieAwardBoostIDs = detectAwardBoostMovieIDs(in: stableMovies)
        async let tvAwardBoostIDs = detectAwardBoostTVIDs(in: stableTVShows)
        let (movieAwardIDs, tvAwardIDs) = await (movieAwardBoostIDs, tvAwardBoostIDs)
        
        let movieRanks = rankMovies(
            filteredMovies,
            query: query,
            understanding: understanding,
            userMovies: userMovies,
            retrievalSnapshot: retrievalSnapshot,
            awardBoostIDs: movieAwardIDs
        )
        let tvRanks = rankTVShows(
            filteredTVShows,
            query: query,
            understanding: understanding,
            userTVShows: userTVShows,
            retrievalSnapshot: retrievalSnapshot,
            awardBoostIDs: tvAwardIDs
        )
        
        return RecommendationResult(
            movies: Array(movieRanks.prefix(10)),
            tvShows: Array(tvRanks.prefix(10))
        )
    }
    
    // MARK: - Retrieval
    
    private func buildCandidateQueries(
        query: String,
        understanding: QueryUnderstanding,
        topicConstraint: TopicConstraint,
        expandedTerms: [String]
    ) -> [String] {
        var candidates: [String] = []
        let sanitizedQuery = sanitizeQueryForSearch(query)
        if !sanitizedQuery.isEmpty {
            candidates.append(sanitizedQuery)
        }
        candidates.append(contentsOf: topicConstraint.seedQueries)
        
        let cleanSuggestions = understanding.suggestions
            .compactMap(cleanSuggestion)
            .filter(isConcreteSuggestion)
        candidates.append(contentsOf: cleanSuggestions.prefix(8))
        candidates.append(contentsOf: expandedTerms.prefix(8))
        
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
        return Array(deduped.prefix(maxCandidateQueries))
    }
    
    private func fetchMovieCandidates(
        queries: [String],
        understanding: QueryUnderstanding,
        userMovies: [Movie],
        keywordIDs: [Int]
    ) async -> [TMDBMovie] {
        await withTaskGroup(of: [TMDBMovie].self) { group in
            for query in queries {
                group.addTask {
                    (try? await TMDBService.shared.searchMovies(query: query)) ?? []
                }
            }
            for genreID in movieGenreIDs(from: understanding) {
                group.addTask {
                    (try? await TMDBService.shared.discoverMovies(genreID: genreID)) ?? []
                }
            }
            for seedID in topMovieSeedIDs(from: userMovies) {
                group.addTask {
                    (try? await TMDBService.shared.getSimilarMovies(movieID: seedID)) ?? []
                }
            }
            for keywordID in keywordIDs.prefix(8) {
                group.addTask {
                    (try? await TMDBService.shared.discoverMovies(keywordID: keywordID)) ?? []
                }
            }
            
            var results: [TMDBMovie] = []
            for await chunk in group {
                results.append(contentsOf: chunk.prefix(perQueryTake))
                if results.count >= targetCandidatePool {
                    group.cancelAll()
                    break
                }
            }
            
            if results.count < popularFallbackThreshold, let popular = try? await TMDBService.shared.getPopularMovies() {
                results.append(contentsOf: popular.prefix(12))
            }
            
            return results
        }
    }
    
    private func fetchTVCandidates(
        queries: [String],
        understanding: QueryUnderstanding,
        userTVShows: [TVShow],
        keywordIDs: [Int]
    ) async -> [TMDBTVShow] {
        await withTaskGroup(of: [TMDBTVShow].self) { group in
            for query in queries {
                group.addTask {
                    (try? await TMDBService.shared.searchTVShows(query: query)) ?? []
                }
            }
            for genreID in tvGenreIDs(from: understanding) {
                group.addTask {
                    (try? await TMDBService.shared.discoverTVShows(genreID: genreID)) ?? []
                }
            }
            for seedID in topTVSeedIDs(from: userTVShows) {
                group.addTask {
                    (try? await TMDBService.shared.getSimilarTVShows(tvID: seedID)) ?? []
                }
            }
            for keywordID in keywordIDs.prefix(8) {
                group.addTask {
                    (try? await TMDBService.shared.discoverTVShows(keywordID: keywordID)) ?? []
                }
            }
            
            var results: [TMDBTVShow] = []
            for await chunk in group {
                results.append(contentsOf: chunk.prefix(perQueryTake))
                if results.count >= targetCandidatePool {
                    group.cancelAll()
                    break
                }
            }
            
            if results.count < popularFallbackThreshold, let popular = try? await TMDBService.shared.getPopularTVShows() {
                results.append(contentsOf: popular.prefix(12))
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
        userMovies: [Movie],
        retrievalSnapshot: VectorRetrievalSnapshot,
        awardBoostIDs: Set<Int>
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
            let coherence = vectorRetriever.coherenceScore(
                queryText: retrievalSnapshot.queryText,
                candidateTitle: movie.title,
                candidateOverview: movie.overview,
                snapshot: retrievalSnapshot
            )
            let semantic = max(semanticBase, suggestionMatch * 0.95, coherence * 0.98)
            let quality = min(1.0, max(0.0, (movie.voteAverage ?? 0) / 10.0))
            
            let maxSeenSimilarity = libraryTitleTokens
                .map { jaccard($0, tokenize(movie.title)) }
                .max() ?? 0
            let novelty = 1.0 - maxSeenSimilarity
            
            let popularity = normalizedPopularity(voteCount: movie.voteCount)
            let strongPopularity = normalizedStrongPopularity(voteCount: movie.voteCount)
            var rawScore =
                config.semanticWeight * semantic +
                config.qualityWeight * quality +
                config.popularityWeight * popularity +
                config.noveltyWeight * novelty +
                0.18 * strongPopularity
            
            if (movie.voteCount ?? 0) < minimumMovieVoteCount {
                rawScore -= 0.20
            }
            if (movie.voteCount ?? 0) < 70 {
                rawScore -= 0.35
            }
            if awardBoostIDs.contains(movie.id) {
                rawScore += 0.08
            }
            if hasIntentSignal && semantic < 0.02 {
                rawScore -= 0.30
            }
            if hasIntentSignal && coherence < config.coherenceThreshold {
                rawScore -= 0.40
            }
            
            let reasons = buildReasons(
                semantic: semantic,
                coherence: coherence,
                quality: quality,
                popularity: popularity,
                novelty: novelty,
                voteCount: movie.voteCount ?? 0
            )
            
            return RankedMovieRecommendation(
                movie: movie,
                score: rawScore,
                reasons: reasons,
                semanticEvidence: semantic,
                coherenceEvidence: coherence
            )
        }

        let constrained: [RankedMovieRecommendation]
        if hasIntentSignal {
            let coherenceMatches = scored.filter { $0.coherenceEvidence >= config.coherenceThreshold }
            if coherenceMatches.count >= 4 {
                constrained = coherenceMatches
            } else {
                let semanticMatches = scored.filter { $0.semanticEvidence >= 0.02 }
                constrained = semanticMatches.count >= 4 ? semanticMatches : scored
            }
        } else {
            constrained = scored
        }

        return rerankMoviesForDiversity(constrained, balance: config.diversityBalance)
    }
    
    private func rankTVShows(
        _ candidates: [TMDBTVShow],
        query: String,
        understanding: QueryUnderstanding,
        userTVShows: [TVShow],
        retrievalSnapshot: VectorRetrievalSnapshot,
        awardBoostIDs: Set<Int>
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
            let coherence = vectorRetriever.coherenceScore(
                queryText: retrievalSnapshot.queryText,
                candidateTitle: show.title,
                candidateOverview: show.overview,
                snapshot: retrievalSnapshot
            )
            let semantic = max(semanticBase, suggestionMatch * 0.95, coherence * 0.98)
            let quality = min(1.0, max(0.0, (show.voteAverage ?? 0) / 10.0))
            
            let maxSeenSimilarity = libraryTitleTokens
                .map { jaccard($0, tokenize(show.title)) }
                .max() ?? 0
            let novelty = 1.0 - maxSeenSimilarity
            
            let popularity = normalizedPopularity(voteCount: show.voteCount)
            let strongPopularity = normalizedStrongPopularity(voteCount: show.voteCount)
            var rawScore =
                config.semanticWeight * semantic +
                config.qualityWeight * quality +
                config.popularityWeight * popularity +
                config.noveltyWeight * novelty +
                0.18 * strongPopularity
            
            if (show.voteCount ?? 0) < minimumTVVoteCount {
                rawScore -= 0.20
            }
            if (show.voteCount ?? 0) < 50 {
                rawScore -= 0.35
            }
            if awardBoostIDs.contains(show.id) {
                rawScore += 0.08
            }
            if hasIntentSignal && semantic < 0.02 {
                rawScore -= 0.30
            }
            if hasIntentSignal && coherence < config.coherenceThreshold {
                rawScore -= 0.40
            }
            
            let reasons = buildReasons(
                semantic: semantic,
                coherence: coherence,
                quality: quality,
                popularity: popularity,
                novelty: novelty,
                voteCount: show.voteCount ?? 0
            )
            
            return RankedTVRecommendation(
                show: show,
                score: rawScore,
                reasons: reasons,
                semanticEvidence: semantic,
                coherenceEvidence: coherence
            )
        }

        let constrained: [RankedTVRecommendation]
        if hasIntentSignal {
            let coherenceMatches = scored.filter { $0.coherenceEvidence >= config.coherenceThreshold }
            if coherenceMatches.count >= 4 {
                constrained = coherenceMatches
            } else {
                let semanticMatches = scored.filter { $0.semanticEvidence >= 0.02 }
                constrained = semanticMatches.count >= 4 ? semanticMatches : scored
            }
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
        coherence: Double,
        quality: Double,
        popularity: Double,
        novelty: Double,
        voteCount: Int
    ) -> [String] {
        var reasons: [(String, Double)] = [
            ("Strong thematic match", semantic),
            ("Strong topic coherence", coherence),
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

    private func satisfiesMovieTopicConstraint(_ movie: TMDBMovie, topicConstraint: TopicConstraint) -> Bool {
        guard topicConstraint.isActive else { return true }
        let normalizedText = normalize([movie.title, movie.overview ?? ""].joined(separator: " "))
        let tokens = tokenize(normalizedText)
        return topicConstraint.matches(normalizedText: normalizedText, tokens: tokens)
    }

    private func satisfiesMovieTopicConstraintRelaxed(_ movie: TMDBMovie, topicConstraint: TopicConstraint) -> Bool {
        guard topicConstraint.isActive else { return true }
        let normalizedText = normalize([movie.title, movie.overview ?? ""].joined(separator: " "))
        let tokens = tokenize(normalizedText)
        return topicConstraint.relaxedMatches(normalizedText: normalizedText, tokens: tokens)
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

    private func satisfiesTVTopicConstraint(_ show: TMDBTVShow, topicConstraint: TopicConstraint) -> Bool {
        guard topicConstraint.isActive else { return true }
        let normalizedText = normalize([show.title, show.overview ?? ""].joined(separator: " "))
        let tokens = tokenize(normalizedText)
        return topicConstraint.matches(normalizedText: normalizedText, tokens: tokens)
    }

    private func satisfiesTVTopicConstraintRelaxed(_ show: TMDBTVShow, topicConstraint: TopicConstraint) -> Bool {
        guard topicConstraint.isActive else { return true }
        let normalizedText = normalize([show.title, show.overview ?? ""].joined(separator: " "))
        let tokens = tokenize(normalizedText)
        return topicConstraint.relaxedMatches(normalizedText: normalizedText, tokens: tokens)
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

    private func normalizedStrongPopularity(voteCount: Int?) -> Double {
        let count = max(0, voteCount ?? 0)
        guard count > 0 else { return 0 }
        let scaled = log(Double(count) + 1.0) / log(40000.0)
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

    private func movieGenreIDs(from understanding: QueryUnderstanding) -> [Int] {
        let movieGenreMap: [String: Int] = [
            "action": 28,
            "adventure": 12,
            "animation": 16,
            "comedy": 35,
            "crime": 80,
            "documentary": 99,
            "drama": 18,
            "family": 10751,
            "fantasy": 14,
            "history": 36,
            "horror": 27,
            "mystery": 9648,
            "romance": 10749,
            "science fiction": 878,
            "thriller": 53,
            "war": 10752
        ]
        return Array(Set(understanding.genres.compactMap { movieGenreMap[normalize($0)] })).prefix(3).map { $0 }
    }

    private func tvGenreIDs(from understanding: QueryUnderstanding) -> [Int] {
        let tvGenreMap: [String: Int] = [
            "action": 10759,
            "adventure": 10759,
            "animation": 16,
            "comedy": 35,
            "crime": 80,
            "documentary": 99,
            "drama": 18,
            "family": 10751,
            "fantasy": 10765,
            "history": 36,
            "horror": 27,
            "mystery": 9648,
            "romance": 10749,
            "science fiction": 10765,
            "thriller": 53,
            "war": 10768
        ]
        return Array(Set(understanding.genres.compactMap { tvGenreMap[normalize($0)] })).prefix(3).map { $0 }
    }

    private func topMovieSeedIDs(from movies: [Movie]) -> [Int] {
        movies
            .sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
            .compactMap(\.tmdbID)
            .prefix(3)
            .map { $0 }
    }

    private func topTVSeedIDs(from shows: [TVShow]) -> [Int] {
        shows
            .sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
            .compactMap(\.tmdbID)
            .prefix(3)
            .map { $0 }
    }

    private func resolveKeywordIDs(from terms: [String]) async -> [Int] {
        let cleaned = Array(Set(terms.map(Self.normalizeTerm)))
            .filter { !$0.isEmpty && $0.count >= 3 }
            .prefix(10)

        let ids = await withTaskGroup(of: Int?.self) { group in
            for term in cleaned {
                group.addTask {
                    let keywords = (try? await TMDBService.shared.searchKeywords(query: term)) ?? []
                    if let exact = keywords.first(where: { Self.normalizeTerm($0.name) == term }) {
                        return exact.id
                    }
                    if let partial = keywords.first(where: { Self.normalizeTerm($0.name).contains(term) || term.contains(Self.normalizeTerm($0.name)) }) {
                        return partial.id
                    }
                    return keywords.first?.id
                }
            }
            var values: [Int] = []
            for await id in group {
                if let id {
                    values.append(id)
                }
            }
            return values
        }
        return Array(Set(ids)).prefix(8).map { $0 }
    }

    private func sanitizeQueryForSearch(_ query: String) -> String {
        query
            .replacingOccurrences(of: "|", with: " ")
            .replacingOccurrences(of: "refine:", with: " ", options: .caseInsensitive)
            .replacingOccurrences(of: "preference:", with: " ", options: .caseInsensitive)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func normalizeTerm(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func buildTopicConstraint(query: String, understanding: QueryUnderstanding, expandedTerms: [String]) -> TopicConstraint {
        let focused = sanitizeQueryForSearch(query)
            .split(separator: "|")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first ?? sanitizeQueryForSearch(query)
        let normalizedQuery = normalize(focused)
        var phrases: Set<String> = []
        var coreTokens: Set<String> = []
        var expandedTokens: Set<String> = []
        let expandedNormalized = expandedTerms.map(normalize)
        phrases.formUnion(expandedNormalized.filter { $0.split(separator: " ").count > 1 })

        let understandingTokens = tokenize((understanding.themes + understanding.genres).joined(separator: " "))
        let queryTokens = tokenize(normalizedQuery).filter { !topicStopTokens.contains($0) }
        let expandedTermTokens = Set(expandedNormalized.flatMap { tokenize($0) }.filter { !topicStopTokens.contains($0) })

        coreTokens.formUnion(understandingTokens.filter { !topicStopTokens.contains($0) })
        coreTokens.formUnion(queryTokens)
        expandedTokens.formUnion(expandedTermTokens.subtracting(coreTokens))

        let seedQueries = Array(phrases.prefix(6)) + Array(coreTokens.prefix(8)).map { $0.capitalized }
        return TopicConstraint(
            requiredPhrases: Array(phrases),
            coreTokens: coreTokens,
            expandedTokens: expandedTokens,
            seedQueries: seedQueries
        )
    }

    private func detectAwardBoostMovieIDs(in candidates: [TMDBMovie]) async -> Set<Int> {
        let shortlist = candidates
            .sorted { ($0.voteCount ?? 0) > ($1.voteCount ?? 0) }
            .prefix(8)

        let pairs = await withTaskGroup(of: (Int, Bool).self) { group in
            for movie in shortlist {
                group.addTask {
                    let hasAwards = await self.topicKnowledgeService.hasAwardsSignal(
                        title: movie.title,
                        year: movie.year,
                        mediaHint: "film"
                    )
                    return (movie.id, hasAwards)
                }
            }

            var output: [(Int, Bool)] = []
            for await value in group {
                output.append(value)
            }
            return output
        }
        return Set(pairs.filter { $0.1 }.map { $0.0 })
    }

    private func detectAwardBoostTVIDs(in candidates: [TMDBTVShow]) async -> Set<Int> {
        let shortlist = candidates
            .sorted { ($0.voteCount ?? 0) > ($1.voteCount ?? 0) }
            .prefix(8)

        let pairs = await withTaskGroup(of: (Int, Bool).self) { group in
            for show in shortlist {
                group.addTask {
                    let hasAwards = await self.topicKnowledgeService.hasAwardsSignal(
                        title: show.title,
                        year: show.year,
                        mediaHint: "tv series"
                    )
                    return (show.id, hasAwards)
                }
            }

            var output: [(Int, Bool)] = []
            for await value in group {
                output.append(value)
            }
            return output
        }
        return Set(pairs.filter { $0.1 }.map { $0.0 })
    }
}

struct RankedMovieRecommendation {
    let movie: TMDBMovie
    let score: Double
    let reasons: [String]
    let semanticEvidence: Double
    let coherenceEvidence: Double
}

struct RankedTVRecommendation {
    let show: TMDBTVShow
    let score: Double
    let reasons: [String]
    let semanticEvidence: Double
    let coherenceEvidence: Double
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

private struct TopicConstraint {
    let requiredPhrases: [String]
    let coreTokens: Set<String>
    let expandedTokens: Set<String>
    let seedQueries: [String]

    var isActive: Bool {
        !requiredPhrases.isEmpty || !coreTokens.isEmpty || !expandedTokens.isEmpty
    }

    func matches(normalizedText: String, tokens: Set<String>) -> Bool {
        guard isActive else { return true }

        let phraseHit = requiredPhrases.contains { phrase in
            normalizedText.contains(phrase)
        }
        if phraseHit { return true }

        let coreHits = tokens.intersection(coreTokens).count
        if coreHits >= 1 { return true }

        // Expanded terms are weaker evidence: require stronger overlap.
        let expandedHits = tokens.intersection(expandedTokens).count
        return expandedHits >= 2
    }

    func relaxedMatches(normalizedText: String, tokens: Set<String>) -> Bool {
        guard isActive else { return true }
        let phraseHit = requiredPhrases.contains { normalizedText.contains($0) }
        if phraseHit { return true }
        if tokens.intersection(coreTokens).count > 0 {
            return true
        }
        return tokens.intersection(expandedTokens).count >= 1
    }
}

struct RecommendationRankingConfig {
    let semanticWeight: Double
    let qualityWeight: Double
    let popularityWeight: Double
    let noveltyWeight: Double
    let diversityBalance: Double
    let coherenceThreshold: Double
    
    private static let semanticKey = "recommend.semanticWeight"
    private static let qualityKey = "recommend.qualityWeight"
    private static let popularityKey = "recommend.popularityWeight"
    private static let noveltyKey = "recommend.noveltyWeight"
    private static let diversityKey = "recommend.diversityBalance"
    private static let coherenceThresholdKey = "recommend.coherenceThreshold"
    
    static var current: RecommendationRankingConfig {
        let defaults = UserDefaults.standard
        return RecommendationRankingConfig(
            semanticWeight: defaults.object(forKey: semanticKey) as? Double ?? 0.58,
            qualityWeight: defaults.object(forKey: qualityKey) as? Double ?? 0.28,
            popularityWeight: defaults.object(forKey: popularityKey) as? Double ?? 0.20,
            noveltyWeight: defaults.object(forKey: noveltyKey) as? Double ?? 0.10,
            diversityBalance: defaults.object(forKey: diversityKey) as? Double ?? 0.78,
            coherenceThreshold: defaults.object(forKey: coherenceThresholdKey) as? Double ?? 0.22
        )
    }
}
