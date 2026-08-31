import Foundation

/// Native SDL presentation for the full game.  Gameplay remains independent
/// of SDL; this layer translates the model into lightweight primitives.
enum SDLNativeGameRenderer {
    static func draw(_ renderer: GameRenderer, game: Game, width: Int, height: Int) {
        let uiRenderer = UITransformRenderer(base: renderer, canvasWidth: width, canvasHeight: height, scalePercent: game.profile.uiScale)
        UIInteraction.pointer = game.uiPoint(for: game.mousePosition, width: Double(width), height: Double(height))
        UIInteraction.time = game.uiAnimationTime
        UIInteraction.primaryHeld = game.mousePrimaryDown
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
        r.fillRect(RenderRect(x: 0, y: 0, width: Float(width), height: 82), color: RenderColor(10, 21, 38, 230))
        r.fillRect(RenderRect(x: 0, y: 80, width: Float(width), height: 2), color: RenderColor(83, 136, 154, 86))
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
        drawCombatHUD(uiRenderer, game: game, field: field, width: width)

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
        if let fighter = (r as? SDLRenderer)?.artTexture(named: "thunder_interceptor") {
            let hitAlpha: UInt8 = game.playerHitFlash > 0 ? 245 : 255
            r.drawSprite(fighter, in: RenderRect(x: Float(playerP.x - 31), y: Float(playerP.y - 50), width: 62, height: 94), alpha: hitAlpha)
        } else {
            r.fillCircle(center: (Float(playerP.x), Float(playerP.y)), radius: 18, color: playerColor)
            r.fillCircle(center: (Float(playerP.x), Float(playerP.y - 7)), radius: 8, color: game.playerHitFlash > 0 ? RenderColor(255, 246, 248) : RenderColor(232, 250, 255))
        }
        if game.pickupShieldCharges > 0, let shield = (r as? SDLRenderer)?.artTexture(named: "player_phase_shield") {
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
        guard let texture = (r as? SDLRenderer)?.artTexture(named: "vfx_warning_beam") else { return }
        let width: Float = active ? 34 : 18
        r.drawSprite(texture, in: RenderRect(x: x - width * 0.5, y: top, width: width, height: max(1, bottom - top)),
                     alpha: active ? 245 : 158)
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
        let warning = RenderColor(255, 74, 128, 150)
        let origin = p + Vec2(x: 0, y: 34)
        switch boss.currentAttack {
        case .aimBurst:
            let target = boss.attackTarget + camera
            drawWarningBeam(r, x: Float(target.x), top: Float(field.top), bottom: Float(field.bottom), active: false)
        case .spread:
            for angle in [-0.52, -0.26, 0.0, 0.26, 0.52] {
                let end = origin + Vec2(x: sin(angle) * 245, y: cos(angle) * 245)
                drawWarningBeam(r, x: Float(end.x), top: Float(origin.y), bottom: Float(field.bottom), active: false)
            }
        case .sideCrossfire:
            let target = boss.attackTarget + camera
            drawWarningBeam(r, x: Float(target.x - 18), top: Float(field.top), bottom: Float(field.bottom), active: false)
            drawWarningBeam(r, x: Float(target.x + 18), top: Float(field.top), bottom: Float(field.bottom), active: false)
        case .laserSweep:
            let left = min(boss.laserX, boss.laserTargetX) + camera.x
            let sweepWidth = abs(boss.laserTargetX - boss.laserX)
            r.fillRect(RenderRect(x: Float(left), y: Float(field.top + camera.y), width: Float(sweepWidth),
                                  height: Float(field.bottom - field.top)), color: RenderColor(255, 68, 126, 20))
            r.line(from: (Float(boss.laserX + camera.x), Float(field.top + camera.y)),
                   to: (Float(boss.laserTargetX + camera.x), Float(field.top + camera.y)), color: warning)
        case .slowField:
            if let effect = (r as? SDLRenderer)?.artTexture(named: "vfx_hit_electric") {
                r.drawSprite(effect, in: RenderRect(x: Float(origin.x - 76), y: Float(origin.y - 76), width: 152, height: 152), alpha: 110)
            }
        case .spiral:
            if let effect = (r as? SDLRenderer)?.artTexture(named: "vfx_hit_critical") {
                r.drawSprite(effect, in: RenderRect(x: Float(origin.x - 68), y: Float(origin.y - 68), width: 136, height: 136), alpha: 105)
            }
        }
    }

    private static func drawCombatHUD(_ r: GameRenderer, game: Game, field: PlayfieldBounds, width: Int) {
        r.fillRect(RenderRect(x: 10, y: 8, width: 294, height: 43), color: UITheme.Color.panelSoft)
        r.fillRect(RenderRect(x: 312, y: 8, width: 326, height: 43), color: UITheme.Color.panelSoft)
        r.fillRect(RenderRect(x: Float(max(646, width - 338)), y: 8, width: Float(min(328, width - max(646, width - 338) - 10)), height: 43), color: UITheme.Color.panelSoft)
        r.fillRect(RenderRect(x: 10, y: 56, width: Float(min(780, width - 20)), height: 24), color: RenderColor(12, 28, 46, 205))
        text(r, t(game, "THUNDER SWIFT", "雷霆疾影"), 16, 16, UITheme.Color.text)
        let progressLabel = game.gameMode == .endless
            ? t(game, "WAVE", "波次") + " \(game.endlessWaveNumber)  •  " + (game.endlessWavePhase == .boss ? t(game, "BOSS", "首领") : t(game, "COMBAT", "战斗"))
            : t(game, "STAGE", "关卡") + " \(game.stage)"
        text(r, progressLabel, 190, 16, UITheme.Color.primary)
        drawRightText(r, t(game, "SCORE", "分数") + " \(game.score)", right: Float(width - 16), y: 16, color: UITheme.Color.warning)
        drawRightText(r, t(game, "KILLS", "击杀") + " \(game.kills)", right: Float(width - 196), y: 16, color: UITheme.Color.boss)

        let healthRatio = game.health / max(1, game.maxHealth)
        progress(r, UIProgressBar(rect: UIRect(x: 18, y: 39, width: 166, height: 10),
                                  value: game.healthLag / max(1, game.maxHealth),
                                  fill: RenderColor(255, 171, 93, game.healthBarFlash > 0 ? 245 : 165),
                                  back: RenderColor(61, 28, 53)), height: 10)
        progress(r, UIProgressBar(rect: UIRect(x: 18, y: 39, width: 166, height: 10),
                                  value: healthRatio, fill: UITheme.Color.danger, back: RenderColor(0, 0, 0, 0)), height: 10)
        text(r, t(game, "HP", "生命") + " \(Int(game.health))/\(Int(game.maxHealth))", 22, 42, UITheme.Color.text)

        let shieldValue = game.pickupShieldCharges > 0 ? 1.0 : min(1, Double(game.armorShieldCharges) / 3.0)
        progress(r, UIProgressBar(rect: UIRect(x: 198, y: 39, width: 104, height: 10), value: shieldValue,
                                  fill: UITheme.Color.shield, back: RenderColor(22, 56, 79)), height: 10)
        text(r, game.pickupShieldCharges > 0 ? t(game, "AEGIS x1", "壁垒 x1") : t(game, "SHIELD", "护盾") + " x\(game.armorShieldCharges)", 202, 42, UITheme.Color.shield)

        progress(r, UIProgressBar(rect: UIRect(x: 318, y: 39, width: 170, height: 10),
                                  value: Double(game.experience) / Double(max(1, game.experienceGoal)),
                                  fill: UITheme.Color.energy, back: RenderColor(22, 56, 79)), height: 10)
        text(r, t(game, "XP", "经验"), 324, 42, UITheme.Color.text)

        let thunderReady = game.thunderEnergy >= CombatConfig.thunderOverloadCost
        let thunderBurstReady = game.thunderEnergy >= CombatConfig.thunderBurstCost
        progress(r, UIProgressBar(rect: UIRect(x: 505, y: 39, width: 124, height: 10),
                                  value: game.thunderEnergy / 100,
                                  fill: thunderReady ? UITheme.Color.warning : UITheme.Color.energy,
                                  back: RenderColor(22, 56, 79)), height: 10)
        let thunderLabel: String
        if thunderReady {
            thunderLabel = t(game, "OVERLOAD READY", "超载就绪")
        } else if thunderBurstReady {
            thunderLabel = t(game, "BURST READY", "爆发就绪")
        } else {
            thunderLabel = t(game, "THUNDER", "雷霆") + " \(Int(game.thunderEnergy))%"
        }
        text(r, thunderLabel, 511, 42, thunderReady ? UITheme.Color.warning : (thunderBurstReady ? UITheme.Color.primary : UITheme.Color.energy))

        // Persistent combat attributes belong in the HUD, not behind the
        // pause overlay.  Keep this compact row left of boss and timed-effect
        // panels so it never occupies the central dodge space.
        let weaponSummary = game.weaponType.label(for: game.language) + "  Lv.\(game.weaponLevel)"
        text(r, weaponSummary, 18, 60, UITheme.Color.text)
        text(r, t(game, "SHOTS", "弹幕") + " +\(game.projectileCountBonus)", 198, 60, UITheme.Color.secondary)
        text(r, t(game, "PIERCE", "穿透") + " +\(game.projectilePenetration)", 338, 60, UITheme.Color.secondary)
        text(r, t(game, "CRIT", "暴击") + " \(Int(game.criticalChance * 100))%", 475, 60, UITheme.Color.warning)
        let dashLabel = game.dashCooldown <= 0.05
            ? t(game, "DASH READY", "闪避就绪")
            : t(game, "DASH", "闪避") + " \(Int(ceil(game.dashCooldown)))s"
        text(r, dashLabel, 620, 60, game.dashCooldown <= 0.05 ? UITheme.Color.success : UITheme.Color.muted)

        if game.combo > 1 { text(r, t(game, "COMBO", "连击") + " x\(game.combo)", 650, 16, UITheme.Color.warning) }
        if let comboBurst = game.combatFeedback.comboFeedback {
            let life = max(0, min(1, 1 - comboBurst.elapsed / 0.9))
            let burstColor = color(comboBurst.tint)
            let label = "\(comboBurst.count) " + t(game, "COMBO!", "连击!")
            text(r, label, Float(width / 2 - 42), Float(field.top + 58 - comboBurst.elapsed * 24),
                 RenderColor(burstColor.red, burstColor.green, burstColor.blue, UInt8(255 * life)))
        }

        if let boss = game.boss {
            let ratio = boss.health / max(1, boss.maxHealth)
            let barX = width / 2 - 220
            progress(r, UIProgressBar(rect: UIRect(x: Double(barX), y: 92, width: 440, height: 10),
                                      value: ratio, fill: UITheme.Color.boss, back: RenderColor(56, 24, 67)), height: 10)
            r.fillRect(RenderRect(x: Float(barX + Int(440 * 0.30)), y: 90, width: 2, height: 14), color: UITheme.Color.warning)
            r.fillRect(RenderRect(x: Float(barX + Int(440 * 0.70)), y: 90, width: 2, height: 14), color: UITheme.Color.warning)
            let bossName = BossType(rawValue: boss.kind)?.title(for: game.language) ?? t(game, "DREADNOUGHT", "无畏战舰")
            text(r, t(game, "BOSS", "首领") + "  " + bossName + "  •  " + t(game, "PHASE", "阶段") + " \(boss.phase)",
                 Float(width / 2 - 135), 95, UITheme.Color.text)
            let leftRatio = boss.leftTurretHealth / max(1, boss.leftTurretMaxHealth)
            let rightRatio = boss.rightTurretHealth / max(1, boss.rightTurretMaxHealth)
            text(r, t(game, "L-TURRET", "左炮塔") + " \(Int(leftRatio * 100))%", Float(width / 2 - 218), 112,
                 boss.leftTurretHealth > 0 ? UITheme.Color.secondary : UITheme.Color.muted)
            text(r, t(game, "R-TURRET", "右炮塔") + " \(Int(rightRatio * 100))%", Float(width / 2 + 108), 112,
                 boss.rightTurretHealth > 0 ? UITheme.Color.secondary : UITheme.Color.muted)
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
            text(r, stateLabel, Float(width / 2 - 72), 112,
                 boss.weakPointOpen ? UITheme.Color.energy : (boss.attackStage == .telegraph ? UITheme.Color.danger : UITheme.Color.muted))
        }
        if game.survivalTime < 8 {
            let hint = t(game, "WASD / ARROWS MOVE  •  SHIFT PRECISION  •  SPACE OVERLOAD", "WASD / 方向键移动  •  Shift 精准  •  Space 超载")
            text(r, hint, 18, Float(field.bottom - 24), UITheme.Color.muted)
        }
    }

    private static func drawMenu(_ r: GameRenderer, game: Game, width: Int, height: Int) {
        panel(r, x: 32, y: 32, width: width - 64, height: height - 64)
        r.fillRect(RenderRect(x: 33, y: 33, width: Float(width - 66), height: 4), color: UITheme.Color.primaryDeep)
        styledText(r, t(game, "THUNDER SWIFT", "雷霆疾影"), x: 64, y: 68, role: .display)
        styledText(r, t(game, "TACTICAL SORTIE CONTROL", "战术出击控制系统"), x: 64, y: 103, role: .sectionTitle, color: UITheme.Color.primary)
        styledText(r, t(game, "LOCAL PILOT TERMINAL  •  SYSTEM READY", "本地飞行员终端  •  系统就绪"), x: 64, y: 132, role: .caption)
        drawRightText(r, t(game, "SDL3 BUILD", "SDL3 版本") + "  //  ONLINE", right: Float(width - 64), y: 74, color: UITheme.Color.success)
        drawRightText(r, t(game, "SLOT", "存档") + " \(SaveManager.shared.activeSlot + 1)  •  " + t(game, "AUTO-SAVE", "自动保存"),
                      right: Float(width - 64), y: 105, color: UITheme.Color.secondary)

        let leftWidth = Int(max(300, Double(width) * 0.34))
        let rightX = Int(Double(width) * 0.43) - 16
        panel(r, x: 56, y: 170, width: leftWidth + 16, height: 346)
        sectionHeader(r, title: t(game, "PILOT STATUS", "飞行员状态"), subtitle: t(game, "CAREER OVERVIEW", "生涯概览"), x: 76, y: 194, width: leftWidth - 24)
        let tileWidth = max(128, (leftWidth - 40) / 2)
        drawStatTile(r, x: 76, y: 232, width: tileWidth, height: 86,
                     label: t(game, "COMBAT POWER", "当前战力"), value: "\(game.combatPower())", tint: UITheme.Color.warning)
        drawStatTile(r, x: 88 + tileWidth, y: 232, width: tileWidth, height: 86,
                     label: t(game, "BEST SCORE", "最高分"), value: "\(game.profile.bestScore)", tint: UITheme.Color.primary)
        drawStatTile(r, x: 76, y: 330, width: tileWidth, height: 86,
                     label: t(game, "BEST COMBO", "最高连击"), value: "×\(game.profile.bestCombo)", tint: UITheme.Color.energy)
        drawStatTile(r, x: 88 + tileWidth, y: 330, width: tileWidth, height: 86,
                     label: t(game, "BOSSES DOWN", "击破首领"), value: "\(game.profile.totalBosses)", tint: UITheme.Color.boss)
        text(r, t(game, "FLIGHT RECORD", "出击记录") + "  \(game.profile.totalRuns)", 78, 451, UITheme.Color.secondary)
        text(r, t(game, "CAMPAIGN SECTOR", "战役进度") + "  \(game.profile.unlockedMission)/\(MissionCatalog.all.count)", 78, 478, UITheme.Color.secondary)

        panel(r, x: rightX, y: 170, width: width - rightX - 56, height: 326)
        sectionHeader(r, title: t(game, "OPERATIONS", "作战操作"), subtitle: t(game, "SELECT A SYSTEM", "选择功能"), x: rightX + 18, y: 194, width: width - rightX - 92)

        let buttons = mainMenuButtons(width: Double(width), height: Double(height))
        let labels = [t(game, "01  START SORTIE", "01  开始出击"), t(game, "02  HOW TO PLAY", "02  操作说明"),
                      t(game, "03  HANGAR", "03  机库整备"), t(game, "04  SETTINGS", "04  系统设置"),
                      t(game, "06  EXIT GAME", "06  退出游戏"), t(game, "05  ARCHIVE", "05  档案馆")]
        for i in buttons.indices { button(r, buttons[i], title: labels[i], selected: false, emphasis: i == 0) }

        let saveButton = saveSlotButton(width: Double(width), height: Double(height))
        button(r, saveButton, title: "", selected: false)
        text(r, t(game, "PILOT DATA", "飞行员存档") + "  //  " + t(game, "SLOT", "存档") + " \(SaveManager.shared.activeSlot + 1)",
             Float(saveButton.x + 18), Float(saveButton.y + 15), UITheme.Color.text)
        text(r, t(game, "Open save manager", "打开存档管理") + "  •  JSON + BACKUP",
             Float(saveButton.x + 18), Float(saveButton.y + 39), UITheme.Color.muted)

        let resourcesX = rightX
        let resourcesWidth = width - rightX - 56
        panel(r, x: resourcesX, y: 516, width: resourcesWidth, height: 86)
        let resourceWidth = (resourcesWidth - 44) / 3
        drawStatTile(r, x: resourcesX + 10, y: 526, width: resourceWidth, height: 66,
                     label: t(game, "CREDITS", "金币"), value: "\(game.profile.credits)", tint: UITheme.Color.warning)
        drawStatTile(r, x: resourcesX + 17 + resourceWidth, y: 526, width: resourceWidth, height: 66,
                     label: t(game, "CORES", "核心"), value: "\(game.profile.cores)", tint: UITheme.Color.energy)
        drawStatTile(r, x: resourcesX + 24 + resourceWidth * 2, y: 526, width: resourceWidth, height: 66,
                     label: t(game, "ALLOY", "合金"), value: "\(game.profile.alloy)", tint: UITheme.Color.secondary)

        r.line(from: (64, 628), to: (Float(width - 64), 628), color: UITheme.Color.border)
        text(r, t(game, "ENTER / LEFT CLICK  CONFIRM", "Enter / 鼠标左键确认"), 64, 647, UITheme.Color.muted)
        drawRightText(r, t(game, "ESC  BACK", "Esc  返回"), right: Float(width - 64), y: 647, color: UITheme.Color.muted)
    }

    private static func drawSaveSlots(_ r: GameRenderer, game: Game, width: Int, height: Int) {
        panel(r, x: width / 2 - 455, y: 58, width: 910, height: height - 105)
        centeredText(r, t(game, "SAVE SELECT // PILOT DATA", "选择存档 // 飞行员数据"), centerX: Float(width / 2), y: 90, role: .pageTitle, shadow: true)
        centeredText(r, t(game, "Choose a slot to continue. Progress is stored beside the game.", "选择一个存档继续，进度保存在游戏根目录。"), centerX: Float(width / 2), y: 122, role: .secondary)
        let summaries = SaveManager.shared.slotSummaries()
        for (i, card) in saveSlotCards(width: Double(width), height: Double(height)).enumerated() {
            button(r, card, title: "", selected: i == SaveManager.shared.activeSlot)
            text(r, t(game, "SLOT", "存档") + " \(i + 1)", Float(card.x + 14), Float(card.y + 7), UITheme.Color.text)
            guard summaries.indices.contains(i) else { continue }
            let summary = summaries[i]
            if let profile = summary.profile {
                let active = i == SaveManager.shared.activeSlot
                text(r, active ? t(game, "ACTIVE", "当前使用") : t(game, "READY", "可用"), Float(card.x + 14), Float(card.y + 20), active ? UITheme.Color.success : UITheme.Color.secondary)
                text(r, t(game, "SECTOR", "区域") + " \(profile.unlockedMission)", Float(card.x + 14), Float(card.y + 48), UITheme.Color.text)
                text(r, t(game, "POWER", "战力") + "  \(profileCombatPower(profile))", Float(card.x + 14), Float(card.y + 72), UITheme.Color.warning)
                text(r, t(game, "RUNS", "出击") + "  \(profile.totalRuns)", Float(card.x + 14), Float(card.y + 96), UITheme.Color.secondary)
                text(r, t(game, "BEST", "最高分") + "  \(profile.bestScore)", Float(card.x + 14), Float(card.y + 120), UITheme.Color.secondary)
            } else {
                text(r, t(game, "EMPTY SLOT", "空存档"), Float(card.x + 14), Float(card.y + 54), UITheme.Color.muted)
                text(r, t(game, "New pilot data will be created", "选择后将创建新的飞行员数据"), Float(card.x + 14), Float(card.y + 82), UITheme.Color.secondary)
            }
        }
        text(r, t(game, "AUTO-SAVE  •  JSON + BACKUP", "自动保存  •  JSON + 备份"), Float(width / 2 - 124), Float(height - 112), UITheme.Color.success)
        button(r, saveSlotsBackButton(width: Double(width), height: Double(height)), title: t(game, "BACK", "返回"), selected: false)
    }

    private static func drawMissionSelect(_ r: GameRenderer, game: Game, width: Int, height: Int) {
        panel(r, x: 32, y: 44, width: width - 64, height: height - 86)
        styledText(r, t(game, "MISSION SELECT // FLIGHT PLAN", "选择关卡 // 航线计划"), x: 64, y: 66, role: .pageTitle, shadow: true)
        styledText(r, t(game, "Select a sector, review drops, then launch.", "选择区域，查看掉落，然后出击。"), x: 66, y: 98, role: .secondary)
        for (i, card) in missionCards(width: Double(width), height: Double(height)).enumerated() {
            let mission = MissionCatalog.all[i]
            let unlocked = i < game.unlockedMissionCount
            button(r, card, title: unlocked ? "\(i + 1)" : "—", selected: i == game.selectedMission)
            text(r, mission.title(for: game.language), Float(card.x + 12), Float(card.y + 39), unlocked ? UITheme.Color.text : UITheme.Color.muted)
            text(r, unlocked ? t(game, "READY", "可出击") : t(game, "LOCKED", "未解锁"), Float(card.x + 12), Float(card.y + 68), unlocked ? UITheme.Color.success : UITheme.Color.muted)
            text(r, "\(mission.recommendedPower) PW", Float(card.x + card.width - 76), Float(card.y + 68), UITheme.Color.warning)
        }
        if MissionCatalog.all.indices.contains(game.selectedMission) {
            let mission = MissionCatalog.all[game.selectedMission]
            panel(r, x: 54, y: 180, width: 185, height: 260)
            text(r, t(game, "SELECTED SECTOR", "当前区域"), 68, 204, UITheme.Color.primary)
            text(r, mission.title(for: game.language), 68, 235, UITheme.Color.text)
            drawWrappedText(r, mission.description(for: game.language), x: 68, y: 268, color: UITheme.Color.secondary, maxWidth: 154, lineHeight: 18, maxLines: 2)
            text(r, t(game, "DURATION", "时长") + "  \(Int(mission.duration))s", 68, 318, UITheme.Color.muted)
            text(r, t(game, "BOSS", "首领") + "  \(Int(mission.bossTime))s", 68, 342, UITheme.Color.boss)
            let powerDelta = game.combatPower() - mission.recommendedPower
            text(r, t(game, "YOUR POWER", "当前战力") + "  \(game.combatPower())", 68, 364, UITheme.Color.warning)
            text(r, powerDelta >= 0 ? t(game, "ADVANTAGE", "优势") : t(game, "CHALLENGE", "挑战"), 68, 388, powerDelta >= 0 ? UITheme.Color.success : UITheme.Color.danger)
            text(r, t(game, "DROPS", "掉落") + "  " + missionDropSummary(mission.id, game: game), 68, 412, UITheme.Color.secondary)
        }
        for (i, card) in modeCards(width: Double(width), height: Double(height)).enumerated() {
            let mode = GameMode(rawValue: i) ?? .campaign
            button(r, card, title: mode.label(for: game.language), selected: i == game.gameMode.rawValue)
            drawWrappedText(r, mode.description(for: game.language), x: Float(card.x + 10), y: Float(card.y + 52), color: UITheme.Color.secondary, maxWidth: Float(card.width - 20), lineHeight: 14, maxLines: 1)
        }
        text(r, t(game, "MODE", "模式"), 260, 414, UITheme.Color.muted)
        button(r, missionLaunchButton(width: Double(width), height: Double(height)), title: t(game, "LAUNCH", "出击"), selected: false, emphasis: true)
        button(r, missionBackButton(width: Double(width), height: Double(height)), title: t(game, "BACK", "返回"), selected: false)
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
                     label: t(game, "SWITCH WEAPON", "切换武器"), value: "Q", tint: UITheme.Color.boss)
        drawStatTile(r, x: width / 2 + 15, y: 402, width: 245, height: 84,
                     label: t(game, "PAUSE / BACK", "暂停 / 返回"), value: "ESC", tint: UITheme.Color.secondary)
        centeredText(r, t(game, "Hold Shift to slow down and reveal the real hitbox.", "按住 Shift 可降低移动速度，并显示战机的真实碰撞核心。"),
                     centerX: Float(width / 2), y: 514, role: .secondary)
        button(r, controlsBackButton(width: Double(width), height: Double(height)), title: t(game, "BACK", "返回"), selected: false)
    }

    private static func drawSettings(_ r: GameRenderer, game: Game, width: Int, height: Int) {
        panel(r, x: width / 2 - 320, y: 44, width: 640, height: height - 78)
        centeredText(r, t(game, "SETTINGS", "设置"), centerX: Float(width / 2), y: 70, role: .pageTitle, shadow: true)
        centeredText(r, t(game, "Presentation and accessibility", "画面与可读性设置"), centerX: Float(width / 2), y: 102, role: .secondary)
        text(r, t(game, "LANGUAGE", "语言"), Float(width / 2 - 230), 140, UITheme.Color.secondary)
        let language = settingsLanguageButtons(width: Double(width), height: Double(height))
        button(r, language[0], title: t(game, "ENGLISH", "英文"), selected: game.language == .english)
        button(r, language[1], title: t(game, "CHINESE", "中文"), selected: game.language == .chinese)
        text(r, t(game, "AUDIO", "音频"), Float(width / 2 - 230), 226, UITheme.Color.secondary)
        button(r, settingsBGMButton(width: Double(width), height: Double(height)), title: "BGM \(game.profile.bgmVolume)%", selected: false)
        button(r, settingsSFXButton(width: Double(width), height: Double(height)), title: "SFX \(game.profile.sfxVolume)%", selected: false)
        text(r, t(game, "ACCESSIBILITY", "辅助选项"), Float(width / 2 - 230), 302, UITheme.Color.secondary)
        let shakeNames = [t(game, "OFF", "关闭"), t(game, "LOW", "低"), t(game, "MEDIUM", "中"), t(game, "HIGH", "高")]
        let shakeValue = shakeNames[min(max(0, game.profile.cameraShake), shakeNames.count - 1)]
        button(r, settingsShakeButton(width: Double(width), height: Double(height)), title: t(game, "CAMERA SHAKE", "镜头震动") + ": " + shakeValue, selected: false)
        text(r, t(game, "DISPLAY", "显示"), Float(width / 2 - 230), 374, UITheme.Color.secondary)
        button(r, settingsWindowModeButton(width: Double(width), height: Double(height)), title: game.profile.isFullscreen ? t(game, "DISPLAY: FULLSCREEN", "显示：全屏") : t(game, "DISPLAY: WINDOWED", "显示：窗口化"), selected: false)
        button(r, settingsResolutionButton(width: Double(width), height: Double(height)), title: t(game, "RESOLUTION", "分辨率") + ": \(game.profile.resolutionWidth)x\(game.profile.resolutionHeight)", selected: false)
        text(r, t(game, "INTERFACE", "界面"), Float(width / 2 - 230), 506, UITheme.Color.secondary)
        button(r, settingsUIScaleButton(width: Double(width), height: Double(height)), title: t(game, "UI SCALE", "界面缩放") + ": \(game.profile.uiScale)%", selected: false)
        text(r, t(game, "Changes apply immediately and are saved automatically.", "设置会立即生效并自动保存。"), Float(width / 2 - 190), 584, UITheme.Color.muted)
        button(r, settingsBackButton(width: Double(width), height: Double(height)), title: t(game, "BACK", "返回"), selected: false)
    }

    private static func drawHangar(_ r: GameRenderer, game: Game, width: Int, height: Int) {
        panel(r, x: 32, y: 32, width: width - 64, height: height - 64)
        styledText(r, t(game, "HANGAR / LOADOUT", "机库 / 装备"), x: 64, y: 64, role: .pageTitle, shadow: true)
        styledText(r, t(game, "AIRFRAME CONFIGURATION", "机体配置台"), x: 66, y: 96, role: .secondary)
        text(r, t(game, "POWER", "战力") + "  \(game.combatPower())", Float(width - 250), 70, UITheme.Color.warning)
        let resourceSummary = t(game, "CREDITS", "金币") + " \(game.profile.credits)   " + t(game, "CORES", "核心") + " \(game.profile.cores)"
        text(r, resourceSummary, Float(width - 390), 96, UITheme.Color.secondary)

        drawShip(r, center: (x: 156, y: 282), scale: 2.2, accent: UITheme.Color.primary)
        text(r, t(game, "SELECT AIRFRAME", "选择机体"), 76, 406, UITheme.Color.muted)
        for (i, card) in shipCards(width: Double(width), height: Double(height)).enumerated() {
            let ship = ShipType(rawValue: i) ?? .thunder
            button(r, card, title: ship.label(for: game.language), selected: ship == game.shipType)
        }
        for (i, tab) in hangarTabButtons(width: Double(width), height: Double(height)).enumerated() { button(r, tab, title: i == 0 ? t(game, "EQUIPMENT", "装备") : t(game, "VAULT", "仓库"), selected: i == game.hangarTab) }
        if game.hangarTab == 0 {
            var hoveredItem: EquipmentState?
            for (i, card) in hangarCards(width: Double(width), height: Double(height)).enumerated() {
                guard game.profile.equipment.indices.contains(i) else { continue }
                let item = game.profile.equipment[i]
                button(r, card, title: game.equipmentDisplayName(item), selected: i == game.selectedEquipmentSlot)
                if card.contains(UIInteraction.pointer) { hoveredItem = item }
                styledText(r, equipmentSlotName(game, item.slot), x: Float(card.x + 12), y: Float(card.y + 12), role: .label,
                           color: i == game.selectedEquipmentSlot ? UITheme.Color.primary : UITheme.Color.muted)
                text(r, game.equipmentQualityName(item.rarity) + "  ★\(item.stars)", Float(card.x + 12), Float(card.y + 38), color(equipmentRarityColor(item.rarity)))
                text(r, "Lv.\(item.level)  •  PW \(equipmentPower(item))", Float(card.x + 12), Float(card.y + 78), UITheme.Color.secondary)
                drawRightText(r, item.locked ? "◆" : "◇", right: Float(card.x + card.width - 12), y: Float(card.y + 12),
                              color: item.locked ? UITheme.Color.warning : UITheme.Color.muted)
            }
            let selectedIndex = min(max(0, game.selectedEquipmentSlot), max(0, game.profile.equipment.count - 1))
            if game.profile.equipment.indices.contains(selectedIndex) {
                let selected = game.profile.equipment[selectedIndex]
                drawEquipmentInspector(r, game: game, item: selected, x: width - 275, y: 180, width: 210, height: 275)
                button(r, hangarUpgradeButton(width: Double(width), height: Double(height)), title: t(game, "UPGRADE", "强化"), selected: false, emphasis: true)
                button(r, hangarBatchUpgradeButton(width: Double(width), height: Double(height)), title: t(game, "UPGRADE ×5", "强化 ×5"), selected: false)
                button(r, hangarPromoteButton(width: Double(width), height: Double(height)),
                       title: selected.rarity >= 4 ? t(game, "MAX QUALITY", "已达最高品质") : t(game, "PROMOTE QUALITY", "品质进阶"), selected: false)
                button(r, hangarLockButton(width: Double(width), height: Double(height)),
                       title: selected.locked ? t(game, "UNLOCK MODULE", "解除锁定") : t(game, "LOCK MODULE", "锁定装备"), selected: false)
            }
            if let hoveredItem { drawTooltip(r, game: game, item: hoveredItem, width: width, height: height) }
            styledText(r, t(game, "Select a module, review its cost, then choose an action.", "先选择装备并确认属性与消耗，再执行强化或进阶。"),
                       x: 292, y: 466, role: .caption)
            if game.profile.equipment.indices.contains(selectedIndex) {
                let selected = game.profile.equipment[selectedIndex]
                let cost = game.equipmentPromoteCost(for: selected)
                styledText(r, t(game, "NEXT LEVEL", "下一级") + "  \(equipmentShortCost(game, selected))  •  CORE \(game.equipmentCoreCost(for: selected))",
                           x: 292, y: 444, role: .label, color: UITheme.Color.warning)
                if selected.rarity < 4 {
                    styledText(r, t(game, "PROMOTION", "品质进阶") + "  \(cost.credits) C / \(cost.alloy) A / \(cost.cores) CORE",
                               x: 600, y: 444, role: .label, color: UITheme.Color.boss)
                }
            }
        } else {
            button(r, vaultFilterButton(width: Double(width), height: Double(height)), title: vaultFilterTitle(game), selected: false)
            button(r, vaultSortButton(width: Double(width), height: Double(height)), title: vaultSortTitle(game), selected: false)
            button(r, vaultPrevButton(width: Double(width), height: Double(height)), title: "<", selected: false)
            button(r, vaultNextButton(width: Double(width), height: Double(height)), title: ">", selected: false)
            text(r, "\(game.vaultPage + 1)/\(game.vaultPageCount)", Float(width / 2 + 205), 154, UITheme.Color.muted)
            var hoveredVaultItem: EquipmentState?
            for (i, card) in vaultCards(width: Double(width), height: Double(height)).enumerated() {
                let visible = game.visibleVaultIndices
                let absoluteIndex = game.vaultPage * 4 + i
                if visible.indices.contains(absoluteIndex) {
                    let item = game.profile.inventory[visible[absoluteIndex]]
                    let inventoryIndex = visible[absoluteIndex]
                    button(r, card, title: game.equipmentDisplayName(item), selected: inventoryIndex == game.selectedVaultInventoryIndex)
                    if card.contains(UIInteraction.pointer) { hoveredVaultItem = item }
                    text(r, game.equipmentQualityName(item.rarity) + "  Lv.\(item.level)  ★\(item.stars)", Float(card.x + 12), Float(card.y + 38), color(equipmentRarityColor(item.rarity)))
                    text(r, equipmentSlotName(game, item.slot) + "  •  PW \(equipmentPower(item))", Float(card.x + 12), Float(card.y + 78), UITheme.Color.secondary)
                    drawRightText(r, item.locked ? "◆" : "◇", right: Float(card.x + card.width - 12), y: Float(card.y + 12),
                                  color: item.locked ? UITheme.Color.warning : UITheme.Color.muted)
                } else {
                    r.fillRect(RenderRect(x: Float(card.x), y: Float(card.y), width: Float(card.width), height: Float(card.height)), color: RenderColor(15, 29, 49, 190))
                    text(r, t(game, "EMPTY SLOT", "空槽位"), Float(card.x + 14), Float(card.y + 48), UITheme.Color.muted)
                }
            }
            let selectedCandidate = game.selectedVaultInventoryIndex.flatMap { game.profile.inventory.indices.contains($0) ? game.profile.inventory[$0] : nil }
            if let candidate = selectedCandidate ?? hoveredVaultItem {
                drawEquipmentCompare(r, game: game, candidate: candidate, x: width - 275, y: 180, width: 210, height: 295)
            }
            if let selectedCandidate {
                let equipped = game.profile.equipment.contains(where: { $0.id == selectedCandidate.id })
                button(r, vaultEquipButton(width: Double(width), height: Double(height)),
                       title: equipped ? t(game, "CURRENTLY EQUIPPED", "当前已装备") : t(game, "EQUIP MODULE", "装备此模块"), selected: false, emphasis: !equipped)
                button(r, vaultSelectedLockButton(width: Double(width), height: Double(height)),
                       title: selectedCandidate.locked ? t(game, "UNLOCK MODULE", "解除锁定") : t(game, "LOCK MODULE", "锁定装备"), selected: false)
            }
            if let hoveredVaultItem { drawTooltip(r, game: game, item: hoveredVaultItem, width: width, height: height) }
        }
        button(r, hangarBackButton(width: Double(width), height: Double(height)), title: t(game, "BACK", "返回"), selected: false)
        if game.hangarMessageTimer > 0 {
            let alpha = notificationAlpha(game.hangarMessageTimer, fullDuration: 2.4)
            let titleColor = RenderColor(UITheme.Color.success.red, UITheme.Color.success.green, UITheme.Color.success.blue, alpha)
            let detailColor = RenderColor(UITheme.Color.secondary.red, UITheme.Color.secondary.green, UITheme.Color.secondary.blue, alpha)
            r.fillRect(RenderRect(x: 54, y: 568, width: 465, height: 54), color: RenderColor(8, 18, 34, UInt8(Double(alpha) * 0.88)))
            text(r, game.hangarMessageTitle, 66, 582, titleColor)
            drawWrappedText(r, game.hangarMessageDetail, x: 66, y: 604, color: detailColor, maxWidth: 440, lineHeight: 16, maxLines: 1)
        }
    }

    private static func drawEquipmentInspector(_ r: GameRenderer, game: Game, item: EquipmentState, x: Int, y: Int, width: Int, height: Int) {
        panel(r, x: x, y: y, width: width, height: height)
        text(r, t(game, "MODULE INSPECTOR", "模块信息"), Float(x + 14), Float(y + 22), UITheme.Color.primary)
        text(r, game.equipmentDisplayName(item), Float(x + 14), Float(y + 52), UITheme.Color.text)
        text(r, game.equipmentQualityName(item.rarity) + "  ★\(item.stars)", Float(x + 14), Float(y + 76), color(equipmentRarityColor(item.rarity)))
        text(r, "Lv. \(item.level)   •   \(t(game, "POWER", "战力")) \(equipmentPower(item))", Float(x + 14), Float(y + 100), UITheme.Color.warning)
        text(r, t(game, "PRIMARY STAT", "主要属性"), Float(x + 14), Float(y + 132), UITheme.Color.muted)
        text(r, equipmentShortStat(game, item), Float(x + 14), Float(y + 154), UITheme.Color.text)
        text(r, t(game, "AFFIX", "词条") + "  " + equipmentShortAffix(game, item), Float(x + 14), Float(y + 178), UITheme.Color.secondary)
        text(r, t(game, "UPGRADE", "强化") + "  " + equipmentShortCost(game, item), Float(x + 14), Float(y + 210), UITheme.Color.secondary)
        text(r, item.locked ? t(game, "LOCKED • SAFE", "已锁定 • 安全") : t(game, "UNLOCKED", "未锁定"), Float(x + 14), Float(y + 244), item.locked ? UITheme.Color.warning : UITheme.Color.muted)
    }

    private static func drawEquipmentCompare(_ r: GameRenderer, game: Game, candidate: EquipmentState, x: Int, y: Int, width: Int, height: Int) {
        panel(r, x: x, y: y, width: width, height: height)
        text(r, t(game, "LOADOUT COMPARE", "配置比较"), Float(x + 14), Float(y + 22), UITheme.Color.primary)
        let current = game.profile.equipment.first(where: { $0.slot == candidate.slot })
        text(r, t(game, "CURRENT", "当前"), Float(x + 14), Float(y + 50), UITheme.Color.muted)
        text(r, current.map { game.equipmentDisplayName($0) } ?? t(game, "EMPTY", "空"), Float(x + 14), Float(y + 72), UITheme.Color.text)
        text(r, t(game, "CANDIDATE", "候选"), Float(x + 14), Float(y + 103), UITheme.Color.muted)
        text(r, game.equipmentDisplayName(candidate), Float(x + 14), Float(y + 125), UITheme.Color.text)
        let delta = equipmentPower(candidate) - (current.map(equipmentPower) ?? 0)
        let deltaText = (delta >= 0 ? "+" : "") + "\(delta)"
        text(r, t(game, "POWER DELTA", "战力变化") + "  " + deltaText, Float(x + 14), Float(y + 160), delta >= 0 ? UITheme.Color.success : UITheme.Color.danger)
        text(r, equipmentShortStat(game, candidate), Float(x + 14), Float(y + 190), UITheme.Color.secondary)
        text(r, candidate.locked ? t(game, "LOCKED", "已锁定") : t(game, "CLICK TO EQUIP", "点击装备"), Float(x + 14), Float(y + 230), candidate.locked ? UITheme.Color.warning : UITheme.Color.primary)
    }

    private static func drawTooltip(_ r: GameRenderer, game: Game, item: EquipmentState, width: Int, height: Int) {
        let tooltipWidth = 276
        let x = Int(min(max(12, UIInteraction.pointer.x + 16), Double(width - tooltipWidth - 12)))
        let y = Int(min(max(60, UIInteraction.pointer.y + 16), Double(height - 126)))
        panel(r, x: x, y: y, width: tooltipWidth, height: 126)
        text(r, game.equipmentDisplayName(item), Float(x + 12), Float(y + 22), UITheme.Color.text)
        text(r, game.equipmentQualityName(item.rarity) + "  •  Lv. \(item.level)  •  ★\(item.stars)", Float(x + 12), Float(y + 46), color(equipmentRarityColor(item.rarity)))
        text(r, equipmentShortStat(game, item), Float(x + 12), Float(y + 70), UITheme.Color.secondary)
        drawWrappedText(r, t(game, "Effect: ", "效果：") + equipmentShortAffix(game, item), x: Float(x + 12), y: Float(y + 92), color: UITheme.Color.muted, maxWidth: 248, lineHeight: 16, maxLines: 2)
    }

    private static func equipmentPower(_ item: EquipmentState) -> Int {
        100 + item.level * 18 + item.rarity * 24 + item.stars * 12 + item.evolution * 75
    }

    private static func profileCombatPower(_ profile: PlayerProfile) -> Int {
        var value = 100
        for item in profile.equipment {
            value += item.level * 18
            value += item.rarity * 24
            value += item.stars * 12
            value += item.evolution * 75
        }
        value += (ShipType(rawValue: profile.selectedShip) ?? .thunder).rawValue * 20
        value += profile.totalBosses * 12
        return value
    }

    private static func equipmentShortStat(_ game: Game, _ item: EquipmentState) -> String {
        switch item.slot {
        case 0: return t(game, "MAX HP +8 / LV", "最大生命 +8 / 级")
        case 1: return t(game, "WEAPON DMG +1.5 / LV", "武器伤害 +1.5 / 级")
        case 2: return t(game, "SECONDARY RATE +0.12", "副武器频率 +0.12")
        case 3: return t(game, "MAX HP +4 / LV", "最大生命 +4 / 级")
        default: return t(game, "DRONE DMG +0.6 / LV", "僚机伤害 +0.6 / 级")
        }
    }

    private static func equipmentSlotName(_ game: Game, _ slot: Int) -> String {
        let names = [t(game, "AIRFRAME", "战机机框"), t(game, "PRIMARY", "主武器"), t(game, "SECONDARY", "副武器"),
                     t(game, "ARMOR", "装甲"), t(game, "DRONE", "僚机")]
        return names.indices.contains(slot) ? names[slot] : t(game, "MODULE", "模块")
    }

    private static func equipmentShortAffix(_ game: Game, _ item: EquipmentState) -> String {
        switch item.affix {
        case 1: return t(game, "DAMAGE +10%", "伤害 +10%")
        case 2: return t(game, "CRIT +5%", "暴击 +5%")
        case 3: return t(game, "FIRE RATE +10%", "射速 +10%")
        case 4: return t(game, "DAMAGE TAKEN -6%", "所受伤害 -6%")
        default: return t(game, "STABLE CORE", "稳定核心")
        }
    }

    private static func equipmentShortCost(_ game: Game, _ item: EquipmentState) -> String {
        "\(game.equipmentUpgradeCost(for: item)) C  /  \(game.equipmentAlloyCost(for: item)) A"
    }

    private static func vaultFilterTitle(_ game: Game) -> String {
        if let slot = game.vaultFilterSlot {
            let names = [t(game, "FRAME", "机体"), t(game, "PRIMARY", "主武器"), t(game, "SECONDARY", "副武器"), t(game, "ARMOR", "装甲"), t(game, "DRONE", "僚机")]
            return t(game, "FILTER", "筛选") + ": " + (names.indices.contains(slot) ? names[slot] : t(game, "ALL", "全部"))
        }
        return t(game, "FILTER", "筛选") + ": " + t(game, "ALL", "全部")
    }

    private static func vaultSortTitle(_ game: Game) -> String {
        let names = [t(game, "RARITY", "品质"), t(game, "LEVEL", "等级"), t(game, "SLOT", "槽位")]
        return t(game, "SORT", "排序") + ": " + names[min(max(0, game.vaultSortMode), names.count - 1)]
    }

    private static func missionDropSummary(_ missionID: Int, game: Game) -> String {
        switch missionID {
        case 1: return t(game, "CREDITS • CORES", "金币 • 核心")
        case 2: return t(game, "CORES • ARMOR", "核心 • 装甲")
        case 3: return t(game, "ALLOY • PRIMARY", "合金 • 主武器")
        case 4: return t(game, "CORES • DRONE", "核心 • 僚机")
        case 5: return t(game, "ALLOY • ARMOR", "合金 • 装甲")
        default: return t(game, "RARE MODULES", "稀有模块")
        }
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
        if !game.runRareDropName.isEmpty {
            let dropName = localizedDropName(game.runRareDropName, game: game)
            text(r, t(game, "RARE MODULE", "稀有模块") + "  •  " + dropName + "  •  " + game.equipmentQualityName(game.runRareDropRarity), Float(width / 2 - 188), Float(height / 2 + 64), UITheme.Color.boss)
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

    private static func localizedDropName(_ name: String, game: Game) -> String {
        guard game.language == .chinese else { return name }
        switch name {
        case "NOVA MISSILE": return "新星导弹"
        case "FROST PLATING": return "寒霜装甲"
        case "STORM DRONE": return "风暴僚机"
        default: return name
        }
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

    private static func button(_ r: GameRenderer, _ rect: UIRect, title: String, selected: Bool, emphasis: Bool = false) {
        let component = UIButton(rect: rect, title: title, selected: selected)
        let state = UIInteraction.state(for: component.rect, selected: component.selected, enabled: component.enabled)
        let fill: RenderColor
        let border: RenderColor
        switch state {
        case .selected:
            let pulse = UIAnimationSystem.pulse(time: UIInteraction.time, speed: 3.0, amount: 0.035)
            fill = UITheme.Color.panelSelected; border = RenderColor(125, 191, 205, UInt8(min(225, 185 * pulse)))
        case .hover:
            let pulse = UIAnimationSystem.pulse(time: UIInteraction.time, speed: 4.0, amount: 0.025)
            fill = emphasis ? RenderColor(49, 113, 125, 248) : UITheme.Color.panelHover
            border = RenderColor(126, 184, 199, UInt8(min(210, 170 * pulse)))
        case .pressed:
            fill = UITheme.Color.panelSelected; border = RenderColor(UITheme.Color.warning.red, UITheme.Color.warning.green, UITheme.Color.warning.blue, 185)
        case .disabled:
            fill = RenderColor(25, 34, 49, 190); border = RenderColor(57, 70, 86, 180)
        default:
            fill = emphasis ? UITheme.Color.primaryDeep : UITheme.Color.panelRaised
            border = emphasis ? UITheme.Color.primary : UITheme.Color.border
        }
        r.fillRect(RenderRect(x: Float(rect.x), y: Float(rect.y), width: Float(rect.width), height: Float(rect.height)), color: fill)
        if emphasis || state == .hover || state == .selected {
            r.fillRect(RenderRect(x: Float(rect.x), y: Float(rect.y), width: 4, height: Float(rect.height)), color: emphasis ? UITheme.Color.energy : UITheme.Color.primary)
        }
        r.line(from: (Float(rect.x), Float(rect.y)), to: (Float(rect.x + rect.width), Float(rect.y)), color: border)
        r.line(from: (Float(rect.x), Float(rect.y + rect.height)), to: (Float(rect.x + rect.width), Float(rect.y + rect.height)), color: border)
        let labelColor = state == .disabled ? UITheme.Color.muted : UITheme.Color.text
        let titleInset: Float = emphasis ? 20 : 16
        let visibleTitle = ellipsized(component.title, maxWidth: Float(rect.width) - titleInset - 12, scale: UITextRole.body.scale)
        styledText(r, visibleTitle, x: Float(rect.x) + titleInset, y: Float(rect.y + rect.height * 0.5 - 7),
                   role: .body, color: labelColor, shadow: emphasis)
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
        r.fillRect(RenderRect(x: x + 4, y: y + 5, width: 382, height: 66), color: RenderColor(1, 5, 12, UInt8(Double(alpha) * 0.46)))
        r.fillRect(RenderRect(x: x, y: y, width: 382, height: 66), color: RenderColor(7, 17, 34, UInt8(Double(alpha) * 0.90)))
        r.fillRect(RenderRect(x: x, y: y, width: 4, height: 66), color: titleColor)
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
            let y = Float(66 + index * 34)
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

    private static func drawWrappedText(_ r: GameRenderer, _ value: String, x: Float, y: Float, color: RenderColor, maxWidth: Float, lineHeight: Float, maxLines: Int) {
        for (index, line) in wrappedLines(value, maxWidth: maxWidth, maxLines: maxLines).enumerated() {
            text(r, line, x, y + Float(index) * lineHeight, color)
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
            let advance = glyphWidth(character)
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
        value.reduce(0) { $0 + glyphWidth($1) } * scale
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
