import AVFoundation
import AnnoFormats

/// Musik aus `MUSIC8/` in zufälliger Reihenfolge und Umgebungsgeräusche (Wellen, Vögel).
@MainActor
final class AudioController: NSObject, AVAudioPlayerDelegate {
    private let gameData: GameData
    private let tracks: [String]
    private var playlist: [String] = []
    private var music: AVAudioPlayer?
    private var waves: AVAudioPlayer?
    private var birds: [AVAudioPlayer] = []
    private var nextBird: Double = 4
    private(set) var musicEnabled = true
    private(set) var effectsEnabled = true

    init(gameData: GameData) {
        self.gameData = gameData
        tracks = gameData.files(withExtension: "wav").filter { $0.lowercased().hasPrefix("music8/") }
        super.init()
        waves = player("SAMPLES/Wellen.wav")
        waves?.numberOfLoops = -1
        waves?.volume = 0
        birds = (1...6).compactMap { player("SAMPLES/Vogel\($0).wav") }
    }

    private func player(_ path: String) -> AVAudioPlayer? {
        guard let url = gameData.url(for: path) else { return nil }
        return try? AVAudioPlayer(contentsOf: url)
    }

    func start() {
        if musicEnabled { playNextTrack() }
        if effectsEnabled { waves?.play() }
    }

    func stop() {
        music?.stop()
        waves?.stop()
        birds.forEach { $0.stop() }
    }

    func toggleMusic() {
        musicEnabled.toggle()
        if musicEnabled { playNextTrack() } else { music?.stop() }
    }

    func toggleEffects() {
        effectsEnabled.toggle()
        if effectsEnabled { waves?.play() } else { waves?.pause() }
    }

    var currentTrack: String? {
        guard musicEnabled, let url = music?.url else { return nil }
        return url.deletingPathExtension().lastPathComponent
    }

    private func playNextTrack() {
        guard !tracks.isEmpty else { return }
        if playlist.isEmpty { playlist = tracks.shuffled() }
        let path = playlist.removeFirst()
        music = player(path)
        music?.delegate = self
        music?.volume = 0.6
        music?.play()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let finished = ObjectIdentifier(player)
        Task { @MainActor in
            if self.musicEnabled, let music = self.music, ObjectIdentifier(music) == finished { self.playNextTrack() }
        }
    }

    /// Passt die Umgebung an das Sichtfeld an: Wellen je nach Meeranteil, gelegentlich Vögel über Land.
    func updateAmbience(seaFraction: Float, landVisible: Bool, dt: Double) {
        guard effectsEnabled else { return }
        let target = 0.15 + 0.45 * seaFraction
        if let waves { waves.volume += (target - waves.volume) * Float(min(dt * 2, 1)) }
        nextBird -= dt
        if nextBird <= 0 {
            nextBird = Double.random(in: 5...14)
            if landVisible, let bird = birds.randomElement() {
                bird.volume = 0.35
                bird.pan = Float.random(in: -0.6...0.6)
                bird.currentTime = 0
                bird.play()
            }
        }
    }
}
