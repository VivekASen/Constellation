import SwiftUI
import UIKit
import Combine

func normalizedRemoteURL(from raw: String?) -> URL? {
    guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
        return nil
    }
    if text.hasPrefix("//") {
        text = "https:" + text
    }
    if text.hasPrefix("http://image.tmdb.org")
        || text.hasPrefix("http://covers.openlibrary.org")
        || text.hasPrefix("http://") {
        text = "https://" + text.dropFirst("http://".count)
    }
    if let direct = URL(string: text), direct.scheme != nil {
        return direct
    }
    if let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.union(.urlPathAllowed)) {
        return URL(string: encoded)
    }
    return nil
}

private final class RemotePosterLoader: ObservableObject {
    @MainActor @Published var image: UIImage?

    private static let cache = NSCache<NSURL, UIImage>()
    private var currentTask: Task<Void, Never>?

    func load(from rawURL: String?) {
        currentTask?.cancel()
        image = nil
        DebugDiagnosticsRecorder.posterRequest()

        guard let url = normalizedRemoteURL(from: rawURL) else {
            DebugDiagnosticsRecorder.posterInvalidURL()
            return
        }
        let key = url as NSURL
        if let cached = Self.cache.object(forKey: key) {
            DebugDiagnosticsRecorder.posterCacheHit()
            image = cached
            return
        }

        currentTask = Task(priority: .utility) {
            if let loaded = await fetchImage(from: url) {
                await MainActor.run {
                    Self.cache.setObject(loaded, forKey: key)
                    self.image = loaded
                }
                DebugDiagnosticsRecorder.posterSuccess()
                return
            }
            DebugDiagnosticsRecorder.posterRetry()
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            guard let retry = await fetchImage(from: url) else {
                DebugDiagnosticsRecorder.posterFailure()
                return
            }
            await MainActor.run {
                Self.cache.setObject(retry, forKey: key)
                self.image = retry
            }
            DebugDiagnosticsRecorder.posterSuccess()
        }
    }

    private func fetchImage(from url: URL) async -> UIImage? {
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 18)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else { return nil }
            return UIImage(data: data)
        } catch {
            return nil
        }
    }

    deinit {
        currentTask?.cancel()
    }
}

struct RemotePosterImageView<Placeholder: View>: View {
    let imageURL: String?
    let contentMode: ContentMode
    @ViewBuilder let placeholder: () -> Placeholder

    @StateObject private var loader = RemotePosterLoader()

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
        }
        .onAppear {
            loader.load(from: imageURL)
        }
        .onChange(of: imageURL) { _, newValue in
            loader.load(from: newValue)
        }
    }
}
