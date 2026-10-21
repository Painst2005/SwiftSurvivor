import Foundation

/// 装备系统配置目录：Resources/Data 下 7 个 JSON 的唯一加载入口与派生计算。
/// 配置加载失败会打印明确错误并以非零码退出（不静默兜底）。
final class EquipmentCatalog {
    nonisolated(unsafe) static let shared = EquipmentCatalog()

    let stageChain: [EquipmentStage]
    let seriesList: [EquipmentSeries]
    let curve: EquipmentCurveConfig
    let materials: [MaterialDef]
    let experienceSources: [ExperienceDef]
    let expPerLevel: ExpPerLevel
    let guaranteedGift: GuaranteedGift
    let drops: MaterialDropsConfig
    let recipes: [WarriorRecipe]
    let synergyConfig: WarriorSynergyConfig
    let powerGates: PowerGatesConfig

    private let stageByIndex: [Int: EquipmentStage]
    private let seriesByID: [String: EquipmentSeries]
    private let curveByStage: [Int: StageCurve]
    private let recipeByID: [String: WarriorRecipe]

    private init() {
        let dataRoot = EquipmentCatalog.resolveDataRoot()
        func load<T: Decodable>(_ name: String, _ type: T.Type) -> T {
            guard let url = dataRoot?.appendingPathComponent(name),
                  let data = try? Data(contentsOf: url) else {
                FileHandle.standardError.write("EQUIPMENT_CONFIG_ERROR: 缺少配置文件 \(name)（查找目录：\(dataRoot?.path ?? "未找到 Resources/Data")）\n".data(using: .utf8)!)
                exit(1)
            }
            do {
                return try JSONDecoder().decode(type, from: data)
            } catch {
                FileHandle.standardError.write("EQUIPMENT_CONFIG_ERROR: \(name) 解析失败 - \(error.localizedDescription)\n".data(using: .utf8)!)
                exit(1)
            }
        }
        // equipment_series.json 顶层还带 slots 字段；用包装结构吸收。
        struct SeriesFile: Decodable {
            var slots: [EquipmentSlot]
            var series: [EquipmentSeries]
        }
        let stagesFile: EquipmentStagesFile = load("equipment_stages.json", EquipmentStagesFile.self)
        let seriesFile: SeriesFile = load("equipment_series.json", SeriesFile.self)
        let curveFile: EquipmentCurveFile = load("equipment_curve.json", EquipmentCurveFile.self)
        let materialsFile: EquipmentMaterialsFile = load("equipment_materials.json", EquipmentMaterialsFile.self)
        let dropsFile: MaterialDropsFile = load("material_drops.json", MaterialDropsFile.self)
        let recipesFile: WarriorRecipesFile = load("warrior_recipes.json", WarriorRecipesFile.self)
        let synergyFile: WarriorSynergyConfig = load("warrior_synergy.json", WarriorSynergyConfig.self)
        let powerGatesFile: PowerGatesConfig = load("power_gates.json", PowerGatesConfig.self)

        stageChain = stagesFile.stages.sorted { $0.stage < $1.stage }
        seriesList = seriesFile.series
        curve = EquipmentCurveConfig(unitPowerDivisor: curveFile.unitPowerDivisor, curves: curveFile.curves)
        materials = materialsFile.materials
        experienceSources = materialsFile.experience
        expPerLevel = materialsFile.expPerLevel
        guaranteedGift = materialsFile.guaranteedGift
        drops = MaterialDropsConfig(missionCount: dropsFile.missionCount, drops: dropsFile.drops,
                                    sameNameDrop: dropsFile.sameNameDrop, endless: dropsFile.endless)
        recipes = recipesFile.recipes
        synergyConfig = synergyFile
        powerGates = powerGatesFile

        stageByIndex = Dictionary(uniqueKeysWithValues: stageChain.map { ($0.stage, $0) })
        seriesByID = Dictionary(uniqueKeysWithValues: seriesList.map { ($0.id, $0) })
        curveByStage = Dictionary(uniqueKeysWithValues: curve.curves.map { ($0.stage, $0) })
        recipeByID = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0) })
    }

    /// 数据根目录定位与 SDLGameArt 一致：优先当前工作目录，其次可执行文件目录。
    static func resolveDataRoot() -> URL? {
        let fileManager = FileManager.default
        var candidates = [URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent("Resources/Data")]
        if let executable = CommandLine.arguments.first {
            candidates.append(URL(fileURLWithPath: executable).deletingLastPathComponent()
                .appendingPathComponent("Resources/Data"))
        }
        return candidates.first { fileManager.fileExists(atPath: $0.path) }
    }

    // MARK: - 阶链查询

    func stageInfo(_ stage: Int) -> EquipmentStage? { stageByIndex[stage] }
    // 兜底值全部由配置表派生（满阶链末端 / 链首），不在代码里留数据魔法数字。
    func levelCap(stage: Int) -> Int { stageByIndex[stage]?.levelCap ?? stageChain.last?.levelCap ?? 0 }
    func levelMin(stage: Int) -> Int { stageByIndex[stage]?.levelMin ?? stageChain.first?.levelMin ?? 0 }
    func stageSuffix(_ stage: Int) -> String { stageByIndex[stage]?.suffix ?? "" }
    func advanceCost(stage: Int) -> AdvanceCost? { stageByIndex[stage]?.advance ?? nil }

    // MARK: - 系列查询

    func series(id: String) -> EquipmentSeries? { seriesByID[id] }
    func series(slot: EquipmentSlot, tier: Int) -> EquipmentSeries? {
        seriesList.first { $0.slot == slot && $0.tier == tier }
    }

    func displayName(seriesId: String, stage: Int) -> String {
        guard let series = seriesByID[seriesId] else { return seriesId }
        return series.displayName(stage: stage, suffix: stageSuffix(stage))
    }

    func displayNameEn(seriesId: String, stage: Int) -> String {
        guard let series = seriesByID[seriesId] else { return seriesId.uppercased() }
        return series.displayNameEn(stage: stage, suffix: stageSuffix(stage))
    }

    // MARK: - 战力派生（规格第 7 节）

    /// 装甲血量锚点插值：阶内按等级线性插值。
    func armorHP(tier: Int, stage: Int, level: Int) -> Double {
        guard let entry = curveByStage[stage] else { return 0 }
        let tierIndex = min(4, max(0, tier - 1))
        guard entry.entryHp.indices.contains(tierIndex), entry.exitHp.indices.contains(tierIndex) else { return 0 }
        let lowHP = entry.entryHp[tierIndex], highHP = entry.exitHp[tierIndex]
        let lowLevel = entry.entryLevel, highLevel = entry.exitLevel
        if level <= lowLevel { return lowHP }
        if level >= highLevel { return highHP }
        guard highLevel > lowLevel else { return lowHP }
        let t = Double(level - lowLevel) / Double(highLevel - lowLevel)
        return lowHP + t * (highHP - lowHP)
    }

    /// 单件战力 = 装甲血量 ÷ 20（四舍五入）。四槽同品质同阶同级归一化相等。
    func unitPower(tier: Int, stage: Int, level: Int) -> Int {
        Int((armorHP(tier: tier, stage: stage, level: level) / curve.unitPowerDivisor).rounded())
    }

    // MARK: - 升级曲线

    /// expToNext(level, stage) = (base + level * slope) * stageMultiplier^stage。
    func expToNext(level: Int, stage: Int) -> Int {
        let base = expPerLevel.base + Double(max(1, level)) * expPerLevel.slope
        let scaled = base * pow(expPerLevel.stageMultiplier, Double(min(9, max(0, stage))))
        return max(1, Int(scaled.rounded()))
    }

    // MARK: - 材料查询

    func material(_ id: String) -> MaterialDef? { materials.first { $0.id == id } }
    func materialName(_ id: String) -> String { material(id)?.name ?? id }
    func materialNameEn(_ id: String) -> String { material(id)?.nameEn ?? id }
    func experience(_ id: String) -> ExperienceDef? { experienceSources.first { $0.id == id } }

    func missionDrops(_ mission: Int) -> MissionDrops? {
        drops.drops.first { $0.mission == mission }
    }

    // MARK: - 战神查询

    func recipe(id: String) -> WarriorRecipe? { recipeByID[id] }
    func warriorLevelCap(golden: Bool) -> Int {
        golden ? synergyConfig.golden.levelCap : synergyConfig.baseLevelCap
    }

    // MARK: - 战力门槛（规格第 7.4 节）

    /// 当前关卡/无尽波次的战力门槛。
    func powerGate(mission: Int? = nil, endlessWave: Int? = nil) -> Int {
        if let endlessWave { return powerGates.endlessGate(endlessWave) }
        return powerGates.missionGate(mission ?? 1)
    }

    /// 伤害折算：达标无衰减，不足按 战力/门槛 线性衰减，下限 minScale。
    func powerScale(power: Int, gate: Int) -> Double {
        guard gate > 0 else { return 1.0 }
        if power >= gate { return 1.0 }
        return max(powerGates.minScale, Double(power) / Double(gate))
    }

    // MARK: - 新玩家初始装备（五等品 starter 系，stage 0 lv1）

    static func starterEquipment() -> [EquipmentState] {
        let starters: [(EquipmentSlot, String)] = [
            (.fighter, "fighter_assault"),
            (.subweapon, "sub_tracking"),
            (.armor, "armor_diamond"),
            (.wingman, "wing_gun")
        ]
        return starters.map { slot, seriesId in
            EquipmentState(uid: "starter_\(slot.rawValue)", seriesId: seriesId,
                           stage: 0, level: 1, exp: 0, locked: false, equipped: true)
        }
    }
}

// MARK: - JSON 包装结构（吸收各文件顶层附加字段）

private struct EquipmentStagesFile: Decodable {
    var version: Int
    var slotOrder: [EquipmentSlot]
    var stages: [EquipmentStage]
    var expSources: [String: String]?
}

private struct EquipmentCurveFile: Decodable {
    var version: Int
    var unitPowerDivisor: Double
    var curves: [StageCurve]
    var gateCheckpoints: [GateCheckpoint]?
}

private struct GateCheckpoint: Decodable {
    var label: String
    var stage: Int
    var level: Int
    var hp: [Double]
}

private struct EquipmentMaterialsFile: Decodable {
    var version: Int
    var materials: [MaterialDef]
    var experience: [ExperienceDef]
    var expPerLevel: ExpPerLevel
    var guaranteedGift: GuaranteedGift
}

private struct MaterialDropsFile: Decodable {
    var version: Int
    var missionCount: Int
    var drops: [MissionDrops]
    var sameNameDrop: SameNameDropConfig
    var endless: EndlessDropsConfig
}

private struct WarriorRecipesFile: Decodable {
    var version: Int
    var slots: [WarriorSlot]
    var recipes: [WarriorRecipe]
}
