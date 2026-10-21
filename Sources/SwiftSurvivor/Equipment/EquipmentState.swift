import Foundation

/// 装备存档模型 v7（推翻 v6 的 id/rarity/stars/evolution/affix 旧模型）。
/// 一件装备 = 系列（决定 tier/slot/弹道签名/技能）+ 阶 + 级 + 经验。
/// tier 由 seriesId 派生，不单独存储（规格第 3 节：系列 ID 与显示名分离）。
struct EquipmentState: Codable {
    var uid: String
    var seriesId: String
    /// 0..9 品质阶（规格第 4 节晋升链）。
    var stage: Int
    var level: Int
    /// 当前等级内已累积经验。
    var exp: Int
    var locked: Bool
    /// true = 正在四槽位上出战；inventory 中的备用件为 false。
    var equipped: Bool

    init(uid: String, seriesId: String, stage: Int, level: Int, exp: Int = 0,
         locked: Bool = false, equipped: Bool = false) {
        self.uid = uid
        self.seriesId = seriesId
        self.stage = stage
        self.level = level
        self.exp = exp
        self.locked = locked
        self.equipped = equipped
    }

    private enum CodingKeys: String, CodingKey {
        case uid, seriesId, stage, level, exp, locked, equipped
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uid = try container.decode(String.self, forKey: .uid)
        seriesId = try container.decode(String.self, forKey: .seriesId)
        stage = min(9, max(0, try container.decodeIfPresent(Int.self, forKey: .stage) ?? 0))
        level = max(1, try container.decodeIfPresent(Int.self, forKey: .level) ?? 1)
        exp = max(0, try container.decodeIfPresent(Int.self, forKey: .exp) ?? 0)
        locked = try container.decodeIfPresent(Bool.self, forKey: .locked) ?? false
        equipped = try container.decodeIfPresent(Bool.self, forKey: .equipped) ?? false
    }

    // MARK: 派生属性（唯一事实来源 = 配置表）

    var series: EquipmentSeries? { EquipmentCatalog.shared.series(id: seriesId) }
    var slot: EquipmentSlot { series?.slot ?? .fighter }
    /// 1=一等品最优 … 5=五等品；未知系列（损坏存档）按 0 哨兵处理，不进战力曲线。
    var tier: Int { series?.tier ?? 0 }
    var levelCap: Int { EquipmentCatalog.shared.levelCap(stage: stage) }
    var stageSuffix: String { EquipmentCatalog.shared.stageInfo(stage)?.suffix ?? "" }
    var displayName: String { EquipmentCatalog.shared.displayName(seriesId: seriesId, stage: stage) }
    var displayNameEn: String { EquipmentCatalog.shared.displayNameEn(seriesId: seriesId, stage: stage) }
    /// 单件战力（规格第 7 节：四槽归一化，装甲血量 ÷ 20 读出）。
    var unitPower: Int { EquipmentCatalog.shared.unitPower(tier: tier, stage: stage, level: level) }
    var isMaxLevel: Bool { level >= levelCap }
    var isMaxStage: Bool { stage >= 9 }

    func advanceCost() -> AdvanceCost? { EquipmentCatalog.shared.advanceCost(stage: stage) }
}

/// 战神存档模型（规格第 8 节：两件紫装融合的第五层）。
/// 激活不消耗素材装备，仅占用：materialUIDs 记录被占用的两件装备。
struct WarriorState: Codable {
    var uid: String
    var recipeId: String
    /// 战神本体等级（基础上限 30，黄金战神 60）。
    var level: Int
    /// 当前等级内已累积经验（与装备同一曲线，stage 0）。
    var exp: Int
    /// 进阶阶级 +0..+9。
    var advanceStage: Int
    var golden: Bool
    /// 被占用的两件素材装备 uid（占用而非消耗，拆解即释放）。
    var materialUIDs: [String]
    var equipped: Bool

    init(uid: String, recipeId: String, level: Int = 1, exp: Int = 0, advanceStage: Int = 0,
         golden: Bool = false, materialUIDs: [String], equipped: Bool = false) {
        self.uid = uid
        self.recipeId = recipeId
        self.level = level
        self.exp = exp
        self.advanceStage = advanceStage
        self.golden = golden
        self.materialUIDs = materialUIDs
        self.equipped = equipped
    }

    private enum CodingKeys: String, CodingKey {
        case uid, recipeId, level, exp, advanceStage, golden, materialUIDs, equipped
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uid = try container.decode(String.self, forKey: .uid)
        recipeId = try container.decode(String.self, forKey: .recipeId)
        level = max(1, try container.decodeIfPresent(Int.self, forKey: .level) ?? 1)
        exp = max(0, try container.decodeIfPresent(Int.self, forKey: .exp) ?? 0)
        advanceStage = min(9, max(0, try container.decodeIfPresent(Int.self, forKey: .advanceStage) ?? 0))
        golden = try container.decodeIfPresent(Bool.self, forKey: .golden) ?? false
        materialUIDs = try container.decodeIfPresent([String].self, forKey: .materialUIDs) ?? []
        equipped = try container.decodeIfPresent(Bool.self, forKey: .equipped) ?? false
    }

    // MARK: 派生属性

    var recipe: WarriorRecipe? { EquipmentCatalog.shared.recipe(id: recipeId) }
    var slot: WarriorSlot { recipe?.slot ?? .warriorFighter }
    var displayName: String {
        guard let recipe else { return recipeId }
        let threshold = recipe.names.keys
            .compactMap { Int($0) }
            .filter { $0 <= advanceStage }
            .max() ?? 0
        return recipe.names[String(threshold)] ?? recipe.name
    }
    var levelCap: Int { EquipmentCatalog.shared.warriorLevelCap(golden: golden) }
    /// 同步率：初值 61% + 每进阶 1 阶 +2%，普通上限 80%，黄金战神再 +10%（上限 90%）。
    /// 只与战神本体阶级有关，与素材装备是否满级无关（冻结项 10）。
    var synergyRate: Double {
        let config = EquipmentCatalog.shared.synergyConfig
        var base = config.initialSynergy + Double(advanceStage) * config.synergyPerAdvance
        if golden { base += config.golden.bonusSynergy }
        let cap = golden ? config.golden.synergyCap : config.synergyCap
        return min(cap, base)
    }
    var isMaxLevel: Bool { level >= levelCap }
}
