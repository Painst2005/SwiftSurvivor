import Foundation
import CSwiftSDL3

/// First real gameplay migration target. It reuses the established simulation
/// and collision code, but presents the player, enemies, bullets and Boss via
/// GameRenderer. The legacy Win32 renderer remains the default until this slice
/// has feature parity with the full UI.
enum SDLGameplaySlice {
    static func run() {
        do {
            let width = 720
            let height = 900
            let platform = try SDLPlatform(title: "SwiftSurvivor SDL gameplay", width: width, height: height)
            let renderer = SDLRenderer(platform: platform)
            let input = SDLInputManager()
            let game = Game.shared
            game.start(width: Double(width), height: Double(height))
            var clock = FixedStepClock()
            var previous = Double(swift_sdl3_ticks_ns()) / 1_000_000_000
            var running = true
            defer {
                setInjectedKeyboardState(nil)
                game.phase = .menu
            }

            while running {
                let now = Double(swift_sdl3_ticks_ns()) / 1_000_000_000
                let realDelta = now - previous
                previous = now
                let events = platform.pollEvents()
                input.beginFrame(events: events)
                if input.shouldQuit { running = false }
                injectGameInput(input)
                game.updateMousePosition(Vec2(x: Double(input.mousePosition.x), y: Double(input.mousePosition.y)))
                clock.advance(realDelta: realDelta) { delta in
                    game.update(delta: delta, width: Double(width), height: Double(height))
                }

                draw(renderer: renderer, game: game, width: width, height: height)
                Thread.sleep(forTimeInterval: 1.0 / 120.0)
            }
        } catch {
            print("SDL gameplay failed: \(error)")
        }
    }

    private static func injectGameInput(_ input: SDLInputManager) {
        var keys: Set<Int32> = []
        if input.isHeld(.moveLeft) { keys.insert(0x41) }
        if input.isHeld(.moveRight) { keys.insert(0x44) }
        if input.isHeld(.moveUp) { keys.insert(0x57) }
        if input.isHeld(.moveDown) { keys.insert(0x53) }
        if input.isHeld(.precisionMove) { keys.insert(0x10) }
        if input.isHeld(.specialAttack) { keys.insert(0x20) }
        if input.isHeld(.pause) { keys.insert(0x1B) }
        setInjectedKeyboardState(keys)
    }

    private static func draw(renderer: SDLRenderer, game: Game, width: Int, height: Int) {
        renderer.beginFrame(clear: RenderColor(5, 9, 24))
        let field = playfieldBounds(width: Double(width), height: Double(height))
        renderer.fillRect(RenderRect(x: Float(field.left), y: Float(field.top), width: Float(field.right - field.left), height: Float(field.bottom - field.top)), color: RenderColor(8, 17, 43))

        // A sparse grid keeps the migrated slice readable without hiding bullets.
        for y in stride(from: Int(field.top), through: Int(field.bottom), by: 90) {
            renderer.line(from: (x: Float(field.left), y: Float(y)), to: (x: Float(field.right), y: Float(y)), color: RenderColor(18, 43, 78, 120))
        }

        for enemy in game.enemies {
            let color = enemy.type == EnemyType.sniper.rawValue ? RenderColor(255, 151, 128) : RenderColor(226, 76, 142)
            let size = Float(max(8, enemy.radius * 1.5))
            renderer.fillRect(RenderRect(x: Float(enemy.position.x) - size / 2, y: Float(enemy.position.y) - size / 2, width: size, height: size), color: color)
        }
        if let boss = game.boss {
            renderer.fillRect(RenderRect(x: Float(boss.position.x) - 78, y: Float(boss.position.y) - 28, width: 156, height: 56), color: RenderColor(192, 53, 219))
            renderer.line(from: (x: Float(boss.position.x) - 92, y: Float(boss.position.y)), to: (x: Float(boss.position.x) + 92, y: Float(boss.position.y)), color: RenderColor(255, 178, 239))
        }
        for bullet in game.bullets {
            let size = Float(max(3, bullet.radius * 1.4))
            let color = bullet.playerOwned ? RenderColor(93, 226, 255) : RenderColor(255, 104, 138)
            renderer.fillRect(RenderRect(x: Float(bullet.position.x) - size / 2, y: Float(bullet.position.y) - size / 2, width: size, height: size), color: color)
        }

        let playerColor = game.precisionMode ? RenderColor(255, 235, 112) : RenderColor(88, 205, 255)
        renderer.fillRect(RenderRect(x: Float(game.player.x) - 12, y: Float(game.player.y) - 22, width: 24, height: 44), color: playerColor)
        renderer.fillRect(RenderRect(x: Float(game.player.x) - 28, y: Float(game.player.y) + 9, width: 56, height: 6), color: RenderColor(45, 117, 206))

        renderer.drawText("HP \(Int(game.health))/\(Int(game.maxHealth))", at: (x: 18, y: 18), color: RenderColor(255, 240, 245))
        renderer.drawText("SCORE \(game.score)  COMBO \(game.combo)", at: (x: 18, y: 36), color: RenderColor(146, 226, 255))
        renderer.drawText("SDL GAMEPLAY SLICE", at: (x: 18, y: Float(height - 24)), color: RenderColor(105, 147, 198))
        renderer.present()
    }
}
