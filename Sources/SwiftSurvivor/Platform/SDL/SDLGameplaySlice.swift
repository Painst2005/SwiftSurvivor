import Foundation
import CSwiftSDL3

/// First real gameplay migration target. It reuses the established simulation
/// and collision code, but presents the player, enemies, bullets and Boss via
/// the shared SDL GameRenderer contract.
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
                if input.isPressed(.pause) { game.togglePause() }
                if input.isPressed(.specialAttack), game.phase == .playing { game.activateThunderOverload() }
                if input.isPressed(keyCode: 0x52), game.phase == .paused || game.phase == .gameOver {
                    game.start(width: Double(width), height: Double(height))
                }
                if input.isPressedQ(), game.phase == .paused || game.phase == .gameOver {
                    game.phase = .menu
                }
                if game.upgradeSelectionActive || game.phase == .upgrade {
                    if input.isPressed(keyCode: 49) { game.chooseUpgrade(0) }
                    if input.isPressed(keyCode: 50) { game.chooseUpgrade(1) }
                    if input.isPressed(keyCode: 51) { game.chooseUpgrade(2) }
                }
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
            let healthRatio = Float(max(0, enemy.health) / max(1, enemy.maxHealth))
            renderer.fillRect(RenderRect(x: Float(enemy.position.x) - size / 2, y: Float(enemy.position.y) - size / 2 - 6, width: size * healthRatio, height: 3), color: RenderColor(255, 134, 126))
            if enemy.attackWarningActive {
                renderer.line(from: (x: Float(enemy.warningTargetX), y: Float(field.top)), to: (x: Float(enemy.warningTargetX), y: Float(field.bottom)), color: RenderColor(255, 79, 125, 150))
            }
        }
        if let boss = game.boss {
            renderer.fillRect(RenderRect(x: Float(boss.position.x) - 78, y: Float(boss.position.y) - 28, width: 156, height: 56), color: RenderColor(192, 53, 219))
            renderer.line(from: (x: Float(boss.position.x) - 92, y: Float(boss.position.y)), to: (x: Float(boss.position.x) + 92, y: Float(boss.position.y)), color: RenderColor(255, 178, 239))
            let ratio = Float(max(0, boss.health) / max(1, boss.maxHealth))
            renderer.fillRect(RenderRect(x: 110, y: 68, width: 500 * ratio, height: 8), color: RenderColor(239, 78, 226))
            if boss.laserWarningTimer > 0 {
                renderer.fillRect(RenderRect(x: Float(boss.laserX) - 3, y: Float(field.top), width: 6, height: Float(field.bottom - field.top)), color: RenderColor(255, 76, 132, 130))
            } else if boss.laserActiveTimer > 0 {
                renderer.fillRect(RenderRect(x: Float(boss.laserX) - 14, y: Float(field.top), width: 28, height: Float(field.bottom - field.top)), color: RenderColor(255, 84, 151, 190))
            }
        }
        for bullet in game.bullets {
            let size = Float(max(3, bullet.radius * 1.4))
            let color = bullet.playerOwned ? RenderColor(93, 226, 255) : RenderColor(255, 104, 138)
            renderer.fillRect(RenderRect(x: Float(bullet.position.x) - size / 2, y: Float(bullet.position.y) - size / 2, width: size, height: size), color: color)
        }
        for powerUp in game.powerUps {
            let color: RenderColor
            switch powerUp.kind {
            case 0: color = RenderColor(81, 224, 255)
            case 1: color = RenderColor(126, 196, 255)
            default: color = RenderColor(255, 213, 112)
            }
            renderer.fillCircle(center: (x: Float(powerUp.position.x), y: Float(powerUp.position.y)), radius: 13, color: color)
            renderer.fillCircle(center: (x: Float(powerUp.position.x), y: Float(powerUp.position.y)), radius: 4, color: RenderColor(250, 252, 255))
        }
        let particleStride = max(1, (game.particles.count + 199) / 200)
        for index in stride(from: 0, to: game.particles.count, by: particleStride) {
            let particle = game.particles[index]
            let alpha = UInt8(max(35, min(255, Int(255 * particle.life / max(0.01, particle.maxLife)))))
            renderer.fillCircle(center: (x: Float(particle.position.x), y: Float(particle.position.y)), radius: Float(max(1, particle.radius)), color: RenderColor(255, 174, 90, alpha))
        }

        let playerColor = game.precisionMode ? RenderColor(255, 235, 112) : RenderColor(88, 205, 255)
        renderer.fillRect(RenderRect(x: Float(game.player.x) - 12, y: Float(game.player.y) - 22, width: 24, height: 44), color: playerColor)
        renderer.fillRect(RenderRect(x: Float(game.player.x) - 28, y: Float(game.player.y) + 9, width: 56, height: 6), color: RenderColor(45, 117, 206))

        renderer.drawText("HP \(Int(game.health))/\(Int(game.maxHealth))", at: (x: 18, y: 18), color: RenderColor(255, 240, 245))
        renderer.drawText("SCORE \(game.score)  COMBO \(game.combo)", at: (x: 18, y: 36), color: RenderColor(146, 226, 255))
        if game.thunderOverloadTime > 0 { renderer.drawText("THUNDER OVERLOAD", at: (x: 18, y: 54), color: RenderColor(120, 240, 255)) }
        if game.phase == .paused {
            renderer.fillRect(RenderRect(x: 70, y: 300, width: 580, height: 230), color: RenderColor(7, 12, 31, 235))
            renderer.drawText("PAUSED", at: (x: 300, y: 350), color: RenderColor(255, 255, 255))
            renderer.drawText("ESC RESUME    R RESTART    Q EXIT", at: (x: 190, y: 390), color: RenderColor(166, 222, 255))
        } else if game.upgradeSelectionActive || game.phase == .upgrade {
            renderer.fillRect(RenderRect(x: 38, y: 260, width: 644, height: 330), color: RenderColor(9, 15, 39, 245))
            renderer.drawText("CHOOSE UPGRADE", at: (x: 270, y: 290), color: RenderColor(255, 231, 133))
            for index in 0..<min(3, game.upgradeOptions.count) {
                let option = game.upgradeOptions[index]
                renderer.fillRect(RenderRect(x: 64 + Float(index) * 205, y: 335, width: 185, height: 170), color: RenderColor(26, 43, 82, 240))
                renderer.drawText("[\(index + 1)]", at: (x: 135 + Float(index) * 205, y: 352), color: RenderColor(255, 255, 255))
                renderer.drawText("UPGRADE \(index + 1)", at: (x: 82 + Float(index) * 205, y: 390), color: RenderColor(133, 231, 255))
                let title = option.title.unicodeScalars.allSatisfy { $0.isASCII } ? option.title : "MODULE \(index + 1)"
                renderer.drawText(title, at: (x: 82 + Float(index) * 205, y: 430), color: RenderColor(255, 222, 139))
            }
        } else if game.phase == .gameOver {
            renderer.fillRect(RenderRect(x: 90, y: 320, width: 540, height: 180), color: RenderColor(16, 12, 36, 240))
            renderer.drawText("MISSION FAILED", at: (x: 270, y: 365), color: RenderColor(255, 116, 154))
            renderer.drawText("R RESTART    ESC MENU", at: (x: 245, y: 420), color: RenderColor(203, 226, 255))
        }
        renderer.drawText("SDL GAMEPLAY SLICE", at: (x: 18, y: Float(height - 24)), color: RenderColor(105, 147, 198))
        renderer.present()
    }
}
