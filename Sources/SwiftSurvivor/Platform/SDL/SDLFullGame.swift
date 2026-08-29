import Foundation
import CSwiftSDL3

/// Full presentation bridge: the existing localized GDI UI is rendered into a
/// reusable DIB and uploaded to SDL as one texture. This is intentionally a
/// migration bridge, so every menu and Chinese string keeps its current visual
/// behavior while the window/presentation path becomes SDL-owned.
enum SDLFullGame {
    static func run() {
        let width = 1280
        let height = 720
        do {
            let platform = try SDLPlatform(title: "SwiftSurvivor", width: width, height: height, resizable: true)
            let renderer = SDLRenderer(platform: platform)
            let input = SDLInputManager()
            let sdlAudio = SDLAudioService()
            let musicPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Resources/Audio/thunder_swift_battle.wav").path
            AudioManager.shared.stopMusic()
            sdlAudio.playMusic(named: musicPath, loop: true)
            let framebuffer = GDIFrameBuffer()
            var pixelBuffer: [UInt8] = []
            var frameTexture: SDLTexture?
            var clock = FixedStepClock()
            var previous = Double(swift_sdl3_ticks_ns()) / 1_000_000_000
            var running = true
            var firstFrame = true

            while running {
                let now = Double(swift_sdl3_ticks_ns()) / 1_000_000_000
                let realDelta = now - previous
                previous = now
                let events = platform.pollEvents()
                input.beginFrame(events: events)
                sdlAudio.tick()
                if input.shouldQuit { running = false }
                handleInput(input, width: width, height: height)
                Game.shared.updateMousePosition(Vec2(x: Double(input.mousePosition.x), y: Double(input.mousePosition.y)))
                clock.advance(realDelta: realDelta) { delta in
                    Game.shared.update(delta: delta, width: Double(width), height: Double(height))
                }

                guard let hdc = framebuffer.ensure(width: width, height: height) else { break }
                drawGame(hdc, width: Double(width), height: Double(height))
                guard framebuffer.copyRGBA(into: &pixelBuffer) else { break }
                if frameTexture == nil {
                    frameTexture = SDLTexture(platform: platform, width: width, height: height, rgbaPixels: pixelBuffer)
                } else {
                    _ = frameTexture?.update(rgbaPixels: pixelBuffer)
                }
                renderer.beginFrame(clear: RenderColor(0, 0, 0))
                if let frameTexture {
                    renderer.drawSprite(frameTexture, in: RenderRect(x: 0, y: 0, width: Float(width), height: Float(height)))
                }
                renderer.present()
                firstFrame = false
                Thread.sleep(forTimeInterval: firstFrame ? 0.02 : 1.0 / 120.0)
            }
            framebuffer.release()
            sdlAudio.stopMusic()
            Game.shared.persistProfile()
        } catch {
            print("SDL full presentation failed: \(error)")
        }
    }

    private static func handleInput(_ input: SDLInputManager, width: Int, height: Int) {
        if let click = input.consumePrimaryClick() {
            Game.shared.handleClick(at: Vec2(x: Double(click.x), y: Double(click.y)), width: Double(width), height: Double(height))
        }
        if input.isPressed(keyCode: 13) {
            switch Game.shared.phase {
            case .menu, .missionSelect: Game.shared.start(width: Double(width), height: Double(height))
            case .gameOver: Game.shared.start(width: Double(width), height: Double(height))
            default: break
            }
        }
        if input.isPressed(.specialAttack), Game.shared.phase == .playing {
            Game.shared.activateThunderOverload()
        }
        if input.isPressed(.pause) {
            switch Game.shared.phase {
            case .playing, .paused: Game.shared.togglePause()
            case .gameOver: Game.shared.phase = .menu
            default: break
            }
        }
        if input.isPressed(keyCode: 0x51), Game.shared.phase == .playing { Game.shared.cycleWeapon() }
        if Game.shared.phase == .upgrade {
            if input.isPressed(keyCode: 49) { Game.shared.chooseUpgrade(0) }
            if input.isPressed(keyCode: 50) { Game.shared.chooseUpgrade(1) }
            if input.isPressed(keyCode: 51) { Game.shared.chooseUpgrade(2) }
        }
        injectGameInput(input)
    }

    private static func injectGameInput(_ input: SDLInputManager) {
        var keys: Set<Int32> = []
        if input.isHeld(.moveLeft) { keys.insert(0x41) }
        if input.isHeld(.moveRight) { keys.insert(0x44) }
        if input.isHeld(.moveUp) { keys.insert(0x57) }
        if input.isHeld(.moveDown) { keys.insert(0x53) }
        if input.isHeld(.precisionMove) { keys.insert(0x10) }
        setInjectedKeyboardState(keys)
    }
}
