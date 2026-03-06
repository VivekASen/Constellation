import AVFoundation
import Combine
import Foundation
import MediaPlayer

@MainActor
final class PodcastPlayerStore: ObservableObject {
    @Published private(set) var currentEpisode: PodcastEpisode?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published var suppressFloatingMiniPlayer = false
    @Published var playbackRate: Float = 1.0 {
        didSet {
            guard oldValue != playbackRate else { return }
            if isPlaying {
                player.rate = playbackRate
            }
            updateNowPlayingInfo()
        }
    }

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?

    init() {
        configureAudioSession()
        configureRemoteCommands()
        installTimeObserver()
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        statusObserver?.invalidate()
    }

    func play(_ episode: PodcastEpisode) {
        guard let audioURL = episode.audioURL, let url = URL(string: audioURL) else { return }

        if currentEpisode?.id != episode.id {
            let item = AVPlayerItem(url: url)
            player.replaceCurrentItem(with: item)
            currentEpisode = episode
            currentTime = episode.currentPositionSeconds
            if episode.currentPositionSeconds > 0 {
                seek(to: episode.currentPositionSeconds, autoPlay: false)
            }
            observeCurrentItemDuration()
        }

        player.playImmediately(atRate: playbackRate)
        isPlaying = true
        updateNowPlayingInfo()
    }

    func togglePlayPause() {
        guard currentEpisode != nil else { return }

        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.playImmediately(atRate: playbackRate)
            isPlaying = true
        }

        updateNowPlayingInfo()
    }

    func seek(to seconds: Double, autoPlay: Bool? = nil) {
        let clamped = max(0, min(seconds, max(duration, seconds)))
        currentTime = clamped
        let cmTime = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        syncEpisodeProgress()

        if let autoPlay {
            if autoPlay {
                player.playImmediately(atRate: playbackRate)
                isPlaying = true
            } else {
                player.pause()
                isPlaying = false
            }
        }

        updateNowPlayingInfo()
    }

    func skip(by seconds: Double) {
        seek(to: currentTime + seconds)
    }

    func reset() {
        player.pause()
        isPlaying = false
        currentEpisode = nil
        currentTime = 0
        duration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.allowAirPlay, .allowBluetoothA2DP])
        try? session.setActive(true)
    }

    private func observeCurrentItemDuration() {
        statusObserver?.invalidate()
        statusObserver = player.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard let self else { return }
            if item.status == .readyToPlay {
                let seconds = item.duration.seconds
                if seconds.isFinite && seconds > 0 {
                    Task { @MainActor in
                        self.duration = seconds
                        self.currentEpisode?.durationSeconds = Int(seconds.rounded())
                        self.updateNowPlayingInfo()
                    }
                }
            }
        }
    }

    private func installTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let seconds = time.seconds
            guard seconds.isFinite else { return }

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = max(0, seconds)
                self.isPlaying = self.player.timeControlStatus == .playing
                self.syncEpisodeProgress()
                self.updateNowPlayingInfo()
            }
        }
    }

    private func syncEpisodeProgress() {
        guard let episode = currentEpisode else { return }
        episode.currentPositionSeconds = currentTime

        guard duration > 0 else { return }
        let progress = currentTime / duration
        if progress >= 0.9 {
            episode.completedAt = episode.completedAt ?? Date()
        }
    }

    private func configureRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if !self.isPlaying {
                self.togglePlayPause()
            }
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if self.isPlaying {
                self.togglePlayPause()
            }
            return .success
        }
        commands.skipForwardCommand.preferredIntervals = [15]
        commands.skipBackwardCommand.preferredIntervals = [15]
        commands.skipForwardCommand.addTarget { [weak self] _ in
            self?.skip(by: 15)
            return .success
        }
        commands.skipBackwardCommand.addTarget { [weak self] _ in
            self?.skip(by: -15)
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let episode = currentEpisode else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: episode.title,
            MPMediaItemPropertyArtist: episode.showName,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? playbackRate : 0
        ]
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
