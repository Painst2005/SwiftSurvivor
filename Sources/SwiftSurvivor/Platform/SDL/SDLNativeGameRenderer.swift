import Foundation

/// 越界安全下标：机库列表依赖存档索引渲染，脏索引返回 nil 而非崩溃。
extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// Native SDL presentation for the full game.  Gameplay remains independent
/// of SDL; this layer translates the model into lightweight primitives.
enum SDLNativeGameRenderer {
    static func draw(_ renderer: GameRenderer, game: Game, width: Int, height: Int) {
        let uiRenderer = UITransformRenderer(base: renderer, canvasWidth: width, canvasHeight: height, scalePercent: game.profile.uiScale)
        UIInteraction.pointer = game.uiPoint(for: game.mousePosition, width: Double(width), height: Double(height))
        UIInteraction.time = game.uiAnimationTime
        UIInteraction.primaryHeld = game.mousePrimaryDown
        UIInteraction.textMeasurementScale = max(1, Float(min(120, game.profile.uiScale)) / 100)
        let currentScreen = String(describing: game.phase)
        if currentScreen != UIInteraction.screenID {
            UIInteraction.screenID = currentScreen
            UIInteraction.transitionStart = game.uiAnimationTime
        }
        renderer.beginFrame(clear: RenderColor(5, 9, 24))
        drawSpace(renderer, game: game, width: width, height: height)
        switch game.phase {
        case .playing, .paused, .upgrade, .gameOver:
            drawBattle(renderer, uiRenderer: uiRenderer, game: game, width: width, height: height)
            if game.phase == .paused { drawPause(uiRenderer, game: game, width: width, height: height) }
            if game.upgradeSelectionActive || game.phase == .upgrade { drawUpgrade(uiRenderer, game: game, width: width, height: height) }
            if game.phase == .gameOver { drawGameOver(uiRenderer, game: game, width: width, height: height) }
        case .menu: drawMenu(uiRenderer, game: game, width: width, height: height)
        case .saveSlots: drawSaveSlots(uiRenderer, game: game, width: width, height: height)
        case .missionSelect: drawMissionSelect(uiRenderer, game: game, width: width, height: height)
        case .controls: drawControls(uiRenderer, game: game, width: width, height: height)
        case .hangar: drawHangar(uiRenderer, game: game, width: width, height: height)
        case .settings: drawSettings(uiRenderer, game: game, width: width, height: height)
        case .archive: drawArchive(uiRenderer, game: game, width: width, height: height)
        }
        if game.confirmation != nil { drawConfirmation(renderer, uiRenderer: uiRenderer, game: game, width: width, height: height) }
        if game.uiDebugOverlay { drawUIDebugOverlay(uiRenderer, game: game, width: width, height: height) }
        let transitionElapsed = game.uiAnimationTime - UIInteraction.transitionStart
        if transitionElapsed >= 0, transitionElapsed < UITheme.Animation.page {
            let progress = UIAnimationSystem.easeOutCubic(transitionElapsed / UITheme.Animation.page)
            let alpha = UInt8(max(0, min(95, 95 * (1 - progress))))
            renderer.fillRect(RenderRect(x: 0, y: 0, width: Float(width), height: Float(height)), color: RenderColor(2, 6, 15, alpha))
        }
        renderer.present()
    }

    private static func drawSpace(_ r: GameRenderer, game: Game, width: Int, height: Int) {
        r.fillRect(RenderRect(x: 0, y: 0, width: Float(width), height: Float(height)), color: UITheme.Color.background)
        let hasSpaceTexture: Bool
        if let spaceTexture = (r as? SDLRenderer)?.artTexture(named: "space_nebula") {
            // Fill the 16:9 play canvas from a portrait space plate. Two
            // copies create a continuous downward drift as the craft advances.
            let tileHeight: Float = Float(width) * 1.5
            let scroll = Float(game.survivalTime * 24).truncatingRemainder(dividingBy: tileHeight)
            r.drawSprite(spaceTexture, in: RenderRect(x: 0, y: -scroll, width: Float(width), height: tileHeight), alpha: 255)
            r.drawSprite(spaceTexture, in: RenderRect(x: 0, y: tileHeight - scroll, width: Float(width), height: tileHeight), alpha: 255)
            hasSpaceTexture = true
        } else {
            hasSpaceTexture = false
        }
        for star in game.stars {
            r.fillCircle(center: (Float(star.position.x), Float(star.position.y)), radius: Float(max(1, star.radius)), color: color(star.tint))
        }
        let field = playfieldBounds(width: Double(width), height: Double(height))
        if !hasSpaceTexture {
            r.fillRect(RenderRect(x: 0, y: Float(field.top), width: Float(width), height: Float(field.bottom - field.top)), color: UITheme.Color.backgroundRaised)
            for lane in stride(from: 0, through: width, by: 96) {
                r.fillRect(RenderRect(x: Float(lane), y: Float(field.top), width: 1, height: Float(field.bottom - field.top)), color: RenderColor(70, 109, 151, 22))
            }
        }
        if game.phase == .playing || game.phase == .paused || game.phase == .upgrade || game.phase == .gameOver {
            r.fillRect(RenderRect(x: 0, y: 0, width: Float(width), height: 82), color: RenderColor(10, 21, 38, 230))
            r.fillRect(RenderRect(x: 0, y: 80, width: Float(width), height: 2), color: RenderColor(83, 136, 154, 86))
        }
    }

    private static func drawUIDebugOverlay(_ r: GameRenderer, game: Game, width: Int, height: Int) {
        var playerBullets = 0
        var enemyBullets = 0
        for bullet in game.bullets {
            if bullet.playerOwned { playerBullets += 1 } else { enemyBullets += 1 }
        }
        let x = max(8, width - 288)
        let y = max(64, height - 214)
        panel(r, x: x, y: y, width: 270, height: 194)
        text(r, "UI DEBUG  •  F9", Float(x + 14), Float(y + 22), UITheme.Color.warning)
        text(r, "SCREEN  \(String(describing: game.phase))", Float(x + 14), Float(y + 47), UITheme.Color.text)
        text(r, "FPS  \(Int(game.measuredFPS))   MOUSE  \(Int(game.mousePosition.x)),\(Int(game.mousePosition.y))", Float(x + 14), Float(y + 70), UITheme.Color.secondary)
        text(r, "ENEMIES  \(game.enemies.count)   BULLETS  \(playerBullets)/\(enemyBullets)", Float(x + 14), Float(y + 93), UITheme.Color.secondary)
        text(r, "PARTICLES  \(game.particles.count)   DAMAGE  \(game.damageNumbers.count)", Float(x + 14), Float(y + 116), UITheme.Color.secondary)
        if let boss = game.boss {
            text(r, "BOSS  P\(boss.phase)  \(boss.lifecycle)  \(boss.currentAttack)", Float(x + 14), Float(y + 139), UITheme.Color.boss)
            text(r, "ATTACK  \(boss.attackStage)  \(String(format: "%.2f", boss.attackTimer))s", Float(x + 14), Float(y + 162), UITheme.Color.secondary)
        } else {
            text(r, "BOSS  INACTIVE", Float(x + 14), Float(y + 139), UITheme.Color.muted)
        }
        text(r, "F7 BOSS  F8 FEEDBACK  F9 UI", Float(x + 14), Float(y + 185), UITheme.Color.success)
    }

    private static func drawBattle(_ r: GameRenderer, uiRenderer: GameRenderer, game: Game, width: Int, height: Int) {
        let field = playfieldBounds(width: Double(width), height: Double(height))
        let camera = game.combatFeedback.cameraOffset

        for enemy in game.enemies {
            let p = enemy.position + enemy.visualOffset + camera
            let c = highlighted(color(enemy.tint), amount: enemy.hitFlash > 0 ? 0.82 : 0)
            if enemy.isElite {
                // A thin, high-contrast outer ring makes the priority target
                // identifiable before the player reads its health bar.
                let warningColor = enemy.eliteWarningTimer > 0 ? UITheme.Color.danger : UITheme.Color.warning
                r.fillCircle(center: (Float(p.x), Float(p.y)), radius: Float(max(8, enemy.radius + 4)), color: warningColor)
                text(r, enemy.eliteWarningTimer > 0 ? "!" : "E", Float(p.x - 4), Float(p.y - enemy.radius - 20), warningColor)
            }
            if let textureName = enemyTextureName(for: enemy),
               let texture = (r as? SDLRenderer)?.artTexture(named: textureName) {
                let side = enemySpriteSide(for: enemy)
                let alpha: UInt8 = enemy.hitFlash > 0 ? 218 : 255
                r.drawSprite(texture, in: RenderRect(x: Float(p.x) - side * 0.5,
                                                     y: Float(p.y) - side * 0.5,
                                                     width: side, height: side), alpha: alpha)
                if enemy.hitFlash > 0 {
                    r.fillCircle(center: (Float(p.x), Float(p.y)), radius: Float(max(4, enemy.radius * 0.42)),
                                 color: RenderColor(255, 255, 255, 82))
                }
            } else {
                drawEnemyModel(r, enemy: enemy, position: p, body: c, time: game.uiAnimationTime)
            }
            r.fillRect(RenderRect(x: Float(p.x - enemy.radius), y: Float(p.y - enemy.radius - 8), width: Float(enemy.radius * 2), height: 3), color: RenderColor(55, 24, 47))
            r.fillRect(RenderRect(x: Float(p.x - enemy.radius), y: Float(p.y - enemy.radius - 8), width: Float(max(0, enemy.radius * 2 * enemy.health / max(1, enemy.maxHealth))), height: 3), color: RenderColor(255, 134, 126))
            if enemy.attackWarningActive {
                drawWarningBeam(r, x: Float(enemy.warningTargetX), top: Float(field.top), bottom: Float(field.bottom), active: false)
                let cosmicRayKind = enemy.warningAttackKind == 0
                    ? t(game, "COSMIC RAY • BARRAGE", "宇宙射线 • 弹流")
                    : t(game, "COSMIC RAY • BEAM", "宇宙射线 • 光束")
                centeredText(r, cosmicRayKind, centerX: Float(enemy.warningTargetX), y: Float(field.top + 8),
                             role: .caption, color: UITheme.Color.danger, shadow: true)
            }
            if enemy.dangerLaserTimer > 0 {
                drawWarningBeam(r, x: Float(enemy.warningTargetX), top: Float(field.top), bottom: Float(field.bottom), active: true)
            }
        }
        if let boss = game.boss {
            let p = boss.position + boss.visualOffset + camera
            let phaseGlow = boss.phaseFlash > 0 ? 0.58 : 0
            let left = p + Vec2(x: -ThunderCarrierBossDefinition.turretOffsetX, y: ThunderCarrierBossDefinition.turretOffsetY)
            let right = p + Vec2(x: ThunderCarrierBossDefinition.turretOffsetX, y: ThunderCarrierBossDefinition.turretOffsetY)
            if let texture = (r as? SDLRenderer)?.artTexture(named: "boss_thunder_carrier") {
                r.drawSprite(texture, in: RenderRect(x: Float(p.x - ThunderCarrierBossDefinition.visualWidth * 0.5),
                                                     y: Float(p.y - ThunderCarrierBossDefinition.visualHeight * 0.5),
                                                     width: Float(ThunderCarrierBossDefinition.visualWidth),
                                                     height: Float(ThunderCarrierBossDefinition.visualHeight)),
                             alpha: boss.hitFlash > 0 ? 218 : 255)
                drawBossDamageTextures(r, boss: boss, position: p, time: game.uiAnimationTime)
                drawGeneratedBossState(r, boss: boss, position: p, leftTurret: left, rightTurret: right,
                                       phaseGlow: phaseGlow, time: game.uiAnimationTime)
            } else {
                drawThunderCarrierBoss(r, boss: boss, position: p, leftTurret: left, rightTurret: right,
                                       highlightAmount: max(phaseGlow, boss.hitFlash > 0 ? 0.82 : 0), time: game.uiAnimationTime)
            }
            if game.uiDebugOverlay {
                r.fillCircle(center: (Float(p.x), Float(p.y)), radius: 50, color: RenderColor(85, 255, 150, 24))
                r.fillCircle(center: (Float(left.x), Float(left.y)), radius: 26, color: RenderColor(255, 230, 90, 36))
                r.fillCircle(center: (Float(right.x), Float(right.y)), radius: 26, color: RenderColor(255, 230, 90, 36))
                r.fillCircle(center: (Float(p.x), Float(p.y)), radius: 18, color: RenderColor(112, 228, 255, 48))
            }
            if boss.attackStage == .telegraph {
                drawBossTelegraph(r, boss: boss, position: p, field: field, camera: camera)
            }
            if boss.laserWarningTimer > 0 || boss.laserActiveTimer > 0 {
                let active = boss.laserActiveTimer > 0
                drawWarningBeam(r, x: Float(boss.laserX + camera.x), top: Float(field.top + camera.y),
                                bottom: Float(field.bottom + camera.y), active: active)
            }
        }
        for bullet in game.bullets {
            let p = bullet.position + camera
            if let name = bulletTextureName(bullet), let texture = (r as? SDLRenderer)?.artTexture(named: name) {
                let size = bulletTextureSize(bullet)
                r.drawSprite(texture, in: RenderRect(x: Float(p.x) - size.0 * 0.5, y: Float(p.y) - size.1 * 0.5,
                                                     width: size.0, height: size.1), alpha: 255)
            } else {
                r.fillCircle(center: (Float(p.x), Float(p.y)), radius: Float(max(2, bullet.radius)), color: color(bullet.tint))
            }
        }
        for pickup in game.powerUps {
            let p = pickup.position + camera
            let textureName = pickup.kind == 0 ? "pickup_laser_module" :
                (pickup.kind == 1 ? "pickup_invincibility_shield" : "pickup_blood_pump")
            if let texture = (r as? SDLRenderer)?.artTexture(named: textureName) {
                let pulse = Float(1 + sin(game.uiAnimationTime * 5 + pickup.position.x * 0.01) * 0.06)
                let side: Float = (pickup.kind == 1 ? 48 : 44) * pulse
                r.drawSprite(texture, in: RenderRect(x: Float(p.x) - side * 0.5, y: Float(p.y) - side * 0.5,
                                                     width: side, height: side), alpha: 255)
            }
        }
        let lowPriorityParticleStride = max(1, (game.particles.count + 599) / 600)
        for (particleIndex, particle) in game.particles.enumerated() {
            let criticalVisual = particle.kind == .coreFlash || particle.kind == .shield || particle.kind == .shockwave
            if !criticalVisual && particleIndex % lowPriorityParticleStride != 0 { continue }
            let life = max(0, min(1, particle.life / max(0.001, particle.maxLife)))
            let p = particle.position + camera
            if let texture = (r as? SDLRenderer)?.artTexture(named: particleTextureName(particle.kind)) {
                let side = particleTextureSide(particle, life: life)
                r.drawSprite(texture, in: RenderRect(x: Float(p.x) - side * 0.5, y: Float(p.y) - side * 0.5,
                                                     width: side, height: side), alpha: UInt8(min(255, max(18, 255 * life))))
            }
        }
        if let bossDeath = game.combatFeedback.bossDeath {
            let p = bossDeath.position + camera
            if let overload = (r as? SDLRenderer)?.artTexture(named: "vfx_boss_reactor") {
                let side = 72 + Float(bossDeath.elapsed) * 118
                let fade = UInt8(max(20, min(220, 220 - bossDeath.elapsed * 86)))
                r.drawSprite(overload, in: RenderRect(x: Float(p.x) - side * 0.5, y: Float(p.y) - side * 0.5,
                                                     width: side, height: side), alpha: fade)
            }
        }
        for number in game.damageNumbers {
            let p = number.position + camera
            let remaining = max(0, min(1, number.life / max(0.001, number.maxLife)))
            let value = number.critical ? "\(number.amount)!" : "\(number.amount)"
            let nColor = color(number.tint)
            text(r, value, Float(p.x), Float(p.y), RenderColor(nColor.red, nColor.green, nColor.blue, UInt8(255 * remaining)))
            if number.critical { text(r, "!", Float(p.x + 16), Float(p.y - 3), RenderColor(255, 249, 180, UInt8(220 * remaining))) }
        }
        let playerP = game.player + game.playerVisualOffset + camera
        let playerColor = game.playerShieldFlash > 0 ? RenderColor(122, 232, 204) :
            (game.playerHitFlash > 0 ? RenderColor(255, 128, 150) : RenderColor(81, 205, 255))
        if let fighter = (r as? SDLRenderer)?.artTexture(named: shipTextureName(game.shipType)) {
            let hitAlpha: UInt8 = game.playerHitFlash > 0 ? 245 : 255
            let shipSize = gameplayShipSize(game.shipType)
            r.drawSprite(fighter, in: RenderRect(x: Float(playerP.x) - shipSize.width * 0.5,
                                                 y: Float(playerP.y) - shipSize.height * 0.53,
                                                 width: shipSize.width, height: shipSize.height), alpha: hitAlpha)
        } else {
            r.fillCircle(center: (Float(playerP.x), Float(playerP.y)), radius: 18, color: playerColor)
            r.fillCircle(center: (Float(playerP.x), Float(playerP.y - 7)), radius: 8, color: game.playerHitFlash > 0 ? RenderColor(255, 246, 248) : RenderColor(232, 250, 255))
        }
        if game.armorShieldCharges > 0, let shield = (r as? SDLRenderer)?.artTexture(named: "player_phase_shield") {
            let pulse = Float(1 + sin(game.uiAnimationTime * 4.5) * 0.035)
            let side = 112 * pulse
            r.drawSprite(shield, in: RenderRect(x: Float(playerP.x) - side * 0.5, y: Float(playerP.y) - side * 0.5,
                                               width: side, height: side), alpha: 218)
        }
        if game.playerHitFlash > 0, let damage = (r as? SDLRenderer)?.artTexture(named: "vfx_damage_armor") {
            r.drawSprite(damage, in: RenderRect(x: Float(playerP.x - 39), y: Float(playerP.y - 39), width: 78, height: 78),
                         alpha: UInt8(min(245, 90 + game.playerHitFlash * 1200)))
        }
        if game.playerShieldFlash > 0, let shieldHit = (r as? SDLRenderer)?.artTexture(named: "vfx_hit_shield") {
            r.drawSprite(shieldHit, in: RenderRect(x: Float(playerP.x - 42), y: Float(playerP.y - 42), width: 84, height: 84),
                         alpha: UInt8(min(230, 70 + game.playerShieldFlash * 650)))
        }
        if game.precisionMode { r.fillCircle(center: (Float(playerP.x), Float(playerP.y)), radius: 5, color: RenderColor(255, 229, 112)) }
        if game.damageEdgeFlash > 0 {
            let alpha = UInt8(min(115, game.damageEdgeFlash * 440))
            r.fillRect(RenderRect(x: 0, y: Float(field.top), width: Float(width), height: 14), color: RenderColor(255, 55, 80, alpha))
            r.fillRect(RenderRect(x: 0, y: Float(height - 14), width: Float(width), height: 14), color: RenderColor(255, 55, 80, alpha))
            r.fillRect(RenderRect(x: 0, y: Float(field.top), width: 14, height: Float(field.bottom - field.top)), color: RenderColor(255, 55, 80, alpha))
            r.fillRect(RenderRect(x: Float(width - 14), y: Float(field.top), width: 14, height: Float(field.bottom - field.top)), color: RenderColor(255, 55, 80, alpha))
        }
        if game.notificationTimer > 0 {
            // Pick-up and boss callouts used to be a single line at the bottom of
            // the screen.  That placed them directly on top of the ship and also
            // discarded the useful explanation carried by notificationDetail.
            drawCombatNotification(uiRenderer, game: game, field: field)
        }
        drawTimedEffectBars(uiRenderer, game: game, width: width)
        // HUD is deliberately rendered after every world-space sprite and VFX.
        // Large bosses and explosions can never cover critical combat data.
        drawCombatHUD(uiRenderer, game: game, field: field, width: width)
    }

    private static func enemyTextureName(for enemy: Enemy) -> String? {
        switch EnemyType(rawValue: enemy.type) ?? .fighter {
        case .fighter: return "enemy_fighter"
        case .diver: return "enemy_diver"
        case .turret: return "enemy_turret"
        case .sniper: return "enemy_sniper"
        case .shield: return "enemy_shield"
        case .kamikaze: return "enemy_kamikaze"
        case .carrier: return "enemy_carrier"
        }
    }

    private static func shipTextureName(_ ship: ShipType) -> String {
        switch ship {
        case .thunder: return "ship_thunder"
        case .ghost: return "ship_ghost"
        case .heavy: return "ship_heavy"
        case .destroyer: return "ship_destroyer"
        case .carrier: return "ship_carrier"
        }
    }

    private static func gameplayShipSize(_ ship: ShipType) -> (width: Float, height: Float) {
        switch ship {
        case .thunder: return (64, 96)
        case .ghost: return (58, 98)
        case .heavy: return (74, 98)
        case .destroyer: return (68, 100)
        case .carrier: return (78, 100)
        }
    }

    private static func bulletTextureName(_ bullet: Bullet) -> String? {
        if bullet.playerOwned {
            switch WeaponType(rawValue: bullet.weaponStyle) ?? .cannon {
            case .cannon, .scatter: return "vfx_bullet_player_plasma"
            case .laser: return "vfx_bullet_player_laser"
            case .missile: return "vfx_bullet_missile"
            case .electromagnetic: return "vfx_bullet_electromagnetic"
            }
        }
        switch BulletType(rawValue: bullet.bulletType) ?? .normal {
        case .cosmicRayBarrage: return "vfx_cosmic_ray_barrage"
        case .boss, .explosive: return "vfx_bullet_boss_orb"
        case .piercing, .laser: return "vfx_bullet_enemy_sniper"
        default: return bullet.radius >= 7 ? "vfx_bullet_enemy_heavy" : "vfx_bullet_enemy_normal"
        }
    }

    private static func bulletTextureSize(_ bullet: Bullet) -> (Float, Float) {
        if bullet.playerOwned {
            switch WeaponType(rawValue: bullet.weaponStyle) ?? .cannon {
            case .cannon: return (16, 34)
            case .scatter: return (14, 28)
            case .laser: return (17, 44)
            case .missile: return (22, 42)
            case .electromagnetic: return (30, 30)
            }
        }
        switch BulletType(rawValue: bullet.bulletType) ?? .normal {
        case .cosmicRayBarrage: return (34, 68)
        case .boss, .explosive: return (34, 34)
        case .piercing, .laser: return (15, 42)
        default: return bullet.radius >= 7 ? (25, 36) : (17, 28)
        }
    }

    private static func particleTextureName(_ kind: FeedbackParticleKind) -> String {
        switch kind {
        case .spark: return "vfx_hit_kinetic"
        case .coreFlash: return "vfx_explosion_core"
        case .debris: return "vfx_hit_plasma"
        case .smoke: return "vfx_boss_smoke"
        case .shield: return "vfx_hit_shield"
        case .shockwave: return "vfx_hit_critical"
        }
    }

    private static func particleTextureSide(_ particle: Particle, life: Double) -> Float {
        let radius = Float(particle.radius)
        switch particle.kind {
        case .spark: return min(34, max(16, radius * 7))
        case .coreFlash: return min(104, max(46, radius * 5.5))
        case .debris: return min(42, max(18, radius * 6))
        case .smoke: return min(78, max(30, radius * Float(7.5 + (1 - life) * 2)))
        case .shield: return min(48, max(22, radius * 7))
        case .shockwave: return min(170, max(48, radius * Float(5 + (1 - life) * 12)))
        }
    }

    private static func drawWarningBeam(_ r: GameRenderer, x: Float, top: Float, bottom: Float, active: Bool) {
        let textureName = active ? "vfx_cosmic_ray_beam" : "vfx_warning_beam"
        guard let texture = (r as? SDLRenderer)?.artTexture(named: textureName) else { return }
        let width: Float = active ? 64 : 20
        r.drawSprite(texture, in: RenderRect(x: x - width * 0.5, y: top, width: width, height: max(1, bottom - top)),
                     alpha: active ? 252 : 168)
    }

    private static func drawBossDamageTextures(_ r: GameRenderer, boss: Boss, position p: Vec2, time: Double) {
        let healthRatio = boss.health / max(1, boss.maxHealth)
        if healthRatio < 0.72, let cracks = (r as? SDLRenderer)?.artTexture(named: "vfx_boss_cracks") {
            r.drawSprite(cracks, in: RenderRect(x: Float(p.x - 83), y: Float(p.y - 46), width: 108, height: 72), alpha: 205)
        }
        if healthRatio < 0.48, let smoke = (r as? SDLRenderer)?.artTexture(named: "vfx_boss_smoke") {
            let pulse = Float(1 + sin(time * 3.5) * 0.05)
            r.drawSprite(smoke, in: RenderRect(x: Float(p.x + 23) - 62 * pulse, y: Float(p.y - 52) - 42 * pulse,
                                              width: 124 * pulse, height: 84 * pulse), alpha: 190)
        }
        if boss.phase >= 3, let electric = (r as? SDLRenderer)?.artTexture(named: "vfx_boss_electric") {
            r.drawSprite(electric, in: RenderRect(x: Float(p.x - 72), y: Float(p.y - 52), width: 144, height: 104),
                         alpha: UInt8(175 + Int((sin(time * 11) + 1) * 35)))
        }
        if boss.weakPointOpen, let reactor = (r as? SDLRenderer)?.artTexture(named: "vfx_boss_reactor") {
            r.drawSprite(reactor, in: RenderRect(x: Float(p.x - 42), y: Float(p.y - 36), width: 84, height: 72), alpha: 225)
        }
    }

    private static func enemySpriteSide(for enemy: Enemy) -> Float {
        let base: Float
        switch EnemyType(rawValue: enemy.type) ?? .fighter {
        case .fighter: base = 70
        case .diver: base = 78
        case .turret: base = 92
        case .sniper: base = 84
        case .shield: base = 90
        case .kamikaze: base = 70
        case .carrier: base = 112
        }
        return enemy.isElite ? base * 1.12 : base
    }

    /// Keeps destructible parts and the exposed reactor readable while the
    /// generated sprite remains the primary visual model.
    private static func drawGeneratedBossState(_ r: GameRenderer, boss: Boss, position p: Vec2,
                                               leftTurret: Vec2, rightTurret: Vec2,
                                               phaseGlow: Double, time: Double) {
        if phaseGlow > 0, let flash = (r as? SDLRenderer)?.artTexture(named: "vfx_hit_critical") {
            r.drawSprite(flash, in: RenderRect(x: Float(p.x - 78), y: Float(p.y - 78), width: 156, height: 156),
                         alpha: UInt8(min(180, phaseGlow * 260)))
        }
        if boss.leftTurretHealth <= 0 {
            drawDestroyedBossPart(r, at: leftTurret)
        }
        if boss.rightTurretHealth <= 0 {
            drawDestroyedBossPart(r, at: rightTurret)
        }
        _ = time
    }

    private static func drawDestroyedBossPart(_ r: GameRenderer, at p: Vec2) {
        if let damage = (r as? SDLRenderer)?.artTexture(named: "vfx_boss_cracks") {
            r.drawSprite(damage, in: RenderRect(x: Float(p.x - 40), y: Float(p.y - 32), width: 80, height: 64), alpha: 235)
        }
    }

    /// Resource-failure fallback. Normal gameplay uses generated image sprites;
    /// collision remains independent from either visual representation.
    private static func drawEnemyModel(_ r: GameRenderer, enemy: Enemy, position p: Vec2, body: RenderColor, time: Double) {
        let x = Float(p.x), y = Float(p.y)
        let s = Float(max(0.78, enemy.radius / 20.0))
        let dark = RenderColor(UInt8(Double(body.red) * 0.34), UInt8(Double(body.green) * 0.34), UInt8(Double(body.blue) * 0.38), body.alpha)
        let edge = highlighted(body, amount: enemy.isElite ? 0.34 : 0.12)
        let enginePulse = Float(1 + sin(time * 9 + enemy.phase) * 0.16)
        let type = EnemyType(rawValue: enemy.type) ?? .fighter

        switch type {
        case .fighter:
            // Compact interceptor: forward nose, straight wings, twin engines.
            r.line(from: (x, y - 17 * s), to: (x, y + 19 * s), color: edge)
            r.line(from: (x, y + 14 * s), to: (x - 20 * s, y - 9 * s), color: edge)
            r.line(from: (x, y + 14 * s), to: (x + 20 * s, y - 9 * s), color: edge)
            r.fillRect(RenderRect(x: x - 14 * s, y: y - 9 * s, width: 28 * s, height: 8 * s), color: dark)
            r.fillRect(RenderRect(x: x - 5 * s, y: y - 13 * s, width: 10 * s, height: 27 * s), color: body)
            r.fillCircle(center: (x, y + 6 * s), radius: 3.5 * s, color: RenderColor(255, 184, 194))
            enemyEngine(r, x: x - 7 * s, y: y - 13 * s, scale: s * enginePulse, tint: body)
            enemyEngine(r, x: x + 7 * s, y: y - 13 * s, scale: s * enginePulse, tint: body)

        case .diver:
            // Swept arrowhead visually communicates speed and commitment.
            r.line(from: (x, y + 22 * s), to: (x, y - 22 * s), color: edge)
            r.line(from: (x, y + 18 * s), to: (x - 22 * s, y - 16 * s), color: edge)
            r.line(from: (x, y + 18 * s), to: (x + 22 * s, y - 16 * s), color: edge)
            r.line(from: (x - 22 * s, y - 16 * s), to: (x - 5 * s, y - 9 * s), color: dark)
            r.line(from: (x + 22 * s, y - 16 * s), to: (x + 5 * s, y - 9 * s), color: dark)
            r.fillRect(RenderRect(x: x - 4 * s, y: y - 15 * s, width: 8 * s, height: 31 * s), color: body)
            r.fillCircle(center: (x, y + 5 * s), radius: 4 * s, color: RenderColor(255, 222, 135))
            enemyEngine(r, x: x, y: y - 18 * s, scale: 1.35 * s * enginePulse, tint: RenderColor(255, 103, 77))

        case .turret:
            // Broad armored gunship with an unmistakable twin cannon battery.
            r.fillRect(RenderRect(x: x - 23 * s, y: y - 9 * s, width: 46 * s, height: 20 * s), color: dark)
            r.fillRect(RenderRect(x: x - 15 * s, y: y - 14 * s, width: 30 * s, height: 27 * s), color: body)
            r.fillCircle(center: (x, y - 2 * s), radius: 8 * s, color: edge)
            r.fillCircle(center: (x, y - 2 * s), radius: 4 * s, color: RenderColor(255, 224, 142))
            r.fillRect(RenderRect(x: x - 18 * s, y: y + 8 * s, width: 5 * s, height: 18 * s), color: edge)
            r.fillRect(RenderRect(x: x + 13 * s, y: y + 8 * s, width: 5 * s, height: 18 * s), color: edge)
            enemyEngine(r, x: x - 8 * s, y: y - 15 * s, scale: s * enginePulse, tint: body)
            enemyEngine(r, x: x + 8 * s, y: y - 15 * s, scale: s * enginePulse, tint: body)

        case .sniper:
            // Long central rail and optical core identify the telegraphed shot.
            r.line(from: (x - 18 * s, y + 11 * s), to: (x, y - 19 * s), color: edge)
            r.line(from: (x + 18 * s, y + 11 * s), to: (x, y - 19 * s), color: edge)
            r.fillRect(RenderRect(x: x - 5 * s, y: y - 17 * s, width: 10 * s, height: 34 * s), color: dark)
            r.fillRect(RenderRect(x: x - 2 * s, y: y + 8 * s, width: 4 * s, height: 18 * s), color: edge)
            let charge = enemy.attackWarningActive ? RenderColor(255, 75, 132) : RenderColor(205, 181, 255)
            r.fillCircle(center: (x, y + 7 * s), radius: enemy.attackWarningActive ? 7 * s : 5 * s, color: charge)
            r.line(from: (x - 18 * s, y + 11 * s), to: (x - 7 * s, y + 3 * s), color: body)
            r.line(from: (x + 18 * s, y + 11 * s), to: (x + 7 * s, y + 3 * s), color: body)
            enemyEngine(r, x: x, y: y - 18 * s, scale: s * enginePulse, tint: body)

        case .shield:
            // Projector ring surrounds a small support craft.
            r.fillCircle(center: (x, y), radius: 25 * s, color: RenderColor(body.red, body.green, body.blue, 45))
            r.fillCircle(center: (x, y), radius: 20 * s, color: dark)
            r.fillCircle(center: (x, y), radius: 14 * s, color: body)
            r.fillRect(RenderRect(x: x - 22 * s, y: y - 2 * s, width: 44 * s, height: 4 * s), color: edge)
            r.fillRect(RenderRect(x: x - 2 * s, y: y - 22 * s, width: 4 * s, height: 44 * s), color: edge)
            r.fillCircle(center: (x, y), radius: 6 * s, color: RenderColor(191, 255, 238))

        case .kamikaze:
            // Small dart with an oversized unstable core and hot exhaust.
            r.line(from: (x, y + 21 * s), to: (x - 15 * s, y - 16 * s), color: edge)
            r.line(from: (x, y + 21 * s), to: (x + 15 * s, y - 16 * s), color: edge)
            r.line(from: (x - 15 * s, y - 16 * s), to: (x, y - 9 * s), color: dark)
            r.line(from: (x + 15 * s, y - 16 * s), to: (x, y - 9 * s), color: dark)
            r.fillCircle(center: (x, y), radius: (6 + Float(sin(time * 12 + enemy.phase)) * 1.5) * s,
                         color: RenderColor(255, 224, 167))
            enemyEngine(r, x: x, y: y - 16 * s, scale: 1.5 * s * enginePulse, tint: RenderColor(255, 70, 78))

        case .carrier:
            // Heavy carrier: wide hull, side bays and a luminous launch deck.
            r.fillRect(RenderRect(x: x - 31 * s, y: y - 10 * s, width: 62 * s, height: 25 * s), color: dark)
            r.fillRect(RenderRect(x: x - 18 * s, y: y - 19 * s, width: 36 * s, height: 39 * s), color: body)
            r.fillRect(RenderRect(x: x - 35 * s, y: y - 4 * s, width: 13 * s, height: 24 * s), color: edge)
            r.fillRect(RenderRect(x: x + 22 * s, y: y - 4 * s, width: 13 * s, height: 24 * s), color: edge)
            r.fillRect(RenderRect(x: x - 11 * s, y: y + 4 * s, width: 22 * s, height: 12 * s), color: RenderColor(49, 24, 66))
            r.fillCircle(center: (x, y - 8 * s), radius: 7 * s, color: RenderColor(241, 171, 255))
            enemyEngine(r, x: x - 15 * s, y: y - 21 * s, scale: 1.1 * s * enginePulse, tint: body)
            enemyEngine(r, x: x + 15 * s, y: y - 21 * s, scale: 1.1 * s * enginePulse, tint: body)
        }
    }

    private static func enemyEngine(_ r: GameRenderer, x: Float, y: Float, scale: Float, tint: RenderColor) {
        r.fillCircle(center: (x, y), radius: max(2, 3.4 * scale), color: RenderColor(tint.red, tint.green, tint.blue, 150))
        r.line(from: (x, y - 2 * scale), to: (x, y - 9 * scale), color: RenderColor(255, 184, 104, 190))
    }

    /// Resource-failure fallback for the generated carrier sprite.
    private static func drawThunderCarrierBoss(_ r: GameRenderer, boss: Boss, position p: Vec2,
                                               leftTurret: Vec2, rightTurret: Vec2,
                                               highlightAmount: Double, time: Double) {
        let x = Float(p.x), y = Float(p.y)
        let lx = Float(leftTurret.x), ly = Float(leftTurret.y)
        let rx = Float(rightTurret.x), ry = Float(rightTurret.y)
        let phaseAccent: RenderColor = boss.phase >= 3 ? RenderColor(255, 89, 172) :
            (boss.phase == 2 ? RenderColor(255, 142, 92) : RenderColor(167, 102, 231))
        let armor = highlighted(RenderColor(56, 45, 79), amount: highlightAmount)
        let armorRaised = highlighted(RenderColor(91, 61, 119), amount: highlightAmount)
        let seam = highlighted(phaseAccent, amount: highlightAmount * 0.55)
        let reactorPulse = Float(1 + sin(time * (boss.phase >= 3 ? 10 : 6)) * 0.10)

        // Rear engine bank and broad silhouette shadow.
        r.fillRect(RenderRect(x: x - 68, y: y - 33, width: 136, height: 73), color: RenderColor(19, 17, 31, 238))
        for offset in [-44.0, -15.0, 15.0, 44.0] {
            enemyEngine(r, x: x + Float(offset), y: y - 35, scale: 1.35 * reactorPulse, tint: phaseAccent)
        }

        // Swept armored shoulders create the wide, threatening boss footprint.
        r.fillRect(RenderRect(x: x - 91, y: y - 21, width: 55, height: 43), color: armor)
        r.fillRect(RenderRect(x: x + 36, y: y - 21, width: 55, height: 43), color: armor)
        r.line(from: (x - 91, y - 21), to: (x - 119, y + 20), color: armorRaised)
        r.line(from: (x + 91, y - 21), to: (x + 119, y + 20), color: armorRaised)
        r.line(from: (x - 91, y + 22), to: (x - 119, y + 20), color: seam)
        r.line(from: (x + 91, y + 22), to: (x + 119, y + 20), color: seam)
        r.fillRect(RenderRect(x: x - 77, y: y - 12, width: 31, height: 12), color: armorRaised)
        r.fillRect(RenderRect(x: x + 46, y: y - 12, width: 31, height: 12), color: armorRaised)

        // Central armored spine, lower prow and segmented plating.
        r.fillRect(RenderRect(x: x - 39, y: y - 46, width: 78, height: 86), color: armor)
        r.fillRect(RenderRect(x: x - 29, y: y - 35, width: 58, height: 66), color: armorRaised)
        r.line(from: (x - 39, y + 28), to: (x, y + 59), color: seam)
        r.line(from: (x + 39, y + 28), to: (x, y + 59), color: seam)
        r.line(from: (x, y + 59), to: (x, y + 32), color: seam)
        r.fillRect(RenderRect(x: x - 4, y: y - 43, width: 8, height: 74), color: RenderColor(seam.red, seam.green, seam.blue, 160))
        r.fillRect(RenderRect(x: x - 31, y: y - 17, width: 62, height: 3), color: seam)
        r.fillRect(RenderRect(x: x - 31, y: y + 13, width: 62, height: 3), color: seam)

        // Independent turret arms mirror their actual destructible hitboxes.
        r.line(from: (x - 66, y + 3), to: (lx + 18, ly - 2), color: armorRaised)
        r.line(from: (x + 66, y + 3), to: (rx - 18, ry - 2), color: armorRaised)
        drawBossTurret(r, x: lx, y: ly, alive: boss.leftTurretHealth > 0, accent: RenderColor(232, 104, 165), facingOffset: -1)
        drawBossTurret(r, x: rx, y: ry, alive: boss.rightTurretHealth > 0, accent: RenderColor(255, 151, 92), facingOffset: 1)

        // The reactor remains readable at bullet-hell scale. Armor shutters
        // retract visually once the weak point is exposed.
        if boss.weakPointOpen {
            r.fillCircle(center: (x, y), radius: 24 * reactorPulse, color: RenderColor(102, 229, 255, 74))
            r.fillCircle(center: (x, y), radius: 15 * reactorPulse, color: RenderColor(199, 249, 255))
            r.fillCircle(center: (x, y), radius: 7 * reactorPulse, color: RenderColor(255, 255, 240))
        } else {
            r.fillCircle(center: (x, y), radius: 16, color: RenderColor(36, 27, 53))
            r.fillCircle(center: (x, y), radius: 9 * reactorPulse, color: phaseAccent)
            r.line(from: (x - 26, y - 20), to: (x - 8, y - 5), color: armor)
            r.line(from: (x + 26, y - 20), to: (x + 8, y - 5), color: armor)
        }

        // Damage state: broken armor seams and electrical flicker intensify by phase.
        if boss.phase >= 2 {
            r.line(from: (x - 65, y - 19), to: (x - 51, y - 4), color: RenderColor(255, 178, 92, 210))
            r.line(from: (x + 54, y + 1), to: (x + 69, y + 17), color: RenderColor(255, 178, 92, 210))
        }
        if boss.phase >= 3 {
            let flicker = UInt8(140 + Int((sin(time * 13) + 1) * 45))
            r.line(from: (x - 26, y - 32), to: (x - 12, y - 20), color: RenderColor(126, 229, 255, flicker))
            r.line(from: (x + 18, y + 26), to: (x + 32, y + 40), color: RenderColor(126, 229, 255, flicker))
        }
    }

    private static func drawBossTurret(_ r: GameRenderer, x: Float, y: Float, alive: Bool, accent: RenderColor, facingOffset: Float) {
        let base = alive ? RenderColor(66, 48, 82) : RenderColor(39, 38, 47)
        let edge = alive ? accent : RenderColor(88, 75, 89)
        r.fillRect(RenderRect(x: x - 23, y: y - 17, width: 46, height: 34), color: base)
        r.fillRect(RenderRect(x: x - 15, y: y - 12, width: 30, height: 24), color: edge)
        r.fillCircle(center: (x, y - 1), radius: 8, color: alive ? RenderColor(245, 211, 233) : RenderColor(72, 67, 76))
        if alive {
            r.fillRect(RenderRect(x: x - 13 + facingOffset * 2, y: y + 12, width: 7, height: 25), color: accent)
            r.fillRect(RenderRect(x: x + 6 + facingOffset * 2, y: y + 12, width: 7, height: 25), color: accent)
        } else {
            r.line(from: (x - 17, y - 13), to: (x + 17, y + 13), color: RenderColor(16, 14, 21))
            r.line(from: (x + 17, y - 13), to: (x - 17, y + 13), color: RenderColor(16, 14, 21))
        }
    }

    private static func drawBossTelegraph(_ r: GameRenderer, boss: Boss, position p: Vec2,
                                          field: PlayfieldBounds, camera: Vec2) {
        let origin = p + Vec2(x: 0, y: 34)
        switch boss.currentAttack {
        case .aimBurst:
            let target = boss.attackTarget + camera
            // A burst follows one aimed lane: warn only that trajectory, not
            // the whole screen. Incidental single turret shots remain unmarked.
            drawBossWarningRay(r, from: origin, direction: (target - origin).normalized, field: field)
        case .spread:
            let count = boss.phase == 1 ? 7 : 9
            let spread = boss.phase == 1 ? 0.52 : 0.68
            for index in 0..<count {
                let t = count == 1 ? 0.5 : Double(index) / Double(count - 1)
                let angle = -spread + t * spread * 2
                drawBossWarningRay(r, from: origin, direction: rotated(Vec2(x: 0, y: 1), by: angle), field: field)
            }
        case .sideCrossfire:
            // The two side emitters create two readable parallel danger lanes.
            if boss.leftTurretHealth > 0 {
                for laneOffset in [-12.0, 12.0] {
                    let laneOrigin = p + Vec2(x: -ThunderCarrierBossDefinition.turretOffsetX + laneOffset,
                                              y: ThunderCarrierBossDefinition.turretOffsetY)
                    drawBossWarningRay(r, from: laneOrigin, direction: Vec2(x: 0, y: 1), field: field)
                }
            }
            if boss.rightTurretHealth > 0 {
                for laneOffset in [-12.0, 12.0] {
                    let laneOrigin = p + Vec2(x: ThunderCarrierBossDefinition.turretOffsetX + laneOffset,
                                              y: ThunderCarrierBossDefinition.turretOffsetY)
                    drawBossWarningRay(r, from: laneOrigin, direction: Vec2(x: 0, y: 1), field: field)
                }
            }
        case .laserSweep:
            let left = min(boss.laserX, boss.laserTargetX) + camera.x
            let sweepWidth = abs(boss.laserTargetX - boss.laserX)
            r.fillRect(RenderRect(x: Float(left), y: Float(field.top + camera.y), width: Float(sweepWidth),
                                  height: Float(field.bottom - field.top)), color: RenderColor(255, 42, 72, 38))
            drawWarningBeam(r, x: Float(boss.laserX + camera.x), top: Float(field.top + camera.y),
                            bottom: Float(field.bottom + camera.y), active: false)
        case .slowField:
            // The delayed semicircle exposes its actual fan before activation.
            for index in 0..<9 {
                let angle = -Double.pi * 0.46 + Double(index) / 8.0 * Double.pi * 0.92
                var direction = rotated(Vec2(x: 0, y: 1), by: angle)
                if direction.y < 0.22 { direction.y = 0.22; direction = direction.normalized }
                drawBossWarningRay(r, from: origin, direction: direction, field: field)
            }
        case .spiral:
            // Show the two mirrored fan families without drawing every future
            // curved sample; alternating brightness keeps the paths legible.
            for index in 0..<10 {
                let angle = -1.08 + Double(index) / 9.0 * 2.16
                drawBossWarningRay(r, from: origin, direction: rotated(Vec2(x: 0, y: 1), by: angle), field: field)
            }
        }
    }

    private static func drawBossWarningRay(_ r: GameRenderer, from origin: Vec2,
                                           direction rawDirection: Vec2, field: PlayfieldBounds) {
        var direction = rawDirection.normalized
        if direction.y < 0.12 { direction.y = 0.12; direction = direction.normalized }
        let distance = max(1, (field.bottom - origin.y) / direction.y)
        let end = origin + direction * distance
        let perpendicular = Vec2(x: -direction.y, y: direction.x)
        for (offset, alpha) in [(-3.0, 34.0), (-1.5, 74.0), (0.0, 220.0), (1.5, 74.0), (3.0, 34.0)] {
            let shift = perpendicular * offset
            r.line(from: (Float(origin.x + shift.x), Float(origin.y + shift.y)),
                   to: (Float(end.x + shift.x), Float(end.y + shift.y)),
                   color: RenderColor(255, 48, 72, UInt8(alpha)))
        }
    }

    private static func drawCombatHUD(_ r: GameRenderer, game: Game, field: PlayfieldBounds, width: Int) {
        // All combat information stays on the frame edges. The center of the
        // playfield remains clear for the fighter, bullets and boss warnings.
        r.fillRect(RenderRect(x: 0, y: 0, width: Float(width), height: 82), color: RenderColor(4, 12, 27, 246))
        r.fillRect(RenderRect(x: 0, y: 80, width: Float(width), height: 2), color: UITheme.Color.primaryDeep)
        r.fillRect(RenderRect(x: 0, y: 80, width: 150, height: 2), color: UITheme.Color.primary)
        r.fillRect(RenderRect(x: Float(width - 150), y: 80, width: 150, height: 2), color: UITheme.Color.primary)
        drawPlayerTopHUD(r, game: game)
        if let boss = game.boss {
            drawBossTopHUD(r, game: game, boss: boss, width: width)
        } else {
            drawMissionTopHUD(r, game: game, width: width)
        }
        drawScoreTopHUD(r, game: game, width: width)

        if let comboBurst = game.combatFeedback.comboFeedback {
            let life = max(0, min(1, 1 - comboBurst.elapsed / 0.9))
            let burstColor = color(comboBurst.tint)
            let label = "\(comboBurst.count) " + t(game, "COMBO!", "连击!")
            centeredText(r, label, centerX: Float(width) * 0.5,
                         y: Float(field.top + 58 - comboBurst.elapsed * 24), role: .sectionTitle,
                         color: RenderColor(burstColor.red, burstColor.green, burstColor.blue, UInt8(255 * life)), shadow: true)
        }

        drawThunderControlHUD(r, game: game, field: field)
        drawWeaponControlHUD(r, game: game, field: field, width: width)
        if game.survivalTime < 8 {
            let hint = t(game, "MOVE  WASD   •   PRECISION  SHIFT   •   OVERLOAD  SPACE",
                         "WASD 移动   •   SHIFT 精准   •   SPACE 超载")
            centeredText(r, hint, centerX: Float(width) * 0.5, y: Float(field.bottom - 20),
                         role: .caption, color: UITheme.Color.muted)
        }
    }

    private static func drawPlayerTopHUD(_ r: GameRenderer, game: Game) {
        hudPanel(r, x: 16, y: 8, width: 306, height: 64, accent: UITheme.Color.danger)
        styledText(r, t(game, "ARMOR", "机体耐久"), x: 30, y: 12, role: .caption,
                   color: game.armorShieldCharges > 0 ? UITheme.Color.shield : UITheme.Color.secondary)
        styledRightText(r, "\(Int(max(0, game.health))) / \(Int(game.maxHealth))", right: 307, y: 11,
                        role: .body, color: game.healthBarFlash > 0 ? UITheme.Color.warning : UITheme.Color.text)
        hudSegments(r, x: 30, y: 35, width: 278, height: 11, segments: 16,
                    value: game.health / max(1, game.maxHealth),
                    fill: UITheme.Color.danger, back: RenderColor(63, 35, 52),
                    lag: game.healthLag / max(1, game.maxHealth))
        let xp = t(game, "XP", "经验") + " \(game.experience)/\(game.experienceGoal)"
        styledText(r, ellipsized(xp, maxWidth: 130, scale: UITextRole.caption.scale),
                   x: 30, y: 52, role: .caption, color: UITheme.Color.secondary)
        hudSegments(r, x: 173, y: 59, width: 135, height: 5, segments: 10,
                    value: Double(game.experience) / Double(max(1, game.experienceGoal)),
                    fill: UITheme.Color.energy, back: RenderColor(24, 53, 68))
    }

    private static func drawMissionTopHUD(_ r: GameRenderer, game: Game, width: Int) {
        let x = Float(width) * 0.5 - 308
        hudPanel(r, x: x, y: 8, width: 616, height: 64, accent: UITheme.Color.primary)
        let mode = game.gameMode == .endless ? t(game, "ENDLESS", "无尽模式") : t(game, "CAMPAIGN", "战役模式")
        let stage = game.gameMode == .endless
            ? t(game, "WAVE", "第") + " \(game.endlessWaveNumber)" + t(game, "", " 波")
            : t(game, "STAGE", "第") + " \(game.stage)" + t(game, "", " 关")
        let elapsed = Int(game.survivalTime)
        let clock = String(format: "%02d:%02d", elapsed / 60, elapsed % 60)
        styledText(r, mode, x: x + 18, y: 14, role: .caption, color: UITheme.Color.primary)
        centeredText(r, stage, centerX: Float(width) * 0.5, y: 11,
                     role: .sectionTitle, color: UITheme.Color.text)
        styledRightText(r, clock, right: x + 598, y: 14, role: .caption, color: UITheme.Color.secondary)
        r.line(from: (x + 18, 40), to: (x + 598, 40), color: UITheme.Color.border)
        let missionTitle: String
        if game.gameMode == .endless {
            missionTitle = t(game, "SURVIVE THE SWARM", "突破无尽弹幕")
        } else {
            let index = min(MissionCatalog.all.count - 1, max(0, game.selectedMission))
            missionTitle = MissionCatalog.all[index].title(for: game.language)
        }
        // 战力门槛提示（规格第 7.4 节）：不足门槛时对敌伤害按比例折算。
        let belowGate = game.activePowerGateScale < 0.999
        centeredText(r, ellipsized(missionTitle, maxWidth: belowGate ? 260 : 530, scale: UITextRole.caption.scale),
                     centerX: Float(width) * 0.5, y: 48, role: .caption, color: UITheme.Color.secondary)
        if belowGate {
            let percent = Int((game.activePowerGateScale * 100).rounded())
            styledRightText(r, t(game, "DMG SCALE \(percent)%", "伤害折算 \(percent)%"), right: x + 598, y: 48,
                            role: .caption, color: UITheme.Color.danger)
        }
    }

    private static func drawScoreTopHUD(_ r: GameRenderer, game: Game, width: Int) {
        let x = Float(width - 322)
        hudPanel(r, x: x, y: 8, width: 306, height: 64, accent: UITheme.Color.warning)
        styledText(r, t(game, "SCORE", "分数"), x: x + 16, y: 14, role: .caption, color: UITheme.Color.warning)
        styledRightText(r, t(game, "KILLS", "击杀") + " \(game.kills)", right: x + 290, y: 14,
                        role: .caption, color: UITheme.Color.secondary)
        styledText(r, ellipsized("\(game.score)", maxWidth: 178, scale: UITextRole.number.scale),
                   x: x + 16, y: 34, role: .number, color: UITheme.Color.text)
        r.line(from: (x + 198, 34), to: (x + 198, 65), color: UITheme.Color.border)
        styledRightText(r, "×\(max(1, game.combo))", right: x + 289, y: 33, role: .body,
                        color: game.combo >= 50 ? UITheme.Color.warning : (game.combo > 1 ? UITheme.Color.primary : UITheme.Color.muted))
        styledRightText(r, t(game, "COMBO", "连击"), right: x + 289, y: 54, role: .caption,
                        color: UITheme.Color.muted)
    }

    private static func drawThunderControlHUD(_ r: GameRenderer, game: Game, field: PlayfieldBounds) {
        let ready = game.thunderEnergy >= CombatConfig.thunderOverloadCost
        let burstReady = game.thunderEnergy >= CombatConfig.thunderBurstCost
        let tint = ready ? UITheme.Color.warning : (burstReady ? UITheme.Color.primary : UITheme.Color.energy)
        let x: Float = 16
        let y = Float(field.bottom - 112)
        hudPanel(r, x: x, y: y - 28, width: 306, height: 24, accent: UITheme.Color.secondary)
        let stats = [t(game, "SHOT", "弹幕") + "+\(game.projectileCountBonus)",
                     t(game, "PEN", "穿透") + "+\(game.projectilePenetration)",
                     t(game, "CRIT", "暴击") + " \(Int(game.criticalChance * 100))%"]
        for (index, stat) in stats.enumerated() {
            centeredText(r, ellipsized(stat, maxWidth: 91, scale: UITextRole.caption.scale),
                         centerX: x + 54 + Float(index) * 101, y: y - 24,
                         role: .caption, color: UITheme.Color.secondary)
        }

        hudPanel(r, x: x, y: y, width: 306, height: 96, accent: tint)
        let ringX = x + 49
        let ringY = y + 48
        hudRing(r, centerX: ringX, centerY: ringY, radius: 36,
                value: game.thunderEnergy / 100, tint: tint)
        centeredText(r, "SPACE", centerX: ringX, y: ringY - 8, role: .caption, color: tint)
        styledText(r, t(game, "THUNDER ENERGY", "雷霆能量"), x: x + 99, y: y + 11,
                   role: .caption, color: UITheme.Color.secondary)
        styledRightText(r, "\(Int(game.thunderEnergy))%", right: x + 290, y: y + 9,
                        role: .number, color: tint)
        let status = ready ? t(game, "OVERLOAD READY", "超载就绪") :
            (burstReady ? t(game, "BURST READY", "爆发就绪") : t(game, "CHARGING", "正在充能"))
        styledText(r, status, x: x + 99, y: y + 38, role: .body,
                   color: ready ? UITheme.Color.warning : UITheme.Color.text)
        hudSegments(r, x: x + 99, y: y + 68, width: 190, height: 7, segments: 10,
                    value: game.thunderEnergy / 100, fill: tint, back: RenderColor(24, 53, 68))
        styledText(r, t(game, "50 BURST  /  100 OVERLOAD", "50 爆发  /  100 超载"),
                   x: x + 99, y: y + 75, role: .caption, color: UITheme.Color.muted)
    }

    private static func drawWeaponControlHUD(_ r: GameRenderer, game: Game, field: PlayfieldBounds, width: Int) {
        let x = Float(width - 322)
        let y = Float(field.bottom - 112)
        let dashReady = game.dashCooldown <= 0.05
        let dashTint = dashReady ? UITheme.Color.success : UITheme.Color.muted
        hudPanel(r, x: x, y: y, width: 306, height: 96, accent: UITheme.Color.primary)
        styledText(r, t(game, "LOADOUT WEAPON", "出战主武器"), x: x + 16, y: y + 11,
                   role: .caption, color: UITheme.Color.primary)
        styledText(r, ellipsized(game.activeWeaponName.isEmpty
                                  ? t(game, "STANDARD CANNON", "标准机炮")
                                  : game.activeWeaponName,
                                maxWidth: 187, scale: UITextRole.body.scale),
                   x: x + 16, y: y + 34, role: .body, color: UITheme.Color.text)
        styledText(r, "LV.\(game.weaponLevel)", x: x + 16, y: y + 55,
                   role: .caption, color: UITheme.Color.secondary)
        r.line(from: (x + 16, y + 75), to: (x + 202, y + 75), color: UITheme.Color.border)
        let dashLabel = dashReady ? t(game, "DASH READY", "闪避就绪") :
            t(game, "DASH", "闪避") + "  \(String(format: "%.1f", game.dashCooldown))s"
        styledRightText(r, dashLabel, right: x + 200, y: y + 77,
                        role: .caption, color: dashTint)
        let ringX = x + 256
        let ringY = y + 48
        hudRing(r, centerX: ringX, centerY: ringY, radius: 36,
                value: 1 - game.dashCooldown / 4.8, tint: dashTint)
        centeredText(r, "F", centerX: ringX, y: ringY - 16,
                     role: .sectionTitle, color: dashTint)
        centeredText(r, dashReady ? t(game, "READY", "就绪") : t(game, "WAIT", "冷却"),
                     centerX: ringX, y: ringY + 8, role: .caption, color: dashTint)
    }

    private static func drawBossTopHUD(_ r: GameRenderer, game: Game, boss: Boss, width: Int) {
        let x = Float(width) * 0.5 - 308
        hudPanel(r, x: x, y: 8, width: 616, height: 64, accent: UITheme.Color.boss)
        let bossName = BossType(rawValue: boss.kind)?.title(for: game.language) ?? t(game, "DREADNOUGHT", "无畏战舰")
        let title = t(game, "BOSS", "首领") + "  " + bossName
        styledText(r, ellipsized(title, maxWidth: 440, scale: UITextRole.body.scale),
                   x: x + 18, y: 9, role: .body, color: UITheme.Color.text)
        styledRightText(r, t(game, "PHASE", "阶段") + " \(boss.phase)", right: x + 598, y: 12,
                        role: .caption, color: UITheme.Color.boss)

        let healthRatio = min(1, max(0, boss.health / max(1, boss.maxHealth)))
        let layerValue: Double
        let layerColor: RenderColor
        let revealedColor: RenderColor
        if healthRatio > 0.70 {
            layerValue = (healthRatio - 0.70) / 0.30
            layerColor = RenderColor(75, 222, 143)
            revealedColor = RenderColor(255, 158, 72)
        } else if healthRatio > 0.30 {
            layerValue = (healthRatio - 0.30) / 0.40
            layerColor = RenderColor(255, 158, 72)
            revealedColor = RenderColor(255, 72, 96)
        } else {
            layerValue = healthRatio / 0.30
            layerColor = RenderColor(255, 72, 96)
            revealedColor = RenderColor(62, 26, 39)
        }
        // The next phase fills the track below the current phase. Each phase
        // still occupies the same single bar, so the boss never crowds the HUD.
        r.fillRect(RenderRect(x: x + 18, y: 33, width: 580, height: 12), color: revealedColor)
        r.fillRect(RenderRect(x: x + 18, y: 33, width: 580 * Float(min(1, max(0, layerValue))), height: 12),
                   color: layerColor)
        for notch in 1..<16 {
            let notchX = x + 18 + Float(notch) * 580 / 16
            r.line(from: (notchX, 33), to: (notchX, 45), color: RenderColor(5, 13, 27, 112))
        }
        let stateLabel: String
        switch boss.lifecycle {
        case .entering: stateLabel = t(game, "APPROACHING", "正在接近")
        case .phaseTransition: stateLabel = t(game, "PHASE SHIFT", "阶段转换")
        case .dying: stateLabel = t(game, "CORE COLLAPSE", "核心崩解")
        case .combat:
            if boss.attackStage == .telegraph {
                stateLabel = t(game, "WARNING", "预警") + " • " + boss.currentAttack.label(for: game.language)
            } else if boss.weakPointOpen {
                stateLabel = t(game, "CORE EXPOSED", "核心暴露")
            } else {
                stateLabel = boss.currentAttack.label(for: game.language)
            }
        }
        let leftTurret = t(game, "L", "左") + " \(Int(boss.leftTurretHealth / max(1, boss.leftTurretMaxHealth) * 100))%"
        let rightTurret = t(game, "R", "右") + " \(Int(boss.rightTurretHealth / max(1, boss.rightTurretMaxHealth) * 100))%"
        styledText(r, leftTurret, x: x + 18, y: 52, role: .caption,
                   color: boss.leftTurretHealth > 0 ? UITheme.Color.secondary : UITheme.Color.muted)
        centeredText(r, ellipsized(stateLabel, maxWidth: 300, scale: UITextRole.caption.scale),
                     centerX: Float(width) * 0.5, y: 52, role: .caption,
                     color: boss.weakPointOpen ? UITheme.Color.energy :
                        (boss.attackStage == .telegraph ? UITheme.Color.danger : UITheme.Color.secondary))
        styledRightText(r, rightTurret, right: x + 598, y: 52, role: .caption,
                        color: boss.rightTurretHealth > 0 ? UITheme.Color.secondary : UITheme.Color.muted)
    }

    private static func hudPanel(_ r: GameRenderer, x: Float, y: Float, width: Float, height: Float,
                                 accent: RenderColor) {
        r.fillRect(RenderRect(x: x, y: y, width: width, height: height), color: RenderColor(9, 25, 43, 228))
        r.line(from: (x, y), to: (x + width - 12, y), color: RenderColor(99, 153, 177, 128))
        r.line(from: (x + width - 12, y), to: (x + width, y + 12), color: RenderColor(99, 153, 177, 128))
        r.line(from: (x, y + height), to: (x + width, y + height), color: RenderColor(46, 87, 113, 160))
        r.fillRect(RenderRect(x: x, y: y + 10, width: 3, height: height - 20), color: accent)
        r.fillRect(RenderRect(x: x + 13, y: y, width: 42, height: 2), color: accent)
    }

    private static func hudSegments(_ r: GameRenderer, x: Float, y: Float, width: Float, height: Float,
                                    segments: Int, value: Double, fill: RenderColor, back: RenderColor,
                                    lag: Double = 0) {
        let gap: Float = 2
        let segmentWidth = (width - Float(segments - 1) * gap) / Float(segments)
        for index in 0..<segments {
            let segmentX = x + Float(index) * (segmentWidth + gap)
            r.fillRect(RenderRect(x: segmentX, y: y, width: segmentWidth, height: height), color: back)
            let lagFraction = Float(min(1, max(0, lag * Double(segments) - Double(index))))
            if lagFraction > 0 {
                r.fillRect(RenderRect(x: segmentX, y: y, width: segmentWidth * lagFraction, height: height),
                           color: UITheme.Color.warning)
            }
            let fraction = Float(min(1, max(0, value * Double(segments) - Double(index))))
            if fraction > 0 {
                r.fillRect(RenderRect(x: segmentX, y: y, width: segmentWidth * fraction, height: height), color: fill)
            }
        }
    }

    private static func hudRing(_ r: GameRenderer, centerX: Float, centerY: Float, radius: Float,
                                value: Double, tint: RenderColor) {
        r.fillCircle(center: (centerX, centerY), radius: radius - 8, color: RenderColor(4, 13, 27, 232))
        let count = 40
        let filled = Int(Double(count) * min(1, max(0, value)))
        for index in 0..<count {
            let start = Float(index) * .pi * 2 / Float(count) - .pi * 0.5
            let end = Float(index + 1) * .pi * 2 / Float(count) - .pi * 0.5 - 0.035
            let segmentTint = index < filled ? tint : RenderColor(53, 91, 112, 190)
            for inset in 0..<3 {
                let ringRadius = radius - Float(inset)
                r.line(from: (centerX + cos(start) * ringRadius, centerY + sin(start) * ringRadius),
                       to: (centerX + cos(end) * ringRadius, centerY + sin(end) * ringRadius),
                       color: segmentTint)
            }
        }
    }

    private static func drawMenu(_ r: GameRenderer, game: Game, width: Int, height: Int) {
        let w = Float(width), h = Float(height)
        let right = w - 350
        let center = (280 + right) * 0.5
        let ship = ShipType(rawValue: game.profile.selectedShip) ?? .thunder
        let accent = UITheme.Color.primary
        let missionIndex = min(MissionCatalog.all.count - 1, max(0, game.selectedMission))
        let mission = MissionCatalog.all[missionIndex]

        // An open hangar stage gives the actual equipped craft visual priority.
        r.fillRect(RenderRect(x: 0, y: 0, width: w, height: h), color: RenderColor(3, 9, 18, 100))
        r.fillRect(RenderRect(x: 0, y: 0, width: 280, height: h), color: RenderColor(6, 14, 24, 230))
        r.fillRect(RenderRect(x: 0, y: 0, width: w, height: 96), color: RenderColor(7, 15, 26, 244))
        r.line(from: (40, 96), to: (w - 40, 96), color: UITheme.Color.border)
        r.line(from: (280, 128), to: (280, h - 66), color: UITheme.Color.border)
        r.fillRect(RenderRect(x: 40, y: 36, width: 4, height: 28), color: accent)
        styledText(r, t(game, "THUNDER / SWIFT", "雷霆战机"), x: 58, y: 32, role: .pageTitle)
        styledText(r, t(game, "FLIGHT COMMAND", "雷霆疾影 · 飞行指挥部"), x: 58, y: 65, role: .caption)
        let resourceStart = w - 518
        let resourceLabels = [t(game, "CREDITS", "金币"), t(game, "CORES", "核心"), t(game, "ALLOY", "合金")]
        let resourceValues = [game.profile.credits, game.profile.cores, game.profile.alloy]
        let resourceTints = [UITheme.Color.action, accent, UITheme.Color.secondary]
        for i in 0..<3 {
            let x = resourceStart + Float(i) * 162
            r.fillRect(RenderRect(x: x, y: 28, width: 146, height: 49), color: UITheme.Color.panelSoft)
            r.fillRect(RenderRect(x: x + 12, y: 42, width: 3, height: 20), color: resourceTints[i])
            styledText(r, resourceLabels[i], x: x + 24, y: 33, role: .caption)
            styledText(r, ellipsized("\(resourceValues[i])", maxWidth: 96, scale: 0.9), x: x + 24, y: 53, role: .body, color: resourceTints[i])
        }

        let save = saveSlotButton(width: Double(width), height: Double(height))
        button(r, save, title: "", selected: false)
        styledText(r, t(game, "PILOT PROFILE", "飞行员档案"), x: 56, y: 142, role: .label)
        styledText(r, t(game, "PILOT", "飞行员") + String(format: " / %02d", SaveManager.shared.activeSlot + 1),
                   x: 56, y: 169, role: .body)
        styledText(r, ">", x: 231, y: 169, role: .body, color: accent)
        styledText(r, t(game, "COMMAND CENTER", "指挥中心"), x: 42, y: 217, role: .caption)
        let buttons = mainMenuButtons(width: Double(width), height: Double(height))
        let navigation: [(Int, String, String)] = [
            (2, t(game, "HANGAR", "机库整备"), t(game, "Aircraft & modules", "战机与装备")),
            (5, t(game, "ARCHIVE", "作战档案"), t(game, "Records & codex", "成就与图鉴")),
            (1, t(game, "FLIGHT GUIDE", "飞行指南"), t(game, "Controls & tactics", "操纵与战术"))
        ]
        for (index, title, subtitle) in navigation {
            let rect = buttons[index]
            button(r, rect, title: "", selected: false)
            menuGlyph(r, kind: index, x: Float(rect.x + 22), y: Float(rect.y + 27), tint: accent)
            styledText(r, ellipsized(title, maxWidth: Float(rect.width - 72), scale: UITextRole.body.scale), x: Float(rect.x + 56), y: Float(rect.y + 12), role: .body)
            styledText(r, ellipsized(subtitle, maxWidth: Float(rect.width - 72), scale: UITextRole.caption.scale), x: Float(rect.x + 56), y: Float(rect.y + 37), role: .caption)
        }
        r.line(from: (42, 526), to: (258, 526), color: UITheme.Color.border)
        button(r, buttons[3], title: t(game, "SETTINGS", "系统设置"), selected: false)
        button(r, buttons[4], title: t(game, "EXIT GAME", "退出游戏"), selected: false)

        styledText(r, "01 / " + t(game, "ACTIVE AIRCRAFT", "当前战机"), x: 316, y: 129, role: .label, color: accent)
        r.drawTextScaled(t(game, "READY TO FLY", "向星海，出击"), at: (316, 166), scale: game.language == .chinese ? 2.15 : 1.8, color: UITheme.Color.text)
        styledText(r, ship.label(for: game.language) + " / " + t(game, "FLIGHT SYSTEM READY", "飞行系统就绪"), x: 316, y: 219, role: .caption)
        // Fine orbital marks anchor the craft without surrounding it in cards.
        menuOrbit(r, center: (center, 430), radiusX: 220, radiusY: 122, tint: RenderColor(84, 159, 187, 37))
        menuOrbit(r, center: (center, 430), radiusX: 184, radiusY: 101, tint: RenderColor(84, 159, 187, 26))
        r.line(from: (center - 238, 430), to: (center - 172, 430), color: UITheme.Color.borderHighlight)
        r.line(from: (center + 172, 430), to: (center + 238, 430), color: UITheme.Color.borderHighlight)
        let floatY = Float(sin(game.uiAnimationTime * 1.35)) * 5
        if let texture = (r as? GameTextureProvider)?.gameTexture(named: shipTextureName(ship)) {
            r.drawSprite(texture, in: RenderRect(x: center - 124, y: 242 + floatY, width: 248, height: 342), alpha: 255)
        }
        styledText(r, "[ " + ship.label(for: game.language) + " ]", x: 316, y: 550, role: .sectionTitle, color: accent)
        styledText(r, ship.subtitle(for: game.language), x: 316, y: 580, role: .caption)
        let statY = h - 104
        let statWidth = (right - 330) / 3
        let stats = [(t(game, "POWER", "当前战力"), "\(game.combatPower())", UITheme.Color.action),
                     (t(game, "BEST SCORE", "最高得分"), "\(game.profile.bestScore)", UITheme.Color.text),
                     (t(game, "SORTIES", "累计出击"), "\(game.profile.totalRuns)", UITheme.Color.text)]
        for (i, stat) in stats.enumerated() {
            let x = 316 + Float(i) * statWidth
            r.line(from: (x, statY), to: (x + statWidth - 20, statY), color: UITheme.Color.border)
            styledText(r, stat.0, x: x, y: statY + 10, role: .caption)
            styledText(r, ellipsized(stat.1, maxWidth: statWidth - 25, scale: 1.12), x: x, y: statY + 31, role: .number, color: stat.2)
        }

        panel(r, x: Int(right), y: 128, width: 302, height: 390)
        styledText(r, t(game, "NEXT OPERATION", "下一次行动"), x: right + 22, y: 149, role: .label, color: accent)
        styledRightText(r, String(format: "%02d / 08", mission.id), right: w - 70, y: 149, role: .caption)
        r.line(from: (right + 22, 182), to: (w - 70, 182), color: UITheme.Color.border)
        styledText(r, t(game, "CAMPAIGN SECTOR", "战役区域"), x: right + 22, y: 204, role: .caption)
        styledText(r, ellipsized(mission.title(for: game.language), maxWidth: 258, scale: UITextRole.pageTitle.scale), x: right + 22, y: 238, role: .pageTitle)
        drawWrappedText(r, mission.description(for: game.language), x: right + 22, y: 280, color: UITheme.Color.secondary, maxWidth: 252, lineHeight: 25, maxLines: 3, scale: 0.85)
        styledText(r, t(game, "RECOMMENDED", "推荐战力"), x: right + 22, y: 370, role: .label)
        styledRightText(r, "\(mission.powerGate)", right: w - 70, y: 369, role: .number, color: UITheme.Color.action)
        r.line(from: (right + 22, 408), to: (w - 70, 408), color: UITheme.Color.border)
        styledText(r, t(game, "SECTORS UNLOCKED", "已解锁区域"), x: right + 22, y: 430, role: .caption)
        styledRightText(r, "\(game.unlockedMissionCount) / \(MissionCatalog.all.count)", right: w - 70, y: 430, role: .caption, color: accent)
        for i in 0..<MissionCatalog.all.count {
            r.fillRect(RenderRect(x: right + 22 + Float(i) * 33, y: 465, width: 26, height: 5), color: i < game.unlockedMissionCount ? accent : UITheme.Color.panelRaised)
        }
        button(r, buttons[0], title: "", selected: false, emphasis: true)
        styledText(r, t(game, "START SORTIE", "开始出击"), x: right + 24, y: h - 150, role: .pageTitle, color: UITheme.Color.ink)
        styledRightText(r, ">", right: w - 74, y: h - 150, role: .pageTitle, color: UITheme.Color.ink)
        centeredText(r, t(game, "ENTER  /  SELECT SECTOR", "ENTER  /  选择作战区域"), centerX: right + 151, y: h - 85, role: .caption)
        r.line(from: (40, h - 40), to: (w - 40, h - 40), color: UITheme.Color.border)
        styledText(r, t(game, "AUTO-SAVE ENABLED", "进度自动保存"), x: 42, y: h - 27, role: .caption)
        styledRightText(r, t(game, "WASD  MOVE    SHIFT  PRECISION    SPACE  OVERLOAD", "WASD  移动    SHIFT  精准飞行    SPACE  雷霆超载"), right: w - 42, y: h - 27, role: .caption)
    }

    private static func menuOrbit(_ r: GameRenderer, center: (Float, Float), radiusX: Float, radiusY: Float, tint: RenderColor) {
        for i in 0..<72 {
            let a = Float(i) * .pi * 2 / 72, b = Float(i + 1) * .pi * 2 / 72
            r.line(from: (center.0 + cos(a) * radiusX, center.1 + sin(a) * radiusY),
                   to: (center.0 + cos(b) * radiusX, center.1 + sin(b) * radiusY), color: tint)
        }
    }

    private static func menuGlyph(_ r: GameRenderer, kind: Int, x: Float, y: Float, tint: RenderColor) {
        if kind == 2 {
            r.line(from: (x - 9, y + 6), to: (x, y - 9), color: tint)
            r.line(from: (x, y - 9), to: (x + 9, y + 6), color: tint)
            r.line(from: (x - 9, y + 6), to: (x + 9, y + 6), color: tint)
            r.line(from: (x, y - 2), to: (x, y + 10), color: tint)
        } else if kind == 5 {
            for i in 0..<3 {
                r.line(from: (x - 8, y - 7 + Float(i) * 7), to: (x + 9, y - 7 + Float(i) * 7), color: tint)
            }
        } else {
            menuOrbit(r, center: (x, y), radiusX: 10, radiusY: 10, tint: tint)
            r.line(from: (x - 14, y), to: (x + 14, y), color: tint)
            r.line(from: (x, y - 14), to: (x, y + 14), color: tint)
        }
    }

    private static func drawSaveSlots(_ r: GameRenderer, game: Game, width: Int, height: Int) {
        panel(r, x: width / 2 - 455, y: 58, width: 910, height: height - 105)
        centeredText(r, t(game, "SAVE SELECT // PILOT DATA", "选择存档 // 飞行员数据"), centerX: Float(width / 2), y: 90, role: .pageTitle, shadow: true)
        centeredText(r, t(game, "Choose your pilot profile to continue.", "选择飞行员档案，继续你的旅程。"), centerX: Float(width / 2), y: 122, role: .secondary)
        let summaries = SaveManager.shared.slotSummaries()
        for (i, card) in saveSlotCards(width: Double(width), height: Double(height)).enumerated() {
            button(r, card, title: "", selected: i == SaveManager.shared.activeSlot)
            text(r, t(game, "SLOT", "存档") + " \(i + 1)", Float(card.x + 14), Float(card.y + 7), UITheme.Color.text)
            guard summaries.indices.contains(i) else { continue }
            let summary = summaries[i]
            if let profile = summary.profile {
                let active = i == SaveManager.shared.activeSlot
                text(r, active ? t(game, "ACTIVE", "当前使用") : t(game, "READY", "可用"), Float(card.x + 14), Float(card.y + 30), active ? UITheme.Color.success : UITheme.Color.secondary)
                text(r, t(game, "SECTOR", "区域") + " \(profile.unlockedMission)", Float(card.x + 14), Float(card.y + 48), UITheme.Color.text)
                text(r, t(game, "POWER", "战力") + "  \(profile.equipment.reduce(0) { $0 + $1.unitPower })", Float(card.x + 14), Float(card.y + 72), UITheme.Color.warning)
                text(r, t(game, "RUNS", "出击") + "  \(profile.totalRuns)", Float(card.x + 14), Float(card.y + 96), UITheme.Color.secondary)
                text(r, t(game, "BEST", "最高分") + "  \(profile.bestScore)", Float(card.x + 14), Float(card.y + 120), UITheme.Color.secondary)
            } else {
                text(r, t(game, "EMPTY SLOT", "空存档"), Float(card.x + 14), Float(card.y + 54), UITheme.Color.muted)
                drawWrappedText(r, t(game, "Create a new pilot profile", "创建新的飞行员档案"), x: Float(card.x + 14), y: Float(card.y + 82), color: UITheme.Color.secondary, maxWidth: Float(card.width - 28), lineHeight: 24, maxLines: 3)
            }
        }
        centeredText(r, t(game, "PROGRESS SAVED AUTOMATICALLY", "游戏进度自动保存"), centerX: Float(width / 2), y: Float(height - 128), role: .caption, color: UITheme.Color.success)
        button(r, saveSlotsBackButton(width: Double(width), height: Double(height)), title: t(game, "BACK", "返回"), selected: false)
    }

    private static func drawMissionSelect(_ r: GameRenderer, game: Game, width: Int, height: Int) {
        r.fillRect(RenderRect(x: 0, y: 0, width: Float(width), height: Float(height)), color: RenderColor(4, 11, 21, 178))
        let right = Float(width - 350)
        styledText(r, "02 / " + t(game, "MISSION CONTROL", "作战指挥"), x: 40, y: 40, role: .label, color: UITheme.Color.primary)
        r.drawTextScaled(t(game, "CHOOSE YOUR SECTOR", "选择你的战场"), at: (40, 79), scale: 1.8, color: UITheme.Color.text)
        styledText(r, t(game, "SECTORS", "作战区域"), x: 40, y: 156, role: .label)
        styledRightText(r, t(game, "UNLOCKED", "已解锁") + "  \(game.unlockedMissionCount) / 8", right: right - 32, y: 156, role: .caption)
        for (i, card) in missionCards(width: Double(width), height: Double(height)).enumerated() {
            let mission = MissionCatalog.all[i]
            let unlocked = i < game.unlockedMissionCount
            let selected = i == game.selectedMission
            button(r, card, title: "", selected: selected, enabled: unlocked)
            styledText(r, String(format: "%02d", i + 1), x: Float(card.x + 16), y: Float(card.y + 14), role: .number, color: unlocked ? UITheme.Color.primary : UITheme.Color.muted)
            styledRightText(r, selected ? t(game, "SELECTED", "已选择") : (unlocked ? t(game, "READY", "可出击") : t(game, "LOCKED", "未解锁")), right: Float(card.x + card.width - 14), y: Float(card.y + 18), role: .caption, color: selected ? UITheme.Color.primary : UITheme.Color.muted)
            styledText(r, ellipsized(mission.title(for: game.language), maxWidth: Float(card.width - 30), scale: UITextRole.body.scale), x: Float(card.x + 15), y: Float(card.y + 55), role: .body, color: unlocked ? UITheme.Color.text : UITheme.Color.muted)
            styledText(r, t(game, "GATE", "门槛") + " \(mission.powerGate)  " + t(game, "POWER", "战力"), x: Float(card.x + 15), y: Float(card.y + 90), role: .caption, color: unlocked ? UITheme.Color.secondary : UITheme.Color.muted)
        }
        styledText(r, t(game, "FLIGHT MODE", "飞行模式"), x: 40, y: 465, role: .label)
        for (i, card) in modeCards(width: Double(width), height: Double(height)).enumerated() {
            let mode = GameMode.allCases[i]
            button(r, card, title: "", selected: mode == game.gameMode)
            styledText(r, mode.label(for: game.language), x: Float(card.x + 18), y: Float(card.y + 17), role: .sectionTitle, color: mode == game.gameMode ? UITheme.Color.primary : UITheme.Color.text)
            drawWrappedText(r, mode.description(for: game.language), x: Float(card.x + 18), y: Float(card.y + 52), color: UITheme.Color.secondary, maxWidth: Float(card.width - 36), lineHeight: 22, maxLines: 2)
        }
        if MissionCatalog.all.indices.contains(game.selectedMission) {
            let mission = MissionCatalog.all[game.selectedMission]
            // 战力门槛（规格第 7.4 节）：闯关按章、无尽按波次；不足门槛时伤害按比例折算。
            let gate = game.activePowerGate()
            let scale = game.powerGateScale(gate: gate)
            let scalePercent = Int((scale * 100).rounded())
            panel(r, x: Int(right), y: 128, width: 302, height: 390)
            styledText(r, t(game, "MISSION BRIEF", "任务简报"), x: right + 22, y: 150, role: .label, color: UITheme.Color.primary)
            r.line(from: (right + 22, 184), to: (right + 280, 184), color: UITheme.Color.border)
            styledText(r, mission.title(for: game.language), x: right + 22, y: 207, role: .sectionTitle)
            drawWrappedText(r, mission.description(for: game.language), x: right + 22, y: 253, color: UITheme.Color.secondary, maxWidth: 252, lineHeight: 24, maxLines: 3, scale: 0.85)
            let rows = [(t(game, "YOUR POWER", "当前战力"), "\(game.combatPower())", UITheme.Color.primary),
                        (t(game, "POWER GATE", "战力门槛"), "\(gate)", UITheme.Color.action),
                        (t(game, "DAMAGE SCALE", "伤害折算"), "\(scalePercent)%", scale >= 1 ? UITheme.Color.success : UITheme.Color.danger),
                        (t(game, "REWARDS", "奖励倍率"), String(format: "x%.2f", mission.rewardMultiplier), UITheme.Color.primary)]
            for (i, row) in rows.enumerated() {
                let y: Float = 338 + Float(i) * 42
                styledText(r, row.0, x: right + 22, y: y, role: .label)
                styledRightText(r, row.1, right: right + 280, y: y - 2, role: .body, color: row.2)
            }
            if scale < 1 {
                styledText(r, ellipsized(t(game, "Below gate: enemy damage is scaled down", "未达门槛：对敌伤害将按比例衰减"),
                                         maxWidth: 258, scale: UITextRole.caption.scale),
                           x: right + 22, y: 512, role: .caption, color: UITheme.Color.danger)
            }
        }
        button(r, missionLaunchButton(width: Double(width), height: Double(height)), title: t(game, "LAUNCH MISSION  >", "确认出击  >"), selected: false, emphasis: true)
        centeredText(r, t(game, "ENTER  /  LAUNCH", "ENTER  /  确认出击"), centerX: right + 151, y: Float(height - 85), role: .caption)
        button(r, missionBackButton(width: Double(width), height: Double(height)), title: t(game, "<  BACK", "<  返回指挥中心"), selected: false)
    }

    private static func drawControls(_ r: GameRenderer, game: Game, width: Int, height: Int) {
        panel(r, x: width / 2 - 320, y: 70, width: 640, height: height - 125)
        sectionHeader(r, title: t(game, "HOW TO PLAY", "操作说明"), subtitle: t(game, "KEYBOARD FLIGHT", "键盘操纵"),
                      x: width / 2 - 280, y: 112, width: 560)
        centeredText(r, t(game, "The fighter is controlled by keyboard. Mouse input is reserved for menus.", "战机仅使用键盘操纵，鼠标只用于菜单选择。"),
                     centerX: Float(width / 2), y: 154, role: .secondary)

        drawStatTile(r, x: width / 2 - 260, y: 198, width: 245, height: 84,
                     label: t(game, "MOVE", "移动"), value: t(game, "WASD / ARROWS", "WASD / 方向键"), tint: UITheme.Color.primary)
        drawStatTile(r, x: width / 2 + 15, y: 198, width: 245, height: 84,
                     label: t(game, "PRECISION MODE", "精准模式"), value: "SHIFT", tint: UITheme.Color.energy)
        drawStatTile(r, x: width / 2 - 260, y: 300, width: 245, height: 84,
                     label: t(game, "THUNDER OVERLOAD", "雷霆超载"), value: "SPACE", tint: UITheme.Color.warning)
        drawStatTile(r, x: width / 2 + 15, y: 300, width: 245, height: 84,
                     label: t(game, "EMERGENCY DASH", "紧急闪避"), value: "F", tint: UITheme.Color.success)
        drawStatTile(r, x: width / 2 - 260, y: 402, width: 245, height: 84,
                     label: t(game, "BALLISTICS", "弹道签名"), value: t(game, "BY EQUIPMENT", "由出战装备决定"), tint: UITheme.Color.primary)
        drawStatTile(r, x: width / 2 + 15, y: 402, width: 245, height: 84,
                     label: t(game, "PAUSE / BACK", "暂停 / 返回"), value: "ESC", tint: UITheme.Color.secondary)
        centeredText(r, t(game, "Hold Shift to slow down and reveal the real hitbox.", "按住 Shift 可降低移动速度，并显示战机的真实碰撞核心。"),
                     centerX: Float(width / 2), y: 514, role: .secondary)
        button(r, controlsBackButton(width: Double(width), height: Double(height)), title: t(game, "BACK", "返回"), selected: false)
    }

    private static func drawSettings(_ r: GameRenderer, game: Game, width: Int, height: Int) {
        panel(r, x: width / 2 - 320, y: 44, width: 640, height: height - 78)
        centeredText(r, t(game, "SETTINGS", "设置"), centerX: Float(width / 2), y: 70, role: .pageTitle, shadow: true)
        centeredText(r, t(game, "Presentation and accessibility", "调整画面、声音与辅助功能"), centerX: Float(width / 2), y: 102, role: .secondary)
        text(r, t(game, "LANGUAGE", "语言"), Float(width / 2 - 230), 140, UITheme.Color.secondary)
        let language = settingsLanguageButtons(width: Double(width), height: Double(height))
        button(r, language[0], title: t(game, "ENGLISH", "英文"), selected: game.language == .english)
        button(r, language[1], title: t(game, "CHINESE", "中文"), selected: game.language == .chinese)
        text(r, t(game, "AUDIO", "音频"), Float(width / 2 - 230), 226, UITheme.Color.secondary)
        button(r, settingsBGMButton(width: Double(width), height: Double(height)),
               title: t(game, "BGM", "音乐") + " \(game.profile.bgmVolume)%", selected: false)
        button(r, settingsSFXButton(width: Double(width), height: Double(height)),
               title: t(game, "SFX", "音效") + " \(game.profile.sfxVolume)%", selected: false)
        text(r, t(game, "ACCESSIBILITY", "辅助选项"), Float(width / 2 - 230), 302, UITheme.Color.secondary)
        let shakeNames = [t(game, "OFF", "关闭"), t(game, "LOW", "低"), t(game, "MEDIUM", "中"), t(game, "HIGH", "高")]
        let shakeValue = shakeNames[min(max(0, game.profile.cameraShake), shakeNames.count - 1)]
        button(r, settingsShakeButton(width: Double(width), height: Double(height)), title: t(game, "CAMERA SHAKE", "镜头震动") + ": " + shakeValue, selected: false)
        text(r, t(game, "DISPLAY", "显示"), Float(width / 2 - 230), 374, UITheme.Color.secondary)
        button(r, settingsWindowModeButton(width: Double(width), height: Double(height)), title: game.profile.isFullscreen ? t(game, "DISPLAY: FULLSCREEN", "显示：全屏") : t(game, "DISPLAY: WINDOWED", "显示：窗口化"), selected: false)
        button(r, settingsResolutionButton(width: Double(width), height: Double(height)), title: t(game, "RESOLUTION", "分辨率") + ": \(game.profile.resolutionWidth)x\(game.profile.resolutionHeight)", selected: false)
        button(r, settingsUIScaleButton(width: Double(width), height: Double(height)), title: t(game, "UI SCALE", "界面缩放") + ": \(game.profile.uiScale)%", selected: false)
        centeredText(r, t(game, "CHANGES ARE SAVED AUTOMATICALLY", "设置立即生效，并自动保存"), centerX: Float(width / 2), y: 584, role: .caption)
        button(r, settingsBackButton(width: Double(width), height: Double(height)), title: t(game, "BACK", "返回"), selected: false)
    }

    private static func drawHangar(_ r: GameRenderer, game: Game, width: Int, height: Int) {
        let displayedShip = ShipType(rawValue: game.profile.selectedShip) ?? .thunder
        var hoveredModule: EquipmentState?
        panel(r, x: 32, y: 32, width: width - 64, height: height - 64)
        styledText(r, t(game, "HANGAR / LOADOUT", "机库 / 装备"), x: 64, y: 58, role: .pageTitle, shadow: true)
        styledText(r, t(game, "AIRFRAME CONFIGURATION", "战机与装备配置"), x: 66, y: 92, role: .secondary)
        // 页头右侧：战力大数字 + 资源，形成"标题左、数值右"的对称锚点。
        styledRightText(r, t(game, "COMBAT POWER", "战力"), right: Float(width - 66), y: 56, role: .caption, color: UITheme.Color.muted)
        styledRightText(r, "\(game.combatPower())", right: Float(width - 66), y: 72, role: .number, color: UITheme.Color.warning)
        let resourceSummary = t(game, "CREDITS", "金币") + " \(game.profile.credits)   " + t(game, "CORES", "核心") + " \(game.profile.cores)"
        styledRightText(r, ellipsized(resourceSummary, maxWidth: 380, scale: UITextRole.caption.scale), right: Float(width - 66), y: 104, role: .caption, color: UITheme.Color.secondary)
        r.line(from: (64, 118), to: (Float(width - 64), 118), color: UITheme.Color.border)

        // 左栏：机体预览 + 2x2 机体选择（收进左栏，避免与内容区重叠）。
        if let shipTexture = (r as? GameTextureProvider)?.gameTexture(named: shipTextureName(displayedShip)) {
            let previewWidth: Float
            switch displayedShip {
            case .ghost: previewWidth = 150
            case .heavy: previewWidth = 184
            case .carrier: previewWidth = 190
            default: previewWidth = 172
            }
            r.drawSprite(shipTexture, in: RenderRect(x: 172 - previewWidth * 0.5, y: 140,
                                                     width: previewWidth, height: 246), alpha: 255)
        } else {
            drawShip(r, center: (x: 172, y: 270), scale: 2.0, accent: UITheme.Color.primary)
        }
        centeredText(r, displayedShip.label(for: game.language), centerX: 172, y: 402,
                     role: .sectionTitle, color: UITheme.Color.text)
        centeredText(r, ellipsized(displayedShip.subtitle(for: game.language), maxWidth: 260, scale: UITextRole.caption.scale), centerX: 172, y: 430,
                     role: .caption, color: UITheme.Color.secondary)
        styledText(r, t(game, "SELECT AIRFRAME", "选择机体"), x: 64, y: 462, role: .caption)
        // 机体列表：内容整体按滚动量平移，绘制裁剪到视口内，因此可连续平滑滚动。
        let shipArea = shipListArea(width: Double(width), height: Double(height))
        r.setClipRect(RenderRect(x: Float(shipArea.x), y: Float(shipArea.y),
                                 width: Float(shipArea.width), height: Float(shipArea.height)))
        for (i, card) in shipCards(width: Double(width), height: Double(height)).enumerated() {
            let visible = UIRect(x: card.x, y: card.y - game.shipListScroll, width: card.width, height: card.height)
            let ship = ShipType(rawValue: i) ?? .thunder
            button(r, visible, title: ship.label(for: game.language), selected: ship == displayedShip)
        }
        r.setClipRect(nil)
        if shipListMaxScroll(width: Double(width), height: Double(height)) > 0 {
            let track = shipScrollTrack(width: Double(width), height: Double(height))
            r.fillRect(RenderRect(x: Float(track.x), y: Float(track.y), width: Float(track.width), height: Float(track.height)),
                       color: RenderColor(12, 23, 40, 210))
            let knob = shipScrollKnob(width: Double(width), height: Double(height), scroll: game.shipListScroll)
            let active = UIInteraction.primaryHeld || knob.contains(UIInteraction.pointer)
            r.fillRect(RenderRect(x: Float(knob.x), y: Float(knob.y), width: Float(knob.width), height: Float(knob.height)),
                       color: active ? UITheme.Color.primary : UITheme.Color.primaryDeep)
        }

        // Tab 栏：左对齐内容区 + 选中下划线指示条。
        let tabTitles = [t(game, "EQUIPMENT", "装备"), t(game, "WARRIOR", "战神")]
        for (i, tab) in hangarTabButtons(width: Double(width), height: Double(height)).enumerated() {
            button(r, tab, title: tabTitles[min(i, tabTitles.count - 1)], selected: i == game.hangarTab)
            if i == game.hangarTab {
                r.fillRect(RenderRect(x: Float(tab.x), y: Float(tab.y + tab.height), width: Float(tab.width), height: 3),
                           color: UITheme.Color.primary)
            }
        }
        switch game.hangarTab {
        case 1:
            drawWarriorTab(r, game: game, width: width, height: height)
        default:
            if let hovered = drawEquipmentTab(r, game: game, width: width, height: height) { hoveredModule = hovered }
        }
        button(r, hangarBackButton(width: Double(width), height: Double(height)), title: t(game, "BACK", "返回"), selected: false)
        // 提示气泡固定在中栏底部，与左右两栏内容互不遮挡。
        if game.hangarMessageTimer > 0 {
            let alpha = notificationAlpha(game.hangarMessageTimer, fullDuration: 2.4)
            let titleColor = RenderColor(UITheme.Color.success.red, UITheme.Color.success.green, UITheme.Color.success.blue, alpha)
            let detailColor = RenderColor(UITheme.Color.secondary.red, UITheme.Color.secondary.green, UITheme.Color.secondary.blue, alpha)
            r.fillRect(RenderRect(x: 350, y: 606, width: 560, height: 54), color: RenderColor(8, 18, 34, UInt8(Double(alpha) * 0.88)))
            r.fillRect(RenderRect(x: 350, y: 606, width: 3, height: 54), color: titleColor)
            hangarText(r, game.hangarMessageTitle, x: 364, y: 614, width: 532, role: .body, color: titleColor)
            hangarText(r, game.hangarMessageDetail, x: 364, y: 638, width: 532, role: .caption, color: detailColor)
        }
        if let hoveredModule { drawTooltip(r, game: game, item: hoveredModule, width: width, height: height) }
    }

    private static func hangarText(_ r: GameRenderer, _ value: String, x: Float, y: Float, width: Float,
                                   role: UITextRole, color: RenderColor? = nil) {
        styledText(r, ellipsized(value, maxWidth: width, scale: role.scale), x: x, y: y, role: role, color: color)
    }

    private static func hangarDetail(_ r: GameRenderer, _ value: String, x: Float, y: Float, width: Float) {
        let role = UITextRole.caption
        for (index, line) in wrappedLines(value, maxWidth: width / role.scale, maxLines: 2).enumerated() {
            styledText(r, line, x: x, y: y + Float(index) * 22, role: role, color: UITheme.Color.secondary)
        }
    }

    /// 装备悬浮提示（v7：阶标签 / 等级 / 战力 / 特性）。
    private static func drawTooltip(_ r: GameRenderer, game: Game, item: EquipmentState, width: Int, height: Int) {
        let tooltipWidth = 320, tooltipHeight = 168
        let x = Int(min(max(12, UIInteraction.pointer.x + 20), Double(width - tooltipWidth - 12)))
        let y = Int(min(max(60, UIInteraction.pointer.y + 20), Double(height - tooltipHeight - 12)))
        panel(r, x: x, y: y, width: tooltipWidth, height: tooltipHeight)
        let left = Float(x + 16), top = Float(y), contentWidth = Float(tooltipWidth - 32)
        let right = Float(x + tooltipWidth - 16)
        hangarText(r, game.equipmentDisplayName(item), x: left, y: top + 14, width: contentWidth, role: .body)
        hangarText(r, game.equipmentStageLabel(item.stage) + "  •  " + t(game, "TIER", "档位") + " \(item.tier)",
                   x: left, y: top + 42, width: 180, role: .caption, color: color(equipmentStageColor(item.stage)))
        styledRightText(r, "Lv.\(item.level)/\(item.levelCap)", right: right, y: top + 41, role: .caption, color: UITheme.Color.secondary)
        hangarDetail(r, game.equipmentBonusText(item), x: left, y: top + 70, width: contentWidth)
        styledText(r, t(game, "POWER", "战力"), x: left, y: top + 126, role: .caption, color: UITheme.Color.muted)
        styledRightText(r, "\(item.unitPower)", right: right, y: top + 124, role: .body, color: UITheme.Color.action)
    }

    /// Tab 0 装备：2x2 槽位卡（等级进度条 + 状态徽章）+ 详情 + 强化 / 全灌 / 进阶 / 锁定
    /// + 经验素材格（规格第 4/5 节）。点击槽位卡进入换装子视图。
    private static func drawEquipmentTab(_ r: GameRenderer, game: Game, width: Int, height: Int) -> EquipmentState? {
        if game.hangarVaultSlot != nil {
            return drawVaultForSlot(r, game: game, width: width, height: height)
        }
        var hoveredModule: EquipmentState?
        for (index, card) in hangarCards(width: Double(width), height: Double(height)).enumerated() {
            guard game.profile.equipment.indices.contains(index) else { continue }
            let item = game.profile.equipment[index]
            button(r, card, title: "", selected: index == game.selectedEquipmentSlot)
            r.fillRect(RenderRect(x: Float(card.x), y: Float(card.y), width: Float(card.width), height: 3),
                       color: color(equipmentStageColor(item.stage)))
            if card.contains(UIInteraction.pointer) { hoveredModule = item }
            let left = Float(card.x + 16)
            let right = Float(card.x + card.width - 16)
            // 首行：槽位名居左，战神 / 锁定状态徽章居右。
            hangarText(r, equipmentSlotName(game, item.slot), x: left, y: Float(card.y + 12),
                       width: 150, role: .caption, color: UITheme.Color.primary)
            if let warrior = game.deployedWarrior(for: item.slot) {
                let name = game.language == .chinese ? warrior.displayName : (warrior.recipe?.nameEn ?? warrior.displayName)
                hangarText(r, t(game, "WARRIOR: ", "战神：") + ellipsized(name, maxWidth: 130, scale: UITextRole.caption.scale),
                           x: right - 150, y: Float(card.y + 12), width: 150, role: .caption, color: UITheme.Color.warning)
            } else if item.locked {
                hangarText(r, t(game, "LOCKED", "已锁定"), x: right - 150, y: Float(card.y + 12), width: 150,
                           role: .caption, color: UITheme.Color.action)
            }
            hangarText(r, ellipsized(game.equipmentDisplayName(item), maxWidth: Float(card.width - 32), scale: UITextRole.body.scale),
                       x: left, y: Float(card.y + 36), width: Float(card.width - 32), role: .body, color: UITheme.Color.text)
            hangarText(r, game.equipmentStageLabel(item.stage), x: left, y: Float(card.y + 66),
                       width: 160, role: .caption, color: color(equipmentStageColor(item.stage)))
            styledRightText(r, "Lv.\(item.level)/\(item.levelCap)", right: right,
                            y: Float(card.y + 65), role: .caption, color: UITheme.Color.secondary)
            styledText(r, t(game, "POWER", "战力"), x: left, y: Float(card.y + 90), role: .caption, color: UITheme.Color.muted)
            styledRightText(r, "\(item.unitPower)", right: right, y: Float(card.y + 88),
                            role: .body, color: UITheme.Color.action)
            // 等级进度条：直观展示当前等级在阶链封顶中的位置。
            progress(r, UIProgressBar(rect: UIRect(x: Double(left), y: Double(card.y + 116), width: Double(card.width - 32), height: 5),
                                      value: Double(item.level) / Double(max(1, item.levelCap)),
                                      fill: UITheme.Color.primary, back: RenderColor(24, 53, 68)), height: 5)
        }
        // 经验素材格（规格第 5 节：下方小格选经验素材）。
        styledText(r, t(game, "EXP MATERIAL", "经验素材"), x: 350, y: 496, role: .caption, color: UITheme.Color.primary)
        styledText(r, t(game, "TIP: CLICK A SLOT TO SWAP GEAR", "提示：点击槽位卡可从仓库更换装备"),
                   x: 700, y: 496, role: .caption, color: UITheme.Color.muted)
        for (index, cell) in hangarExpCells(width: Double(width), height: Double(height)).enumerated() {
            let sources = EquipmentCatalog.shared.experienceSources
            guard index < sources.count else { continue }
            let source = sources[index]
            let selected = source.id == game.selectedExpMaterial
            button(r, cell, title: "", selected: selected)
            let left = Float(cell.x + 12)
            hangarText(r, ellipsized(game.materialDisplayName(source.id), maxWidth: 132, scale: UITextRole.caption.scale),
                       x: left, y: Float(cell.y + 8), width: 132, role: .caption, color: UITheme.Color.text)
            hangarText(r, t(game, "+\(source.exp) EXP", "+\(source.exp) 经验"), x: left, y: Float(cell.y + 30),
                       width: 100, role: .caption, color: UITheme.Color.energy)
            styledRightText(r, "x\(game.materialCount(source.id))", right: Float(cell.x + cell.width - 12),
                            y: Float(cell.y + 30), role: .caption, color: game.materialCount(source.id) > 0 ? UITheme.Color.success : UITheme.Color.danger)
        }
        // 详情 + 操作按钮。
        if game.profile.equipment.indices.contains(game.selectedEquipmentSlot) {
            let item = game.profile.equipment[game.selectedEquipmentSlot]
            drawEquipmentInspector(r, game: game, item: item, x: width - 275, y: 132, width: 210, height: 300)
        }
        button(r, hangarUpgradeButton(width: Double(width), height: Double(height)),
               title: t(game, "LEVEL UP", "强化"), selected: false, emphasis: true)
        button(r, hangarBatchUpgradeButton(width: Double(width), height: Double(height)),
               title: t(game, "AUTO", "全灌"), selected: false)
        button(r, hangarAdvanceButton(width: Double(width), height: Double(height)),
               title: t(game, "ADVANCE", "进阶"), selected: false)
        button(r, hangarLockButton(width: Double(width), height: Double(height)),
               title: game.profile.equipment.indices.contains(game.selectedEquipmentSlot) && game.profile.equipment[game.selectedEquipmentSlot].locked
                   ? t(game, "UNLOCK", "解锁")
                   : t(game, "LOCK", "锁定"), selected: false)
        return hoveredModule
    }

    /// 换装子视图：点击装备槽位卡后进入，展示该槽位的仓库备用件（返回 / 翻页
    /// + 备用装备网格 + 详情 + 装备 / 锁定）。列表固定按战力降序。
    private static func drawVaultForSlot(_ r: GameRenderer, game: Game, width: Int, height: Int) -> EquipmentState? {
        var hoveredModule: EquipmentState?
        // 工具行：返回槽位居左，子视图标题居中，翻页器居右。
        button(r, vaultBackToSlotsButton(width: Double(width), height: Double(height)), title: t(game, "BACK", "返回"), selected: false)
        if let slot = game.hangarVaultSlot {
            let title = equipmentSlotName(game, slot) + "  •  " + t(game, "SELECT REPLACEMENT", "选择替换装备")
            hangarText(r, title, x: 486, y: 198, width: 340, role: .body, color: UITheme.Color.primary)
        }
        button(r, vaultPrevButton(width: Double(width), height: Double(height)), title: "<", selected: false)
        button(r, vaultNextButton(width: Double(width), height: Double(height)), title: ">", selected: false)
        // 页码计数绘制在翻页箭头正上方，避免与 < > 按钮重叠。
        centeredText(r, "\(min(game.vaultPage + 1, game.vaultPageCount))/\(game.vaultPageCount)",
                     centerX: Float(vaultPageLabelCenterX(width: Double(width), height: Double(height))),
                     y: 168, role: .caption, color: UITheme.Color.muted)
        let visible = game.visibleVaultIndices
        let occupied = Set(game.profile.warriors.flatMap { $0.materialUIDs })
        for (cardIndex, card) in vaultCards(width: Double(width), height: Double(height)).enumerated() {
            let absoluteIndex = game.vaultPage * 4 + cardIndex
            guard visible.indices.contains(absoluteIndex) else { continue }
            let inventoryIndex = visible[absoluteIndex]
            let item = game.profile.inventory[inventoryIndex]
            let selected = game.selectedVaultInventoryIndex == inventoryIndex
            button(r, card, title: "", selected: selected)
            r.fillRect(RenderRect(x: Float(card.x), y: Float(card.y), width: Float(card.width), height: 3),
                       color: color(equipmentStageColor(item.stage)))
            if card.contains(UIInteraction.pointer) { hoveredModule = item }
            let left = Float(card.x + 16)
            let right = Float(card.x + card.width - 16)
            hangarText(r, equipmentSlotName(game, item.slot), x: left, y: Float(card.y + 12),
                       width: 150, role: .caption, color: UITheme.Color.primary)
            // 状态徽章居右：锁定 / 战神素材占用。
            var marks: [String] = []
            if item.locked { marks.append(t(game, "LOCKED", "已锁定")) }
            if occupied.contains(item.uid) { marks.append(t(game, "WARRIOR MATERIAL", "战神素材")) }
            if !marks.isEmpty {
                hangarText(r, marks.joined(separator: " • "), x: right - 150, y: Float(card.y + 12), width: 150,
                           role: .caption, color: item.locked ? UITheme.Color.action : UITheme.Color.warning)
            }
            hangarText(r, ellipsized(game.equipmentDisplayName(item), maxWidth: Float(card.width - 32), scale: UITextRole.body.scale),
                       x: left, y: Float(card.y + 36), width: Float(card.width - 32), role: .body, color: UITheme.Color.text)
            hangarText(r, game.equipmentStageLabel(item.stage) + "  •  " + t(game, "TIER", "档位") + " \(item.tier)",
                       x: left, y: Float(card.y + 66), width: 200, role: .caption, color: color(equipmentStageColor(item.stage)))
            styledRightText(r, "Lv.\(item.level)", right: right, y: Float(card.y + 65),
                            role: .caption, color: UITheme.Color.secondary)
            styledText(r, t(game, "POWER", "战力"), x: left, y: Float(card.y + 90), role: .caption, color: UITheme.Color.muted)
            styledRightText(r, "\(item.unitPower)", right: right, y: Float(card.y + 88),
                            role: .body, color: UITheme.Color.action)
        }
        if visible.isEmpty {
            centeredText(r, t(game, "NO SPARE MODULES FOR THIS SLOT", "该槽位暂无备用装备"),
                         centerX: 670, y: 320, role: .body, color: UITheme.Color.muted)
            centeredText(r, t(game, "Rare module caches drop from boss waves", "首领波次会掉落稀有模块"),
                         centerX: 670, y: 346, role: .caption, color: UITheme.Color.muted)
        }
        // 详情 + 操作按钮。
        if let selected = game.selectedVaultInventoryIndex, profileInventory(game, contains: selected) {
            drawEquipmentInspector(r, game: game, item: game.profile.inventory[selected],
                                   x: width - 275, y: 132, width: 210, height: 300)
        } else {
            panel(r, x: width - 275, y: 132, width: 210, height: 300)
            hangarText(r, t(game, "SELECT A MODULE", "选择一件装备"), x: Float(width - 261), y: 148, width: 182, role: .caption, color: UITheme.Color.muted)
        }
        button(r, vaultEquipButton(width: Double(width), height: Double(height)),
               title: t(game, "EQUIP", "装备"), selected: false, emphasis: game.selectedVaultInventoryIndex != nil)
        button(r, vaultSelectedLockButton(width: Double(width), height: Double(height)),
               title: t(game, "LOCK / UNLOCK", "锁定 / 解锁"), selected: false)
        return hoveredModule
    }

    /// Tab 1 战神：配方列表（双重前置条件）+ 已激活战神槽位卡 + 详情 + 操作按钮组（规格第 8 节）。
    private static func drawWarriorTab(_ r: GameRenderer, game: Game, width: Int, height: Int) {
        // 两列小节标题，建立"配方 → 已激活"的阅读顺序。
        styledText(r, t(game, "RECIPES", "融合配方"), x: 350, y: 190, role: .caption, color: UITheme.Color.primary)
        styledText(r, t(game, "ACTIVE WARRIORS", "已激活战神"), x: 664, y: 190, role: .caption, color: UITheme.Color.primary)
        for (index, card) in warriorRecipeCards(width: Double(width), height: Double(height)).enumerated() {
            let recipes = EquipmentCatalog.shared.recipes
            guard index < recipes.count else { continue }
            let recipe = recipes[index]
            let activated = game.profile.warriors.contains { $0.recipeId == recipe.id }
            let selected = game.selectedWarriorRecipe == recipe.id
            button(r, card, title: "", selected: selected)
            r.fillRect(RenderRect(x: Float(card.x), y: Float(card.y), width: 3, height: Float(card.height)),
                       color: activated ? UITheme.Color.success : color(equipmentStageColor(6)))
            let left = Float(card.x + 14)
            hangarText(r, ellipsized(game.language == .chinese ? recipe.name : recipe.nameEn, maxWidth: 150, scale: UITextRole.caption.scale),
                       x: left, y: Float(card.y + 5), width: 150, role: .caption,
                       color: activated ? UITheme.Color.success : UITheme.Color.text)
            styledRightText(r, warriorSlotBadge(game, recipe.slot), right: Float(card.x + card.width - 12),
                            y: Float(card.y + 5), role: .caption, color: UITheme.Color.muted)
            hangarText(r, ellipsized(game.warriorConditionText(recipe), maxWidth: 240, scale: UITextRole.caption.scale),
                       x: left, y: Float(card.y + 22), width: 240, role: .caption, color: UITheme.Color.secondary)
        }
        for (index, card) in warriorSlotCards(width: Double(width), height: Double(height)).enumerated() {
            let slot = WarriorSlot.allCases[index]
            let warriors = game.profile.warriors.enumerated().filter { $0.element.slot == slot }
            let warriorIndex = warriors.first?.0
            let selected = game.selectedWarriorIndex == warriorIndex
            button(r, card, title: "", selected: selected)
            let left = Float(card.x + 14)
            let right = Float(card.x + card.width - 14)
            hangarText(r, warriorSlotName(game, slot), x: left, y: Float(card.y + 8), width: 182,
                       role: .caption, color: UITheme.Color.primary)
            if let warriorIndex, let warrior = game.profile.warriors[safe: warriorIndex] {
                let name = game.language == .chinese ? warrior.displayName : (warrior.recipe?.nameEn ?? warrior.displayName)
                // 首行右侧：部署状态徽章；第二行右侧：同步率。
                let state = warrior.equipped ? t(game, "DEPLOYED", "已部署") : t(game, "STANDBY", "待命")
                hangarText(r, state, x: right - 90, y: Float(card.y + 8), width: 90,
                           role: .caption, color: warrior.equipped ? UITheme.Color.success : UITheme.Color.muted)
                hangarText(r, ellipsized(name, maxWidth: 200, scale: UITextRole.caption.scale), x: left, y: Float(card.y + 28),
                           width: 200, role: .caption, color: UITheme.Color.text)
                let synergyColor = warrior.golden ? UITheme.Color.warning : UITheme.Color.primary
                styledRightText(r, "\(Int(warrior.synergyRate * 100))%", right: right,
                                y: Float(card.y + 28), role: .caption, color: synergyColor)
                styledText(r, "+\(warrior.advanceStage)  •  Lv.\(warrior.level)/\(warrior.levelCap)", x: left, y: Float(card.y + 50),
                           role: .caption, color: UITheme.Color.secondary)
            } else {
                hangarText(r, t(game, "EMPTY", "未激活"), x: left, y: Float(card.y + 34), width: 182,
                           role: .caption, color: UITheme.Color.muted)
            }
        }
        // 详情面板。
        drawWarriorInspector(r, game: game, width: width)
        // 操作按钮：激活 → 养成（升级/进阶）→ 部署/拆解 → 素材切换。
        button(r, warriorFuseButton(width: Double(width), height: Double(height)),
               title: t(game, "FUSE", "激活"), selected: false,
               emphasis: game.selectedWarriorRecipe != nil && !game.profile.warriors.contains { $0.recipeId == game.selectedWarriorRecipe })
        button(r, warriorLevelButton(width: Double(width), height: Double(height)),
               title: t(game, "LEVEL UP", "升级"), selected: false, emphasis: game.selectedWarriorIndex != nil)
        let canGolden = game.selectedWarriorIndex.flatMap { game.profile.warriors[safe: $0] }?.advanceStage ?? 0 >= 9
        button(r, warriorAdvanceButton(width: Double(width), height: Double(height)),
               title: canGolden ? t(game, "GOLDEN", "黄金晋级") : t(game, "ADVANCE", "进阶"),
               selected: false, emphasis: game.selectedWarriorIndex != nil)
        button(r, warriorDeployButton(width: Double(width), height: Double(height)),
               title: t(game, "DEPLOY", "部署"), selected: false, emphasis: game.selectedWarriorIndex != nil)
        button(r, warriorDissolveButton(width: Double(width), height: Double(height)),
               title: t(game, "DISSOLVE", "拆解"), selected: false)
        button(r, warriorExpButton(width: Double(width), height: Double(height)),
               title: t(game, "EXP: ", "素材：") + game.materialDisplayName(game.selectedExpMaterial) + " x\(game.materialCount(game.selectedExpMaterial))",
               selected: false)
    }

    /// 装备详情面板（v7：阶标签 / 等级经验 / 战力 / 特性 / 进阶消耗）。
    private static func drawEquipmentInspector(_ r: GameRenderer, game: Game, item: EquipmentState,
                                               x: Int, y: Int, width: Int, height: Int) {
        panel(r, x: x, y: y, width: width, height: height)
        let left = Float(x + 14), top = Float(y), contentWidth = Float(width - 28)
        let right = Float(x + width - 14)
        hangarText(r, t(game, "MODULE DETAILS", "模块信息"), x: left, y: top + 14, width: contentWidth,
                   role: .label, color: UITheme.Color.primary)
        hangarText(r, ellipsized(game.equipmentDisplayName(item), maxWidth: contentWidth, scale: UITextRole.body.scale),
                   x: left, y: top + 40, width: contentWidth, role: .body, color: UITheme.Color.text)
        hangarText(r, game.equipmentStageLabel(item.stage) + "  •  " + t(game, "TIER", "档位") + " \(item.tier)",
                   x: left, y: top + 68, width: 140, role: .caption, color: color(equipmentStageColor(item.stage)))
        styledRightText(r, "Lv.\(item.level)/\(item.levelCap)", right: right, y: top + 67, role: .caption, color: UITheme.Color.secondary)
        styledText(r, t(game, "POWER", "战力"), x: left, y: top + 94, role: .caption, color: UITheme.Color.muted)
        styledRightText(r, "\(item.unitPower)", right: right, y: top + 92, role: .body, color: UITheme.Color.action)
        // 经验条（升级只吃经验素材）。
        if item.isMaxLevel {
            hangarText(r, t(game, "EXP  MAX", "经验  已满"), x: left, y: top + 122, width: contentWidth,
                       role: .caption, color: UITheme.Color.success)
        } else {
            let need = EquipmentCatalog.shared.expToNext(level: item.level, stage: item.stage)
            hangarText(r, t(game, "EXP", "经验") + "  \(item.exp)/\(need)", x: left, y: top + 122, width: contentWidth,
                       role: .caption, color: UITheme.Color.secondary)
            progress(r, UIProgressBar(rect: UIRect(x: Double(left), y: Double(top + 144), width: Double(contentWidth), height: 7),
                                      value: Double(item.exp) / Double(max(1, need)),
                                      fill: UITheme.Color.energy, back: RenderColor(24, 53, 68)), height: 7)
        }
        r.line(from: (left, top + 172), to: (right, top + 172), color: UITheme.Color.border)
        hangarDetail(r, game.equipmentBonusText(item), x: left, y: top + 186, width: contentWidth)
        hangarText(r, t(game, "ADVANCE", "进阶消耗"), x: left, y: top + 244, width: contentWidth,
                   role: .caption, color: UITheme.Color.primary)
        hangarDetail(r, game.equipmentAdvanceCostText(item), x: left, y: top + 264, width: contentWidth)
    }

    /// 战神详情面板：选中已激活战神展示本体阶级 / 同步率 / 素材；选中配方展示条件与素材需求。
    private static func drawWarriorInspector(_ r: GameRenderer, game: Game, width: Int) {
        let x = width - 275, y = 132, panelWidth = 210, panelHeight = 264
        panel(r, x: x, y: y, width: panelWidth, height: panelHeight)
        let left = Float(x + 14), top = Float(y), contentWidth = Float(panelWidth - 28)
        let right = Float(x + panelWidth - 14)
        hangarText(r, t(game, "WARRIOR", "战神"), x: left, y: top + 14, width: contentWidth, role: .label, color: UITheme.Color.primary)
        if let index = game.selectedWarriorIndex, let warrior = game.profile.warriors[safe: index] {
            let name = game.language == .chinese ? warrior.displayName : (warrior.recipe?.nameEn ?? warrior.displayName)
            hangarText(r, ellipsized(name, maxWidth: contentWidth, scale: UITextRole.body.scale), x: left, y: top + 38,
                       width: contentWidth, role: .body, color: UITheme.Color.text)
            let advanceText = warrior.advanceStage >= 9
                ? (warrior.golden ? t(game, "GOLDEN", "黄金") : t(game, "+9 MAX", "+9 满阶"))
                : "+\(warrior.advanceStage)"
            hangarText(r, advanceText + "  •  Lv.\(warrior.level)/\(warrior.levelCap)", x: left, y: top + 62,
                       width: 130, role: .caption, color: warrior.golden ? UITheme.Color.warning : color(equipmentStageColor(6)))
            styledRightText(r, "\(Int(warrior.synergyRate * 100))%", right: right, y: top + 61, role: .body,
                            color: UITheme.Color.primary)
            hangarText(r, t(game, "SYNERGY", "同步率") + "  •  " + (warrior.equipped ? t(game, "DEPLOYED", "已部署") : t(game, "STANDBY", "待命")),
                       x: left, y: top + 86, width: contentWidth, role: .caption, color: UITheme.Color.secondary)
            r.line(from: (left, top + 108), to: (right, top + 108), color: UITheme.Color.border)
            hangarText(r, t(game, "FUSION MATERIALS", "融合素材"), x: left, y: top + 120, width: contentWidth,
                       role: .caption, color: UITheme.Color.primary)
            let materials = warrior.materialUIDs.compactMap { uid -> EquipmentState? in
                game.profile.equipment.first { $0.uid == uid } ?? game.profile.inventory.first { $0.uid == uid }
            }
            for (offset, material) in materials.prefix(2).enumerated() {
                hangarText(r, ellipsized("\(game.equipmentDisplayName(material))  Lv.\(material.level)  \(game.equipmentStageLabel(material.stage))",
                                         maxWidth: contentWidth, scale: UITextRole.caption.scale),
                           x: left, y: top + 142 + Float(offset) * 22, width: contentWidth, role: .caption, color: UITheme.Color.text)
            }
            hangarDetail(r, t(game, "Output = material panel x base output x synergy. Dissolve returns materials losslessly.",
                              "出力 = 素材面板 × 基础出力 × 同步率；拆解无损归还素材。"),
                         x: left, y: top + 196, width: contentWidth)
        } else if let recipeId = game.selectedWarriorRecipe, let recipe = EquipmentCatalog.shared.recipe(id: recipeId) {
            hangarText(r, ellipsized(game.language == .chinese ? recipe.name : recipe.nameEn, maxWidth: contentWidth, scale: UITextRole.body.scale),
                       x: left, y: top + 38, width: contentWidth, role: .body, color: UITheme.Color.text)
            hangarText(r, warriorSlotName(game, recipe.slot) + "  •  " + t(game, "TIER", "档位") + " \(recipe.tier)",
                       x: left, y: top + 62, width: contentWidth, role: .caption, color: UITheme.Color.secondary)
            hangarText(r, t(game, "CONDITION", "激活条件"), x: left, y: top + 88, width: contentWidth,
                       role: .caption, color: UITheme.Color.primary)
            hangarDetail(r, game.warriorConditionText(recipe), x: left, y: top + 108, width: contentWidth)
            hangarText(r, t(game, "FUSION MATERIALS", "融合素材"), x: left, y: top + 156, width: contentWidth,
                       role: .caption, color: UITheme.Color.primary)
            for (offset, ref) in recipe.materials.enumerated() {
                let name = EquipmentCatalog.shared.displayName(seriesId: ref.seriesId, stage: ref.minStage)
                hangarText(r, ellipsized(name, maxWidth: contentWidth, scale: UITextRole.caption.scale),
                           x: left, y: top + 176 + Float(offset) * 22, width: contentWidth, role: .caption, color: UITheme.Color.text)
            }
        } else {
            hangarText(r, t(game, "SELECT A RECIPE", "选择一个配方"), x: left, y: top + 38, width: contentWidth,
                       role: .caption, color: UITheme.Color.muted)
            hangarDetail(r, t(game, "Fuse two purple modules into a warrior. Materials are occupied, never consumed.",
                              "两件指定紫装融合为战神；素材只占用、不消耗，可随时无损拆解。"),
                         x: left, y: top + 64, width: contentWidth)
        }
    }

    /// 战神槽位展示名。
    private static func warriorSlotName(_ game: Game, _ slot: WarriorSlot) -> String {
        switch slot {
        case .warriorFighter: return t(game, "BODY", "机体")
        case .warriorArmor: return t(game, "ARMOR", "装甲")
        case .warriorSubweapon: return t(game, "SUB", "副武器")
        case .warriorWingman: return t(game, "WINGMAN", "僚机")
        }
    }

    /// 配方卡右侧槽位缩写。
    private static func warriorSlotBadge(_ game: Game, _ slot: WarriorSlot) -> String {
        switch slot {
        case .warriorFighter: return t(game, "BODY", "机体")
        case .warriorArmor: return t(game, "ARMOR", "装甲")
        case .warriorSubweapon: return t(game, "SUB", "副武")
        case .warriorWingman: return t(game, "WING", "僚机")
        }
    }

    /// 槽位展示名（v7 槽位枚举；老存档 slot 编码 1..4 已由迁移层映射，此处不再兼容）。
    private static func equipmentSlotName(_ game: Game, _ slot: EquipmentSlot) -> String {
        switch slot {
        case .fighter: return t(game, "FIGHTER", "战机")
        case .subweapon: return t(game, "SUBWEAPON", "副武器")
        case .armor: return t(game, "ARMOR", "装甲")
        case .wingman: return t(game, "WINGMAN", "僚机")
        }
    }

    private static func profileInventory(_ game: Game, contains index: Int) -> Bool {
        game.profile.inventory.indices.contains(index)
    }

    private static func drawShip(_ r: GameRenderer, center: (x: Float, y: Float), scale: Float, accent: RenderColor) {
        let x = center.x, y = center.y
        r.fillCircle(center: (x, y - 34 * scale), radius: 10 * scale, color: RenderColor(235, 250, 255))
        r.fillRect(RenderRect(x: x - 9 * scale, y: y - 28 * scale, width: 18 * scale, height: 62 * scale), color: accent)
        r.fillRect(RenderRect(x: x - 34 * scale, y: y + 4 * scale, width: 68 * scale, height: 9 * scale), color: accent)
        r.fillRect(RenderRect(x: x - 23 * scale, y: y + 18 * scale, width: 46 * scale, height: 8 * scale), color: RenderColor(196, 237, 255))
        r.fillCircle(center: (x, y + 37 * scale), radius: 8 * scale, color: RenderColor(255, 155, 92, 220))
        r.line(from: (x - 28 * scale, y + 13 * scale), to: (x - 42 * scale, y + 30 * scale), color: UITheme.Color.borderHighlight)
        r.line(from: (x + 28 * scale, y + 13 * scale), to: (x + 42 * scale, y + 30 * scale), color: UITheme.Color.borderHighlight)
    }

    private static func drawArchive(_ r: GameRenderer, game: Game, width: Int, height: Int) {
        panel(r, x: width / 2 - 340, y: 74, width: 680, height: height - 115)
        centeredText(r, t(game, "ARCHIVE // RECORDS", "档案馆 // 记录"), centerX: Float(width / 2), y: 94, role: .pageTitle, shadow: true)
        let tabs = archiveTabButtons(width: Double(width), height: Double(height))
        button(r, tabs[0], title: t(game, "ACHIEVEMENTS", "成就"), selected: game.archiveTab == 0)
        button(r, tabs[1], title: t(game, "CODEX", "图鉴"), selected: game.archiveTab == 1)
        if game.archiveTab == 0 {
            text(r, "\(game.profile.achievements.count)/\(AchievementCatalog.all.count) " + t(game, "UNLOCKED", "已解锁"), 330, 198, UITheme.Color.warning)
            for (index, achievement) in AchievementCatalog.all.enumerated() {
                let y = 224 + index * 52
                let unlocked = game.profile.achievements.contains(achievement.id)
                let value = min(game.achievementValue(achievement.metric), achievement.target)
                text(r, achievement.title(for: game.language), 330, Float(y), unlocked ? UITheme.Color.text : UITheme.Color.muted)
                text(r, achievement.detail(for: game.language), 330, Float(y + 20), UITheme.Color.secondary)
                progress(r, UIProgressBar(rect: UIRect(x: 700, y: Double(y + 7), width: 220, height: 8), value: Double(value) / Double(max(1, achievement.target)), fill: unlocked ? UITheme.Color.success : UITheme.Color.primary, back: RenderColor(24, 39, 58)), height: 8)
                text(r, "\(value)/\(achievement.target)", 930, Float(y + 8), unlocked ? UITheme.Color.success : UITheme.Color.muted)
            }
        } else {
            let categories = codexCategoryButtons(width: Double(width), height: Double(height))
            for (index, category) in CodexCategory.allCases.enumerated() {
                button(r, categories[index], title: category.label(for: game.language), selected: category == game.codexCategory)
            }
            let entries = CodexCatalog.all.filter { $0.category == game.codexCategory }
            let pageSize = 3
            let start = min(max(0, game.codexPage * pageSize), max(0, entries.count - 1))
            let pageEntries = entries.dropFirst(start).prefix(pageSize)
            for (index, entry) in pageEntries.enumerated() {
                let y = 254 + index * 94
                panel(r, x: 330, y: y - 20, width: 580, height: 76)
                text(r, entry.title(for: game.language), 350, Float(y), UITheme.Color.text)
                text(r, entry.detail(for: game.language), 350, Float(y + 27), UITheme.Color.secondary)
                text(r, String(format: "%02d", start + index + 1), 866, Float(y), UITheme.Color.primary)
            }
            button(r, codexPrevButton(width: Double(width), height: Double(height)), title: "<", selected: false)
            button(r, codexNextButton(width: Double(width), height: Double(height)), title: ">", selected: false)
            text(r, "\(game.codexPage + 1)/\(max(1, (entries.count + pageSize - 1) / pageSize))", 600, Float(height - 126), UITheme.Color.muted)
        }
        button(r, archiveBackButton(width: Double(width), height: Double(height)), title: t(game, "BACK", "返回"), selected: false)
    }

    private static func drawPause(_ r: GameRenderer, game: Game, width: Int, height: Int) {
        r.fillRect(RenderRect(x: 0, y: 0, width: Float(width), height: Float(height)), color: RenderColor(3, 8, 17, 168))
        panel(r, x: width / 2 - 310, y: height / 2 - 225, width: 620, height: 450)
        sectionHeader(r, title: t(game, "MISSION PAUSED", "战斗暂停"), subtitle: t(game, "TACTICAL MENU", "战术菜单"),
                      x: width / 2 - 278, y: height / 2 - 190, width: 556)
        text(r, t(game, "Combat simulation suspended. Select an action.", "战斗已暂停，请选择下一步操作。"),
             Float(width / 2 - 190), Float(height / 2 - 155), UITheme.Color.muted)
        let buttons = pauseButtons(width: Double(width), height: Double(height))
        let titles = [t(game, "RESUME", "继续"), t(game, "RESTART", "重新开始"), t(game, "SETTINGS", "设置"), t(game, "MAIN MENU", "主菜单"), t(game, "EXIT", "退出")]
        for (i, title) in titles.enumerated() { button(r, buttons[i], title: title, selected: false, emphasis: i == 0) }
    }

    private static func drawConfirmation(_ overlay: GameRenderer, uiRenderer r: GameRenderer, game: Game, width: Int, height: Int) {
        // The dimmer sits inside the logical canvas, so it remains aligned
        // with the letterboxed viewport and does not affect gameplay state.
        overlay.fillRect(RenderRect(x: 0, y: 0, width: Float(width), height: Float(height)), color: RenderColor(2, 5, 14, 176))
        let dialog = confirmationPanel(width: Double(width), height: Double(height))
        panel(r, x: Int(dialog.x), y: Int(dialog.y), width: Int(dialog.width), height: Int(dialog.height))
        text(r, t(game, "ABANDON SORTIE?", "结束本次出击？"), Float(dialog.x + 34), Float(dialog.y + 42), UITheme.Color.warning)
        text(r, t(game, "Current run progress will be saved before returning.", "返回前会保存当前进度，本局战斗将结束。"), Float(dialog.x + 34), Float(dialog.y + 78), UITheme.Color.secondary)
        text(r, t(game, "You can launch again from Mission Select.", "你可以从关卡选择再次出击。"), Float(dialog.x + 34), Float(dialog.y + 101), UITheme.Color.muted)
        button(r, confirmationConfirmButton(width: Double(width), height: Double(height)), title: t(game, "RETURN TO MENU", "返回主菜单"), selected: false, emphasis: true)
        button(r, confirmationCancelButton(width: Double(width), height: Double(height)), title: t(game, "CANCEL", "取消"), selected: false)
    }

    private static func drawUpgrade(_ r: GameRenderer, game: Game, width: Int, height: Int) {
        let cards = upgradeCards(width: Double(width), height: Double(height))
        if let first = cards.first, let last = cards.last {
            let stripX = Int(first.x - 8)
            let stripY = Int(first.y - 8)
            panel(r, x: stripX, y: stripY, width: Int(last.x + last.width - first.x + 16), height: Int(first.height + 16))
        }
        for (i, card) in cards.enumerated() {
            let option = i < game.upgradeOptions.count ? game.upgradeOptions[i] : UpgradeOption(title: t(game, "MODULE", "模块"), detail: "", kind: 0)
            button(r, card, title: "", selected: card.contains(UIInteraction.pointer))
            let rarity = UpgradeRarity(rawValue: option.rarity) ?? .common
            r.fillRect(RenderRect(x: Float(card.x), y: Float(card.y), width: Float(card.width), height: 3), color: color(rarityColor(rarity)))
            text(r, game.localizedRarity(rarity), Float(card.x + 12), Float(card.y + 12), color(rarityColor(rarity)))
            text(r, "[\(i + 1)]", Float(card.x + card.width - 30), Float(card.y + 12), UITheme.Color.muted)
            text(r, option.title, Float(card.x + 12), Float(card.y + 36), UITheme.Color.text)
            drawWrappedText(r, option.detail, x: Float(card.x + 12), y: Float(card.y + 59), color: UITheme.Color.secondary,
                            maxWidth: Float(card.width - 24), lineHeight: 15, maxLines: 2)
        }
    }

    private static func drawGameOver(_ r: GameRenderer, game: Game, width: Int, height: Int) {
        r.fillRect(RenderRect(x: 0, y: 0, width: Float(width), height: Float(height)), color: RenderColor(3, 8, 17, 176))
        panel(r, x: width / 2 - 310, y: height / 2 - 215, width: 620, height: 430)
        sectionHeader(r, title: game.runWon ? t(game, "MISSION COMPLETE", "任务完成") : t(game, "SORTIE FAILED", "任务失败"),
                      subtitle: t(game, "SORTIE REPORT", "出击报告"), x: width / 2 - 278, y: height / 2 - 168, width: 556)
        text(r, t(game, "RATING", "评级") + "  " + runGrade(game), Float(width / 2 - 58), Float(height / 2 - 132), game.runWon ? UITheme.Color.success : UITheme.Color.secondary)
        text(r, t(game, "SCORE", "分数") + "  \(game.score)", Float(width / 2 - 70), Float(height / 2 - 104), UITheme.Color.text)
        text(r, t(game, "KILLS", "击杀") + "  \(game.kills)    " + t(game, "BEST COMBO", "最高连击") + "  \(game.comboBest)", Float(width / 2 - 144), Float(height / 2 - 62), UITheme.Color.secondary)
        text(r, t(game, "SURVIVAL", "存活") + "  \(Int(game.survivalTime))s    " + t(game, "BOSS", "首领") + "  " + (game.missionBossDefeated ? t(game, "DOWN", "已击破") : t(game, "ACTIVE", "未击破")), Float(width / 2 - 170), Float(height / 2 - 34), UITheme.Color.secondary)
        text(r, t(game, "RUN REWARDS", "本局奖励"), Float(width / 2 - 140), Float(height / 2 + 10), UITheme.Color.primary)
        text(r, t(game, "CREDITS", "金币") + " +\(game.runCreditsEarned)    " + t(game, "CORES", "核心") + " +\(game.runCoresEarned)    " + t(game, "ALLOY", "合金") + " +\(game.runAlloyEarned)", Float(width / 2 - 190), Float(height / 2 + 40), UITheme.Color.warning)
        if !game.runRareDropSeriesId.isEmpty {
            let dropName = game.equipmentName(seriesId: game.runRareDropSeriesId, stage: game.runRareDropStage)
            text(r, t(game, "RARE MODULE", "稀有模块") + "  •  " + dropName + "  •  " + game.equipmentQualityName(stage: game.runRareDropStage), Float(width / 2 - 188), Float(height / 2 + 64), UITheme.Color.boss)
        }
        let buttons = gameOverButtons(width: Double(width), height: Double(height))
        button(r, buttons[0], title: t(game, "RESTART", "重新开始"), selected: false, emphasis: true)
        button(r, buttons[1], title: t(game, "MAIN MENU", "主菜单"), selected: false)
    }

    private static func runGrade(_ game: Game) -> String {
        if game.runWon {
            if game.score >= 25000 { return "S" }
            if game.score >= 12000 { return "A" }
            return "B"
        }
        if game.score >= 15000 { return "B" }
        if game.score >= 5000 { return "C" }
        return "D"
    }

    private static func panel(_ r: GameRenderer, x: Int, y: Int, width: Int, height: Int) {
        let component = UIPanel(rect: UIRect(x: Double(x), y: Double(y), width: Double(width), height: Double(height)))
        r.fillRect(RenderRect(x: Float(x + 5), y: Float(y + 6), width: Float(width), height: Float(height)), color: RenderColor(1, 5, 12, 82))
        r.fillRect(RenderRect(x: Float(component.rect.x), y: Float(component.rect.y), width: Float(component.rect.width), height: Float(component.rect.height)), color: UITheme.Color.panel)
        // A muted edge hierarchy reads as a single glass-like surface instead
        // of a grid of bright boxes.
        r.fillRect(RenderRect(x: Float(x + 1), y: Float(y + 1), width: Float(max(0, width - 2)), height: 1), color: RenderColor(190, 218, 230, 24))
        r.line(from: (Float(x), Float(y)), to: (Float(x + width), Float(y)), color: UITheme.Color.borderHighlight)
        r.line(from: (Float(x), Float(y + height)), to: (Float(x + width), Float(y + height)), color: UITheme.Color.border)
        r.line(from: (Float(x), Float(y)), to: (Float(x), Float(y + height)), color: UITheme.Color.border)
        r.line(from: (Float(x + width), Float(y)), to: (Float(x + width), Float(y + height)), color: UITheme.Color.border)
    }

    private static func sectionHeader(_ r: GameRenderer, title: String, subtitle: String, x: Int, y: Int, width: Int) {
        styledText(r, title, x: Float(x), y: Float(y - 2), role: .sectionTitle)
        styledRightText(r, subtitle, right: Float(x + width), y: Float(y + 1), role: .caption)
        r.fillRect(RenderRect(x: Float(x), y: Float(y + 24), width: Float(width), height: 1), color: UITheme.Color.border)
        r.fillRect(RenderRect(x: Float(x), y: Float(y + 24), width: Float(min(74, width)), height: 2), color: UITheme.Color.primaryDeep)
    }

    private static func drawStatTile(_ r: GameRenderer, x: Int, y: Int, width: Int, height: Int,
                                     label: String, value: String, tint: RenderColor) {
        r.fillRect(RenderRect(x: Float(x), y: Float(y), width: Float(width), height: Float(height)), color: UITheme.Color.panelSoft)
        r.fillRect(RenderRect(x: Float(x), y: Float(y), width: 3, height: Float(height)), color: tint)
        styledText(r, ellipsized(label, maxWidth: Float(width - 28), scale: UITextRole.label.scale),
                   x: Float(x + 14), y: Float(y + 12), role: .label)
        styledText(r, ellipsized(value, maxWidth: Float(width - 28), scale: UITextRole.number.scale),
                   x: Float(x + 14), y: Float(y + height - 35), role: .number, color: tint, shadow: true)
    }

    private static func button(_ r: GameRenderer, _ rect: UIRect, title: String, selected: Bool, emphasis: Bool = false, enabled: Bool = true) {
        let component = UIButton(rect: rect, title: title, selected: selected, enabled: enabled)
        let state = UIInteraction.state(for: component.rect, selected: component.selected, enabled: component.enabled)
        let fill: RenderColor
        let border: RenderColor
        switch state {
        case .selected:
            let pulse = UIAnimationSystem.pulse(time: UIInteraction.time, speed: 3.0, amount: 0.035)
            fill = UITheme.Color.panelSelected; border = RenderColor(125, 191, 205, UInt8(min(225, 185 * pulse)))
        case .hover:
            let pulse = UIAnimationSystem.pulse(time: UIInteraction.time, speed: 4.0, amount: 0.025)
            fill = emphasis ? UITheme.Color.actionHover : UITheme.Color.panelHover
            border = RenderColor(126, 184, 199, UInt8(min(210, 170 * pulse)))
        case .pressed:
            fill = emphasis ? UITheme.Color.action : UITheme.Color.panelSelected; border = RenderColor(UITheme.Color.warning.red, UITheme.Color.warning.green, UITheme.Color.warning.blue, 185)
        case .disabled:
            fill = RenderColor(25, 34, 49, 190); border = RenderColor(57, 70, 86, 180)
        default:
            fill = emphasis ? UITheme.Color.action : UITheme.Color.panelRaised
            border = emphasis ? UITheme.Color.actionHover : UITheme.Color.border
        }
        r.fillRect(RenderRect(x: Float(rect.x), y: Float(rect.y), width: Float(rect.width), height: Float(rect.height)), color: fill)
        if emphasis || state == .hover || state == .selected {
            r.fillRect(RenderRect(x: Float(rect.x), y: Float(rect.y), width: 4, height: Float(rect.height)), color: emphasis ? UITheme.Color.actionHover : UITheme.Color.primary)
        }
        r.line(from: (Float(rect.x), Float(rect.y)), to: (Float(rect.x + rect.width), Float(rect.y)), color: border)
        r.line(from: (Float(rect.x), Float(rect.y + rect.height)), to: (Float(rect.x + rect.width), Float(rect.y + rect.height)), color: border)
        let labelColor = state == .disabled ? UITheme.Color.muted : (emphasis ? UITheme.Color.ink : UITheme.Color.text)
        let titleInset: Float = emphasis ? 20 : 16
        let visibleTitle = ellipsized(component.title, maxWidth: Float(rect.width) - titleInset - 12, scale: UITextRole.body.scale)
        styledText(r, visibleTitle, x: Float(rect.x) + titleInset, y: Float(rect.y + rect.height * 0.5 - 7),
                   role: .body, color: labelColor)
    }

    private static func bar(_ r: GameRenderer, x: Float, y: Float, width: Float, value: Double, fill: RenderColor, back: RenderColor) {
        progress(r, UIProgressBar(rect: UIRect(x: Double(x), y: Double(y), width: Double(width), height: 10), value: value, fill: fill, back: back), height: 10)
    }

    private static func progress(_ r: GameRenderer, _ bar: UIProgressBar, height: Float) {
        let rect = bar.rect
        r.fillRect(RenderRect(x: Float(rect.x), y: Float(rect.y), width: Float(rect.width), height: height), color: bar.back)
        r.fillRect(RenderRect(x: Float(rect.x), y: Float(rect.y), width: Float(rect.width) * Float(min(1, max(0, bar.value))), height: height), color: bar.fill)
        r.line(from: (Float(rect.x), Float(rect.y)), to: (Float(rect.x + rect.width), Float(rect.y)), color: RenderColor(UITheme.Color.border.red, UITheme.Color.border.green, UITheme.Color.border.blue, 100))
    }

    private static func text(_ r: GameRenderer, _ value: String, _ x: Float, _ y: Float, _ c: RenderColor) { r.drawText(value, at: (x: x, y: y), color: c) }

    private static func styledText(_ r: GameRenderer, _ value: String, x: Float, y: Float, role: UITextRole,
                                   color: RenderColor? = nil, shadow: Bool = false) {
        let tint = color ?? role.defaultColor
        if shadow {
            r.drawTextScaled(value, at: (x: x + 1, y: y + 2), scale: role.scale,
                             color: RenderColor(1, 5, 11, min(170, tint.alpha)))
        }
        r.drawTextScaled(value, at: (x: x, y: y), scale: role.scale, color: tint)
    }

    private static func centeredText(_ r: GameRenderer, _ value: String, centerX: Float, y: Float, role: UITextRole,
                                     color: RenderColor? = nil, shadow: Bool = false) {
        styledText(r, value, x: centerX - textWidth(value, scale: role.scale) * 0.5, y: y,
                   role: role, color: color, shadow: shadow)
    }

    private static func styledRightText(_ r: GameRenderer, _ value: String, right: Float, y: Float, role: UITextRole,
                                        color: RenderColor? = nil) {
        styledText(r, value, x: right - textWidth(value, scale: role.scale), y: y, role: role, color: color)
    }

    private static func drawRightText(_ r: GameRenderer, _ value: String, right: Float, y: Float, color: RenderColor) {
        text(r, value, right - textWidth(value), y, color)
    }

    private static func drawCombatNotification(_ r: GameRenderer, game: Game, field: PlayfieldBounds) {
        let alpha = notificationAlpha(game.notificationTimer, fullDuration: 3.2)
        let tint = color(game.notificationTint)
        let titleColor = RenderColor(tint.red, tint.green, tint.blue, alpha)
        let detailColor = RenderColor(UITheme.Color.secondary.red, UITheme.Color.secondary.green, UITheme.Color.secondary.blue, alpha)
        let x: Float = 18
        let y = Float(field.top + 26)
        let height: Float = 84
        r.fillRect(RenderRect(x: x + 4, y: y + 5, width: 382, height: height), color: RenderColor(1, 5, 12, UInt8(Double(alpha) * 0.46)))
        r.fillRect(RenderRect(x: x, y: y, width: 382, height: height), color: RenderColor(7, 17, 34, UInt8(Double(alpha) * 0.90)))
        r.fillRect(RenderRect(x: x, y: y, width: 4, height: height), color: titleColor)
        r.fillRect(RenderRect(x: x + 14, y: y, width: 54, height: 2), color: titleColor)
        styledText(r, ellipsized(game.notificationTitle, maxWidth: 345, scale: UITextRole.sectionTitle.scale),
                   x: x + 15, y: y + 9, role: .sectionTitle, color: titleColor, shadow: true)
        drawWrappedText(r, game.notificationDetail, x: x + 15, y: y + 36, color: detailColor,
                        maxWidth: 350, lineHeight: UITheme.Typography.compactLineHeight, maxLines: 2)
    }

    /// Persistent, compact countdowns make temporary power-up windows useful
    /// without forcing the player to remember the number in the pickup toast.
    /// They sit outside the central bullet-dodging area and only appear while
    /// an effect is actually active.
    private static func drawTimedEffectBars(_ r: GameRenderer, game: Game, width: Int) {
        var effects: [(name: String, remaining: Double, duration: Double, tint: RenderColor)] = []
        if game.fireRateBoostTime > 0 {
            effects.append((t(game, "FIRE RATE +50%", "射速 +50%"), game.fireRateBoostTime, 5, UITheme.Color.energy))
        }
        if game.shieldBreakSpeedTime > 0 {
            effects.append((t(game, "MOVE +30%", "移速 +30%"), game.shieldBreakSpeedTime, 3, UITheme.Color.shield))
        }
        if game.bloodLeechTime > 0 {
            effects.append((t(game, "BLOODLUST", "嗜血如命"), game.bloodLeechTime, 8, UITheme.Color.danger))
        }
        if game.thunderOverloadTime > 0 {
            effects.append((t(game, "OVERLOAD", "雷霆超载"), game.thunderOverloadTime, 6, UITheme.Color.primary))
        }
        guard !effects.isEmpty else { return }

        let panelWidth: Float = 178
        let x = Float(width) - panelWidth - 16
        for (index, effect) in effects.enumerated() {
            // Begin below the fixed 82 px combat header so countdowns never
            // compete with HP, XP, Boss state, or the build summary.
            let y = Float(96 + index * 34)
            r.fillRect(RenderRect(x: x, y: y, width: panelWidth, height: 28), color: RenderColor(10, 22, 40, 214))
            r.fillRect(RenderRect(x: x, y: y, width: 3, height: 28), color: effect.tint)
            text(r, effect.name, x + 10, y + 6, UITheme.Color.text)
            let seconds = max(1, Int(ceil(effect.remaining)))
            drawRightText(r, "\(seconds)s", right: x + panelWidth - 9, y: y + 6, color: effect.tint)
            progress(r, UIProgressBar(rect: UIRect(x: Double(x + 10), y: Double(y + 20), width: Double(panelWidth - 20), height: 4),
                                      value: effect.remaining / effect.duration,
                                      fill: effect.tint,
                                      back: RenderColor(34, 53, 71)), height: 4)
        }
    }

    private static func notificationAlpha(_ timeRemaining: Double, fullDuration: Double) -> UInt8 {
        let fadeStart = min(0.55, fullDuration * 0.24)
        let opacity = timeRemaining < fadeStart ? max(0, timeRemaining / fadeStart) : 1
        return UInt8(max(0, min(255, Int(opacity * 255))))
    }

    private static func drawWrappedText(_ r: GameRenderer, _ value: String, x: Float, y: Float, color: RenderColor, maxWidth: Float, lineHeight: Float, maxLines: Int, scale: Float = 1) {
        for (index, line) in wrappedLines(value, maxWidth: maxWidth / scale, maxLines: maxLines).enumerated() {
            r.drawTextScaled(line, at: (x, y + Float(index) * lineHeight * UIInteraction.textMeasurementScale), scale: scale, color: color)
        }
    }

    private static func wrappedLines(_ value: String, maxWidth: Float, maxLines: Int) -> [String] {
        guard maxWidth > 0, maxLines > 0 else { return [] }
        let source = Array(value.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !source.isEmpty else { return [] }
        var lines: [String] = []
        var line: [Character] = []
        var width: Float = 0
        var lastBreak: Int?
        var index = 0
        while index < source.count {
            let character = source[index]
            let advance = glyphWidth(character) * UIInteraction.textMeasurementScale
            if width + advance > maxWidth, !line.isEmpty {
                var emitted: [Character]
                var remainder: [Character] = []
                if let breakIndex = lastBreak, breakIndex > 0 {
                    emitted = Array(line[..<breakIndex])
                    remainder = Array(Array(line[breakIndex...]).drop(while: { $0 == " " }))
                } else {
                    emitted = line
                }
                if lines.count == maxLines - 1 {
                    var shortened = emitted
                    while !shortened.isEmpty && textWidth(String(shortened) + "…") > maxWidth { shortened.removeLast() }
                    lines.append(String(shortened) + (index < source.count || !remainder.isEmpty ? "…" : ""))
                    return lines
                }
                lines.append(String(emitted).trimmingCharacters(in: .whitespaces))
                line = remainder
                width = textWidth(String(line))
                lastBreak = line.lastIndex(where: isBreakOpportunity)
                continue
            }
            line.append(character)
            width += advance
            if isBreakOpportunity(character) { lastBreak = line.count - 1 }
            index += 1
        }
        if !line.isEmpty && lines.count < maxLines {
            lines.append(String(line).trimmingCharacters(in: .whitespaces))
        }
        return lines
    }

    private static func isBreakOpportunity(_ character: Character) -> Bool {
        character == " " || character == "-" || character == "•" || character == "/" || character == "," || character == "，" || character == "。"
    }

    private static func glyphWidth(_ character: Character) -> Float {
        if character == " " { return 8 }
        return character.unicodeScalars.allSatisfy { $0.value < 128 } ? 14 : 20
    }

    private static func textWidth(_ value: String, scale: Float = 1) -> Float {
        value.reduce(0) { $0 + glyphWidth($1) } * scale * UIInteraction.textMeasurementScale
    }

    private static func ellipsized(_ value: String, maxWidth: Float, scale: Float = 1) -> String {
        guard textWidth(value, scale: scale) > maxWidth else { return value }
        var result = Array(value)
        while !result.isEmpty && textWidth(String(result) + "…", scale: scale) > maxWidth {
            result.removeLast()
        }
        return result.isEmpty ? "" : String(result).trimmingCharacters(in: .whitespaces) + "…"
    }

    private static func t(_ game: Game, _ english: String, _ chinese: String) -> String {
        game.uiText(english, chinese)
    }

    private static func color(_ value: UInt32) -> RenderColor {
        let v = UInt32(value)
        return RenderColor(UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff))
    }

    private static func highlighted(_ color: RenderColor, amount: Double) -> RenderColor {
        guard amount > 0 else { return color }
        func blend(_ value: UInt8) -> UInt8 { UInt8(min(255, Double(value) + (255 - Double(value)) * min(1, amount))) }
        return RenderColor(blend(color.red), blend(color.green), blend(color.blue), color.alpha)
    }
}
