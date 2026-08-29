import Foundation

enum AudioBus { case music, effects, userInterface }

/// Gameplay-facing audio seam. The existing WinMM player can conform to this
/// while SDL audio is introduced behind the same interface.
protocol GameAudioService: AnyObject {
    var musicVolume: Float { get set }
    var effectsVolume: Float { get set }
    var masterVolume: Float { get set }
    func playEffect(named resource: String)
    func playMusic(named resource: String, loop: Bool)
    func stopMusic()
}

final class NullAudioService: GameAudioService {
    var musicVolume: Float = 1
    var effectsVolume: Float = 1
    var masterVolume: Float = 1
    func playEffect(named resource: String) {}
    func playMusic(named resource: String, loop: Bool) {}
    func stopMusic() {}
}
