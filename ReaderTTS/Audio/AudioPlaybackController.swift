import AVFoundation
import Foundation
import MediaPlayer

@MainActor
final class AudioPlaybackController: NSObject, ObservableObject {
    private var player: AVAudioPlayer?
    private var currentRate: Float = 1
    private let enablesSystemControls: Bool
    private var remoteCommandTargets: [(MPRemoteCommand, Any)] = []
    private var hasConfiguredSession = false
    private var hasActiveSession = false
    @Published private(set) var isPlaying = false

    var onRemotePlay: (() -> Void)?
    var onRemotePause: (() -> Void)?

    init(enablesSystemControls: Bool = false) {
        self.enablesSystemControls = enablesSystemControls
        super.init()
        if enablesSystemControls { configureRemoteCommands() }
    }

    func configureForPlayback() throws {
        let session = AVAudioSession.sharedInstance()
        if !hasConfiguredSession {
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
            hasConfiguredSession = true
        }
        if !hasActiveSession {
            try session.setActive(true)
            hasActiveSession = true
        }
    }

    @discardableResult
    func play(fileURL: URL, rate: Float = 1.0) throws -> TimeInterval {
        stopCurrentPlayer()
        try configureForPlayback()
        player = try AVAudioPlayer(contentsOf: fileURL)
        player?.enableRate = true
        player?.rate = rate
        currentRate = rate
        player?.prepareToPlay()
        isPlaying = player?.play() ?? false
        guard let player, isPlaying else {
            throw NSError(domain: "ReaderTTS.AudioPlayback", code: 1, userInfo: [NSLocalizedDescriptionKey: "No se pudo iniciar la reproducción local."])
        }
        return player.duration / Double(rate)
    }

    func pause() -> TimeInterval? {
        guard let player, player.isPlaying else { return nil }
        player.pause()
        isPlaying = false
        return max(0, (player.duration - player.currentTime) / Double(currentRate))
    }

    func resume() throws -> TimeInterval {
        guard let player else {
            throw NSError(domain: "ReaderTTS.AudioPlayback", code: 2, userInfo: [NSLocalizedDescriptionKey: "No hay audio local para reanudar."])
        }
        try configureForPlayback()
        guard player.play() else {
            throw NSError(domain: "ReaderTTS.AudioPlayback", code: 3, userInfo: [NSLocalizedDescriptionKey: "No se pudo reanudar la reproducción local."])
        }
        isPlaying = true
        return max(0, (player.duration - player.currentTime) / Double(currentRate))
    }

    func stop() {
        stopCurrentPlayer()
        guard hasActiveSession else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        hasActiveSession = false
    }

    private func stopCurrentPlayer() {
        player?.stop()
        player = nil
        isPlaying = false
        currentRate = 1
    }

    func updateNowPlaying(bookTitle: String, chapterTitle: String, isPlaying: Bool) {
        guard enablesSystemControls else { return }
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = bookTitle
        info[MPMediaItemPropertyArtist] = chapterTitle
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? currentRate : 0
        if let player {
            info[MPMediaItemPropertyPlaybackDuration] = player.duration
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.currentTime
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func clearNowPlaying() {
        guard enablesSystemControls else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true

        let playTarget = center.playCommand.addTarget { [weak self] _ in
            self?.onRemotePlay?()
            return .success
        }
        let pauseTarget = center.pauseCommand.addTarget { [weak self] _ in
            self?.onRemotePause?()
            return .success
        }
        let toggleTarget = center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if self.isPlaying {
                self.onRemotePause?()
            } else {
                self.onRemotePlay?()
            }
            return .success
        }
        remoteCommandTargets = [
            (center.playCommand, playTarget),
            (center.pauseCommand, pauseTarget),
            (center.togglePlayPauseCommand, toggleTarget)
        ]
    }
}
