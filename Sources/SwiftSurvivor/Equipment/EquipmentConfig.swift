import Foundation

// MARK: - 槽位（规格第 2 节：四槽位三攻一防）

/// 出战配置固定 4 个槽位：战机 / 副武器 / 装甲 / 僚机。
/// 同一件装备不允许跨槽位复用。
enum EquipmentSlot: String, CaseIterable, Codable {
    case fighter
    case subweapon
    case armor
    case wingman

    /// 配置表 equipment_stages.json 的 slotOrder，与 allCases 一致。
    /// 所有按"槽位下标"索引的代码（出战件数组、保底领取位、换装筛选）都必须依赖此顺序。
    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    /// 老存档 slot 编码（1=主武器 2=副武器 3=装甲 4=僚机）到新槽位的映射。
    static func fromLegacySlot(_ legacy: Int) -> EquipmentSlot? {
        switch legacy {
        case 1: return .fighter
        case 2: return .subweapon
        case 3: return .armor
        case 4: return .wingman
        default: return nil
        }
    }
}

/// 装甲生存被动技能（规格第 2 节：装甲提供生存类被动）。
enum ArmorSkill: String, Codable {
    case regen          // 魔龙之鳞：回血
    case scoreBonus     // 聚能之光：加分
    case damageBonus    // 黄金之铠：增攻
    case surviveLethal  // 神圣之力：免秒
    case damageReduction // 金刚护盾：减伤
}

// MARK: - 装备系列（规格第 3 节：4 槽 x 5 档 = 20 系列）

struct EquipmentSeries: Codable {
    var id: String
    var slot: EquipmentSlot
    /// 1=一等品（最优）… 5=五等品。
    var tier: Int
    var family: String
    var scenario: String
    /// 以阶为阈值的改名表：键为阈值阶，如 {"0": 脉冲突击, "2": 迅雷突击, "6": 雷霆突击}。
    var names: [String: String]
    var namesEn: [String: String]
    /// 仅装甲系列有值。
    var skill: ArmorSkill?
    /// 仅武器系列（战机/副武器/僚机）有值。
    var weaponProfile: WeaponProfile?

    /// 按 (系列, 阶) 查显示名：取不大于当前阶的最大阈值键，再拼阶级后缀。
    func displayName(stage: Int, suffix: String) -> String {
        let threshold = names.keys
            .compactMap { Int($0) }
            .filter { $0 <= stage }
            .max() ?? 0
        let base = names[String(threshold)] ?? id
        return suffix.isEmpty ? base : base + suffix
    }

    func displayNameEn(stage: Int, suffix: String) -> String {
        let threshold = namesEn.keys
            .compactMap { Int($0) }
            .filter { $0 <= stage }
            .max() ?? 0
        let base = namesEn[String(threshold)] ?? id.uppercased()
        return suffix.isEmpty ? base : base + suffix
    }
}

// MARK: - 品质—星级—阶数晋升链（规格第 4 节：10 阶）

/// 进阶到下一阶的消耗。materials 为四色材料各 each 个；
/// sameName 为同名装备件数（等级不限）；gold 为金币。
struct AdvanceCost: Codable {
    var materials: [String]
    var each: Int
    var sameName: Int
    var gold: Int
}

struct EquipmentStage: Codable {
    var stage: Int
    var color: String
    var stars: Int
    /// 阶级后缀："" / "+1" / "+2" / "+3"。
    var suffix: String
    var levelMin: Int
    var levelCap: Int
    /// nil 表示满阶（stage 9）不可再进阶。
    var advance: AdvanceCost?
}

// MARK: - 装甲血量曲线（规格第 7.3 节）

struct StageCurve: Codable {
    var stage: Int
    var entryLevel: Int
    /// 五档锚点，数组顺序 [tier1..tier5] = [魔龙, 聚能, 黄金, 神圣, 金刚]。
    var entryHp: [Double]
    var exitLevel: Int
    var exitHp: [Double]
}

struct EquipmentCurveConfig: Codable {
    var unitPowerDivisor: Double
    var curves: [StageCurve]
}

// MARK: - 进阶材料（规格第 6 节）

struct MaterialDef: Codable {
    var id: String
    var name: String
    var nameEn: String
    /// quantum（绿）/ mega（蓝）/ quark（紫）。
    var set: String
    var color: String
}

struct ExperienceDef: Codable {
    var id: String
    var name: String
    var nameEn: String
    /// 单件提供的经验值。
    var exp: Int
}

struct ExpPerLevel: Codable {
    var base: Double
    var slope: Double
    var stageMultiplier: Double
}

struct GuaranteedGift: Codable {
    var triggerLevel: Int
    var grant: [String]
}

struct EquipmentMaterialsConfig: Codable {
    var materials: [MaterialDef]
    var experience: [ExperienceDef]
    var expPerLevel: ExpPerLevel
    var guaranteedGift: GuaranteedGift
}

// MARK: - 关卡掉落映射（规格第 6 节 + 本项目 8 章结构）

struct MissionDrops: Codable {
    var mission: Int
    var normalWaves: [String]
    var boss: [String]
}

struct MaterialDropsConfig: Codable {
    var missionCount: Int
    var drops: [MissionDrops]
    var sameNameDrop: SameNameDropConfig
    var endless: EndlessDropsConfig
}

struct SameNameDropConfig: Codable {
    /// Boss 稀有掉落只会出自这三个系列（传奇掉落）。
    var bossRareDropSeries: [String]
    var pityBossDefeats: Int
}

struct EndlessDropsConfig: Codable {
    var equipmentCratePerWaves: Int
    var warriorMaterialPerBossWaves: Int
}

// MARK: - 雷霆战神（规格第 8 节）

enum WarriorSlot: String, CaseIterable, Codable {
    case warriorFighter = "warrior_fighter"
    case warriorArmor = "warrior_armor"
    case warriorSubweapon = "warrior_subweapon"
    case warriorWingman = "warrior_wingman"
}

enum WarriorConditionKind: String, Codable {
    case campaignMission
    case endlessBestScore
    case bossTypeDefeated
    case currencyTotal
}

struct WarriorCondition: Codable {
    var kind: WarriorConditionKind
    /// 数值型条件的值（campaignMission/endlessBestScore/currencyTotal）。
    var value: Int
    /// 原始值原文：bossTypeDefeated 用字符串（如 "rift"），其余为数字。
    var rawValue: String
    /// currencyTotal 条件的币种（如 alloy）。
    var currency: String?

    private enum CodingKeys: String, CodingKey {
        case kind, value, currency
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(WarriorConditionKind.self, forKey: .kind)
        currency = try container.decodeIfPresent(String.self, forKey: .currency)
        if let intValue = try? container.decode(Int.self, forKey: .value) {
            value = intValue
            rawValue = String(intValue)
        } else {
            let stringValue = try container.decode(String.self, forKey: .value)
            value = Int(stringValue) ?? 0
            rawValue = stringValue
        }
    }
}

struct WarriorMaterialRef: Codable {
    var seriesId: String
    /// 素材装备要求的最低阶（紫五星 = stage 6）。
    var minStage: Int
}

struct WarriorRecipe: Codable {
    var id: String
    var slot: WarriorSlot
    var tier: Int
    var name: String
    var nameEn: String
    var materials: [WarriorMaterialRef]
    var condition: WarriorCondition
    var names: [String: String]
}

struct WarriorRecipesConfig: Codable {
    var recipes: [WarriorRecipe]
}

struct WarriorSynergyConfig: Codable {
    var initialSynergy: Double
    var synergyPerAdvance: Double
    var synergyCap: Double
    var golden: WarriorGoldenConfig
    var baseLevelCap: Int
    var advanceMaterials: [String]
    var goldenMaterials: [String]
    /// 战神基础出力倍率：出战战神时面板 = 素材装备属性 × 该值，
    /// 实际输出再乘同步率（0.61 起步约等于素材本体，随进阶涨到 +28%）。
    var baseOutputScale: Double
}

// MARK: - 关卡战力门槛（规格第 7.4 节 + 第 12.2 节平滑公式）

/// 战力门槛 → 伤害折算：damageScale = power >= gate ? 1 : max(minScale, power/gate)。
struct PowerGatesConfig: Codable {
    /// 闯关模式 8 章门槛，按章序号（1..8）取值。
    var missionGates: [Int]
    /// 无尽模式第 1 波门槛；第 n 波 = endlessBase × endlessGrowth^(n-1)。
    var endlessBase: Int
    var endlessGrowth: Double
    /// 伤害折算下限（避免完全打不动）。
    var minScale: Double

    func missionGate(_ mission: Int) -> Int {
        guard !missionGates.isEmpty else { return 0 }
        let index = min(max(1, mission), missionGates.count) - 1
        return missionGates[index]
    }

    func endlessGate(_ wave: Int) -> Int {
        let step = max(1, wave) - 1
        return Int((Double(endlessBase) * pow(endlessGrowth, Double(min(60, step)))).rounded())
    }
}

struct WarriorGoldenConfig: Codable {
    var bonusSynergy: Double
    var synergyCap: Double
    var requiredAdvanceStage: Int
    var goldenMaterialSets: Int
    var levelCap: Int
}
