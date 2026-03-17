import Foundation

enum AppSecretKey {
    case tmdb
    case tasteDive
    case podcast
    case podcastIndexKey
    case podcastIndexSecret
    case podcastSecret
    case books
    case hardcover
    case gemini
    case groq
}

enum AppSecrets {
    static func value(_ key: AppSecretKey) -> String {
        if let env = firstNonEmpty(environmentKeys(for: key)) {
            return env
        }

        if let plist = firstNonEmpty(infoPlistKeys(for: key)) {
            return plist
        }

        return ""
    }

    private static func firstNonEmpty(_ keys: [String]) -> String? {
        for key in keys {
            if let envValue = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               isUsable(envValue) {
                return envValue
            }

            if let dict = Bundle.main.object(forInfoDictionaryKey: "APIKeys") as? [String: String],
               let plistValue = dict[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               isUsable(plistValue) {
                return plistValue
            }
        }
        return nil
    }

    private static func environmentKeys(for key: AppSecretKey) -> [String] {
        switch key {
        case .tmdb:
            return ["TMDB_API_KEY", "TMDB_KEY"]
        case .tasteDive:
            return ["TASTEDIVE_API_KEY", "TASTEDIVE_KEY"]
        case .podcast:
            return ["PODCAST_API_KEY", "PODCAST_KEY"]
        case .podcastIndexKey:
            return ["PODCAST_INDEX_KEY", "PODCASTINDEX_KEY"]
        case .podcastIndexSecret:
            return ["PODCAST_INDEX_SECRET", "PODCASTINDEX_SECRET"]
        case .podcastSecret:
            return ["PODCAST_SECRET"]
        case .books:
            return ["BOOKS_API_KEY", "BOOKS_KEY"]
        case .hardcover:
            return ["HARDCOVER_TOKEN", "HARDCOVER_API_TOKEN", "HARDCOVER_KEY"]
        case .gemini:
            return ["GEMINI_API_KEY", "GOOGLE_API_KEY"]
        case .groq:
            return ["GROQ_API_KEY", "GROQ_KEY"]
        }
    }

    private static func infoPlistKeys(for key: AppSecretKey) -> [String] {
        switch key {
        case .tmdb:
            return ["TMDB"]
        case .tasteDive:
            return ["TasteDive"]
        case .podcast:
            return ["Podcast"]
        case .podcastIndexKey:
            return ["PodcastIndexKey", "Podcast"]
        case .podcastIndexSecret:
            return ["PodcastIndexSecret", "PodcastSecret"]
        case .podcastSecret:
            return ["PodcastSecret"]
        case .books:
            return ["Books"]
        case .hardcover:
            return ["Hardcover", "Books"]
        case .gemini:
            return ["Gemini"]
        case .groq:
            return ["Groq"]
        }
    }

    private static func isUsable(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        return value.uppercased() != "REDACTED_SET_LOCALLY"
    }
}
