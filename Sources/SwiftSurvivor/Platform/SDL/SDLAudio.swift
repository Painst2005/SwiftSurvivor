import Foundation
import CSwiftSDL3

/// SDL3 WAV player used by the migrated presentation path. It keeps music,
/// effects and UI volume controls behind GameAudioService; the existing WinMM
/// AudioManager remains available until the full game switches over.
final class SDLAudioService: GameAudioService {
    var musicVolume: Float = 1
    var effectsVolume: Float = 1
    var masterVolume: Float = 1
    private var music: OpaquePointer?
    private var effects: [OpaquePointer] = []

    func playEffect(named resource: String) {
        tick()
        if let effect = resource.withCString({ swift_sdl3_audio_create($0, false) }) {
            effects.append(effect)
        }
    }

    func playMusic(named resource: String, loop: Bool) {
        stopMusic()
        music = resource.withCString { swift_sdl3_audio_create($0, loop) }
    }

    func stopMusic() {
        if let music { swift_sdl3_audio_destroy(music) }
        music = nil
    }

    func tick() {
        if let music, !swift_sdl3_audio_tick(music) {
            swift_sdl3_audio_destroy(music)
            self.music = nil
        }
        var writeIndex = 0
        for effect in effects where swift_sdl3_audio_tick(effect) {
            effects[writeIndex] = effect
            writeIndex += 1
        }
        while effects.count > writeIndex {
            let effect = effects.removeLast()
            swift_sdl3_audio_destroy(effect)
        }
    }

    deinit {
        stopMusic()
        for effect in effects { swift_sdl3_audio_destroy(effect) }
    }
}
