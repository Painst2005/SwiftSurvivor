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

    var label: String {
        switch self {
        case .campaign: return "CAMPAIGN"
        case .endless: return "ENDLESS"
        }
    }

    func label(for language: GameLanguage) -> String {
        guard language == .chinese else { return label }
        switch self {
        case .campaign: return "章节模式"
        case .endless: return "无尽模式"
        }
    }

    func description(for language: GameLanguage) -> String {
        guard language == .chinese else {
            switch self {
            case .campaign: return "Clear a mission and unlock the next sector"
            case .endless: return "No time limit • chase your highest score"
            }
        }
        switch self {
        case .campaign: return "完成关卡并解锁下一个区域"
        case .endless: return "逐波迎战强敌与首领 • 挑战最高纪录"
        }
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
    let frontWaveCount: Int
    let difficulty: Double
    let rewardMultiplier: Double

    /// 关卡战力门槛（规格第 7.4 节，数值外置在 power_gates.json）。
    var powerGate: Int { EquipmentCatalog.shared.powerGate(mission: id) }

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
                          frontWaveCount: 4, difficulty: 0.86, rewardMultiplier: 1.0),
        MissionDefinition(id: 2, title: "VOID RIFT", chineseTitle: "虚空裂隙",
                          description: "Enemy formations emerge from a broken gate",
                          chineseDescription: "敌方编队从破碎的空间门涌出",
                          frontWaveCount: 4, difficulty: 1.08, rewardMultiplier: 1.35),
        MissionDefinition(id: 3, title: "STAR FORGE", chineseTitle: "星铸核心",
                          description: "Hold the forge while its reactor overloads",
                          chineseDescription: "守住星铸核心，直到反应堆完成过载",
                          frontWaveCount: 5, difficulty: 1.32, rewardMultiplier: 1.75),
        MissionDefinition(id: 4, title: "THUNDER CITADEL", chineseTitle: "雷霆堡垒",
                          description: "Break through the fortress command fleet",
                          chineseDescription: "突破堡垒舰队，摧毁敌方指挥中枢",
                          frontWaveCount: 5, difficulty: 1.58, rewardMultiplier: 2.2),
        MissionDefinition(id: 5, title: "FROSTLINE", chineseTitle: "寒霜防线",
                          description: "Escort the last convoy through a frozen storm",
                          chineseDescription: "护送最后的运输队穿越寒霜风暴",
                          frontWaveCount: 6, difficulty: 1.82, rewardMultiplier: 2.7),
        MissionDefinition(id: 6, title: "ECLIPSE GATE", chineseTitle: "日蚀之门",
                          description: "Close the gate before the eclipse reaches orbit",
                          chineseDescription: "在日蚀抵达轨道前关闭虚空之门",
                          frontWaveCount: 6, difficulty: 2.08, rewardMultiplier: 3.2),
        MissionDefinition(id: 7, title: "STARFALL", chineseTitle: "星陨禁区",
                          description: "Survive the meteor field and break the siege",
                          chineseDescription: "穿越陨石场，突破敌军围攻",
                          frontWaveCount: 7, difficulty: 2.38, rewardMultiplier: 3.8),
        MissionDefinition(id: 8, title: "ORIGIN CORE", chineseTitle: "起源核心",
                          description: "Enter the origin core and end the invasion",
                          chineseDescription: "进入起源核心，终结这场入侵",
                          frontWaveCount: 7, difficulty: 2.72, rewardMultiplier: 4.5)
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

    /// 配置口径 id：战神配方 bossTypeDefeated 条件用（如 "rift"）。
    var configID: String {
        switch self {
        case .dreadnought: return "dreadnought"
        case .riftBehemoth: return "rift"
        case .frostWarden: return "frost"
        case .originArchitect: return "origin"
        }
    }

    /// 由配置 id 反查 Boss 类型。
    static func fromConfigID(_ id: String) -> BossType? {
        allCases.first { $0.configID == id }
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
    /// 本局 Boss 稀有掉落（同名装备）：存系列 ID + 阶，显示名按语言实时解析。
    var runRareDropSeriesId = ""
    var runRareDropStage = 0
    var hangarMessageTitle = ""
    var hangarMessageDetail = ""
    var hangarMessageTimer = 0.0
    var hangarTab = 0
    var selectedEquipmentSlot = 0
    /// 装备 Tab 换装子视图：非 nil 时中栏显示该槽位的仓库选择列表。
    var hangarVaultSlot: EquipmentSlot? = nil
    var selectedVaultInventoryIndex: Int? = nil
    var vaultPage = 0
    /// 仓库过滤始终跟随换装子视图的槽位，不再单独循环切换。
    var vaultFilterSlot: EquipmentSlot? = nil
    /// 机体列表滚动：显示值由弹簧动画插值，目标值由输入（滚轮/拖拽/轨道）直接设置。
    /// 两者分离后，输入立即生效、画面平滑追赶，且动画只作用在显示值上。
    var shipListScroll = 0.0
    private var shipListScrollTarget = 0.0
    private var shipScrollVelocity = 0.0
    private var shipScrollDragging = false
    private var shipScrollGrabOffset = 0.0
    /// 滚轮增量累加器：高分辨率滚轮/触控板的单次增量常小于 1 格，需累积到整格再滚动。
    private var shipWheelAccumulator = 0.0
    var archiveTab = 0
    var codexCategory = CodexCategory.weapons
    var codexPage = 0
    var language: GameLanguage {
        GameLanguage(rawValue: profile.language) ?? .english
    }
    /// 换装列表固定顺序：战力降序，同级再比阶与等级，保证次序稳定可预期。
    var visibleVaultIndices: [Int] {
        profile.inventory.indices
            .filter { index in
                guard let filter = vaultFilterSlot else { return true }
                return profile.inventory[index].slot == filter
            }
            .sorted { lhs, rhs in
                let left = profile.inventory[lhs]
                let right = profile.inventory[rhs]
                if left.unitPower != right.unitPower { return left.unitPower > right.unitPower }
                if left.stage != right.stage { return left.stage > right.stage }
                if left.level != right.level { return left.level > right.level }
                return left.uid < right.uid
            }
    }
    var vaultPageCount: Int {
        max(1, (visibleVaultIndices.count + 3) / 4)
    }
    var mousePosition = Vec2(x: 500, y: 630)
    var mousePrimaryDown = false
    /// 本帧累计的鼠标滚轮刻度（向上滚为正），由 SDL 层每帧写入。
    var mouseWheelDelta = 0.0
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
    /// 魔龙之鳞回血技能的计时器。
    var armorRegenTimer = 0.0
    var waveTimer = 1.2
    var waveIndex = 0
    var endlessWaveNumber = 1
    var endlessWavePhase: EndlessWavePhase = .combat
    var endlessWaveTimeRemaining = 36.0
    var survivalTime = 0.0
    var stage = 1
    var boss: Boss?
    var stageClearTimer = 0.0
    var stageBannerTimer = 0.0
    var stageBannerTitle = ""
    var stageBannerDetail = ""
    var bossDefeats = 0
    var enemyBulletClearPending = false
    var weaponLevel = 1
    /// 出战主武器名称（弹道签名所属装备系列，HUD 展示）。
    var activeWeaponName = ""
    /// 出战战机的弹道签名（规格：弹道由出战装备决定，废除战斗中切武器）。
    var activeWeaponProfile: WeaponProfile?
    /// 出战副武器的弹道签名。
    var activeSubWeaponProfile: WeaponProfile?
    /// 出战僚机的弹道签名。
    var activeWingProfile: WeaponProfile?
    /// 出战装甲的生存技能。
    var activeArmorSkill: ArmorSkill?
    /// 关卡战力门槛伤害折算（1.0 = 达标无衰减）。
    var activePowerGateScale = 1.0
    /// 出战战神的同步率乘数（无战神 = 1.0）。
    var activeWarriorSynergy = 1.0
    /// 副武器/僚机战神的同步率乘数（各自槽位独立结算）。
    var warriorSubSynergy = 1.0
    var warriorWingSynergy = 1.0
    /// 部署中的装甲战神（素材面板技能生效）。
    var activeWarriorArmor: WarriorState? = nil
    /// 副武器/僚机当前生效等级（战神部署时取素材面板）。
    var activeSubLevel = 1
    var activeWingLevel = 1
    /// 机库升级 Tab 当前选中的经验素材。
    var selectedExpMaterial = "exp_wreckage"
    /// 装备 uid 单调序号（配合时间戳保证唯一）。
    private var equipmentUIDCounter = 0
    /// 战神 Tab 当前选中的配方（nil = 未选中）。
    var selectedWarriorRecipe: String? = nil
    /// 战神 Tab 当前选中的已激活战神（profile.warriors 下标，nil = 未选中）。
    var selectedWarriorIndex: Int? = nil
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
        }
    }

    var activeSpawnMultiplier: Double {
        switch gameMode {
        case .campaign: return 1.0 + Double(activeMission.id - 1) * 0.08
        case .endless: return 1.0
        }
    }

    var activeEnemyDamageMultiplier: Double {
        switch gameMode {
        case .campaign: return 0.92 + activeMission.difficulty * 0.18
        case .endless: return endlessEnemyDamageMultiplier
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
        }
    }

    var activeRewardMultiplier: Double {
        switch gameMode {
        case .campaign: return activeMission.rewardMultiplier
        case .endless: return 1.0
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
        switch activeWeaponProfile?.archetype {
        case .missile: base = max(fireCooldown * 2.15, 0.32)
        case .emp: base = max(fireCooldown * 0.72, 0.065)
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
        // 战神部署后，对应槽位的面板由战神素材合成（规格第 8 节：占用不消耗、出力 = 素材面板 × 出力倍率 × 同步率）。
        let warriorFighter = deployedWarrior(for: .fighter)
        let warriorSub = deployedWarrior(for: .subweapon)
        let warriorArmor = deployedWarrior(for: .armor)
        let warriorWing = deployedWarrior(for: .wingman)
        let fighterItem = warriorFighter.flatMap { warriorMaterialPanel($0) } ?? profile.equipment.first { $0.slot == .fighter }
        let subItem = warriorSub.flatMap { warriorMaterialPanel($0) } ?? profile.equipment.first { $0.slot == .subweapon }
        let armorItem = warriorArmor.flatMap { warriorMaterialPanel($0) } ?? profile.equipment.first { $0.slot == .armor }
        let wingItem = warriorWing.flatMap { warriorMaterialPanel($0) } ?? profile.equipment.first { $0.slot == .wingman }
        let primaryLevel = fighterItem?.level ?? 1
        let secondaryLevel = subItem?.level ?? 1
        let armorLevel = armorItem?.level ?? 1
        let droneLevel = wingItem?.level ?? 1
        // 弹道签名归装备系列：出战战机/副武器/僚机各带唯一 WeaponProfile。
        activeWeaponProfile = fighterItem?.series?.weaponProfile
            ?? EquipmentCatalog.shared.series(id: "fighter_assault")?.weaponProfile
        activeSubWeaponProfile = subItem?.series?.weaponProfile
        activeWingProfile = wingItem?.series?.weaponProfile
        activeArmorSkill = armorItem?.series?.skill
        // 出战战神：实际输出 = 素材面板 × baseOutputScale × 同步率（规格第 8.3 节）。
        if let warrior = warriorFighter {
            activeWarriorSynergy = EquipmentCatalog.shared.synergyConfig.baseOutputScale * warrior.synergyRate
        } else {
            activeWarriorSynergy = 1.0
        }
        // 副武器/僚机战神同样按 出力倍率 × 同步率 放大（各自槽位独立结算）。
        warriorSubSynergy = warriorSub.map { EquipmentCatalog.shared.synergyConfig.baseOutputScale * $0.synergyRate } ?? 1.0
        warriorWingSynergy = warriorWing.map { EquipmentCatalog.shared.synergyConfig.baseOutputScale * $0.synergyRate } ?? 1.0
        activeSubLevel = subItem?.level ?? 1
        activeWingLevel = wingItem?.level ?? 1
        // 装甲战神：素材面板的生存技能直接生效（增攻/减伤/免秒/回血/加分）。
        activeWarriorArmor = warriorArmor
        // 战力门槛伤害折算：达标无衰减，不足按比例线性衰减（规格第 7.4 节）。
        activePowerGateScale = powerGateScale()
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
        maxHealth = (120 + Double(max(0, armorLevel - 1)) * 4) * shipHealthMultiplier
        health = maxHealth
        moveSpeed = 330 * shipSpeedMultiplier
        // 主武器射速与伤害由出战战机的弹道签名参数化。
        fireCooldown = 0.24 / max(0.5, min(2.0, activeWeaponProfile?.fireRateScale ?? 1.0))
        let weaponDamageScale = activeWeaponProfile?.damageScale ?? 1.0
        // 装甲技能：黄金之铠=增攻 8%；金刚护盾=减伤；神圣之力=免秒（双层护盾）。
        let armorDamageBonus = activeArmorSkill == .damageBonus ? 1.08 : 1.0
        damage = (18 + Double(max(0, primaryLevel - 1)) * 1.5 + Double(max(0, droneLevel - 1)) * 0.6)
            * shipDamageMultiplier * weaponDamageScale * armorDamageBonus * activePowerGateScale * activeWarriorSynergy * activePlayerDamageMultiplier
        // 装甲技能：金刚护盾=减伤，神圣之力=免秒（双层护盾），其余见 power-up 结算。
        armorDamageReduction = min(0.28, 0.08 + Double(max(0, armorLevel - 1)) * 0.012)
        if activeArmorSkill == .damageReduction { armorDamageReduction = min(0.36, armorDamageReduction + 0.08) }
        // Armor and pickup shields share one non-stackable defensive layer.
        armorShieldCharges = activeArmorSkill == .surviveLethal ? 2 : 1
        fireTimer = 0.10
        auxiliaryFireTimer = 0.65
        let subWeaponRate = max(0.5, min(2.0, activeSubWeaponProfile?.fireRateScale ?? 1.0))
        secondaryFireTimer = max(1.6, (4.6 - Double(secondaryLevel) * 0.12) / subWeaponRate)
        waveTimer = 1.20
        waveIndex = 0
        endlessWaveNumber = 1
        endlessWavePhase = .combat
        endlessWaveTimeRemaining = 36.0
        survivalTime = 0
        stage = 1
        boss = nil
        stageClearTimer = 0
        stageBannerTimer = 0
        stageBannerTitle = ""
        stageBannerDetail = ""
        bossDefeats = 0
        enemyBulletClearPending = false
        // 武器形态由出战装备的阶决定（废除战斗中 Q 切武器）。
        weaponLevel = min(9, 1 + primaryLevel / 5 + (fighterItem?.stage ?? 0) / 2)
        activeWeaponName = fighterItem.map { equipmentDisplayName($0) } ?? ""
        projectileDamageMultiplier = 1.0
        projectilePenetration = activeWeaponProfile?.pierce ?? 0
        projectileCountBonus = 0
        laserWidthLevel = min(4, (fighterItem?.stage ?? 0) / 2)
        thunderGainMultiplier = 1.0
        grazeRadiusBonus = 0.0
        // 装甲技能：聚能之光 = 得分 +15%（规格第 2 节）。
        comboScoreMultiplier = activeArmorSkill == .scoreBonus ? 1.15 : 1.0
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
        runRareDropSeriesId = ""
        runRareDropStage = 0
        experience = 0
        experienceGoal = 10
        enemies.removeAll(keepingCapacity: true)
        recycleAllBullets()
        powerUps.removeAll(keepingCapacity: true)
        particles.removeAll(keepingCapacity: true)
        damageNumbers.removeAll(keepingCapacity: true)
        upgradeOptions.removeAll()
        selectedBuildCoreKinds.removeAll(keepingCapacity: true)
        armorRegenTimer = 0
        // 保底兜底：装备练到 75 级时任务线赠送一整套紫色材料（每槽位一次）。
        claimQuarkGiftIfEligible()
        if stars.isEmpty { initializeStars(width: width, height: height) }
    }

    func update(delta rawDelta: Double, width: Double, height: Double) {
        let realDelta = min(max(rawDelta, 0), 0.05)
        // 滚轮增量每次 update 只消费一次：既不会被固定步长循环重复应用，
        // 也不会在非机库界面堆积成延迟生效的队列。
        let wheelDelta = mouseWheelDelta
        mouseWheelDelta = 0
        uiAnimationTime += realDelta
        if stars.isEmpty { initializeStars(width: width, height: height) }
        if phase == .menu || phase == .saveSlots || phase == .missionSelect || phase == .controls || phase == .hangar || phase == .settings || phase == .archive {
            updateStars(delta: realDelta, height: height)
            updateParticles(delta: realDelta)
            hangarMessageTimer = max(0, hangarMessageTimer - realDelta)
            if phase == .hangar { updateShipListScroll(delta: realDelta, wheelDelta: wheelDelta, width: width, height: height) }
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
        // 魔龙之鳞（回血）：每 2 秒恢复 2% 最大生命。
        if activeArmorSkill == .regen, health > 0, health < maxHealth {
            armorRegenTimer -= delta
            if armorRegenTimer <= 0 {
                armorRegenTimer = 2.0
                health = min(maxHealth, health + maxHealth * 0.02)
            }
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

        let normalWaveSpawningAllowed = gameMode == .campaign
            ? waveIndex < activeMission.frontWaveCount
            : endlessWavePhase == .combat
        if stageClearTimer <= 0, boss == nil, normalWaveSpawningAllowed {
            waveTimer -= delta
            if waveTimer <= 0 {
                spawnWave(field: field)
                waveTimer = nextWaveDelay()
            }
        }

        let campaignFrontCleared = gameMode == .campaign
            && waveIndex >= activeMission.frontWaveCount
            && enemies.isEmpty
        if stageClearTimer <= 0, campaignFrontCleared, boss == nil, !missionBossSpawned {
            stageBannerTimer = 2.2
            stageBannerTitle = uiText("BOSS INBOUND", "首领来袭")
            stageBannerDetail = uiText("FRONT LINE CLEARED  •  FINAL TARGET APPROACHING",
                                       "前期战斗完成  •  最终目标正在接近")
            spawnBoss(field: field)
        }

        fireTimer -= delta
        if fireTimer <= 0 {
            fireWeapon()
            fireTimer = effectiveFireCooldown
        }
        auxiliaryFireTimer -= delta
        if auxiliaryFireTimer <= 0 {
            fireAuxiliaryWeapon()
            auxiliaryFireTimer = max(0.28, 0.82 - Double(activeWingLevel) * 0.025)
        }
        secondaryFireTimer -= delta
        if secondaryFireTimer <= 0 {
            fireSecondaryWeapon()
            secondaryFireTimer = max(2.8, 6.4 - Double(activeSubLevel) * 0.22)
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
            recordRunScore()
            claimQuarkGiftIfEligible()
            persistProfile()
        }
    }

    /// 记录本局最高分：总榜 + 无尽单独记账（战神配方 endlessBestScore 条件）。
    private func recordRunScore() {
        profile.bestCombo = max(profile.bestCombo, comboBest)
        profile.bestScore = max(profile.bestScore, score)
        if gameMode == .endless {
            profile.endlessBestScore = max(profile.endlessBestScore, score)
        }
        if score > highScore {
            highScore = score
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
        grantWaveMaterials()
    }

    /// 规格第 6 节 + material_drops.json：闯关普通波次掉绿色量子系（必掉）；
    /// 无尽模式每 equipmentCratePerWaves 波投放一个装备宝箱（随机系列）。
    private func grantWaveMaterials() {
        if gameMode == .campaign {
            guard let drops = EquipmentCatalog.shared.missionDrops(activeMission.id) else { return }
            for materialID in drops.normalWaves { addMaterial(materialID, amount: 1) }
        } else {
            guard waveIndex % EquipmentCatalog.shared.drops.endless.equipmentCratePerWaves == 0,
                  profile.inventory.count < 96 else { return }
            let series = EquipmentCatalog.shared.seriesList.randomElement(using: &rng)
            guard let series else { return }
            profile.inventory.append(EquipmentState(uid: nextEquipmentUID(),
                                                    seriesId: series.id, stage: 0, level: 1,
                                                    exp: 0, locked: false, equipped: false))
            notifyPickup(title: uiText("EQUIPMENT CRATE", "装备宝箱"),
                         detail: uiText("\(series.displayName(stage: 0, suffix: "")) secured", "获得了\(series.displayName(stage: 0, suffix: ""))"),
                         tint: rgb(126, 220, 255))
        }
    }

    /// 装备 uid 生成：时间戳 + 单调序号，保证跨会话唯一（迁移与战神占用都以 uid 为准）。
    func nextEquipmentUID() -> String {
        equipmentUIDCounter += 1
        return "eq_\(Int(Date().timeIntervalSince1970 * 1000))_\(equipmentUIDCounter)"
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
        newBoss.laserCooldown = 5.0
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

    /// 每种弹道原型的子弹参数（规格第 12.4/12.5 节：archetype 路由 + scale 参数化）。
    private struct ArchetypeBullet {
        var speed: Double
        var radius: Double
        var damageMultiplier: Double
        var life: Double
        var tint: COLORREF
        var style: Int
        var pierceBonus: Int
    }

    /// 默认弹道签名（找不到出战装备时兜底，等价于突击系单发机炮）。
    private var defaultWeaponProfile: WeaponProfile {
        WeaponProfile(archetype: .cannon, damageScale: 1.0, fireRateScale: 1.0,
                      projectileCount: 1, spread: 0.0, speedScale: 1.0,
                      pierce: 0, homingTurn: 0, radiusScale: 1.0)
    }

    private func archetypeBullet(_ weapon: WeaponProfile, laserBoost: Double) -> ArchetypeBullet {
        switch weapon.archetype {
        case .cannon:
            return ArchetypeBullet(speed: 720, radius: 4.5, damageMultiplier: 1.0,
                                   life: 2.0, tint: rgb(155, 239, 255),
                                   style: WeaponType.cannon.rawValue, pierceBonus: 0)
        case .laser:
            return ArchetypeBullet(speed: 900, radius: 5.5 + Double(laserWidthLevel) * 0.6,
                                   damageMultiplier: 1.18 * laserBoost,
                                   life: 1.55, tint: frostRayActive ? rgb(174, 239, 255) : rgb(112, 224, 255),
                                   style: WeaponType.laser.rawValue, pierceBonus: 3)
        case .scatter:
            return ArchetypeBullet(speed: 650, radius: 5.0, damageMultiplier: 0.68,
                                   life: 1.35, tint: rgb(255, 202, 119),
                                   style: WeaponType.scatter.rawValue, pierceBonus: 0)
        case .missile:
            return ArchetypeBullet(speed: 430, radius: 7.0, damageMultiplier: 1.72,
                                   life: 3.4, tint: rgb(255, 133, 92),
                                   style: WeaponType.missile.rawValue, pierceBonus: 0)
        case .emp:
            return ArchetypeBullet(speed: 560, radius: 7.0, damageMultiplier: 0.82,
                                   life: 2.2, tint: rgb(191, 133, 255),
                                   style: WeaponType.electromagnetic.rawValue, pierceBonus: 1)
        }
    }

    /// 主武器：由出战战机的弹道签名驱动（废除战斗中切武器）。
    private func fireWeapon() {
        AudioManager.shared.playSFX("sfx_shoot")
        let weapon = activeWeaponProfile ?? defaultWeaponProfile
        fireProfile(weapon, level: weaponLevel, origin: player + Vec2(x: 0, y: -22))
    }

    /// 副武器：与主武器弹道互补，出力占比 0.72。
    private func fireSecondaryWeapon() {
        guard let weapon = activeSubWeaponProfile else { return }
        fireProfile(weapon, level: activeSubLevel, origin: player + Vec2(x: 0, y: -20),
                    damageFraction: 0.72, synergyScale: warriorSubSynergy)
    }

    /// 僚机：广域支援 lanes 几何 + 各自系列的弹道原型参数。
    private func fireAuxiliaryWeapon() {
        guard let weapon = activeWingProfile else { return }
        let level = activeWingLevel
        let laserBoost = weapon.archetype == .laser ? (frostRayActive ? 2.0 : 1.6) : 1.0
        let bullet = archetypeBullet(weapon, laserBoost: laserBoost)
        let lanes = min(4, 1 + level / 4 + (shipType == .carrier ? 1 : 0))
        for index in 0..<lanes {
            let side = index % 2 == 0 ? -1.0 : 1.0
            let lane = Double(index / 2)
            let origin = player + Vec2(x: side * (28 + lane * 13), y: -8)
            let angle = side * (0.10 + lane * 0.035)
            appendPlayerBullet(origin: origin,
                               angle: angle,
                               speed: bullet.speed * weapon.speedScale,
                               radius: bullet.radius * weapon.radiusScale,
                               damage: damage * (shipType == .carrier ? 0.44 : 0.32) * bullet.damageMultiplier * warriorWingSynergy,
                               life: bullet.life,
                               tint: bullet.tint,
                               pierce: max(0, projectilePenetration + bullet.pierceBonus + weapon.pierce - 1),
                               style: bullet.style, homingTurn: weapon.homingTurn)
        }
    }

    /// 弹道签名统一发射器：archetype 决定弹形， WeaponProfile 决定数量/扇面/速度/穿透。
    private func fireProfile(_ weapon: WeaponProfile, level: Int, origin: Vec2,
                             damageFraction: Double = 1.0, synergyScale: Double = 1.0) {
        let laserBoost = weapon.archetype == .laser ? (frostRayActive ? 2.0 : 1.6) : 1.0
        let bullet = archetypeBullet(weapon, laserBoost: laserBoost)
        let count = max(1, weapon.projectileCount)
        let half = max(0.0, weapon.spread)
        let shotDamage = damage * damageFraction * projectileDamageMultiplier * bullet.damageMultiplier * synergyScale
        let pierce = projectilePenetration + bullet.pierceBonus + weapon.pierce

        switch weapon.archetype {
        case .cannon:
            var pellets = count + (level >= 4 ? 1 : 0) + (level >= 7 ? 2 : 0) + projectileCountBonus
                + (arrayOverdriveActive ? 1 : 0)
            pellets = min(9, pellets)
            for index in 0..<pellets {
                let t = pellets == 1 ? 0.5 : Double(index) / Double(pellets - 1)
                appendPlayerBullet(origin: origin, angle: -half + t * half * 2,
                                   speed: bullet.speed * weapon.speedScale,
                                   radius: bullet.radius * weapon.radiusScale,
                                   damage: shotDamage, life: bullet.life, tint: bullet.tint,
                                   pierce: pierce, homingTurn: weapon.homingTurn)
            }
        case .laser:
            let beams = min(5, count + (level >= 6 ? 1 : 0))
            for index in 0..<beams {
                let t = beams == 1 ? 0.5 : Double(index) / Double(beams - 1)
                appendPlayerBullet(origin: origin, angle: -half + t * half * 2,
                                   speed: bullet.speed * weapon.speedScale,
                                   radius: bullet.radius * weapon.radiusScale,
                                   damage: shotDamage, life: bullet.life, tint: bullet.tint,
                                   pierce: max(2, pierce), style: bullet.style, homingTurn: weapon.homingTurn)
            }
        case .scatter:
            let pellets = min(13, count + level - 1 + projectileCountBonus + (arrayOverdriveActive ? 1 : 0))
            for index in 0..<pellets {
                let t = pellets == 1 ? 0.5 : Double(index) / Double(pellets - 1)
                appendPlayerBullet(origin: origin, angle: -half + t * half * 2,
                                   speed: bullet.speed * weapon.speedScale,
                                   radius: bullet.radius * weapon.radiusScale,
                                   damage: shotDamage, life: bullet.life, tint: bullet.tint,
                                   pierce: pierce, style: bullet.style, homingTurn: weapon.homingTurn)
            }
        case .missile:
            var missiles = count + (level >= 4 ? 1 : 0) + (level >= 7 ? 2 : 0) + projectileCountBonus
            missiles = min(6, missiles)
            for index in 0..<missiles {
                let t = missiles == 1 ? 0.5 : Double(index) / Double(missiles - 1)
                appendPlayerBullet(origin: origin, angle: -half + t * half * 2,
                                   speed: bullet.speed * weapon.speedScale,
                                   radius: bullet.radius * weapon.radiusScale,
                                   damage: shotDamage, life: bullet.life, tint: bullet.tint,
                                   pierce: pierce, style: bullet.style, homingTurn: weapon.homingTurn)
            }
        case .emp:
            let orbs = min(6, count + (level >= 3 ? 1 : 0) + (level >= 6 ? 1 : 0) + (level >= 7 ? 1 : 0) + projectileCountBonus)
            for index in 0..<orbs {
                let t = orbs == 1 ? 0.5 : Double(index) / Double(orbs - 1)
                appendPlayerBullet(origin: origin, angle: -half + t * half * 2,
                                   speed: bullet.speed * weapon.speedScale,
                                   radius: bullet.radius * weapon.radiusScale,
                                   damage: shotDamage, life: bullet.life, tint: bullet.tint,
                                   pierce: max(1, pierce), style: bullet.style, homingTurn: weapon.homingTurn)
            }
        }
    }

    private func appendPlayerBullet(origin: Vec2, angle: Double, speed: Double, radius: Double, damage: Double, life: Double, tint: COLORREF, pierce: Int, style: Int = WeaponType.cannon.rawValue, homingTurn: Double = 0) {
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
                              maxTurnRate: homingTurn > 0 ? homingTurn : (style == WeaponType.missile.rawValue ? 2.6 : 0),
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
                registerBossDefeat(at: currentBoss.position, kind: currentBoss.kind)
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
            advanceBossPosition(&currentBoss.position, toward: Vec2(x: field.centerX, y: 138),
                                delta: delta, response: 5, maximumSpeed: 340)
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
        let target: Vec2
        let maximumSpeed: Double
        switch boss.movement {
        case .positionLock:
            target = Vec2(x: field.centerX, y: 138)
            maximumSpeed = 440
        case .horizontalSweep:
            target = Vec2(x: field.centerX + sin(boss.age * 0.60) * horizontalLimit,
                          y: 142 + sin(boss.age * 0.74) * 12)
            maximumSpeed = 300
        case .aggressiveHover:
            target = Vec2(x: field.centerX + sin(boss.age * 0.98) * min(horizontalLimit * 1.15, field.width * 0.5 - 132),
                          y: 145 + sin(boss.age * 1.12) * 24)
            maximumSpeed = 440
        case .hover:
            target = Vec2(x: field.centerX + sin(boss.age * 0.44) * horizontalLimit * 0.75,
                          y: 136 + sin(boss.age * 0.58) * 10)
            maximumSpeed = 220
        }
        // Attack selection changes the target curve, never the actual position.
        // A bounded step keeps entrance, attack switches and phase changes continuous.
        advanceBossPosition(&boss.position, toward: target, delta: delta,
                            response: 8, maximumSpeed: maximumSpeed)
    }

    private func advanceBossPosition(_ position: inout Vec2, toward target: Vec2,
                                     delta: Double, response: Double, maximumSpeed: Double) {
        guard delta > 0 else { return }
        let desiredStep = (target - position) * min(1, delta * response)
        let stepLimit = maximumSpeed * delta
        position = position + (desiredStep.length > stepLimit
            ? desiredStep.normalized * stepLimit : desiredStep)
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
            emitBossParallelCrossfire(boss)
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

    private func emitBossParallelCrossfire(_ boss: Boss) {
        let emitter = BulletEmitter(pattern: .single, count: 1, speed: 292 + Double(boss.phase) * 14,
                                    damage: 11 * activeEnemyDamageMultiplier * ThunderCarrierBossDefinition.damageMultiplier,
                                    radius: 5.8, lifetime: 5.5, tint: rgb(255, 126, 174), bulletType: .normal,
                                    modifiers: [.constantVelocity, .lockDirection])
        if boss.leftTurretHealth > 0 {
            for laneOffset in [-12.0, 12.0] {
                emitPattern(emitter, from: boss.position + Vec2(x: -ThunderCarrierBossDefinition.turretOffsetX + laneOffset,
                                                                y: ThunderCarrierBossDefinition.turretOffsetY))
            }
        }
        if boss.rightTurretHealth > 0 {
            for laneOffset in [-12.0, 12.0] {
                emitPattern(emitter, from: boss.position + Vec2(x: ThunderCarrierBossDefinition.turretOffsetX + laneOffset,
                                                                y: ThunderCarrierBossDefinition.turretOffsetY))
            }
        }
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
        // A trajectory change may move the target abruptly, but the boss
        // itself must not cross a visible part of the arena in one frame.
        func advanceBoss() -> Bool {
            guard let previous = boss?.position else { return false }
            updateBoss(delta: 1.0 / 60.0, field: field)
            guard let current = boss?.position else { return false }
            let step = distance(previous, current)
            if step > 8.5 {
                print(String(format: "BOSS_MOTION_JUMP %.2fpx", step))
                return false
            }
            return true
        }
        for _ in 0..<120 { guard advanceBoss() else { return false } }
        guard boss?.lifecycle == .combat, boss?.phase == 1 else { return false }
        // Exercise the first combat frames before changing health. This is
        // where the old absolute hover curve jumped away from the entry path.
        for _ in 0..<30 { guard advanceBoss() else { return false } }

        guard var testBoss = boss else { return false }
        testBoss.health = testBoss.maxHealth * 0.69
        boss = testBoss
        for _ in 0..<80 { guard advanceBoss() else { return false } }
        guard boss?.phase == 2, boss?.lifecycle == .combat else { return false }

        testBoss = boss!
        testBoss.health = testBoss.maxHealth * 0.29
        boss = testBoss
        for _ in 0..<80 { guard advanceBoss() else { return false } }
        guard boss?.phase == 3, boss?.lifecycle == .combat else { return false }

        testBoss = boss!
        testBoss.attackPatternIndex = 0
        testBoss.attackStage = .recovery
        testBoss.attackTimer = 0
        testBoss.leftTurretHealth = 0
        testBoss.rightTurretHealth = 0
        boss = testBoss
        for _ in 0..<55 { guard advanceBoss() else { return false } }
        let enemyBulletCount = bullets.reduce(0) { $0 + ($1.playerOwned ? 0 : 1) }
        guard enemyBulletCount > 0, boss?.weakPointOpen == true else { return false }

        bossSmokePeakBullets = enemyBulletCount
        let simulationStart = Date().timeIntervalSinceReferenceDate
        let simulationFrames = 1_080
        for _ in 0..<simulationFrames {
            guard advanceBoss() else { return false }
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
        // 规格第 5/6 节：闯关掉落经验素材（敌机残骸/魔方），升级只吃经验。
        if isElite {
            addMaterial("exp_wreckage", amount: 2)
            addMaterial("exp_cube", amount: 1)
        } else if Int.random(in: 0..<100, using: &rng) < 22 {
            addMaterial("exp_wreckage", amount: 1)
        }
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
        recordRunScore()
        claimQuarkGiftIfEligible()
        stageBannerTitle = uiText("MISSION COMPLETE", "任务完成")
        stageBannerDetail = uiText("SECTOR SECURED  •  EXTRA REWARDS GRANTED",
                                   "区域已肃清  •  已发放额外奖励")
        persistProfile()
        phase = .gameOver
    }

    private func registerBossDefeat(at position: Vec2, kind: Int) {
        AudioManager.shared.playSFX("sfx_boss")
        bossDefeats += 1
        missionBossDefeated = true
        // 规格第 8.1 节：按 Boss 类型记录击败（战神配方 bossTypeDefeated 条件）。
        if let bossType = BossType(rawValue: kind), !profile.bossTypesDefeated.contains(bossType.configID) {
            profile.bossTypesDefeated.append(bossType.configID)
        }
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
        let guaranteedDrop = profile.bossDropPity >= EquipmentCatalog.shared.drops.sameNameDrop.pityBossDefeats
        let rareDrop = guaranteedDrop || Int.random(in: 0..<100, using: &rng) < 28
        var dropDetail = uiText("Boss materials secured", "已获得首领材料")
        // 规格第 6 节：Boss 关必掉本章蓝色材料（第 5 章起含夸克系）。
        let bossMaterials = gameMode == .campaign
            ? (EquipmentCatalog.shared.missionDrops(activeMission.id)?.boss ?? [])
            : []
        for materialID in bossMaterials { addMaterial(materialID, amount: 1) }
        // 规格第 8 节：无尽模式每 warriorMaterialPerBossWaves 个 Boss 波次掉战神进阶材料。
        if gameMode == .endless, endlessWaveNumber % EquipmentCatalog.shared.drops.endless.warriorMaterialPerBossWaves == 0 {
            for materialID in EquipmentCatalog.shared.synergyConfig.advanceMaterials { addMaterial(materialID, amount: 1) }
            dropDetail = uiText("WARRIOR CORE MATERIALS SECURED", "已获得战神核心材料")
        }
        if rareDrop {
            profile.bossDropPity = 0
            profile.cores += 2
            runCoresEarned += 2
            // 同名装备（进阶材料本体）：只从三个传奇系列掉；保底掉蓝四星，常规白/绿随机。
            let rareSeries = EquipmentCatalog.shared.drops.sameNameDrop.bossRareDropSeries
            if let seriesID = rareSeries.randomElement(using: &rng),
               let series = EquipmentCatalog.shared.series(id: seriesID) {
                let dropStage: Int = guaranteedDrop ? 2 : (Int.random(in: 0..<100, using: &rng) < 30 ? 1 : 0)
                let drop = EquipmentState(uid: nextEquipmentUID(), seriesId: series.id,
                                          stage: dropStage, level: EquipmentCatalog.shared.levelMin(stage: dropStage),
                                          exp: 0, locked: false, equipped: false)
                profile.inventory.append(drop)
                runRareDropSeriesId = series.id
                runRareDropStage = dropStage
                dropDetail = uiText("RARE MODULE CACHE  •  \(drop.displayNameEn) (Lv.\(drop.level)/\(drop.levelCap))",
                                    "获得稀有模块  •  \(drop.displayName) (Lv.\(drop.level)/\(drop.levelCap))")
                combatFeedback.play(.rareDrop,
                                    context: FeedbackContext(position: position, level: .heavy, tint: rgb(255, 211, 112)),
                                    game: self)
            }
        } else {
            profile.bossDropPity += 1
        }
        // 经验素材：Boss 必掉魔方（升级只吃经验）。
        addMaterial("exp_cube", amount: 2)
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
        notifyPickup(title: uiText("BOSS REWARD CACHE", "首领奖励"), detail: dropDetail, tint: rgb(255, 211, 112))
        checkForUpgradeReady()
        persistProfile()
        if gameMode == .campaign {
            completeMission()
        }
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
        hangarVaultSlot = nil
        selectedVaultInventoryIndex = nil
        vaultPage = 0
        vaultFilterSlot = nil
        resetShipScroll()
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

    // MARK: - 材料背包（进阶材料 / 经验素材 / 战神材料共用一本账）

    func materialCount(_ id: String) -> Int { profile.materials[id] ?? 0 }

    func addMaterial(_ id: String, amount: Int) {
        guard amount != 0 else { return }
        let next = max(0, materialCount(id) + amount)
        if next == 0 {
            profile.materials.removeValue(forKey: id)
        } else {
            profile.materials[id] = next
        }
    }

    /// 消耗材料；数量不足返回 false，不产生部分扣费。
    @discardableResult
    func spendMaterial(_ id: String, amount: Int) -> Bool {
        guard amount > 0, materialCount(id) >= amount else { return false }
        addMaterial(id, amount: -amount)
        return true
    }

    /// 经验素材单件经验值。
    func experienceValue(_ id: String) -> Int { EquipmentCatalog.shared.experience(id)?.exp ?? 0 }

    /// 切换升级 Tab 选中的经验素材（规格第 5 节：下方小格选素材）。
    func cycleExpMaterial() {
        let sources = EquipmentCatalog.shared.experienceSources
        guard !sources.isEmpty else { return }
        let current = sources.firstIndex { $0.id == selectedExpMaterial } ?? -1
        selectedExpMaterial = sources[(current + 1) % sources.count].id
    }

    /// 直接选中指定经验素材（机库经验素材格点击）。
    func selectExpMaterial(_ id: String) {
        guard EquipmentCatalog.shared.experience(id) != nil else { return }
        selectedExpMaterial = id
    }

    /// 素材展示名。经验素材（敌机残骸 / 魔方）单独成表，必须先查经验表：
    /// 进阶材料表查不到它们，否则会退化成把内部 ID 直接显示在界面上。
    func materialDisplayName(_ id: String) -> String {
        if let source = EquipmentCatalog.shared.experience(id) {
            return language == .chinese ? source.name : source.nameEn
        }
        return language == .chinese ? EquipmentCatalog.shared.materialName(id) : EquipmentCatalog.shared.materialNameEn(id)
    }

    // MARK: - 机库展示助手（名称 / 品质 / 阶标签全部由配置表派生）

    func equipmentDisplayName(_ item: EquipmentState) -> String {
        language == .chinese ? item.displayName : item.displayNameEn
    }

    /// 按系列 ID + 阶取当前语言的装备名（掉落提示等只有 ID 的场景使用）。
    func equipmentName(seriesId: String, stage: Int) -> String {
        language == .chinese
            ? EquipmentCatalog.shared.displayName(seriesId: seriesId, stage: stage)
            : EquipmentCatalog.shared.displayNameEn(seriesId: seriesId, stage: stage)
    }

    /// 阶 → 颜色品质名（规格第 4 节：白 / 绿 / 蓝 / 紫 四色）。
    func equipmentQualityName(stage: Int) -> String {
        let color = EquipmentCatalog.shared.stageInfo(stage)?.color ?? "white"
        switch color {
        case "green": return uiText("GREEN", "绿色")
        case "blue": return uiText("BLUE", "蓝色")
        case "purple": return uiText("PURPLE", "紫色")
        default: return uiText("WHITE", "白色")
        }
    }

    /// 阶 → 完整阶标签，如“蓝四星+2”。
    func equipmentStageLabel(_ stage: Int) -> String {
        guard let info = EquipmentCatalog.shared.stageInfo(stage) else { return "" }
        if language == .chinese {
            let numerals = ["零", "一", "二", "三", "四", "五", "六"]
            let color: String
            switch info.color {
            case "green": color = "绿"
            case "blue": color = "蓝"
            case "purple": color = "紫"
            default: color = "白"
            }
            return "\(color)\(numerals[min(numerals.count - 1, max(0, info.stars))])星\(info.suffix)"
        }
        return "\(info.color.uppercased()) \(info.stars)STAR\(info.suffix)"
    }

    /// 装备特性说明：装甲展示生存被动，武器槽展示弹道签名摘要。
    func equipmentBonusText(_ item: EquipmentState) -> String {
        guard let series = item.series else { return "" }
        if let skill = series.skill {
            switch skill {
            case .regen: return uiText("Regen: restores 2% max HP every 2s", "回血：每 2 秒恢复 2% 最大生命")
            case .scoreBonus: return uiText("Focus: +15% score gain", "聚能：得分 +15%")
            case .damageBonus: return uiText("Assault: +8% weapon damage", "增攻：武器伤害 +8%")
            case .surviveLethal: return uiText("Bless: survives one lethal hit", "免秒：每局抵挡一次致命伤害")
            case .damageReduction: return uiText("Guard: -8% damage taken", "减伤：所受伤害 -8%")
            }
        }
        guard let profile = series.weaponProfile else { return "" }
        let archetype: String
        switch profile.archetype {
        case .cannon: archetype = uiText("Cannon", "机炮")
        case .laser: archetype = uiText("Laser", "激光")
        case .scatter: archetype = uiText("Scatter", "散射")
        case .missile: archetype = uiText("Missile", "导弹")
        case .emp: archetype = uiText("EMP", "电磁")
        }
        return "\(archetype)  •  \(uiText("DMG", "伤害")) x\(String(format: "%.2f", profile.damageScale))  •  \(uiText("RATE", "射速")) x\(String(format: "%.2f", profile.fireRateScale))"
    }

    /// 进阶消耗摘要（机库进阶按钮旁展示）。
    func equipmentAdvanceCostText(_ item: EquipmentState) -> String {
        guard let cost = item.advanceCost() else { return uiText("MAX STAGE", "满阶") }
        var parts: [String] = []
        for materialID in cost.materials where cost.each > 0 {
            let owned = materialCount(materialID)
            let satisfied = owned >= cost.each
            let text = "\(materialDisplayName(materialID)) \(owned)/\(cost.each)"
            parts.append(satisfied ? text : "[\(text)]")
        }
        if cost.sameName > 0 {
            let owned = sameNameCandidateIndices(for: item).count
            let text = "\(uiText("DUPLICATES", "同名装备")) \(owned)/\(cost.sameName)"
            parts.append(owned >= cost.sameName ? text : "[\(text)]")
        }
        if cost.gold > 0 {
            let satisfied = profile.credits >= cost.gold
            let text = "\(uiText("CREDITS", "金币")) \(profile.credits)/\(cost.gold)"
            parts.append(satisfied ? text : "[\(text)]")
        }
        return parts.joined(separator: "  ")
    }

    /// 同名装备同色段名（进阶材料提示用）。
    private func colorSegmentName(_ stage: Int) -> String {
        switch stage {
        case 2...5: return uiText("BLUE", "蓝色")
        case 6...8: return uiText("PURPLE", "紫色")
        default: return uiText("SAME-SERIES", "同名")
        }
    }

    // MARK: - 升级（吃经验素材，规格第 5 节）

    /// 同名装备进阶候选（仓库下标）：同系列同色段、未锁定、未被战神占用，按等级升序。
    /// 蓝段（阶 2...5）喂蓝段，紫段（阶 6...9）喂紫段；等级不限（规格第 4 节）。
    func sameNameCandidateIndices(for item: EquipmentState) -> [Int] {
        let band: ClosedRange<Int>
        switch item.stage {
        case 2...5: band = 2...5
        case 6...8: band = 6...9
        default: band = 0...0
        }
        let occupied = Set(profile.warriors.flatMap { $0.materialUIDs })
        return profile.inventory.indices.filter { index in
            let candidate = profile.inventory[index]
            return candidate.seriesId == item.seriesId
                && band.contains(candidate.stage)
                && !candidate.locked
                && !occupied.contains(candidate.uid)
        }.sorted { profile.inventory[$0].level < profile.inventory[$1].level }
    }

    /// 经验结算：按 expToNext 曲线连续升级，满级后清空溢出经验。
    private func applyExperience(to slot: Int, amount: Int) {
        guard profile.equipment.indices.contains(slot), amount > 0 else { return }
        var item = profile.equipment[slot]
        var remaining = max(0, item.exp) + amount
        while !item.isMaxLevel {
            let need = EquipmentCatalog.shared.expToNext(level: item.level, stage: item.stage)
            if remaining < need { break }
            remaining -= need
            item.level += 1
        }
        item.exp = item.isMaxLevel ? 0 : remaining
        profile.equipment[slot] = item
    }

    /// 单次升级：消耗 1 件选中的经验素材。
    func upgradeEquipmentWithExp(slot: Int) {
        guard phase == .hangar, profile.equipment.indices.contains(slot) else { return }
        let item = profile.equipment[slot]
        guard !item.isMaxLevel else {
            showHangarMessage(uiText("LEVEL CAP REACHED", "已达当前阶满级"),
                              uiText("Advance to the next stage to raise the cap", "进阶到下一阶可提升等级上限"))
            return
        }
        let value = experienceValue(selectedExpMaterial)
        guard value > 0 else {
            showHangarMessage(uiText("INVALID MATERIAL", "无效素材"),
                              uiText("Pick an experience material below", "请在下方选择经验素材"))
            return
        }
        guard spendMaterial(selectedExpMaterial, amount: 1) else {
            showHangarMessage(uiText("INSUFFICIENT MATERIALS", "经验素材不足"),
                              uiText("Need 1x \(materialDisplayName(selectedExpMaterial))",
                                     "需要 1 个\(materialDisplayName(selectedExpMaterial))"))
            return
        }
        applyExperience(to: slot, amount: value)
        persistProfile()
        let upgraded = profile.equipment[slot]
        let nextNeed = EquipmentCatalog.shared.expToNext(level: upgraded.level, stage: upgraded.stage)
        showHangarMessage(uiText("LEVEL UP", "等级提升"),
                          uiText("\(equipmentDisplayName(upgraded))  •  Lv.\(upgraded.level)  •  EXP \(upgraded.exp)/\(nextNeed)",
                                 "\(equipmentDisplayName(upgraded))  •  等级 \(upgraded.level)  •  经验 \(upgraded.exp)/\(nextNeed)"))
        AudioManager.shared.playSFX("sfx_upgrade")
    }

    /// 一键填充：把背包内全部经验素材灌入选中装备（规格第 5 节）。
    func autoFillEquipmentExp(slot: Int) {
        guard phase == .hangar, profile.equipment.indices.contains(slot) else { return }
        let item = profile.equipment[slot]
        guard !item.isMaxLevel else {
            showHangarMessage(uiText("LEVEL CAP REACHED", "已达当前阶满级"),
                              uiText("Advance to the next stage to raise the cap", "进阶到下一阶可提升等级上限"))
            return
        }
        var total = 0
        for source in EquipmentCatalog.shared.experienceSources {
            let count = materialCount(source.id)
            guard count > 0 else { continue }
            total += count * source.exp
            addMaterial(source.id, amount: -count)
        }
        guard total > 0 else {
            showHangarMessage(uiText("NO EXPERIENCE MATERIALS", "没有经验素材"),
                              uiText("Clear missions to collect wreckage and cubes", "闯关掉落敌机残骸与魔方"))
            return
        }
        applyExperience(to: slot, amount: total)
        persistProfile()
        let upgraded = profile.equipment[slot]
        showHangarMessage(uiText("AUTO-FILL COMPLETE", "一键填充完成"),
                          uiText("+\(total) EXP  •  \(equipmentDisplayName(upgraded)) Lv.\(upgraded.level)",
                                 "灌入 \(total) 点经验  •  \(equipmentDisplayName(upgraded)) 等级 \(upgraded.level)"))
        AudioManager.shared.playSFX("sfx_upgrade")
    }

    // MARK: - 进阶（品质阶 +1，规格第 4 节）

    /// 进阶流程：满级锁 → 四色材料 → 同名装备 → 金币 → 阶 +1、等级落到新阶下限。
    func advanceEquipment(slot: Int) {
        guard phase == .hangar, profile.equipment.indices.contains(slot) else { return }
        let item = profile.equipment[slot]
        guard !item.isMaxStage else {
            showHangarMessage(uiText("MAX STAGE", "已达满阶"),
                              uiText("This module is already PURPLE +3 (stage 9)", "该装备已是紫五星+3（满阶）"))
            return
        }
        // 冻结项 3：必须达到当前阶满级才能进阶。
        guard item.isMaxLevel else {
            showHangarMessage(uiText("LEVEL CAP REACHED", "未达当前阶满级"),
                              uiText("Reach Lv.\(item.levelCap) before advancing", "升到 \(item.levelCap) 级后才能进阶"))
            return
        }
        guard let cost = item.advanceCost() else {
            showHangarMessage(uiText("MAX STAGE", "已达满阶"),
                              uiText("This module cannot advance further", "该装备无法继续进阶"))
            return
        }
        // 1) 四色进阶材料（阶 0/1/5 的材料进阶）。
        for materialID in cost.materials where cost.each > 0 {
            guard materialCount(materialID) >= cost.each else {
                showHangarMessage(uiText("INSUFFICIENT MATERIALS", "进阶材料不足"),
                                  uiText("Need \(cost.each)x \(materialDisplayName(materialID))",
                                         "需要 \(cost.each) 个\(materialDisplayName(materialID))"))
                return
            }
        }
        // 2) 同名装备本体（阶 2..4 / 6..8，等级不限）。
        let candidates = sameNameCandidateIndices(for: item)
        guard candidates.count >= cost.sameName else {
            showHangarMessage(uiText("INSUFFICIENT DUPLICATES", "同名装备不足"),
                              uiText("Need \(cost.sameName)x same-series \(colorSegmentName(item.stage)) module(s)",
                                     "需要 \(cost.sameName) 件同系列\(colorSegmentName(item.stage))装备"))
            return
        }
        // 3) 金币。
        guard profile.credits >= cost.gold else {
            showHangarMessage(uiText("INSUFFICIENT CREDITS", "金币不足"),
                              uiText("Need \(cost.gold) credits", "需要 \(cost.gold) 金币"))
            return
        }
        for materialID in cost.materials where cost.each > 0 { spendMaterial(materialID, amount: cost.each) }
        profile.credits -= cost.gold
        for index in candidates.prefix(cost.sameName).sorted(by: >) {
            profile.inventory.remove(at: index)
        }
        profile.equipment[slot].stage += 1
        let newStage = profile.equipment[slot].stage
        // 等级落到新阶下限（levelMin = 上一阶 levelCap），只升不降；经验清零。
        profile.equipment[slot].level = EquipmentCatalog.shared.levelMin(stage: newStage)
        profile.equipment[slot].exp = 0
        persistProfile()
        let upgraded = profile.equipment[slot]
        showHangarMessage(uiText("STAGE ADVANCED", "进阶成功"),
                          uiText("\(upgraded.displayNameEn)  •  \(equipmentStageLabel(newStage))  •  CAP \(upgraded.levelCap)",
                                 "\(equipmentDisplayName(upgraded))  •  \(equipmentStageLabel(newStage))  •  等级上限 \(upgraded.levelCap)"))
        AudioManager.shared.playSFX("sfx_upgrade")
    }

    /// 保底兜底（规格第 6 节）：装备练到触发等级时任务线赠送一整套紫色材料，每槽位一次。
    func claimQuarkGiftIfEligible() {
        let gift = EquipmentCatalog.shared.guaranteedGift
        var claimedAny = false
        for (index, slot) in EquipmentSlot.allCases.enumerated() {
            guard index < profile.quarkGiftClaimed.count, !profile.quarkGiftClaimed[index] else { continue }
            guard let item = profile.equipment.first(where: { $0.slot == slot }),
                  item.level >= gift.triggerLevel else { continue }
            for materialID in gift.grant { addMaterial(materialID, amount: 1) }
            profile.quarkGiftClaimed[index] = true
            claimedAny = true
        }
        guard claimedAny else { return }
        persistProfile()
        notifyPickup(title: uiText("QUARK MATERIAL GRANT", "夸克材料赠送"),
                     detail: uiText("Task line granted a full purple material set", "任务线赠送了一整套紫色进阶材料"),
                     tint: rgb(198, 132, 255))
    }

    private func showHangarMessage(_ title: String, _ detail: String) {
        hangarMessageTitle = title
        hangarMessageDetail = detail
        hangarMessageTimer = 2.4
    }

    /// 装备 Tab：点击槽位卡进入该槽位的仓库换装子视图。
    /// 入参是出战件数组下标；槽位由装备自身派生，避免下标与槽位枚举混用。
    func openVaultForSlot(_ equipmentIndex: Int) {
        guard phase == .hangar, profile.equipment.indices.contains(equipmentIndex) else { return }
        let slot = profile.equipment[equipmentIndex].slot
        selectedEquipmentSlot = equipmentIndex
        hangarVaultSlot = slot
        vaultFilterSlot = slot
        vaultPage = 0
        selectedVaultInventoryIndex = nil
    }

    /// 退出换装子视图，回到装备槽位总览。
    func closeVaultForSlot() {
        hangarVaultSlot = nil
        vaultFilterSlot = nil
        vaultPage = 0
        selectedVaultInventoryIndex = nil
    }

    func moveVaultPage(_ delta: Int) {
        vaultPage = min(max(0, vaultPage + delta), vaultPageCount - 1)
        selectedVaultInventoryIndex = nil
    }

    /// 机体列表滚动：输入只改目标值，显示值随后由弹簧动画平滑追赶。
    /// 指针坐标需经 uiPoint 转换，才能与布局热区保持同一坐标系。
    private func updateShipListScroll(delta: Double, wheelDelta: Double, width: Double, height: Double) {
        let maxScroll = shipListMaxScroll(width: width, height: height)
        guard maxScroll > 0 else {
            resetShipScroll()
            return
        }
        // 滚轮：累积到整格后每格滚动一行。按行对齐可避免出现半截卡片。
        shipWheelAccumulator += wheelDelta
        let notches = shipWheelAccumulator.rounded(.towardZero)
        if notches != 0 {
            shipWheelAccumulator -= notches
            shipListScrollTarget = alignedShipScroll(shipListScrollTarget - notches * shipRowStride(),
                                                     width: width, height: height)
        }
        if mousePrimaryDown {
            let pointer = uiPoint(for: mousePosition, width: width, height: height)
            let knob = shipScrollKnob(width: width, height: height, scroll: shipListScroll)
            if !shipScrollDragging, knob.contains(pointer) {
                shipScrollDragging = true
                shipScrollGrabOffset = pointer.y - knob.y
            }
            if shipScrollDragging {
                // 拖拽同样走目标值：指针位置决定目标行，显示值平滑跟随。
                shipListScrollTarget = shipScrollValue(forKnobY: pointer.y - shipScrollGrabOffset,
                                                       width: width, height: height)
            }
        } else {
            shipScrollDragging = false
        }
        advanceShipScrollSpring(delta: delta)
    }

    /// 阻尼弹簧插值：帧率无关（显式欧拉 + 指数衰减），约 0.3 秒收敛、几乎不过冲。
    private func advanceShipScrollSpring(delta: Double) {
        let target = shipListScrollTarget
        shipScrollVelocity += (target - shipListScroll) * UITheme.Animation.scrollStiffness * delta
        shipScrollVelocity *= pow(UITheme.Animation.scrollDamping, delta * 60)
        shipListScroll += shipScrollVelocity * delta
        // 收敛后吸附，避免长期停留在肉眼不可见的微动状态。
        if abs(target - shipListScroll) < 0.5, abs(shipScrollVelocity) < 2 {
            shipListScroll = target
            shipScrollVelocity = 0
        }
    }

    /// 复位机体列表滚动（进入机库或列表不可滚动时）。
    private func resetShipScroll() {
        shipListScroll = 0
        shipListScrollTarget = 0
        shipScrollVelocity = 0
        shipScrollDragging = false
        shipWheelAccumulator = 0
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
        hangarVaultSlot = nil
        selectedVaultInventoryIndex = nil
    }

    func toggleEquipmentLock(_ slot: Int) {
        guard phase == .hangar, profile.equipment.indices.contains(slot) else { return }
        let nextValue = !profile.equipment[slot].locked
        profile.equipment[slot].locked = nextValue
        persistProfile()
        hangarMessageTitle = nextValue ? uiText("MODULE LOCKED", "模块已锁定") : uiText("MODULE UNLOCKED", "模块已解锁")
        hangarMessageDetail = equipmentDisplayName(profile.equipment[slot])
        hangarMessageTimer = 1.8
        AudioManager.shared.playSFX("sfx_upgrade")
    }

    func toggleInventoryLock(_ inventoryIndex: Int) {
        guard phase == .hangar, profile.inventory.indices.contains(inventoryIndex) else { return }
        profile.inventory[inventoryIndex].locked.toggle()
        persistProfile()
        let locked = profile.inventory[inventoryIndex].locked
        hangarMessageTitle = locked ? uiText("MODULE LOCKED", "模块已锁定") : uiText("MODULE UNLOCKED", "模块已解锁")
        hangarMessageDetail = equipmentDisplayName(profile.inventory[inventoryIndex])
        hangarMessageTimer = 1.8
        AudioManager.shared.playSFX("sfx_upgrade")
    }

    /// 仓库 → 出战槽位换装（同槽位替换，旧件回仓库）。
    func equipInventoryItem(_ index: Int) {
        guard phase == .hangar, profile.inventory.indices.contains(index) else { return }
        let item = profile.inventory[index]
        guard let slotIndex = profile.equipment.firstIndex(where: { $0.slot == item.slot }) else { return }
        let previous = profile.equipment[slotIndex]
        var incoming = item
        incoming.equipped = true
        profile.equipment[slotIndex] = incoming
        var outgoing = previous
        outgoing.equipped = false
        let equippedUID = incoming.uid
        profile.inventory.removeAll { $0.uid == equippedUID }
        profile.inventory.append(outgoing)
        persistProfile()
        hangarMessageTitle = uiText("LOADOUT UPDATED", "装备配置已更新")
        hangarMessageDetail = uiText("\(equipmentDisplayName(incoming)) equipped (\(item.slot.rawValue))",
                                     "\(equipmentDisplayName(incoming)) 已装备至\(item.slot.rawValue)槽位")
        hangarMessageTimer = 2.4
    }

    // MARK: - 雷霆战神（规格第 8 节）

    /// 战神槽位 → 装备槽位映射（战神是四槽位之上的第五层，按槽位覆盖）。
    func warriorCoversSlot(_ warrior: WarriorState) -> EquipmentSlot {
        switch warrior.slot {
        case .warriorFighter: return .fighter
        case .warriorSubweapon: return .subweapon
        case .warriorArmor: return .armor
        case .warriorWingman: return .wingman
        }
    }

    /// 部署在某装备槽位的战神（同槽位取第一个）。
    func deployedWarrior(for slot: EquipmentSlot) -> WarriorState? {
        profile.warriors.first { $0.equipped && warriorCoversSlot($0) == slot }
    }

    /// 战神素材合成面板（规格第 8.2 节属性继承）：两件素材按档位优先、阶高、级高取本体；
    /// 素材本体保留原状，只是被占用，拆解即释放。
    func warriorMaterialPanel(_ warrior: WarriorState) -> EquipmentState? {
        let occupied = Set(warrior.materialUIDs)
        let materials = profile.equipment.filter { occupied.contains($0.uid) }
            + profile.inventory.filter { occupied.contains($0.uid) }
        return materials.min { lhs, rhs in
            if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
            if lhs.stage != rhs.stage { return lhs.stage > rhs.stage }
            return lhs.level < rhs.level
        }
    }

    /// 配方激活条件是否满足（双重前置之一：关卡/无尽分数/Boss 类型/币种）。
    func warriorConditionMet(_ recipe: WarriorRecipe) -> Bool {
        let condition = recipe.condition
        switch condition.kind {
        case .campaignMission:
            // unlockedMission = 已通关章数 + 1；通关第 N 章 ⇔ unlockedMission >= N + 1。
            return profile.unlockedMission >= condition.value + 1
        case .endlessBestScore:
            return profile.endlessBestScore >= condition.value
        case .bossTypeDefeated:
            return profile.bossTypesDefeated.contains(condition.rawValue)
        case .currencyTotal:
            let currency = condition.currency ?? "alloy"
            if currency == "alloy" { return profile.alloy >= condition.value }
            return materialCount(currency) >= condition.value
        }
    }

    /// 配方条件文案（机库展示）。
    func warriorConditionText(_ recipe: WarriorRecipe) -> String {
        let condition = recipe.condition
        let met = warriorConditionMet(recipe)
        let text: String
        switch condition.kind {
        case .campaignMission:
            text = uiText("Clear campaign mission \(condition.value)", "通关战役第 \(condition.value) 章")
        case .endlessBestScore:
            text = uiText("Endless best score \(condition.value)", "无尽模式最高分 \(condition.value)")
        case .bossTypeDefeated:
            let bossName = BossType.fromConfigID(condition.rawValue)?.title(for: .chinese) ?? condition.rawValue
            text = uiText("Defeat \(condition.rawValue.uppercased()) boss", "击败\(bossName)")
        case .currencyTotal:
            let currency = condition.currency ?? "alloy"
            let name = currency == "alloy" ? uiText("ALLOY", "合金") : materialDisplayName(currency)
            text = uiText("Own \(condition.value) \(currency)", "持有 \(condition.value) \(name)")
        }
        return met ? text : "[\(text)]"
    }

    /// 配方素材位候选（仓库下标）：满足 seriesId + minStage、未锁定、未被其他战神占用。
    func warriorMaterialIndices(for recipe: WarriorRecipe) -> [[Int]] {
        let occupied = Set(profile.warriors.flatMap { $0.materialUIDs })
        return recipe.materials.map { ref in
            profile.inventory.indices.filter { index in
                let item = profile.inventory[index]
                return item.seriesId == ref.seriesId
                    && item.stage >= ref.minStage
                    && !item.locked
                    && !occupied.contains(item.uid)
            }.sorted { profile.inventory[$0].unitPower > profile.inventory[$1].unitPower }
        }
    }

    /// 激活战神（规格第 8.1 节双重前置：条件 + 两件指定紫装；占用不消耗）。
    func activateWarrior(recipeId: String) {
        guard phase == .hangar, let recipe = EquipmentCatalog.shared.recipe(id: recipeId) else { return }
        guard !profile.warriors.contains(where: { $0.recipeId == recipeId }) else {
            showHangarMessage(uiText("ALREADY FUSED", "已激活"),
                              uiText("\(recipe.name) is already deployed", "\(recipe.name) 已经激活"))
            return
        }
        guard warriorConditionMet(recipe) else {
            showHangarMessage(uiText("CONDITION NOT MET", "激活条件未满足"),
                              warriorConditionText(recipe).replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: ""))
            return
        }
        let slotCandidates = warriorMaterialIndices(for: recipe)
        guard slotCandidates.allSatisfy({ !$0.isEmpty }) else {
            showHangarMessage(uiText("MATERIALS NOT FOUND", "素材装备不足"),
                              uiText("Need two \(recipe.materials.map { EquipmentCatalog.shared.displayName(seriesId: $0.seriesId, stage: $0.minStage) }.joined(separator: " + "))",
                                     "需要两件指定紫装：\(recipe.materials.map { EquipmentCatalog.shared.displayName(seriesId: $0.seriesId, stage: $0.minStage) }.joined(separator: " + "))"))
            return
        }
        let materialUIDs = slotCandidates.compactMap { $0.first.map { profile.inventory[$0].uid } }
        // 激活即部署：该战神槽位为空时自动出战，否则转入待命。
        let slotBusy = profile.warriors.contains { $0.equipped && $0.slot == recipe.slot }
        // 阶级保留（规格第 8.2 节）：同配方若拆过，重新激活继承归档的阶级/等级/黄金态，不洗白。
        let archived = profile.dissolvedWarriors.first { $0.recipeId == recipe.id }
        let warrior = WarriorState(uid: nextEquipmentUID(), recipeId: recipe.id,
                                   level: min(archived?.level ?? 1, EquipmentCatalog.shared.warriorLevelCap(golden: archived?.golden ?? false)),
                                   advanceStage: archived?.advanceStage ?? 0,
                                   golden: archived?.golden ?? false,
                                   materialUIDs: materialUIDs, equipped: !slotBusy)
        profile.warriors.append(warrior)
        if let archived, let archiveIndex = profile.dissolvedWarriors.firstIndex(where: { $0.uid == archived.uid }) {
            profile.dissolvedWarriors.remove(at: archiveIndex)
        }
        persistProfile()
        showHangarMessage(uiText("WARRIOR FUSED", "战神激活成功"),
                          uiText("\(recipe.name)  •  SYNERGY \(Int(warrior.synergyRate * 100))%",
                                 "\(recipe.name)  •  同步率 \(Int(warrior.synergyRate * 100))%"))
        AudioManager.shared.playSFX("sfx_upgrade")
    }

    /// 无损拆解（冻结项 9）：释放占用素材，素材装备原样保留。
    /// 阶级保留（规格第 8.2 节）：战神记录归档不删除，重新激活同配方时继承阶级/等级/黄金态。
    func dissolveWarrior(index: Int) {
        guard phase == .hangar, profile.warriors.indices.contains(index) else { return }
        let warrior = profile.warriors.remove(at: index)
        if let archivedIndex = profile.dissolvedWarriors.firstIndex(where: { $0.recipeId == warrior.recipeId }) {
            profile.dissolvedWarriors[archivedIndex] = warrior
        } else {
            profile.dissolvedWarriors.append(warrior)
        }
        persistProfile()
        if let selected = selectedWarriorIndex {
            if selected == index {
                selectedWarriorIndex = nil
            } else if selected > index {
                selectedWarriorIndex = selected - 1
            }
        }
        showHangarMessage(uiText("WARRIOR DISSOLVED", "战神已拆解"),
                          uiText("Materials returned to the vault • stage preserved", "素材装备已无损归还仓库 • 阶级已保留"))
        AudioManager.shared.playSFX("sfx_upgrade")
    }

    /// 战神部署 / 待命切换（同槽位只部署一个战神）。
    func toggleWarriorDeploy(index: Int) {
        guard phase == .hangar, profile.warriors.indices.contains(index) else { return }
        let warrior = profile.warriors[index]
        if warrior.equipped {
            profile.warriors[index].equipped = false
        } else {
            // 同槽位其他战神先待命，保证唯一部署。
            for other in profile.warriors.indices where profile.warriors[other].slot == warrior.slot {
                profile.warriors[other].equipped = false
            }
            profile.warriors[index].equipped = true
        }
        persistProfile()
        AudioManager.shared.playSFX("sfx_upgrade")
    }

    /// 战神升级：吃经验素材（与装备同一经验池），满级后可进阶（规格第 8.4 节）。
    func upgradeWarriorWithExp(index: Int) {
        guard phase == .hangar, profile.warriors.indices.contains(index) else { return }
        let warrior = profile.warriors[index]
        guard !warrior.isMaxLevel else {
            showHangarMessage(uiText("LEVEL CAP REACHED", "已达本体满级"),
                              uiText("Advance to raise the warrior cap", "进阶可提升战神等级上限"))
            return
        }
        let value = experienceValue(selectedExpMaterial)
        guard value > 0 else {
            showHangarMessage(uiText("INVALID MATERIAL", "无效素材"),
                              uiText("Pick an experience material in the upgrade tab", "请在升级页选择经验素材"))
            return
        }
        guard spendMaterial(selectedExpMaterial, amount: 1) else {
            showHangarMessage(uiText("INSUFFICIENT MATERIALS", "经验素材不足"),
                              uiText("Need 1x \(materialDisplayName(selectedExpMaterial))",
                                     "需要 1 个\(materialDisplayName(selectedExpMaterial))"))
            return
        }
        var level = warrior.level
        var remaining = max(0, warrior.exp) + value
        while level < warrior.levelCap {
            let need = EquipmentCatalog.shared.expToNext(level: level, stage: 0)
            if remaining < need { break }
            remaining -= need
            level += 1
        }
        profile.warriors[index].level = level
        profile.warriors[index].exp = level >= warrior.levelCap ? 0 : remaining
        persistProfile()
        let updated = profile.warriors[index]
        showHangarMessage(uiText("WARRIOR LEVEL UP", "战神等级提升"),
                          uiText("\(updated.displayName)  •  Lv.\(updated.level)/\(updated.levelCap)",
                                 "\(updated.displayName)  •  等级 \(updated.level)/\(updated.levelCap)"))
        AudioManager.shared.playSFX("sfx_upgrade")
    }

    /// 战神进阶 +0..+9：满级后消耗四种战神专属材料各 N 个（N = 当前阶级 + 1，规格第 8.4 节）。
    func advanceWarrior(index: Int) {
        guard phase == .hangar, profile.warriors.indices.contains(index) else { return }
        let warrior = profile.warriors[index]
        guard warrior.advanceStage < 9 else {
            showHangarMessage(uiText("MAX ADVANCE", "已达最高进阶"),
                              uiText("Promote to GOLDEN warrior instead", "可晋级为黄金战神"))
            return
        }
        guard warrior.isMaxLevel else {
            showHangarMessage(uiText("LEVEL CAP REQUIRED", "需先升满本体等级"),
                              uiText("Reach Lv.\(warrior.levelCap) before advancing", "升到 \(warrior.levelCap) 级后才能进阶"))
            return
        }
        let need = warrior.advanceStage + 1
        for materialID in EquipmentCatalog.shared.synergyConfig.advanceMaterials {
            guard materialCount(materialID) >= need else {
                showHangarMessage(uiText("INSUFFICIENT WARRIOR MATERIALS", "战神进阶材料不足"),
                                  uiText("Need \(need)x \(materialDisplayName(materialID))",
                                         "需要 \(need) 个\(materialDisplayName(materialID))"))
                return
            }
        }
        for materialID in EquipmentCatalog.shared.synergyConfig.advanceMaterials {
            spendMaterial(materialID, amount: need)
        }
        profile.warriors[index].advanceStage += 1
        persistProfile()
        let updated = profile.warriors[index]
        showHangarMessage(uiText("WARRIOR ADVANCED", "战神进阶成功"),
                          uiText("+\(updated.advanceStage)  •  SYNERGY \(Int(updated.synergyRate * 100))%",
                                 "+\(updated.advanceStage)  •  同步率 \(Int(updated.synergyRate * 100))%"))
        AudioManager.shared.playSFX("sfx_upgrade")
    }

    /// 黄金战神（规格第 8.5 节）：+9 满进阶 + 10 套黄金材料 → 等级上限 60、同步率上限 90%。
    func promoteWarriorGolden(index: Int) {
        guard phase == .hangar, profile.warriors.indices.contains(index) else { return }
        let warrior = profile.warriors[index]
        guard !warrior.golden else {
            showHangarMessage(uiText("ALREADY GOLDEN", "已是黄金战神"), warrior.displayName)
            return
        }
        let goldenConfig = EquipmentCatalog.shared.synergyConfig.golden
        guard warrior.advanceStage >= goldenConfig.requiredAdvanceStage else {
            showHangarMessage(uiText("ADVANCE STAGE REQUIRED", "进阶阶级不足"),
                              uiText("Reach +\(goldenConfig.requiredAdvanceStage) first", "需先进阶到 +\(goldenConfig.requiredAdvanceStage)"))
            return
        }
        for materialID in EquipmentCatalog.shared.synergyConfig.goldenMaterials {
            guard materialCount(materialID) >= goldenConfig.goldenMaterialSets else {
                showHangarMessage(uiText("INSUFFICIENT GOLDEN MATERIALS", "黄金材料不足"),
                                  uiText("Need \(goldenConfig.goldenMaterialSets)x \(materialDisplayName(materialID))",
                                         "需要 \(goldenConfig.goldenMaterialSets) 个\(materialDisplayName(materialID))"))
                return
            }
        }
        for materialID in EquipmentCatalog.shared.synergyConfig.goldenMaterials {
            spendMaterial(materialID, amount: goldenConfig.goldenMaterialSets)
        }
        profile.warriors[index].golden = true
        persistProfile()
        let updated = profile.warriors[index]
        showHangarMessage(uiText("GOLDEN WARRIOR", "黄金战神达成"),
                          uiText("\(updated.displayName)  •  SYNERGY CAP \(Int(updated.synergyRate * 100))%  •  CAP Lv.\(updated.levelCap)",
                                 "\(updated.displayName)  •  同步率上限 \(Int(updated.synergyRate * 100))%  •  等级上限 \(updated.levelCap)"))
        AudioManager.shared.playSFX("sfx_upgrade")
    }

    // MARK: - 战力与关卡门槛（规格第 7 节）

    /// 总战力 = Σ 四件单件战力（归一化：同品质同阶同级四槽相等；战神不进战力）。
    func combatPower() -> Int {
        profile.equipment.reduce(0) { $0 + $1.unitPower }
    }

    /// 当前关卡战力门槛：闯关按章、无尽按波次。
    func activePowerGate() -> Int {
        if gameMode == .endless {
            return EquipmentCatalog.shared.powerGate(endlessWave: max(1, endlessWaveNumber))
        }
        return EquipmentCatalog.shared.powerGate(mission: activeMission.id)
    }

    /// 战力门槛伤害折算（规格第 7.4 节）：达标 1.0，不足按 战力/门槛 线性衰减，下限 minScale。
    func powerGateScale(gate: Int? = nil) -> Double {
        EquipmentCatalog.shared.powerScale(power: combatPower(), gate: gate ?? activePowerGate())
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
        hangarMessageDetail = uiText("Progress will autosave in the Save folder.", "进度会自动保存到 Save 文件夹。")
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
                selectGameMode(GameMode.allCases[index])
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
            let shipArea = shipListArea(width: width, height: height)
            if shipScrollTrack(width: width, height: height).contains(point) {
                // 点击轨道空白处：让滑块中心跳到点击位置（拖拽滑块由 updateShipListScroll 处理）。
                // 只改目标值，显示值由弹簧动画平滑跟随。
                if !shipScrollKnob(width: width, height: height, scroll: shipListScroll).contains(point) {
                    let knobHeight = shipScrollKnob(width: width, height: height, scroll: 0).height
                    shipListScrollTarget = shipScrollValue(forKnobY: point.y - knobHeight * 0.5,
                                                           width: width, height: height)
                }
                return
            }
            if shipArea.contains(point) {
                // 机体卡按滚动偏移判定；视口外的部分已被裁剪，不应响应点击。
                for (index, card) in shipCards(width: width, height: height).enumerated() {
                    let visible = UIRect(x: card.x, y: card.y - shipListScroll, width: card.width, height: card.height)
                    if visible.contains(point), let ship = ShipType(rawValue: index) { selectShip(ship) }
                }
                return
            }
            if hangarTab == 0 {
                if hangarVaultSlot != nil {
                    // 换装子视图：返回 / 翻页 / 选卡 / 装备 / 锁定。
                    if vaultBackToSlotsButton(width: width, height: height).contains(point) { closeVaultForSlot(); return }
                    if vaultPrevButton(width: width, height: height).contains(point) { moveVaultPage(-1); return }
                    if vaultNextButton(width: width, height: height).contains(point) { moveVaultPage(1); return }
                    let visible = visibleVaultIndices
                    for (cardIndex, card) in vaultCards(width: width, height: height).enumerated() where card.contains(point) {
                        let absoluteIndex = vaultPage * 4 + cardIndex
                        if visible.indices.contains(absoluteIndex) {
                            selectedVaultInventoryIndex = visible[absoluteIndex]
                        }
                        return
                    }
                    if let selectedVaultInventoryIndex {
                        if vaultEquipButton(width: width, height: height).contains(point) {
                            equipInventoryItem(selectedVaultInventoryIndex)
                            closeVaultForSlot()
                        } else if vaultSelectedLockButton(width: width, height: height).contains(point) {
                            toggleInventoryLock(selectedVaultInventoryIndex)
                        }
                    }
                    return
                }
                for (index, card) in hangarCards(width: width, height: height).enumerated() where card.contains(point) {
                    openVaultForSlot(index)
                    return
                }
                // 经验素材格（规格第 5 节）。
                let sources = EquipmentCatalog.shared.experienceSources
                for (index, cell) in hangarExpCells(width: width, height: height).enumerated() where cell.contains(point) {
                    if sources.indices.contains(index) { selectExpMaterial(sources[index].id) }
                    return
                }
                if hangarUpgradeButton(width: width, height: height).contains(point) { upgradeEquipmentWithExp(slot: selectedEquipmentSlot) }
                else if hangarBatchUpgradeButton(width: width, height: height).contains(point) { autoFillEquipmentExp(slot: selectedEquipmentSlot) }
                else if hangarAdvanceButton(width: width, height: height).contains(point) { advanceEquipment(slot: selectedEquipmentSlot) }
                else if hangarLockButton(width: width, height: height).contains(point) { toggleEquipmentLock(selectedEquipmentSlot) }
            } else if hangarTab == 1 {
                // 战神 Tab：先点配方卡，再点已激活战神卡。
                let recipes = EquipmentCatalog.shared.recipes
                for (index, card) in warriorRecipeCards(width: width, height: height).enumerated() where card.contains(point) {
                    if recipes.indices.contains(index) {
                        selectedWarriorRecipe = recipes[index].id
                        selectedWarriorIndex = nil
                    }
                    return
                }
                for (index, card) in warriorSlotCards(width: width, height: height).enumerated() where card.contains(point) {
                    let slot = WarriorSlot.allCases[index]
                    if let found = profile.warriors.enumerated().first(where: { $0.element.slot == slot })?.0 {
                        selectedWarriorIndex = found
                        selectedWarriorRecipe = nil
                    } else {
                        selectedWarriorIndex = nil
                    }
                    return
                }
                if warriorFuseButton(width: width, height: height).contains(point) {
                    if let recipeId = selectedWarriorRecipe {
                        activateWarrior(recipeId: recipeId)
                    } else {
                        showHangarMessage(uiText("SELECT A RECIPE", "请先选择配方"),
                                          uiText("Pick a warrior recipe on the left", "在左侧配方卡中选择一个战神"))
                    }
                }
                else if warriorLevelButton(width: width, height: height).contains(point) {
                    if let index = selectedWarriorIndex { upgradeWarriorWithExp(index: index) }
                }
                else if warriorAdvanceButton(width: width, height: height).contains(point) {
                    if let index = selectedWarriorIndex {
                        let warrior = profile.warriors[index]
                        // +9 满阶且非黄金时，进阶按钮切换为黄金晋级（规格第 8.5 节）。
                        if warrior.advanceStage >= 9 && !warrior.golden { promoteWarriorGolden(index: index) }
                        else { advanceWarrior(index: index) }
                    }
                }
                else if warriorDeployButton(width: width, height: height).contains(point) {
                    if let index = selectedWarriorIndex { toggleWarriorDeploy(index: index) }
                }
                else if warriorDissolveButton(width: width, height: height).contains(point) {
                    if let index = selectedWarriorIndex { dissolveWarrior(index: index) }
                }
                else if warriorExpButton(width: width, height: height).contains(point) {
                    cycleExpMaterial()
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
            // The SDL presentation owns dynamic music. This lobby track is a
            // native fallback for non-SDL diagnostic entry points only.
            let path = audioFilePath("music_lobby.wav")
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

/// 阶 → 品质色（规格第 4 节四色：白 / 绿 / 蓝 / 紫；黄金战神单独用 warning 色）。
func equipmentStageColor(_ stage: Int) -> COLORREF {
    let color = EquipmentCatalog.shared.stageInfo(stage)?.color ?? "white"
    switch color {
    case "green": return rgb(97, 209, 255)
    case "blue": return rgb(204, 143, 255)
    case "purple": return rgb(255, 211, 105)
    default: return rgb(187, 199, 219)
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
        if CommandLine.arguments.contains("--equipment-self-check") { EquipmentSelfCheck.run(); return }
        if CommandLine.arguments.contains("--font-coverage") { FontCoverageCheck.run(); return }
        SDLFullGame.run()
    }
}
