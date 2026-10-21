import Foundation

/// v6 及更早的旧装备模型，仅用于读老存档，读完即迁移、不再写回。
private struct LegacyEquipment: Codable {
    var id: String
    var name: String
    var slot: Int
    var level: Int
    var rarity: Int
    var stars: Int
    var evolution: Int
    var affix: Int
    var locked: Bool
}

/// v6 及更早的旧存档结构，仅用于迁移。
private struct LegacyPlayerProfile: Codable {
    var saveVersion: Int
    var credits: Int
    var cores: Int
    var alloy: Int
    var selectedShip: Int
    var language: Int
    var controlMode: String
    var bgmVolume: Int
    var sfxVolume: Int
    var cameraShake: Int
    var isFullscreen: Bool
    var resolutionWidth: Int
    var resolutionHeight: Int
    var uiScale: Int
    var unlockedMission: Int
    var equipment: [LegacyEquipment]
    var inventory: [LegacyEquipment]
    var totalKills: Int
    var totalBosses: Int
    var bestCombo: Int
    var bestScore: Int
    var totalRuns: Int
    var bossDropPity: Int
    var achievements: [String]
}

struct PlayerProfile: Codable {
    var saveVersion: Int
    var credits: Int
    var cores: Int
    var alloy: Int
    var selectedShip: Int
    var language: Int
    var controlMode: String
    var bgmVolume: Int
    var sfxVolume: Int
    var cameraShake: Int
    var isFullscreen: Bool
    var resolutionWidth: Int
    var resolutionHeight: Int
    /// UI readability scale in percent.  The value is intentionally discrete
    /// so it stays portable across window sizes and old save files.
    var uiScale: Int
    var unlockedMission: Int
    /// 四槽位出战装备（equipped=true），按槽位有序。
    var equipment: [EquipmentState]
    /// 备用装备池（equipped=false）。
    var inventory: [EquipmentState]
    /// 材料背包：进阶材料与经验素材 id → 数量。
    var materials: [String: Int]
    /// 雷霆战神（规格第 8 节融合层）。
    var warriors: [WarriorState]
    /// 已拆解战神的归档记录（规格第 8.2 节阶级保留）：拆解不洗白阶级与等级，重新合成时继承。
    var dissolvedWarriors: [WarriorState]
    /// 75 级送全套紫材料保底的领取标记，按四槽位索引。
    var quarkGiftClaimed: [Bool]
    var totalKills: Int
    var totalBosses: Int
    var bestCombo: Int
    var bestScore: Int
    /// 无尽模式历史最高分（战神配方 endlessBestScore 条件）。
    var endlessBestScore: Int
    /// 已击败过的 Boss 类型 id（战神配方 bossTypeDefeated 条件，如 rift）。
    var bossTypesDefeated: [String]
    var totalRuns: Int
    var bossDropPity: Int
    var achievements: [String]

    /// 新玩家初始装备：四槽位五等品 starter 系，stage 0 lv1。
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

    static var fresh: PlayerProfile {
        PlayerProfile(saveVersion: SaveManager.currentSaveVersion,
                      credits: 0,
                      cores: 0,
                      alloy: 0,
                      selectedShip: ShipType.thunder.rawValue,
                      language: GameLanguage.english.rawValue,
                      controlMode: ControlMode.wasd.rawValue,
                      bgmVolume: 70,
                      sfxVolume: 80,
                      cameraShake: 2,
                      isFullscreen: true,
                      resolutionWidth: 1280,
                      resolutionHeight: 720,
                      uiScale: 100,
                      unlockedMission: 1,
                      equipment: starterEquipment(),
                      inventory: [],
                      materials: [:],
                      warriors: [],
                      dissolvedWarriors: [],
                      quarkGiftClaimed: [false, false, false, false],
                      totalKills: 0,
                      totalBosses: 0,
                      bestCombo: 0,
                      bestScore: 0,
                      endlessBestScore: 0,
                      bossTypesDefeated: [],
                      totalRuns: 0,
                      bossDropPity: 0,
                      achievements: [])
    }

    init(saveVersion: Int,
         credits: Int,
         cores: Int,
         alloy: Int,
         selectedShip: Int,
         language: Int,
         controlMode: String,
         bgmVolume: Int,
         sfxVolume: Int,
         cameraShake: Int,
         isFullscreen: Bool = true,
         resolutionWidth: Int = 1280,
         resolutionHeight: Int = 720,
         uiScale: Int = 100,
         unlockedMission: Int,
         equipment: [EquipmentState],
         inventory: [EquipmentState],
         materials: [String: Int] = [:],
         warriors: [WarriorState] = [],
         dissolvedWarriors: [WarriorState] = [],
         quarkGiftClaimed: [Bool] = [false, false, false, false],
         totalKills: Int,
         totalBosses: Int,
         bestCombo: Int,
         bestScore: Int,
         endlessBestScore: Int = 0,
         bossTypesDefeated: [String] = [],
         totalRuns: Int,
         bossDropPity: Int,
         achievements: [String]) {
        self.saveVersion = max(SaveManager.currentSaveVersion, saveVersion)
        self.credits = credits
        self.cores = cores
        self.alloy = alloy
        self.selectedShip = selectedShip
        self.language = language
        self.controlMode = controlMode
        self.bgmVolume = min(100, max(0, bgmVolume))
        self.sfxVolume = min(100, max(0, sfxVolume))
        self.cameraShake = min(3, max(0, cameraShake))
        self.isFullscreen = isFullscreen
        if resolutionWidth == 1024 && resolutionHeight == 768 {
            self.resolutionWidth = 1024
            self.resolutionHeight = 768
        } else {
            self.resolutionWidth = 1280
            self.resolutionHeight = 720
        }
        self.uiScale = [80, 90, 100, 110, 120].contains(uiScale) ? uiScale : 100
        self.unlockedMission = max(1, unlockedMission)
        self.equipment = equipment
        self.inventory = inventory
        self.materials = materials
        self.warriors = warriors
        self.dissolvedWarriors = dissolvedWarriors
        self.quarkGiftClaimed = quarkGiftClaimed
        self.totalKills = totalKills
        self.totalBosses = totalBosses
        self.bestCombo = bestCombo
        self.bestScore = bestScore
        self.endlessBestScore = endlessBestScore
        self.bossTypesDefeated = bossTypesDefeated
        self.totalRuns = totalRuns
        self.bossDropPity = bossDropPity
        self.achievements = achievements
    }

    private enum CodingKeys: String, CodingKey {
        case saveVersion, credits, cores, alloy, selectedShip, language, controlMode, bgmVolume, sfxVolume, cameraShake, isFullscreen, resolutionWidth, resolutionHeight, uiScale, unlockedMission, equipment, inventory, materials, warriors, dissolvedWarriors, quarkGiftClaimed
        case totalKills, totalBosses, bestCombo, bestScore, endlessBestScore, bossTypesDefeated, totalRuns, bossDropPity, achievements
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decodeIfPresent(Int.self, forKey: .saveVersion) ?? 1
        if version < SaveManager.currentSaveVersion {
            // 老存档（v6 及更早）：整体按旧结构解码后迁移，迁移逻辑集中在一处。
            let legacy = try LegacyPlayerProfile(from: decoder)
            self = PlayerProfile.migrated(from: legacy)
            return
        }
        saveVersion = SaveManager.currentSaveVersion
        credits = try container.decodeIfPresent(Int.self, forKey: .credits) ?? 0
        cores = try container.decodeIfPresent(Int.self, forKey: .cores) ?? 0
        alloy = try container.decodeIfPresent(Int.self, forKey: .alloy) ?? 0
        selectedShip = try container.decodeIfPresent(Int.self, forKey: .selectedShip) ?? ShipType.thunder.rawValue
        language = try container.decodeIfPresent(Int.self, forKey: .language) ?? GameLanguage.english.rawValue
        controlMode = try container.decodeIfPresent(String.self, forKey: .controlMode) ?? ControlMode.wasd.rawValue
        bgmVolume = min(100, max(0, try container.decodeIfPresent(Int.self, forKey: .bgmVolume) ?? 70))
        sfxVolume = min(100, max(0, try container.decodeIfPresent(Int.self, forKey: .sfxVolume) ?? 80))
        cameraShake = min(3, max(0, try container.decodeIfPresent(Int.self, forKey: .cameraShake) ?? 2))
        isFullscreen = try container.decodeIfPresent(Bool.self, forKey: .isFullscreen) ?? true
        let loadedWidth = try container.decodeIfPresent(Int.self, forKey: .resolutionWidth) ?? 1280
        let loadedHeight = try container.decodeIfPresent(Int.self, forKey: .resolutionHeight) ?? 720
        if loadedWidth == 1024 && loadedHeight == 768 {
            resolutionWidth = 1024
            resolutionHeight = 768
        } else {
            resolutionWidth = 1280
            resolutionHeight = 720
        }
        let loadedUIScale = try container.decodeIfPresent(Int.self, forKey: .uiScale) ?? 100
        uiScale = [80, 90, 100, 110, 120].contains(loadedUIScale) ? loadedUIScale : 100
        unlockedMission = max(1, try container.decodeIfPresent(Int.self, forKey: .unlockedMission) ?? 1)
        var loadedEquipment = (try? container.decode([EquipmentState].self, forKey: .equipment)) ?? []
        var loadedInventory = (try? container.decode([EquipmentState].self, forKey: .inventory)) ?? []
        // v7：equipment 只放四槽位出战件；未知系列/未标记出战的遗留数据一律裁掉。
        loadedEquipment.removeAll { $0.series == nil || !$0.equipped }
        loadedInventory.removeAll { $0.equipped }
        for starter in PlayerProfile.starterEquipment() where !loadedEquipment.contains(where: { $0.slot == starter.slot }) {
            loadedEquipment.append(starter)
        }
        equipment = loadedEquipment.sorted { $0.slot.order < $1.slot.order }
        inventory = loadedInventory
        materials = (try? container.decode([String: Int].self, forKey: .materials)) ?? [:]
        warriors = (try? container.decode([WarriorState].self, forKey: .warriors)) ?? []
        dissolvedWarriors = (try? container.decode([WarriorState].self, forKey: .dissolvedWarriors)) ?? []
        var gifts = (try? container.decode([Bool].self, forKey: .quarkGiftClaimed)) ?? []
        while gifts.count < 4 { gifts.append(false) }
        quarkGiftClaimed = Array(gifts.prefix(4))
        totalKills = try container.decodeIfPresent(Int.self, forKey: .totalKills) ?? 0
        totalBosses = try container.decodeIfPresent(Int.self, forKey: .totalBosses) ?? 0
        bestCombo = try container.decodeIfPresent(Int.self, forKey: .bestCombo) ?? 0
        bestScore = try container.decodeIfPresent(Int.self, forKey: .bestScore) ?? 0
        endlessBestScore = try container.decodeIfPresent(Int.self, forKey: .endlessBestScore) ?? 0
        bossTypesDefeated = try container.decodeIfPresent([String].self, forKey: .bossTypesDefeated) ?? []
        totalRuns = try container.decodeIfPresent(Int.self, forKey: .totalRuns) ?? 0
        bossDropPity = try container.decodeIfPresent(Int.self, forKey: .bossDropPity) ?? 0
        achievements = try container.decodeIfPresent([String].self, forKey: .achievements) ?? []
    }

    // MARK: - v6 → v7 迁移

    private static func migrated(from legacy: LegacyPlayerProfile) -> PlayerProfile {
        let catalog = EquipmentCatalog.shared

        // v6 时期的槽位修正：去掉机架槽；aegis 装甲 2→3、轨道僚机 3→4。
        func legacySlot(_ item: LegacyEquipment) -> Int {
            if item.id == "aegis_armor", item.slot == 2 { return 3 }
            if item.id == "orbit_drone", item.slot == 3 { return 4 }
            return item.slot
        }

        // 旧 id/name → 新系列 ID。
        func legacySeriesID(_ item: LegacyEquipment) -> String? {
            switch item.id {
            case "arc_cannon": return "fighter_assault"
            case "nova_payload": return "sub_tracking"
            case "aegis_armor": return "armor_diamond"
            case "orbit_drone": return "wing_gun"
            default: break
            }
            switch item.name {
            case "NOVA MISSILE": return "sub_blast"
            case "FROST PLATING": return "armor_gold"
            case "STORM DRONE": return "wing_rapid"
            default: return nil
            }
        }

        func migrate(_ items: [LegacyEquipment], equipped: Bool) -> [EquipmentState] {
            var usedUIDs = Set<String>()
            var result: [EquipmentState] = []
            for item in items {
                let slotValue = legacySlot(item)
                guard (1...4).contains(slotValue),
                      let slot = EquipmentSlot.fromLegacySlot(slotValue) else { continue }
                // tier 映射 {0→5, 1→5, 2→4, 3→3, 4→1}；未知 id/译名按映射档位兜底选系列。
                let tierMap = [0: 5, 1: 5, 2: 4, 3: 3, 4: 1]
                let tier = tierMap[min(4, max(0, item.rarity))] ?? 5
                let seriesID = legacySeriesID(item)
                    ?? catalog.series(slot: slot, tier: tier)?.id
                    ?? "fighter_assault"
                let series = catalog.series(id: seriesID) ?? catalog.series(slot: slot, tier: tier)
                let resolvedSeriesID = series?.id ?? seriesID
                // stage = clamp(evolution + (rarity>=2 ? rarity-1 : 0), 0, 9)。
                let evolution = max(0, item.evolution)
                let rarityBonus = item.rarity >= 2 ? item.rarity - 1 : 0
                let stage = min(9, max(0, evolution + rarityBonus))
                let levelCap = catalog.levelCap(stage: stage)
                let levelMin = catalog.levelMin(stage: stage)
                // 只升不降：不低于新阶下限，不高于新阶上限。
                let level = min(levelCap, max(levelMin, max(1, item.level)))
                var uid = "\(item.id)_\(slotValue)"
                var suffix = 2
                while usedUIDs.contains(uid) {
                    uid = "\(item.id)_\(slotValue)_\(suffix)"
                    suffix += 1
                }
                usedUIDs.insert(uid)
                result.append(EquipmentState(uid: uid, seriesId: resolvedSeriesID, stage: stage,
                                             level: level, exp: 0, locked: item.locked, equipped: equipped))
            }
            return result
        }

        var migratedEquipment = migrate(legacy.equipment, equipped: true)
        // 老存档 equipment/inventory 同一 id 重复：仓库只保留未出战的备用件。
        let equippedUIDs = Set(migratedEquipment.map { $0.uid })
        var migratedInventory = migrate(legacy.inventory, equipped: false)
            .filter { !equippedUIDs.contains($0.uid) }

        for starter in PlayerProfile.starterEquipment()
        where !migratedEquipment.contains(where: { $0.slot == starter.slot }) {
            migratedEquipment.append(starter)
        }

        return PlayerProfile(saveVersion: SaveManager.currentSaveVersion,
                             credits: legacy.credits,
                             cores: legacy.cores,
                             alloy: legacy.alloy,
                             selectedShip: legacy.selectedShip,
                             language: legacy.language,
                             controlMode: ControlMode.wasd.rawValue,
                             bgmVolume: legacy.bgmVolume,
                             sfxVolume: legacy.sfxVolume,
                             cameraShake: legacy.cameraShake,
                             isFullscreen: legacy.isFullscreen,
                             resolutionWidth: legacy.resolutionWidth,
                             resolutionHeight: legacy.resolutionHeight,
                             uiScale: legacy.uiScale,
                             unlockedMission: legacy.unlockedMission,
                             equipment: migratedEquipment.sorted { $0.slot.order < $1.slot.order },
                             inventory: migratedInventory,
                             materials: [:],
                             warriors: [],
                             dissolvedWarriors: [],
                             quarkGiftClaimed: [false, false, false, false],
                             totalKills: legacy.totalKills,
                             totalBosses: legacy.totalBosses,
                             bestCombo: legacy.bestCombo,
                             bestScore: legacy.bestScore,
                             totalRuns: legacy.totalRuns,
                             bossDropPity: legacy.bossDropPity,
                             achievements: legacy.achievements)
    }
}

struct SaveSlotSummary {
    let slot: Int
    let profile: PlayerProfile?

    var exists: Bool { profile != nil }
}

final class SaveManager: @unchecked Sendable {
    static let shared = SaveManager()

    static let slotCount = 3
    /// 当前存档版本。v6 → v7：装备系统重做（系列/阶/级/材料背包/战神）。
    static let currentSaveVersion = 7
    private let profileKey = "SwiftSurvivor.profile.v3"
    private let legacyProfileKeyV2 = "SwiftSurvivor.profile.v2"
    private let legacyProfileKeyV1 = "SwiftSurvivor.profile.v1"
    private let backupKey = "SwiftSurvivor.profile.v3.backup"
    private let rootDirectory: URL
    private let activeSlotMarkerURL: URL
    private(set) var activeSlot: Int
    private(set) var profile: PlayerProfile
    private var summariesCache: [SaveSlotSummary]? = nil

    private init() {
        let gameRoot = SaveManager.gameRootDirectory()
        let root = SaveManager.prepareSaveDirectory(gameRoot: gameRoot)
        rootDirectory = root
        activeSlotMarkerURL = root.appendingPathComponent("SwiftSurvivor.active-slot")
        activeSlot = SaveManager.readActiveSlot(from: activeSlotMarkerURL)

        let slotProfile = SaveManager.loadProfile(at: SaveManager.slotURL(root: root, slot: activeSlot))
            ?? SaveManager.loadProfile(at: SaveManager.backupURL(root: root, slot: activeSlot))
        let legacyProfile = SaveManager.decode(UserDefaults.standard.data(forKey: profileKey))
            ?? SaveManager.decode(UserDefaults.standard.data(forKey: backupKey))
            ?? SaveManager.decode(UserDefaults.standard.data(forKey: legacyProfileKeyV2))
            ?? SaveManager.decode(UserDefaults.standard.data(forKey: legacyProfileKeyV1))
        profile = slotProfile ?? legacyProfile ?? PlayerProfile.fresh

        let needsMigration = profile.saveVersion < SaveManager.currentSaveVersion
            || profile.equipment.count != 4
            || profile.equipment.contains(where: { !$0.equipped })
        if slotProfile == nil || needsMigration {
            save(profile)
        } else {
            persistActiveSlot()
        }
    }

    func save(_ value: PlayerProfile) {
        var normalized = value
        normalized.saveVersion = SaveManager.currentSaveVersion
        // equipment 只保留四槽位出战件；缺失槽位用初始装备补齐。
        normalized.equipment.removeAll { !$0.equipped }
        for starter in PlayerProfile.starterEquipment()
        where !normalized.equipment.contains(where: { $0.slot == starter.slot }) {
            normalized.equipment.append(starter)
        }
        normalized.inventory.removeAll { $0.equipped }
        normalized.equipment.sort { $0.slot.order < $1.slot.order }
        profile = normalized
        summariesCache = nil
        if let data = try? JSONEncoder().encode(normalized) {
            let fileManager = FileManager.default
            let destination = SaveManager.slotURL(root: rootDirectory, slot: activeSlot)
            let backup = SaveManager.backupURL(root: rootDirectory, slot: activeSlot)
            if fileManager.fileExists(atPath: destination.path) {
                try? fileManager.removeItem(at: backup)
                try? fileManager.copyItem(at: destination, to: backup)
            }
            try? data.write(to: destination, options: .atomic)
            persistActiveSlot()
        }
    }

    @discardableResult
    func selectSlot(_ slot: Int) -> Bool {
        guard (0..<Self.slotCount).contains(slot) else { return false }
        if slot == activeSlot {
            persistActiveSlot()
            return true
        }

        // Flush the current profile before changing slots. All gameplay
        // mutations already autosave, but this also protects a slot switch
        // made immediately after a menu action.
        save(profile)
        activeSlot = slot
        summariesCache = nil
        let root = rootDirectory
        if let loaded = SaveManager.loadProfile(at: SaveManager.slotURL(root: root, slot: slot))
            ?? SaveManager.loadProfile(at: SaveManager.backupURL(root: root, slot: slot)) {
            profile = loaded
            persistActiveSlot()
        } else {
            profile = PlayerProfile.fresh
            save(profile)
        }
        return true
    }

    func slotSummaries() -> [SaveSlotSummary] {
        if let summariesCache { return summariesCache }
        let summaries = (0..<Self.slotCount).map { slot in
            let root = rootDirectory
            let loaded = SaveManager.loadProfile(at: SaveManager.slotURL(root: root, slot: slot))
                ?? SaveManager.loadProfile(at: SaveManager.backupURL(root: root, slot: slot))
            return SaveSlotSummary(slot: slot, profile: loaded)
        }
        summariesCache = summaries
        return summaries
    }

    var saveLocation: URL { rootDirectory }

    private func persistActiveSlot() {
        try? Data(String(activeSlot).utf8).write(to: activeSlotMarkerURL, options: .atomic)
    }

    private static func gameRootDirectory() -> URL {
        let fileManager = FileManager.default
        let current = URL(fileURLWithPath: fileManager.currentDirectoryPath).standardizedFileURL
        // `swift run` starts in the package root, while a double-clicked
        // executable may have an unrelated working directory. Prefer the
        // package/current directory when it is clearly the game root, then
        // fall back to the executable's directory.
        if fileManager.fileExists(atPath: current.appendingPathComponent("Package.swift").path)
            || fileManager.fileExists(atPath: current.appendingPathComponent("Resources").path) {
            return current
        }
        if let argument = CommandLine.arguments.first, !argument.isEmpty {
            return URL(fileURLWithPath: argument, relativeTo: current)
                .standardizedFileURL
                .deletingLastPathComponent()
        }
        return current
    }

    /// Keep every user-generated save artifact in one predictable folder.
    /// Existing root-level saves from versions before this layout are moved
    /// on first launch without overwriting a newer file already in `Save`.
    private static func prepareSaveDirectory(gameRoot: URL) -> URL {
        let fileManager = FileManager.default
        let saveRoot = gameRoot.appendingPathComponent("Save", isDirectory: true)
        try? fileManager.createDirectory(at: saveRoot, withIntermediateDirectories: true)

        var legacyNames = ["SwiftSurvivor.active-slot"]
        for slot in 1...slotCount {
            legacyNames.append("SwiftSurvivorSave\(slot).json")
            legacyNames.append("SwiftSurvivorSave\(slot).backup.json")
        }
        for name in legacyNames {
            let legacyURL = gameRoot.appendingPathComponent(name)
            let destinationURL = saveRoot.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: legacyURL.path),
                  !fileManager.fileExists(atPath: destinationURL.path) else { continue }
            try? fileManager.moveItem(at: legacyURL, to: destinationURL)
        }
        return saveRoot
    }

    private static func slotURL(root: URL, slot: Int) -> URL {
        root.appendingPathComponent("SwiftSurvivorSave\(slot + 1).json")
    }

    private static func backupURL(root: URL, slot: Int) -> URL {
        root.appendingPathComponent("SwiftSurvivorSave\(slot + 1).backup.json")
    }

    private static func readActiveSlot(from url: URL) -> Int {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              (0..<Self.slotCount).contains(value) else { return 0 }
        return value
    }

    private static func loadProfile(at url: URL) -> PlayerProfile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }

    private static func decode(_ data: Data?) -> PlayerProfile? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(PlayerProfile.self, from: data)
    }
}
