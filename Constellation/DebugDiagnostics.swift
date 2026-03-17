import Foundation
import Combine

@MainActor
final class DebugDiagnostics: ObservableObject {
    static let shared = DebugDiagnostics()

    @Published var themeBackfillRuns = 0
    @Published var themeBackfillUpdates = 0
    @Published var movieThemesGenerated = 0
    @Published var tvThemesGenerated = 0
    @Published var bookThemesGenerated = 0

    @Published var posterRequests = 0
    @Published var posterCacheHits = 0
    @Published var posterRetries = 0
    @Published var posterSuccesses = 0
    @Published var posterFailures = 0
    @Published var posterInvalidURLs = 0

    func reset() {
        themeBackfillRuns = 0
        themeBackfillUpdates = 0
        movieThemesGenerated = 0
        tvThemesGenerated = 0
        bookThemesGenerated = 0
        posterRequests = 0
        posterCacheHits = 0
        posterRetries = 0
        posterSuccesses = 0
        posterFailures = 0
        posterInvalidURLs = 0
    }
}

enum DebugDiagnosticsRecorder {
    static func themeBackfillStarted() {
        #if DEBUG
        Task { @MainActor in
            DebugDiagnostics.shared.themeBackfillRuns += 1
        }
        #endif
    }

    static func themeBackfillUpdated() {
        #if DEBUG
        Task { @MainActor in
            DebugDiagnostics.shared.themeBackfillUpdates += 1
        }
        #endif
    }

    static func movieThemeGenerated() {
        #if DEBUG
        Task { @MainActor in
            DebugDiagnostics.shared.movieThemesGenerated += 1
        }
        #endif
    }

    static func tvThemeGenerated() {
        #if DEBUG
        Task { @MainActor in
            DebugDiagnostics.shared.tvThemesGenerated += 1
        }
        #endif
    }

    static func bookThemeGenerated() {
        #if DEBUG
        Task { @MainActor in
            DebugDiagnostics.shared.bookThemesGenerated += 1
        }
        #endif
    }

    static func posterRequest() {
        #if DEBUG
        Task { @MainActor in
            DebugDiagnostics.shared.posterRequests += 1
        }
        #endif
    }

    static func posterCacheHit() {
        #if DEBUG
        Task { @MainActor in
            DebugDiagnostics.shared.posterCacheHits += 1
        }
        #endif
    }

    static func posterRetry() {
        #if DEBUG
        Task { @MainActor in
            DebugDiagnostics.shared.posterRetries += 1
        }
        #endif
    }

    static func posterSuccess() {
        #if DEBUG
        Task { @MainActor in
            DebugDiagnostics.shared.posterSuccesses += 1
        }
        #endif
    }

    static func posterFailure() {
        #if DEBUG
        Task { @MainActor in
            DebugDiagnostics.shared.posterFailures += 1
        }
        #endif
    }

    static func posterInvalidURL() {
        #if DEBUG
        Task { @MainActor in
            DebugDiagnostics.shared.posterInvalidURLs += 1
        }
        #endif
    }
}
