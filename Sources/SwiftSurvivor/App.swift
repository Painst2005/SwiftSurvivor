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
        case .endless: return "没有时间限制 • 挑战最高分"
        case .blitz: return "更多敌机 • 更强火力 • 更丰厚掉落"
        case .zen: return "低伤害 • 密集编队 • 轻松飞行"
        }
    }

    var isFinite: Bool {
        self != .endless
    }
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
                               englishDetail: "Overdrive now adds auxiliary projectiles", chineseDetail: "超频驱动现在会增加辅助子弹"),
        BuildSynergyDefinition(id: "storm_crit", required: [.thunder],
                               englishTitle: "SYNERGY ONLINE: STORM CRIT", chineseTitle: "联动已激活：风暴暴击",
                               englishDetail: "Critical hits now charge Thunder energy", chineseDetail: "暴击现在会充能雷霆能量"),
        BuildSynergyDefinition(id: "overload_matrix", required: [.laser, .thunder],
                               englishTitle: "SYNERGY ONLINE: OVERLOAD MATRIX", chineseTitle: "联动已激活：超载矩阵",
                               englishDetail: "Laser and Thunder damage gain a final surge", chineseDetail: "激光与雷霆伤害获得终极增幅")
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
        AchievementDefinition(id: "boss_breaker", title: "BOSS BREAKER", chineseTitle: "Boss 终结者",
                              detail: "Defeat 3 bosses", chineseDetail: "击败 3 个 Boss",
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
        switch self { case .weapons: return "武器"; case .enemies: return "敌机"; case .bosses: return "Boss" }
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
        CodexEntry(id: "dreadnought", category: .bosses, title: "DREADNOUGHT", chineseTitle: "无畏战舰", detail: "Twin turrets and fan barrages", chineseDetail: "双炮塔与扇形弹幕"),
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

    var winRect: RECT {
        RECT(left: LONG(x), top: LONG(y), right: LONG(x + width), bottom: LONG(y + height))
    }
}

struct Enemy {
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
    var diveStarted: Bool = false
    var spawnTimer: Double = 4.5
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
}

struct DamageNumber {
    var position: Vec2
    var amount: Int
    var critical: Bool
    var life: Double
    var maxLife: Double
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
}

enum BossType: Int, CaseIterable {
    case dreadnought = 0
    case riftBehemoth = 1
    case frostWarden = 2
    case originArchitect = 3

    var title: String {
        switch self {
        case .dreadnought: return "DREADNOUGHT"
        case .riftBehemoth: return "RIFT BEHEMOTH"
        case .frostWarden: return "FROST WARDEN"
        case .originArchitect: return "ORIGIN ARCHITECT"
        }
    }

    func title(for language: GameLanguage) -> String {
        guard language == .chinese else { return title }
        switch self {
        case .dreadnought: return "无畏战舰"
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
    var controlMode: ControlMode = .wasd
    var phaseBeforeControls: GamePhase = .menu
    var phaseBeforeSettings: GamePhase = .menu
    var phaseBeforeSaveSlots: GamePhase = .menu
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
    var hangarMessageTitle = ""
    var hangarMessageDetail = ""
    var hangarMessageTimer = 0.0
    var hangarTab = 0
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
    var precisionMode = false
    var player = Vec2(x: 500, y: 630)
    var playerRadius = 18.0
    var coreRadius = 6.0
    var health = 120.0
    var maxHealth = 120.0
    var moveSpeed = 330.0
    var damage = 18.0
    var fireCooldown = 0.24
    var fireTimer = 0.0
    var auxiliaryFireTimer = 0.65
    var secondaryFireTimer = 3.8
    var armorShieldCharges = 0
    var armorDamageReduction = 0.0
    var waveTimer = 1.2
    var waveIndex = 0
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
    var laserTime = 0.0
    var reflectorTime = 0.0
    var spreadTime = 0.0
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
        case .endless: return 1.0
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
        case .endless: return 1.0
        case .blitz: return 1.12
        case .zen: return 0.30
        }
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
        switch weaponType {
        case .missile: return max(fireCooldown * 2.15, 0.32)
        case .electromagnetic: return max(fireCooldown * 0.72, 0.065)
        default: return fireCooldown
        }
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
        controlMode = ControlMode(rawValue: profile.controlMode) ?? .wasd
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
        armorShieldCharges = 1 + max(0, armorLevel / 8)
        fireTimer = 0.10
        auxiliaryFireTimer = 0.65
        secondaryFireTimer = max(2.8, 4.6 - Double(secondaryLevel) * 0.12)
        waveTimer = 1.20
        waveIndex = 0
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
        laserTime = 0
        reflectorTime = 0
        spreadTime = 0
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
        score = 0
        kills = 0
        runCreditsEarned = 0
        runCoresEarned = 0
        runAlloyEarned = 0
        experience = 0
        experienceGoal = 10
        enemies.removeAll(keepingCapacity: true)
        recycleAllBullets()
        powerUps.removeAll(keepingCapacity: true)
        particles.removeAll(keepingCapacity: true)
        damageNumbers.removeAll(keepingCapacity: true)
        upgradeOptions.removeAll()
        if stars.isEmpty { initializeStars(width: width, height: height) }
    }

    func update(delta rawDelta: Double, width: Double, height: Double) {
        let delta = min(max(rawDelta, 0), 0.05)
        if stars.isEmpty { initializeStars(width: width, height: height) }
        if phase == .menu || phase == .saveSlots || phase == .missionSelect || phase == .controls || phase == .hangar || phase == .settings || phase == .archive {
            updateStars(delta: delta, height: height)
            updateParticles(delta: delta)
            hangarMessageTimer = max(0, hangarMessageTimer - delta)
            return
        }
        guard phase == .playing else { return }
        updateStars(delta: delta, height: height)
        updateParticles(delta: delta)
        updateDamageNumbers(delta: delta)
        updateCameraShake(delta: delta)

        survivalTime += delta
        stage = gameMode == .campaign ? activeMission.id : Int(survivalTime / 45.0) + 1
        laserTime = max(0, laserTime - delta)
        reflectorTime = max(0, reflectorTime - delta)
        spreadTime = max(0, spreadTime - delta)
        notificationTimer = max(0, notificationTimer - delta)
        stageClearTimer = max(0, stageClearTimer - delta)
        stageBannerTimer = max(0, stageBannerTimer - delta)
        playerInvulnerability = max(0, playerInvulnerability - delta)
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
        if controlMode == .mouse {
            let toCursor = mousePosition - player
            if toCursor.length > 4 { direction = toCursor.normalized }
        } else {
            if keyDown(0x41) || keyDown(0x25) { direction.x -= 1 } // A / left
            if keyDown(0x44) || keyDown(0x27) { direction.x += 1 } // D / right
            if keyDown(0x57) || keyDown(0x26) { direction.y -= 1 } // W / up
            if keyDown(0x53) || keyDown(0x28) { direction.y += 1 } // S / down
        }
        if direction.length > 0 {
            let speed = precisionMode ? moveSpeed * 0.42 : moveSpeed
            let travel = min(speed * delta, max(0, (mousePosition - player).length))
            player = controlMode == .mouse ? player + direction * travel : player + direction.normalized * speed * delta
        }
        let field = playfieldBounds(width: width, height: height)
        player.x = min(max(player.x, field.left + playerRadius + 10), field.right - playerRadius - 10)
        player.y = min(max(player.y, field.top + playerRadius + 10), field.bottom - playerRadius - 12)

        if stageClearTimer <= 0, boss == nil {
            waveTimer -= delta
            if waveTimer <= 0 {
                spawnWave(field: field)
                let ramp = min(survivalTime / 180.0, 1.0)
                waveTimer = 1.95 - ramp * 0.82
            }
        }

        let canSpawnAnotherBoss = gameMode == .endless || !missionBossSpawned
        if stageClearTimer <= 0, survivalTime >= nextBossTime, boss == nil, canSpawnAnotherBoss {
            spawnBoss(field: field)
            if gameMode == .endless { nextBossTime += 45 }
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
        let formation = waveIndex % 3
        let baseCount = survivalTime < 20 ? 2 : (survivalTime < 60 ? 3 : 4)
        let count = min(10, max(1, Int((Double(baseCount + waveIndex / 8) * activeSpawnMultiplier).rounded(.down))))
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
            spawnEnemy(position: Vec2(x: x, y: y), pattern: pattern, type: enemyTypeForWave(index: index, formation: formation))
        }
        waveIndex += 1
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

    private func spawnEnemy(position: Vec2, pattern: Int, type: Int = EnemyType.fighter.rawValue) {
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
        let hp = (24.0 + survivalTime * 0.22 + Double(stage - 1) * 10) * hpMultiplier * activeDifficultyMultiplier
        enemies.append(Enemy(position: position,
                             baseX: position.x,
                             radius: radius,
                             speed: (speed + survivalTime * 0.04 + Double(stage - 1) * 7) * (0.88 + activeDifficultyMultiplier * 0.12),
                             health: hp,
                             maxHealth: hp,
                             tint: tint,
                             pattern: pattern,
                             age: 0,
                             phase: Double.random(in: 0...6.28, using: &rng),
                             shootTimer: initialShoot,
                             type: enemyType.rawValue))
    }

    private func spawnBoss(field: PlayfieldBounds) {
        // Swift's checked integer arithmetic emits a CPU trap on overflow.
        // Keep restored and long-running session values bounded so an invalid
        // value cannot surface on Windows as the 0xc000001d boss-spawn crash.
        let safeStage = min(10_000, max(1, stage))
        let safeTime = survivalTime.isFinite ? min(1_000_000, max(0, survivalTime)) : 0
        let rawDifficulty = activeDifficultyMultiplier
        let safeDifficulty = rawDifficulty.isFinite ? min(100, max(0.05, rawDifficulty)) : 1
        let bossCount = BossCatalog.all.count
        guard bossCount > 0 else { return }
        missionBossSpawned = true
        let hp = min(100_000_000, (650 + Double(safeStage - 1) * 180 + safeTime * 2.2) * safeDifficulty)
        var newBoss = Boss(position: Vec2(x: field.centerX, y: -100), health: hp, maxHealth: hp, age: 0, shootTimer: 1.6)
        let safeMission = min(100_000, max(0, selectedMission))
        let safeDefeats = min(100_000, max(0, bossDefeats))
        newBoss.kind = (safeMission + safeDefeats) % bossCount
        newBoss.leftTurretHealth = hp * 0.18
        newBoss.rightTurretHealth = hp * 0.18
        newBoss.laserCooldown = gameMode == .zen ? 8.0 : 5.0
        newBoss.laserX = field.centerX
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

    private func clearEnemyBullets() {
        for index in bullets.indices.reversed() where !bullets[index].playerOwned {
            recycleBullet(at: index)
        }
    }

    private func fireWeapon() {
        AudioManager.shared.playSFX("sfx_shoot")
        let laserBoost = (weaponType == .laser || laserTime > 0) ? (frostRayActive ? 2.0 : 1.6) : 1.0
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
            var spread = spreadTime > 0 ? [-0.28] + baseSpread + [0.28] : baseSpread
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
                                   pierce: laserTime > 0 ? max(1, projectilePenetration + 2) : projectilePenetration)
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
            let spreadAngle = spreadTime > 0 ? 0.95 : 0.72
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
                    enemies[index].shootTimer = 3.7
                }
                if enemies[index].attackWarningActive {
                    enemies[index].warningTimer -= delta
                    if enemies[index].warningTimer <= 0 {
                    let sniperEmitter = BulletEmitter(pattern: .aimed, count: 1, speed: 430, damage: 14 * activeEnemyDamageMultiplier,
                                                          radius: 6, lifetime: 5.5, tint: rgb(255, 102, 133),
                                                          bulletType: .aimed, modifiers: [.constantVelocity, .lockDirection])
                        emitPattern(sniperEmitter, from: enemies[index].position + Vec2(x: 0, y: 18),
                                    target: Vec2(x: enemies[index].warningTargetX, y: field.bottom + 100))
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

            if enemyType != .sniper, enemyType != .kamikaze {
                enemies[index].shootTimer -= delta
                if enemies[index].shootTimer <= 0, enemies[index].position.y > field.top + 4, enemies[index].position.y < field.bottom - 40 {
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
                    let emitter = BulletEmitter(pattern: pattern, count: pattern == .triple ? 3 : 1,
                                                speed: 175 + survivalTime * 0.16, damage: damage * activeEnemyDamageMultiplier,
                                                radius: 5.5, lifetime: 5, tint: enemyType == .carrier ? rgb(255, 140, 221) : rgb(255, 113, 104),
                                                bulletType: bulletType, modifiers: modifiers,
                                                spread: pattern == .triple ? 0.23 : 0,
                                                homingDuration: pattern == .aimed && modifiers.contains(.homing) ? 1.15 : 0,
                                                maxTurnRate: 1.45,
                                                splitCount: enemyType == .carrier ? 2 : 0,
                                                splitSpread: 0.20)
                    emitPattern(emitter, from: enemies[index].position, target: pattern == .aimed ? player : nil)
                    enemies[index].shootTimer = enemyType == .turret ? 1.65 : Double.random(in: 1.9...3.2, using: &rng)
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
        let ratio = currentBoss.health / max(1, currentBoss.maxHealth)
        let desiredPhase = ratio > 0.70 ? 1 : (ratio > 0.30 ? 2 : 3)
        if desiredPhase != currentBoss.phase {
            currentBoss.phase = desiredPhase
            currentBoss.phaseFlash = 1.0
            currentBoss.attackPrimed = false
            currentBoss.attackPatternIndex = 0
            currentBoss.warningTimer = 0
            currentBoss.shootTimer = 0.8
            currentBoss.laserWarningTimer = 0
            currentBoss.laserActiveTimer = 0
            currentBoss.laserCooldown = 1.2
            addCameraShake(strength: 9)
            let detail = desiredPhase == 2 ? "Armor breach • twin fan barrage" : "Core unstable • survive the final storm"
            notifyPickup(title: "BOSS PHASE \(desiredPhase)", detail: detail, tint: rgb(255, 146, 244))
        }
        currentBoss.phaseFlash = max(0, currentBoss.phaseFlash - delta)
        if currentBoss.position.y < 125 {
            currentBoss.position.y += 100 * delta
        } else {
            switch currentBoss.phase {
            case 1:
                currentBoss.position.x = field.centerX + sin(currentBoss.age * 0.75) * min(max(120, field.width * 0.28), field.width * 0.5 - 110)
            case 2:
                currentBoss.position.y = 150 + sin(currentBoss.age * 1.25) * 22
                currentBoss.position.x = field.centerX + sin(currentBoss.age * 1.10) * min(max(150, field.width * 0.33), field.width * 0.5 - 110)
            default:
                currentBoss.position.y = 142 + sin(currentBoss.age * 1.9) * 38
                currentBoss.position.x = field.centerX + sin(currentBoss.age * 1.75) * min(max(170, field.width * 0.38), field.width * 0.5 - 110)
            }
        }
        currentBoss.shootTimer -= delta
        currentBoss.warningTimer = max(0, currentBoss.warningTimer - delta)
        currentBoss.laserCooldown = max(0, currentBoss.laserCooldown - delta)
        let wasLaserWarning = currentBoss.laserWarningTimer > 0
        currentBoss.laserWarningTimer = max(0, currentBoss.laserWarningTimer - delta)
        currentBoss.laserActiveTimer = max(0, currentBoss.laserActiveTimer - delta)
        currentBoss.laserHitCooldown = max(0, currentBoss.laserHitCooldown - delta)
        if wasLaserWarning, currentBoss.laserWarningTimer <= 0 {
            currentBoss.laserActiveTimer = currentBoss.phase == 3 ? 1.45 : 1.10
            currentBoss.laserHitCooldown = 0
            addCameraShake(strength: 5)
            notifyPickup(title: "BOSS LASER", detail: "Stay clear of the marked lane", tint: rgb(255, 104, 160))
        }
        if currentBoss.laserActiveTimer > 0, abs(player.x - currentBoss.laserX) < 24, currentBoss.laserHitCooldown <= 0 {
            damagePlayer(amount: (currentBoss.phase == 3 ? 28 : 22) * activeEnemyDamageMultiplier)
            currentBoss.laserHitCooldown = 0.42
        }
        let laserStep = (currentBoss.attackPatternIndex + currentBoss.kind) % 5
        if currentBoss.phase >= 2, currentBoss.laserCooldown <= 0, !currentBoss.attackPrimed,
           currentBoss.laserWarningTimer <= 0, currentBoss.laserActiveTimer <= 0,
           laserStep == 4, currentBoss.position.y >= 120 {
            currentBoss.laserX = min(max(player.x, field.left + 52), field.right - 52)
            currentBoss.laserWarningTimer = currentBoss.phase == 3 ? 0.70 : 0.90
            currentBoss.laserCooldown = currentBoss.phase == 3 ? 4.6 : 5.8
            currentBoss.attackPatternIndex += 1
            currentBoss.shootTimer = 1.25
        } else if !currentBoss.attackPrimed, currentBoss.shootTimer <= 0, currentBoss.position.y >= 120 {
            currentBoss.attackPrimed = true
            currentBoss.warningTimer = currentBoss.phase == 1 ? 0.18 : (currentBoss.phase == 2 ? 0.55 : 0.72)
        }
        if currentBoss.attackPrimed, currentBoss.warningTimer <= 0 {
            let origin = currentBoss.position + Vec2(x: 0, y: 34)
            let timelineStep = (currentBoss.attackPatternIndex + currentBoss.kind) % 3
            switch currentBoss.phase {
            case 1:
                if timelineStep == 1 {
                    let emitter = BulletEmitter(pattern: .aimed, count: 3, speed: 300, damage: 15 * activeEnemyDamageMultiplier,
                                                radius: 6, lifetime: 5.5, tint: rgb(255, 192, 108), bulletType: .aimed,
                                                modifiers: [.constantVelocity, .homing, .lockDirection], spread: 0.30,
                                                homingDuration: 0.65, maxTurnRate: 1.0)
                    emitPattern(emitter, from: origin, target: player)
                    currentBoss.shootTimer = 1.45
                } else {
                    let emitter = BulletEmitter(pattern: .spread, count: 5, speed: 250, damage: 14 * activeEnemyDamageMultiplier,
                                                radius: 7, lifetime: 6, tint: rgb(255, 178, 75), bulletType: .boss,
                                                modifiers: [.constantVelocity, .sineWave, .lockDirection], spread: timelineStep == 2 ? 0.62 : 0.50)
                    emitPattern(emitter, from: origin)
                    currentBoss.shootTimer = 1.85
                }
            case 2:
                if timelineStep == 0 {
                    let ringEmitter = BulletEmitter(pattern: .ring, count: 11, speed: 225, damage: 16 * activeEnemyDamageMultiplier,
                                                    radius: 7, lifetime: 6, tint: rgb(255, 112, 155), bulletType: .boss,
                                                    modifiers: [.constantVelocity, .lockDirection])
                    emitPattern(ringEmitter, from: origin)
                    currentBoss.shootTimer = 1.65
                } else if timelineStep == 1 {
                    let burstEmitter = BulletEmitter(pattern: .spread, count: 7, speed: 205, damage: 15 * activeEnemyDamageMultiplier,
                                                     radius: 6.5, lifetime: 6, tint: rgb(224, 102, 230), bulletType: .boss,
                                                     modifiers: [.constantVelocity, .accelerate, .delayedActivation, .stopAndGo, .lockDirection], spread: 0.75, acceleration: 26,
                                                     activationDelay: 0.42)
                    emitPattern(burstEmitter, from: origin)
                    currentBoss.shootTimer = 1.35
                } else {
                    let aimedEmitter = BulletEmitter(pattern: .aimed, count: 1, speed: 315, damage: 17 * activeEnemyDamageMultiplier,
                                                     radius: 6, lifetime: 5.5, tint: rgb(255, 183, 102), bulletType: .aimed,
                                                     modifiers: [.constantVelocity, .homing, .lockDirection], homingDuration: 0.9, maxTurnRate: 1.2)
                    emitPattern(aimedEmitter, from: origin, target: player)
                    currentBoss.shootTimer = 1.35
                }
            default:
                if timelineStep == 0 {
                    let spiralEmitter = BulletEmitter(pattern: .spiral, count: 15, speed: 240, damage: 18 * activeEnemyDamageMultiplier,
                                                      radius: 7, lifetime: 6, tint: rgb(255, 78, 126), bulletType: .boss,
                                                      modifiers: [.constantVelocity, .accelerate, .split, .curve, .lockDirection], spread: 0.95,
                                                      rotation: currentBoss.age * 0.65, acceleration: 22, splitCount: 3, splitSpread: 0.24)
                    emitPattern(spiralEmitter, from: origin)
                    currentBoss.shootTimer = 1.35
                } else if timelineStep == 1 {
                    let ringEmitter = BulletEmitter(pattern: .ring, count: 13, speed: 240, damage: 18 * activeEnemyDamageMultiplier,
                                                    radius: 7, lifetime: 6, tint: rgb(207, 92, 250), bulletType: .boss,
                                                    modifiers: [.constantVelocity, .accelerate, .bounce, .lockDirection], acceleration: 18,
                                                    bounceCount: 1)
                    emitPattern(ringEmitter, from: origin)
                    currentBoss.shootTimer = 1.25
                } else {
                    let aimedEmitter = BulletEmitter(pattern: .aimed, count: 2, speed: 330, damage: 20 * activeEnemyDamageMultiplier,
                                                     radius: 6.5, lifetime: 5.5, tint: rgb(255, 170, 89), bulletType: .aimed,
                                                     modifiers: [.constantVelocity, .homing, .lockDirection], spread: 0.48,
                                                     homingDuration: 1.2, maxTurnRate: 1.35)
                    emitPattern(aimedEmitter, from: origin, target: player)
                    currentBoss.shootTimer = 1.10
                }
            }
            // Side turrets are independent emitters. Destroying one removes
            // its contribution to the attack timeline and opens a safe lane.
            if currentBoss.leftTurretHealth > 0, currentBoss.attackPatternIndex % 2 == 0 {
                let leftEmitter = BulletEmitter(pattern: .aimed, count: 1,
                                                speed: 275 + Double(currentBoss.phase) * 18,
                                                damage: 10 * activeEnemyDamageMultiplier,
                                                radius: 5.5, lifetime: 5.5, tint: rgb(255, 124, 188),
                                                bulletType: .aimed,
                                                modifiers: [.constantVelocity, .homing, .lockDirection],
                                                homingDuration: 0.55, maxTurnRate: 0.95)
                emitPattern(leftEmitter, from: currentBoss.position + Vec2(x: -102, y: 18), target: player)
            }
            if currentBoss.rightTurretHealth > 0, currentBoss.attackPatternIndex % 2 == 1 {
                let rightEmitter = BulletEmitter(pattern: .spread, count: 3,
                                                 speed: 220 + Double(currentBoss.phase) * 16,
                                                 damage: 9 * activeEnemyDamageMultiplier,
                                                 radius: 5.5, lifetime: 5.5, tint: rgb(255, 164, 108),
                                                 bulletType: .normal,
                                                 modifiers: [.constantVelocity, .lockDirection], spread: 0.22)
                emitPattern(rightEmitter, from: currentBoss.position + Vec2(x: 102, y: 18))
            }
            currentBoss.attackPatternIndex += 1
            currentBoss.attackPrimed = false
        }
        let bossCollisionDistance = coreRadius + 52
        if distanceSquared(player, currentBoss.position) < bossCollisionDistance * bossCollisionDistance { damagePlayer(amount: 35) }
        boss = currentBoss
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
        let left = boss.position + Vec2(x: -102, y: 18)
        let right = boss.position + Vec2(x: 102, y: 18)
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
                    let finalDamage = bullets[index].damage * (critical ? criticalMultiplier : 1.0) * (thunderOverloadTime > 0 ? 1.45 : 1.0) * (overloadMatrixActive ? 1.12 : 1.0)
                    let hitPosition: Vec2
                    switch hitPart {
                    case .leftTurret:
                        currentBoss.leftTurretHealth = max(0, currentBoss.leftTurretHealth - finalDamage)
                        currentBoss.health -= finalDamage * 0.45
                        hitPosition = currentBoss.position + Vec2(x: -102, y: 18)
                        if currentBoss.leftTurretHealth <= 0 {
                            notifyPickup(title: "BOSS TURRET DESTROYED", detail: "Left weapon disabled", tint: rgb(255, 188, 112))
                            spawnExplosion(at: hitPosition, tint: rgb(255, 188, 112), count: 22)
                            addCameraShake(strength: 6)
                        }
                    case .rightTurret:
                        currentBoss.rightTurretHealth = max(0, currentBoss.rightTurretHealth - finalDamage)
                        currentBoss.health -= finalDamage * 0.45
                        hitPosition = currentBoss.position + Vec2(x: 102, y: 18)
                        if currentBoss.rightTurretHealth <= 0 {
                            notifyPickup(title: "BOSS TURRET DESTROYED", detail: "Right weapon disabled", tint: rgb(255, 188, 112))
                            spawnExplosion(at: hitPosition, tint: rgb(255, 188, 112), count: 22)
                            addCameraShake(strength: 6)
                        }
                    case .core:
                        currentBoss.health -= finalDamage
                        hitPosition = currentBoss.position
                    }
                    boss = currentBoss
                    addDamageNumber(at: hitPosition, amount: Int(finalDamage), critical: critical)
                    spawnHit(at: bullets[index].position, tint: rgb(255, 225, 122))
                    if bullets[index].weaponStyle == WeaponType.missile.rawValue {
                        spawnExplosion(at: bullets[index].position, tint: rgb(255, 133, 92), count: 12)
                        addCameraShake(strength: 3.5)
                    } else if bullets[index].weaponStyle == WeaponType.electromagnetic.rawValue {
                        spawnHit(at: bullets[index].position, tint: rgb(191, 133, 255))
                    }
                    if critical { addCameraShake(strength: 2.5) }
                    if critical, stormCoreActive { thunderEnergy = min(100, thunderEnergy + 4) }
                    if laserTime > 0 || bullets[index].pierceRemaining > 0 {
                        if laserTime <= 0 { bullets[index].pierceRemaining -= 1 }
                        bullets[index].position = bullets[index].position + bullets[index].velocity.normalized * 28
                    } else {
                        removeBullet = true
                    }
                    if currentBoss.health <= 0 {
                        registerBossDefeat(at: currentBoss.position)
                        spawnExplosion(at: currentBoss.position, tint: rgb(244, 104, 255), count: 55)
                        boss = nil
                    }
                } else {
                    for enemyIndex in enemies.indices.reversed() {
                        let hitDistance = bullets[index].radius + enemies[enemyIndex].radius
                        if distanceSquared(bullets[index].position, enemies[enemyIndex].position) < hitDistance * hitDistance {
                            let critical = Double.random(in: 0...1, using: &rng) < criticalChance
                            let shieldMultiplier = isEnemyProtected(enemyIndex) ? 0.55 : 1.0
                            let finalDamage = bullets[index].damage * (critical ? criticalMultiplier : 1.0) * (thunderOverloadTime > 0 ? 1.45 : 1.0) * shieldMultiplier
                            enemies[enemyIndex].health -= finalDamage
                            addDamageNumber(at: bullets[index].position, amount: Int(finalDamage), critical: critical)
                            spawnHit(at: bullets[index].position, tint: rgb(255, 225, 122))
                            if bullets[index].weaponStyle == WeaponType.missile.rawValue {
                                spawnExplosion(at: bullets[index].position, tint: rgb(255, 133, 92), count: 10)
                                addCameraShake(strength: 3.0)
                            } else if bullets[index].weaponStyle == WeaponType.electromagnetic.rawValue {
                                spawnHit(at: bullets[index].position, tint: rgb(191, 133, 255))
                            }
                            if critical { addCameraShake(strength: 1.8) }
                            if critical, stormCoreActive { thunderEnergy = min(100, thunderEnergy + 4) }
                            if laserTime > 0 || bullets[index].pierceRemaining > 0 {
                                if laserTime <= 0 { bullets[index].pierceRemaining -= 1 }
                                bullets[index].position = bullets[index].position + bullets[index].velocity.normalized * 28
                            } else {
                                removeBullet = true
                            }
                            if enemies[enemyIndex].health <= 0 {
                                let defeated = enemies[enemyIndex]
                                enemies.remove(at: enemyIndex)
                                registerKill(at: defeated.position, tint: defeated.tint, baseScore: 100 + stage * 15, radius: defeated.radius)
                                if Int.random(in: 0...4, using: &rng) == 0 {
                                    if powerUps.count < 18 {
                                        powerUps.append(PowerUp(position: defeated.position,
                                                                 kind: Int.random(in: 0...2, using: &rng),
                                                                 life: 12))
                                    }
                                }
                                spawnExplosion(at: defeated.position, tint: defeated.tint, count: defeated.radius > 18 ? 24 : 14)
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
                if distanceToCoreSquared < hitDistance * hitDistance, reflectorTime > 0 {
                    bullets[index].playerOwned = true
                    bullets[index].velocity = bullets[index].velocity * -1.12
                    bullets[index].damage *= 2.2
                    bullets[index].tint = rgb(127, 231, 255)
                    bullets[index].life = 2.4
                    bullets[index].position = bullets[index].position + bullets[index].velocity.normalized * 14
                    spawnHit(at: player, tint: rgb(127, 231, 255))
                } else if distanceToCoreSquared < hitDistance * hitDistance {
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
            laserTime = max(laserTime, 10)
            score += 300
            notifyPickup(title: "LASER CANNON ONLINE", detail: "Piercing shots • 10 seconds", tint: rgb(89, 236, 255))
        case 1:
            reflectorTime = max(reflectorTime, 8)
            score += 280
            notifyPickup(title: "REFLECTOR SHIELD", detail: "Invincible + bounce bullets • 8 seconds", tint: rgb(126, 196, 255))
        default:
            spreadTime = max(spreadTime, 12)
            score += 240
            notifyPickup(title: "BULLET ARRAY", detail: "+2 side projectiles per volley • 12 seconds", tint: rgb(255, 214, 110))
        }
    }

    private func damagePlayer(amount: Double) {
        guard reflectorTime <= 0, playerInvulnerability <= 0 else { return }
        if armorShieldCharges > 0 {
            armorShieldCharges -= 1
            playerInvulnerability = 0.72
            notifyPickup(title: "ARMOR SHIELD ABSORBED", detail: "\(armorShieldCharges) charge(s) remaining", tint: rgb(122, 232, 204))
            spawnHit(at: player, tint: rgb(122, 232, 204))
            addCameraShake(strength: 2.5)
            return
        }
        health -= amount * (1.0 - armorDamageReduction)
        playerInvulnerability = 0.50
        combo = max(0, combo - 5)
        comboTimer = 0
        thunderEnergy = max(0, thunderEnergy - 10)
        addCameraShake(strength: 5)
        spawnHit(at: player, tint: rgb(255, 105, 132))
    }

    private func notifyPickup(title: String, detail: String, tint: COLORREF) {
        if language == .chinese {
            let translatedTitle: String
            let translatedDetail: String
            switch title {
            case "LASER CANNON ONLINE":
                translatedTitle = "激光炮已上线"
                translatedDetail = "穿透射击 • 持续 10 秒"
            case "REFLECTOR SHIELD":
                translatedTitle = "反射护盾"
                translatedDetail = "无敌并反弹子弹 • 持续 8 秒"
            case "BULLET ARRAY":
                translatedTitle = "弹幕阵列"
                translatedDetail = "每轮增加 2 发侧翼子弹 • 持续 12 秒"
            case "THUNDER OVERLOAD":
                translatedTitle = "雷霆超载"
                translatedDetail = "火力强化与免疫 • 持续 6 秒"
            case "BOSS REWARD CACHE":
                translatedTitle = "Boss 奖励缓存"
                if detail == "Boss materials secured" {
                    translatedDetail = "Boss 材料已收集"
                } else if detail.hasPrefix("RARE MODULE CACHE  •  ") {
                    let rawName = detail.replacingOccurrences(of: "RARE MODULE CACHE  •  ", with: "")
                    let localizedName: String
                    switch rawName {
                    case "NOVA MISSILE": localizedName = "新星导弹"
                    case "FROST PLATING": localizedName = "寒霜装甲"
                    case "STORM DRONE": localizedName = "风暴僚机"
                    default: localizedName = rawName
                    }
                    translatedDetail = "稀有模块缓存 •  \(localizedName)"
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
                translatedTitle = "Boss 炮塔已摧毁"
                translatedDetail = detail.hasPrefix("Left") ? "左侧武器已禁用" : "右侧武器已禁用"
            case "BOSS LASER":
                translatedTitle = "Boss 激光预警"
                translatedDetail = "远离标记航道"
            default:
                if title.hasPrefix("ACHIEVEMENT UNLOCKED: ") {
                    translatedTitle = "成就已解锁：" + title.replacingOccurrences(of: "ACHIEVEMENT UNLOCKED: ", with: "")
                    translatedDetail = detail
                } else if title.hasPrefix("WEAPON SELECTED: ") {
                    translatedTitle = "已选择武器：" + title.replacingOccurrences(of: "WEAPON SELECTED: ", with: "")
                    translatedDetail = detail
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
                    case "SYNERGY ONLINE: FLIGHT ARRAY": translatedDetail = "超频驱动现在会增加辅助子弹"
                    case "SYNERGY ONLINE: STORM CRIT": translatedDetail = "暴击现在会充能雷霆能量"
                    case "SYNERGY ONLINE: OVERLOAD MATRIX": translatedDetail = "激光与雷霆伤害获得终极增幅"
                    default: translatedDetail = detail
                    }
                } else if title.hasPrefix("BOSS PHASE ") {
                    translatedTitle = "Boss 阶段 " + title.replacingOccurrences(of: "BOSS PHASE ", with: "")
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
        guard phase == .playing, thunderEnergy >= 100 else { return }
        thunderEnergy = 0
        thunderOverloadTime = 6.0
        playerInvulnerability = 6.0
        clearEnemyBullets()
        let cleared = enemies.count
        for enemy in enemies { spawnExplosion(at: enemy.position, tint: rgb(95, 224, 255), count: 8) }
        enemies.removeAll(keepingCapacity: true)
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
        if var currentBoss = boss {
            currentBoss.health -= damage * 12
            boss = currentBoss
            addDamageNumber(at: currentBoss.position, amount: Int(damage * 12), critical: true)
            if currentBoss.health <= 0 {
                registerBossDefeat(at: currentBoss.position)
                spawnExplosion(at: currentBoss.position, tint: rgb(244, 104, 255), count: 55)
                boss = nil
            }
        }
        addCameraShake(strength: 16)
        spawnExplosion(at: player, tint: rgb(89, 236, 255), count: 42)
        notifyPickup(title: "THUNDER OVERLOAD", detail: "6 seconds of amplified fire and immunity", tint: rgb(106, 239, 255))
    }

    private func registerKill(at position: Vec2, tint: COLORREF, baseScore: Int, radius: Double) {
        kills += 1
        let credits = scaledReward(5 + stage)
        let alloy = scaledReward(2 + stage / 2)
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
        let multiplier = 1.0 + min(Double(combo), 50.0) * 0.015
        score += Int(Double(baseScore) * multiplier * comboScoreMultiplier)
        experience += 1
        thunderEnergy = min(100, thunderEnergy + (5.0 + min(Double(combo), 20.0) * 0.20) * thunderGainMultiplier)
        addCameraShake(strength: radius > 18 ? 3.2 : 1.1)
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
            profile.inventory.append(EquipmentState(id: "boss_\(bossDefeats)_\(dropIndex)",
                                                     name: dropNames[dropIndex],
                                                     slot: dropSlots[dropIndex],
                                                     level: 1,
                                                     rarity: dropRarity,
                                                     stars: 1,
                                                     evolution: 0,
                                                     affix: Int.random(in: 1...4, using: &rng)))
            dropDetail = "RARE MODULE CACHE  •  \(dropNames[dropIndex])"
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
        stageBannerTitle = uiText("BOSS DOWN", "Boss 已击破")
        stageBannerDetail = uiText("REWARD CACHE  •  +\(experienceReward) XP  •  HULL REPAIRED",
                                   "奖励缓存  •  +\(experienceReward) 经验  •  机体已修复")
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
        let multipliers = [0.0, 0.45, 1.0, 1.35]
        let multiplier = multipliers[min(3, max(0, profile.cameraShake))]
        guard multiplier > 0 else { return }
        let adjusted = strength * multiplier
        cameraShakeStrength = min(22, max(cameraShakeStrength, adjusted))
        cameraShakeTime = min(0.45, max(cameraShakeTime, adjusted > 10 ? 0.35 : 0.18))
    }

    private func updateCameraShake(delta: Double) {
        cameraShakeTime = max(0, cameraShakeTime - delta)
        cameraShakeStrength = max(0, cameraShakeStrength - delta * 38)
    }

    func currentShakeOffset() -> Vec2 {
        guard cameraShakeTime > 0, cameraShakeStrength > 0 else { return .zero }
        return Vec2(x: Double.random(in: -cameraShakeStrength...cameraShakeStrength, using: &rng),
                    y: Double.random(in: -cameraShakeStrength...cameraShakeStrength, using: &rng))
    }

    // Experience is an upgrade-charge meter, not a player-level system.
    // Reaching the current threshold opens the three-choice upgrade screen;
    // there is deliberately no level counter or level cap to gate growth.
    private func checkForUpgradeReady() {
        guard phase == .playing, experience >= experienceGoal else { return }
        experience -= experienceGoal
        experienceGoal = Int(Double(experienceGoal) * 1.32) + 3
        let pool = Array(0...11)
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
        phase = .upgrade
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
        notifyPickup(title: definition.englishTitle, detail: definition.englishDetail,
                     tint: definition.id == "frost_ray" ? rgb(137, 228, 255) : (definition.id == "flight_array" ? rgb(255, 220, 120) : rgb(187, 172, 255)))
    }

    func chooseUpgrade(_ index: Int) {
        guard phase == .upgrade, upgradeOptions.indices.contains(index) else { return }
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
            hasLaserCore = true
            laserWidthLevel += max(1, Int(scale.rounded(.down)))
            projectileDamageMultiplier += 0.05 * scale
        case 8:
            hasCryoCore = true
            laserWidthLevel += max(1, Int(scale.rounded(.down)))
            projectileDamageMultiplier += 0.04 * scale
        case 9:
            hasThunderCore = true
            thunderGainMultiplier = min(3.0, thunderGainMultiplier + 0.10 * scale)
        case 10:
            hasArrayCore = true
            projectileCountBonus = min(3, projectileCountBonus + 1)
        default:
            comboScoreMultiplier = min(2.5, comboScoreMultiplier + 0.08 * scale)
        }
        phase = .playing
        let newlyActivated = activeSynergyIDs.subtracting(previousSynergies)
        if newlyActivated.isEmpty {
            notifyPickup(title: option.title, detail: option.detail, tint: rarityColor(rarity))
        } else {
            announceNewSynergies(previous: previousSynergies)
        }
        AudioManager.shared.playSFX("sfx_upgrade")
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

    func setControlMode(_ mode: ControlMode) {
        controlMode = mode
        profile.controlMode = mode.rawValue
        persistProfile()
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
    }

    func cycleVaultSort() {
        vaultSortMode = (vaultSortMode + 1) % 3
        vaultPage = 0
    }

    func moveVaultPage(_ delta: Int) {
        vaultPage = min(max(0, vaultPage + delta), vaultPageCount - 1)
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

    func togglePause() {
        if phase == .playing { phase = .paused }
        else if phase == .paused { phase = .playing }
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
        controlMode = ControlMode(rawValue: profile.controlMode) ?? .wasd
        if let hwnd = WindowRuntime.hwnd {
            _ = PostMessageW(hwnd, WindowRuntime.displayModeMessage, 0, 0)
        }
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
        // Defer the native style/resize operation until the click message has
        // returned. Changing a window while handling WM_LBUTTONDOWN can
        // synchronously re-enter painting on some Windows builds and make the
        // callback unstable.
        if let hwnd = WindowRuntime.hwnd {
            _ = PostMessageW(hwnd, WindowRuntime.displayModeMessage, 0, 0)
        }
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
        if let hwnd = WindowRuntime.hwnd {
            _ = PostMessageW(hwnd, WindowRuntime.displayModeMessage, 0, 0)
        }
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
            else if buttons[4].contains(point) { PostQuitMessage(0) }
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
                if codexPrevButton(width: width, height: height).contains(point) { codexPage = max(0, codexPage - 1) }
                else if codexNextButton(width: width, height: height).contains(point) { codexPage += 1 }
            }
            if archiveBackButton(width: width, height: height).contains(point) { phase = .menu }
        case .controls:
            let modes = controlModeButtons(width: width, height: height)
            if modes[0].contains(point) { setControlMode(.wasd) }
            else if modes[1].contains(point) { setControlMode(.mouse) }
            else if controlsBackButton(width: width, height: height).contains(point) { phase = phaseBeforeControls }
        case .settings:
            let languages = settingsLanguageButtons(width: width, height: height)
            if languages[0].contains(point) { selectLanguage(.english) }
            else if languages[1].contains(point) { selectLanguage(.chinese) }
            else if settingsBGMButton(width: width, height: height).contains(point) { cycleBGMVolume() }
            else if settingsSFXButton(width: width, height: height).contains(point) { cycleSFXVolume() }
            else if settingsShakeButton(width: width, height: height).contains(point) { cycleCameraShake() }
            else if settingsWindowModeButton(width: width, height: height).contains(point) { cycleWindowMode() }
            else if settingsResolutionButton(width: width, height: height).contains(point) { cycleResolution() }
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
                    if equipmentPromoteButton(index, width: width, height: height).contains(point) {
                        promoteEquipment(index)
                    } else {
                        upgradeEquipment(index)
                    }
                    break
                }
            } else {
                if vaultFilterButton(width: width, height: height).contains(point) { cycleVaultFilter(); return }
                if vaultSortButton(width: width, height: height).contains(point) { cycleVaultSort(); return }
                if vaultPrevButton(width: width, height: height).contains(point) { moveVaultPage(-1); return }
                if vaultNextButton(width: width, height: height).contains(point) { moveVaultPage(1); return }
                let visible = visibleVaultIndices
                for (cardIndex, card) in vaultCards(width: width, height: height).enumerated() where card.contains(point) {
                    let absoluteIndex = vaultPage * 4 + cardIndex
                    if visible.indices.contains(absoluteIndex) { equipInventoryItem(visible[absoluteIndex]) }
                    break
                }
            }
            if hangarBackButton(width: width, height: height).contains(point) { phase = .menu }
        case .paused:
            let buttons = pauseButtons(width: width, height: height)
            if buttons[0].contains(point) { phase = .playing }
            else if buttons[1].contains(point) { start(width: width, height: height) }
            else if buttons[2].contains(point) { openControls(from: .paused) }
            else if buttons[3].contains(point) { phase = .menu }
            else if buttons[4].contains(point) { PostQuitMessage(0) }
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
            guard !musicIsPlaying, bgmVolume > 0 else { return nil }
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

// MARK: - Win32 drawing helpers

nonisolated(unsafe) private var injectedKeyboardState: Set<Int32>?

func setInjectedKeyboardState(_ keys: Set<Int32>?) {
    injectedKeyboardState = keys
}

func keyDown(_ key: Int32) -> Bool {
    if let injectedKeyboardState {
        return injectedKeyboardState.contains(key)
    }
    return GetAsyncKeyState(key) < 0
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

// GDI object creation is surprisingly expensive on Windows. The renderer
// draws hundreds of circles/polygons per frame, so creating and destroying a
// brush for every primitive causes visible stutter and eventually exhausts
// the per-process GDI handle budget. Keep a small quantized palette alive and
// reuse it across frames. Quantization keeps particle fade colors from
// creating thousands of one-off brushes while remaining visually identical at
// the game's small sprite sizes.
final class GDIBrushCache: @unchecked Sendable {
    static let shared = GDIBrushCache()

    private let capacity = 512
    private var brushes: [COLORREF: HBRUSH] = [:]
    private var insertionOrder: [COLORREF] = []

    private init() {}

    private func quantized(_ color: COLORREF) -> COLORREF {
        let r = UInt32(color & 0xFF)
        let g = UInt32((color >> 8) & 0xFF)
        let b = UInt32((color >> 16) & 0xFF)
        // 32-step channels cap the palette at 729 colors and make fading
        // particles share brushes. Keep full white available for UI accents.
        func q(_ value: UInt32) -> UInt32 {
            value >= 248 ? 255 : (value / 32) * 32
        }
        return rgb(q(r), q(g), q(b))
    }

    func brush(for color: COLORREF) -> HBRUSH? {
        let key = quantized(color)
        if let cached = brushes[key] { return cached }
        guard let created = CreateSolidBrush(key) else { return nil }
        brushes[key] = created
        insertionOrder.append(key)
        if insertionOrder.count > capacity {
            let expired = insertionOrder.removeFirst()
            if let old = brushes.removeValue(forKey: expired) {
                _ = DeleteObject(HGDIOBJ(old))
            }
        }
        return created
    }

    func release() {
        for brush in brushes.values {
            _ = DeleteObject(HGDIOBJ(brush))
        }
        brushes.removeAll(keepingCapacity: true)
        insertionOrder.removeAll(keepingCapacity: true)
    }
}

func withBrush<T>(_ color: COLORREF, _ body: (HBRUSH?) -> T) -> T {
    body(GDIBrushCache.shared.brush(for: color))
}

func fill(_ hdc: HDC?, _ rect: RECT, _ color: COLORREF) {
    var mutableRect = rect
    withBrush(color) { brush in _ = FillRect(hdc, &mutableRect, brush) }
}

func circle(_ hdc: HDC?, center: Vec2, radius: Double, color: COLORREF) {
    let rect = RECT(left: LONG(center.x - radius), top: LONG(center.y - radius),
                    right: LONG(center.x + radius), bottom: LONG(center.y + radius))
    if radius <= 3.0 {
        fill(hdc, rect, color)
        return
    }
    withBrush(color) { brush in
        let previous = SelectObject(hdc, HGDIOBJ(brush))
        _ = Ellipse(hdc, rect.left, rect.top, rect.right, rect.bottom)
        if let previous { _ = SelectObject(hdc, previous) }
    }
}

func polygon(_ hdc: HDC?, _ points: [POINT], _ color: COLORREF) {
    withBrush(color) { brush in
        let previous = SelectObject(hdc, HGDIOBJ(brush))
        points.withUnsafeBufferPointer { buffer in
            _ = Polygon(hdc, buffer.baseAddress, Int32(points.count))
        }
        if let previous { _ = SelectObject(hdc, previous) }
    }
}

func drawText(_ hdc: HDC?, _ text: String, _ rect: RECT, _ color: COLORREF, _ size: Int32 = 18, _ align: Int32 = DT_LEFT) {
    var mutableRect = rect
    _ = SetTextColor(hdc, color)
    var chars = wide(text)
    chars.withUnsafeMutableBufferPointer { buffer in
        _ = DrawTextW(hdc, buffer.baseAddress, -1, &mutableRect, UINT(align | DT_VCENTER | DT_SINGLELINE))
    }
    _ = size // Keep the renderer dependency-free; the stock font scales with Windows DPI.
}

func drawWorldFrame(_ hdc: HDC?, width: Double, height: Double) {
    let game = Game.shared
    let field = playfieldBounds(width: width, height: height)
    fill(hdc, RECT(left: 0, top: 0, right: LONG(width), bottom: LONG(height)), rgb(7, 11, 27))

    // Scrolling starfield and faint vertical flight lanes.
    for star in game.stars { circle(hdc, center: star.position, radius: star.radius, color: star.tint) }
    for lane in stride(from: field.left + 70.0, through: field.right, by: 86.0) {
        fill(hdc, RECT(left: LONG(lane), top: LONG(field.top), right: LONG(lane + 1), bottom: LONG(field.bottom)), rgb(11, 23, 46))
    }

    fill(hdc, RECT(left: 0, top: 0, right: LONG(width), bottom: 68), rgb(18, 27, 55))
    drawText(hdc, game.uiText("THUNDER SWIFT", "雷霆战机"), RECT(left: 18, top: 5, right: 240, bottom: 35), rgb(224, 240, 255), 19)
    drawText(hdc, game.uiText("STAGE \(game.stage)", "阶段 \(game.stage)"), RECT(left: 255, top: 5, right: 360, bottom: 35), rgb(126, 190, 255), 15)
    if game.combo > 1 { drawText(hdc, game.uiText("COMBO x\(game.combo)", "连击 x\(game.combo)"), RECT(left: 370, top: 5, right: 475, bottom: 35), rgb(255, 181, 91), 14) }
    let fpsValue = Int(game.measuredFPS.rounded())
    let fpsColor = fpsValue >= 56 ? rgb(104, 232, 177) : (fpsValue >= 45 ? rgb(255, 211, 112) : rgb(255, 116, 132))
    drawText(hdc, "FPS \(fpsValue)", RECT(left: 480, top: 5, right: 560, bottom: 35), fpsColor, 12, DT_RIGHT)
    drawText(hdc, game.uiText("KILLS \(game.kills)", "击杀 \(game.kills)"), RECT(left: LONG(width - 420), top: 5, right: LONG(width - 245), bottom: 35), rgb(235, 187, 255), 14, DT_RIGHT)
    drawText(hdc, game.uiText("SCORE \(game.score)", "分数 \(game.score)"), RECT(left: LONG(width - 230), top: 5, right: LONG(width - 18), bottom: 35), rgb(255, 219, 125), 16, DT_RIGHT)
    if game.activeKillGoal > 0 {
        drawText(hdc, game.uiText("TARGET \(game.kills)/\(game.activeKillGoal)", "目标 \(game.kills)/\(game.activeKillGoal)"),
                 RECT(left: LONG(width - 230), top: 32, right: LONG(width - 18), bottom: 50), rgb(255, 164, 112), 10, DT_RIGHT)
    }

    fill(hdc, RECT(left: 18, top: 47, right: 218, bottom: 58), rgb(61, 28, 53))
    let hpWidth = LONG(200 * max(0, game.health) / max(1, game.maxHealth))
    fill(hdc, RECT(left: 18, top: 47, right: 18 + hpWidth, bottom: 58), rgb(239, 70, 105))
    drawText(hdc, game.uiText("HP \(Int(game.health))/\(Int(game.maxHealth))", "生命 \(Int(game.health))/\(Int(game.maxHealth))"), RECT(left: 22, top: 40, right: 215, bottom: 62), rgb(255, 244, 247), 12)
    drawText(hdc,
             game.uiText("\(game.weaponType.label)  LV \(game.weaponLevel)  \(game.weaponEvolutionLabel(for: .english))  PEN \(game.projectilePenetration)",
                         "\(game.weaponType.label(for: .chinese))  等级 \(game.weaponLevel)  \(game.weaponEvolutionLabel(for: .chinese))  穿透 \(game.projectilePenetration)"),
             RECT(left: 245, top: 40, right: 450, bottom: 62), rgb(138, 229, 255), 11)
    drawText(hdc, game.uiText("THUNDER", "雷霆"), RECT(left: 470, top: 39, right: 548, bottom: 62), rgb(106, 239, 255), 11)
    fill(hdc, RECT(left: 548, top: 48, right: 640, bottom: 58), rgb(19, 57, 79))
    let energyWidth = LONG(92 * max(0, min(100, game.thunderEnergy)) / 100)
    fill(hdc, RECT(left: 548, top: 48, right: 548 + energyWidth, bottom: 58), rgb(78, 222, 255))
    drawText(hdc, "\(Int(game.thunderEnergy))%", RECT(left: 548, top: 39, right: 640, bottom: 62), rgb(228, 251, 255), 11, DT_RIGHT)
    var statusX: LONG = 650
    if game.laserTime > 0 {
        drawText(hdc, game.uiText("LASER \(Int(ceil(game.laserTime)))s", "激光 \(Int(ceil(game.laserTime)))秒"),
                 RECT(left: statusX, top: 40, right: statusX + 105, bottom: 62), rgb(91, 236, 255), 12)
        statusX += 112
    }
    if game.reflectorTime > 0 {
        drawText(hdc, game.uiText("REFLECT \(Int(ceil(game.reflectorTime)))s", "反射 \(Int(ceil(game.reflectorTime)))秒"),
                 RECT(left: statusX, top: 40, right: statusX + 125, bottom: 62), rgb(126, 196, 255), 12)
        statusX += 132
    }
    if game.spreadTime > 0 {
        drawText(hdc, game.uiText("ARRAY \(Int(ceil(game.spreadTime)))s", "阵列 \(Int(ceil(game.spreadTime)))秒"),
                 RECT(left: statusX, top: 40, right: statusX + 110, bottom: 62), rgb(255, 214, 110), 12)
        statusX += 116
    }
    if game.frostRayActive {
        drawText(hdc, game.uiText("FROST RAY", "寒霜射线"), RECT(left: statusX, top: 40, right: statusX + 98, bottom: 62), rgb(151, 232, 255), 12)
        statusX += 104
    } else if game.arrayOverdriveActive {
        drawText(hdc, game.uiText("FLIGHT ARRAY", "飞行阵列"), RECT(left: statusX, top: 40, right: statusX + 112, bottom: 62), rgb(255, 221, 121), 12)
        statusX += 118
    }
    if game.precisionMode { drawText(hdc, game.uiText("PRECISION", "精准模式"), RECT(left: statusX, top: 40, right: statusX + 95, bottom: 62), rgb(255, 229, 112), 12) }

    if let boss = game.boss {
        fill(hdc, RECT(left: LONG(width / 2 - 220), top: 72, right: LONG(width / 2 + 220), bottom: 84), rgb(56, 24, 67))
        let bossWidth = LONG(440 * max(0, boss.health) / max(1, boss.maxHealth))
        fill(hdc, RECT(left: LONG(width / 2 - 220), top: 72, right: LONG(width / 2 - 220) + bossWidth, bottom: 84), rgb(226, 71, 226))
        let bossName = (BossType(rawValue: boss.kind) ?? .dreadnought).title(for: game.language)
        drawText(hdc, game.uiText("\(bossName)  //  PHASE \(boss.phase)", "\(bossName)  //  阶段 \(boss.phase)"),
                 RECT(left: LONG(width / 2 - 210), top: 70, right: LONG(width / 2 + 210), bottom: 86), rgb(255, 225, 255), 12, DT_CENTER)
    }

    for powerUp in game.powerUps {
        let color = powerUpTint(powerUp.kind)
        let points = [POINT(x: LONG(powerUp.position.x), y: LONG(powerUp.position.y - 13)),
                      POINT(x: LONG(powerUp.position.x + 13), y: LONG(powerUp.position.y)),
                      POINT(x: LONG(powerUp.position.x), y: LONG(powerUp.position.y + 13)),
                      POINT(x: LONG(powerUp.position.x - 13), y: LONG(powerUp.position.y))]
        polygon(hdc, points, color)
        circle(hdc, center: powerUp.position, radius: 4, color: rgb(248, 251, 255))
        drawText(hdc, powerUpLabel(powerUp.kind), RECT(left: LONG(powerUp.position.x - 12), top: LONG(powerUp.position.y - 7), right: LONG(powerUp.position.x + 12), bottom: LONG(powerUp.position.y + 7)), rgb(17, 33, 60), 10, DT_CENTER)
    }

    if game.notificationTimer > 0 {
        drawPickupNotification(hdc, width: width, game: game)
    }
    if game.stageBannerTimer > 0 {
        drawStageBanner(hdc, width: width, game: game)
    }

    for enemy in game.enemies { drawEnemy(hdc, enemy, field: field) }
    if let boss = game.boss { drawBoss(hdc, boss, field: field, language: game.language) }
    for bullet in game.bullets {
        if bullet.playerOwned {
            if bullet.weaponStyle == WeaponType.missile.rawValue {
                circle(hdc, center: bullet.position, radius: bullet.radius + 4, color: rgb(116, 47, 64))
                circle(hdc, center: bullet.position, radius: bullet.radius, color: bullet.tint)
                fill(hdc, RECT(left: LONG(bullet.position.x - 2), top: LONG(bullet.position.y + 6),
                               right: LONG(bullet.position.x + 2), bottom: LONG(bullet.position.y + 15)), rgb(255, 220, 108))
            } else if bullet.weaponStyle == WeaponType.electromagnetic.rawValue {
                circle(hdc, center: bullet.position, radius: bullet.radius + 5, color: rgb(61, 38, 111))
                circle(hdc, center: bullet.position, radius: bullet.radius, color: bullet.tint)
                circle(hdc, center: bullet.position, radius: 2.5, color: rgb(240, 224, 255))
            } else {
                fill(hdc, RECT(left: LONG(bullet.position.x - 3), top: LONG(bullet.position.y - 13),
                               right: LONG(bullet.position.x + 3), bottom: LONG(bullet.position.y + 13)), rgb(39, 99, 174))
                fill(hdc, RECT(left: LONG(bullet.position.x - 2), top: LONG(bullet.position.y - 10),
                               right: LONG(bullet.position.x + 2), bottom: LONG(bullet.position.y + 10)), bullet.tint)
            }
        } else {
            switch BulletType(rawValue: bullet.bulletType) ?? .normal {
            case .aimed:
                circle(hdc, center: bullet.position, radius: bullet.radius + 5, color: rgb(96, 31, 70))
                circle(hdc, center: bullet.position, radius: bullet.radius, color: bullet.tint)
                circle(hdc, center: bullet.position, radius: 2, color: rgb(255, 238, 193))
            case .boss:
                circle(hdc, center: bullet.position, radius: bullet.radius + 5, color: rgb(98, 25, 79))
                circle(hdc, center: bullet.position, radius: bullet.radius, color: bullet.tint)
                circle(hdc, center: bullet.position, radius: bullet.radius * 0.35, color: rgb(255, 228, 162))
            default:
                circle(hdc, center: bullet.position, radius: bullet.radius + 3, color: rgb(82, 32, 71))
                circle(hdc, center: bullet.position, radius: bullet.radius, color: bullet.tint)
            }
            if bullet.modifiers.contains(.split) {
                circle(hdc, center: bullet.position, radius: bullet.radius + 8, color: scaleColor(bullet.tint, 0.42))
            }
            if bullet.modifiers.contains(.stopAndGo), bullet.velocity.length < 0.1 {
                circle(hdc, center: bullet.position, radius: bullet.radius + 10, color: rgb(255, 219, 112))
            }
            if bullet.modifiers.contains(.bounce) {
                fill(hdc, RECT(left: LONG(bullet.position.x - 1), top: LONG(bullet.position.y - bullet.radius - 5), right: LONG(bullet.position.x + 1), bottom: LONG(bullet.position.y + bullet.radius + 5)), rgb(255, 199, 132))
            }
        }
    }
    // Explosions can briefly accumulate thousands of particles. Updating all
    // particles keeps the simulation smooth, but drawing every one of them
    // adds no visible value at that density. Adapt the render stride so the
    // visual effect stays bright while GDI work remains bounded.
    let particleStride = max(1, (game.particles.count + 899) / 900)
    for index in stride(from: 0, to: game.particles.count, by: particleStride) {
        let particle = game.particles[index]
        if particle.position.x < -40 || particle.position.x > width + 40 ||
           particle.position.y < -40 || particle.position.y > height + 40 { continue }
        let alpha = max(0.2, particle.life / max(0.01, particle.maxLife))
        let tinted = scaleColor(particle.tint, alpha)
        circle(hdc, center: particle.position, radius: particle.radius, color: tinted)
    }
    // Damage text is the most expensive per-hit draw call. Keep the newest
    // numbers visible, but cap the number of DrawTextW calls during dense
    // waves so combat frame time does not depend on hit count.
    let damageStride = max(1, (game.damageNumbers.count + 35) / 36)
    for index in stride(from: 0, to: game.damageNumbers.count, by: damageStride) {
        let number = game.damageNumbers[index]
        guard number.amount > 0 else { continue }
        let alpha = max(0.25, number.life / max(0.01, number.maxLife))
        let color = number.critical ? rgb(255, 211, 91) : rgb(232, 246, 255)
        drawText(hdc, number.critical
                    ? game.uiText("CRIT \(number.amount)", "暴击 \(number.amount)")
                    : "\(number.amount)",
                 RECT(left: LONG(number.position.x - 48), top: LONG(number.position.y - 10),
                      right: LONG(number.position.x + 48), bottom: LONG(number.position.y + 14)),
                 scaleColor(color, alpha), number.critical ? 14 : 11, DT_CENTER)
    }
    drawPlayer(hdc, game: game)

    // Menus and pause/upgrade panels are drawn by the modern UI layer below.
}

// MARK: - Modern menu UI

func mainMenuButtons(width: Double, height: Double) -> [UIRect] {
    let left = width / 2 - 145
    let top = height / 2 - 80
    var buttons = (0..<5).map { UIRect(x: left, y: top + Double($0) * 54, width: 290, height: 48) }
    buttons.append(UIRect(x: left, y: top + 5 * 54, width: 290, height: 48))
    return buttons
}

func saveSlotButton(width: Double, height: Double) -> UIRect {
    UIRect(x: 28, y: 28, width: 270, height: 92)
}

func saveSlotCards(width: Double, height: Double) -> [UIRect] {
    let left = width / 2 - 350
    return (0..<SaveManager.slotCount).map {
        UIRect(x: left + Double($0) * 235, y: 230, width: 220, height: 190)
    }
}

func saveSlotsBackButton(width: Double, height: Double) -> UIRect {
    UIRect(x: width / 2 - 120, y: height - 92, width: 240, height: 50)
}

func archiveTabButtons(width: Double, height: Double) -> [UIRect] {
    let left = width / 2 - 190
    return [UIRect(x: left, y: 142, width: 180, height: 38),
            UIRect(x: left + 200, y: 142, width: 180, height: 38)]
}

func archiveBackButton(width: Double, height: Double) -> UIRect {
    UIRect(x: width / 2 - 120, y: height - 82, width: 240, height: 50)
}

func codexCategoryButtons(width: Double, height: Double) -> [UIRect] {
    let left = width / 2 - 300
    return (0..<3).map { UIRect(x: left + Double($0) * 205, y: 198, width: 190, height: 32) }
}

func codexPrevButton(width: Double, height: Double) -> UIRect {
    UIRect(x: width / 2 - 300, y: height - 135, width: 120, height: 36)
}

func codexNextButton(width: Double, height: Double) -> UIRect {
    UIRect(x: width / 2 + 180, y: height - 135, width: 120, height: 36)
}

func missionCards(width: Double, height: Double) -> [UIRect] {
    let left = width / 2 - 380
    return (0..<MissionCatalog.all.count).map {
        let row = $0 / 4
        let column = $0 % 4
        return UIRect(x: left + Double(column) * 194, y: 180 + Double(row) * 112, width: 182, height: 100)
    }
}

func modeCards(width: Double, height: Double) -> [UIRect] {
    let left = width / 2 - 380
    return (0..<GameMode.allCases.count).map {
        UIRect(x: left + Double($0) * 194, y: 430, width: 182, height: 82)
    }
}

func missionLaunchButton(width: Double, height: Double) -> UIRect {
    UIRect(x: width / 2 + 20, y: height - 86, width: 180, height: 50)
}

func missionBackButton(width: Double, height: Double) -> UIRect {
    UIRect(x: width / 2 - 200, y: height - 86, width: 180, height: 50)
}

func controlModeButtons(width: Double, height: Double) -> [UIRect] {
    let left = width / 2 - 230
    let top = height / 2 - 36
    return [UIRect(x: left, y: top, width: 220, height: 104),
            UIRect(x: left + 240, y: top, width: 220, height: 104)]
}

func controlsBackButton(width: Double, height: Double) -> UIRect {
    UIRect(x: width / 2 - 120, y: height - 92, width: 240, height: 50)
}

func settingsLanguageButtons(width: Double, height: Double) -> [UIRect] {
    let left = width / 2 - 230
    let top = 220.0
    return [UIRect(x: left, y: top, width: 220, height: 70),
            UIRect(x: left + 240, y: top, width: 220, height: 70)]
}

func settingsBGMButton(width: Double, height: Double) -> UIRect {
    UIRect(x: width / 2 - 230, y: 310, width: 220, height: 52)
}

func settingsSFXButton(width: Double, height: Double) -> UIRect {
    UIRect(x: width / 2 + 10, y: 310, width: 220, height: 52)
}

func settingsShakeButton(width: Double, height: Double) -> UIRect {
    UIRect(x: width / 2 - 230, y: 380, width: 460, height: 52)
}

func settingsWindowModeButton(width: Double, height: Double) -> UIRect {
    UIRect(x: width / 2 - 230, y: 450, width: 460, height: 52)
}

func settingsResolutionButton(width: Double, height: Double) -> UIRect {
    UIRect(x: width / 2 - 230, y: 518, width: 460, height: 52)
}

func settingsBackButton(width: Double, height: Double) -> UIRect {
    UIRect(x: width / 2 - 120, y: height - 92, width: 240, height: 50)
}

func pauseButtons(width: Double, height: Double) -> [UIRect] {
    let left = width / 2 - 145
    let top = height / 2 - 112
    return (0..<5).map { UIRect(x: left, y: top + Double($0) * 62, width: 290, height: 48) }
}

func gameOverButtons(width: Double, height: Double) -> [UIRect] {
    let left = width / 2 - 145
    let top = height / 2 + 62
    return [UIRect(x: left, y: top, width: 290, height: 50),
            UIRect(x: left, y: top + 62, width: 290, height: 50)]
}

func upgradeCards(width: Double, height: Double) -> [UIRect] {
    let left = width / 2 - 350
    let top = height / 2 - 20
    return (0..<3).map { UIRect(x: left + Double($0) * 235, y: top, width: 220, height: 130) }
}

func hangarCards(width: Double, height: Double) -> [UIRect] {
    let left = width / 2 - 350
    let top = 210.0
    return (0..<5).map { index in
        let row = index < 3 ? 0 : 1
        let column = index < 3 ? index : index - 3
        let offset = row == 0 ? 0.0 : 117.5
        return UIRect(x: left + offset + Double(column) * 235,
               y: top + Double(row) * 135,
               width: 220,
               height: 118)
    }
}

func equipmentPromoteButton(_ slot: Int, width: Double, height: Double) -> UIRect {
    let card = hangarCards(width: width, height: height)[min(4, max(0, slot))]
    return UIRect(x: card.x + card.width - 92, y: card.y + 87, width: 78, height: 24)
}

func hangarBackButton(width: Double, height: Double) -> UIRect {
    UIRect(x: width / 2 - 120, y: height - 82, width: 240, height: 50)
}

func hangarTabButtons(width: Double, height: Double) -> [UIRect] {
    let left = width / 2 - 170
    return [UIRect(x: left, y: 180, width: 160, height: 30),
            UIRect(x: left + 180, y: 180, width: 160, height: 30)]
}

func vaultCards(width: Double, height: Double) -> [UIRect] {
    let left = width / 2 - 320
    let top = 210.0
    return (0..<4).map { index in
        UIRect(x: left + Double(index % 2) * 330,
               y: top + Double(index / 2) * 135,
               width: 300,
               height: 118)
    }
}

func vaultFilterButton(width: Double, height: Double) -> UIRect {
    UIRect(x: width / 2 - 320, y: 144, width: 150, height: 30)
}

func vaultSortButton(width: Double, height: Double) -> UIRect {
    UIRect(x: width / 2 - 160, y: 144, width: 150, height: 30)
}

func vaultPrevButton(width: Double, height: Double) -> UIRect {
    UIRect(x: width / 2 + 10, y: 144, width: 90, height: 30)
}

func vaultNextButton(width: Double, height: Double) -> UIRect {
    UIRect(x: width / 2 + 110, y: 144, width: 90, height: 30)
}

func shipCards(width: Double, height: Double) -> [UIRect] {
    let left = width / 2 - 335
    return ShipType.allCases.map { ship in
        UIRect(x: left + Double(ship.rawValue) * 136, y: 490, width: 126, height: 68)
    }
}

func drawSpaceBackground(_ hdc: HDC?, width: Double, height: Double, game: Game) {
    fill(hdc, RECT(left: 0, top: 0, right: LONG(width), bottom: LONG(height)), rgb(6, 10, 25))
    for star in game.stars { circle(hdc, center: star.position, radius: star.radius, color: star.tint) }
    for lane in stride(from: 70.0, through: width, by: 86.0) {
        fill(hdc, RECT(left: LONG(lane), top: 0, right: LONG(lane + 1), bottom: LONG(height)), rgb(10, 20, 40))
    }
    fill(hdc, RECT(left: 0, top: 0, right: LONG(width), bottom: 4), rgb(54, 170, 245))
}

func powerUpLabel(_ kind: Int) -> String {
    switch kind {
    case 0: return "L"
    case 1: return "R"
    default: return "A"
    }
}

func drawPickupNotification(_ hdc: HDC?, width: Double, game: Game) {
    let panel = UIRect(x: width / 2 - 225, y: 94, width: 450, height: 64)
    roundedPanel(hdc, panel, rgb(20, 40, 74))
    drawText(hdc, game.notificationTitle, RECT(left: LONG(panel.x + 16), top: LONG(panel.y + 5), right: LONG(panel.x + panel.width - 16), bottom: LONG(panel.y + 30)), game.notificationTint, 15, DT_CENTER)
    drawText(hdc, game.notificationDetail, RECT(left: LONG(panel.x + 16), top: LONG(panel.y + 30), right: LONG(panel.x + panel.width - 16), bottom: LONG(panel.y + 52)), rgb(217, 235, 255), 11, DT_CENTER)
    let progress = min(1.0, game.notificationTimer / 3.2)
    fill(hdc, RECT(left: LONG(panel.x + 20), top: LONG(panel.y + 56), right: LONG(panel.x + 20 + (panel.width - 40) * progress), bottom: LONG(panel.y + 59)), game.notificationTint)
}

func drawStageBanner(_ hdc: HDC?, width: Double, game: Game) {
    let panel = UIRect(x: width / 2 - 250, y: 182, width: 500, height: 78)
    roundedPanel(hdc, panel, rgb(28, 29, 66))
    drawText(hdc, game.stageBannerTitle,
             RECT(left: LONG(panel.x + 18), top: LONG(panel.y + 8), right: LONG(panel.x + panel.width - 18), bottom: LONG(panel.y + 36)),
             rgb(255, 213, 112), 18, DT_CENTER)
    drawText(hdc, game.stageBannerDetail,
             RECT(left: LONG(panel.x + 18), top: LONG(panel.y + 37), right: LONG(panel.x + panel.width - 18), bottom: LONG(panel.y + 61)),
             rgb(210, 231, 255), 11, DT_CENTER)
    let progress = min(1.0, game.stageBannerTimer / 3.4)
    fill(hdc, RECT(left: LONG(panel.x + 22), top: LONG(panel.y + 68), right: LONG(panel.x + 22 + (panel.width - 44) * progress), bottom: LONG(panel.y + 71)), rgb(255, 151, 108))
}

func roundedPanel(_ hdc: HDC?, _ rect: UIRect, _ color: COLORREF) {
    withBrush(color) { brush in
        let previous = SelectObject(hdc, HGDIOBJ(brush))
        let r = rect.winRect
        _ = RoundRect(hdc, r.left, r.top, r.right, r.bottom, 20, 20)
        if let previous { _ = SelectObject(hdc, previous) }
    }
}

func drawButton(_ hdc: HDC?, _ rect: UIRect, title: String, subtitle: String? = nil, selected: Bool = false, game: Game) {
    let hovered = rect.contains(game.mousePosition)
    let color: COLORREF
    if selected { color = rgb(40, 137, 206) }
    else if hovered { color = rgb(37, 73, 122) }
    else { color = rgb(24, 45, 78) }
    roundedPanel(hdc, rect, color)
    drawText(hdc, title, RECT(left: LONG(rect.x + 12), top: LONG(rect.y + 7), right: LONG(rect.x + rect.width - 12), bottom: LONG(rect.y + (subtitle == nil ? rect.height - 7 : 31))), rgb(236, 246, 255), 17, DT_CENTER)
    if let subtitle {
        drawText(hdc, subtitle, RECT(left: LONG(rect.x + 12), top: LONG(rect.y + 31), right: LONG(rect.x + rect.width - 12), bottom: LONG(rect.y + rect.height - 5)), rgb(157, 197, 229), 11, DT_CENTER)
    }
}

func drawMenuUI(_ hdc: HDC?, width: Double, height: Double, game: Game) {
    let panel = UIRect(x: width / 2 - 300, y: 78, width: 600, height: height - 130)
    roundedPanel(hdc, panel, rgb(12, 24, 51))
    let saveCard = saveSlotButton(width: width, height: height)
    roundedPanel(hdc, saveCard, game.mousePosition.x >= saveCard.x && game.mousePosition.x <= saveCard.x + saveCard.width && game.mousePosition.y >= saveCard.y && game.mousePosition.y <= saveCard.y + saveCard.height ? rgb(37, 73, 122) : rgb(24, 45, 78))
    let activeSlot = SaveManager.shared.activeSlot
    drawText(hdc, game.uiText("SAVE SLOT \(activeSlot + 1)", "存档 \(activeSlot + 1)"),
             RECT(left: LONG(saveCard.x + 12), top: LONG(saveCard.y + 10), right: LONG(saveCard.x + saveCard.width - 12), bottom: LONG(saveCard.y + 34)),
             rgb(255, 226, 132), 15, DT_LEFT)
    drawText(hdc, game.uiText("Click to manage", "点击管理存档"),
             RECT(left: LONG(saveCard.x + 12), top: LONG(saveCard.y + 39), right: LONG(saveCard.x + saveCard.width - 12), bottom: LONG(saveCard.y + 59)),
             rgb(169, 202, 230), 10, DT_LEFT)
    drawText(hdc, game.uiText("AUTO-SAVE ON", "自动保存已开启"),
             RECT(left: LONG(saveCard.x + 12), top: LONG(saveCard.y + 64), right: LONG(saveCard.x + saveCard.width - 12), bottom: LONG(saveCard.y + 84)),
             rgb(137, 238, 180), 10, DT_LEFT)
    drawText(hdc, game.uiText("THUNDER SWIFT", "雷霆战机"), RECT(left: LONG(width / 2 - 270), top: 120, right: LONG(width / 2 + 270), bottom: 172), rgb(230, 245, 255), 31, DT_CENTER)
    drawText(hdc, game.uiText("NEON SKY // ARCADE FLIGHT SYSTEM", "霓虹天空 // 街机飞行系统"), RECT(left: LONG(width / 2 - 270), top: 177, right: LONG(width / 2 + 270), bottom: 204), rgb(89, 195, 246), 12, DT_CENTER)
    let buttons = mainMenuButtons(width: width, height: height)
    drawButton(hdc, buttons[0], title: game.uiText("NEW GAME", "开始游戏"), subtitle: game.uiText("Choose mission and mode", "选择关卡与模式"), game: game)
    drawButton(hdc, buttons[1], title: game.uiText("CONTROLS", "操作设置"), subtitle: game.uiText("Choose keyboard or mouse", "选择键盘或鼠标"), game: game)
    drawButton(hdc, buttons[2], title: game.uiText("HANGAR", "机库"), subtitle: game.uiText("Upgrade your loadout", "强化装备配置"), game: game)
    drawButton(hdc, buttons[3], title: game.uiText("SETTINGS", "设置"), subtitle: game.uiText("Language and preferences", "语言与偏好"), game: game)
    drawButton(hdc, buttons[4], title: game.uiText("EXIT", "退出"), subtitle: game.uiText("Close Thunder Swift", "关闭雷霆战机"), game: game)
    drawButton(hdc, buttons[5], title: game.uiText("ARCHIVE", "档案馆"), subtitle: game.uiText("Achievements and codex", "成就与图鉴"), game: game)
    drawText(hdc, game.uiText("CREDITS  \(game.profile.credits)   •   CORES  \(game.profile.cores)   •   ALLOY  \(game.profile.alloy)",
                              "金币  \(game.profile.credits)   •   核心  \(game.profile.cores)   •   合金  \(game.profile.alloy)"),
             RECT(left: LONG(width / 2 - 250), top: 242, right: LONG(width / 2 + 250), bottom: 270),
             rgb(255, 211, 112), 13, DT_CENTER)
    drawText(hdc, game.uiText("SORTIES  \(game.profile.totalRuns)   •   BOSS  \(game.profile.totalBosses)   •   BEST COMBO  \(game.profile.bestCombo)",
                              "出击  \(game.profile.totalRuns)   •   Boss  \(game.profile.totalBosses)   •   最佳连击  \(game.profile.bestCombo)"),
             RECT(left: LONG(width / 2 - 250), top: 272, right: LONG(width / 2 + 250), bottom: 294),
             rgb(126, 200, 238), 10, DT_CENTER)
    drawText(hdc, game.uiText("AUTO-FIRE  •  5 WEAPONS  •  FORMATIONS  •  BOSS WAVES", "自动开火  •  5 种武器  •  编队  •  Boss 波次"), RECT(left: LONG(width / 2 - 270), top: LONG(height - 93), right: LONG(width / 2 + 270), bottom: LONG(height - 65)), rgb(123, 153, 194), 11, DT_CENTER)
}

func drawSaveSlotsUI(_ hdc: HDC?, width: Double, height: Double, game: Game) {
    let panel = UIRect(x: width / 2 - 420, y: 78, width: 840, height: height - 130)
    roundedPanel(hdc, panel, rgb(12, 24, 51))
    drawText(hdc, game.uiText("SAVE SELECT", "选择存档"),
             RECT(left: LONG(width / 2 - 380), top: 116, right: LONG(width / 2 + 380), bottom: 160),
             rgb(230, 245, 255), 28, DT_CENTER)
    drawText(hdc, game.uiText("Choose a profile. Progress autosaves to the game folder.",
                              "选择一个档案。进度会自动保存到游戏根目录。"),
             RECT(left: LONG(width / 2 - 380), top: 166, right: LONG(width / 2 + 380), bottom: 194),
             rgb(137, 183, 220), 12, DT_CENTER)

    let summaries = SaveManager.shared.slotSummaries()
    for (index, card) in saveSlotCards(width: width, height: height).enumerated() {
        let summary = summaries[index]
        let selected = index == SaveManager.shared.activeSlot
        let hovered = card.contains(game.mousePosition)
        roundedPanel(hdc, card, selected ? rgb(38, 121, 187) : (hovered ? rgb(37, 73, 122) : rgb(23, 48, 82)))
        drawText(hdc, game.uiText("PROFILE \(index + 1)", "档案 \(index + 1)"),
                 RECT(left: LONG(card.x + 16), top: LONG(card.y + 14), right: LONG(card.x + card.width - 16), bottom: LONG(card.y + 39)),
                 selected ? rgb(255, 226, 132) : rgb(239, 248, 255), 16, DT_LEFT)
        if let saved = summary.profile {
            drawText(hdc, game.uiText("ACTIVE SAVE", "已有存档"),
                     RECT(left: LONG(card.x + 16), top: LONG(card.y + 48), right: LONG(card.x + card.width - 16), bottom: LONG(card.y + 68)),
                     rgb(137, 238, 180), 10, DT_LEFT)
            drawText(hdc, game.uiText("MISSIONS \(saved.unlockedMission)  •  BOSS \(saved.totalBosses)",
                                      "关卡 \(saved.unlockedMission)  •  Boss \(saved.totalBosses)"),
                     RECT(left: LONG(card.x + 16), top: LONG(card.y + 80), right: LONG(card.x + card.width - 16), bottom: LONG(card.y + 103)),
                     rgb(169, 202, 230), 10, DT_LEFT)
            drawText(hdc, game.uiText("BEST \(saved.bestScore)  •  \(saved.totalRuns) SORTIES",
                                      "最高分 \(saved.bestScore)  •  出击 \(saved.totalRuns) 次"),
                     RECT(left: LONG(card.x + 16), top: LONG(card.y + 108), right: LONG(card.x + card.width - 16), bottom: LONG(card.y + 132)),
                     rgb(255, 211, 112), 10, DT_LEFT)
            drawText(hdc, game.uiText("Click to load", "点击载入"),
                     RECT(left: LONG(card.x + 16), top: LONG(card.y + 151), right: LONG(card.x + card.width - 16), bottom: LONG(card.y + 175)),
                     rgb(126, 200, 238), 10, DT_LEFT)
        } else {
            drawText(hdc, game.uiText("EMPTY PROFILE", "空存档位"),
                     RECT(left: LONG(card.x + 16), top: LONG(card.y + 54), right: LONG(card.x + card.width - 16), bottom: LONG(card.y + 80)),
                     rgb(166, 185, 211), 12, DT_LEFT)
            drawText(hdc, game.uiText("Click to create a new save", "点击创建新存档"),
                     RECT(left: LONG(card.x + 16), top: LONG(card.y + 94), right: LONG(card.x + card.width - 16), bottom: LONG(card.y + 122)),
                     rgb(169, 202, 230), 10, DT_LEFT)
        }
    }
    drawText(hdc, game.uiText("Files: SwiftSurvivorSave1.json / 2 / 3", "文件：SwiftSurvivorSave1.json / 2 / 3"),
             RECT(left: LONG(width / 2 - 340), top: 446, right: LONG(width / 2 + 340), bottom: 470),
             rgb(100, 221, 255), 11, DT_CENTER)
    drawButton(hdc, saveSlotsBackButton(width: width, height: height),
               title: game.uiText("BACK", "返回"), subtitle: game.uiText("Command deck", "指挥台"), game: game)
}

func drawMissionSelectUI(_ hdc: HDC?, width: Double, height: Double, game: Game) {
    let panel = UIRect(x: width / 2 - 430, y: 34, width: 860, height: height - 68)
    roundedPanel(hdc, panel, rgb(11, 24, 52))
    drawText(hdc, game.uiText("MISSION CONTROL", "出击计划"),
             RECT(left: LONG(width / 2 - 390), top: 66, right: LONG(width / 2 + 390), bottom: 108),
             rgb(230, 245, 255), 28, DT_CENTER)
    drawText(hdc, game.uiText("Select a sector, then choose your flight mode",
                              "选择作战区域，再选择飞行模式"),
             RECT(left: LONG(width / 2 - 390), top: 112, right: LONG(width / 2 + 390), bottom: 138),
             rgb(137, 183, 220), 13, DT_CENTER)
    drawText(hdc, game.uiText("SECTORS", "作战区域"),
             RECT(left: LONG(width / 2 - 380), top: 158, right: LONG(width / 2 + 380), bottom: 181),
             rgb(126, 200, 238), 12, DT_LEFT)

    for (index, card) in missionCards(width: width, height: height).enumerated() {
        let mission = MissionCatalog.all[index]
        let unlocked = index < game.unlockedMissionCount
        let selected = game.gameMode == .campaign && game.selectedMission == index
        roundedPanel(hdc, card,
                     selected ? rgb(38, 121, 187) : (unlocked ? rgb(23, 48, 82) : rgb(22, 30, 52)))
        drawText(hdc, game.uiText("SECTOR \(mission.id)", "区域 \(mission.id)"),
                 RECT(left: LONG(card.x + 12), top: LONG(card.y + 7), right: LONG(card.x + card.width - 12), bottom: LONG(card.y + 23)),
                 selected ? rgb(255, 226, 132) : rgb(126, 200, 238), 10, DT_LEFT)
        drawText(hdc, unlocked ? mission.title(for: game.language) : game.uiText("LOCKED", "未解锁"),
                 RECT(left: LONG(card.x + 12), top: LONG(card.y + 26), right: LONG(card.x + card.width - 12), bottom: LONG(card.y + 47)),
                 unlocked ? rgb(239, 248, 255) : rgb(135, 149, 177), 14, DT_LEFT)
        if unlocked {
            drawText(hdc, mission.description(for: game.language),
                     RECT(left: LONG(card.x + 12), top: LONG(card.y + 51), right: LONG(card.x + card.width - 12), bottom: LONG(card.y + 70)),
                     rgb(169, 202, 230), 9, DT_LEFT)
            drawText(hdc, game.uiText("\(Int(mission.duration))s  •  BOSS \(Int(mission.bossTime))s",
                                      "\(Int(mission.duration))秒  •  Boss \(Int(mission.bossTime))秒"),
                     RECT(left: LONG(card.x + 12), top: LONG(card.y + 76), right: LONG(card.x + card.width - 12), bottom: LONG(card.y + 94)),
                     rgb(255, 211, 112), 9, DT_LEFT)
        } else {
            drawText(hdc, game.uiText("Clear previous sector to unlock", "完成前一区域后解锁"),
                     RECT(left: LONG(card.x + 12), top: LONG(card.y + 53), right: LONG(card.x + card.width - 12), bottom: LONG(card.y + 88)),
                     rgb(135, 149, 177), 9, DT_LEFT)
        }
    }

    drawText(hdc, game.uiText("FLIGHT MODES", "飞行模式"),
             RECT(left: LONG(width / 2 - 380), top: 406, right: LONG(width / 2 + 380), bottom: 425),
             rgb(126, 200, 238), 12, DT_LEFT)
    for (index, card) in modeCards(width: width, height: height).enumerated() {
        let mode = GameMode.allCases[index]
        let selected = game.gameMode == mode
        roundedPanel(hdc, card, selected ? rgb(38, 121, 187) : rgb(23, 48, 82))
        drawText(hdc, mode.label(for: game.language),
                 RECT(left: LONG(card.x + 12), top: LONG(card.y + 8), right: LONG(card.x + card.width - 12), bottom: LONG(card.y + 29)),
                 selected ? rgb(255, 226, 132) : rgb(239, 248, 255), 14, DT_LEFT)
        drawText(hdc, mode.description(for: game.language),
                 RECT(left: LONG(card.x + 12), top: LONG(card.y + 36), right: LONG(card.x + card.width - 12), bottom: LONG(card.y + 74)),
                 rgb(169, 202, 230), 9, DT_LEFT)
    }

    let mission = game.activeMission
    let summary = game.gameMode == .campaign
        ? game.uiText("SELECTED: SECTOR \(mission.id)  •  \(mission.title)  •  RECOMMENDED POWER \(mission.recommendedPower)",
                      "已选择：区域 \(mission.id)  •  \(mission.chineseTitle)  •  推荐战力 \(mission.recommendedPower)")
        : game.uiText("SELECTED: \(game.gameMode.label)  •  \(mission.title)  •  RECOMMENDED POWER \(mission.recommendedPower)",
                      "已选择：\(game.gameMode.label(for: .chinese))  •  \(mission.chineseTitle)  •  推荐战力 \(mission.recommendedPower)")
    let objective = game.activeKillGoal > 0
        ? game.uiText("  •  KILLS \(game.activeKillGoal) + BOSS", "  •  击杀 \(game.activeKillGoal) + Boss")
        : game.uiText("  •  DEFEAT BOSS", "  •  击败 Boss")
    drawText(hdc, summary + objective,
             RECT(left: LONG(width / 2 - 380), top: 530, right: LONG(width / 2 + 380), bottom: 557),
             rgb(100, 221, 255), 11, DT_CENTER)
    drawButton(hdc, missionBackButton(width: width, height: height),
               title: game.uiText("BACK", "返回"),
               subtitle: game.uiText("Command deck", "指挥台"), game: game)
    drawButton(hdc, missionLaunchButton(width: width, height: height),
               title: game.uiText("LAUNCH", "出击"),
               subtitle: game.uiText("Start selected mission", "开始所选任务"), selected: true, game: game)
}

func drawArchiveUI(_ hdc: HDC?, width: Double, height: Double, game: Game) {
    let panel = UIRect(x: width / 2 - 390, y: 42, width: 780, height: height - 92)
    roundedPanel(hdc, panel, rgb(12, 24, 51))
    drawText(hdc, game.uiText("ARCHIVE", "档案馆"),
             RECT(left: LONG(width / 2 - 340), top: 74, right: LONG(width / 2 + 340), bottom: 116),
             rgb(230, 245, 255), 28, DT_CENTER)
    let tabs = archiveTabButtons(width: width, height: height)
    drawButton(hdc, tabs[0], title: game.uiText("ACHIEVEMENTS", "成就"), subtitle: game.uiText("Milestones", "里程碑"),
               selected: game.archiveTab == 0, game: game)
    drawButton(hdc, tabs[1], title: game.uiText("CODEX", "图鉴"), subtitle: game.uiText("Combat index", "战斗索引"),
               selected: game.archiveTab == 1, game: game)

    if game.archiveTab == 0 {
        drawText(hdc, game.uiText("FLIGHT RECORD", "出击记录"),
                 RECT(left: LONG(width / 2 - 320), top: 198, right: LONG(width / 2 + 320), bottom: 225),
                 rgb(126, 200, 238), 14, DT_LEFT)
        for (index, achievement) in AchievementCatalog.all.enumerated() {
            let y = 236 + Double(index) * 42
            let unlocked = game.profile.achievements.contains(achievement.id)
            let progress = min(achievement.target, game.achievementValue(achievement.metric))
            let card = UIRect(x: width / 2 - 320, y: y, width: 640, height: 34)
            roundedPanel(hdc, card, unlocked ? rgb(35, 83, 85) : rgb(23, 44, 76))
            drawText(hdc, unlocked ? "✓  " + achievement.title(for: game.language) : "○  " + achievement.title(for: game.language),
                     RECT(left: LONG(card.x + 14), top: LONG(card.y + 3), right: LONG(card.x + 250), bottom: LONG(card.y + 30)),
                     unlocked ? rgb(137, 238, 180) : rgb(226, 239, 252), 12, DT_LEFT)
            drawText(hdc, achievement.detail(for: game.language),
                     RECT(left: LONG(card.x + 255), top: LONG(card.y + 3), right: LONG(card.x + 490), bottom: LONG(card.y + 30)),
                     rgb(170, 202, 229), 10, DT_LEFT)
            drawText(hdc, "\(progress)/\(achievement.target)",
                     RECT(left: LONG(card.x + 500), top: LONG(card.y + 3), right: LONG(card.x + card.width - 14), bottom: LONG(card.y + 30)),
                     unlocked ? rgb(255, 214, 110) : rgb(142, 174, 204), 11, DT_RIGHT)
        }
        drawText(hdc, game.uiText("\(game.profile.achievements.count)/\(AchievementCatalog.all.count) unlocked",
                                  "已解锁 \(game.profile.achievements.count)/\(AchievementCatalog.all.count)"),
                 RECT(left: LONG(width / 2 - 300), top: LONG(height - 143), right: LONG(width / 2 + 300), bottom: LONG(height - 119)),
                 rgb(100, 221, 255), 12, DT_CENTER)
    } else {
        for (index, category) in CodexCategory.allCases.enumerated() {
            let card = codexCategoryButtons(width: width, height: height)[index]
            drawButton(hdc, card, title: category.label(for: game.language), selected: category == game.codexCategory, game: game)
        }
        let entries = CodexCatalog.all.filter { $0.category == game.codexCategory }
        let pageCount = max(1, (entries.count + 7) / 8)
        let page = min(game.codexPage, pageCount - 1)
        let start = page * 8
        for localIndex in 0..<min(8, entries.count - start) {
            let entry = entries[start + localIndex]
            let column = localIndex % 2
            let row = localIndex / 2
            let card = UIRect(x: width / 2 - 320 + Double(column) * 330,
                              y: 246 + Double(row) * 70, width: 300, height: 58)
            let unlocked: Bool
            switch entry.category {
            case .weapons: unlocked = true
            case .enemies: unlocked = game.profile.totalKills >= (localIndex + 1) * 10
            case .bosses: unlocked = game.profile.totalBosses >= localIndex + 1
            }
            roundedPanel(hdc, card, unlocked ? rgb(23, 60, 87) : rgb(24, 33, 56))
            drawText(hdc, unlocked ? entry.title(for: game.language) : "???",
                     RECT(left: LONG(card.x + 12), top: LONG(card.y + 6), right: LONG(card.x + card.width - 12), bottom: LONG(card.y + 28)),
                     unlocked ? rgb(239, 248, 255) : rgb(128, 146, 174), 13, DT_LEFT)
            drawText(hdc, unlocked ? entry.detail(for: game.language) : game.uiText("Log entry locked", "图鉴条目未解锁"),
                     RECT(left: LONG(card.x + 12), top: LONG(card.y + 31), right: LONG(card.x + card.width - 12), bottom: LONG(card.y + 51)),
                     unlocked ? rgb(163, 211, 233) : rgb(118, 137, 165), 9, DT_LEFT)
        }
        drawText(hdc, "\(page + 1)/\(pageCount)",
                 RECT(left: LONG(width / 2 - 80), top: LONG(height - 130), right: LONG(width / 2 + 80), bottom: LONG(height - 102)),
                 rgb(100, 221, 255), 11, DT_CENTER)
        drawButton(hdc, codexPrevButton(width: width, height: height), title: game.uiText("PREV", "上一页"), game: game)
        drawButton(hdc, codexNextButton(width: width, height: height), title: game.uiText("NEXT", "下一页"), game: game)
    }
    drawButton(hdc, archiveBackButton(width: width, height: height), title: game.uiText("BACK", "返回"),
               subtitle: game.uiText("Command deck", "指挥台"), game: game)
}

func drawControlsUI(_ hdc: HDC?, width: Double, height: Double, game: Game) {
    let panel = UIRect(x: width / 2 - 320, y: 70, width: 640, height: height - 125)
    roundedPanel(hdc, panel, rgb(12, 24, 51))
    drawText(hdc, game.uiText("CONTROL DECK", "操作面板"), RECT(left: LONG(width / 2 - 290), top: 115, right: LONG(width / 2 + 290), bottom: 160), rgb(230, 245, 255), 28, DT_CENTER)
    drawText(hdc, game.uiText("Select how you want to pilot the fighter", "选择你的战机操控方式"), RECT(left: LONG(width / 2 - 280), top: 164, right: LONG(width / 2 + 280), bottom: 193), rgb(137, 183, 220), 13, DT_CENTER)
    let modes = controlModeButtons(width: width, height: height)
    drawButton(hdc, modes[0], title: "WASD", subtitle: game.uiText("Keyboard / arrow keys", "键盘 / 方向键"), selected: game.controlMode == .wasd, game: game)
    drawButton(hdc, modes[1], title: game.uiText("MOUSE FOLLOW", "鼠标跟随"), subtitle: game.uiText("Fighter follows cursor", "战机跟随光标"), selected: game.controlMode == .mouse, game: game)
    drawText(hdc, game.controlMode == .wasd
                ? game.uiText("Current mode: keyboard steering  •  Q cycles weapon", "当前模式：键盘操控  •  Q 切换武器")
                : game.uiText("Current mode: mouse steering  •  Q cycles weapon", "当前模式：鼠标操控  •  Q 切换武器"),
             RECT(left: LONG(width / 2 - 260), top: LONG(height / 2 + 92), right: LONG(width / 2 + 260), bottom: LONG(height / 2 + 120)), rgb(100, 221, 255), 13, DT_CENTER)
    drawButton(hdc, controlsBackButton(width: width, height: height), title: game.uiText("BACK", "返回"), game: game)
}

func drawSettingsUI(_ hdc: HDC?, width: Double, height: Double, game: Game) {
    let panel = UIRect(x: width / 2 - 320, y: 70, width: 640, height: height - 125)
    roundedPanel(hdc, panel, rgb(12, 24, 51))
    drawText(hdc, game.uiText("SETTINGS", "设置"),
             RECT(left: LONG(width / 2 - 290), top: 112, right: LONG(width / 2 + 290), bottom: 158),
             rgb(230, 245, 255), 28, DT_CENTER)
    drawText(hdc, game.uiText("LANGUAGE", "语言"),
             RECT(left: LONG(width / 2 - 280), top: 184, right: LONG(width / 2 + 280), bottom: 214),
             rgb(137, 183, 220), 15, DT_CENTER)
    let languages = settingsLanguageButtons(width: width, height: height)
    drawButton(hdc, languages[0], title: "English", subtitle: game.uiText("English UI", "英文界面"),
               selected: game.language == .english, game: game)
    drawButton(hdc, languages[1], title: "中文", subtitle: "简体中文界面",
               selected: game.language == .chinese, game: game)
    drawButton(hdc, settingsBGMButton(width: width, height: height),
               title: game.uiText("BGM \(game.profile.bgmVolume)%", "音乐 \(game.profile.bgmVolume)%"),
               subtitle: game.uiText("Click to cycle volume", "点击切换音量"), game: game)
    drawButton(hdc, settingsSFXButton(width: width, height: height),
               title: game.uiText("SFX \(game.profile.sfxVolume)%", "音效 \(game.profile.sfxVolume)%"),
               subtitle: game.uiText("Click to cycle volume", "点击切换音量"), game: game)
    let shakeNames = game.language == .chinese ? ["关闭", "低", "中", "高"] : ["OFF", "LOW", "MED", "HIGH"]
    drawButton(hdc, settingsShakeButton(width: width, height: height),
               title: game.uiText("CAMERA SHAKE: \(shakeNames[game.profile.cameraShake])", "屏幕震动：\(shakeNames[game.profile.cameraShake])"),
               subtitle: game.uiText("Click to cycle • applies instantly", "点击切换 • 立即生效"), game: game)
    let displayMode = game.profile.isFullscreen ? game.uiText("FULLSCREEN", "全屏") : game.uiText("WINDOWED", "窗口化")
    drawButton(hdc, settingsWindowModeButton(width: width, height: height),
               title: game.uiText("DISPLAY: \(displayMode)", "显示模式：\(displayMode)"),
               subtitle: game.uiText("Click to switch • applies instantly", "点击切换 • 立即生效"), game: game)
    drawButton(hdc, settingsResolutionButton(width: width, height: height),
               title: game.uiText("RESOLUTION: \(game.profile.resolutionWidth) × \(game.profile.resolutionHeight)",
                                  "分辨率：\(game.profile.resolutionWidth) × \(game.profile.resolutionHeight)"),
               subtitle: game.uiText("1024 × 768 / 1280 × 720 • applies instantly",
                                     "1024 × 768 / 1280 × 720 • 立即生效"), game: game)
    drawText(hdc, game.uiText("Language, audio, display and shake settings are saved automatically.",
                              "语言、音频、显示和震动设置会自动保存。"),
             RECT(left: LONG(width / 2 - 290), top: 582, right: LONG(width / 2 + 290), bottom: 610),
             rgb(100, 221, 255), 12, DT_CENTER)
    drawButton(hdc, settingsBackButton(width: width, height: height),
               title: game.uiText("BACK", "返回"), game: game)
}

func drawHangarUI(_ hdc: HDC?, width: Double, height: Double, game: Game) {
    let panel = UIRect(x: width / 2 - 390, y: 52, width: 780, height: height - 100)
    roundedPanel(hdc, panel, rgb(12, 24, 51))
    drawText(hdc, game.uiText("HANGAR / LOADOUT", "机库 / 装备配置"),
             RECT(left: LONG(width / 2 - 350), top: 86, right: LONG(width / 2 + 350), bottom: 128),
             rgb(230, 245, 255), 28, DT_CENTER)
    drawText(hdc, game.uiText("CREDITS  \(game.profile.credits)   •   CORES  \(game.profile.cores)   •   ALLOY  \(game.profile.alloy)",
                              "金币  \(game.profile.credits)   •   核心  \(game.profile.cores)   •   合金  \(game.profile.alloy)"),
             RECT(left: LONG(width / 2 - 320), top: 132, right: LONG(width / 2 + 320), bottom: 158),
             rgb(255, 211, 112), 13, DT_CENTER)
    drawText(hdc, game.uiText("COMBAT POWER  \(game.combatPower())   •   MODULE VAULT  \(game.profile.inventory.count)",
                              "战力  \(game.combatPower())   •   模块仓库  \(game.profile.inventory.count)"),
             RECT(left: LONG(width / 2 - 320), top: 158, right: LONG(width / 2 + 320), bottom: 178),
             rgb(126, 200, 238), 10, DT_CENTER)

    let tabs = hangarTabButtons(width: width, height: height)
    for (index, tab) in tabs.enumerated() {
        let title = index == 0 ? game.uiText("LOADOUT", "装备") : game.uiText("MODULE VAULT", "模块仓库")
        let selected = game.hangarTab == index
        roundedPanel(hdc, tab, selected ? rgb(40, 137, 206) : rgb(24, 45, 78))
        drawText(hdc, title,
                 RECT(left: LONG(tab.x + 6), top: LONG(tab.y + 5), right: LONG(tab.x + tab.width - 6), bottom: LONG(tab.y + tab.height - 5)),
                 rgb(236, 246, 255), 11, DT_CENTER)
    }

    if game.hangarTab == 0 {
        let cards = hangarCards(width: width, height: height)
        for (index, card) in cards.enumerated() where index < game.profile.equipment.count {
            let item = game.profile.equipment[index]
            let hovered = card.contains(game.mousePosition)
            roundedPanel(hdc, card, hovered ? rgb(37, 73, 122) : rgb(23, 44, 76))
            let rarity = game.equipmentQualityName(item.rarity)
            let rarityTint = equipmentRarityColor(item.rarity)
            drawText(hdc, game.equipmentDisplayName(item),
                     RECT(left: LONG(card.x + 16), top: LONG(card.y + 12), right: LONG(card.x + card.width - 16), bottom: LONG(card.y + 35)),
                     rgb(239, 248, 255), 15, DT_LEFT)
            drawText(hdc, game.uiText("LEVEL \(item.level)  •  ★\(item.stars)  •  \(rarity)",
                                      "等级 \(item.level)  •  ★\(item.stars)  •  \(rarity)"),
                     RECT(left: LONG(card.x + 16), top: LONG(card.y + 39), right: LONG(card.x + card.width - 16), bottom: LONG(card.y + 58)),
                     rarityTint, 11, DT_LEFT)
            drawText(hdc, game.equipmentBonusText(for: item),
                     RECT(left: LONG(card.x + 16), top: LONG(card.y + 63), right: LONG(card.x + card.width - 16), bottom: LONG(card.y + 82)),
                     rgb(155, 213, 237), 10, DT_LEFT)
            drawText(hdc, game.uiText("UP \(game.equipmentUpgradeCost(for: item))C / \(game.equipmentAlloyCost(for: item))A",
                                      "强化 \(game.equipmentUpgradeCost(for: item))金 / \(game.equipmentAlloyCost(for: item))合金"),
                     RECT(left: LONG(card.x + 16), top: LONG(card.y + 88), right: LONG(card.x + card.width - 100), bottom: LONG(card.y + 108)),
                     hovered ? rgb(255, 224, 133) : rgb(191, 215, 238), 8, DT_RIGHT)
            let promote = equipmentPromoteButton(index, width: width, height: height)
            roundedPanel(hdc, promote, promote.contains(game.mousePosition) ? rgb(57, 94, 131) : rgb(31, 59, 94))
            drawText(hdc, item.rarity < 4 ? game.uiText("PROMOTE", "升品") : game.uiText("MAX", "最高"),
                     promote.winRect, equipmentRarityColor(min(4, item.rarity + 1)), 10, DT_CENTER)
        }
    } else {
        let filterTitle: String
        if let slot = game.vaultFilterSlot {
            filterTitle = game.uiText("SLOT \(slot + 1)", "槽位 \(slot + 1)")
        } else {
            filterTitle = game.uiText("ALL SLOTS", "全部槽位")
        }
        let sortTitle = game.vaultSortMode == 0 ? game.uiText("QUALITY", "品质") : (game.vaultSortMode == 1 ? game.uiText("LEVEL", "等级") : game.uiText("SLOT", "槽位"))
        drawButton(hdc, vaultFilterButton(width: width, height: height), title: filterTitle, subtitle: game.uiText("Filter", "筛选"), game: game)
        drawButton(hdc, vaultSortButton(width: width, height: height), title: sortTitle, subtitle: game.uiText("Sort", "排序"), game: game)
        drawButton(hdc, vaultPrevButton(width: width, height: height), title: "‹", game: game)
        drawButton(hdc, vaultNextButton(width: width, height: height), title: "›", game: game)
        drawText(hdc, "\(game.vaultPage + 1)/\(game.vaultPageCount)",
                 RECT(left: LONG(width / 2 + 12), top: 174, right: LONG(width / 2 + 198), bottom: 196),
                 rgb(100, 221, 255), 10, DT_CENTER)
        let cards = vaultCards(width: width, height: height)
        let visibleIndices = game.visibleVaultIndices
        for (cardIndex, card) in cards.enumerated() {
            let absoluteIndex = game.vaultPage * 4 + cardIndex
            guard visibleIndices.indices.contains(absoluteIndex) else { continue }
            let item = game.profile.inventory[visibleIndices[absoluteIndex]]
            let hovered = card.contains(game.mousePosition)
            let equipped = game.profile.equipment.contains(where: { $0.id == item.id && $0.slot == item.slot })
            roundedPanel(hdc, card, hovered ? rgb(37, 73, 122) : rgb(23, 44, 76))
            drawText(hdc, game.equipmentDisplayName(item),
                     RECT(left: LONG(card.x + 16), top: LONG(card.y + 12), right: LONG(card.x + card.width - 16), bottom: LONG(card.y + 35)),
                     rgb(239, 248, 255), 14, DT_LEFT)
            drawText(hdc, game.uiText("SLOT \(item.slot + 1)  •  LEVEL \(item.level)  •  ★\(item.stars)  •  \(game.equipmentQualityName(item.rarity))",
                                      "槽位 \(item.slot + 1)  •  等级 \(item.level)  •  ★\(item.stars)  •  \(game.equipmentQualityName(item.rarity))"),
                     RECT(left: LONG(card.x + 16), top: LONG(card.y + 40), right: LONG(card.x + card.width - 16), bottom: LONG(card.y + 60)),
                     equipmentRarityColor(item.rarity), 10, DT_LEFT)
            drawText(hdc, equipped ? game.uiText("EQUIPPED", "已装备") : game.uiText("CLICK TO EQUIP", "点击装备"),
                     RECT(left: LONG(card.x + 16), top: LONG(card.y + 82), right: LONG(card.x + card.width - 16), bottom: LONG(card.y + 105)),
                     equipped ? rgb(134, 238, 177) : (hovered ? rgb(255, 224, 133) : rgb(191, 215, 238)), 10, DT_RIGHT)
        }
        if visibleIndices.count > cards.count {
            drawText(hdc, game.uiText("\(visibleIndices.count) MODULES • PAGE \(game.vaultPage + 1)/\(game.vaultPageCount)",
                                      "共 \(visibleIndices.count) 个模块 • 第 \(game.vaultPage + 1)/\(game.vaultPageCount) 页"),
                     RECT(left: LONG(width / 2 - 300), top: 480, right: LONG(width / 2 + 300), bottom: 497),
                     rgb(126, 200, 238), 10, DT_CENTER)
        }
    }

    drawText(hdc, game.uiText("SHIP CLASS", "战机类型"),
             RECT(left: LONG(width / 2 - 340), top: 468, right: LONG(width / 2 + 340), bottom: 487),
             rgb(126, 200, 238), 11, DT_LEFT)
    let ships = shipCards(width: width, height: height)
    for (index, card) in ships.enumerated() {
        let ship = ShipType.allCases[index]
        drawButton(hdc, card, title: ship.label(for: game.language), subtitle: ship.rarity(for: game.language),
                   selected: game.shipType == ship, game: game)
    }
    drawText(hdc, game.uiText("PRIMARY WEAPON: \(game.weaponType.label)  •  Q cycles weapons in sortie",
                              "主武器：\(game.weaponType.label(for: .chinese))  •  出击中按 Q 切换"),
             RECT(left: LONG(width / 2 - 330), top: LONG(height - 119), right: LONG(width / 2 + 330), bottom: LONG(height - 95)),
             rgb(100, 221, 255), 12, DT_CENTER)
    drawText(hdc, game.uiText("Click a module to upgrade  •  PROMOTE unlocks the next quality",
                              "点击模块强化  •  点击升品可解锁下一品质"),
             RECT(left: LONG(width / 2 - 330), top: LONG(height - 145), right: LONG(width / 2 + 330), bottom: LONG(height - 123)),
             rgb(136, 177, 211), 10, DT_CENTER)
    drawButton(hdc, hangarBackButton(width: width, height: height), title: game.uiText("BACK", "返回"), game: game)
    if game.hangarMessageTimer > 0 {
        let message = UIRect(x: width / 2 - 225, y: 92, width: 450, height: 54)
        roundedPanel(hdc, message, rgb(31, 48, 81))
        drawText(hdc, game.hangarMessageTitle,
                 RECT(left: LONG(message.x + 12), top: LONG(message.y + 5), right: LONG(message.x + message.width - 12), bottom: LONG(message.y + 26)),
                 rgb(255, 220, 120), 13, DT_CENTER)
        drawText(hdc, game.hangarMessageDetail,
                 RECT(left: LONG(message.x + 12), top: LONG(message.y + 28), right: LONG(message.x + message.width - 12), bottom: LONG(message.y + 47)),
                 rgb(205, 229, 250), 10, DT_CENTER)
    }
}

func drawPauseUI(_ hdc: HDC?, width: Double, height: Double, game: Game) {
    let panel = UIRect(x: width / 2 - 230, y: height / 2 - 198, width: 460, height: 465)
    roundedPanel(hdc, panel, rgb(11, 23, 49))
    drawText(hdc, game.uiText("MISSION PAUSED", "任务已暂停"), RECT(left: LONG(width / 2 - 210), top: LONG(height / 2 - 150), right: LONG(width / 2 + 210), bottom: LONG(height / 2 - 105)), rgb(240, 247, 255), 27, DT_CENTER)
    drawText(hdc, game.uiText("Your sortie is safe. Choose an action.", "任务状态已保存，请选择操作。"), RECT(left: LONG(width / 2 - 210), top: LONG(height / 2 - 98), right: LONG(width / 2 + 210), bottom: LONG(height / 2 - 72)), rgb(128, 175, 215), 12, DT_CENTER)
    let buttons = pauseButtons(width: width, height: height)
    drawButton(hdc, buttons[0], title: game.uiText("RESUME", "继续"), subtitle: game.uiText("Continue sortie", "继续出击"), game: game)
    drawButton(hdc, buttons[1], title: game.uiText("RESTART", "重新开始"), subtitle: game.uiText("New sortie", "开始新的出击"), game: game)
    drawButton(hdc, buttons[2], title: game.uiText("CONTROLS", "操作设置"), subtitle: game.uiText("Change pilot mode", "更改操控方式"), game: game)
    drawButton(hdc, buttons[3], title: game.uiText("MAIN MENU", "回到开始界面"), subtitle: game.uiText("Return to command deck", "返回开始界面"), game: game)
    drawButton(hdc, buttons[4], title: game.uiText("EXIT TO DESKTOP", "退出桌面"), subtitle: game.uiText("Close the game", "关闭游戏"), game: game)
}

func drawUpgradeUI(_ hdc: HDC?, width: Double, height: Double, game: Game) {
    let panel = UIRect(x: width / 2 - 390, y: height / 2 - 205, width: 780, height: 375)
    roundedPanel(hdc, panel, rgb(11, 26, 57))
    drawText(hdc, game.uiText("MODULE AVAILABLE", "获得新模块"), RECT(left: LONG(width / 2 - 350), top: LONG(height / 2 - 175), right: LONG(width / 2 + 350), bottom: LONG(height / 2 - 130)), rgb(244, 211, 116), 26, DT_CENTER)
    drawText(hdc, game.uiText("Click a card or press 1 / 2 / 3", "点击卡片或按 1 / 2 / 3"), RECT(left: LONG(width / 2 - 350), top: LONG(height / 2 - 123), right: LONG(width / 2 + 350), bottom: LONG(height / 2 - 96)), rgb(139, 185, 223), 13, DT_CENTER)
    let cards = upgradeCards(width: width, height: height)
    for (index, option) in game.upgradeOptions.enumerated() where index < cards.count {
        let rarity = UpgradeRarity(rawValue: option.rarity) ?? .common
        drawButton(hdc, cards[index], title: "[\(index + 1)]  \(option.title)", subtitle: game.localizedRarity(rarity) + "  •  " + option.detail, game: game)
        drawText(hdc, game.localizedRarity(rarity),
                 RECT(left: LONG(cards[index].x + 12), top: LONG(cards[index].y + cards[index].height - 22), right: LONG(cards[index].x + cards[index].width - 12), bottom: LONG(cards[index].y + cards[index].height - 5)),
                 rarityColor(rarity), 10, DT_RIGHT)
    }
}

func drawGameOverUI(_ hdc: HDC?, width: Double, height: Double, game: Game) {
    let panel = UIRect(x: width / 2 - 275, y: height / 2 - 190, width: 550, height: 420)
    roundedPanel(hdc, panel, rgb(13, 23, 49))
    drawText(hdc, game.runWon ? game.uiText("MISSION COMPLETE", "任务完成") : game.uiText("SORTIE ENDED", "出击结束"),
             RECT(left: LONG(width / 2 - 250), top: LONG(height / 2 - 155), right: LONG(width / 2 + 250), bottom: LONG(height / 2 - 110)),
             game.runWon ? rgb(255, 208, 117) : rgb(255, 135, 157), 26, DT_CENTER)
    drawText(hdc, game.runWon
                ? game.uiText("Sector secured • extraction complete", "区域已肃清 • 撤离完成")
                : game.uiText("Your fighter was overwhelmed", "战机已被击毁"),
             RECT(left: LONG(width / 2 - 250), top: LONG(height / 2 - 93), right: LONG(width / 2 + 250), bottom: LONG(height / 2 - 65)),
             rgb(157, 188, 220), 13, DT_CENTER)
    drawText(hdc, game.gameMode == .campaign
                ? game.uiText("CAMPAIGN  •  SECTOR \(game.activeMission.id)  •  \(game.activeMission.title)",
                              "章节模式  •  区域 \(game.activeMission.id)  •  \(game.activeMission.chineseTitle)")
                : game.uiText("\(game.gameMode.label)  •  \(game.activeMission.title)",
                              "\(game.gameMode.label(for: .chinese))  •  \(game.activeMission.chineseTitle)"),
             RECT(left: LONG(width / 2 - 240), top: LONG(height / 2 - 58), right: LONG(width / 2 + 240), bottom: LONG(height / 2 - 38)),
             rgb(100, 221, 255), 10, DT_CENTER)
    drawText(hdc, game.uiText("SCORE  \(game.score)", "分数  \(game.score)"), RECT(left: LONG(width / 2 - 230), top: LONG(height / 2 - 32), right: LONG(width / 2 + 230), bottom: LONG(height / 2 + 2)), rgb(237, 246, 255), 19, DT_CENTER)
    drawText(hdc, game.uiText("STAGE  \(game.stage)     KILLS  \(game.kills)     BEST  \(game.highScore)",
                              "阶段  \(game.stage)     击杀  \(game.kills)     最高  \(game.highScore)"),
             RECT(left: LONG(width / 2 - 230), top: LONG(height / 2 + 8), right: LONG(width / 2 + 230), bottom: LONG(height / 2 + 34)), rgb(121, 185, 226), 12, DT_CENTER)
    drawText(hdc, game.uiText("REWARD  +\(game.runCreditsEarned) C   +\(game.runCoresEarned) CORE   +\(game.runAlloyEarned) A",
                              "奖励  +\(game.runCreditsEarned) 金   +\(game.runCoresEarned) 核心   +\(game.runAlloyEarned) 合金"),
             RECT(left: LONG(width / 2 - 240), top: LONG(height / 2 + 37), right: LONG(width / 2 + 240), bottom: LONG(height / 2 + 58)),
             rgb(255, 211, 112), 11, DT_CENTER)
    let buttons = gameOverButtons(width: width, height: height)
    drawButton(hdc, buttons[0], title: game.uiText("RESTART", "重新开始"), subtitle: game.uiText("Launch another sortie", "再次出击"), game: game)
    drawButton(hdc, buttons[1], title: game.uiText("MAIN MENU", "主菜单"), subtitle: game.uiText("Return to command deck", "返回指挥台"), game: game)
}

func drawGame(_ hdc: HDC?, width: Double, height: Double) {
    let game = Game.shared
    // All game primitives are filled shapes. Keeping a stock null pen selected
    // avoids an unnecessary outline pass for every circle and polygon.
    if let nullPen = GetStockObject(8) { // NULL_PEN
        _ = SelectObject(hdc, nullPen)
    }
    _ = SetBkMode(hdc, Int32(TRANSPARENT))
    if game.phase == .menu || game.phase == .missionSelect || game.phase == .controls || game.phase == .hangar || game.phase == .settings || game.phase == .archive {
        drawSpaceBackground(hdc, width: width, height: height, game: game)
    } else {
        drawWorldFrame(hdc, width: width, height: height)
    }
    switch game.phase {
    case .menu: drawMenuUI(hdc, width: width, height: height, game: game)
    case .saveSlots: drawSaveSlotsUI(hdc, width: width, height: height, game: game)
    case .missionSelect: drawMissionSelectUI(hdc, width: width, height: height, game: game)
    case .archive: drawArchiveUI(hdc, width: width, height: height, game: game)
    case .controls: drawControlsUI(hdc, width: width, height: height, game: game)
    case .hangar: drawHangarUI(hdc, width: width, height: height, game: game)
    case .settings: drawSettingsUI(hdc, width: width, height: height, game: game)
    case .paused: drawPauseUI(hdc, width: width, height: height, game: game)
    case .upgrade: drawUpgradeUI(hdc, width: width, height: height, game: game)
    case .gameOver: drawGameOverUI(hdc, width: width, height: height, game: game)
    case .playing: break
    }
}

func drawEnemy(_ hdc: HDC?, _ enemy: Enemy, field: PlayfieldBounds) {
    let x = LONG(enemy.position.x)
    let y = LONG(enemy.position.y)
    let radius = enemy.radius
    let enemyType = EnemyType(rawValue: enemy.type) ?? .fighter
    switch enemyType {
    case .fighter:
        let wing = LONG(radius * 1.25)
        polygon(hdc, [POINT(x: x, y: y + LONG(radius)), POINT(x: x - wing, y: y - LONG(radius / 2)),
                      POINT(x: x - LONG(radius / 2), y: y - LONG(radius)), POINT(x: x + LONG(radius / 2), y: y - LONG(radius)),
                      POINT(x: x + wing, y: y - LONG(radius / 2))], enemy.tint)
        circle(hdc, center: enemy.position + Vec2(x: 0, y: -3), radius: radius * 0.28, color: rgb(255, 215, 233))
    case .diver:
        polygon(hdc, [POINT(x: x, y: y + LONG(radius + 5)), POINT(x: x - LONG(radius), y: y - LONG(radius)),
                      POINT(x: x, y: y - LONG(radius / 2)), POINT(x: x + LONG(radius), y: y - LONG(radius))], enemy.tint)
        circle(hdc, center: enemy.position + Vec2(x: 0, y: -4), radius: 4, color: rgb(255, 239, 178))
    case .turret:
        roundedPanel(hdc, UIRect(x: enemy.position.x - radius, y: enemy.position.y - radius,
                                 width: radius * 2, height: radius * 2), enemy.tint)
        fill(hdc, RECT(left: x - 3, top: y - LONG(radius + 9), right: x + 3, bottom: y - LONG(radius / 2)), rgb(255, 235, 157))
        circle(hdc, center: enemy.position, radius: 6, color: rgb(91, 49, 23))
    case .sniper:
        polygon(hdc, [POINT(x: x, y: y - LONG(radius)), POINT(x: x + LONG(radius), y: y),
                      POINT(x: x, y: y + LONG(radius)), POINT(x: x - LONG(radius), y: y)], enemy.tint)
        circle(hdc, center: enemy.position, radius: 5, color: rgb(255, 243, 193))
        if enemy.attackWarningActive {
            let targetX = LONG(enemy.warningTargetX)
            fill(hdc, RECT(left: targetX - 2, top: LONG(field.top), right: targetX + 2, bottom: LONG(field.bottom)), rgb(183, 48, 92))
            fill(hdc, RECT(left: targetX - 10, top: LONG(field.bottom - 28), right: targetX + 10, bottom: LONG(field.bottom - 25)), rgb(255, 104, 133))
        }
    case .shield:
        circle(hdc, center: enemy.position, radius: radius + 8, color: rgb(21, 75, 86))
        circle(hdc, center: enemy.position, radius: radius + 4, color: rgb(92, 230, 193))
        polygon(hdc, [POINT(x: x, y: y - LONG(radius)), POINT(x: x + LONG(radius), y: y),
                      POINT(x: x, y: y + LONG(radius)), POINT(x: x - LONG(radius), y: y)], enemy.tint)
        circle(hdc, center: enemy.position, radius: 5, color: rgb(223, 255, 241))
    case .kamikaze:
        polygon(hdc, [POINT(x: x, y: y - LONG(radius + 4)), POINT(x: x + LONG(radius), y: y + LONG(radius)),
                      POINT(x: x, y: y + LONG(radius / 2)), POINT(x: x - LONG(radius), y: y + LONG(radius))], enemy.tint)
        circle(hdc, center: enemy.position, radius: 4, color: rgb(255, 224, 126))
    case .carrier:
        roundedPanel(hdc, UIRect(x: enemy.position.x - radius * 1.25, y: enemy.position.y - radius * 0.75,
                                 width: radius * 2.5, height: radius * 1.5), enemy.tint)
        polygon(hdc, [POINT(x: x - LONG(radius * 1.25), y: y), POINT(x: x - LONG(radius * 1.7), y: y + LONG(radius / 2)),
                      POINT(x: x - LONG(radius), y: y + LONG(radius / 3))], rgb(127, 53, 175))
        polygon(hdc, [POINT(x: x + LONG(radius * 1.25), y: y), POINT(x: x + LONG(radius * 1.7), y: y + LONG(radius / 2)),
                      POINT(x: x + LONG(radius), y: y + LONG(radius / 3))], rgb(127, 53, 175))
        circle(hdc, center: enemy.position, radius: 8, color: rgb(255, 213, 249))
    }
    let hp = LONG(enemy.radius * 2 * max(0, enemy.health) / max(1, enemy.maxHealth))
    fill(hdc, RECT(left: x - LONG(enemy.radius), top: y - LONG(enemy.radius) - 8,
                   right: x + LONG(enemy.radius), bottom: y - LONG(enemy.radius) - 4), rgb(42, 21, 42))
    fill(hdc, RECT(left: x - LONG(enemy.radius), top: y - LONG(enemy.radius) - 8,
                   right: x - LONG(enemy.radius) + hp, bottom: y - LONG(enemy.radius) - 4), rgb(255, 125, 126))
}

func warningBeam(_ hdc: HDC?, origin: Vec2, angle: Double, length: Double, width: Double, color: COLORREF) {
    let direction = rotated(Vec2(x: 0, y: 1), by: angle)
    let perpendicular = Vec2(x: -direction.y, y: direction.x) * (width / 2)
    let end = origin + direction * length
    polygon(hdc, [POINT(x: LONG(origin.x - perpendicular.x), y: LONG(origin.y - perpendicular.y)),
                  POINT(x: LONG(origin.x + perpendicular.x), y: LONG(origin.y + perpendicular.y)),
                  POINT(x: LONG(end.x + perpendicular.x), y: LONG(end.y + perpendicular.y)),
                  POINT(x: LONG(end.x - perpendicular.x), y: LONG(end.y - perpendicular.y))], color)
}

func drawBoss(_ hdc: HDC?, _ boss: Boss, field: PlayfieldBounds, language: GameLanguage = .english) {
    let x = LONG(boss.position.x)
    let y = LONG(boss.position.y)
    let bossType = BossType(rawValue: boss.kind) ?? .dreadnought
    let points = [POINT(x: x, y: y + 58), POINT(x: x - 72, y: y + 26), POINT(x: x - 100, y: y - 20),
                  POINT(x: x - 42, y: y - 42), POINT(x: x, y: y - 58), POINT(x: x + 42, y: y - 42),
                  POINT(x: x + 100, y: y - 20), POINT(x: x + 72, y: y + 26)]
    let baseColor: COLORREF
    switch bossType {
    case .dreadnought: baseColor = rgb(188, 49, 213)
    case .riftBehemoth: baseColor = rgb(212, 68, 172)
    case .frostWarden: baseColor = rgb(60, 177, 224)
    case .originArchitect: baseColor = rgb(233, 117, 66)
    }
    let phaseFactor = boss.phase == 1 ? 1.0 : (boss.phase == 2 ? 1.12 : 1.28)
    let bodyColor = scaleColor(baseColor, phaseFactor)
    polygon(hdc, points, bodyColor)
    polygon(hdc, [POINT(x: x - 100, y: y - 20), POINT(x: x - 140, y: y + 34), POINT(x: x - 54, y: y + 22)], scaleColor(baseColor, 0.60))
    polygon(hdc, [POINT(x: x + 100, y: y - 20), POINT(x: x + 140, y: y + 34), POINT(x: x + 54, y: y + 22)], scaleColor(baseColor, 0.60))
    // Turrets are separate weak points and visibly disappear when disabled.
    let turretPositions = [boss.position + Vec2(x: -102, y: 18), boss.position + Vec2(x: 102, y: 18)]
    let turretHealth = [boss.leftTurretHealth, boss.rightTurretHealth]
    for index in 0..<2 {
        let turret = turretPositions[index]
        if turretHealth[index] > 0 {
            circle(hdc, center: turret, radius: 19, color: rgb(57, 32, 76))
            circle(hdc, center: turret, radius: 13, color: bossType == .frostWarden ? rgb(137, 237, 255) : rgb(255, 164, 205))
            fill(hdc, RECT(left: LONG(turret.x - 8), top: LONG(turret.y - 3), right: LONG(turret.x + 8), bottom: LONG(turret.y + 3)), rgb(255, 245, 221))
            let turretWidth = LONG(30 * max(0, turretHealth[index]) / max(1, boss.maxHealth * 0.18))
            fill(hdc, RECT(left: LONG(turret.x - 15), top: LONG(turret.y + 23), right: LONG(turret.x + 15), bottom: LONG(turret.y + 27)), rgb(46, 23, 49))
            fill(hdc, RECT(left: LONG(turret.x - 15), top: LONG(turret.y + 23), right: LONG(turret.x - 15) + turretWidth, bottom: LONG(turret.y + 27)), rgb(255, 188, 112))
        } else {
            circle(hdc, center: turret, radius: 15, color: rgb(47, 52, 72))
            circle(hdc, center: turret, radius: 7, color: rgb(116, 126, 151))
        }
    }
    circle(hdc, center: boss.position, radius: 23 + (boss.phase == 3 ? 4 : 0), color: bossType == .frostWarden ? rgb(216, 251, 255) : rgb(255, 206, 244))
    circle(hdc, center: boss.position, radius: 10, color: boss.phase == 3 ? rgb(117, 14, 66) : scaleColor(baseColor, 0.45))
    // The HUD boss bar already carries the localized name; drawing it again
    // above the moving sprite can overlap the FPS/Combo header.
    if boss.laserWarningTimer > 0 {
        fill(hdc, RECT(left: LONG(boss.laserX - 3), top: LONG(field.top + 20), right: LONG(boss.laserX + 3), bottom: LONG(field.bottom)), rgb(255, 58, 120))
        drawText(hdc, language == .chinese ? "激光锁定" : "LASER LOCK", RECT(left: LONG(boss.laserX - 60), top: 92, right: LONG(boss.laserX + 60), bottom: 114), rgb(255, 176, 210), 11, DT_CENTER)
    } else if boss.laserActiveTimer > 0 {
        fill(hdc, RECT(left: LONG(boss.laserX - 17), top: LONG(field.top + 20), right: LONG(boss.laserX + 17), bottom: LONG(field.bottom)), scaleColor(rgb(255, 71, 142), 0.62))
        fill(hdc, RECT(left: LONG(boss.laserX - 5), top: LONG(field.top + 20), right: LONG(boss.laserX + 5), bottom: LONG(field.bottom)), rgb(255, 239, 244))
    }
    if boss.phaseFlash > 0 {
        circle(hdc, center: boss.position, radius: 70 + boss.phaseFlash * 18, color: scaleColor(rgb(255, 134, 235), boss.phaseFlash * 0.45))
        let phaseText = language == .chinese ? "阶段 \(boss.phase)" : "PHASE \(boss.phase)"
        drawText(hdc, phaseText, RECT(left: x - 80, top: y - 86, right: x + 80, bottom: y - 60), rgb(255, 229, 246), 15, DT_CENTER)
    }
    if boss.attackPrimed, boss.warningTimer > 0 {
        let count = boss.phase == 1 ? 5 : (boss.phase == 2 ? 7 : 9)
        let spread = boss.phase == 1 ? 0.50 : (boss.phase == 2 ? 0.75 : 1.0)
        for index in 0..<count {
            let t = count == 1 ? 0.5 : Double(index) / Double(count - 1)
            let angle = -spread + t * spread * 2
            warningBeam(hdc, origin: boss.position + Vec2(x: 0, y: 32), angle: angle, length: max(320, field.bottom - boss.position.y), width: 2.2,
                        color: scaleColor(rgb(255, 91, 135), 0.35 + boss.warningTimer * 0.75))
        }
    }
}

func drawPlayer(_ hdc: HDC?, game: Game) {
    let x = LONG(game.player.x)
    let y = LONG(game.player.y)
    if game.thunderOverloadTime > 0 {
        circle(hdc, center: game.player, radius: 43 + sin(game.survivalTime * 16) * 3, color: rgb(36, 142, 208))
        circle(hdc, center: game.player, radius: 37 + sin(game.survivalTime * 16) * 3, color: rgb(81, 222, 255))
    }
    if game.reflectorTime > 0 {
        circle(hdc, center: game.player, radius: 31 + sin(game.survivalTime * 8) * 2, color: rgb(46, 128, 207))
        circle(hdc, center: game.player, radius: 25 + sin(game.survivalTime * 8) * 2, color: rgb(96, 205, 255))
    }
    if game.armorShieldCharges > 0 {
        circle(hdc, center: game.player, radius: 28 + sin(game.survivalTime * 5) * 1.5, color: rgb(80, 221, 188))
    }
    let droneLevel = game.profile.equipment.first(where: { $0.slot == 4 })?.level ?? 1
    let droneCount = min(4, 1 + droneLevel / 4 + (game.shipType == .carrier ? 1 : 0))
    for index in 0..<droneCount {
        let side = index % 2 == 0 ? -1.0 : 1.0
        let lane = Double(index / 2)
        let drone = game.player + Vec2(x: side * (28 + lane * 13), y: 2 + sin(game.survivalTime * 4 + lane) * 4)
        circle(hdc, center: drone, radius: 6, color: game.shipType == .carrier ? rgb(197, 151, 255) : rgb(113, 213, 255))
        circle(hdc, center: drone + Vec2(x: 0, y: -1), radius: 2, color: rgb(238, 254, 255))
    }
    let flame = 15 + LONG(abs(sin(game.survivalTime * 20)) * 10)
    polygon(hdc, [POINT(x: x - 8, y: y + 20), POINT(x: x, y: y + flame + 20), POINT(x: x + 8, y: y + 20)], rgb(255, 161, 64))
    polygon(hdc, [POINT(x: x - 4, y: y + 20), POINT(x: x, y: y + flame + 12), POINT(x: x + 4, y: y + 20)], rgb(255, 238, 163))
    polygon(hdc, [POINT(x: x, y: y - 27), POINT(x: x - 15, y: y + 20), POINT(x: x - 48, y: y + 26),
                  POINT(x: x - 28, y: y + 3), POINT(x: x - 8, y: y - 2)], rgb(49, 151, 230))
    polygon(hdc, [POINT(x: x, y: y - 27), POINT(x: x + 15, y: y + 20), POINT(x: x + 48, y: y + 26),
                  POINT(x: x + 28, y: y + 3), POINT(x: x + 8, y: y - 2)], rgb(49, 151, 230))
    polygon(hdc, [POINT(x: x, y: y - 35), POINT(x: x - 13, y: y + 22), POINT(x: x + 13, y: y + 22)], rgb(101, 213, 251))
    circle(hdc, center: game.player + Vec2(x: 0, y: -8), radius: 6, color: rgb(229, 249, 255))
    circle(hdc, center: game.player + Vec2(x: 0, y: -8), radius: game.precisionMode ? 4.5 : 3.5,
           color: game.precisionMode ? rgb(255, 236, 112) : rgb(42, 99, 163))
    if game.laserTime > 0 || game.weaponType == .laser {
        let beamHalfWidth = LONG(2 + game.laserWidthLevel + (game.frostRayActive ? 2 : 0))
        let beamTint = game.frostRayActive ? rgb(131, 224, 255) : rgb(80, 226, 255)
        fill(hdc, RECT(left: x - beamHalfWidth, top: y - 120, right: x + beamHalfWidth, bottom: y - 28), beamTint)
        fill(hdc, RECT(left: x - max(1, beamHalfWidth / 2), top: y - 118, right: x + max(1, beamHalfWidth / 2), bottom: y - 28), rgb(231, 255, 255))
    }
}

func powerUpTint(_ kind: Int) -> COLORREF {
    switch kind {
    case 0: return rgb(91, 222, 255)
    case 1: return rgb(112, 184, 255)
    default: return rgb(106, 238, 143)
    }
}

func scaleColor(_ color: COLORREF, _ factor: Double) -> COLORREF {
    let r = UInt32(min(255, max(0, Double(color & 0xFF) * factor)))
    let g = UInt32(min(255, max(0, Double((color >> 8) & 0xFF) * factor)))
    let b = UInt32(min(255, max(0, Double((color >> 16) & 0xFF) * factor)))
    return rgb(r, g, b)
}

func overlay(_ hdc: HDC?, width: Double, height: Double, title: String, lines: [String]) {
    fill(hdc, RECT(left: LONG(width / 2 - 310), top: LONG(height / 2 - 175), right: LONG(width / 2 + 310), bottom: LONG(height / 2 + 175)), rgb(13, 24, 51))
    drawText(hdc, title, RECT(left: LONG(width / 2 - 290), top: LONG(height / 2 - 142), right: LONG(width / 2 + 290), bottom: LONG(height / 2 - 92)), rgb(244, 208, 113), 26, DT_CENTER)
    for (index, line) in lines.enumerated() {
        let y = LONG(height / 2 - 66 + Double(index) * 34)
        drawText(hdc, line, RECT(left: LONG(width / 2 - 290), top: y, right: LONG(width / 2 + 290), bottom: y + 28), rgb(218, 231, 249), 16, DT_CENTER)
    }
}

// MARK: - Window procedure

enum WindowRuntime {
    static let timerID: UINT_PTR = 1
    static let displayModeMessage: UINT = UINT(WM_APP) + 1
    nonisolated(unsafe) static var hwnd: HWND?
    nonisolated(unsafe) static var isFullscreen = true
    nonisolated(unsafe) static var windowedRect = RECT()
}

func applyWindowMode(_ hwnd: HWND?, fullscreen: Bool) {
    guard let hwnd else { return }

    // Keep the last windowed frame so switching back feels like a normal
    // desktop app instead of resetting the user's size and position.
    if fullscreen && !WindowRuntime.isFullscreen {
        var current = RECT()
        _ = GetWindowRect(hwnd, &current)
        if current.right > current.left && current.bottom > current.top {
            WindowRuntime.windowedRect = current
        }
    }

    // The 32-bit GetWindowLongW/SetWindowLongW entry points are marked as
    // unavailable by the Swift WinSDK overlay on x64 and lower to `ud2`.
    // Calling the pointer-sized variants avoids the 0xc000001d trap that was
    // previously reported during intermittent Boss/display transitions.
    var style = GetWindowLongPtrW(hwnd, Int32(GWL_STYLE))
    let framedStyle = LONG_PTR(WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_THICKFRAME)
    if fullscreen {
        style &= ~framedStyle
        style |= LONG_PTR(WS_POPUP)
        _ = SetWindowLongPtrW(hwnd, Int32(GWL_STYLE), style)
        let screenWidth = max(640, GetSystemMetrics(0))
        let screenHeight = max(480, GetSystemMetrics(1))
        _ = SetWindowPos(hwnd, nil, 0, 0, screenWidth, screenHeight,
                         UINT(SWP_FRAMECHANGED | SWP_SHOWWINDOW))
    } else {
        style &= ~LONG_PTR(WS_POPUP)
        style |= LONG_PTR(WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_THICKFRAME)
        _ = SetWindowLongPtrW(hwnd, Int32(GWL_STYLE), style)

        let screenWidth = max(800, GetSystemMetrics(0))
        let screenHeight = max(600, GetSystemMetrics(1))
        let requestedWidth: Int32 = Game.shared.profile.resolutionWidth == 1024 ? 1024 : 1280
        let requestedHeight: Int32 = requestedWidth == 1024 ? 768 : 720
        let clientWidth = min(requestedWidth, screenWidth - 80)
        let clientHeight = min(requestedHeight, screenHeight - 100)
        var frame = RECT(left: 0, top: 0, right: LONG(clientWidth), bottom: LONG(clientHeight))
        let fullStyle = DWORD(WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_THICKFRAME)
        _ = AdjustWindowRectEx(&frame, fullStyle, false, 0)
        let outerWidth = frame.right - frame.left
        let outerHeight = frame.bottom - frame.top
        let left = LONG((screenWidth - Int32(outerWidth)) / 2)
        let top = LONG((screenHeight - Int32(outerHeight)) / 2)
        let target = RECT(left: left, top: top, right: left + outerWidth, bottom: top + outerHeight)
        WindowRuntime.windowedRect = target
        _ = SetWindowPos(hwnd, nil, target.left, target.top,
                         target.right - target.left, target.bottom - target.top,
                         UINT(SWP_FRAMECHANGED | SWP_SHOWWINDOW))
    }
    WindowRuntime.isFullscreen = fullscreen
    _ = InvalidateRect(hwnd, nil, false)
}

final class WindowBackBuffer: @unchecked Sendable {
    private var dc: HDC?
    private var bitmap: HBITMAP?
    private var previousBitmap: HGDIOBJ?
    private var width: Int32 = 0
    private var height: Int32 = 0

    func ensure(windowDC: HDC?, width: Int32, height: Int32) -> HDC? {
        guard let windowDC, width > 0, height > 0 else { return nil }
        if dc == nil || bitmap == nil || self.width != width || self.height != height {
            release()
            guard let newDC = CreateCompatibleDC(windowDC),
                  let newBitmap = CreateCompatibleBitmap(windowDC, width, height) else {
                release()
                return nil
            }
            dc = newDC
            bitmap = newBitmap
            previousBitmap = SelectObject(newDC, HGDIOBJ(newBitmap))
            self.width = width
            self.height = height
        }
        return dc
    }

    func release() {
        if let dc, let previousBitmap {
            _ = SelectObject(dc, previousBitmap)
        }
        if let bitmap {
            _ = DeleteObject(HGDIOBJ(bitmap))
        }
        if let dc {
            _ = DeleteDC(dc)
        }
        dc = nil
        bitmap = nil
        previousBitmap = nil
        width = 0
        height = 0
    }
}

let windowBackBuffer = WindowBackBuffer()

func renderWindowFrame(_ hwnd: HWND?, windowDC: HDC?) {
    guard let windowDC else { return }
    var rect = RECT()
    _ = GetClientRect(hwnd, &rect)
    let width = max(1, rect.right)
    let height = max(1, rect.bottom)
    guard let backDC = windowBackBuffer.ensure(windowDC: windowDC, width: width, height: height) else { return }
    let viewport = viewportMetrics(pixelWidth: width, pixelHeight: height)
    // Render the whole game in logical coordinates, then let GDI scale the
    // completed frame to the physical client surface. Save/restore keeps the
    // back buffer in normal pixel coordinates for the final BitBlt.
    let savedDC = SaveDC(backDC)
    _ = SetMapMode(backDC, MM_ANISOTROPIC)
    _ = SetWindowExtEx(backDC, LONG(viewport.logicalWidth), LONG(viewport.logicalHeight), nil)
    _ = SetViewportExtEx(backDC, width, height, nil)
    drawGame(backDC, width: viewport.logicalWidth, height: viewport.logicalHeight)
    if savedDC > 0 { _ = RestoreDC(backDC, savedDC) }
    _ = BitBlt(windowDC, 0, 0, width, height, backDC, 0, 0, DWORD(SRCCOPY))
    Game.shared.recordPresentedFrame(at: Date().timeIntervalSinceReferenceDate)
}

func clientCursorPosition(_ hwnd: HWND?) -> Vec2 {
    var point = POINT()
    _ = GetCursorPos(&point)
    _ = ScreenToClient(hwnd, &point)
    let viewport = clientViewportMetrics(hwnd)
    return Vec2(x: Double(point.x) / viewport.scale, y: Double(point.y) / viewport.scale)
}

func clientViewportMetrics(_ hwnd: HWND?) -> ViewportMetrics {
    var rect = RECT()
    _ = GetClientRect(hwnd, &rect)
    return viewportMetrics(pixelWidth: max(1, rect.right), pixelHeight: max(1, rect.bottom))
}

func windowProc(_ hwnd: HWND?, _ message: UINT, _ wParam: WPARAM, _ lParam: LPARAM) -> LRESULT {
    switch message {
    case UINT(WM_CREATE):
        _ = timeBeginPeriod(1)
        // Wake frequently, then gate simulation/presentation with the precise
        // 60 Hz deadline below. A 16 ms SetTimer adds render time to the next
        // wait and measured only ~40 FPS on high-DPI Windows systems.
        _ = SetTimer(hwnd, WindowRuntime.timerID, 1, nil)
        AudioManager.shared.configure(bgmVolume: SaveManager.shared.profile.bgmVolume,
                                      sfxVolume: SaveManager.shared.profile.sfxVolume)
        AudioManager.shared.startMusic()
        return 0
    case WindowRuntime.displayModeMessage:
        applyWindowMode(hwnd, fullscreen: Game.shared.profile.isFullscreen)
        return 0
    case UINT(WM_TIMER):
        if wParam == WindowRuntime.timerID {
            let now = Date().timeIntervalSinceReferenceDate
            let frameInterval = 1.0 / 60.0
            guard now + 0.0002 >= Game.shared.nextFrameDeadline else { return 0 }
            var rect = RECT()
            _ = GetClientRect(hwnd, &rect)
            let delta = now - Game.shared.lastTime
            Game.shared.lastTime = now
            Game.shared.nextFrameDeadline += frameInterval
            // If the app was paused by the OS or dragged between monitors,
            // discard the stale backlog instead of trying to render it.
            if Game.shared.nextFrameDeadline < now - frameInterval * 2 {
                Game.shared.nextFrameDeadline = now + frameInterval
            }
            let viewport = viewportMetrics(pixelWidth: max(1, rect.right), pixelHeight: max(1, rect.bottom))
            Game.shared.advanceFixed(realDelta: delta,
                                     width: viewport.logicalWidth,
                                     height: viewport.logicalHeight)
            // Render and present in the same timer message. WM_PAINT is a
            // low-priority message and can be delayed behind input/audio,
            // which previously produced irregular visual frame pacing.
            if let windowDC = GetDC(hwnd) {
                renderWindowFrame(hwnd, windowDC: windowDC)
                _ = ReleaseDC(hwnd, windowDC)
                _ = ValidateRect(hwnd, nil)
            }
        }
        return 0
    case UINT(WM_ERASEBKGND):
        return 1
    case UINT(WM_MOUSEMOVE):
        Game.shared.updateMousePosition(clientCursorPosition(hwnd))
        return 0
    case UINT(WM_LBUTTONDOWN):
        let point = clientCursorPosition(hwnd)
        Game.shared.updateMousePosition(point)
        let viewport = clientViewportMetrics(hwnd)
        Game.shared.handleClick(at: point, width: viewport.logicalWidth, height: viewport.logicalHeight)
        _ = InvalidateRect(hwnd, nil, false)
        return 0
    case UINT(WM_KEYDOWN):
        if wParam == 0x0D, Game.shared.phase == .menu {
            let viewport = clientViewportMetrics(hwnd)
            Game.shared.start(width: viewport.logicalWidth, height: viewport.logicalHeight)
        }
        if wParam == 0x0D, Game.shared.phase == .missionSelect {
            let viewport = clientViewportMetrics(hwnd)
            Game.shared.start(width: viewport.logicalWidth, height: viewport.logicalHeight)
        }
        if Game.shared.phase == .controls, wParam == 0x31 { Game.shared.setControlMode(.wasd) }
        if Game.shared.phase == .controls, wParam == 0x32 { Game.shared.setControlMode(.mouse) }
        if Game.shared.phase == .upgrade, wParam >= 0x31 && wParam <= 0x33 { Game.shared.chooseUpgrade(Int(wParam - 0x31)) }
        if wParam == 0x52, Game.shared.phase == .gameOver {
            let viewport = clientViewportMetrics(hwnd)
            Game.shared.start(width: viewport.logicalWidth, height: viewport.logicalHeight)
        }
        if wParam == 0x20 {
            Game.shared.activateThunderOverload()
        }
        if wParam == 0x51, Game.shared.phase == .playing {
            Game.shared.cycleWeapon()
        }
        if wParam == 0x50 || wParam == 0x1B {
            switch Game.shared.phase {
            case .playing, .paused:
                Game.shared.togglePause()
            case .saveSlots:
                Game.shared.phase = Game.shared.phaseBeforeSaveSlots
            case .controls:
                Game.shared.phase = Game.shared.phaseBeforeControls
            case .settings:
                Game.shared.phase = Game.shared.phaseBeforeSettings
            case .missionSelect:
                Game.shared.phase = .menu
            case .archive:
                Game.shared.phase = .menu
            case .hangar:
                Game.shared.phase = .menu
            case .menu:
                if wParam == 0x1B { PostQuitMessage(0) }
            case .gameOver:
                if wParam == 0x1B { Game.shared.phase = .menu }
            case .upgrade:
                break
            }
        }
        return 0
    case UINT(WM_PAINT):
        var paint = PAINTSTRUCT()
        guard let windowDC = BeginPaint(hwnd, &paint) else { return 0 }
        renderWindowFrame(hwnd, windowDC: windowDC)
        _ = EndPaint(hwnd, &paint)
        return 0
    case UINT(WM_DESTROY):
        _ = KillTimer(hwnd, WindowRuntime.timerID)
        _ = timeEndPeriod(1)
        windowBackBuffer.release()
        GDIBrushCache.shared.release()
        Game.shared.persistProfile()
        AudioManager.shared.stopMusic()
        PostQuitMessage(0)
        return 0
    default:
        return DefWindowProcW(hwnd, message, wParam, lParam)
    }
}

@main
struct SwiftSurvivorApp {
    static func main() {
        if CommandLine.arguments.contains("--sdl-smoke") {
            SDLSmoke.run()
            return
        }
        if CommandLine.arguments.contains("--sdl-game") {
            SDLGameplaySlice.run()
            return
        }
        if CommandLine.arguments.contains("--sdl-full") {
            SDLFullGame.run()
            return
        }
        if CommandLine.arguments.contains("--sdl-audio-smoke") {
            SDLAudioSmoke.run()
            return
        }
        // Opt out of Windows bitmap DPI virtualization. On high-DPI laptops
        // the old behavior rendered a much larger off-screen surface and then
        // scaled every frame, which both blurred the UI and caused stutter.
        _ = SetProcessDPIAware()
        let instance = GetModuleHandleW(nil)
        let className = wide("SwiftSurvivorWindow")
        var windowClass = WNDCLASSEXW()
        windowClass.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
        windowClass.style = UINT(CS_HREDRAW | CS_VREDRAW)
        windowClass.lpfnWndProc = windowProc
        windowClass.hInstance = instance
        windowClass.hCursor = LoadCursorW(nil, UnsafePointer<WCHAR>(bitPattern: 32512))
        windowClass.hbrBackground = nil
        className.withUnsafeBufferPointer { buffer in
            windowClass.lpszClassName = buffer.baseAddress
            _ = RegisterClassExW(&windowClass)
            let initialFullscreen = SaveManager.shared.profile.isFullscreen
            WindowRuntime.isFullscreen = initialFullscreen
            // Fullscreen uses a borderless surface; windowed mode starts as a
            // centered, resizable desktop window and can be changed later in
            // Settings without restarting the game.
            let screenWidth = max(640, GetSystemMetrics(0))
            let screenHeight = max(480, GetSystemMetrics(1))
            let savedResolutionWidth: Int32 = SaveManager.shared.profile.resolutionWidth == 1024 ? 1024 : 1280
            let savedResolutionHeight: Int32 = savedResolutionWidth == 1024 ? 768 : 720
            var initialWindowFrame = RECT(left: 0, top: 0,
                                          right: LONG(min(savedResolutionWidth, screenWidth - 80)),
                                          bottom: LONG(min(savedResolutionHeight, screenHeight - 100)))
            let framedStyle = DWORD(WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_THICKFRAME)
            _ = AdjustWindowRectEx(&initialWindowFrame, framedStyle, false, 0)
            let windowedWidth = Int32(initialWindowFrame.right - initialWindowFrame.left)
            let windowedHeight = Int32(initialWindowFrame.bottom - initialWindowFrame.top)
            let initialWidth = initialFullscreen ? screenWidth : windowedWidth
            let initialHeight = initialFullscreen ? screenHeight : windowedHeight
            let initialX = initialFullscreen ? 0 : (screenWidth - windowedWidth) / 2
            let initialY = initialFullscreen ? 0 : (screenHeight - windowedHeight) / 2
            if !initialFullscreen {
                WindowRuntime.windowedRect = RECT(left: LONG(initialX), top: LONG(initialY),
                                                  right: LONG(initialX + windowedWidth),
                                                  bottom: LONG(initialY + windowedHeight))
            }
            let windowStyle: DWORD = initialFullscreen
                ? DWORD(WS_POPUP)
                : DWORD(WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_THICKFRAME)
            guard let hwnd = CreateWindowExW(0, buffer.baseAddress, buffer.baseAddress,
                                              windowStyle,
                                              initialX, initialY, initialWidth, initialHeight,
                                              nil, nil, instance, nil) else { return }
            WindowRuntime.hwnd = hwnd
            _ = ShowWindow(hwnd, SW_SHOW)
            _ = UpdateWindow(hwnd)
            Game.shared.resetFrameClock(at: Date().timeIntervalSinceReferenceDate)
            var message = MSG()
            while GetMessageW(&message, nil, 0, 0) {
                _ = TranslateMessage(&message)
                _ = DispatchMessageW(&message)
            }
        }
    }
}
