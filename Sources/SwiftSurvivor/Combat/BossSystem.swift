import Foundation

enum BossLifecycleState: Int {
    case entering
    case combat
    case phaseTransition
    case dying
}

enum BossAttackStage: Int {
    case recovery
    case telegraph
    case execute
}

enum BossAttackID: Int, CaseIterable {
    case spread
    case aimBurst
    case sideCrossfire
    case laserSweep
    case slowField
    case spiral

    func label(for language: GameLanguage) -> String {
        switch (self, language) {
        case (.spread, .chinese): return "扇形压制"
        case (.aimBurst, .chinese): return "锁定三连"
        case (.sideCrossfire, .chinese): return "侧炮交火"
        case (.laserSweep, .chinese): return "激光横扫"
        case (.slowField, .chinese): return "延迟力场"
        case (.spiral, .chinese): return "双重螺旋"
        case (.spread, _): return "SPREAD"
        case (.aimBurst, _): return "AIM BURST"
        case (.sideCrossfire, _): return "CROSSFIRE"
        case (.laserSweep, _): return "LASER SWEEP"
        case (.slowField, _): return "SLOW FIELD"
        case (.spiral, _): return "TWIN SPIRAL"
        }
    }
}

enum BossMovementID: Int {
    case hover
    case horizontalSweep
    case aggressiveHover
    case positionLock
}

struct BossAttackDefinition {
    let id: BossAttackID
    let telegraph: Double
    let execute: Double
    let recovery: Double
    let movement: BossMovementID
}

struct BossPhaseDefinition {
    let phase: Int
    let lowerHealthRatio: Double
    let attacks: [BossAttackDefinition]
    let weakPointDuringRecovery: Bool
}

enum ThunderCarrierBossDefinition {
    static let weakPointMultiplier = 1.65
    static let disabledTurretsMultiplier = 1.20
    static let entranceDuration = 1.55
    static let transitionDuration = 1.15
    static let deathDuration = 2.40

    static let phases: [BossPhaseDefinition] = [
        BossPhaseDefinition(
            phase: 1,
            lowerHealthRatio: 0.70,
            attacks: [
                BossAttackDefinition(id: .spread, telegraph: 0.42, execute: 0.08, recovery: 0.95, movement: .positionLock),
                BossAttackDefinition(id: .aimBurst, telegraph: 0.62, execute: 0.38, recovery: 1.05, movement: .hover),
                BossAttackDefinition(id: .sideCrossfire, telegraph: 0.48, execute: 0.10, recovery: 1.20, movement: .positionLock)
            ],
            weakPointDuringRecovery: true
        ),
        BossPhaseDefinition(
            phase: 2,
            lowerHealthRatio: 0.30,
            attacks: [
                BossAttackDefinition(id: .spread, telegraph: 0.50, execute: 0.08, recovery: 0.82, movement: .positionLock),
                BossAttackDefinition(id: .sideCrossfire, telegraph: 0.52, execute: 0.10, recovery: 0.88, movement: .horizontalSweep),
                BossAttackDefinition(id: .laserSweep, telegraph: 0.92, execute: 1.25, recovery: 1.35, movement: .horizontalSweep),
                BossAttackDefinition(id: .slowField, telegraph: 0.68, execute: 0.12, recovery: 1.00, movement: .hover)
            ],
            weakPointDuringRecovery: true
        ),
        BossPhaseDefinition(
            phase: 3,
            lowerHealthRatio: 0,
            attacks: [
                BossAttackDefinition(id: .spiral, telegraph: 0.72, execute: 0.12, recovery: 0.82, movement: .positionLock),
                BossAttackDefinition(id: .aimBurst, telegraph: 0.55, execute: 0.38, recovery: 0.72, movement: .aggressiveHover),
                BossAttackDefinition(id: .laserSweep, telegraph: 0.78, execute: 1.35, recovery: 1.05, movement: .horizontalSweep)
            ],
            weakPointDuringRecovery: true
        )
    ]

    static func phase(_ value: Int) -> BossPhaseDefinition {
        phases[min(phases.count - 1, max(0, value - 1))]
    }
}
