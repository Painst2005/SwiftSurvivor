import Foundation

enum SDLAudioSmoke {
    static func run() {
        do {
            let platform = try SDLPlatform(title: "SwiftSurvivor SDL audio", width: 320, height: 180, resizable: false)
            let audio = SDLAudioService()
            let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Resources/Audio")
            let tracks = ["music_lobby.wav", "music_battle_intro.wav", "music_battle_advance.wav",
                          "music_battle_assault.wav", "music_battle_blood.wav",
                          "music_battle_laststand.wav", "music_boss.wav"]
            for filename in tracks {
                audio.transitionMusic(named: root.appendingPathComponent(filename).path, duration: 0.04)
                precondition(audio.hasLoadedMusic, "Unable to load \(filename)")
                let end = Date().timeIntervalSinceReferenceDate + 0.08
                while Date().timeIntervalSinceReferenceDate < end {
                    audio.tick(delta: 0.02)
                    _ = platform.pollEvents()
                    Thread.sleep(forTimeInterval: 0.02)
                }
            }
            audio.stopMusic()
            print("SDL_AUDIO_SMOKE_OK \(tracks.count) tracks")
        } catch {
            print("SDL audio smoke failed: \(error)")
        }
    }
}
