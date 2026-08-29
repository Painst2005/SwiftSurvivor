import Foundation
import WinSDK

// MARK: - Combat feedback contract

enum FeedbackLevel: Int, Comparable {
    case light = 0
    case medium = 1
    case heavy = 2
    case critical = 3

    static func < (lhs: FeedbackLevel, rhs: FeedbackLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum CombatEvent {
    case enemyHit
    case criticalHit
    case enemyKilled
    case eliteKilled
    case playerHit
    case shieldHit
    case shieldBreak
    case bossPartDestroyed
    case bossKilled
    case playerKilled
    case comboMilestone
    case rareDrop
}

enum FeedbackDamageKind {
    case cannon, laser, missile, electromagnetic, collision, enemyBullet
}

enum FeedbackParticleKind {
    case spark, coreFlash, debris, smoke, shield, shockwave
}

struct FeedbackContext {
    var position: Vec2
    var direction: Vec2 = .zero
    var damage: Double = 0
    var level: FeedbackLevel = .light
    var targetID: Int? = nil
    var critical = false
    var overkill = false
    var damageKind: FeedbackDamageKind = .cannon
    var tint: COLORREF = rgb(255, 225, 122)
}

struct CombatFeedbackConfig {
    let normalHitFlash = 0.055
    let criticalHitFlash = 0.090
    let playerHitFlash = 0.105
    let shieldFlash = 0.085
    let damageAggregateWindow = 0.11
    let maxDamageNumbers = 90
    let lightHitSoundCooldown = 0.045
    let hitStopCritical = 0.014
    let hitStopHeavy = 0.032
    let hitStopCriticalEvent = 0.075
    let healthLagSpeed = 3.8
    let lightShake = 1.4
    let mediumShake = 3.1
    let heavyShake = 6.0
    let criticalShake = 10.5
    let maxShake = 12.0
    let maxHitParticles = 14
    let maxExplosionParticles = 68
}

private struct PendingDamage {
    var position: Vec2
    var amount: Int
    var life: Double
    var tint: COLORREF
}

struct BossDeathFeedback {
    var position: Vec2
    var tint: COLORREF
    var elapsed: Double = 0
    var burstStage = 0
}

struct ComboFeedback {
    var count: Int
    var elapsed: Double = 0
    var tint: COLORREF
}

/// Owns presentation response to combat events. Gameplay sends a concise
/// event; this system decides flash, particles, sounds, text, shake and time.
/// It intentionally contains no SDL calls.
final class CombatFeedbackSystem {
    let config = CombatFeedbackConfig()
    private var rng = SystemRandomNumberGenerator()
    private var pendingDamage: [Int: PendingDamage] = [:]
    private var hitSoundClock = 0.0
    private var lastLightHitSound = -10.0
    private(set) var cameraOffset = Vec2.zero
    private var shakeTime = 0.0
    private var shakeStrength = 0.0
    private var hitStopTime = 0.0
    private var slowMotionTime = 0.0
    private var slowMotionScale = 1.0
    private var lowHealthSmokeClock = 0.0
    private var lowHealthWarningClock = 0.0
    var bossDeath: BossDeathFeedback?
    var comboFeedback: ComboFeedback?

    func reset() {
        pendingDamage.removeAll(keepingCapacity: true)
        hitSoundClock = 0
        lastLightHitSound = -10
        cameraOffset = .zero
        shakeTime = 0
        shakeStrength = 0
        hitStopTime = 0
        slowMotionTime = 0
        slowMotionScale = 1
        lowHealthSmokeClock = 0
        lowHealthWarningClock = 0
        bossDeath = nil
        comboFeedback = nil
    }

    /// Updates feedback in real time. It returns the gameplay time step after
    /// hit-stop / slow motion have been applied; UI and particles remain live.
    func advance(realDelta: Double, game: Game) -> Double {
        hitSoundClock += realDelta
        flushDamage(realDelta: realDelta, game: game)
        updateVisualState(realDelta: realDelta, game: game)
        updateBossDeath(realDelta: realDelta, game: game)
        updateComboFeedback(realDelta: realDelta)

        shakeTime = max(0, shakeTime - realDelta)
        shakeStrength = max(0, shakeStrength - realDelta * 42)
        if shakeTime > 0, shakeStrength > 0 {
            cameraOffset = Vec2(x: Double.random(in: -shakeStrength...shakeStrength, using: &rng),
                                y: Double.random(in: -shakeStrength...shakeStrength, using: &rng))
        } else {
            cameraOffset = .zero
        }

        if hitStopTime > 0 {
            hitStopTime = max(0, hitStopTime - realDelta)
            return 0
        }
        if slowMotionTime > 0 {
            slowMotionTime = max(0, slowMotionTime - realDelta)
            if slowMotionTime <= 0 { slowMotionScale = 1 }
            return realDelta * slowMotionScale
        }
        return realDelta
    }

    func play(_ event: CombatEvent, context: FeedbackContext, game: Game) {
        switch event {
        case .enemyHit:
            if context.targetID != nil {
                flashEnemy(context.targetID, duration: config.normalHitFlash, offset: context.direction * 1.8, game: game)
            } else {
                flashBoss(duration: config.normalHitFlash, offset: context.direction * 1.8, game: game)
            }
            spawnSparks(at: context.position, direction: context.direction, tint: context.tint, count: 4, game: game)
            aggregateDamage(context, game: game)
            playSound(level: .light, name: "sfx_hit")
            if context.damageKind == .missile {
                spawnExplosion(at: context.position, direction: context.direction, tint: rgb(255, 135, 92), level: .medium, game: game)
                requestShake(.medium, game: game)
            }
        case .criticalHit:
            if context.targetID != nil {
                flashEnemy(context.targetID, duration: config.criticalHitFlash, offset: context.direction * 3.0, game: game)
            } else {
                flashBoss(duration: config.criticalHitFlash, offset: context.direction * 3.0, game: game)
            }
            spawnSparks(at: context.position, direction: context.direction, tint: rgb(255, 245, 168), count: 9, game: game)
            appendDamage(context, critical: true, game: game)
            requestShake(.light, game: game)
            requestHitStop(config.hitStopCritical)
            playSound(level: .medium, name: "sfx_hit")
        case .enemyKilled:
            spawnExplosion(at: context.position, direction: context.direction, tint: context.tint, level: context.overkill ? .medium : .light, game: game)
            applyWeaponKillAccent(context, level: context.overkill ? .medium : .light, game: game)
            requestShake(context.overkill ? .medium : .light, game: game)
            playSound(level: .medium, name: "sfx_explosion")
        case .eliteKilled:
            spawnExplosion(at: context.position, direction: context.direction, tint: context.tint, level: .heavy, game: game)
            applyWeaponKillAccent(context, level: .heavy, game: game)
            requestShake(.heavy, game: game)
            requestHitStop(config.hitStopHeavy)
            playSound(level: .heavy, name: "sfx_explosion")
        case .playerHit:
            game.playerHitFlash = config.playerHitFlash
            game.playerShieldFlash = 0
            game.playerVisualOffset = context.direction * 5.0
            game.healthLag = max(game.healthLag, game.health + context.damage)
            game.healthBarFlash = 0.20
            game.damageEdgeFlash = max(game.damageEdgeFlash, context.level >= .heavy ? 0.24 : 0.15)
            spawnSparks(at: context.position, direction: context.direction, tint: rgb(255, 106, 132), count: 7, game: game)
            requestShake(context.level == .heavy ? .heavy : .medium, game: game)
            playSound(level: .heavy, name: "sfx_hit")
        case .shieldHit:
            game.playerShieldFlash = config.shieldFlash
            game.playerHitFlash = 0
            game.playerVisualOffset = context.direction * 2.5
            spawnShield(at: context.position, tint: rgb(122, 232, 204), count: 10, game: game)
            requestShake(.light, game: game)
            playSound(level: .medium, name: "sfx_hit")
        case .shieldBreak:
            game.playerShieldFlash = 0.24
            spawnShield(at: context.position, tint: rgb(114, 222, 255), count: 25, game: game)
            spawnShockwave(at: context.position, tint: rgb(114, 222, 255), game: game)
            requestShake(.heavy, game: game)
            requestHitStop(config.hitStopHeavy)
            game.notifyFeedback(title: "SHIELD BREAK", chineseTitle: "护盾破裂", tint: rgb(114, 222, 255))
            playSound(level: .heavy, name: "sfx_explosion")
        case .bossPartDestroyed:
            flashBoss(duration: 0.16, offset: context.direction * 5, game: game)
            spawnExplosion(at: context.position, direction: context.direction, tint: context.tint, level: .heavy, game: game)
            requestShake(.heavy, game: game)
            requestHitStop(0.050)
            playSound(level: .heavy, name: "sfx_explosion")
        case .bossKilled:
            flashBoss(duration: 0.30, offset: Vec2(x: 0, y: 6), game: game)
            bossDeath = BossDeathFeedback(position: context.position, tint: context.tint)
            spawnExplosion(at: context.position, direction: context.direction, tint: context.tint, level: .critical, game: game)
            requestShake(.critical, game: game)
            requestHitStop(config.hitStopCriticalEvent)
            slowMotionTime = 0.18
            slowMotionScale = 0.42
            playSound(level: .critical, name: "sfx_boss")
        case .playerKilled:
            game.playerHitFlash = 0.34
            spawnExplosion(at: context.position, direction: context.direction, tint: rgb(255, 118, 140), level: .critical, game: game)
            requestShake(.critical, game: game)
            requestHitStop(config.hitStopCriticalEvent)
            slowMotionTime = 0.15
            slowMotionScale = 0.35
            playSound(level: .critical, name: "sfx_explosion")
        case .comboMilestone:
            let count = max(1, Int(context.damage.rounded()))
            let tint: COLORREF = count >= 100 ? rgb(255, 108, 226) : (count >= 50 ? rgb(130, 239, 255) : rgb(255, 207, 105))
            comboFeedback = ComboFeedback(count: count, tint: tint)
            spawnShockwave(at: game.player, tint: tint, game: game)
            spawnSparks(at: game.player, direction: Vec2(x: 0, y: -1), tint: tint, count: min(12, 4 + count / 15), game: game)
            requestShake(count >= 100 ? .heavy : .medium, game: game)
            playSound(level: .heavy, name: "sfx_hit")
        case .rareDrop:
            spawnShockwave(at: context.position, tint: context.tint, game: game)
            spawnShield(at: context.position, tint: context.tint, count: 18, game: game)
            spawnSparks(at: context.position, direction: Vec2(x: 0, y: -1), tint: rgb(255, 245, 194), count: 12, game: game)
            requestShake(.medium, game: game)
            game.notifyFeedback(title: "RARE MODULE ACQUIRED", chineseTitle: "获得稀有模块", tint: context.tint)
            playSound(level: .heavy, name: "sfx_boss")
        }
    }

    func requestLegacyShake(strength: Double, game: Game) {
        let level: FeedbackLevel
        switch strength {
        case ..<2.2: level = .light
        case ..<5.0: level = .medium
        case ..<9.0: level = .heavy
        default: level = .critical
        }
        requestShake(level, game: game)
    }

    private func flashEnemy(_ id: Int?, duration: Double, offset: Vec2, game: Game) {
        guard let id, let index = game.enemies.firstIndex(where: { $0.feedbackID == id }) else { return }
        game.enemies[index].hitFlash = max(game.enemies[index].hitFlash, duration)
        game.enemies[index].visualOffset = game.enemies[index].visualOffset + offset
    }

    private func flashBoss(duration: Double, offset: Vec2, game: Game) {
        guard var boss = game.boss else { return }
        boss.hitFlash = max(boss.hitFlash, duration)
        boss.visualOffset = boss.visualOffset + offset
        game.boss = boss
    }

    private func aggregateDamage(_ context: FeedbackContext, game: Game) {
        guard let targetID = context.targetID else { appendDamage(context, critical: false, game: game); return }
        if var pending = pendingDamage[targetID] {
            pending.amount += max(1, Int(context.damage.rounded()))
            pending.position = context.position
            pending.life = config.damageAggregateWindow
            pendingDamage[targetID] = pending
        } else {
            pendingDamage[targetID] = PendingDamage(position: context.position,
                                                    amount: max(1, Int(context.damage.rounded())),
                                                    life: config.damageAggregateWindow,
                                                    tint: context.tint)
        }
    }

    private func flushDamage(realDelta: Double, game: Game) {
        guard !pendingDamage.isEmpty else { return }
        // This small table is capped by active targets; copy keys so entries
        // can safely merge or flush without mutating a Dictionary mid-iterate.
        for id in Array(pendingDamage.keys) {
            guard var pending = pendingDamage[id] else { continue }
            pending.life -= realDelta
            if pending.life <= 0 {
                appendDamage(FeedbackContext(position: pending.position, damage: Double(pending.amount), tint: pending.tint), critical: false, game: game)
                pendingDamage.removeValue(forKey: id)
            } else {
                pendingDamage[id] = pending
            }
        }
    }

    private func appendDamage(_ context: FeedbackContext, critical: Bool, game: Game) {
        let life = critical ? 0.92 : 0.65
        game.damageNumbers.append(DamageNumber(position: context.position + Vec2(x: Double.random(in: -8...8, using: &rng), y: -8),
                                               amount: max(1, Int(context.damage.rounded())),
                                               critical: critical,
                                               life: life,
                                               maxLife: life,
                                               tint: critical ? rgb(255, 225, 112) : context.tint))
        if game.damageNumbers.count > config.maxDamageNumbers {
            game.damageNumbers.removeFirst(game.damageNumbers.count - config.maxDamageNumbers)
        }
    }

    private func updateVisualState(realDelta: Double, game: Game) {
        game.playerHitFlash = max(0, game.playerHitFlash - realDelta)
        game.playerShieldFlash = max(0, game.playerShieldFlash - realDelta)
        game.healthBarFlash = max(0, game.healthBarFlash - realDelta)
        game.damageEdgeFlash = max(0, game.damageEdgeFlash - realDelta)
        game.playerVisualOffset = game.playerVisualOffset * max(0, 1 - realDelta * 15)
        if game.healthLag > game.health {
            game.healthLag = max(game.health, game.healthLag - realDelta * max(1, game.maxHealth) * config.healthLagSpeed)
        } else {
            game.healthLag = game.health
        }
        for index in game.enemies.indices {
            game.enemies[index].hitFlash = max(0, game.enemies[index].hitFlash - realDelta)
            game.enemies[index].visualOffset = game.enemies[index].visualOffset * max(0, 1 - realDelta * 17)
        }
        if var boss = game.boss {
            boss.hitFlash = max(0, boss.hitFlash - realDelta)
            boss.visualOffset = boss.visualOffset * max(0, 1 - realDelta * 12)
            game.boss = boss
        }
        let healthRatio = game.health / max(1, game.maxHealth)
        if healthRatio < 0.5, game.phase == .playing {
            lowHealthSmokeClock -= realDelta
            if lowHealthSmokeClock <= 0 {
                lowHealthSmokeClock = healthRatio < 0.2 ? 0.14 : 0.28
                let tint = healthRatio < 0.2 ? rgb(255, 104, 112) : rgb(178, 194, 220)
                let life = healthRatio < 0.2 ? 0.44 : 0.30
                appendParticle(Particle(position: game.player + Vec2(x: Double.random(in: -8...8, using: &rng), y: 12),
                                        velocity: Vec2(x: Double.random(in: -18...18, using: &rng), y: Double.random(in: 18...40, using: &rng)),
                                        radius: healthRatio < 0.2 ? 4.8 : 3.2, life: life, maxLife: life, tint: tint, kind: .smoke), game: game)
            }
        } else {
            lowHealthSmokeClock = 0
        }
        if healthRatio < 0.2, game.phase == .playing {
            lowHealthWarningClock -= realDelta
            if lowHealthWarningClock <= 0 {
                lowHealthWarningClock = 1.2
                game.notifyFeedback(title: "HULL CRITICAL", chineseTitle: "机体严重受损", tint: rgb(255, 105, 121))
            }
        } else {
            lowHealthWarningClock = 0
        }
    }

    private func updateBossDeath(realDelta: Double, game: Game) {
        guard var sequence = bossDeath else { return }
        sequence.elapsed += realDelta
        let stages: [Double] = [0.13, 0.28, 0.46, 0.68]
        while sequence.burstStage < stages.count, sequence.elapsed >= stages[sequence.burstStage] {
            let angle = Double(sequence.burstStage) * 2.1
            let offset = Vec2(x: cos(angle) * (42 + Double(sequence.burstStage) * 25), y: sin(angle) * 20)
            spawnExplosion(at: sequence.position + offset, direction: offset.normalized, tint: sequence.tint,
                           level: sequence.burstStage == stages.count - 1 ? .critical : .heavy, game: game)
            sequence.burstStage += 1
        }
        if sequence.elapsed > 1.12 {
            bossDeath = nil
        } else {
            bossDeath = sequence
        }
    }

    private func updateComboFeedback(realDelta: Double) {
        guard var feedback = comboFeedback else { return }
        feedback.elapsed += realDelta
        comboFeedback = feedback.elapsed > 0.9 ? nil : feedback
    }

    private func applyWeaponKillAccent(_ context: FeedbackContext, level: FeedbackLevel, game: Game) {
        switch context.damageKind {
        case .missile:
            spawnShockwave(at: context.position, tint: rgb(255, 185, 104), game: game)
        case .laser:
            spawnSparks(at: context.position, direction: context.direction, tint: rgb(130, 239, 255), count: 10, game: game)
        case .electromagnetic:
            spawnShield(at: context.position, tint: rgb(190, 132, 255), count: level >= .heavy ? 14 : 8, game: game)
        default:
            break
        }
    }

    private func spawnSparks(at position: Vec2, direction: Vec2, tint: COLORREF, count: Int, game: Game) {
        let forward = direction.length > 0.01 ? direction.normalized : Vec2(x: 0, y: -1)
        for _ in 0..<min(count, config.maxHitParticles) {
            let life = Double.random(in: 0.10...0.24, using: &rng)
            let spread = Vec2(x: Double.random(in: -0.65...0.65, using: &rng), y: Double.random(in: -0.55...0.55, using: &rng))
            appendParticle(Particle(position: position,
                                    velocity: forward * Double.random(in: 65...150, using: &rng) + spread * 95,
                                    radius: Double.random(in: 1.5...3.2, using: &rng),
                                    life: life, maxLife: life, tint: tint, kind: .spark), game: game)
        }
    }

    private func spawnShield(at position: Vec2, tint: COLORREF, count: Int, game: Game) {
        for index in 0..<count {
            let angle = Double(index) / Double(max(1, count)) * Double.pi * 2
            let life = Double.random(in: 0.22...0.42, using: &rng)
            appendParticle(Particle(position: position + Vec2(x: cos(angle) * 13, y: sin(angle) * 13),
                                    velocity: Vec2(x: cos(angle) * Double.random(in: 45...125, using: &rng), y: sin(angle) * Double.random(in: 45...125, using: &rng)),
                                    radius: Double.random(in: 2...4, using: &rng), life: life, maxLife: life, tint: tint, kind: .shield), game: game)
        }
    }

    private func spawnShockwave(at position: Vec2, tint: COLORREF, game: Game) {
        appendParticle(Particle(position: position, velocity: .zero, radius: 8, life: 0.32, maxLife: 0.32, tint: tint, kind: .shockwave), game: game)
    }

    private func spawnExplosion(at position: Vec2, direction: Vec2, tint: COLORREF, level: FeedbackLevel, game: Game) {
        let count: Int
        switch level { case .light: count = 12; case .medium: count = 20; case .heavy: count = 34; case .critical: count = 52 }
        // Layer 1: short core flash.
        appendParticle(Particle(position: position, velocity: .zero, radius: level >= .heavy ? 16 : 10,
                                life: 0.055, maxLife: 0.055, tint: rgb(255, 247, 220), kind: .coreFlash), game: game)
        // Layer 2: directional debris and flame.
        let forward = direction.length > 0.01 ? direction.normalized : .zero
        for index in 0..<min(count, config.maxExplosionParticles) {
            let angle = Double.random(in: 0...(Double.pi * 2), using: &rng)
            let directional = forward * Double.random(in: 0...85, using: &rng)
            let speed = Double.random(in: 50...220, using: &rng)
            let life = Double.random(in: 0.20...0.62, using: &rng)
            appendParticle(Particle(position: position,
                                    velocity: Vec2(x: cos(angle) * speed, y: sin(angle) * speed) + directional,
                                    radius: Double.random(in: 2...5.5, using: &rng), life: life, maxLife: life,
                                    tint: index % 3 == 0 ? rgb(255, 174, 92) : tint, kind: .debris), game: game)
        }
        // Layer 3: residual smoke.
        let smokeCount = level >= .heavy ? 7 : 3
        for _ in 0..<smokeCount {
            let life = Double.random(in: 0.55...0.95, using: &rng)
            appendParticle(Particle(position: position + Vec2(x: Double.random(in: -10...10, using: &rng), y: Double.random(in: -8...8, using: &rng)),
                                    velocity: Vec2(x: Double.random(in: -20...20, using: &rng), y: Double.random(in: -55 ... -12, using: &rng)),
                                    radius: Double.random(in: 4...8, using: &rng), life: life, maxLife: life,
                                    tint: rgb(94, 108, 136), kind: .smoke), game: game)
        }
    }

    private func appendParticle(_ particle: Particle, game: Game) {
        guard game.particles.count < game.particleLimit else { return }
        game.particles.append(particle)
    }

    private func requestShake(_ level: FeedbackLevel, game: Game) {
        let base: Double
        switch level { case .light: base = config.lightShake; case .medium: base = config.mediumShake; case .heavy: base = config.heavyShake; case .critical: base = config.criticalShake }
        let multipliers = [0.0, 0.45, 1.0, 1.35]
        let userMultiplier = multipliers[min(3, max(0, game.profile.cameraShake))]
        guard userMultiplier > 0 else { return }
        let magnitude = base * userMultiplier
        shakeStrength = min(config.maxShake, max(shakeStrength, magnitude))
        shakeTime = min(0.30, max(shakeTime, level >= .heavy ? 0.15 : 0.065))
        // Preserve these fields for existing HUD/debug consumers.
        game.cameraShakeStrength = shakeStrength
        game.cameraShakeTime = shakeTime
    }

    private func requestHitStop(_ seconds: Double) {
        hitStopTime = min(0.10, max(hitStopTime, seconds))
    }

    private func playSound(level: FeedbackLevel, name: String) {
        if level == .light {
            guard hitSoundClock - lastLightHitSound >= config.lightHitSoundCooldown else { return }
            lastLightHitSound = hitSoundClock
        }
        AudioManager.shared.playSFX(name)
    }
}

extension Game {
    func notifyFeedback(title: String, chineseTitle: String, tint: COLORREF) {
        notificationTitle = language == .chinese ? chineseTitle : title
        notificationDetail = ""
        notificationTint = tint
        notificationTimer = max(notificationTimer, 1.15)
    }
}
