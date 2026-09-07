import AVFoundation

/// AVAudioPlayer may activate the audio session implicitly. Keep all preparation
/// and playback on this actor's executor, away from the main/UI actor.
actor ButtonAudio {
    private var players: [String: AVAudioPlayer] = [:]

    func load(_ urls: [URL]) {
        stop()
        for url in urls {
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.volume = 0.45
                player.prepareToPlay()
                players[url.deletingPathExtension().lastPathComponent] = player
            } catch { print("Button audio load failed: \(error)") }
        }
    }

    func play(_ name: String) {
        guard let player = players[name] else { return }
        player.currentTime = 0
        player.play()
    }

    func stop() {
        players.values.forEach { $0.stop() }
        players.removeAll()
    }
}
