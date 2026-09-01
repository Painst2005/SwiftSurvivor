import Foundation
import Dispatch
import WinSDK

// MARK: - Math

struct Vec2 {
    var x: Double
    var y: Double

    static let zero = Vec2(x: 0, y: 0)

    static func + (lhs: Vec2, rhs: Vec2) -> Vec2 { Vec2(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }
    static func - (lhs: Vec2, rhs: Vec2) -> Vec2 { Vec2(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }
    static func * (lhs: Vec2, rhs: Double) -> Vec2 { Vec2(x: lhs.x * rhs, y: lhs.y * rhs) }

    var length: Double { sqrt(x * x + y * y) }
    var lengthSquared: Double { x * x + y * y }
    var normalized: Vec2 {
        let len = length
        return len > 0.0001 ? self * (1.0 / len) : .zero
    }
}

func distance(_ a: Vec2, _ b: Vec2) -> Double { (a - b).length }
func distanceSquared(_ a: Vec2, _ b: Vec2) -> Double { (a - b).lengthSquared }

func rotated(_ vector: Vec2, by angle: Double) -> Vec2 {
    let cosine = cos(angle)
    let sine = sin(angle)
    return Vec2(x: vector.x * cosine - vector.y * sine,
                y: vector.x * sine + vector.y * cosine)
}

// The game is authored in a compact logical coordinate space and then scaled
// to the real client surface. This preserves the original sprite/UI size on
// high-DPI monitors without introducing empty side columns in the battlefield.
struct PlayfieldBounds {
    let left: Double
    let right: Double
    let top: Double
    let bottom: Double

    var width: Double { right - left }
    var centerX: Double { (left + right) * 0.5 }
}

func playfieldBounds(width: Double, height: Double) -> PlayfieldBounds {
    let top = 68.0
    return PlayfieldBounds(left: 0, right: width, top: top,
                           bottom: max(top + 1, height - 12.0))
}

struct ViewportMetrics {
    let scale: Double
    let logicalWidth: Double
    let logicalHeight: Double
}

// 1000x760 is the original authoring size. On a 200% DPI display, for
// example, a 2880x1620 client becomes a 1350x760 logical canvas and every
// primitive is presented at the same apparent size as it was in the original
// window. The aspect ratio remains that of the monitor, so there are no
// pillar-boxed combat columns.
func viewportMetrics(pixelWidth: Int32, pixelHeight: Int32) -> ViewportMetrics {
    let width = max(1.0, Double(pixelWidth))
    let height = max(1.0, Double(pixelHeight))
    let scale = max(0.25, min(width / 1000.0, height / 760.0))
    return ViewportMetrics(scale: scale,
                           logicalWidth: width / scale,
                           logicalHeight: height / scale)
}

// MARK: - Game model

enum GamePhase { case menu, saveSlots, missionSelect, controls, hangar, settings, archive, playing, paused, upgrade, gameOver }

enum UIConfirmationKind {
    case abandonRun
}

enum GameLanguage: Int, CaseIterable {
    case english = 0
    case chinese = 1

    var label: String {
        switch self {
        case .english: return "English"
        case .chinese: return "中文"
        }
    }

}

enum ControlMode: String { case wasd = "WASD", mouse = "MOUSE" }

enum GameMode: Int, CaseIterable {
    case campaign = 0
    case endless = 1
    case blitz = 2
    case zen = 3

    var label: String {
        switch self {
        case .campaign: return "CAMPAIGN"
        case .endless: return "ENDLESS"
        case .blitz: return "BLITZ"
        case .zen: return "ZEN"
        }
    }

    func label(for language: GameLanguage) -> String {
        guard language == .chinese else { return label }
        switch self {
        case .campaign: return "章节模式"
        case .endless: return "无尽模式"
        case .blitz: return "爽快模式"
        case .zen: return "禅模式"
        }
    }

    func description(for language: GameLanguage) -> String {
        guard language == .chinese else {
            switch self {
            case .campaign: return "Clear a mission and unlock the next sector"
            case .endless: return "No time limit • chase your highest score"
            case .blitz: return "More enemies • faster firepower • richer drops"
            case .zen: return "Gentle damage • dense formations • relaxed flight"
            }
        }
        switch self {
        case .campaign: return "完成关卡并解锁下一个区域"
        case .endless: return "逐波迎战强敌与首领 • 挑战最高纪录"
        case .blitz: return "敌机更多 • 火力更猛 • 奖励更丰厚"
        case .zen: return "敌人伤害较低 • 适合轻松体验战斗"
        }
    }

    var isFinite: Bool {
        self != .endless
    }
}

enum EndlessWavePhase {
    case combat
    case boss
}

struct MissionDefinition {
    let id: Int
    let title: String
    let chineseTitle: String
    let description: String
    let chineseDescription: String
    let duration: Double
    let bossTime: Double
    let difficulty: Double
    let rewardMultiplier: Double
    let recommendedPower: Int

    func title(for language: GameLanguage) -> String {
        language == .chinese ? chineseTitle : title
    }

    func description(for language: GameLanguage) -> String {
        language == .chinese ? chineseDescription : description
    }
}

enum MissionCatalog {
    static let all: [MissionDefinition] = [
        MissionDefinition(id: 1, title: "NEON FRONT", chineseTitle: "霓虹前线",
                          description: "The first defense line is under attack",
                          chineseDescription: "第一道防线正在遭受攻击",
                          duration: 75, bossTime: 42, difficulty: 0.86, rewardMultiplier: 1.0, recommendedPower: 100),
        MissionDefinition(id: 2, title: "VOID RIFT", chineseTitle: "虚空裂隙",
                          description: "Enemy formations emerge from a broken gate",
                          chineseDescription: "敌方编队从破碎的空间门涌出",
                          duration: 90, bossTime: 48, difficulty: 1.08, rewardMultiplier: 1.35, recommendedPower: 180),
        MissionDefinition(id: 3, title: "STAR FORGE", chineseTitle: "星铸核心",
                          description: "Hold the forge while its reactor overloads",
                          chineseDescription: "守住星铸核心，直到反应堆完成过载",
                          duration: 105, bossTime: 54, difficulty: 1.32, rewardMultiplier: 1.75, recommendedPower: 290),
        MissionDefinition(id: 4, title: "THUNDER CITADEL", chineseTitle: "雷霆堡垒",
                          description: "Break through the fortress command fleet",
                          chineseDescription: "突破堡垒舰队，摧毁敌方指挥中枢",
                          duration: 120, bossTime: 60, difficulty: 1.58, rewardMultiplier: 2.2, recommendedPower: 430),
        MissionDefinition(id: 5, title: "FROSTLINE", chineseTitle: "寒霜防线",
                          description: "Escort the last convoy through a frozen storm",
                          chineseDescription: "护送最后的运输队穿越寒霜风暴",
                          duration: 135, bossTime: 66, difficulty: 1.82, rewardMultiplier: 2.7, recommendedPower: 580),
        MissionDefinition(id: 6, title: "ECLIPSE GATE", chineseTitle: "日蚀之门",
                          description: "Close the gate before the eclipse reaches orbit",
                          chineseDescription: "在日蚀抵达轨道前关闭虚空之门",
                          duration: 150, bossTime: 72, difficulty: 2.08, rewardMultiplier: 3.2, recommendedPower: 760),
        MissionDefinition(id: 7, title: "STARFALL", chineseTitle: "星陨禁区",
                          description: "Survive the meteor field and break the siege",
                          chineseDescription: "穿越陨石场，突破敌军围攻",
                          duration: 165, bossTime: 78, difficulty: 2.38, rewardMultiplier: 3.8, recommendedPower: 980),
        MissionDefinition(id: 8, title: "ORIGIN CORE", chineseTitle: "起源核心",
                          description: "Enter the origin core and end the invasion",
                          chineseDescription: "进入起源核心，终结这场入侵",
                          duration: 180, bossTime: 84, difficulty: 2.72, rewardMultiplier: 4.5, recommendedPower: 1250)
    ]
}

// Build synergies are declared as data so new combinations can be added
// without scattering one-off checks through the upgrade flow.
enum BuildCore: String, CaseIterable {
    case laser
    case cryo
    case thunder
    case array
    case overdrive
}

struct BuildSynergyDefinition {
    let id: String
    let required: [BuildCore]
    let englishTitle: String
    let chineseTitle: String
    let englishDetail: String
    let chineseDetail: String

    func title(for language: GameLanguage) -> String {
        language == .chinese ? chineseTitle : englishTitle
    }

    func detail(for language: GameLanguage) -> String {
        language == .chinese ? chineseDetail : englishDetail
    }
}

enum BuildSynergyCatalog {
    static let all: [BuildSynergyDefinition] = [
        BuildSynergyDefinition(id: "frost_ray", required: [.laser, .cryo],
                               englishTitle: "SYNERGY ONLINE: FROST RAY", chineseTitle: "联动已激活：寒霜射线",
                               englishDetail: "Laser damage amplified • cryo beam unlocked", chineseDetail: "激光伤害强化 • 寒霜光束已解锁"),
        BuildSynergyDefinition(id: "flight_array", required: [.array, .overdrive],
                               englishTitle: "SYNERGY ONLINE: FLIGHT ARRAY", chineseTitle: "联动已激活：飞行阵列",
                               englishDetail: "Overdrive now adds auxiliary projectiles", chineseDetail: "超频驱动将额外发射辅助弹幕"),
        BuildSynergyDefinition(id: "storm_crit", required: [.thunder],
                               englishTitle: "SYNERGY ONLINE: STORM CRIT", chineseTitle: "联动已激活：风暴暴击",
                               englishDetail: "Critical hits now charge Thunder energy", chineseDetail: "暴击现在会充能雷霆能量"),
        BuildSynergyDefinition(id: "overload_matrix", required: [.laser, .thunder],
                               englishTitle: "SYNERGY ONLINE: OVERLOAD MATRIX", chineseTitle: "联动已激活：超载矩阵",
                               englishDetail: "Laser and Thunder damage gain a final surge", chineseDetail: "激光与雷霆伤害大幅提升")
    ]
}

enum AchievementMetric: Int {
    case runs
    case kills
    case bosses
    case combo
    case score
    case missions
    case modules
}

struct AchievementDefinition {
    let id: String
    let title: String
    let chineseTitle: String
    let detail: String
    let chineseDetail: String
    let metric: AchievementMetric
    let target: Int

    func title(for language: GameLanguage) -> String { language == .chinese ? chineseTitle : title }
    func detail(for language: GameLanguage) -> String { language == .chinese ? chineseDetail : detail }
}

enum AchievementCatalog {
    static let all: [AchievementDefinition] = [
        AchievementDefinition(id: "first_sortie", title: "FIRST SORTIE", chineseTitle: "首次出击",
                              detail: "Complete your first launch", chineseDetail: "完成第一次出击",
                              metric: .runs, target: 1),
        AchievementDefinition(id: "ace_pilot", title: "ACE PILOT", chineseTitle: "王牌飞行员",
                              detail: "Destroy 100 enemies", chineseDetail: "击毁 100 架敌机",
                              metric: .kills, target: 100),
        AchievementDefinition(id: "boss_breaker", title: "BOSS BREAKER", chineseTitle: "首领终结者",
                              detail: "Defeat 3 bosses", chineseDetail: "击败 3 名首领",
                              metric: .bosses, target: 3),
        AchievementDefinition(id: "combo_master", title: "COMBO MASTER", chineseTitle: "连击大师",
                              detail: "Reach a 50-hit combo", chineseDetail: "达到 50 连击",
                              metric: .combo, target: 50),
        AchievementDefinition(id: "sector_runner", title: "SECTOR RUNNER", chineseTitle: "区域征服者",
                              detail: "Unlock 4 sectors", chineseDetail: "解锁 4 个作战区域",
                              metric: .missions, target: 4),
        AchievementDefinition(id: "high_roller", title: "HIGH ROLLER", chineseTitle: "高分猎手",
                              detail: "Score 10,000 points in one sortie", chineseDetail: "单局达到 10,000 分",
                              metric: .score, target: 10000),
        AchievementDefinition(id: "full_vault", title: "FULL VAULT", chineseTitle: "满载仓库",
                              detail: "Collect 8 modules", chineseDetail: "收集 8 个模块",
                              metric: .modules, target: 8)
    ]
}

enum CodexCategory: Int, CaseIterable {
    case weapons = 0
    case enemies = 1
    case bosses = 2

    func label(for language: GameLanguage) -> String {
        guard language == .chinese else {
            switch self { case .weapons: return "WEAPONS"; case .enemies: return "ENEMIES"; case .bosses: return "BOSSES" }
        }
        switch self { case .weapons: return "武器"; case .enemies: return "敌机"; case .bosses: return "首领" }
    }
}

struct CodexEntry {
    let id: String
    let category: CodexCategory
    let title: String
    let chineseTitle: String
    let detail: String
    let chineseDetail: String

    func title(for language: GameLanguage) -> String { language == .chinese ? chineseTitle : title }
    func detail(for language: GameLanguage) -> String { language == .chinese ? chineseDetail : detail }
}

enum CodexCatalog {
    static let all: [CodexEntry] = [
        CodexEntry(id: "cannon", category: .weapons, title: "CANNON", chineseTitle: "机炮", detail: "Stable high-rate fire", chineseDetail: "稳定的高速火力"),
        CodexEntry(id: "laser", category: .weapons, title: "LASER", chineseTitle: "激光", detail: "Piercing beam damage", chineseDetail: "可穿透的光束伤害"),
        CodexEntry(id: "scatter", category: .weapons, title: "SCATTER", chineseTitle: "散弹", detail: "Wide close-range burst", chineseDetail: "近距离宽幅爆发"),
        CodexEntry(id: "missile", category: .weapons, title: "MISSILE", chineseTitle: "导弹", detail: "Homing explosive payload", chineseDetail: "追踪爆炸弹头"),
        CodexEntry(id: "emp", category: .weapons, title: "EMP", chineseTitle: "电磁", detail: "Oscillating suppression orbs", chineseDetail: "摆动压制电磁球"),
        CodexEntry(id: "fighter", category: .enemies, title: "FIGHTER", chineseTitle: "战斗机", detail: "Basic formation attacker", chineseDetail: "基础编队攻击单位"),
        CodexEntry(id: "diver", category: .enemies, title: "DIVER", chineseTitle: "俯冲机", detail: "Locks on and dives fast", chineseDetail: "锁定目标后快速俯冲"),
        CodexEntry(id: "turret", category: .enemies, title: "TURRET", chineseTitle: "炮艇", detail: "Slow armored gun platform", chineseDetail: "缓慢的装甲火力平台"),
        CodexEntry(id: "sniper", category: .enemies, title: "SNIPER", chineseTitle: "狙击机", detail: "Telegraphed high-speed shot", chineseDetail: "带预警的高速狙击弹"),
        CodexEntry(id: "shield", category: .enemies, title: "SHIELD", chineseTitle: "护盾机", detail: "Protects nearby enemies", chineseDetail: "为附近敌机提供保护"),
        CodexEntry(id: "kamikaze", category: .enemies, title: "KAMIKAZE", chineseTitle: "自爆机", detail: "Rushes in for impact damage", chineseDetail: "冲向玩家造成撞击伤害"),
        CodexEntry(id: "carrier", category: .enemies, title: "CARRIER", chineseTitle: "母舰", detail: "Summons reinforcement fighters", chineseDetail: "周期性召唤增援战机"),
        CodexEntry(id: "dreadnought", category: .bosses, title: "HEAVY THUNDER CARRIER", chineseTitle: "重装雷霆母舰", detail: "Breakable twin turrets, exposed core and readable attack sequences", chineseDetail: "可破坏双炮塔、核心弱点与可读攻击序列"),
        CodexEntry(id: "rift", category: .bosses, title: "RIFT BEHEMOTH", chineseTitle: "裂隙巨兽", detail: "Ring fire and accelerating bursts", chineseDetail: "环形弹与加速爆发"),
        CodexEntry(id: "frost", category: .bosses, title: "FROST WARDEN", chineseTitle: "寒霜守望者", detail: "Cold lanes and laser locks", chineseDetail: "寒霜航道与激光锁定"),
        CodexEntry(id: "origin", category: .bosses, title: "ORIGIN ARCHITECT", chineseTitle: "起源构造者", detail: "Final storm with shifting lanes", chineseDetail: "变幻航道的终极风暴")
    ]
}

enum WeaponType: Int, CaseIterable {
    case cannon = 0
    case laser = 1
    case scatter = 2
    case missile = 3
    case electromagnetic = 4

    var label: String {
        switch self {
        case .cannon: return "CANNON"
        case .laser: return "LASER"
        case .scatter: return "SCATTER"
        case .missile: return "MISSILE"
        case .electromagnetic: return "EMP"
        }
    }

    func label(for language: GameLanguage) -> String {
        guard language == .chinese else { return label }
        switch self {
        case .cannon: return "机炮"
        case .laser: return "激光"
        case .scatter: return "散弹"
        case .missile: return "导弹"
        case .electromagnetic: return "电磁"
        }
    }
}

enum ShipType: Int, CaseIterable {
    case thunder = 0
    case ghost = 1
    case heavy = 2
    case destroyer = 3
    case carrier = 4

    var label: String {
        switch self {
        case .thunder: return "THUNDER"
        case .ghost: return "GHOST"
        case .heavy: return "HEAVY"
        case .destroyer: return "DESTROYER"
        case .carrier: return "CARRIER"
        }
    }

    func label(for language: GameLanguage) -> String {
        guard language == .chinese else { return label }
        switch self {
        case .thunder: return "雷霆号"
        case .ghost: return "幽灵号"
        case .heavy: return "重装号"
        case .destroyer: return "毁灭者"
        case .carrier: return "母舰型"
        }
    }

    var subtitle: String {
        switch self {
        case .thunder: return "Balanced / lightning crits"
        case .ghost: return "Evasion / periodic immunity"
        case .heavy: return "Hull / shield specialist"
        case .destroyer: return "Close-range damage"
        case .carrier: return "Auxiliary drone power"
        }
    }

    func subtitle(for language: GameLanguage) -> String {
        guard language == .chinese else { return subtitle }
        switch self {
        case .thunder: return "均衡 / 闪电暴击"
        case .ghost: return "闪避 / 周期免疫"
        case .heavy: return "装甲 / 护盾专家"
        case .destroyer: return "近距离 / 高伤害"
        case .carrier: return "僚机 / 辅助火力"
        }
    }

    var rarity: String {
        switch self {
        case .thunder: return "STARTER"
        case .ghost, .destroyer: return "RARE"
        case .heavy, .carrier: return "EPIC"
        }
    }

    func rarity(for language: GameLanguage) -> String {
        guard language == .chinese else { return rarity }
        switch self {
        case .thunder: return "初始"
        case .ghost, .destroyer: return "稀有"
        case .heavy, .carrier: return "史诗"
        }
    }
}

// Enemy roles are intentionally data-driven so new archetypes can be added
// without changing the rest of the combat loop.
enum EnemyType: Int {
    case fighter = 0
    case diver = 1
    case turret = 2
    case sniper = 3
    case shield = 4
    case kamikaze = 5
    case carrier = 6
}

/// Tunable combat values kept out of the update loops, so feel changes are
/// deliberate and do not require hunting through unrelated gameplay code.
enum CombatConfig {
    static let precisionSpeedMultiplier = 0.46
    static let playerHitInvulnerability = 0.68
    static let thunderBurstCost = 50.0
    static let thunderOverloadCost = 100.0
    static let thunderBurstDuration = 2.8
    static let thunderOverloadDuration = 6.0
    static let swarmHealthMultiplier = 0.56
    static let eliteHealthMultiplier = 2.15
    static let eliteDamageMultiplier = 1.25
}

enum UpgradeRarity: Int {
    case common = 0
    case rare = 1
    case epic = 2
    case legendary = 3

    var label: String {
        switch self {
        case .common: return "COMMON"
        case .rare: return "RARE"
        case .epic: return "EPIC"
        case .legendary: return "LEGENDARY"
        }
    }
}

struct UIRect {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    func contains(_ point: Vec2) -> Bool {
        point.x >= x && point.x <= x + width && point.y >= y && point.y <= y + height
    }

}

struct Enemy {
    var feedbackID: Int = 0
    var position: Vec2
    var baseX: Double
    var radius: Double
    var speed: Double
    var health: Double
    var maxHealth: Double
    var tint: COLORREF
    var pattern: Int
    var age: Double
    var phase: Double
    var shootTimer: Double
    var type: Int
    var warningTimer: Double = 0
    var warningTargetX: Double = 0
    var attackWarningActive: Bool = false
    /// 0 = dense low-damage bullet column, 1 = instantaneous heavy laser.
    var warningAttackKind: Int = 0
    var dangerLaserTimer: Double = 0
    var diveStarted: Bool = false
    var spawnTimer: Double = 4.5
    // Presentation-only response. Collision and movement always use position.
    var visualOffset: Vec2 = .zero
    var hitFlash: Double = 0
    var isElite: Bool = false
    var eliteWarningTimer: Double = 0
    var eliteAttackTimer: Double = 3.2
}

struct PowerUp {
    var position: Vec2
    var kind: Int // 0 weapon, 1 shield, 2 repair
    var life: Double
}

struct Particle {
    var position: Vec2
    var velocity: Vec2
    var radius: Double
    var life: Double
    var maxLife: Double
    var tint: COLORREF
    var kind: FeedbackParticleKind = .spark
}

struct DamageNumber {
    var position: Vec2
    var amount: Int
    var critical: Bool
    var life: Double
    var maxLife: Double
    var tint: COLORREF = rgb(255, 231, 150)
}

struct Star {
    var position: Vec2
    var speed: Double
    var radius: Double
    var tint: COLORREF
}

struct Boss {
    var position: Vec2
    var health: Double
    var maxHealth: Double
    var age: Double
    var shootTimer: Double
    var kind: Int = 0
    var leftTurretHealth: Double = 0
    var rightTurretHealth: Double = 0
    var phase: Int = 1
    var phaseFlash: Double = 0
    var warningTimer: Double = 0
    var attackPrimed: Bool = false
    var attackPatternIndex: Int = 0
    var laserWarningTimer: Double = 0
    var laserActiveTimer: Double = 0
    var laserCooldown: Double = 5
    var laserX: Double = 0
    var laserHitCooldown: Double = 0
    var visualOffset: Vec2 = .zero
    var hitFlash: Double = 0
    var lifecycle: BossLifecycleState = .entering
    var stateTimer: Double = ThunderCarrierBossDefinition.entranceDuration
    var pendingPhase: Int = 1
    var currentAttack: BossAttackID = .spread
    var attackStage: BossAttackStage = .recovery
    var attackTimer: Double = 0.8
    var attackTarget: Vec2 = .zero
    var movement: BossMovementID = .hover
    var weakPointOpen = false
    var leftTurretMaxHealth: Double = 0
    var rightTurretMaxHealth: Double = 0
    var laserTargetX: Double = 0
    var burstShotsRemaining = 0
    var burstShotTimer = 0.0
}

enum BossType: Int, CaseIterable {
    case dreadnought = 0
    case riftBehemoth = 1
    case frostWarden = 2
    case originArchitect = 3

    var title: String {
        switch self {
        case .dreadnought: return "HEAVY THUNDER CARRIER"
        case .riftBehemoth: return "RIFT BEHEMOTH"
        case .frostWarden: return "FROST WARDEN"
        case .originArchitect: return "ORIGIN ARCHITECT"
        }
    }

    func title(for language: GameLanguage) -> String {
        guard language == .chinese else { return title }
        switch self {
        case .dreadnought: return "重装雷霆母舰"
        case .riftBehemoth: return "裂隙巨兽"
        case .frostWarden: return "寒霜守望者"
        case .originArchitect: return "起源构造者"
        }
    }
}

enum BossCatalog {
    static let all: [BossType] = BossType.allCases
}

struct UpgradeOption {
    var title: String
    var detail: String
    var kind: Int
    var rarity: Int = UpgradeRarity.common.rawValue
}

final class Game: @unchecked Sendable {
    static let shared = Game()

    var phase: GamePhase = .menu
    /// Set by the menu's visible Exit action.  SDLFullGame consumes this after
    /// normal UI hit testing so the rendered action and its behavior cannot
    /// drift apart.
    var exitRequested = false
    var controlMode: ControlMode = .wasd
    var phaseBeforeControls: GamePhase = .menu
    var phaseBeforeSettings: GamePhase = .menu
    var phaseBeforeSaveSlots: GamePhase = .menu
    var confirmation: UIConfirmationKind?
    var selectedMission = 0
    var gameMode: GameMode = .campaign
    var runWon = false
    var missionBossSpawned = false
    var missionBossDefeated = false
    var profile = SaveManager.shared.profile
    var shipType: ShipType = .thunder
    var shipTraitTimer = 0.0
    var runCreditsEarned = 0
    var runCoresEarned = 0
    var runAlloyEarned = 0
    var runRareDropName = ""
    var runRareDropRarity = 0
    var hangarMessageTitle = ""
    var hangarMessageDetail = ""
    var hangarMessageTimer = 0.0
    var hangarTab = 0
    var selectedEquipmentSlot = 0
    var selectedVaultInventoryIndex: Int? = nil
    var vaultPage = 0
    var vaultFilterSlot: Int? = nil
    var vaultSortMode = 0
    var archiveTab = 0
    var codexCategory = CodexCategory.weapons
    var codexPage = 0
    var language: GameLanguage {
        GameLanguage(rawValue: profile.language) ?? .english
    }
    var visibleVaultIndices: [Int] {
        var indices = profile.inventory.indices.filter { index in
            guard let slot = vaultFilterSlot else { return true }
            return profile.inventory[index].slot == slot
        }
        if vaultSortMode == 0 {
            indices.sort { lhs, rhs in
                let left = profile.inventory[lhs]
                let right = profile.inventory[rhs]
                if left.rarity != right.rarity { return left.rarity > right.rarity }
                if left.level != right.level { return left.level > right.level }
                return left.name < right.name
            }
        } else if vaultSortMode == 1 {
            indices.sort { profile.inventory[$0].level > profile.inventory[$1].level }
        } else {
            indices.sort { profile.inventory[$0].slot < profile.inventory[$1].slot }
        }
        return indices
    }
    var vaultPageCount: Int {
        max(1, (visibleVaultIndices.count + 3) / 4)
    }
    var mousePosition = Vec2(x: 500, y: 630)
    var mousePrimaryDown = false
    var precisionMode = false
    var player = Vec2(x: 500, y: 630)
    var playerRadius = 18.0
    var coreRadius = 6.0
    var health = 120.0
    var maxHealth = 120.0
    var moveSpeed = 330.0
    var lastMoveDirection = Vec2(x: 0, y: -1)
    var dashCooldown = 0.0
    var damage = 18.0
    var fireCooldown = 0.24
    var fireTimer = 0.0
    var auxiliaryFireTimer = 0.65
    var secondaryFireTimer = 3.8
    var armorShieldCharges = 0
    var armorDamageReduction = 0.0
    var waveTimer = 1.2
    var waveIndex = 0
    var endlessWaveNumber = 1
    var endlessWavePhase: EndlessWavePhase = .combat
    var endlessWaveTimeRemaining = 36.0
    var survivalTime = 0.0
    var stage = 1
    var nextBossTime = 42.0
    var boss: Boss?
    var stageClearTimer = 0.0
    var stageBannerTimer = 0.0
    var stageBannerTitle = ""
    var stageBannerDetail = ""
    var bossDefeats = 0
    var enemyBulletClearPending = false
    var weaponType: WeaponType = .cannon
    var weaponLevel = 1
    var projectileDamageMultiplier = 1.0
    var projectilePenetration = 0
    var projectileCountBonus = 0
    var laserWidthLevel = 0
    var thunderGainMultiplier = 1.0
    var grazeRadiusBonus = 0.0
    var comboScoreMultiplier = 1.0
    var hasLaserCore = false
    var hasCryoCore = false
    var hasThunderCore = false
    var hasArrayCore = false
    var hasOverdriveCore = false
    var fireRateBoostTime = 0.0
    var shieldBreakSpeedTime = 0.0
    var bloodLeechTime = 0.0
    var bloodLeechCooldown = 0.0
    var notificationTitle = ""
    var notificationDetail = ""
    var notificationTimer = 0.0
    var notificationTint: COLORREF = 0
    var playerInvulnerability = 0.0
    var combo = 0
    var comboBest = 0
    var comboTimer = 0.0
    var grazeCount = 0
    var criticalChance = 0.12
    var criticalMultiplier = 2.0
    var thunderEnergy = 0.0
    var thunderOverloadTime = 0.0
    var cameraShakeTime = 0.0
    var cameraShakeStrength = 0.0
    let combatFeedback = CombatFeedbackSystem()
    var playerVisualOffset = Vec2.zero
    var playerHitFlash = 0.0
    var playerShieldFlash = 0.0
    var healthLag = 120.0
    var healthBarFlash = 0.0
    var damageEdgeFlash = 0.0
    var nextFeedbackID = 1
    var feedbackDebugIndex = 0
    var bossDebugIndex = 0
    var bossSmokePeakBullets = 0
    var bossSmokeAverageFrameMilliseconds = 0.0
    var uiDebugOverlay = false
    var uiAnimationTime = 0.0
    var score = 0
    var kills = 0
    var experience = 0
    var experienceGoal = 10
    var highScore = 0
    var enemies: [Enemy] = []
    var bullets: [Bullet] = []
    var bulletPool: [Bullet] = []
    let bulletLimit = 900
    var powerUps: [PowerUp] = []
    var particles: [Particle] = []
    var damageNumbers: [DamageNumber] = []
    var stars: [Star] = []
    var upgradeOptions: [UpgradeOption] = []
    var upgradeSelectionActive: Bool { phase == .playing && !upgradeOptions.isEmpty }
    // A run can develop two specialist doctrines. Repeated selections still
    // deepen an existing doctrine, but it cannot accumulate every core.
    var selectedBuildCoreKinds = Set<Int>()
    let particleLimit = 2200
    var lastTime = Date().timeIntervalSinceReferenceDate
    var nextFrameDeadline = Date().timeIntervalSinceReferenceDate
    private var fixedStepAccumulator = 0.0
    private let fixedStepDelta = 1.0 / 60.0
    var measuredFPS = 0.0
    private var presentedFrameCount = 0
    private var fpsWindowStart = Date().timeIntervalSinceReferenceDate
    var rng = SystemRandomNumberGenerator()

    var activeMission: MissionDefinition {
        MissionCatalog.all[min(max(0, selectedMission), MissionCatalog.all.count - 1)]
    }

    var unlockedMissionCount: Int {
        min(MissionCatalog.all.count, max(1, profile.unlockedMission))
    }

    var activeDifficultyMultiplier: Double {
        switch gameMode {
        case .campaign: return activeMission.difficulty
        case .endless: return endlessEnemyHealthMultiplier
        case .blitz: return 1.28
        case .zen: return 0.46
        }
    }

    var activeSpawnMultiplier: Double {
        switch gameMode {
        case .campaign: return 1.0 + Double(activeMission.id - 1) * 0.08
        case .endless: return 1.0
        case .blitz: return 1.48
        case .zen: return 1.32
        }
    }

    var activeEnemyDamageMultiplier: Double {
        switch gameMode {
        case .campaign: return 0.92 + activeMission.difficulty * 0.18
        case .endless: return endlessEnemyDamageMultiplier
        case .blitz: return 1.12
        case .zen: return 0.30
        }
    }

    /// Endless scaling deliberately uses separate, readable curves instead of
    /// multiplying every statistic by one aggressive factor. Wave one is the
    /// baseline; health grows 15%, damage 10%, fire rate 6.5%, and boss health
    /// 18% per cleared wave, each with a safety cap for very long sessions.
    private var endlessWaveExponent: Double { Double(max(0, endlessWaveNumber - 1)) }
    var endlessEnemyHealthMultiplier: Double {
        gameMode == .endless ? min(12, pow(1.15, endlessWaveExponent)) : 1
    }
    var endlessEnemyDamageMultiplier: Double {
        gameMode == .endless ? min(6, pow(1.10, endlessWaveExponent)) : 1
    }
    var endlessFireRateMultiplier: Double {
        gameMode == .endless ? min(2.5, pow(1.065, endlessWaveExponent)) : 1
    }
    var endlessBossHealthMultiplier: Double {
        gameMode == .endless ? min(30, pow(1.18, endlessWaveExponent)) : 1
    }

    var activePlayerDamageMultiplier: Double {
        switch gameMode {
        case .campaign: return 1.0
        case .endless: return 1.0
        case .blitz: return 1.30
        case .zen: return 1.12
        }
    }

    var activeRewardMultiplier: Double {
        switch gameMode {
        case .campaign: return activeMission.rewardMultiplier
        case .endless: return 1.0
        case .blitz: return 1.35
        case .zen: return 0.65
        }
    }

    var activeMissionDuration: Double {
        switch gameMode {
        case .campaign: return activeMission.duration
        case .endless: return .infinity
        case .blitz: return 72
        case .zen: return 120
        }
    }

    var activeKillGoal: Int {
        switch gameMode {
        case .blitz: return 45
        default: return 0
        }
    }

    var activeBossTime: Double {
        switch gameMode {
        case .campaign: return activeMission.bossTime
        case .endless: return 42
        case .blitz: return 30
        case .zen: return 64
        }
    }

    private func hasBuildCore(_ core: BuildCore) -> Bool {
        switch core {
        case .laser: return hasLaserCore
        case .cryo: return hasCryoCore
        case .thunder: return hasThunderCore && criticalChance >= 0.20
        case .array: return hasArrayCore
        case .overdrive: return hasOverdriveCore
        }
    }

    var activeSynergyIDs: Set<String> {
        Set(BuildSynergyCatalog.all.filter { definition in
            definition.required.allSatisfy { hasBuildCore($0) }
        }.map(\.id))
    }

    var frostRayActive: Bool { activeSynergyIDs.contains("frost_ray") }
    var stormCoreActive: Bool { activeSynergyIDs.contains("storm_crit") }
    var arrayOverdriveActive: Bool { activeSynergyIDs.contains("flight_array") }
    var overloadMatrixActive: Bool { activeSynergyIDs.contains("overload_matrix") }
    var weaponEvolutionTier: Int { min(5, max(1, (weaponLevel + 1) / 2)) }
    func weaponEvolutionLabel(for language: GameLanguage) -> String {
        let names = language == .chinese
            ? ["原型", "双联", "裂阵", "天穹", "终焉"]
            : ["PROTOTYPE", "TWIN-LINK", "BREACH", "SKYFALL", "APEX"]
        return names[min(names.count - 1, weaponEvolutionTier - 1)]
    }
    var effectiveFireCooldown: Double {
        let base: Double
        switch weaponType {
        case .missile: base = max(fireCooldown * 2.15, 0.32)
        case .electromagnetic: base = max(fireCooldown * 0.72, 0.065)
        default: base = fireCooldown
        }
        return fireRateBoostTime > 0 ? base / 1.5 : base
    }

    private init() {
        // Older builds kept the score in UserDefaults. Keep it as a one-time
        // migration source, then let the root-directory save own it.
        let legacyHighScore = UserDefaults.standard.integer(forKey: "SwiftSurvivor.highScore")
        highScore = max(profile.bestScore, legacyHighScore)
        if highScore > profile.bestScore {
            profile.bestScore = highScore
            SaveManager.shared.save(profile)
        }
    }

    func recordPresentedFrame(at now: Double) {
        presentedFrameCount += 1
        let elapsed = now - fpsWindowStart
        if elapsed >= 0.75 {
            measuredFPS = Double(presentedFrameCount) / elapsed
            presentedFrameCount = 0
            fpsWindowStart = now
        }
    }

    func resetFrameClock(at now: Double) {
        lastTime = now
        nextFrameDeadline = now
        fixedStepAccumulator = 0
        presentedFrameCount = 0
        fpsWindowStart = now
    }

    /// Advances gameplay at a deterministic 60 Hz. Rendering remains driven by
    /// the window timer, while a stalled frame is capped to avoid a catch-up
    /// spiral and frame-rate-dependent gameplay.
    func advanceFixed(realDelta: Double, width: Double, height: Double) {
        fixedStepAccumulator += min(max(realDelta, 0), 0.25)
        var steps = 0
        while fixedStepAccumulator >= fixedStepDelta && steps < 8 {
            update(delta: fixedStepDelta, width: width, height: height)
            fixedStepAccumulator -= fixedStepDelta
            steps += 1
        }
        if steps == 8 && fixedStepAccumulator > fixedStepDelta {
            fixedStepAccumulator = fixedStepDelta
        }
    }

    func start(width: Double, height: Double) {
        profile = SaveManager.shared.profile
        // Migrate legacy mouse-follow saves to keyboard-only flight.
        controlMode = .wasd
        profile.controlMode = ControlMode.wasd.rawValue
        AudioManager.shared.configure(bgmVolume: profile.bgmVolume, sfxVolume: profile.sfxVolume)
        // Retry the music when a sortie begins as well as at window creation.
        // This covers devices that become ready a moment after the menu first
        // appears and prevents a silent session after an early MCI failure.
        AudioManager.shared.startMusic()
        selectedMission = min(max(0, selectedMission), MissionCatalog.all.count - 1)
        if gameMode == .campaign {
            selectedMission = min(selectedMission, unlockedMissionCount - 1)
        }
        profile.totalRuns += 1
        persistProfile()
        phase = .playing
        runWon = false
        missionBossSpawned = false
        missionBossDefeated = false
        let field = playfieldBounds(width: width, height: height)
        player = Vec2(x: field.centerX, y: field.bottom - 100)
        mousePosition = player
        precisionMode = false
        lastMoveDirection = Vec2(x: 0, y: -1)
        dashCooldown = 0
        shipType = ShipType(rawValue: profile.selectedShip) ?? .thunder
        shipTraitTimer = 12.0
        let frameLevel = profile.equipment.first(where: { $0.slot == 0 })?.level ?? 1
        let primaryLevel = profile.equipment.first(where: { $0.slot == 1 })?.level ?? 1
        let secondaryLevel = profile.equipment.first(where: { $0.slot == 2 })?.level ?? 1
        let armorLevel = profile.equipment.first(where: { $0.slot == 3 })?.level ?? 1
        let droneLevel = profile.equipment.first(where: { $0.slot == 4 })?.level ?? 1
        let primaryItem = profile.equipment.first(where: { $0.slot == 1 })
        let armorItem = profile.equipment.first(where: { $0.slot == 3 })
        let secondaryItem = profile.equipment.first(where: { $0.slot == 2 })
        var shipHealthMultiplier = 1.0
        var shipDamageMultiplier = 1.0
        var shipSpeedMultiplier = 1.0
        criticalChance = 0.12
        criticalMultiplier = 2.0
        switch shipType {
        case .thunder:
            criticalChance = 0.17
        case .ghost:
            shipHealthMultiplier = 0.90
            shipSpeedMultiplier = 1.12
        case .heavy:
            shipHealthMultiplier = 1.38
            shipDamageMultiplier = 0.94
            shipSpeedMultiplier = 0.88
        case .destroyer:
            shipHealthMultiplier = 0.88
            shipDamageMultiplier = 1.25
        case .carrier:
            shipHealthMultiplier = 1.08
            shipDamageMultiplier = 1.08
            shipSpeedMultiplier = 0.95
        }
        maxHealth = (120 + Double(max(0, frameLevel - 1)) * 8 + Double(max(0, armorLevel - 1)) * 4) * shipHealthMultiplier
        health = maxHealth
        moveSpeed = 330 * shipSpeedMultiplier
        let rarityMultiplier = 1.0 + Double(primaryItem?.rarity ?? 0) * 0.06 + Double(secondaryItem?.rarity ?? 0) * 0.02
        fireCooldown = 0.24
        damage = (18 + Double(max(0, primaryLevel - 1)) * 1.5 + Double(max(0, droneLevel - 1)) * 0.6) * shipDamageMultiplier * rarityMultiplier * activePlayerDamageMultiplier
        if primaryItem?.affix == 1 { damage *= 1.10 }
        if primaryItem?.affix == 2 { criticalChance = min(0.75, criticalChance + 0.05) }
        if primaryItem?.affix == 3 { fireCooldown *= 0.90 }
        armorDamageReduction = min(0.28, 0.08 + Double(max(0, armorLevel - 1)) * 0.012)
        if armorItem?.id.contains("frost") == true { armorDamageReduction = min(0.32, armorDamageReduction + 0.04) }
        if armorItem?.affix == 4 { armorDamageReduction = min(0.36, armorDamageReduction + 0.06) }
        // Armor and pickup shields share one non-stackable defensive layer.
        armorShieldCharges = 1
        fireTimer = 0.10
        auxiliaryFireTimer = 0.65
        secondaryFireTimer = max(2.8, 4.6 - Double(secondaryLevel) * 0.12)
        waveTimer = 1.20
        waveIndex = 0
        endlessWaveNumber = 1
        endlessWavePhase = .combat
        endlessWaveTimeRemaining = 36.0
        survivalTime = 0
        stage = 1
        nextBossTime = activeBossTime
        boss = nil
        stageClearTimer = 0
        stageBannerTimer = 0
        stageBannerTitle = ""
        stageBannerDetail = ""
        bossDefeats = 0
        enemyBulletClearPending = false
        weaponType = WeaponType(rawValue: profile.equippedWeapon) ?? .cannon
        // In-run weapon growth has no level cap. Pattern thresholds still
        // unlock naturally, while later upgrades continue adding firepower.
        weaponLevel = max(1, 1 + primaryLevel / 5 + (primaryItem?.evolution ?? 0))
        projectileDamageMultiplier = 1.0
        projectilePenetration = max(0, (primaryItem?.stars ?? 1) - 1)
        projectileCountBonus = 0
        laserWidthLevel = min(4, primaryItem?.evolution ?? 0)
        thunderGainMultiplier = 1.0
        grazeRadiusBonus = 0.0
        comboScoreMultiplier = 1.0
        hasLaserCore = false
        hasCryoCore = false
        hasThunderCore = false
        hasArrayCore = false
        hasOverdriveCore = false
        fireRateBoostTime = 0
        shieldBreakSpeedTime = 0
        bloodLeechTime = 0
        bloodLeechCooldown = 0
        notificationTitle = ""
        notificationDetail = ""
        notificationTimer = 0
        playerInvulnerability = 0
        combo = 0
        comboBest = 0
        grazeCount = 0
        comboTimer = 0
        thunderEnergy = 0
        thunderOverloadTime = 0
        cameraShakeTime = 0
        cameraShakeStrength = 0
        playerVisualOffset = .zero
        playerHitFlash = 0
        playerShieldFlash = 0
        healthLag = maxHealth
        healthBarFlash = 0
        damageEdgeFlash = 0
        nextFeedbackID = 1
        feedbackDebugIndex = 0
        bossDebugIndex = 0
        combatFeedback.reset()
        score = 0
        kills = 0
        runCreditsEarned = 0
        runCoresEarned = 0
        runAlloyEarned = 0
        runRareDropName = ""
        runRareDropRarity = 0
        experience = 0
        experienceGoal = 10
        enemies.removeAll(keepingCapacity: true)
        recycleAllBullets()
        powerUps.removeAll(keepingCapacity: true)
        particles.removeAll(keepingCapacity: true)
        damageNumbers.removeAll(keepingCapacity: true)
        upgradeOptions.removeAll()
        selectedBuildCoreKinds.removeAll(keepingCapacity: true)
        if stars.isEmpty { initializeStars(width: width, height: height) }
    }

    func update(delta rawDelta: Double, width: Double, height: Double) {
        let realDelta = min(max(rawDelta, 0), 0.05)
        uiAnimationTime += realDelta
        if stars.isEmpty { initializeStars(width: width, height: height) }
        if phase == .menu || phase == .saveSlots || phase == .missionSelect || phase == .controls || phase == .hangar || phase == .settings || phase == .archive {
            updateStars(delta: realDelta, height: height)
            updateParticles(delta: realDelta)
            hangarMessageTimer = max(0, hangarMessageTimer - realDelta)
            return
        }
        // The death/defeat screen still needs to advance presentation-only feedback.
        // Gameplay remains stopped, while particles, damage numbers, hit flashes and
        // the delayed health bar are allowed to finish their short animations.
        if phase == .gameOver {
            updateStars(delta: realDelta, height: height)
            updateParticles(delta: realDelta)
            updateDamageNumbers(delta: realDelta)
            _ = combatFeedback.advance(realDelta: realDelta, game: self)
            return
        }
        guard phase == .playing else { return }
        updateStars(delta: realDelta, height: height)
        updateParticles(delta: realDelta)
        updateDamageNumbers(delta: realDelta)
        let gameplayDelta = combatFeedback.advance(realDelta: realDelta, game: self)
        guard gameplayDelta > 0 else { return }
        let delta = gameplayDelta

        survivalTime += delta
        stage = gameMode == .campaign ? activeMission.id : (gameMode == .endless ? endlessWaveNumber : Int(survivalTime / 45.0) + 1)
        fireRateBoostTime = max(0, fireRateBoostTime - delta)
        shieldBreakSpeedTime = max(0, shieldBreakSpeedTime - delta)
        bloodLeechTime = max(0, bloodLeechTime - delta)
        bloodLeechCooldown = max(0, bloodLeechCooldown - delta)
        notificationTimer = max(0, notificationTimer - delta)
        stageClearTimer = max(0, stageClearTimer - delta)
        stageBannerTimer = max(0, stageBannerTimer - delta)
        playerInvulnerability = max(0, playerInvulnerability - delta)
        dashCooldown = max(0, dashCooldown - delta)
        thunderOverloadTime = max(0, thunderOverloadTime - delta)
        comboTimer = max(0, comboTimer - delta)
        if comboTimer <= 0 { combo = 0 }
        shipTraitTimer = max(0, shipTraitTimer - delta)
        if shipType == .ghost, shipTraitTimer <= 0 {
            playerInvulnerability = max(playerInvulnerability, 1.2)
            shipTraitTimer = 18.0
            notifyPickup(title: "GHOST PHASE", detail: "Periodic immunity window activated", tint: rgb(169, 200, 255))
        }

        var direction = Vec2.zero
        precisionMode = keyDown(0x10) // Shift: slow, precise steering
        if keyDown(0x41) || keyDown(0x25) { direction.x -= 1 } // A / left
        if keyDown(0x44) || keyDown(0x27) { direction.x += 1 } // D / right
        if keyDown(0x57) || keyDown(0x26) { direction.y -= 1 } // W / up
        if keyDown(0x53) || keyDown(0x28) { direction.y += 1 } // S / down
        if direction.length > 0 {
            lastMoveDirection = direction.normalized
            let boostedMoveSpeed = moveSpeed * (shieldBreakSpeedTime > 0 ? 1.30 : 1.0)
            let speed = precisionMode ? boostedMoveSpeed * CombatConfig.precisionSpeedMultiplier : boostedMoveSpeed
            player = player + direction.normalized * speed * delta
        }
        let field = playfieldBounds(width: width, height: height)
        player.x = min(max(player.x, field.left + playerRadius + 10), field.right - playerRadius - 10)
        player.y = min(max(player.y, field.top + playerRadius + 10), field.bottom - playerRadius - 12)

        if gameMode == .endless, stageClearTimer <= 0, endlessWavePhase == .combat {
            endlessWaveTimeRemaining = max(0, endlessWaveTimeRemaining - delta)
            if endlessWaveTimeRemaining <= 0, boss == nil {
                endlessWavePhase = .boss
                stageBannerTimer = 2.2
                stageBannerTitle = uiText("WAVE \(endlessWaveNumber) BOSS", "第 \(endlessWaveNumber) 波首领")
                stageBannerDetail = uiText("NORMAL FLOW COMPLETE  •  BOSS INBOUND", "常规战结束  •  首领正在接近")
                spawnBoss(field: field)
            }
        }

        let normalWaveSpawningAllowed = gameMode != .endless || endlessWavePhase == .combat
        if stageClearTimer <= 0, boss == nil, normalWaveSpawningAllowed {
            waveTimer -= delta
            if waveTimer <= 0 {
                spawnWave(field: field)
                waveTimer = nextWaveDelay()
            }
        }

        let canSpawnAnotherBoss = gameMode != .endless && !missionBossSpawned
        if stageClearTimer <= 0, survivalTime >= nextBossTime, boss == nil, canSpawnAnotherBoss {
            spawnBoss(field: field)
        }

        let modeObjectiveComplete = activeKillGoal == 0 || kills >= activeKillGoal
        if gameMode.isFinite, stageClearTimer <= 0, survivalTime >= activeMissionDuration,
           boss == nil, missionBossDefeated, modeObjectiveComplete {
            completeMission()
            return
        }

        fireTimer -= delta
        if fireTimer <= 0 {
            fireWeapon()
            fireTimer = effectiveFireCooldown
        }
        auxiliaryFireTimer -= delta
        if auxiliaryFireTimer <= 0 {
            fireAuxiliaryWeapon()
            let droneLevel = profile.equipment.first(where: { $0.slot == 4 })?.level ?? 1
            auxiliaryFireTimer = max(0.28, 0.82 - Double(droneLevel) * 0.025)
        }
        secondaryFireTimer -= delta
        if secondaryFireTimer <= 0 {
            fireSecondaryWeapon()
            secondaryFireTimer = max(2.8, 6.4 - Double(profile.equipment.first(where: { $0.slot == 2 })?.level ?? 1) * 0.22)
        }

        if stageClearTimer <= 0 {
            updateEnemies(delta: delta, field: field)
            updateBoss(delta: delta, field: field)
        } else {
            clearEnemyBullets()
        }
        updateBullets(delta: delta, field: field)
        updatePowerUps(delta: delta, field: field)

        if health <= 0 {
            health = 0
            combatFeedback.play(.playerKilled,
                                context: FeedbackContext(position: player, level: .critical, tint: rgb(255, 118, 140)), game: self)
            phase = .gameOver
            profile.bestCombo = max(profile.bestCombo, comboBest)
            profile.bestScore = max(profile.bestScore, score)
            if score > highScore {
                highScore = score
            }
            persistProfile()
        }
    }

    private func initializeStars(width: Double, height: Double) {
        stars.removeAll(keepingCapacity: true)
        for _ in 0..<100 {
            let brightness = UInt32.random(in: 90...220, using: &rng)
            let tint = rgb(brightness / 2, brightness / 2 + 25, brightness)
            stars.append(Star(position: Vec2(x: Double.random(in: 0...width, using: &rng),
                                             y: Double.random(in: 68...height, using: &rng)),
                              speed: Double.random(in: 20...115, using: &rng),
                              radius: Double.random(in: 1...2.7, using: &rng),
                              tint: tint))
        }
    }

    private func updateStars(delta: Double, height: Double) {
        for index in stars.indices {
            stars[index].position.y += stars[index].speed * delta
            if stars[index].position.y > height + 5 {
                stars[index].position.y = 70
            }
        }
    }

    private func spawnWave(field: PlayfieldBounds) {
        let plannedWave = waveIndex
        let isSwarmWave = survivalTime >= 22 && plannedWave % 7 == 5
        let isEliteWave = survivalTime >= 38 && plannedWave % 6 == 0
        let formation = waveIndex % 3
        let baseCount = survivalTime < 20 ? 2 : (survivalTime < 60 ? 3 : 4)
        let requestedCount = isSwarmWave ? 9 + min(3, waveIndex / 12) : baseCount + waveIndex / 8
        let count = min(isSwarmWave ? 12 : 10, max(1, Int((Double(requestedCount) * activeSpawnMultiplier).rounded(.down))))
        let spacing = min(92.0, max(58.0, field.width / Double(count + 1)))
        let center = field.centerX
        for index in 0..<count {
            var x = center + (Double(index) - Double(count - 1) / 2) * spacing
            var y = 74.0 - Double(index % 2) * 30
            var pattern = formation
            if formation == 1 {
                x = center + (Double(index) - Double(count - 1) / 2) * spacing
                y = 78 + abs(Double(index) - Double(count - 1) / 2) * 28
            } else if formation == 2 {
                x = field.left + 35 + Double(index) * (field.width - 70) / Double(max(1, count - 1))
                y = 72 + Double(index % 3) * 18
                pattern = 2
            }
            x = min(max(x, field.left + 30), field.right - 30)
            y = max(field.top + 4, y)
            let isElite = isEliteWave && index == count / 2
            let type: Int
            if isSwarmWave {
                type = index % 5 == 0 ? EnemyType.diver.rawValue : EnemyType.fighter.rawValue
            } else if isElite {
                type = plannedWave % 2 == 0 ? EnemyType.turret.rawValue : EnemyType.carrier.rawValue
            } else if isEliteWave, index % 3 == 0 {
                type = EnemyType.shield.rawValue
            } else {
                type = enemyTypeForWave(index: index, formation: formation)
            }
            spawnEnemy(position: Vec2(x: x, y: y), pattern: pattern, type: type,
                       elite: isElite, healthScale: isSwarmWave ? CombatConfig.swarmHealthMultiplier : 1)
        }
        if isEliteWave {
            notifyPickup(title: uiText("ELITE CONTACT", "精英来袭"),
                         detail: uiText("Clear escorts, then claim the reward", "先清理护卫，再击破精英获取奖励"),
                         tint: rgb(255, 204, 112))
        } else if isSwarmWave {
            notifyPickup(title: uiText("SWARM WAVE", "歼灭波次"),
                         detail: uiText("Low armor • build Combo and Thunder", "低护甲敌群 • 快速积累连击与雷霆"),
                         tint: rgb(126, 220, 255))
        }
        waveIndex += 1
    }

    private func nextWaveDelay() -> Double {
        let completedWave = max(0, waveIndex - 1)
        if survivalTime >= 22 && completedWave % 7 == 5 { return 3.15 }
        if survivalTime >= 38 && completedWave % 6 == 0 { return 3.45 }
        let ramp = min(survivalTime / 180.0, 1.0)
        return 1.95 - ramp * 0.82
    }

    private func enemyTypeForWave(index: Int, formation: Int) -> Int {
        // Keep the opening gentle, then introduce one new threat at a time.
        if survivalTime < 18 { return EnemyType.fighter.rawValue }
        let roll = (waveIndex + index * 3 + formation) % 12
        if survivalTime < 34 {
            return roll % 5 == 0 ? EnemyType.diver.rawValue : (roll % 5 == 1 ? EnemyType.turret.rawValue : EnemyType.fighter.rawValue)
        }
        if survivalTime < 65 {
            switch roll {
            case 0: return EnemyType.sniper.rawValue
            case 1: return EnemyType.shield.rawValue
            case 2: return EnemyType.diver.rawValue
            default: return EnemyType.fighter.rawValue
            }
        }
        switch roll {
        case 0: return EnemyType.carrier.rawValue
        case 1, 2: return EnemyType.kamikaze.rawValue
        case 3: return EnemyType.sniper.rawValue
        case 4: return EnemyType.shield.rawValue
        case 5: return EnemyType.turret.rawValue
        default: return EnemyType.fighter.rawValue
        }
    }

    private func spawnEnemy(position: Vec2, pattern: Int, type: Int = EnemyType.fighter.rawValue,
                            elite: Bool = false, healthScale: Double = 1) {
        let enemyType = EnemyType(rawValue: type) ?? .fighter
        let radius: Double
        let hpMultiplier: Double
        let speed: Double
        let tint: COLORREF
        let initialShoot: Double
        switch enemyType {
        case .diver:
            radius = 18; hpMultiplier = 1.05; speed = 64; tint = rgb(244, 139, 67); initialShoot = 2.7
        case .turret:
            radius = 23; hpMultiplier = 1.70; speed = 34; tint = rgb(246, 191, 75); initialShoot = 1.4
        case .sniper:
            radius = 20; hpMultiplier = 1.25; speed = 45; tint = rgb(163, 125, 255); initialShoot = 2.1
        case .shield:
            radius = 21; hpMultiplier = 1.45; speed = 48; tint = rgb(83, 214, 185); initialShoot = 2.5
        case .kamikaze:
            radius = 16; hpMultiplier = 0.85; speed = 70; tint = rgb(255, 88, 103); initialShoot = 99
        case .carrier:
            radius = 28; hpMultiplier = 2.4; speed = 28; tint = rgb(193, 93, 237); initialShoot = 2.4
        case .fighter:
            radius = pattern == 2 ? 19 : 17; hpMultiplier = 1.0; speed = 54; tint = pattern == 1 ? rgb(232, 101, 68) : (pattern == 2 ? rgb(177, 77, 224) : rgb(235, 65, 108)); initialShoot = Double.random(in: 2.2...3.8, using: &rng)
        }
        let hp = (24.0 + survivalTime * 0.22 + Double(stage - 1) * 10) * hpMultiplier * healthScale
            * (elite ? CombatConfig.eliteHealthMultiplier : 1) * activeDifficultyMultiplier
        let feedbackID = nextFeedbackID
        nextFeedbackID &+= 1
        enemies.append(Enemy(feedbackID: feedbackID,
                             position: position,
                             baseX: position.x,
                             radius: radius,
                             speed: (speed + survivalTime * 0.04 + Double(stage - 1) * 7) * (elite ? 0.90 : 1) * (0.88 + activeDifficultyMultiplier * 0.12),
                             health: hp,
                             maxHealth: hp,
                             tint: tint,
                             pattern: pattern,
                             age: 0,
                             phase: Double.random(in: 0...6.28, using: &rng),
                             shootTimer: initialShoot,
                             type: enemyType.rawValue,
                             isElite: elite))
    }

    private func spawnBoss(field: PlayfieldBounds) {
        // Swift's checked integer arithmetic emits a CPU trap on overflow.
        // Keep restored and long-running session values bounded so an invalid
        // value cannot surface on Windows as the 0xc000001d boss-spawn crash.
        let safeStage = min(10_000, max(1, stage))
        let safeTime = survivalTime.isFinite ? min(1_000_000, max(0, survivalTime)) : 0
        // Endless bosses have their own 18% per-wave curve below. Reusing the
        // normal-enemy health curve here would compound both curves and create
        // an unintended ~36% jump per wave.
        let rawDifficulty = gameMode == .endless ? 1.0 : activeDifficultyMultiplier
        let safeDifficulty = rawDifficulty.isFinite ? min(100, max(0.05, rawDifficulty)) : 1
        let bossCount = BossCatalog.all.count
        guard bossCount > 0 else { return }
        missionBossSpawned = true
        let baseBossHealth = gameMode == .endless
            ? 650.0
            : 650 + Double(safeStage - 1) * 180 + safeTime * 2.2
        let hp = min(100_000_000, baseBossHealth * safeDifficulty
            * ThunderCarrierBossDefinition.healthMultiplier * endlessBossHealthMultiplier)
        var newBoss = Boss(position: Vec2(x: field.centerX, y: -100), health: hp, maxHealth: hp, age: 0, shootTimer: 1.6)
        let safeMission = min(100_000, max(0, selectedMission))
        let safeDefeats = min(100_000, max(0, bossDefeats))
        newBoss.kind = (safeMission + safeDefeats) % bossCount
        newBoss.leftTurretHealth = hp * 0.18
        newBoss.rightTurretHealth = hp * 0.18
        newBoss.leftTurretMaxHealth = newBoss.leftTurretHealth
        newBoss.rightTurretMaxHealth = newBoss.rightTurretHealth
        newBoss.laserCooldown = gameMode == .zen ? 8.0 : 5.0
        newBoss.laserX = field.centerX
        newBoss.laserTargetX = field.centerX
        newBoss.attackTarget = player
        boss = newBoss
        waveTimer = 2.4
        clearEnemyBullets()
        enemies.removeAll(keepingCapacity: true)
        spawnExplosion(at: Vec2(x: field.centerX, y: field.top + 22), tint: rgb(210, 70, 245), count: 30)
        AudioManager.shared.playSFX("sfx_boss")
    }

    private func spawnBullet(_ bullet: Bullet) {
        if bullets.count >= bulletLimit, !bullet.playerOwned { return }
        if var recycled = bulletPool.popLast() {
            recycled = bullet
            bullets.append(recycled)
        } else {
            bullets.append(bullet)
        }
    }

    @discardableResult
    private func recycleBullet(at index: Int, preservingOriginalCount: Int? = nil) -> Bool {
        guard bullets.indices.contains(index) else { return false }
        // During the frame update, split bullets can be appended while the
        // original bullets are being scanned. Remove from the original range
        // so a freshly spawned child is never accidentally recycled. Swapping
        // avoids shifting the whole active array for the common case.
        let removalIndex: Int
        if let preservingOriginalCount {
            removalIndex = min(max(0, preservingOriginalCount - 1), bullets.count - 1)
        } else {
            removalIndex = bullets.count - 1
        }
        let recycled = bullets[index]
        if index != removalIndex {
            bullets.swapAt(index, removalIndex)
        }
        bullets.remove(at: removalIndex)
        bulletPool.append(recycled)
        if bulletPool.count > bulletLimit * 2 { bulletPool.removeLast(bulletPool.count - bulletLimit * 2) }
        return true
    }

    private func recycleAllBullets() {
        bulletPool.append(contentsOf: bullets)
        bullets.removeAll(keepingCapacity: true)
        if bulletPool.count > bulletLimit * 2 { bulletPool.removeLast(bulletPool.count - bulletLimit * 2) }
    }

    private func clearEnemyBullets(fraction: Double = 1.0) {
        let clampedFraction = min(1.0, max(0.0, fraction))
        let enemyIndices = bullets.indices.filter { !bullets[$0].playerOwned }
        let clearCount = Int((Double(enemyIndices.count) * clampedFraction).rounded(.up))
        guard clearCount > 0 else { return }

        // A partial Thunder Burst removes the bullets that threaten the player
        // first. Rebuild only for this rare special action; normal bullet
        // lifetime still uses the pool's O(1) swap-and-recycle path.
        let dangerOrdered = enemyIndices.sorted {
            let left = bullets[$0].position - player
            let right = bullets[$1].position - player
            return left.x * left.x + left.y * left.y < right.x * right.x + right.y * right.y
        }
        let removalSet = Set(dangerOrdered.prefix(clearCount))
        var survivors: [Bullet] = []
        survivors.reserveCapacity(bullets.count - removalSet.count)
        for (index, bullet) in bullets.enumerated() {
            if removalSet.contains(index) {
                bulletPool.append(bullet)
            } else {
                survivors.append(bullet)
            }
        }
        bullets = survivors
        if bulletPool.count > bulletLimit * 2 { bulletPool.removeLast(bulletPool.count - bulletLimit * 2) }
    }

    private func fireWeapon() {
        AudioManager.shared.playSFX("sfx_shoot")
        let laserBoost = weaponType == .laser ? (frostRayActive ? 2.0 : 1.6) : 1.0
        let origin = player + Vec2(x: 0, y: -22)
        switch weaponType {
        case .cannon:
            let baseSpread: [Double]
            switch min(weaponLevel, 7) {
            case 2: baseSpread = [-0.055, 0.055]
            case 3: baseSpread = [-0.11, 0, 0.11]
            case 4: baseSpread = [-0.16, -0.055, 0.055, 0.16]
            case 5: baseSpread = [-0.20, -0.10, 0, 0.10, 0.20]
            case 6: baseSpread = [-0.26, -0.17, -0.085, 0, 0.085, 0.17, 0.26]
            case 7: baseSpread = [-0.32, -0.21, -0.105, 0, 0.105, 0.21, 0.32]
            default: baseSpread = [0]
            }
            var spread = baseSpread
            let auxiliaryCount = projectileCountBonus + (arrayOverdriveActive ? 1 : 0)
            for index in 0..<min(auxiliaryCount, 3) {
                let offset = 0.38 + Double(index) * 0.065
                spread.append(-offset)
                spread.append(offset)
            }
            for angle in spread {
                appendPlayerBullet(origin: origin, angle: angle, speed: 720, radius: 4.5,
                                   damage: damage * projectileDamageMultiplier * laserBoost,
                                   life: 2.0, tint: laserBoost > 1.0 && frostRayActive ? rgb(174, 239, 255) : rgb(155, 239, 255),
                                   pierce: projectilePenetration)
            }
        case .laser:
            var beamAngles: [Double] = [0]
            if weaponLevel >= 3 { beamAngles = [-0.018, 0.018] }
            if weaponLevel >= 6 { beamAngles = [-0.032, 0, 0.032] }
            for angle in beamAngles {
                appendPlayerBullet(origin: origin, angle: angle, speed: 900, radius: 5.5 + Double(laserWidthLevel) * 0.6,
                                   damage: damage * projectileDamageMultiplier * 1.18 * laserBoost,
                                   life: 1.55, tint: frostRayActive ? rgb(174, 239, 255) : rgb(112, 224, 255),
                                   pierce: max(2, projectilePenetration + 3), style: WeaponType.laser.rawValue)
            }
        case .scatter:
            let pelletCount = min(13, 3 + weaponLevel + projectileCountBonus + (arrayOverdriveActive ? 1 : 0))
            let spreadAngle = 0.72
            for index in 0..<pelletCount {
                let t = pelletCount == 1 ? 0.5 : Double(index) / Double(pelletCount - 1)
                let angle = -spreadAngle + t * spreadAngle * 2
                appendPlayerBullet(origin: origin, angle: angle, speed: 650, radius: 5.0,
                                   damage: damage * projectileDamageMultiplier * 0.68 * laserBoost,
                                   life: 1.35, tint: rgb(255, 202, 119), pierce: projectilePenetration,
                                   style: WeaponType.scatter.rawValue)
            }
        case .missile:
            let missileCount = min(6, 1 + (weaponLevel >= 4 ? 1 : 0) + (weaponLevel >= 7 ? 2 : 0) + projectileCountBonus)
            let spreadAngle = missileCount == 1 ? 0 : (weaponLevel >= 7 ? 0.24 : 0.16)
            for index in 0..<missileCount {
                let angle = missileCount == 1 ? 0 : (Double(index) - Double(missileCount - 1) / 2) * (spreadAngle * 2 / Double(max(1, missileCount - 1)))
                appendPlayerBullet(origin: origin, angle: angle, speed: 430, radius: 7.0,
                                   damage: damage * projectileDamageMultiplier * 1.72,
                                   life: 3.4, tint: rgb(255, 133, 92), pierce: projectilePenetration,
                                   style: WeaponType.missile.rawValue)
            }
        case .electromagnetic:
            let orbCount = min(6, 1 + (weaponLevel >= 3 ? 1 : 0) + (weaponLevel >= 6 ? 1 : 0) + (weaponLevel >= 7 ? 1 : 0) + projectileCountBonus)
            let spreadAngle = orbCount == 1 ? 0 : (weaponLevel >= 7 ? 0.34 : 0.22)
            for index in 0..<orbCount {
                let t = orbCount == 1 ? 0.5 : Double(index) / Double(orbCount - 1)
                let angle = -spreadAngle + t * spreadAngle * 2
                appendPlayerBullet(origin: origin, angle: angle, speed: 560, radius: 7.0,
                                   damage: damage * projectileDamageMultiplier * 0.82,
                                   life: 2.2, tint: rgb(191, 133, 255), pierce: max(1, projectilePenetration),
                                   style: WeaponType.electromagnetic.rawValue)
            }
        }
    }

    private func fireAuxiliaryWeapon() {
        let droneLevel = profile.equipment.first(where: { $0.slot == 4 })?.level ?? 1
        let droneItem = profile.equipment.first(where: { $0.slot == 4 })
        let count = min(4, 1 + droneLevel / 4 + (shipType == .carrier ? 1 : 0))
        let isStormDrone = droneItem?.id.contains("storm") == true
        let isFrostDrone = droneItem?.id.contains("frost") == true
        for index in 0..<count {
            let side = index % 2 == 0 ? -1.0 : 1.0
            let lane = Double(index / 2)
            let origin = player + Vec2(x: side * (28 + lane * 13), y: -8)
            let angle = side * (isStormDrone ? (0.16 + lane * 0.05) : (0.10 + lane * 0.035))
            let tint = isStormDrone ? rgb(194, 156, 255) : (isFrostDrone ? rgb(169, 239, 255) : rgb(118, 210, 255))
            appendPlayerBullet(origin: origin,
                               angle: angle,
                               speed: isFrostDrone ? 680 : 620,
                               radius: isStormDrone ? 5.0 : 4.0,
                               damage: damage * (shipType == .carrier ? 0.44 : 0.32) * (isStormDrone ? 1.14 : 1.0),
                               life: isFrostDrone ? 1.95 : 1.85,
                               tint: tint,
                               pierce: max(0, projectilePenetration - 1),
                               style: isFrostDrone ? WeaponType.laser.rawValue : (isStormDrone ? WeaponType.electromagnetic.rawValue : WeaponType.cannon.rawValue))
        }
    }

    private func fireSecondaryWeapon() {
        let item = profile.equipment.first(where: { $0.slot == 2 })
        let level = item?.level ?? 1
        let isMissile = item?.id.contains("missile") == true || item?.id.contains("nova") == true
        let isFrost = item?.id.contains("frost") == true
        let isStorm = item?.id.contains("storm") == true
        let count = min(4, 1 + level / 8 + (isStorm ? 1 : 0))
        for index in 0..<count {
            let spread = isFrost ? 0.24 : (isStorm ? 0.30 : 0.16)
            let angle = count == 1 ? 0 : (Double(index) - Double(count - 1) / 2) * spread
            let explosive = isMissile && !isStorm
            appendPlayerBullet(origin: player + Vec2(x: 0, y: -20),
                               angle: angle,
                               speed: explosive ? 390 : (isFrost ? 560 : 510),
                               radius: explosive ? 7.5 : 5.5,
                               damage: damage * (explosive ? 1.15 : (isFrost ? 0.86 : 0.72)),
                               life: explosive ? 3.1 : (isFrost ? 2.25 : 2.0),
                               tint: explosive ? rgb(255, 144, 96) : (isFrost ? rgb(152, 232, 255) : rgb(242, 205, 106)),
                               pierce: isFrost ? max(1, projectilePenetration + 1) : projectilePenetration,
                               style: explosive ? WeaponType.missile.rawValue : (isFrost ? WeaponType.laser.rawValue : WeaponType.electromagnetic.rawValue))
        }
    }

    private func appendPlayerBullet(origin: Vec2, angle: Double, speed: Double, radius: Double, damage: Double, life: Double, tint: COLORREF, pierce: Int, style: Int = WeaponType.cannon.rawValue) {
        spawnBullet(Bullet(position: origin,
                              velocity: rotated(Vec2(x: 0, y: -1), by: angle) * speed,
                              radius: radius,
                              damage: damage,
                              life: life,
                              playerOwned: true,
                              tint: tint,
                              bulletType: style == WeaponType.missile.rawValue ? BulletType.explosive.rawValue : (style == WeaponType.laser.rawValue ? BulletType.laser.rawValue : BulletType.normal.rawValue),
                              modifiers: style == WeaponType.missile.rawValue ? [.constantVelocity, .homing] : (style == WeaponType.electromagnetic.rawValue ? [.constantVelocity, .sineWave] : [.constantVelocity]),
                              pierceRemaining: pierce,
                              weaponStyle: style,
                              modifierPhase: Double.random(in: 0...(Double.pi * 2), using: &rng),
                              homingTimeRemaining: style == WeaponType.missile.rawValue ? 1.8 : 0,
                              maxTurnRate: style == WeaponType.missile.rawValue ? 2.6 : 0,
                              acceleration: 0))
    }

    private func nearestTargetPosition(from origin: Vec2) -> Vec2? {
        var nearest: Vec2?
        var nearestDistanceSquared = Double.greatestFiniteMagnitude
        if let currentBoss = boss {
            nearest = currentBoss.position
            nearestDistanceSquared = distanceSquared(origin, currentBoss.position)
        }
        for enemy in enemies {
            let candidateDistanceSquared = distanceSquared(origin, enemy.position)
            if candidateDistanceSquared < nearestDistanceSquared {
                nearest = enemy.position
                nearestDistanceSquared = candidateDistanceSquared
            }
        }
        return nearest
    }

    private func emitPattern(_ emitter: BulletEmitter, from origin: Vec2, target: Vec2? = nil, playerOwned: Bool = false, weaponStyle: Int = WeaponType.cannon.rawValue) {
        let count = max(1, emitter.count)
        var angles: [Double]
        switch emitter.pattern {
        case .single:
            angles = [0]
        case .aimed:
            if count == 1 {
                angles = [0]
            } else {
                angles = (0..<count).map { index in
                    let t = Double(index) / Double(count - 1)
                    return -emitter.spread * 0.45 + t * emitter.spread * 0.9
                }
            }
        case .triple:
            angles = [-emitter.spread, 0, emitter.spread]
        case .spread:
            angles = (0..<count).map { index in
                let t = count == 1 ? 0.5 : Double(index) / Double(count - 1)
                return -emitter.spread + t * emitter.spread * 2
            }
        case .ring:
            angles = (0..<count).map { index in
                let t = count == 1 ? 0.5 : Double(index) / Double(count - 1)
                return -Double.pi / 2 + t * Double.pi
            }
        case .spiral:
            angles = (0..<count).map { index in
                let t = count == 1 ? 0.5 : Double(index) / Double(count - 1)
                return -Double.pi / 2 + t * Double.pi + emitter.rotation
            }
        }
        for angle in angles {
            var direction: Vec2
            if emitter.pattern == .aimed, let target {
                direction = rotated((target - origin).normalized, by: angle)
            } else {
                direction = rotated(Vec2(x: 0, y: playerOwned ? -1 : 1), by: angle)
            }
            if !playerOwned, direction.y < 0.22 {
                direction.y = 0.22
                direction = direction.normalized
            }
            let bullet = Bullet(position: origin,
                                velocity: direction * emitter.speed,
                                radius: emitter.radius,
                                damage: emitter.damage,
                                life: emitter.lifetime,
                                playerOwned: playerOwned,
                                tint: emitter.tint,
                                bulletType: emitter.bulletType.rawValue,
                                modifiers: emitter.modifiers,
                                modifierPhase: emitter.rotation + Double.random(in: 0...(Double.pi * 2), using: &rng),
                                homingTimeRemaining: emitter.homingDuration,
                                maxTurnRate: emitter.maxTurnRate,
                                acceleration: emitter.acceleration,
                                activationDelay: emitter.modifiers.contains(.delayedActivation) ? (emitter.activationDelay > 0 ? emitter.activationDelay : 0.75) : 0,
                                minForwardSpeed: playerOwned ? -70 : 70,
                                baseVelocity: direction * emitter.speed,
                                splitChildCount: emitter.splitCount > 0 ? emitter.splitCount : (playerOwned ? 2 : 3),
                                splitSpread: emitter.splitSpread,
                                bounceRemaining: emitter.bounceCount)
            spawnBullet(bullet)
        }
    }

    private func updateEnemies(delta: Double, field: PlayfieldBounds) {
        for index in enemies.indices.reversed() {
            let enemyType = EnemyType(rawValue: enemies[index].type) ?? .fighter
            enemies[index].age += delta
            enemies[index].dangerLaserTimer = max(0, enemies[index].dangerLaserTimer - delta)
            switch enemyType {
            case .fighter:
                enemies[index].position.y += enemies[index].speed * delta
                enemies[index].position.x = enemies[index].baseX + sin(enemies[index].age * 1.8 + enemies[index].phase) * 12
            case .diver:
                if !enemies[index].diveStarted, enemies[index].age > 0.65 { enemies[index].diveStarted = true }
                let diveSpeed = enemies[index].diveStarted ? enemies[index].speed + 155 : enemies[index].speed
                enemies[index].position.y += diveSpeed * delta
                if enemies[index].diveStarted {
                    let horizontalError = player.x - enemies[index].position.x
                    enemies[index].position.x += min(170, max(-170, horizontalError * 1.8)) * delta
                } else {
                    enemies[index].position.x = enemies[index].baseX + sin(enemies[index].age * 2.2 + enemies[index].phase) * 34
                }
            case .turret:
                enemies[index].position.y = min(145, enemies[index].position.y + enemies[index].speed * delta)
                enemies[index].position.x = enemies[index].baseX + sin(enemies[index].age * 0.9 + enemies[index].phase) * 28
            case .sniper:
                enemies[index].position.y = min(155, enemies[index].position.y + enemies[index].speed * delta)
                enemies[index].position.x = enemies[index].baseX + sin(enemies[index].age * 1.1 + enemies[index].phase) * 42
                enemies[index].shootTimer -= delta
                if !enemies[index].attackWarningActive, enemies[index].shootTimer <= 0, enemies[index].position.y > 80 {
                    enemies[index].attackWarningActive = true
                    enemies[index].warningTimer = 0.95
                    enemies[index].warningTargetX = player.x
                    enemies[index].warningAttackKind = Int.random(in: 0..<100, using: &rng) < 68 ? 0 : 1
                    enemies[index].shootTimer = 3.7 / endlessFireRateMultiplier
                }
                if enemies[index].attackWarningActive {
                    enemies[index].warningTimer -= delta
                    if enemies[index].warningTimer <= 0 {
                        if enemies[index].warningAttackKind == 0 {
                            // A compact train enters exactly on the telegraphed
                            // lane. Individual bullets are weak, but the column
                            // rewards leaving the lane before the warning ends.
                            for shot in 0..<10 {
                                spawnBullet(Bullet(position: Vec2(x: enemies[index].warningTargetX,
                                                                  y: field.top - 12 - Double(shot) * 23),
                                                   velocity: Vec2(x: 0, y: 390), radius: 7,
                                                   damage: 4.0 * activeEnemyDamageMultiplier,
                                                   life: 5.5, playerOwned: false,
                                                   tint: rgb(255, 125, 118),
                                                   bulletType: BulletType.cosmicRayBarrage.rawValue,
                                                   modifiers: [.constantVelocity, .lockDirection],
                                                   minForwardSpeed: 70,
                                                   baseVelocity: Vec2(x: 0, y: 390)))
                            }
                        } else {
                            // The beam is intentionally brief and high impact.
                            // Its damage is applied once, never once per frame.
                            enemies[index].dangerLaserTimer = 0.18
                            if abs(player.x - enemies[index].warningTargetX) <= coreRadius + 30 {
                                damagePlayer(amount: 32 * activeEnemyDamageMultiplier)
                            }
                            addCameraShake(strength: 5.5)
                            AudioManager.shared.playSFX("sfx_laser")
                        }
                        enemies[index].attackWarningActive = false
                    }
                }
            case .shield:
                enemies[index].position.y += enemies[index].speed * delta
                enemies[index].position.x = enemies[index].baseX + sin(enemies[index].age * 1.35 + enemies[index].phase) * 48
            case .kamikaze:
                let isDiving = enemies[index].position.y > player.y - 210
                let diveSpeed = isDiving ? enemies[index].speed * 2.8 : enemies[index].speed
                enemies[index].position.y += diveSpeed * delta
                if isDiving {
                    let horizontalError = player.x - enemies[index].position.x
                    enemies[index].position.x += min(220, max(-220, horizontalError * 2.3)) * delta
                } else {
                    enemies[index].position.x = enemies[index].baseX + sin(enemies[index].age * 2.4 + enemies[index].phase) * 18
                }
            case .carrier:
                enemies[index].position.y = min(132, enemies[index].position.y + enemies[index].speed * delta)
                enemies[index].position.x = enemies[index].baseX + sin(enemies[index].age * 0.65 + enemies[index].phase) * 58
                enemies[index].spawnTimer -= delta
                if enemies[index].spawnTimer <= 0, enemies[index].position.y >= 105 {
                    let childPosition = enemies[index].position + Vec2(x: Double.random(in: -42...42, using: &rng), y: 30)
                    spawnEnemy(position: childPosition, pattern: 1, type: EnemyType.fighter.rawValue)
                    enemies[index].spawnTimer = 4.5
                    spawnHit(at: childPosition, tint: rgb(223, 150, 255))
                }
            }
            enemies[index].position.x = min(max(enemies[index].position.x, field.left + 22), field.right - 22)

            // Elite attacks are deliberately telegraphed. Their warning window
            // creates a visible "move now" decision instead of hidden damage
            // inflation, and the broad fan keeps a readable escape route.
            if enemies[index].isElite {
                enemies[index].eliteAttackTimer -= delta
                if enemies[index].eliteWarningTimer <= 0, enemies[index].eliteAttackTimer <= 0 {
                    enemies[index].eliteWarningTimer = 0.72
                    enemies[index].eliteAttackTimer = 4.4 / endlessFireRateMultiplier
                }
                if enemies[index].eliteWarningTimer > 0 {
                    enemies[index].eliteWarningTimer -= delta
                    if enemies[index].eliteWarningTimer <= 0 {
                        let eliteEmitter = BulletEmitter(pattern: .spread, count: 7,
                                                         speed: 238 + survivalTime * 0.14,
                                                         damage: 12 * activeEnemyDamageMultiplier,
                                                         radius: 6.5, lifetime: 5.8,
                                                         tint: rgb(255, 202, 104), bulletType: .boss,
                                                         modifiers: [.constantVelocity, .lockDirection], spread: 0.72)
                        emitPattern(eliteEmitter, from: enemies[index].position + Vec2(x: 0, y: 18))
                        enemies[index].shootTimer = max(enemies[index].shootTimer, 0.75)
                    }
                }
            }

            if enemyType != .sniper, enemyType != .kamikaze {
                enemies[index].shootTimer -= delta
                if enemies[index].shootTimer <= 0, enemies[index].eliteWarningTimer <= 0,
                   enemies[index].position.y > field.top + 4, enemies[index].position.y < field.bottom - 40 {
                    let pattern: BulletPattern
                    let modifiers: [BulletModifier]
                    let bulletType: BulletType
                    let damage: Double
                    switch enemyType {
                    case .turret:
                        pattern = .single; modifiers = [.constantVelocity, .lockDirection]; bulletType = .normal; damage = 12
                    case .shield:
                        pattern = .single; modifiers = [.constantVelocity, .sineWave, .lockDirection]; bulletType = .normal; damage = 9
                    case .carrier:
                        pattern = .triple; modifiers = [.constantVelocity, .sineWave, .split, .lockDirection]; bulletType = .boss; damage = 11
                    case .diver:
                        pattern = .aimed; modifiers = [.constantVelocity, .homing, .lockDirection]; bulletType = .aimed; damage = 10
                    default:
                        let roll = Int.random(in: 0...2, using: &rng)
                        pattern = roll == 2 ? .aimed : .single
                        modifiers = roll == 1 ? [.constantVelocity, .sineWave, .lockDirection] : (roll == 2 ? [.constantVelocity, .homing, .lockDirection] : [.constantVelocity, .lockDirection])
                        bulletType = roll == 2 ? .aimed : .normal
                        damage = 8
                    }
                    let eliteMultiplier = enemies[index].isElite ? CombatConfig.eliteDamageMultiplier : 1.0
                    let emitter = BulletEmitter(pattern: pattern, count: pattern == .triple ? 3 : 1,
                                                speed: 175 + survivalTime * 0.16, damage: damage * activeEnemyDamageMultiplier * eliteMultiplier,
                                                radius: 5.5, lifetime: 5, tint: enemyType == .carrier ? rgb(255, 140, 221) : rgb(255, 113, 104),
                                                bulletType: bulletType, modifiers: modifiers,
                                                spread: pattern == .triple ? 0.23 : 0,
                                                homingDuration: pattern == .aimed && modifiers.contains(.homing) ? 1.15 : 0,
                                                maxTurnRate: 1.45,
                                                splitCount: enemyType == .carrier ? 2 : 0,
                                                splitSpread: 0.20)
                    emitPattern(emitter, from: enemies[index].position, target: pattern == .aimed ? player : nil)
                    let baseCooldown = enemyType == .turret ? 1.65 : Double.random(in: 1.9...3.2, using: &rng)
                    enemies[index].shootTimer = baseCooldown * (enemies[index].isElite ? 0.86 : 1.0) / endlessFireRateMultiplier
                }
            }

            let collisionDistance = coreRadius + enemies[index].radius
            if distanceSquared(player, enemies[index].position) < collisionDistance * collisionDistance {
                let collisionDamage: Double = (enemyType == .kamikaze ? 55 : (enemyType == .carrier ? 40 : 30)) * activeEnemyDamageMultiplier
                damagePlayer(amount: collisionDamage)
                combo = max(0, combo - 2)
                spawnExplosion(at: enemies[index].position, tint: enemies[index].tint, count: enemyType == .kamikaze ? 24 : 12)
                enemies.remove(at: index)
            } else if enemies[index].position.y > field.bottom + 45 {
                enemies.remove(at: index)
            }
        }
    }

    private func updateBoss(delta: Double, field: PlayfieldBounds) {
        guard var currentBoss = boss else { return }
        currentBoss.age += delta
        currentBoss.phaseFlash = max(0, currentBoss.phaseFlash - delta)
        currentBoss.warningTimer = max(0, currentBoss.warningTimer - delta)
        currentBoss.laserWarningTimer = max(0, currentBoss.laserWarningTimer - delta)
        currentBoss.laserActiveTimer = max(0, currentBoss.laserActiveTimer - delta)
        currentBoss.laserHitCooldown = max(0, currentBoss.laserHitCooldown - delta)

        if currentBoss.lifecycle == .dying {
            currentBoss.stateTimer -= delta
            currentBoss.weakPointOpen = false
            currentBoss.laserActiveTimer = 0
            currentBoss.laserWarningTimer = 0
            currentBoss.position.y += 9 * delta
            boss = currentBoss
            if currentBoss.stateTimer <= 0 {
                registerBossDefeat(at: currentBoss.position)
                boss = nil
            }
            return
        }

        if currentBoss.lifecycle == .entering {
            currentBoss.stateTimer -= delta
            currentBoss.position.y = min(125, currentBoss.position.y + 112 * delta)
            currentBoss.position.x += (field.centerX - currentBoss.position.x) * min(1, delta * 4)
            if currentBoss.stateTimer <= 0, currentBoss.position.y >= 122 {
                currentBoss.lifecycle = .combat
                currentBoss.attackStage = .recovery
                currentBoss.attackTimer = 0.85
            }
            boss = currentBoss
            return
        }

        let healthRatio = currentBoss.health / max(1, currentBoss.maxHealth)
        let desiredPhase = healthRatio > 0.70 ? 1 : (healthRatio > 0.30 ? 2 : 3)
        if currentBoss.lifecycle == .combat, desiredPhase > currentBoss.phase {
            currentBoss.lifecycle = .phaseTransition
            currentBoss.pendingPhase = desiredPhase
            currentBoss.stateTimer = ThunderCarrierBossDefinition.transitionDuration
            currentBoss.attackStage = .recovery
            currentBoss.attackTimer = currentBoss.stateTimer
            currentBoss.weakPointOpen = false
            currentBoss.laserActiveTimer = 0
            currentBoss.laserWarningTimer = 0
            currentBoss.warningTimer = 0
            enemyBulletClearPending = true
        }

        if currentBoss.lifecycle == .phaseTransition {
            currentBoss.stateTimer -= delta
            currentBoss.position.x += (field.centerX - currentBoss.position.x) * min(1, delta * 5)
            currentBoss.position.y += (138 - currentBoss.position.y) * min(1, delta * 5)
            currentBoss.phaseFlash = max(currentBoss.phaseFlash, 0.25)
            if currentBoss.stateTimer <= 0 {
                currentBoss.phase = currentBoss.pendingPhase
                currentBoss.lifecycle = .combat
                currentBoss.phaseFlash = 1.0
                currentBoss.attackPatternIndex = 0
                currentBoss.attackStage = .recovery
                currentBoss.attackTimer = 0.85
                addCameraShake(strength: 9)
                combatFeedback.play(.bossPhaseChanged,
                                    context: FeedbackContext(position: currentBoss.position, direction: Vec2(x: 0, y: 1),
                                                             level: .heavy, tint: rgb(255, 146, 244)), game: self)
                let detail = currentBoss.phase == 2 ? "Armor breached • attack combinations online" : "Core exposed • damage window increased"
                notifyPickup(title: "BOSS PHASE \(currentBoss.phase)", detail: detail, tint: rgb(255, 146, 244))
            }
            boss = currentBoss
            return
        }

        updateBossMovement(&currentBoss, delta: delta, field: field)
        if currentBoss.laserActiveTimer > 0 {
            let remaining = max(0.04, currentBoss.laserActiveTimer)
            currentBoss.laserX += (currentBoss.laserTargetX - currentBoss.laserX) * min(1, delta / remaining)
            if abs(player.x - currentBoss.laserX) < 24, currentBoss.laserHitCooldown <= 0 {
                damagePlayer(amount: (currentBoss.phase == 3 ? 28 : 22) * activeEnemyDamageMultiplier * ThunderCarrierBossDefinition.damageMultiplier)
                currentBoss.laserHitCooldown = 0.42
            }
        }

        let phaseDefinition = ThunderCarrierBossDefinition.phase(currentBoss.phase)
        let turretsDisabled = currentBoss.leftTurretHealth <= 0 && currentBoss.rightTurretHealth <= 0
        switch currentBoss.attackStage {
        case .recovery:
            currentBoss.attackTimer -= delta
            currentBoss.weakPointOpen = currentBoss.phase == 3 || turretsDisabled || phaseDefinition.weakPointDuringRecovery
            if currentBoss.attackTimer <= 0 {
                let attacks = phaseDefinition.attacks
                let definition = attacks[currentBoss.attackPatternIndex % attacks.count]
                currentBoss.currentAttack = definition.id
                currentBoss.movement = definition.movement
                currentBoss.attackTarget = player
                currentBoss.attackStage = .telegraph
                currentBoss.attackTimer = definition.telegraph
                currentBoss.warningTimer = definition.telegraph
                currentBoss.weakPointOpen = false
                prepareBossTelegraph(&currentBoss, definition: definition, field: field)
            }
        case .telegraph:
            currentBoss.attackTimer -= delta
            currentBoss.weakPointOpen = false
            if currentBoss.attackTimer <= 0 {
                let definition = phaseDefinition.attacks[currentBoss.attackPatternIndex % phaseDefinition.attacks.count]
                executeBossAttack(&currentBoss, definition: definition, field: field)
                currentBoss.attackStage = .execute
                currentBoss.attackTimer = definition.execute
            }
        case .execute:
            currentBoss.attackTimer -= delta
            currentBoss.weakPointOpen = currentBoss.phase == 3 || turretsDisabled
            if currentBoss.currentAttack == .aimBurst, currentBoss.burstShotsRemaining > 0 {
                currentBoss.burstShotTimer -= delta
                if currentBoss.burstShotTimer <= 0 {
                    emitBossAimShot(currentBoss)
                    currentBoss.burstShotsRemaining -= 1
                    currentBoss.burstShotTimer = 0.14
                }
            }
            if currentBoss.attackTimer <= 0 {
                let definition = phaseDefinition.attacks[currentBoss.attackPatternIndex % phaseDefinition.attacks.count]
                currentBoss.attackPatternIndex += 1
                currentBoss.attackStage = .recovery
                currentBoss.attackTimer = (definition.recovery + (turretsDisabled ? 0.32 : 0)) / endlessFireRateMultiplier
                currentBoss.movement = .hover
                currentBoss.warningTimer = 0
            }
        }

        let bossCollisionDistance = coreRadius + ThunderCarrierBossDefinition.collisionRadius
        if distanceSquared(player, currentBoss.position) < bossCollisionDistance * bossCollisionDistance {
            damagePlayer(amount: 35 * activeEnemyDamageMultiplier * ThunderCarrierBossDefinition.damageMultiplier)
        }
        boss = currentBoss
    }

    private func updateBossMovement(_ boss: inout Boss, delta: Double, field: PlayfieldBounds) {
        let horizontalLimit = min(max(120, field.width * 0.27), field.width * 0.5 - ThunderCarrierBossDefinition.visualWidth * 0.34)
        switch boss.movement {
        case .positionLock:
            boss.position.x += (field.centerX - boss.position.x) * min(1, delta * 2.3)
            boss.position.y += (138 - boss.position.y) * min(1, delta * 2.3)
        case .horizontalSweep:
            boss.position.x = field.centerX + sin(boss.age * 0.60) * horizontalLimit
            boss.position.y = 142 + sin(boss.age * 0.74) * 12
        case .aggressiveHover:
            boss.position.x = field.centerX + sin(boss.age * 0.98) * min(horizontalLimit * 1.15, field.width * 0.5 - 132)
            boss.position.y = 145 + sin(boss.age * 1.12) * 24
        case .hover:
            boss.position.x = field.centerX + sin(boss.age * 0.44) * horizontalLimit * 0.75
            boss.position.y = 136 + sin(boss.age * 0.58) * 10
        }
    }

    private func prepareBossTelegraph(_ boss: inout Boss, definition: BossAttackDefinition, field: PlayfieldBounds) {
        if definition.id == .laserSweep {
            let leftToRight = boss.attackPatternIndex % 2 == 0
            boss.laserX = leftToRight ? field.left + 68 : field.right - 68
            boss.laserTargetX = leftToRight ? field.right - 68 : field.left + 68
            boss.laserWarningTimer = definition.telegraph
            AudioManager.shared.playSFX("sfx_boss")
        }
    }

    private func executeBossAttack(_ boss: inout Boss, definition: BossAttackDefinition, field: PlayfieldBounds) {
        let origin = boss.position + Vec2(x: 0, y: 34)
        switch definition.id {
        case .spread:
            let count = boss.phase == 1 ? 7 : 9
            let emitter = BulletEmitter(pattern: .spread, count: count, speed: boss.phase == 1 ? 235 : 255,
                                        damage: (boss.phase == 1 ? 14 : 16) * activeEnemyDamageMultiplier * ThunderCarrierBossDefinition.damageMultiplier,
                                        radius: 6.5, lifetime: 6, tint: rgb(255, 178, 75), bulletType: .boss,
                                        modifiers: [.constantVelocity, .lockDirection], spread: boss.phase == 1 ? 0.52 : 0.68)
            emitPattern(emitter, from: origin)
            emitBossSideWeapon(&boss, alternating: true)
        case .aimBurst:
            emitBossAimShot(boss)
            boss.burstShotsRemaining = 3
            boss.burstShotTimer = 0.14
            if boss.phase >= 2 { emitBossSideWeapon(&boss, alternating: true) }
        case .sideCrossfire:
            emitBossSideWeapon(&boss, alternating: false)
        case .laserSweep:
            boss.laserWarningTimer = 0
            boss.laserActiveTimer = definition.execute
            boss.laserHitCooldown = 0
            addCameraShake(strength: 5)
        case .slowField:
            let emitter = BulletEmitter(pattern: .ring, count: 15, speed: 205,
                                        damage: 15 * activeEnemyDamageMultiplier * ThunderCarrierBossDefinition.damageMultiplier,
                                        radius: 6.5, lifetime: 6, tint: rgb(224, 102, 230), bulletType: .boss,
                                        modifiers: [.constantVelocity, .accelerate, .delayedActivation, .stopAndGo, .lockDirection],
                                        acceleration: -22, activationDelay: 0.42)
            emitPattern(emitter, from: origin)
        case .spiral:
            for offset in [0.0, Double.pi] {
                let emitter = BulletEmitter(pattern: .spiral, count: 12, speed: 225,
                                            damage: 18 * activeEnemyDamageMultiplier * ThunderCarrierBossDefinition.damageMultiplier,
                                            radius: 6.5, lifetime: 6, tint: rgb(255, 78, 151), bulletType: .boss,
                                            modifiers: [.constantVelocity, .accelerate, .curve, .lockDirection], spread: 0.82,
                                            rotation: boss.age * 0.70 + offset, acceleration: 16)
                emitPattern(emitter, from: origin)
            }
        }
    }

    private func emitBossAimShot(_ boss: Boss) {
        let emitter = BulletEmitter(pattern: .aimed, count: 1, speed: boss.phase == 3 ? 325 : 290,
                                        damage: (boss.phase == 3 ? 18 : 15) * activeEnemyDamageMultiplier * ThunderCarrierBossDefinition.damageMultiplier,
                                        radius: 6, lifetime: 5.5, tint: rgb(255, 192, 108), bulletType: .aimed,
                                        modifiers: [.constantVelocity, .homing, .lockDirection], spread: 0,
                                        homingDuration: 0.62, maxTurnRate: 0.95)
        emitPattern(emitter, from: boss.position + Vec2(x: 0, y: 34), target: boss.attackTarget)
    }

    private func emitBossSideWeapon(_ boss: inout Boss, alternating: Bool) {
        let useLeft = !alternating || boss.attackPatternIndex % 2 == 0
        let useRight = !alternating || !useLeft
        if useLeft, boss.leftTurretHealth > 0 {
            let emitter = BulletEmitter(pattern: .aimed, count: 1, speed: 272 + Double(boss.phase) * 12,
                                        damage: 10 * activeEnemyDamageMultiplier * ThunderCarrierBossDefinition.damageMultiplier, radius: 5.5, lifetime: 5.5,
                                        tint: rgb(255, 124, 188), bulletType: .aimed,
                                        modifiers: [.constantVelocity, .homing, .lockDirection], homingDuration: 0.48, maxTurnRate: 0.88)
            emitPattern(emitter, from: boss.position + Vec2(x: -ThunderCarrierBossDefinition.turretOffsetX, y: ThunderCarrierBossDefinition.turretOffsetY), target: player)
        }
        if useRight, boss.rightTurretHealth > 0 {
            let emitter = BulletEmitter(pattern: .spread, count: 5, speed: 220 + Double(boss.phase) * 12,
                                        damage: 9 * activeEnemyDamageMultiplier * ThunderCarrierBossDefinition.damageMultiplier, radius: 5.5, lifetime: 5.5,
                                        tint: rgb(255, 164, 108), bulletType: .normal,
                                        modifiers: [.constantVelocity, .lockDirection], spread: 0.24)
            emitPattern(emitter, from: boss.position + Vec2(x: ThunderCarrierBossDefinition.turretOffsetX, y: ThunderCarrierBossDefinition.turretOffsetY))
        }
    }

    private func beginBossDeath(_ bossToDestroy: Boss, direction: Vec2, damage: Double,
                                critical: Bool, damageKind: FeedbackDamageKind) {
        guard bossToDestroy.lifecycle != .dying else { return }
        var dyingBoss = bossToDestroy
        dyingBoss.health = 0
        dyingBoss.lifecycle = .dying
        dyingBoss.stateTimer = ThunderCarrierBossDefinition.deathDuration
        dyingBoss.attackStage = .recovery
        dyingBoss.attackTimer = dyingBoss.stateTimer
        dyingBoss.warningTimer = 0
        dyingBoss.laserWarningTimer = 0
        dyingBoss.laserActiveTimer = 0
        dyingBoss.weakPointOpen = false
        boss = dyingBoss
        enemyBulletClearPending = true
        combatFeedback.play(.bossKilled,
                            context: FeedbackContext(position: dyingBoss.position, direction: direction,
                                                     damage: damage, level: .critical, critical: critical,
                                                     damageKind: damageKind, tint: rgb(244, 104, 255)), game: self)
    }

    private func isEnemyProtected(_ enemyIndex: Int) -> Bool {
        guard enemies.indices.contains(enemyIndex), enemies[enemyIndex].type != EnemyType.shield.rawValue else { return false }
        let target = enemies[enemyIndex].position
        return enemies.contains { other in
            other.type == EnemyType.shield.rawValue && distanceSquared(other.position, target) < 128 * 128
        }
    }

    private func turnVelocity(_ velocity: Vec2, toward target: Vec2, from origin: Vec2, maxTurnRate: Double, delta: Double, enforceForward: Bool) -> Vec2 {
        let speed = max(1, velocity.length)
        guard speed > 0, maxTurnRate > 0 else { return velocity }
        let currentAngle = atan2(velocity.y, velocity.x)
        let desiredAngle = atan2(target.y - origin.y, target.x - origin.x)
        var difference = desiredAngle - currentAngle
        while difference > Double.pi { difference -= Double.pi * 2 }
        while difference < -Double.pi { difference += Double.pi * 2 }
        let turn = min(maxTurnRate * delta, max(-maxTurnRate * delta, difference))
        var result = Vec2(x: cos(currentAngle + turn), y: sin(currentAngle + turn)) * speed
        if enforceForward { result.y = max(70, result.y) }
        return result
    }

    private func updateBulletMovement(index: Int, delta: Double) {
        guard bullets.indices.contains(index) else { return }
        bullets[index].age += delta
        if bullets[index].activationDelay > 0 {
            bullets[index].activationDelay = max(0, bullets[index].activationDelay - delta)
            return
        }
        for modifier in bullets[index].modifiers {
            switch modifier {
            case .constantVelocity:
                break
            case .accelerate:
                let direction = bullets[index].velocity.normalized
                bullets[index].velocity = bullets[index].velocity + direction * bullets[index].acceleration * delta
            case .homing:
                guard bullets[index].homingTimeRemaining > 0 else { continue }
                bullets[index].homingTimeRemaining = max(0, bullets[index].homingTimeRemaining - delta)
                let target = bullets[index].playerOwned ? nearestTargetPosition(from: bullets[index].position) : player
                if let target {
                    bullets[index].velocity = turnVelocity(bullets[index].velocity, toward: target,
                                                          from: bullets[index].position,
                                                          maxTurnRate: bullets[index].maxTurnRate, delta: delta,
                                                          enforceForward: !bullets[index].playerOwned)
                }
            case .sineWave:
                let forwardSpeed = max(abs(bullets[index].velocity.y), bullets[index].minForwardSpeed)
                bullets[index].velocity.x = sin(bullets[index].age * 3.2 + bullets[index].modifierPhase) * 110
                if !bullets[index].playerOwned { bullets[index].velocity.y = max(150, forwardSpeed) }
            case .delayedActivation:
                break
            case .lockDirection:
                if !bullets[index].playerOwned, bullets[index].velocity.length > 0.1 {
                    bullets[index].velocity.y = max(70, bullets[index].velocity.y)
                }
            case .curve:
                let curveDirection = bullets[index].playerOwned ? -0.72 : 0.72
                bullets[index].velocity = rotated(bullets[index].velocity, by: curveDirection * delta)
            case .stopAndGo:
                let cycle = bullets[index].age.truncatingRemainder(dividingBy: 1.8)
                if cycle < 0.32 {
                    bullets[index].velocity = .zero
                } else if bullets[index].velocity.length < 0.1 {
                    bullets[index].velocity = bullets[index].baseVelocity
                }
            case .split, .bounce:
                break
            }
        }
        if !bullets[index].playerOwned, bullets[index].velocity.length > 0.1 {
            bullets[index].velocity.y = max(70, bullets[index].velocity.y)
        }
        bullets[index].position = bullets[index].position + bullets[index].velocity * delta
    }

    private enum BossHitPart {
        case leftTurret
        case rightTurret
        case core
    }

    private func bossHitPart(_ boss: Boss, position: Vec2, radius: Double) -> BossHitPart? {
        guard boss.lifecycle != .entering, boss.lifecycle != .dying else { return nil }
        let left = boss.position + Vec2(x: -ThunderCarrierBossDefinition.turretOffsetX, y: ThunderCarrierBossDefinition.turretOffsetY)
        let right = boss.position + Vec2(x: ThunderCarrierBossDefinition.turretOffsetX, y: ThunderCarrierBossDefinition.turretOffsetY)
        let turretHitDistance = radius + 24
        if boss.leftTurretHealth > 0, distanceSquared(position, left) < turretHitDistance * turretHitDistance { return .leftTurret }
        if boss.rightTurretHealth > 0, distanceSquared(position, right) < turretHitDistance * turretHitDistance { return .rightTurret }
        let coreHitDistance = radius + 50
        return distanceSquared(position, boss.position) < coreHitDistance * coreHitDistance ? .core : nil
    }

    private func updateBullets(delta: Double, field: PlayfieldBounds) {
        var activeOriginalCount = bullets.count
        for index in bullets.indices.reversed() {
            // Keep the frame loop defensive: Boss defeat and reflection can
            // change bullet ownership, but an index must never be used after
            // another path has removed that slot.
            guard bullets.indices.contains(index) else { continue }
            updateBulletMovement(index: index, delta: delta)
            if bullets[index].modifiers.contains(.bounce), bullets[index].bounceRemaining > 0 {
                if bullets[index].position.x < field.left + 14 {
                    bullets[index].position.x = field.left + 14
                    bullets[index].velocity.x = abs(bullets[index].velocity.x)
                    bullets[index].bounceRemaining -= 1
                } else if bullets[index].position.x > field.right - 14 {
                    bullets[index].position.x = field.right - 14
                    bullets[index].velocity.x = -abs(bullets[index].velocity.x)
                    bullets[index].bounceRemaining -= 1
                }
            }
            if bullets[index].modifiers.contains(.split), !bullets[index].splitTriggered, bullets[index].age >= 0.82 {
                let parent = bullets[index]
                bullets[index].splitTriggered = true
                let childCount = max(2, parent.splitChildCount > 0 ? parent.splitChildCount : (parent.playerOwned ? 2 : 3))
                let childDamage = parent.damage * (parent.playerOwned ? 0.48 : 0.56)
                let childModifiers = parent.modifiers.filter { $0 != .split }
                for childIndex in 0..<childCount {
                    let offset = Double(childIndex) - Double(childCount - 1) / 2
                    let childVelocity = rotated(parent.velocity, by: offset * parent.splitSpread)
                    spawnBullet(Bullet(position: parent.position,
                                       velocity: childVelocity,
                                       radius: max(3.5, parent.radius * 0.82),
                                       damage: childDamage,
                                       life: parent.life,
                                       playerOwned: parent.playerOwned,
                                       tint: parent.tint,
                                       bulletType: parent.bulletType,
                                       modifiers: childModifiers,
                                       pierceRemaining: parent.pierceRemaining,
                                       weaponStyle: parent.weaponStyle,
                                       modifierPhase: parent.modifierPhase + offset * 0.4,
                                       homingTimeRemaining: parent.homingTimeRemaining,
                                       maxTurnRate: parent.maxTurnRate,
                                       acceleration: parent.acceleration,
                                       minForwardSpeed: parent.minForwardSpeed,
                                       baseVelocity: childVelocity,
                                       splitChildCount: 0,
                                       bounceRemaining: parent.bounceRemaining))
                }
            }
            bullets[index].life -= delta
            var removeBullet = bullets[index].life <= 0
                || bullets[index].position.y < field.top - 15
                || bullets[index].position.y > field.bottom + 30
                || bullets[index].position.x < field.left - 30
                || bullets[index].position.x > field.right + 30

            if !removeBullet, bullets[index].playerOwned {
                if var currentBoss = boss, let hitPart = bossHitPart(currentBoss, position: bullets[index].position, radius: bullets[index].radius) {
                    let critical = Double.random(in: 0...1, using: &rng) < criticalChance
                    let baseDamage = bullets[index].damage * (critical ? criticalMultiplier : 1.0) * (thunderOverloadTime > 0 ? 1.45 : 1.0) * (overloadMatrixActive ? 1.12 : 1.0)
                    var finalDamage = baseDamage
                    var weakPointHit = false
                    let hitPosition: Vec2
                    switch hitPart {
                    case .leftTurret:
                        let wasAlive = currentBoss.leftTurretHealth > 0
                        currentBoss.leftTurretHealth = max(0, currentBoss.leftTurretHealth - baseDamage)
                        finalDamage = baseDamage * 0.45
                        currentBoss.health -= finalDamage
                        hitPosition = currentBoss.position + Vec2(x: -ThunderCarrierBossDefinition.turretOffsetX, y: ThunderCarrierBossDefinition.turretOffsetY)
                        if wasAlive && currentBoss.leftTurretHealth <= 0 {
                            notifyPickup(title: "BOSS TURRET DESTROYED", detail: "Left weapon disabled", tint: rgb(255, 188, 112))
                            combatFeedback.play(.bossPartDestroyed,
                                                context: FeedbackContext(position: hitPosition, direction: bullets[index].velocity.normalized,
                                                                         damage: finalDamage, level: .heavy, tint: rgb(255, 188, 112)), game: self)
                        }
                    case .rightTurret:
                        let wasAlive = currentBoss.rightTurretHealth > 0
                        currentBoss.rightTurretHealth = max(0, currentBoss.rightTurretHealth - baseDamage)
                        finalDamage = baseDamage * 0.45
                        currentBoss.health -= finalDamage
                        hitPosition = currentBoss.position + Vec2(x: ThunderCarrierBossDefinition.turretOffsetX, y: ThunderCarrierBossDefinition.turretOffsetY)
                        if wasAlive && currentBoss.rightTurretHealth <= 0 {
                            notifyPickup(title: "BOSS TURRET DESTROYED", detail: "Right weapon disabled", tint: rgb(255, 188, 112))
                            combatFeedback.play(.bossPartDestroyed,
                                                context: FeedbackContext(position: hitPosition, direction: bullets[index].velocity.normalized,
                                                                         damage: finalDamage, level: .heavy, tint: rgb(255, 188, 112)), game: self)
                        }
                    case .core:
                        if currentBoss.weakPointOpen {
                            finalDamage *= ThunderCarrierBossDefinition.weakPointMultiplier
                            weakPointHit = true
                        }
                        if currentBoss.leftTurretHealth <= 0, currentBoss.rightTurretHealth <= 0 {
                            finalDamage *= ThunderCarrierBossDefinition.disabledTurretsMultiplier
                        }
                        currentBoss.health -= finalDamage
                        hitPosition = currentBoss.position
                    }
                    boss = currentBoss
                    let bossDamageKind: FeedbackDamageKind = bullets[index].weaponStyle == WeaponType.missile.rawValue ? .missile :
                        (bullets[index].weaponStyle == WeaponType.electromagnetic.rawValue ? .electromagnetic :
                            (bullets[index].weaponStyle == WeaponType.laser.rawValue ? .laser : .cannon))
                    let bossFeedback = FeedbackContext(position: hitPosition, direction: bullets[index].velocity.normalized,
                                                        damage: finalDamage, level: critical ? .medium : .light, critical: critical,
                                                        damageKind: bossDamageKind,
                                                        tint: bullets[index].weaponStyle == WeaponType.electromagnetic.rawValue ? rgb(191, 133, 255) : rgb(255, 225, 122))
                    combatFeedback.play(weakPointHit ? .bossWeakPointHit : (critical ? .criticalHit : .enemyHit),
                                        context: bossFeedback, game: self)
                    if critical, stormCoreActive { thunderEnergy = min(100, thunderEnergy + 4) }
                    applyBloodLeech()
                    if bullets[index].pierceRemaining > 0 {
                        bullets[index].pierceRemaining -= 1
                        bullets[index].position = bullets[index].position + bullets[index].velocity.normalized * 28
                    } else {
                        removeBullet = true
                    }
                    if currentBoss.health <= 0 {
                        beginBossDeath(currentBoss, direction: bullets[index].velocity.normalized,
                                       damage: finalDamage, critical: critical, damageKind: bossDamageKind)
                    }
                } else {
                    for enemyIndex in enemies.indices.reversed() {
                        let hitDistance = bullets[index].radius + enemies[enemyIndex].radius
                        if distanceSquared(bullets[index].position, enemies[enemyIndex].position) < hitDistance * hitDistance {
                            let critical = Double.random(in: 0...1, using: &rng) < criticalChance
                            let shieldMultiplier = isEnemyProtected(enemyIndex) ? 0.55 : 1.0
                            let finalDamage = bullets[index].damage * (critical ? criticalMultiplier : 1.0) * (thunderOverloadTime > 0 ? 1.45 : 1.0) * shieldMultiplier
                            let remainingHealth = enemies[enemyIndex].health
                            let targetID = enemies[enemyIndex].feedbackID
                            let targetTint = enemies[enemyIndex].tint
                            let enemyType = EnemyType(rawValue: enemies[enemyIndex].type) ?? .fighter
                            enemies[enemyIndex].health -= finalDamage
                            let damageKind: FeedbackDamageKind = bullets[index].weaponStyle == WeaponType.missile.rawValue ? .missile :
                                (bullets[index].weaponStyle == WeaponType.electromagnetic.rawValue ? .electromagnetic :
                                    (bullets[index].weaponStyle == WeaponType.laser.rawValue ? .laser : .cannon))
                            let feedback = FeedbackContext(position: bullets[index].position, direction: bullets[index].velocity.normalized,
                                                           damage: finalDamage, level: critical ? .medium : .light, targetID: targetID,
                                                           critical: critical, overkill: finalDamage > max(1, remainingHealth) * 2.5,
                                                           damageKind: damageKind,
                                                           tint: bullets[index].weaponStyle == WeaponType.electromagnetic.rawValue ? rgb(191, 133, 255) : rgb(255, 225, 122))
                            combatFeedback.play(critical ? .criticalHit : .enemyHit, context: feedback, game: self)
                            if critical, stormCoreActive { thunderEnergy = min(100, thunderEnergy + 4) }
                            applyBloodLeech()
                            if bullets[index].pierceRemaining > 0 {
                                bullets[index].pierceRemaining -= 1
                                bullets[index].position = bullets[index].position + bullets[index].velocity.normalized * 28
                            } else {
                                removeBullet = true
                            }
                            if enemies[enemyIndex].health <= 0 {
                                let defeated = enemies[enemyIndex]
                                enemies.remove(at: enemyIndex)
                                let isElite = defeated.isElite || enemyType == .turret || enemyType == .carrier || defeated.radius >= 23
                                registerKill(at: defeated.position, tint: defeated.tint, baseScore: 100 + stage * 15,
                                             radius: defeated.radius, isElite: isElite)
                                if Int.random(in: 0...4, using: &rng) == 0 {
                                    if powerUps.count < 18 {
                                        powerUps.append(PowerUp(position: defeated.position,
                                                                 kind: Int.random(in: 0...2, using: &rng),
                                                                 life: 12))
                                    }
                                }
                                combatFeedback.play(isElite ? .eliteKilled : .enemyKilled,
                                                    context: FeedbackContext(position: defeated.position, direction: bullets[index].velocity.normalized,
                                                                             damage: finalDamage, level: isElite ? .heavy : .medium,
                                                                             overkill: feedback.overkill, damageKind: damageKind, tint: targetTint), game: self)
                                checkForUpgradeReady()
                            }
                            break
                        }
                    }
                }
            } else if !removeBullet, !bullets[index].playerOwned {
                let hitDistance = bullets[index].radius + coreRadius
                let grazeDistance = hitDistance + (precisionMode ? 18 : 14) + grazeRadiusBonus
                let distanceToCoreSquared = distanceSquared(bullets[index].position, player)
                if !bullets[index].grazeAwarded, distanceToCoreSquared > hitDistance * hitDistance,
                   distanceToCoreSquared < grazeDistance * grazeDistance {
                    bullets[index].grazeAwarded = true
                    registerGraze(at: bullets[index].position)
                }
                if distanceToCoreSquared < hitDistance * hitDistance {
                    damagePlayer(amount: bullets[index].damage)
                    spawnHit(at: bullets[index].position, tint: bullets[index].tint)
                    removeBullet = true
                }
            }
            if removeBullet, recycleBullet(at: index, preservingOriginalCount: activeOriginalCount) {
                activeOriginalCount = max(0, activeOriginalCount - 1)
            }
        }
        if enemyBulletClearPending {
            clearEnemyBullets()
            enemyBulletClearPending = false
        }
    }

    private func updatePowerUps(delta: Double, field: PlayfieldBounds) {
        for index in powerUps.indices.reversed() {
            powerUps[index].position.y += 46 * delta
            powerUps[index].life -= delta
            let pickupDistance = playerRadius + 18
            if distanceSquared(player, powerUps[index].position) < pickupDistance * pickupDistance {
                collectPowerUp(powerUps[index].kind)
                spawnExplosion(at: powerUps[index].position, tint: powerUpTint(powerUps[index].kind), count: 16)
                powerUps.remove(at: index)
            } else if powerUps[index].life <= 0 || powerUps[index].position.y > field.bottom + 30 {
                powerUps.remove(at: index)
            }
        }
    }

    private func collectPowerUp(_ kind: Int) {
        AudioManager.shared.playSFX("sfx_powerup")
        switch kind {
        case 0:
            fireRateBoostTime = max(fireRateBoostTime, 5)
            score += 300
            notifyPickup(title: uiText("FIRE CONTROL OVERDRIVE", "火控超频"),
                         detail: uiText("Fire rate +50% • 5 seconds", "射速 +50% • 持续 5 秒"), tint: rgb(89, 236, 255))
        case 1:
            let alreadyProtected = armorShieldCharges > 0
            armorShieldCharges = 1
            score += 280
            notifyPickup(title: uiText("PHASE SHIELD", "相位护盾"),
                         detail: alreadyProtected
                            ? uiText("Shield already active • charges do not stack", "护盾已生效 • 层数不会叠加")
                            : uiText("Blocks one hit • break grants speed and resets dash", "抵挡一次攻击 • 破裂后加速并重置闪避"),
                         tint: rgb(126, 196, 255))
        default:
            bloodLeechTime = max(bloodLeechTime, 8)
            score += 240
            notifyPickup(title: uiText("BLOODLUST", "嗜血如命"),
                         detail: uiText("Hits restore trace hull integrity • 8 seconds", "命中缓慢修复机体 • 持续 8 秒"), tint: rgb(255, 126, 136))
        }
    }

    private func applyBloodLeech() {
        guard bloodLeechTime > 0, bloodLeechCooldown <= 0, health > 0, health < maxHealth else { return }
        // Intentionally weak: at most 0.9 HP per second, or about 7.2 HP
        // across the complete pickup window regardless of weapon fire rate.
        health = min(maxHealth, health + 0.18)
        bloodLeechCooldown = 0.20
    }

    private func damagePlayer(amount: Double) {
        let incomingDirection = (player - Vec2(x: player.x, y: player.y - 1)).normalized
        guard playerInvulnerability <= 0 else { return }
        if armorShieldCharges > 0 {
            armorShieldCharges = 0
            shieldBreakSpeedTime = 3.0
            dashCooldown = 0
            playerInvulnerability = 0.72
            combatFeedback.play(.shieldBreak,
                                context: FeedbackContext(position: player, direction: incomingDirection, damage: amount,
                                                         level: .heavy, damageKind: .enemyBullet, tint: rgb(126, 196, 255)), game: self)
            notifyPickup(title: uiText("SHIELD BROKEN", "护盾破裂"),
                         detail: uiText("Move speed +30% for 3s • dash reset", "移速 +30% 持续 3 秒 • 闪避已重置"),
                         tint: rgb(126, 196, 255))
            return
        }
        let actualDamage = amount * (1.0 - armorDamageReduction)
        health -= actualDamage
        playerInvulnerability = CombatConfig.playerHitInvulnerability
        combo = max(0, combo - 5)
        comboTimer = 0
        thunderEnergy = max(0, thunderEnergy - 10)
        combatFeedback.play(.playerHit,
                            context: FeedbackContext(position: player, direction: incomingDirection, damage: actualDamage,
                                                     level: actualDamage >= maxHealth * 0.18 ? .heavy : .medium,
                                                     damageKind: .enemyBullet, tint: rgb(255, 105, 132)), game: self)
    }

    /// F8 cycles through feedback samples without requiring a full boss run.
    func debugFeedbackTest() {
        guard phase == .playing else { return }
        feedbackDebugIndex = (feedbackDebugIndex + 1) % 10
        let point = enemies.first?.position ?? (boss?.position ?? player + Vec2(x: 0, y: -90))
        let targetID = enemies.first?.feedbackID
        let event: CombatEvent
        let level: FeedbackLevel
        switch feedbackDebugIndex {
        case 0: event = .enemyHit; level = .light
        case 1: event = .criticalHit; level = .medium
        case 2: event = .enemyKilled; level = .medium
        case 3: event = .eliteKilled; level = .heavy
        case 4: event = .playerHit; level = .medium
        case 5: event = .shieldHit; level = .medium
        case 6: event = .shieldBreak; level = .heavy
        case 7: event = .bossKilled; level = .critical
        case 8: event = .comboMilestone; level = .heavy
        default: event = .rareDrop; level = .heavy
        }
        combatFeedback.play(event,
                            context: FeedbackContext(position: point, direction: Vec2(x: 0, y: -1), damage: 128,
                                                     level: level, targetID: targetID, critical: event == .criticalHit,
                                                     tint: event == .shieldHit || event == .shieldBreak ? rgb(114, 222, 255) : rgb(255, 190, 112)), game: self)
        notifyFeedback(title: "FEEDBACK TEST", chineseTitle: "反馈测试", tint: rgb(126, 231, 255))
    }

    /// F7 advances through the expensive Boss test cases without requiring a
    /// full mission: spawn, phase 2, phase 3, part break, then attack cycle.
    func debugBossControl(width: Double, height: Double) {
        guard phase == .playing else { return }
        playerInvulnerability = max(playerInvulnerability, 999)
        thunderEnergy = 100
        let field = playfieldBounds(width: width, height: height)
        guard var currentBoss = boss, currentBoss.lifecycle != .dying else {
            spawnBoss(field: field)
            bossDebugIndex = 0
            notifyPickup(title: "BOSS DEBUG", detail: "Boss spawned • pilot invulnerability enabled", tint: rgb(255, 164, 232))
            return
        }

        switch bossDebugIndex % 4 {
        case 0:
            currentBoss.health = currentBoss.maxHealth * 0.69
            notifyPickup(title: "BOSS DEBUG", detail: "Phase 2 threshold", tint: rgb(255, 188, 112))
        case 1:
            currentBoss.health = currentBoss.maxHealth * 0.29
            notifyPickup(title: "BOSS DEBUG", detail: "Phase 3 threshold", tint: rgb(255, 116, 178))
        case 2:
            let left = currentBoss.position + Vec2(x: -ThunderCarrierBossDefinition.turretOffsetX, y: ThunderCarrierBossDefinition.turretOffsetY)
            let right = currentBoss.position + Vec2(x: ThunderCarrierBossDefinition.turretOffsetX, y: ThunderCarrierBossDefinition.turretOffsetY)
            currentBoss.leftTurretHealth = 0
            currentBoss.rightTurretHealth = 0
            combatFeedback.play(.bossPartDestroyed,
                                context: FeedbackContext(position: left, level: .heavy, tint: rgb(255, 188, 112)), game: self)
            combatFeedback.play(.bossPartDestroyed,
                                context: FeedbackContext(position: right, level: .heavy, tint: rgb(255, 188, 112)), game: self)
            notifyPickup(title: "BOSS DEBUG", detail: "Both turrets destroyed", tint: rgb(255, 211, 112))
        default:
            currentBoss.attackPatternIndex += 1
            currentBoss.attackStage = .recovery
            currentBoss.attackTimer = 0
            notifyPickup(title: "BOSS DEBUG", detail: "Next attack forced", tint: rgb(126, 231, 255))
        }
        bossDebugIndex += 1
        boss = currentBoss
    }

    /// Deterministic structural smoke test for CI and packaging validation.
    /// It exercises entrance, both phase transitions, Phase 3 Spiral, weak
    /// point exposure and the non-instant death state without touching saves.
    func runBossSimulationSmoke(width: Double, height: Double) -> Bool {
        phase = .playing
        player = Vec2(x: width * 0.5, y: height - 90)
        playerInvulnerability = 999
        boss = nil
        enemies.removeAll(keepingCapacity: true)
        recycleAllBullets()
        let field = playfieldBounds(width: width, height: height)
        spawnBoss(field: field)
        for _ in 0..<120 { updateBoss(delta: 1.0 / 60.0, field: field) }
        guard var testBoss = boss, testBoss.lifecycle == .combat, testBoss.phase == 1 else { return false }

        testBoss.health = testBoss.maxHealth * 0.69
        boss = testBoss
        for _ in 0..<80 { updateBoss(delta: 1.0 / 60.0, field: field) }
        guard boss?.phase == 2, boss?.lifecycle == .combat else { return false }

        testBoss = boss!
        testBoss.health = testBoss.maxHealth * 0.29
        boss = testBoss
        for _ in 0..<80 { updateBoss(delta: 1.0 / 60.0, field: field) }
        guard boss?.phase == 3, boss?.lifecycle == .combat else { return false }

        testBoss = boss!
        testBoss.attackPatternIndex = 0
        testBoss.attackStage = .recovery
        testBoss.attackTimer = 0
        testBoss.leftTurretHealth = 0
        testBoss.rightTurretHealth = 0
        boss = testBoss
        for _ in 0..<55 { updateBoss(delta: 1.0 / 60.0, field: field) }
        let enemyBulletCount = bullets.reduce(0) { $0 + ($1.playerOwned ? 0 : 1) }
        guard enemyBulletCount > 0, boss?.weakPointOpen == true else { return false }

        bossSmokePeakBullets = enemyBulletCount
        let simulationStart = Date().timeIntervalSinceReferenceDate
        let simulationFrames = 1_080
        for _ in 0..<simulationFrames {
            updateBoss(delta: 1.0 / 60.0, field: field)
            updateBullets(delta: 1.0 / 60.0, field: field)
            let activeEnemyBullets = bullets.reduce(0) { $0 + ($1.playerOwned ? 0 : 1) }
            bossSmokePeakBullets = max(bossSmokePeakBullets, activeEnemyBullets)
        }
        bossSmokeAverageFrameMilliseconds =
            (Date().timeIntervalSinceReferenceDate - simulationStart) * 1_000 / Double(simulationFrames)

        testBoss = boss!
        beginBossDeath(testBoss, direction: Vec2(x: 0, y: -1), damage: 999, critical: true, damageKind: .cannon)
        let deathStarted = boss?.lifecycle == .dying && enemyBulletClearPending
        boss = nil
        recycleAllBullets()
        return deathStarted
    }

    private func notifyPickup(title: String, detail: String, tint: COLORREF) {
        if language == .chinese {
            let translatedTitle: String
            let translatedDetail: String
            switch title {
            case "LASER CANNON ONLINE":
                translatedTitle = "激光炮已启用"
                translatedDetail = "穿透射击 • 持续 10 秒"
            case "REFLECTOR SHIELD":
                translatedTitle = "反射护盾"
                translatedDetail = "无敌并反弹子弹 • 持续 8 秒"
            case "BULLET ARRAY":
                translatedTitle = "弹幕阵列"
                translatedDetail = "每轮增加 2 发侧翼子弹 • 持续 12 秒"
            case "THUNDER OVERLOAD":
                translatedTitle = "雷霆超载"
                translatedDetail = "火力大幅提升并进入无敌状态 • 持续 6 秒"
            case "THUNDER BURST":
                translatedTitle = "雷霆爆发"
                translatedDetail = "短暂强化火力并清除部分敌弹 • 持续 2.8 秒"
            case "BOSS REWARD CACHE":
                translatedTitle = "首领奖励"
                if detail == "Boss materials secured" {
                    translatedDetail = "已获得首领材料"
                } else if detail.hasPrefix("RARE MODULE CACHE  •  ") {
                    let rawName = detail.replacingOccurrences(of: "RARE MODULE CACHE  •  ", with: "")
                    let localizedName: String
                    switch rawName {
                    case "NOVA MISSILE": localizedName = "新星导弹"
                    case "FROST PLATING": localizedName = "寒霜装甲"
                    case "STORM DRONE": localizedName = "风暴僚机"
                    default: localizedName = rawName
                    }
                    translatedDetail = "获得稀有模块 •  \(localizedName)"
                } else {
                    translatedDetail = detail
                }
            case "ARMOR SHIELD ABSORBED":
                translatedTitle = "装甲护盾已吸收伤害"
                translatedDetail = detail.replacingOccurrences(of: "charge(s) remaining", with: "层护盾剩余")
            case "GHOST PHASE":
                translatedTitle = "幽灵相位"
                translatedDetail = "周期性免疫窗口已激活"
            case "BOSS TURRET DESTROYED":
                translatedTitle = "首领炮塔已摧毁"
                translatedDetail = detail.hasPrefix("Left") ? "左侧武器已禁用" : "右侧武器已禁用"
            case "BOSS LASER":
                translatedTitle = "首领激光预警"
                translatedDetail = "远离标记航道"
            default:
                if title.hasPrefix("ACHIEVEMENT UNLOCKED: ") {
                    let englishName = title.replacingOccurrences(of: "ACHIEVEMENT UNLOCKED: ", with: "")
                    let achievement = AchievementCatalog.all.first { $0.title == englishName }
                    translatedTitle = "解锁成就：" + (achievement?.chineseTitle ?? englishName)
                    translatedDetail = achievement?.chineseDetail ?? detail
                } else if title.hasPrefix("WEAPON SELECTED: ") {
                    let englishName = title.replacingOccurrences(of: "WEAPON SELECTED: ", with: "")
                    let weapon = WeaponType.allCases.first { $0.label == englishName }
                    translatedTitle = "已切换至：" + (weapon?.label(for: .chinese) ?? englishName)
                    switch weapon {
                    case .cannon: translatedDetail = "射速稳定，弹道均衡"
                    case .laser: translatedDetail = "光束可穿透敌人，擅长持续输出"
                    case .scatter: translatedDetail = "近距离覆盖范围广，爆发力强"
                    case .missile: translatedDetail = "自动追踪目标并造成爆炸伤害"
                    case .electromagnetic: translatedDetail = "电磁弹往复摆动，适合压制敌群"
                    case nil: translatedDetail = detail
                    }
                } else if title.hasPrefix("SYNERGY ONLINE: ") {
                    let synergyName: String
                    switch title {
                    case "SYNERGY ONLINE: FROST RAY": synergyName = "寒霜射线"
                    case "SYNERGY ONLINE: FLIGHT ARRAY": synergyName = "飞行阵列"
            case "SYNERGY ONLINE: STORM CRIT": synergyName = "风暴暴击"
            case "SYNERGY ONLINE: OVERLOAD MATRIX": synergyName = "超载矩阵"
            default: synergyName = title.replacingOccurrences(of: "SYNERGY ONLINE: ", with: "")
                    }
                    translatedTitle = "联动已激活：" + synergyName
                    switch title {
                    case "SYNERGY ONLINE: FROST RAY": translatedDetail = "激光伤害强化 • 寒霜光束已解锁"
                    case "SYNERGY ONLINE: FLIGHT ARRAY": translatedDetail = "超频驱动将额外发射辅助弹幕"
                    case "SYNERGY ONLINE: STORM CRIT": translatedDetail = "暴击现在会充能雷霆能量"
                    case "SYNERGY ONLINE: OVERLOAD MATRIX": translatedDetail = "激光与雷霆伤害大幅提升"
                    default: translatedDetail = detail
                    }
                } else if title.hasPrefix("BOSS PHASE ") {
                    translatedTitle = "首领进入第 " + title.replacingOccurrences(of: "BOSS PHASE ", with: "") + " 阶段"
                    translatedDetail = title.hasSuffix("2")
                        ? "装甲突破 • 双重扇形弹幕"
                        : "核心失稳 • 撑过最终风暴"
                } else {
                    translatedTitle = title
                    translatedDetail = detail
                }
            }
            notificationTitle = translatedTitle
            notificationDetail = translatedDetail
        } else {
            notificationTitle = title
            notificationDetail = detail
        }
        notificationTint = tint
        notificationTimer = 3.2
    }

    func activateThunderOverload() {
        guard phase == .playing, thunderEnergy >= CombatConfig.thunderBurstCost else { return }
        let isFullOverload = thunderEnergy >= CombatConfig.thunderOverloadCost
        let cost = isFullOverload ? CombatConfig.thunderOverloadCost : CombatConfig.thunderBurstCost
        let duration = isFullOverload ? CombatConfig.thunderOverloadDuration : CombatConfig.thunderBurstDuration
        thunderEnergy = max(0, thunderEnergy - cost)
        thunderOverloadTime = duration
        playerInvulnerability = max(playerInvulnerability, duration)
        clearEnemyBullets(fraction: isFullOverload ? 1.0 : 0.50)

        let cleared = isFullOverload ? enemies.count : 0
        if isFullOverload {
            for enemy in enemies { spawnExplosion(at: enemy.position, tint: rgb(95, 224, 255), count: 8) }
            enemies.removeAll(keepingCapacity: true)
        }
        if cleared > 0 {
            kills += cleared
            profile.totalKills += cleared
            let credits = scaledReward(cleared * (5 + stage))
            let alloy = scaledReward(cleared * (2 + stage / 2))
            profile.credits += credits
            profile.alloy += alloy
            runCreditsEarned += credits
            runAlloyEarned += alloy
            score += cleared * 60
            combo += cleared
            comboBest = max(comboBest, combo)
            profile.bestCombo = max(profile.bestCombo, comboBest)
            comboTimer = 3.0
        }
        if var currentBoss = boss, currentBoss.lifecycle != .dying {
            var burstDamage = damage * (isFullOverload ? 12 : 5)
            if currentBoss.weakPointOpen { burstDamage *= ThunderCarrierBossDefinition.weakPointMultiplier }
            currentBoss.health -= burstDamage
            boss = currentBoss
            addDamageNumber(at: currentBoss.position, amount: Int(burstDamage), critical: true)
            if currentBoss.health <= 0 {
                beginBossDeath(currentBoss, direction: Vec2(x: 0, y: -1),
                               damage: burstDamage, critical: true, damageKind: .electromagnetic)
            }
        }
        addCameraShake(strength: isFullOverload ? 16 : 9)
        spawnExplosion(at: player, tint: rgb(89, 236, 255), count: isFullOverload ? 42 : 24)
        if isFullOverload {
            notifyPickup(title: "THUNDER OVERLOAD", detail: "6 seconds of amplified fire and immunity", tint: rgb(106, 239, 255))
        } else {
            notifyPickup(title: "THUNDER BURST", detail: "2.8 seconds of amplified fire and partial bullet clear", tint: rgb(132, 214, 255))
        }
    }

    private func registerKill(at position: Vec2, tint: COLORREF, baseScore: Int, radius: Double, isElite: Bool = false) {
        kills += 1
        let rewardMultiplier = isElite ? 3 : 1
        let credits = scaledReward((5 + stage) * rewardMultiplier)
        let alloy = scaledReward((2 + stage / 2) * rewardMultiplier)
        profile.credits += credits
        profile.alloy += alloy
        profile.totalKills += 1
        runCreditsEarned += credits
        runAlloyEarned += alloy
        if kills % 8 == 0 {
            profile.cores += 1
            runCoresEarned += 1
        }
        combo = min(999, combo + 1)
        comboBest = max(comboBest, combo)
        profile.bestCombo = max(profile.bestCombo, comboBest)
        comboTimer = 3.0
        if [10, 25, 50, 100, 200, 500].contains(combo) {
            combatFeedback.play(.comboMilestone,
                                context: FeedbackContext(position: player, damage: Double(combo), level: combo >= 100 ? .heavy : .medium),
                                game: self)
        }
        let multiplier = 1.0 + min(Double(combo), 50.0) * 0.015
        score += Int(Double(baseScore) * multiplier * comboScoreMultiplier)
        experience += isElite ? 3 : 1
        thunderEnergy = min(100, thunderEnergy + (isElite ? 16.0 : 5.0 + min(Double(combo), 20.0) * 0.20) * thunderGainMultiplier)
        if isElite, powerUps.count < 18 {
            powerUps.append(PowerUp(position: position, kind: Int.random(in: 0...2, using: &rng), life: 12))
        }
        addCameraShake(strength: isElite ? 5.4 : (radius > 18 ? 3.2 : 1.1))
    }

    private func scaledReward(_ value: Int) -> Int {
        max(1, Int((Double(value) * activeRewardMultiplier).rounded()))
    }

    private func completeMission() {
        guard phase == .playing else { return }
        runWon = true
        clearEnemyBullets()
        enemies.removeAll(keepingCapacity: true)
        boss = nil

        let completionCredits = scaledReward(320 + stage * 80)
        let completionCores = scaledReward(2 + stage / 3)
        let completionAlloy = scaledReward(28 + stage * 5)
        profile.credits += completionCredits
        profile.cores += completionCores
        profile.alloy += completionAlloy
        runCreditsEarned += completionCredits
        runCoresEarned += completionCores
        runAlloyEarned += completionAlloy
        score += scaledReward(2400 + stage * 450)

        if gameMode == .campaign {
            profile.unlockedMission = max(profile.unlockedMission,
                                          min(MissionCatalog.all.count, selectedMission + 2))
        }
        profile.bestCombo = max(profile.bestCombo, comboBest)
        profile.bestScore = max(profile.bestScore, score)
        if score > highScore {
            highScore = score
        }
        stageBannerTitle = uiText("MISSION COMPLETE", "任务完成")
        stageBannerDetail = uiText("SECTOR SECURED  •  EXTRA REWARDS GRANTED",
                                   "区域已肃清  •  已发放额外奖励")
        persistProfile()
        phase = .gameOver
    }

    private func registerBossDefeat(at position: Vec2) {
        AudioManager.shared.playSFX("sfx_boss")
        bossDefeats += 1
        missionBossDefeated = true
        kills += 1
        combo = min(999, combo + 10)
        comboBest = max(comboBest, combo)
        profile.bestCombo = max(profile.bestCombo, comboBest)
        comboTimer = 4.0
        let experienceReward = 8 + stage * 2
        score += 1800 + stage * 300 + bossDefeats * 250
        experience += experienceReward
        let credits = scaledReward(250 + stage * 50)
        let cores = scaledReward(2 + stage / 3)
        let alloy = scaledReward(24 + stage * 4)
        profile.credits += credits
        profile.cores += cores
        profile.alloy += alloy
        profile.totalBosses += 1
        runCreditsEarned += credits
        runCoresEarned += cores
        runAlloyEarned += alloy
        let guaranteedDrop = profile.bossDropPity >= 2
        let rareDrop = guaranteedDrop || Int.random(in: 0..<100, using: &rng) < 28
        var dropDetail = "Boss materials secured"
        if rareDrop {
            profile.bossDropPity = 0
            profile.cores += 2
            runCoresEarned += 2
            let dropNames = ["NOVA MISSILE", "FROST PLATING", "STORM DRONE"]
            let dropSlots = [2, 3, 4]
            let dropIndex = Int.random(in: 0..<dropNames.count, using: &rng)
            let dropRarity = min(3, 1 + Int.random(in: 1...2, using: &rng))
            runRareDropName = dropNames[dropIndex]
            runRareDropRarity = dropRarity
            profile.inventory.append(EquipmentState(id: "boss_\(bossDefeats)_\(dropIndex)",
                                                     name: dropNames[dropIndex],
                                                     slot: dropSlots[dropIndex],
                                                     level: 1,
                                                     rarity: dropRarity,
                                                     stars: 1,
                                                     evolution: 0,
                                                     affix: Int.random(in: 1...4, using: &rng)))
            dropDetail = "RARE MODULE CACHE  •  \(dropNames[dropIndex])"
            combatFeedback.play(.rareDrop,
                                context: FeedbackContext(position: position, level: .heavy, tint: rgb(255, 211, 112)),
                                game: self)
        } else {
            profile.bossDropPity += 1
        }
        thunderEnergy = min(100, thunderEnergy + 40)
        health = min(maxHealth, health + maxHealth * 0.22)
        playerInvulnerability = max(playerInvulnerability, 1.8)
        // The Boss can be defeated while updateBullets is iterating. Defer
        // clearing enemy bullets until that loop has finished to keep indices valid.
        enemyBulletClearPending = true
        let rewardKinds = [bossDefeats % 3, (bossDefeats + 1) % 3, (bossDefeats + 2) % 3]
        for (index, kind) in rewardKinds.enumerated() {
            if powerUps.count < 18 {
                powerUps.append(PowerUp(position: position + Vec2(x: Double(index - 1) * 34, y: 26), kind: kind, life: 14))
            }
        }
        stageClearTimer = 2.6
        stageBannerTimer = 3.4
        stageBannerTitle = uiText("BOSS DOWN", "首领已击破")
        stageBannerDetail = uiText("REWARD CACHE  •  +\(experienceReward) XP  •  HULL REPAIRED",
                                   "获得奖励  •  +\(experienceReward) 经验  •  机体已修复")
        if gameMode == .endless {
            endlessWaveNumber = min(10_000, endlessWaveNumber + 1)
            stage = endlessWaveNumber
            endlessWavePhase = .combat
            endlessWaveTimeRemaining = 36.0
            missionBossSpawned = false
            missionBossDefeated = false
            stageBannerTitle = uiText("WAVE \(endlessWaveNumber - 1) CLEARED", "第 \(endlessWaveNumber - 1) 波完成")
            stageBannerDetail = uiText("WAVE \(endlessWaveNumber)  •  ENEMIES EVOLVING",
                                       "第 \(endlessWaveNumber) 波  •  敌军强度提升")
        }
        waveTimer = 1.25
        addCameraShake(strength: 18)
        notifyPickup(title: "BOSS REWARD CACHE", detail: dropDetail, tint: rgb(255, 211, 112))
        checkForUpgradeReady()
        persistProfile()
    }

    private func registerGraze(at position: Vec2) {
        grazeCount += 1
        combo = min(999, combo + 1)
        comboBest = max(comboBest, combo)
        profile.bestCombo = max(profile.bestCombo, comboBest)
        comboTimer = 3.0
        score += Int(Double(25 + combo * 2) * comboScoreMultiplier)
        thunderEnergy = min(100, thunderEnergy + 4.0 * thunderGainMultiplier)
        addCameraShake(strength: 1.4)
        spawnHit(at: position, tint: rgb(255, 229, 112))
    }

    private func addDamageNumber(at position: Vec2, amount: Int, critical: Bool) {
        let life = critical ? 0.95 : 0.72
        damageNumbers.append(DamageNumber(position: position + Vec2(x: Double.random(in: -8...8, using: &rng), y: -8),
                                          amount: amount,
                                          critical: critical,
                                          life: life,
                                          maxLife: life))
        if damageNumbers.count > 90 { damageNumbers.removeFirst(damageNumbers.count - 90) }
    }

    private func updateDamageNumbers(delta: Double) {
        guard !damageNumbers.isEmpty else { return }
        var writeIndex = 0
        for readIndex in damageNumbers.indices {
            var number = damageNumbers[readIndex]
            number.position.y -= 30 * delta
            number.life -= delta
            if number.life > 0 {
                damageNumbers[writeIndex] = number
                writeIndex += 1
            }
        }
        if writeIndex < damageNumbers.count {
            damageNumbers.removeLast(damageNumbers.count - writeIndex)
        }
    }

    private func addCameraShake(strength: Double) {
        combatFeedback.requestLegacyShake(strength: strength, game: self)
    }

    private func updateCameraShake(delta: Double) {
        // CombatFeedbackSystem owns camera timing. Retained as a compatibility
        // seam for old callers while gameplay migrates to combat events.
    }

    func currentShakeOffset() -> Vec2 {
        combatFeedback.cameraOffset
    }

    // Experience is an upgrade-charge meter, not a player-level system.
    // Reaching the current threshold opens the three-choice upgrade screen;
    // there is deliberately no level counter or level cap to gate growth.
    private func checkForUpgradeReady() {
        guard phase == .playing, upgradeOptions.isEmpty, experience >= experienceGoal else { return }
        experience -= experienceGoal
        experienceGoal = Int(Double(experienceGoal) * 1.32) + 3
        var pool = Array(0...11)
        let specialistCoreKinds: Set<Int> = [7, 8, 9, 10]
        if selectedBuildCoreKinds.count >= 2 {
            pool.removeAll { specialistCoreKinds.contains($0) && !selectedBuildCoreKinds.contains($0) }
        }
        var selectedKinds = Set<Int>()
        upgradeOptions.removeAll(keepingCapacity: true)
        for _ in 0..<3 {
            var kind = Int.random(in: 0..<pool.count, using: &rng)
            while selectedKinds.contains(kind) { kind = Int.random(in: 0..<pool.count, using: &rng) }
            selectedKinds.insert(kind)
            upgradeOptions.append(makeUpgradeOption(kind: pool[kind], rarity: randomUpgradeRarity()))
        }
        if !upgradeOptions.contains(where: { $0.rarity >= UpgradeRarity.rare.rawValue }) {
            upgradeOptions[0] = makeUpgradeOption(kind: upgradeOptions[0].kind, rarity: .rare)
        }
        // Upgrade selection is a live combat overlay. Keeping the gameplay
        // phase active allows movement, firing, enemies and collisions to
        // continue while the player chooses a module.
    }

    private func randomUpgradeRarity() -> UpgradeRarity {
        let roll = Int.random(in: 0..<100, using: &rng)
        if roll < 55 { return .common }
        if roll < 84 { return .rare }
        if roll < 97 { return .epic }
        return .legendary
    }

    private func upgradeScale(_ rarity: UpgradeRarity) -> Double {
        switch rarity {
        case .common: return 1.0
        case .rare: return 1.25
        case .epic: return 1.60
        case .legendary: return 2.10
        }
    }

    private func makeUpgradeOption(kind: Int, rarity: UpgradeRarity) -> UpgradeOption {
        switch kind {
        case 0:
            let levels = rarity == .legendary ? 2 : 1
            let title = weaponLevel >= 7 ? uiText("WEAPON CORE", "武器核心") : uiText("WING CANNON", "翼炮强化")
            let detail = weaponLevel >= 7
                ? uiText("+" + String(levels) + " weapon level • damage +" + String(Int(6 * upgradeScale(rarity))) + "%",
                         "武器等级 +" + String(levels) + " • 伤害 +" + String(Int(6 * upgradeScale(rarity))) + "%")
                : uiText("+" + String(levels) + " weapon level • new firing pattern",
                         "武器等级 +" + String(levels) + " • 解锁新弹道")
            return UpgradeOption(title: title, detail: detail,
                                 kind: kind, rarity: rarity.rawValue)
        case 1:
            return UpgradeOption(title: uiText("OVERDRIVE", "超频驱动"),
                                 detail: uiText("-" + String(Int(12 * upgradeScale(rarity))) + "% fire cooldown • unlocks Array synergy",
                                                "射击冷却 -" + String(Int(12 * upgradeScale(rarity))) + "% • 解锁阵列联动"),
                                 kind: kind, rarity: rarity.rawValue)
        case 2:
            return UpgradeOption(title: uiText("ARMOR PLATING", "装甲强化"),
                                 detail: uiText("+" + String(Int(24 * upgradeScale(rarity))) + " max HP and repair",
                                                "最大生命 +" + String(Int(24 * upgradeScale(rarity))) + " 并修复机体"),
                                 kind: kind, rarity: rarity.rawValue)
        case 3:
            return UpgradeOption(title: uiText("CRITICAL SYSTEM", "暴击系统"),
                                 detail: uiText("+" + String(Int(4 * upgradeScale(rarity))) + "% critical chance",
                                                "暴击率 +" + String(Int(4 * upgradeScale(rarity))) + "%"),
                                 kind: kind, rarity: rarity.rawValue)
        case 4:
            return UpgradeOption(title: uiText("PIERCING ROUNDS", "穿透弹头"),
                                 detail: uiText("+" + String(max(1, Int(upgradeScale(rarity)))) + " projectile penetration",
                                                "子弹穿透 +" + String(max(1, Int(upgradeScale(rarity))))),
                                 kind: kind, rarity: rarity.rawValue)
        case 5:
            return UpgradeOption(title: uiText("THUNDER AMPLIFIER", "雷霆增幅"),
                                 detail: uiText("+" + String(Int(14 * upgradeScale(rarity))) + "% energy from kills and grazes",
                                                "击杀与擦弹能量 +" + String(Int(14 * upgradeScale(rarity))) + "%"),
                                 kind: kind, rarity: rarity.rawValue)
        case 6:
            return UpgradeOption(title: uiText("GRAZE CALIBRATION", "擦弹校准"),
                                 detail: uiText("+" + String(Int(5 * upgradeScale(rarity))) + "px graze window",
                                                "擦弹范围 +" + String(Int(5 * upgradeScale(rarity))) + " 像素"),
                                 kind: kind, rarity: rarity.rawValue)
        case 7:
            return UpgradeOption(title: uiText("LASER FOCUS", "激光聚焦"),
                                 detail: uiText("Unlocks Laser Core • wider piercing beam", "解锁激光核心 • 穿透光束变宽"),
                                 kind: kind, rarity: rarity.rawValue)
        case 8:
            return UpgradeOption(title: uiText("CRYO CORE", "寒霜核心"),
                                 detail: uiText("Unlocks Cryo Core • pairs with Laser Focus", "解锁寒霜核心 • 可与激光聚焦联动"),
                                 kind: kind, rarity: rarity.rawValue)
        case 9:
            return UpgradeOption(title: uiText("STORM CORE", "风暴核心"),
                                 detail: uiText("Critical hits feed Thunder energy", "暴击会额外充能雷霆能量"),
                                 kind: kind, rarity: rarity.rawValue)
        case 10:
            return UpgradeOption(title: uiText("AUXILIARY ARRAY", "辅助阵列"),
                                 detail: uiText("+1 side projectile • pairs with Overdrive", "侧翼子弹 +1 • 可与超频驱动联动"),
                                 kind: kind, rarity: rarity.rawValue)
        default:
            return UpgradeOption(title: uiText("COMBO ENGINE", "连击引擎"),
                                 detail: uiText("+" + String(Int(8 * upgradeScale(rarity))) + "% Combo score",
                                                "连击分数 +" + String(Int(8 * upgradeScale(rarity))) + "%"),
                                 kind: kind, rarity: rarity.rawValue)
        }
    }

    private func announceNewSynergies(previous: Set<String>) {
        let activated = activeSynergyIDs.subtracting(previous)
        guard let definition = BuildSynergyCatalog.all.first(where: { activated.contains($0.id) }) else { return }
        notifyPickup(title: definition.title(for: language), detail: definition.detail(for: language),
                     tint: definition.id == "frost_ray" ? rgb(137, 228, 255) : (definition.id == "flight_array" ? rgb(255, 220, 120) : rgb(187, 172, 255)))
    }

    func buildFocusLabel() -> String {
        guard !selectedBuildCoreKinds.isEmpty else {
            return uiText("FLEXIBLE LOADOUT", "自由构筑")
        }
        let labels = selectedBuildCoreKinds.sorted().map { kind -> String in
            switch kind {
            case 7: return uiText("LASER", "激光")
            case 8: return uiText("CRYO", "寒霜")
            case 9: return uiText("STORM", "风暴")
            case 10: return uiText("ARRAY", "阵列")
            default: return uiText("CORE", "核心")
            }
        }
        return labels.joined(separator: " + ")
    }

    func chooseUpgrade(_ index: Int) {
        guard (upgradeSelectionActive || phase == .upgrade), upgradeOptions.indices.contains(index) else { return }
        let option = upgradeOptions[index]
        let rarity = UpgradeRarity(rawValue: option.rarity) ?? .common
        let scale = upgradeScale(rarity)
        let previousSynergies = activeSynergyIDs
        switch option.kind {
        case 0:
            let levelGain = rarity == .legendary ? 2 : 1
            weaponLevel += levelGain
            // Once the core patterns are unlocked, every further level still
            // matters instead of becoming a dead/blocked choice.
            if weaponLevel - levelGain >= 7 { projectileDamageMultiplier += 0.06 * scale }
        case 1:
            hasOverdriveCore = true
            fireCooldown = max(0.075, fireCooldown * (1.0 - 0.12 * scale))
        case 2:
            let gain = 24.0 * scale
            maxHealth += gain
            health = min(maxHealth, health + gain)
        case 3:
            criticalChance = min(0.75, criticalChance + 0.04 * scale)
            if rarity.rawValue >= UpgradeRarity.epic.rawValue { criticalMultiplier += 0.12 }
        case 4:
            projectilePenetration += max(1, Int(scale.rounded(.down)))
        case 5:
            thunderGainMultiplier = min(3.0, thunderGainMultiplier + 0.14 * scale)
        case 6:
            grazeRadiusBonus = min(30, grazeRadiusBonus + 5.0 * scale)
        case 7:
            selectedBuildCoreKinds.insert(option.kind)
            hasLaserCore = true
            laserWidthLevel += max(1, Int(scale.rounded(.down)))
            projectileDamageMultiplier += 0.05 * scale
        case 8:
            selectedBuildCoreKinds.insert(option.kind)
            hasCryoCore = true
            laserWidthLevel += max(1, Int(scale.rounded(.down)))
            projectileDamageMultiplier += 0.04 * scale
        case 9:
            selectedBuildCoreKinds.insert(option.kind)
            hasThunderCore = true
            thunderGainMultiplier = min(3.0, thunderGainMultiplier + 0.10 * scale)
        case 10:
            selectedBuildCoreKinds.insert(option.kind)
            hasArrayCore = true
            projectileCountBonus = min(3, projectileCountBonus + 1)
        default:
            comboScoreMultiplier = min(2.5, comboScoreMultiplier + 0.08 * scale)
        }
        phase = .playing
        upgradeOptions.removeAll(keepingCapacity: true)
        let newlyActivated = activeSynergyIDs.subtracting(previousSynergies)
        if newlyActivated.isEmpty {
            notifyPickup(title: option.title, detail: option.detail, tint: rarityColor(rarity))
        } else {
            announceNewSynergies(previous: previousSynergies)
        }
        AudioManager.shared.playSFX("sfx_upgrade")
        checkForUpgradeReady()
    }

    func cycleWeapon() {
        guard phase == .playing else { return }
        let all = WeaponType.allCases
        guard let currentIndex = all.firstIndex(of: weaponType) else { return }
        weaponType = all[(currentIndex + 1) % all.count]
        let detail: String
        switch weaponType {
        case .cannon: detail = uiText("Stable DPS • balanced spread", "稳定输出 • 均衡散射")
        case .laser: detail = uiText("Piercing beam • high single-target damage", "穿透光束 • 单体高伤害")
        case .scatter: detail = uiText("Wide burst • close-range crowd control", "宽幅爆发 • 近距离控场")
        case .missile: detail = uiText("Homing payloads • heavy impact damage", "追踪弹头 • 高额爆炸伤害")
        case .electromagnetic: detail = uiText("Oscillating energy orbs • rapid suppression", "摆动电磁球 • 快速压制")
        }
        profile.equippedWeapon = weaponType.rawValue
        persistProfile()
        let title = language == .chinese
            ? "已选择武器：" + weaponType.label(for: .chinese)
            : "WEAPON SELECTED: " + weaponType.label
        notifyPickup(title: title, detail: detail, tint: weaponType == .laser ? rgb(132, 229, 255) : (weaponType == .scatter ? rgb(255, 185, 104) : rgb(170, 211, 255)))
    }

    func tryDash(width: Double, height: Double) {
        guard phase == .playing, dashCooldown <= 0 else { return }

        var direction = lastMoveDirection
        if direction.length < 0.01 { direction = Vec2(x: 0, y: -1) }

        let origin = player
        let field = playfieldBounds(width: width, height: height)
        player = player + direction.normalized * 128
        player.x = min(max(player.x, field.left + playerRadius + 10), field.right - playerRadius - 10)
        player.y = min(max(player.y, field.top + playerRadius + 10), field.bottom - playerRadius - 12)
        dashCooldown = 4.8
        playerInvulnerability = max(playerInvulnerability, 0.20)
        spawnExplosion(at: origin, tint: rgb(112, 220, 246), count: 10)
        spawnHit(at: player, tint: rgb(173, 240, 255))
        addCameraShake(strength: 2.6)
        AudioManager.shared.playSFX("sfx_powerup")
    }

    func persistProfile() {
        refreshAchievements()
        SaveManager.shared.save(profile)
    }

    func achievementValue(_ metric: AchievementMetric) -> Int {
        switch metric {
        case .runs: return profile.totalRuns
        case .kills: return profile.totalKills
        case .bosses: return profile.totalBosses
        case .combo: return profile.bestCombo
        case .score: return profile.bestScore
        case .missions: return profile.unlockedMission
        case .modules: return profile.inventory.count
        }
    }

    func refreshAchievements() {
        for achievement in AchievementCatalog.all where achievementValue(achievement.metric) >= achievement.target {
            if !profile.achievements.contains(achievement.id) {
                profile.achievements.append(achievement.id)
                if phase == .playing {
                    let title = language == .chinese
                        ? "ACHIEVEMENT UNLOCKED: \(achievement.chineseTitle)"
                        : "ACHIEVEMENT UNLOCKED: \(achievement.title)"
                    notifyPickup(title: title, detail: achievement.detail(for: language), tint: rgb(255, 214, 110))
                    AudioManager.shared.playSFX("sfx_achievement")
                }
            }
        }
    }

    func openArchive() {
        guard phase == .menu || phase == .gameOver else { return }
        profile = SaveManager.shared.profile
        refreshAchievements()
        SaveManager.shared.save(profile)
        archiveTab = 0
        codexCategory = .weapons
        codexPage = 0
        phase = .archive
    }

    func openHangar() {
        guard phase == .menu || phase == .gameOver else { return }
        profile = SaveManager.shared.profile
        hangarMessageTitle = ""
        hangarMessageDetail = ""
        hangarMessageTimer = 0
        hangarTab = 0
        selectedEquipmentSlot = 0
        selectedVaultInventoryIndex = nil
        vaultPage = 0
        vaultFilterSlot = nil
        vaultSortMode = 0
        phase = .hangar
    }

    func openMissionSelect() {
        guard phase == .menu || phase == .gameOver else { return }
        profile = SaveManager.shared.profile
        selectedMission = min(max(0, selectedMission), unlockedMissionCount - 1)
        gameMode = .campaign
        phase = .missionSelect
    }

    func selectMission(_ index: Int) {
        guard phase == .missionSelect, MissionCatalog.all.indices.contains(index),
              index < unlockedMissionCount else { return }
        selectedMission = index
    }

    func selectGameMode(_ mode: GameMode) {
        guard phase == .missionSelect else { return }
        gameMode = mode
    }

    func equipmentUpgradeCost(for item: EquipmentState) -> Int {
        let level = max(1, item.level)
        let value = 120.0 + Double(level - 1) * 90.0 + Double(max(0, item.evolution)) * 180.0
        return Int(min(9_000_000_000_000_000, max(120, value)))
    }

    func equipmentCoreCost(for item: EquipmentState) -> Int {
        item.level >= 10 ? 1 + item.evolution : 0
    }

    func equipmentAlloyCost(for item: EquipmentState) -> Int {
        let level = max(1, item.level)
        let value = 2.0 + Double(level) * 2.0 + Double(max(0, item.evolution)) * 4.0
        return Int(min(9_000_000_000_000_000, max(2, value)))
    }

    func equipmentPromoteCost(for item: EquipmentState) -> (credits: Int, alloy: Int, cores: Int) {
        let nextRarity = min(4, item.rarity + 1)
        return (420 + nextRarity * 260, 24 + nextRarity * 18, 1 + nextRarity)
    }

    func equipmentDisplayName(_ item: EquipmentState) -> String {
        guard language == .chinese else { return item.name }
        switch item.id {
        case "thunder_frame": return "雷霆机框"
        case "arc_cannon": return "弧光机炮"
        case "nova_payload": return "新星弹舱"
        case "aegis_armor": return "神盾装甲"
        case "orbit_drone": return "轨道僚机"
        default:
            switch item.name {
            case "NOVA MISSILE": return "新星导弹"
            case "FROST PLATING": return "寒霜装甲"
            case "STORM DRONE": return "风暴僚机"
            default: return item.name
            }
        }
    }

    func equipmentBonusText(for item: EquipmentState) -> String {
        let base: String
        switch item.slot {
        case 0: base = uiText("+8 MAX HP / LEVEL", "最大生命 +8 / 等级")
        case 1: base = uiText("+1.5 WEAPON DAMAGE / LEVEL", "武器伤害 +1.5 / 等级")
        case 2: base = uiText("+0.12 SECONDARY RATE / LEVEL", "副武器频率 +0.12 / 等级")
        case 3: base = uiText("+4 MAX HP / LEVEL", "最大生命 +4 / 等级")
        default: base = uiText("+0.6 DRONE DAMAGE / LEVEL", "僚机伤害 +0.6 / 等级")
        }
        let affix: String
        switch item.affix {
        case 1: affix = uiText("DAMAGE +10%", "伤害 +10%")
        case 2: affix = uiText("CRIT +5%", "暴击 +5%")
        case 3: affix = uiText("FIRE RATE +10%", "射速 +10%")
        case 4: affix = uiText("DAMAGE TAKEN -6%", "所受伤害 -6%")
        default: affix = uiText("STABLE CORE", "稳定核心")
        }
        return base + "  •  " + uiText("EV ", "进阶 ") + "\(item.evolution)  •  \(affix)"
    }

    func upgradeEquipment(_ slot: Int) {
        guard phase == .hangar, profile.equipment.indices.contains(slot) else { return }
        let item = profile.equipment[slot]
        let creditCost = equipmentUpgradeCost(for: item)
        let alloyCost = equipmentAlloyCost(for: item)
        let coreCost = equipmentCoreCost(for: item)
        guard profile.credits >= creditCost, profile.alloy >= alloyCost, profile.cores >= coreCost else {
            hangarMessageTitle = uiText("INSUFFICIENT RESOURCES", "资源不足")
            hangarMessageDetail = uiText("Need \(creditCost) C  /  \(alloyCost) A  /  \(coreCost) CORE",
                                         "需要 \(creditCost) 金 / \(alloyCost) 合金 / \(coreCost) 核心")
            hangarMessageTimer = 2.4
            return
        }
        profile.credits -= creditCost
        profile.alloy -= alloyCost
        profile.cores -= coreCost
        profile.equipment[slot].level += 1
        if profile.equipment[slot].level % 10 == 0 {
            profile.equipment[slot].evolution = min(5, profile.equipment[slot].evolution + 1)
            profile.equipment[slot].stars = min(5, profile.equipment[slot].stars + 1)
        }
        let upgraded = profile.equipment[slot]
        if let inventoryIndex = profile.inventory.firstIndex(where: { $0.id == upgraded.id }) {
            profile.inventory[inventoryIndex] = upgraded
        }
        persistProfile()
        hangarMessageTitle = uiText("MODULE UPGRADED", "模块已强化")
        hangarMessageDetail = uiText("\(upgraded.name)  •  LEVEL \(upgraded.level)  •  EV \(upgraded.evolution)",
                                     "\(equipmentDisplayName(upgraded))  •  等级 \(upgraded.level)  •  进阶 \(upgraded.evolution)")
        hangarMessageTimer = 2.4
        AudioManager.shared.playSFX("sfx_upgrade")
    }

    func upgradeEquipmentMultiple(_ slot: Int, count: Int) {
        guard phase == .hangar, profile.equipment.indices.contains(slot), count > 0 else { return }
        let startingLevel = profile.equipment[slot].level
        var completed = 0
        while completed < count {
            let item = profile.equipment[slot]
            let creditCost = equipmentUpgradeCost(for: item)
            let alloyCost = equipmentAlloyCost(for: item)
            let coreCost = equipmentCoreCost(for: item)
            guard profile.credits >= creditCost, profile.alloy >= alloyCost, profile.cores >= coreCost else { break }
            profile.credits -= creditCost
            profile.alloy -= alloyCost
            profile.cores -= coreCost
            profile.equipment[slot].level += 1
            if profile.equipment[slot].level % 10 == 0 {
                profile.equipment[slot].evolution = min(5, profile.equipment[slot].evolution + 1)
                profile.equipment[slot].stars = min(5, profile.equipment[slot].stars + 1)
            }
            completed += 1
        }
        guard completed > 0 else {
            let item = profile.equipment[slot]
            hangarMessageTitle = uiText("INSUFFICIENT RESOURCES", "资源不足")
            hangarMessageDetail = uiText("Next level needs \(equipmentUpgradeCost(for: item)) C / \(equipmentAlloyCost(for: item)) A / \(equipmentCoreCost(for: item)) CORE",
                                         "下一级需要 \(equipmentUpgradeCost(for: item)) 金币 / \(equipmentAlloyCost(for: item)) 合金 / \(equipmentCoreCost(for: item)) 核心")
            hangarMessageTimer = 2.4
            return
        }
        let upgraded = profile.equipment[slot]
        if let inventoryIndex = profile.inventory.firstIndex(where: { $0.id == upgraded.id }) {
            profile.inventory[inventoryIndex] = upgraded
        }
        persistProfile()
        hangarMessageTitle = uiText("BATCH UPGRADE COMPLETE", "批量强化完成")
        hangarMessageDetail = uiText("LEVEL \(startingLevel) → \(upgraded.level)  •  \(completed) upgrade(s)",
                                     "等级 \(startingLevel) → \(upgraded.level)  •  成功强化 \(completed) 次")
        hangarMessageTimer = 2.4
        AudioManager.shared.playSFX("sfx_upgrade")
    }

    func promoteEquipment(_ slot: Int) {
        guard phase == .hangar, profile.equipment.indices.contains(slot) else { return }
        let item = profile.equipment[slot]
        guard item.rarity < 4 else {
            hangarMessageTitle = uiText("MAX QUALITY", "已达最高品质")
            hangarMessageDetail = uiText("This module is already RED quality", "该模块已经是红色品质")
            hangarMessageTimer = 2.4
            return
        }
        let cost = equipmentPromoteCost(for: item)
        guard profile.credits >= cost.credits, profile.alloy >= cost.alloy, profile.cores >= cost.cores else {
            hangarMessageTitle = uiText("INSUFFICIENT RESOURCES", "资源不足")
            hangarMessageDetail = uiText("Need \(cost.credits) C / \(cost.alloy) A / \(cost.cores) CORE",
                                         "需要 \(cost.credits) 金 / \(cost.alloy) 合金 / \(cost.cores) 核心")
            hangarMessageTimer = 2.4
            return
        }
        profile.credits -= cost.credits
        profile.alloy -= cost.alloy
        profile.cores -= cost.cores
        profile.equipment[slot].rarity += 1
        profile.equipment[slot].stars = min(5, max(profile.equipment[slot].stars + 1, profile.equipment[slot].rarity))
        profile.equipment[slot].evolution = min(5, max(profile.equipment[slot].evolution, profile.equipment[slot].rarity - 1))
        if profile.equipment[slot].affix == 0 {
            profile.equipment[slot].affix = Int.random(in: 1...4, using: &rng)
        }
        let upgraded = profile.equipment[slot]
        if let inventoryIndex = profile.inventory.firstIndex(where: { $0.id == upgraded.id }) {
            profile.inventory[inventoryIndex] = upgraded
        }
        persistProfile()
        hangarMessageTitle = uiText("QUALITY PROMOTED", "品质已提升")
        hangarMessageDetail = uiText("\(upgraded.name)  •  \(equipmentQualityName(upgraded.rarity))",
                                     "\(equipmentDisplayName(upgraded))  •  \(equipmentQualityName(upgraded.rarity))")
        hangarMessageTimer = 2.4
        AudioManager.shared.playSFX("sfx_upgrade")
    }

    func equipmentQualityName(_ rarity: Int) -> String {
        let names = language == .chinese ? ["白色", "蓝色", "紫色", "金色", "红色"] : ["WHITE", "BLUE", "PURPLE", "GOLD", "RED"]
        return names[min(names.count - 1, max(0, rarity))]
    }

    func cycleVaultFilter() {
        let filters: [Int?] = [nil, 0, 1, 2, 3, 4]
        let current = filters.firstIndex { $0 == vaultFilterSlot } ?? 0
        vaultFilterSlot = filters[(current + 1) % filters.count]
        vaultPage = 0
        selectedVaultInventoryIndex = nil
    }

    func cycleVaultSort() {
        vaultSortMode = (vaultSortMode + 1) % 3
        vaultPage = 0
        selectedVaultInventoryIndex = nil
    }

    func moveVaultPage(_ delta: Int) {
        vaultPage = min(max(0, vaultPage + delta), vaultPageCount - 1)
        selectedVaultInventoryIndex = nil
    }

    func selectShip(_ value: ShipType) {
        guard phase == .hangar else { return }
        shipType = value
        profile.selectedShip = value.rawValue
        persistProfile()
        hangarMessageTitle = uiText("SHIP SELECTED: \(value.label)", "已选择战机：\(value.label(for: .chinese))")
        hangarMessageDetail = value.subtitle(for: language)
        hangarMessageTimer = 2.4
    }

    func setHangarTab(_ tab: Int) {
        guard phase == .hangar, tab == 0 || tab == 1 else { return }
        hangarTab = tab
        selectedVaultInventoryIndex = nil
    }

    func toggleEquipmentLock(_ slot: Int) {
        guard phase == .hangar, profile.equipment.indices.contains(slot) else { return }
        let nextValue = !profile.equipment[slot].locked
        profile.equipment[slot].locked = nextValue
        let itemID = profile.equipment[slot].id
        for index in profile.inventory.indices where profile.inventory[index].id == itemID {
            profile.inventory[index].locked = nextValue
        }
        persistProfile()
        hangarMessageTitle = nextValue ? uiText("MODULE LOCKED", "模块已锁定") : uiText("MODULE UNLOCKED", "模块已解锁")
        hangarMessageDetail = equipmentDisplayName(profile.equipment[slot])
        hangarMessageTimer = 1.8
        AudioManager.shared.playSFX("sfx_upgrade")
    }

    func toggleInventoryLock(_ inventoryIndex: Int) {
        guard phase == .hangar, profile.inventory.indices.contains(inventoryIndex) else { return }
        profile.inventory[inventoryIndex].locked.toggle()
        let itemID = profile.inventory[inventoryIndex].id
        if let equippedIndex = profile.equipment.firstIndex(where: { $0.id == itemID }) {
            profile.equipment[equippedIndex].locked = profile.inventory[inventoryIndex].locked
        }
        persistProfile()
        let locked = profile.inventory[inventoryIndex].locked
        hangarMessageTitle = locked ? uiText("MODULE LOCKED", "模块已锁定") : uiText("MODULE UNLOCKED", "模块已解锁")
        hangarMessageDetail = equipmentDisplayName(profile.inventory[inventoryIndex])
        hangarMessageTimer = 1.8
        AudioManager.shared.playSFX("sfx_upgrade")
    }

    func equipInventoryItem(_ index: Int) {
        guard phase == .hangar, profile.inventory.indices.contains(index) else { return }
        let item = profile.inventory[index]
        guard (0...4).contains(item.slot) else { return }
        guard let slotIndex = profile.equipment.firstIndex(where: { $0.slot == item.slot }) else { return }
        profile.equipment[slotIndex] = item
        persistProfile()
        hangarMessageTitle = uiText("LOADOUT UPDATED", "装备配置已更新")
        hangarMessageDetail = uiText("\(item.name) equipped in slot \(item.slot + 1)",
                                     "\(equipmentDisplayName(item)) 已装备至第 \(item.slot + 1) 槽位")
        hangarMessageTimer = 2.4
    }

    func combatPower() -> Int {
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

    func updateMousePosition(_ point: Vec2) {
        mousePosition = point
    }

    /// Convert a screen-space logical point into the coordinate space used by
    /// UI layout. Gameplay keeps the raw pointer only for menu interaction;
    /// fighter movement is keyboard-only.
    func uiPoint(for point: Vec2, width: Double, height: Double) -> Vec2 {
        let scale = min(1.0, min(1.2, max(0.8, Double(profile.uiScale) / 100.0)))
        let offsetX = (width - width * scale) * 0.5
        let offsetY = (height - height * scale) * 0.5
        return Vec2(x: (point.x - offsetX) / scale, y: (point.y - offsetY) / scale)
    }

    func togglePause() {
        if phase == .playing { phase = .paused }
        else if phase == .paused { phase = .playing }
    }

    func requestAbandonRunConfirmation() {
        guard phase == .paused else { return }
        confirmation = .abandonRun
    }

    func resolveConfirmation(confirmed: Bool) {
        guard let pending = confirmation else { return }
        confirmation = nil
        guard confirmed else { return }
        switch pending {
        case .abandonRun:
            phase = .menu
            persistProfile()
        }
    }

    func openControls(from source: GamePhase) {
        phaseBeforeControls = source
        phase = .controls
    }

    func openSettings(from source: GamePhase) {
        phaseBeforeSettings = source
        phase = .settings
    }

    func openSaveSlots(from source: GamePhase = .menu) {
        phaseBeforeSaveSlots = source
        phase = .saveSlots
    }

    func selectSaveSlot(_ slot: Int) {
        guard SaveManager.shared.selectSlot(slot) else { return }
        profile = SaveManager.shared.profile
        highScore = profile.bestScore
        controlMode = .wasd
        profile.controlMode = ControlMode.wasd.rawValue
        // SDLFullGame observes profile changes on its next frame.
        selectedMission = min(max(0, selectedMission), max(0, unlockedMissionCount - 1))
        hangarMessageTitle = uiText("SAVE SLOT \(slot + 1) SELECTED", "已选择存档 \(slot + 1)")
        hangarMessageDetail = uiText("Progress will autosave in the game folder.", "进度会自动保存到游戏根目录。")
        hangarMessageTimer = 2.8
        phase = phaseBeforeSaveSlots
    }

    func selectLanguage(_ value: GameLanguage) {
        profile.language = value.rawValue
        persistProfile()
    }

    func cycleBGMVolume() {
        let levels = [0, 25, 50, 75, 100]
        let index = levels.firstIndex(of: profile.bgmVolume) ?? 2
        profile.bgmVolume = levels[(index + 1) % levels.count]
        AudioManager.shared.configure(bgmVolume: profile.bgmVolume, sfxVolume: profile.sfxVolume)
        if profile.bgmVolume > 0 { AudioManager.shared.startMusic() }
        persistProfile()
    }

    func cycleSFXVolume() {
        let levels = [0, 25, 50, 75, 100]
        let index = levels.firstIndex(of: profile.sfxVolume) ?? 3
        profile.sfxVolume = levels[(index + 1) % levels.count]
        AudioManager.shared.configure(bgmVolume: profile.bgmVolume, sfxVolume: profile.sfxVolume)
        persistProfile()
    }

    func cycleCameraShake() {
        profile.cameraShake = (profile.cameraShake + 1) % 4
        persistProfile()
    }

    func cycleWindowMode() {
        profile.isFullscreen.toggle()
        persistProfile()
        // SDLFullGame observes the setting on its next frame and applies the
        // native window operation outside the click handler.
        // SDLFullGame observes profile changes on its next frame.
    }

    func cycleResolution() {
        if profile.resolutionWidth == 1280 && profile.resolutionHeight == 720 {
            profile.resolutionWidth = 1024
            profile.resolutionHeight = 768
        } else {
            profile.resolutionWidth = 1280
            profile.resolutionHeight = 720
        }
        persistProfile()
        // SDLFullGame observes profile changes on its next frame.
    }

    func cycleUIScale() {
        let values = [80, 90, 100, 110, 120]
        let current = values.firstIndex(of: profile.uiScale) ?? 2
        profile.uiScale = values[(current + 1) % values.count]
        persistProfile()
        hangarMessageTitle = uiText("UI SCALE (profile.uiScale)%", "界面缩放 (profile.uiScale)%")
        hangarMessageDetail = uiText("Text and controls will use the new readability scale.", "文字和控件已切换到新的可读性比例。")
        hangarMessageTimer = 1.8
    }

    func uiText(_ english: String, _ chinese: String) -> String {
        language == .chinese ? chinese : english
    }

    func localizedRarity(_ rarity: UpgradeRarity) -> String {
        switch rarity {
        case .common: return uiText("COMMON", "普通")
        case .rare: return uiText("RARE", "稀有")
        case .epic: return uiText("EPIC", "史诗")
        case .legendary: return uiText("LEGENDARY", "传说")
        }
    }

    func handleClick(at point: Vec2, width: Double, height: Double) {
        if confirmation != nil {
            if confirmationConfirmButton(width: width, height: height).contains(point) {
                resolveConfirmation(confirmed: true)
            } else if confirmationCancelButton(width: width, height: height).contains(point) {
                resolveConfirmation(confirmed: false)
            }
            return
        }
        if upgradeSelectionActive {
            for (index, card) in upgradeCards(width: width, height: height).enumerated() where card.contains(point) {
                chooseUpgrade(index)
                return
            }
        }
        switch phase {
        case .menu:
            if saveSlotButton(width: width, height: height).contains(point) {
                openSaveSlots()
                return
            }
            let buttons = mainMenuButtons(width: width, height: height)
            if buttons[0].contains(point) { openMissionSelect() }
            else if buttons[1].contains(point) { openControls(from: .menu) }
            else if buttons[2].contains(point) { openHangar() }
            else if buttons[3].contains(point) { openSettings(from: .menu) }
            else if buttons[4].contains(point) { exitRequested = true }
            else if buttons[5].contains(point) { openArchive() }
        case .saveSlots:
            for (index, card) in saveSlotCards(width: width, height: height).enumerated() where card.contains(point) {
                selectSaveSlot(index)
                return
            }
            if saveSlotsBackButton(width: width, height: height).contains(point) {
                phase = phaseBeforeSaveSlots
            }
        case .missionSelect:
            for (index, card) in missionCards(width: width, height: height).enumerated() where card.contains(point) {
                selectMission(index)
                return
            }
            for (index, card) in modeCards(width: width, height: height).enumerated() where card.contains(point) {
                if let mode = GameMode(rawValue: index) { selectGameMode(mode) }
                return
            }
            if missionLaunchButton(width: width, height: height).contains(point) {
                start(width: width, height: height)
            } else if missionBackButton(width: width, height: height).contains(point) {
                phase = .menu
            }
        case .archive:
            let tabs = archiveTabButtons(width: width, height: height)
            if tabs[0].contains(point) { archiveTab = 0; codexPage = 0 }
            else if tabs[1].contains(point) { archiveTab = 1; codexPage = 0 }
            else if archiveTab == 1 {
                for (index, card) in codexCategoryButtons(width: width, height: height).enumerated() where card.contains(point) {
                    codexCategory = CodexCategory(rawValue: index) ?? .weapons
                    codexPage = 0
                    return
                }
                let codexPageCount = max(1, (CodexCatalog.all.filter { $0.category == codexCategory }.count + 2) / 3)
                if codexPrevButton(width: width, height: height).contains(point) { codexPage = max(0, codexPage - 1) }
                else if codexNextButton(width: width, height: height).contains(point) { codexPage = min(codexPageCount - 1, codexPage + 1) }
            }
            if archiveBackButton(width: width, height: height).contains(point) { phase = .menu }
        case .controls:
            if controlsBackButton(width: width, height: height).contains(point) { phase = phaseBeforeControls }
        case .settings:
            let languages = settingsLanguageButtons(width: width, height: height)
            if languages[0].contains(point) { selectLanguage(.english) }
            else if languages[1].contains(point) { selectLanguage(.chinese) }
            else if settingsBGMButton(width: width, height: height).contains(point) { cycleBGMVolume() }
            else if settingsSFXButton(width: width, height: height).contains(point) { cycleSFXVolume() }
            else if settingsShakeButton(width: width, height: height).contains(point) { cycleCameraShake() }
            else if settingsWindowModeButton(width: width, height: height).contains(point) { cycleWindowMode() }
            else if settingsResolutionButton(width: width, height: height).contains(point) { cycleResolution() }
            else if settingsUIScaleButton(width: width, height: height).contains(point) { cycleUIScale() }
            else if settingsBackButton(width: width, height: height).contains(point) { phase = phaseBeforeSettings }
        case .hangar:
            for (index, tab) in hangarTabButtons(width: width, height: height).enumerated() where tab.contains(point) {
                setHangarTab(index)
                return
            }
            for (index, card) in shipCards(width: width, height: height).enumerated() where card.contains(point) {
                if let ship = ShipType(rawValue: index) { selectShip(ship) }
                return
            }
            if hangarTab == 0 {
                for (index, card) in hangarCards(width: width, height: height).enumerated() where card.contains(point) {
                    selectedEquipmentSlot = index
                    break
                }
                if hangarUpgradeButton(width: width, height: height).contains(point) { upgradeEquipment(selectedEquipmentSlot) }
                else if hangarBatchUpgradeButton(width: width, height: height).contains(point) { upgradeEquipmentMultiple(selectedEquipmentSlot, count: 5) }
                else if hangarPromoteButton(width: width, height: height).contains(point) { promoteEquipment(selectedEquipmentSlot) }
                else if hangarLockButton(width: width, height: height).contains(point) { toggleEquipmentLock(selectedEquipmentSlot) }
            } else {
                if vaultFilterButton(width: width, height: height).contains(point) { cycleVaultFilter(); return }
                if vaultSortButton(width: width, height: height).contains(point) { cycleVaultSort(); return }
                if vaultPrevButton(width: width, height: height).contains(point) { moveVaultPage(-1); return }
                if vaultNextButton(width: width, height: height).contains(point) { moveVaultPage(1); return }
                let visible = visibleVaultIndices
                for (cardIndex, card) in vaultCards(width: width, height: height).enumerated() where card.contains(point) {
                    let absoluteIndex = vaultPage * 4 + cardIndex
                    if visible.indices.contains(absoluteIndex) {
                        let inventoryIndex = visible[absoluteIndex]
                        selectedVaultInventoryIndex = inventoryIndex
                    }
                    break
                }
                if let selectedVaultInventoryIndex {
                    if vaultEquipButton(width: width, height: height).contains(point) { equipInventoryItem(selectedVaultInventoryIndex) }
                    else if vaultSelectedLockButton(width: width, height: height).contains(point) { toggleInventoryLock(selectedVaultInventoryIndex) }
                }
            }
            if hangarBackButton(width: width, height: height).contains(point) { phase = .menu }
        case .paused:
            let buttons = pauseButtons(width: width, height: height)
            if buttons[0].contains(point) { phase = .playing }
            else if buttons[1].contains(point) { start(width: width, height: height) }
            else if buttons[2].contains(point) { openSettings(from: .paused) }
            else if buttons[3].contains(point) { requestAbandonRunConfirmation() }
            else if buttons[4].contains(point) { phase = .menu }
        case .upgrade:
            for (index, card) in upgradeCards(width: width, height: height).enumerated() where card.contains(point) {
                chooseUpgrade(index)
                break
            }
        case .gameOver:
            let buttons = gameOverButtons(width: width, height: height)
            if buttons[0].contains(point) { start(width: width, height: height) }
            else if buttons[1].contains(point) { phase = .menu }
        case .playing:
            break
        }
    }

    private func updateParticles(delta: Double) {
        guard !particles.isEmpty else { return }
        // Compact in place instead of remove(at:), which shifts every later
        // particle and becomes quadratic during large explosions.
        var writeIndex = 0
        for readIndex in particles.indices {
            var particle = particles[readIndex]
            particle.position = particle.position + particle.velocity * delta
            particle.velocity = particle.velocity * 0.96
            particle.life -= delta
            if particle.life > 0 {
                particles[writeIndex] = particle
                writeIndex += 1
            }
        }
        if writeIndex < particles.count {
            particles.removeLast(particles.count - writeIndex)
        }
    }

    private func spawnHit(at position: Vec2, tint: COLORREF) {
        AudioManager.shared.playSFX("sfx_hit")
        for _ in 0..<4 {
            if particles.count >= particleLimit { break }
            let life = Double.random(in: 0.16...0.32, using: &rng)
            particles.append(Particle(position: position,
                                      velocity: Vec2(x: Double.random(in: -75...75, using: &rng), y: Double.random(in: -75...75, using: &rng)),
                                      radius: Double.random(in: 2...4, using: &rng),
                                      life: life, maxLife: life, tint: tint))
        }
    }

    private func spawnExplosion(at position: Vec2, tint: COLORREF, count: Int) {
        AudioManager.shared.playSFX("sfx_explosion")
        for _ in 0..<count {
            if particles.count >= particleLimit { break }
            let life = Double.random(in: 0.30...0.82, using: &rng)
            let angle = Double.random(in: 0...(Double.pi * 2), using: &rng)
            let speed = Double.random(in: 35...190, using: &rng)
            particles.append(Particle(position: position,
                                      velocity: Vec2(x: cos(angle) * speed, y: sin(angle) * speed),
                                      radius: Double.random(in: 2...6, using: &rng),
                                      life: life, maxLife: life, tint: tint))
        }
    }
}

// MARK: - Music and sound effects

@_silgen_name("mciSendStringW")
private func mciSendStringW(_ command: UnsafePointer<WCHAR>?, _ returnString: UnsafeMutablePointer<WCHAR>?,
                            _ returnLength: UINT, _ callback: HWND?) -> UINT

// PlaySoundW uses the native waveOut path and does not depend on the optional
// MCI MPEG/WAV drivers. This is intentionally used for BGM only; MCI remains
// useful for short SFX because it allows per-alias volume control.
@_silgen_name("PlaySoundW")
private func playSoundW(_ sound: UnsafeRawPointer?, _ module: UnsafeRawPointer?, _ flags: DWORD) -> Int32

// Raise the Windows multimedia timer resolution while the game is running.
// SetTimer is still driven on the UI thread, but this removes the default
// ~15.6 ms quantization that otherwise causes uneven 16 ms frame intervals.
@_silgen_name("timeBeginPeriod")
private func timeBeginPeriod(_ period: UINT) -> UINT

@_silgen_name("timeEndPeriod")
private func timeEndPeriod(_ period: UINT) -> UINT

final class AudioManager: @unchecked Sendable {
    static let shared = AudioManager()
    private let commandQueue = DispatchQueue(label: "ThunderSwift.AudioCommands", qos: .userInitiated)
    private let stateLock = NSLock()
    private var musicIsPlaying = false
    // The SDL presentation path owns music playback. Keeping this gate in
    // the legacy WinMM manager prevents Game.start() and other gameplay
    // callbacks from starting a second copy of the same track.
    private var externalMusicActive = false
    private var bgmVolume = 70
    private var sfxVolume = 80
    private var openedAliases: Set<String> = []
    private var lastSFXTime: [String: Double] = [:]
    private var sfxPaths: [String: String?] = [:]
    private var sfxAliases: [String: String] = [:]
    private var musicWatchdogScheduled = false
    // PlaySoundW's asynchronous memory mode keeps the complete battle track
    // resident, so audio playback never competes with frame rendering or
    // disk I/O during a dense wave.
    private var musicBuffer: UnsafeMutablePointer<UInt8>?
    private var musicBufferLength = 0

    private init() {}

    private func withState<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }

    private func audioFilePath(_ filename: String) -> String? {
        let fileManager = FileManager.default
        var directories = [fileManager.currentDirectoryPath]
        if let argument = CommandLine.arguments.first, !argument.isEmpty {
            directories.append(URL(fileURLWithPath: argument).deletingLastPathComponent().path)
        }
        var visited: Set<String> = []
        for directory in directories {
            let path = URL(fileURLWithPath: directory).appendingPathComponent("Resources/Audio/\(filename)").path
            if visited.insert(path).inserted, fileManager.fileExists(atPath: path) { return path }
        }
        return nil
    }

    func configure(bgmVolume: Int, sfxVolume: Int) {
        let (previousSFXVolume, currentBGMVolume, currentSFXVolume, playing) = withState { () -> (Int, Int, Int, Bool) in
            let previous = self.sfxVolume
            self.bgmVolume = min(100, max(0, bgmVolume))
            self.sfxVolume = min(100, max(0, sfxVolume))
            return (previous, self.bgmVolume, self.sfxVolume, self.musicIsPlaying)
        }
        if currentBGMVolume == 0 {
            if playing { stopMusic() }
        } else if playing {
            // PlaySound has no per-stream volume knob. Restarting after a
            // setting change keeps the native path authoritative and avoids
            // leaving an MCI alias silently active in the background.
            stopMusic()
            startMusic()
        }
        if previousSFXVolume != currentSFXVolume {
            commandQueue.async { [self] in
                for alias in openedAliases where alias != "thunder_bgm" {
                    _ = send("setaudio \(alias) volume to \(currentSFXVolume * 10)")
                }
            }
        }
    }

    @discardableResult
    private func send(_ command: String) -> UINT {
        var chars = wide(command)
        return chars.withUnsafeMutableBufferPointer { buffer in
            mciSendStringW(buffer.baseAddress, nil, 0, nil)
        }
    }

    private func query(_ command: String) -> (code: UINT, value: String) {
        var chars = wide(command)
        var result = [WCHAR](repeating: 0, count: 64)
        let code = chars.withUnsafeMutableBufferPointer { commandBuffer in
            result.withUnsafeMutableBufferPointer { resultBuffer in
                mciSendStringW(commandBuffer.baseAddress, resultBuffer.baseAddress,
                               UINT(resultBuffer.count), nil)
            }
        }
        let length = result.firstIndex(of: 0) ?? result.endIndex
        return (code, String(decoding: result[..<length], as: UTF16.self))
    }

    func startMusic() {
        let request: String? = withState {
            guard !externalMusicActive, !musicIsPlaying, bgmVolume > 0 else { return nil }
            // PlaySoundW supports PCM WAV directly on Windows. This WAV is a
            // decoded copy of the requested thunder_swift_battle.mp3 track,
            // so playback uses the exact battle composition without routing
            // it through the MCI decoder that caused silent playback.
            let path = audioFilePath("thunder_swift_battle.wav")
            guard let path else { return nil }
            musicIsPlaying = true
            return path
        }
        guard let request else { return }
        commandQueue.async { [self] in
            playMusicLoop(path: request, attempt: 0)
        }
    }

    func setExternalMusicActive(_ active: Bool) {
        withState { externalMusicActive = active }
        if active { stopMusic() }
    }

    private func playMusicLoop(path: String, attempt: Int) {
        guard withState({ musicIsPlaying && bgmVolume > 0 }) else { return }
        if musicBuffer == nil {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)), !data.isEmpty else {
                if attempt < 3 {
                    commandQueue.asyncAfter(deadline: .now() + .milliseconds(250)) { [weak self] in
                        self?.playMusicLoop(path: path, attempt: attempt + 1)
                    }
                } else {
                    withState { musicIsPlaying = false }
                }
                return
            }
            let storage = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
            data.copyBytes(to: storage, count: data.count)
            musicBuffer = storage
            musicBufferLength = data.count
        }
        // SND_MEMORY (0x4) + SND_ASYNC (0x1) + SND_LOOP (0x8) +
        // SND_NODEFAULT (0x2). The allocated buffer remains alive until the
        // stop command has completed, as required by asynchronous playback.
        let result = playSoundW(UnsafeRawPointer(musicBuffer), nil, DWORD(0x0000000F))
        guard result != 0 else {
            if attempt < 3 {
                commandQueue.asyncAfter(deadline: .now() + .milliseconds(250)) { [weak self] in
                    self?.playMusicLoop(path: path, attempt: attempt + 1)
                }
            } else {
                withState { musicIsPlaying = false }
            }
            return
        }
    }

    private func scheduleMusicWatchdog() {
        let shouldSchedule = withState { () -> Bool in
            guard !musicWatchdogScheduled else { return false }
            musicWatchdogScheduled = true
            return true
        }
        guard shouldSchedule else { return }
        commandQueue.asyncAfter(deadline: .now() + .seconds(2)) { [weak self] in
            self?.musicWatchdogTick()
        }
    }

    private func musicWatchdogTick() {
        let active = withState { musicIsPlaying && bgmVolume > 0 }
        guard active else {
            withState { musicWatchdogScheduled = false }
            return
        }

        let status = query("status thunder_bgm mode")
        if status.code != 0 || status.value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "playing" {
            // The Windows MCI device can silently lose an alias after an
            // output-device change. Mark it inactive and let startMusic()
            // reopen the preferred track (with the WAV fallback) safely.
            withState { musicIsPlaying = false }
            startMusic()
        }
        withState { musicWatchdogScheduled = false }
        scheduleMusicWatchdog()
    }

    private func openAndPlayMusic(path: String, volume: Int, attempt: Int) {
        guard withState({ musicIsPlaying }) else { return }
        _ = send("close thunder_bgm")
        let extensionName = URL(fileURLWithPath: path).pathExtension.lowercased()
        let mediaType = extensionName == "mp3" ? "mpegvideo" : "waveaudio"
        var openCode = send("open \"\(path)\" type \(mediaType) alias thunder_bgm")
        // Keep the original PCM track as a local fallback if the Windows MCI
        // installation does not expose its MPEG decoder.
        if openCode != 0, extensionName == "mp3", let fallback = audioFilePath("thunder_swift_bgm.wav") {
            openCode = send("open \"\(fallback)\" type waveaudio alias thunder_bgm")
        }
        guard openCode == 0 else {
            if attempt < 3 {
                commandQueue.asyncAfter(deadline: .now() + .milliseconds(250)) { [weak self] in
                    guard let self else { return }
                    self.openAndPlayMusic(path: path, volume: volume, attempt: attempt + 1)
                }
            } else {
                withState { musicIsPlaying = false }
            }
            return
        }
        openedAliases.insert("thunder_bgm")
        _ = send("setaudio thunder_bgm volume to \(volume * 10)")
        let playCode = send("play thunder_bgm repeat")
        if playCode != 0 {
            _ = send("close thunder_bgm")
            openedAliases.remove("thunder_bgm")
            if attempt < 3 {
                commandQueue.asyncAfter(deadline: .now() + .milliseconds(250)) { [weak self] in
                    guard let self else { return }
                    self.openAndPlayMusic(path: path, volume: volume, attempt: attempt + 1)
                }
            } else {
                withState { musicIsPlaying = false }
            }
        }
    }

    func playSFX(_ name: String) {
        let normalizedName = name.hasPrefix("sfx_") ? name : "sfx_\(name)"
        let now = Date().timeIntervalSinceReferenceDate
        // Hit effects can be emitted once per projectile, so throttle them a
        // little more aggressively than UI/Boss cues.
        let cooldown = normalizedName == "sfx_hit" ? 0.075 : (normalizedName == "sfx_shoot" ? 0.055 : 0.045)
        let request: (file: String, alias: String, volume: Int)? = withState {
            guard sfxVolume > 0 else { return nil }
            if let previous = lastSFXTime[normalizedName], now - previous < cooldown { return nil }
            lastSFXTime[normalizedName] = now
            let file: String
            if let cached = sfxPaths[normalizedName] {
                guard let cached else { return nil }
                file = cached
            } else {
                guard let resolved = audioFilePath("\(normalizedName).wav") else {
                    sfxPaths[normalizedName] = nil
                    return nil
                }
                sfxPaths[normalizedName] = resolved
                file = resolved
            }
            let alias = sfxAliases[normalizedName] ?? normalizedName.replacingOccurrences(of: "-", with: "_")
            sfxAliases[normalizedName] = alias
            return (file, alias, sfxVolume)
        }
        guard let request else { return }
        commandQueue.async { [self] in
            playSFXOnQueue(file: request.file, alias: request.alias, volume: request.volume)
        }
    }

    private func playSFXOnQueue(file: String, alias: String, volume: Int) {
        func openAlias() -> Bool {
            let openCode = send("open \"\(file)\" type waveaudio alias \(alias)")
            guard openCode == 0 else { return false }
            openedAliases.insert(alias)
            _ = send("setaudio \(alias) volume to \(volume * 10)")
            return true
        }
        if !openedAliases.contains(alias), !openAlias() { return }
        if send("play \(alias) from 0") != 0 {
            // MCI can retain a stale alias after a device/decoder hiccup.
            // Reopen it once so later effects are not muted for the session.
            _ = send("close \(alias)")
            openedAliases.remove(alias)
            if openAlias() { _ = send("play \(alias) from 0") }
        }
    }

    func stopMusic() {
        let shouldStop = withState { () -> Bool in
            guard musicIsPlaying else { return false }
            musicIsPlaying = false
            return true
        }
        guard shouldStop else { return }
        commandQueue.async { [self] in
            // Passing nil stops the asynchronous PlaySound stream regardless
            // of which output device is currently selected.
            _ = playSoundW(nil, nil, 0)
            _ = send("stop thunder_bgm")
            _ = send("close thunder_bgm")
            openedAliases.remove("thunder_bgm")
            if let musicBuffer {
                musicBuffer.deallocate()
                self.musicBuffer = nil
                self.musicBufferLength = 0
            }
        }
    }
}

func rgb(_ r: UInt32, _ g: UInt32, _ b: UInt32) -> COLORREF {
    COLORREF(r | (g << 8) | (b << 16))
}

func rarityColor(_ rarity: UpgradeRarity) -> COLORREF {
    switch rarity {
    case .common: return rgb(198, 219, 239)
    case .rare: return rgb(93, 207, 255)
    case .epic: return rgb(193, 133, 255)
    case .legendary: return rgb(255, 210, 104)
    }
}

func equipmentRarityColor(_ rarity: Int) -> COLORREF {
    switch rarity {
    case 0: return rgb(187, 199, 219)
    case 1: return rgb(97, 209, 255)
    case 2: return rgb(204, 143, 255)
    case 3: return rgb(255, 211, 105)
    default: return rgb(255, 110, 136)
    }
}

func wide(_ text: String) -> [WCHAR] { Array(text.utf16) + [0] }

nonisolated(unsafe) private var injectedKeyboardState: Set<Int32>?

func setInjectedKeyboardState(_ keys: Set<Int32>?) {
    injectedKeyboardState = keys
}

func keyDown(_ key: Int32) -> Bool {
    injectedKeyboardState?.contains(key) ?? false
}

/// SDL3 is the sole application entry point.
@main
struct SwiftSurvivorApp {
    static func main() {
        if CommandLine.arguments.contains("--boss-smoke") {
            let passed = Game.shared.runBossSimulationSmoke(width: 1280, height: 720)
            let metrics = String(format: "peakEnemyBullets=%d avgSimulationFrame=%.4fms",
                                 Game.shared.bossSmokePeakBullets, Game.shared.bossSmokeAverageFrameMilliseconds)
            print((passed ? "BOSS_SMOKE_OK " : "BOSS_SMOKE_FAILED ") + metrics)
            if !passed { ExitProcess(1) }
            return
        }
        if CommandLine.arguments.contains("--sdl-smoke") { SDLSmoke.run(); return }
        if CommandLine.arguments.contains("--sdl-game") { SDLGameplaySlice.run(); return }
        if CommandLine.arguments.contains("--sdl-audio-smoke") { SDLAudioSmoke.run(); return }
        SDLFullGame.run()
    }
}
