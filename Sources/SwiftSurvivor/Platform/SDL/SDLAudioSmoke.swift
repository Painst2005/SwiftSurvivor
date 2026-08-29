import Foundation

enum SDLAudioSmoke {
    static func run() {
        do {
            let platform = try SDLPlatform(title: "SwiftSurvivor SDL audio", width: 320, height: 180, resizable: false)
            let audio = SDLAudioService()
            let path = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Resources/Audio/sfx_hit.wav").path
            audio.playEffect(named: path)
            let end = Date().timeIntervalSinceReferenceDate + 0.8
            while Date().timeIntervalSinceReferenceDate < end {
                audio.tick()
                _ = platform.pollEvents()
                Thread.sleep(forTimeInterval: 0.02)
            }
        } catch {
            print("SDL audio smoke failed: \(error)")
        }
    }
}
