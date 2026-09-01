import Foundation
import CSwiftSDL3

/// SDL3 WAV player used by the migrated presentation path. It keeps music,
/// effects and UI volume controls behind GameAudioService; the existing WinMM
/// AudioManager remains available until the full game switches over.
final class SDLAudioService: GameAudioService {
    var musicVolume: Float = 1 { didSet { if musicVolume != oldValue { applyMusicGains() } } }
    var effectsVolume: Float = 1
    var masterVolume: Float = 1 { didSet { if masterVolume != oldValue { applyMusicGains() } } }
    private var music: OpaquePointer?
    private var fadingMusic: OpaquePointer?
    private var musicResource = ""
    private var fadeElapsed: Double = 0
    private var fadeDuration: Double = 0
    private var effects: [OpaquePointer] = []
    var hasLoadedMusic: Bool { music != nil }

    func playEffect(named resource: String) {
        tick()
        if let effect = resource.withCString({ swift_sdl3_audio_create($0, false) }) {
            effects.append(effect)
        }
    }

    func playMusic(named resource: String, loop: Bool) {
        stopMusic()
        music = resource.withCString { swift_sdl3_audio_create($0, loop) }
        musicResource = music == nil ? "" : resource
        applyMusicGains()
    }

    /// Changes music without overlap artifacts. During the short transition
    /// the outgoing stream fades down while the new stream fades up; the old
    /// stream is destroyed as soon as the crossfade completes.
    func transitionMusic(named resource: String, loop: Bool = true, duration: Double = 0.75) {
        guard resource != musicResource else { return }
        guard let incoming = resource.withCString({ swift_sdl3_audio_create($0, loop) }) else { return }
        if let fadingMusic { swift_sdl3_audio_destroy(fadingMusic) }
        fadingMusic = music
        music = incoming
        musicResource = resource
        fadeElapsed = 0
        fadeDuration = max(0, duration)
        applyMusicGains()
    }

    func stopMusic() {
        if let music { swift_sdl3_audio_destroy(music) }
        if let fadingMusic { swift_sdl3_audio_destroy(fadingMusic) }
        music = nil
        fadingMusic = nil
        musicResource = ""
        fadeElapsed = 0
        fadeDuration = 0
    }

    func tick(delta: Double = 0) {
        if let music, !swift_sdl3_audio_tick(music) {
            swift_sdl3_audio_destroy(music)
            self.music = nil
            musicResource = ""
        }
        if let fadingMusic, !swift_sdl3_audio_tick(fadingMusic) {
            swift_sdl3_audio_destroy(fadingMusic)
            self.fadingMusic = nil
        }
        if fadingMusic != nil {
            fadeElapsed += max(0, delta)
            if fadeDuration <= 0 || fadeElapsed >= fadeDuration {
                if let fadingMusic { swift_sdl3_audio_destroy(fadingMusic) }
                self.fadingMusic = nil
            }
            applyMusicGains()
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

    private func applyMusicGains() {
        let baseGain = min(1, max(0, musicVolume * masterVolume))
        let progress = fadeDuration > 0 ? Float(min(1, fadeElapsed / fadeDuration)) : 1
        if let music { _ = swift_sdl3_audio_set_gain(music, baseGain * progress) }
        if let fadingMusic { _ = swift_sdl3_audio_set_gain(fadingMusic, baseGain * (1 - progress)) }
    }

    deinit {
        stopMusic()
        for effect in effects { swift_sdl3_audio_destroy(effect) }
    }
}
