import Foundation

struct EquipmentState: Codable {
    var id: String
    var name: String
    var slot: Int
    var level: Int
    var rarity: Int
    var stars: Int
    var evolution: Int
    var affix: Int

    init(id: String, name: String, slot: Int, level: Int, rarity: Int, stars: Int = 1, evolution: Int = 0, affix: Int = 0) {
        self.id = id
        self.name = name
        self.slot = slot
        self.level = level
        self.rarity = rarity
        self.stars = stars
        self.evolution = evolution
        self.affix = affix
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, slot, level, rarity, stars, evolution, affix
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        slot = try container.decode(Int.self, forKey: .slot)
        // Levels are open-ended progression values. Clamp only malformed
        // negative save data; there is intentionally no upper bound.
        level = max(1, try container.decode(Int.self, forKey: .level))
        rarity = try container.decode(Int.self, forKey: .rarity)
        stars = try container.decodeIfPresent(Int.self, forKey: .stars) ?? 1
        evolution = try container.decodeIfPresent(Int.self, forKey: .evolution) ?? 0
        affix = try container.decodeIfPresent(Int.self, forKey: .affix) ?? 0
    }
}

struct PlayerProfile: Codable {
    var saveVersion: Int
    var credits: Int
    var cores: Int
    var alloy: Int
    var equippedWeapon: Int
    var selectedShip: Int
    var language: Int
    var controlMode: String
    var bgmVolume: Int
    var sfxVolume: Int
    var cameraShake: Int
    var isFullscreen: Bool
    var resolutionWidth: Int
    var resolutionHeight: Int
    var unlockedMission: Int
    var equipment: [EquipmentState]
    var inventory: [EquipmentState]
    var totalKills: Int
    var totalBosses: Int
    var bestCombo: Int
    var bestScore: Int
    var totalRuns: Int
    var bossDropPity: Int
    var achievements: [String]

    static var starterEquipment: [EquipmentState] {
        [
            EquipmentState(id: "thunder_frame", name: "THUNDER FRAME", slot: 0, level: 1, rarity: 1),
            EquipmentState(id: "arc_cannon", name: "ARC CANNON", slot: 1, level: 1, rarity: 1),
            EquipmentState(id: "nova_payload", name: "NOVA PAYLOAD", slot: 2, level: 1, rarity: 1),
            EquipmentState(id: "aegis_armor", name: "AEGIS ARMOR", slot: 3, level: 1, rarity: 0),
            EquipmentState(id: "orbit_drone", name: "ORBIT DRONE", slot: 4, level: 1, rarity: 2)
        ]
    }

    static var fresh: PlayerProfile {
        let starter = starterEquipment
        return PlayerProfile(saveVersion: 5,
                             credits: 0,
                             cores: 0,
                             alloy: 0,
                             equippedWeapon: WeaponType.cannon.rawValue,
                             selectedShip: ShipType.thunder.rawValue,
                             language: GameLanguage.english.rawValue,
                             controlMode: ControlMode.wasd.rawValue,
                             bgmVolume: 70,
                             sfxVolume: 80,
                             cameraShake: 2,
                             isFullscreen: true,
                             resolutionWidth: 1280,
                             resolutionHeight: 720,
                             unlockedMission: 1,
                             equipment: starter,
                             inventory: starter,
                             totalKills: 0,
                             totalBosses: 0,
                             bestCombo: 0,
                             bestScore: 0,
                             totalRuns: 0,
                             bossDropPity: 0,
                             achievements: [])
    }

    init(saveVersion: Int,
         credits: Int,
         cores: Int,
         alloy: Int,
         equippedWeapon: Int,
         selectedShip: Int,
         language: Int,
         controlMode: String,
         bgmVolume: Int,
         sfxVolume: Int,
         cameraShake: Int,
         isFullscreen: Bool = true,
         resolutionWidth: Int = 1280,
         resolutionHeight: Int = 720,
         unlockedMission: Int,
         equipment: [EquipmentState],
         inventory: [EquipmentState],
         totalKills: Int,
         totalBosses: Int,
         bestCombo: Int,
         bestScore: Int,
         totalRuns: Int,
         bossDropPity: Int,
         achievements: [String]) {
        self.saveVersion = saveVersion
        self.credits = credits
        self.cores = cores
        self.alloy = alloy
        self.equippedWeapon = equippedWeapon
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
        self.unlockedMission = max(1, unlockedMission)
        self.equipment = equipment
        self.inventory = inventory
        self.totalKills = totalKills
        self.totalBosses = totalBosses
        self.bestCombo = bestCombo
        self.bestScore = bestScore
        self.totalRuns = totalRuns
        self.bossDropPity = bossDropPity
        self.achievements = achievements
    }

    private enum CodingKeys: String, CodingKey {
        case saveVersion, credits, cores, alloy, equippedWeapon, selectedShip, language, controlMode, bgmVolume, sfxVolume, cameraShake, isFullscreen, resolutionWidth, resolutionHeight, unlockedMission, equipment, inventory
        case totalKills, totalBosses, bestCombo, bestScore, totalRuns, bossDropPity, achievements
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        saveVersion = try container.decodeIfPresent(Int.self, forKey: .saveVersion) ?? 1
        credits = try container.decodeIfPresent(Int.self, forKey: .credits) ?? 0
        cores = try container.decodeIfPresent(Int.self, forKey: .cores) ?? 0
        alloy = try container.decodeIfPresent(Int.self, forKey: .alloy) ?? 0
        equippedWeapon = try container.decodeIfPresent(Int.self, forKey: .equippedWeapon) ?? WeaponType.cannon.rawValue
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
        unlockedMission = max(1, try container.decodeIfPresent(Int.self, forKey: .unlockedMission) ?? 1)
        var loadedEquipment = try container.decodeIfPresent([EquipmentState].self, forKey: .equipment) ?? PlayerProfile.starterEquipment
        var loadedInventory = try container.decodeIfPresent([EquipmentState].self, forKey: .inventory) ?? loadedEquipment
        for index in loadedEquipment.indices {
            if loadedEquipment[index].id == "aegis_armor", loadedEquipment[index].slot == 2 { loadedEquipment[index].slot = 3 }
            if loadedEquipment[index].id == "orbit_drone", loadedEquipment[index].slot == 3 { loadedEquipment[index].slot = 4 }
        }
        for index in loadedInventory.indices {
            if loadedInventory[index].id == "aegis_armor", loadedInventory[index].slot == 2 { loadedInventory[index].slot = 3 }
            if loadedInventory[index].id == "orbit_drone", loadedInventory[index].slot == 3 { loadedInventory[index].slot = 4 }
        }
        if !loadedEquipment.contains(where: { $0.slot == 2 }) {
            loadedEquipment.append(PlayerProfile.starterEquipment[2])
        }
        if !loadedInventory.contains(where: { $0.slot == 2 }) {
            loadedInventory.append(PlayerProfile.starterEquipment[2])
        }
        if !loadedEquipment.contains(where: { $0.slot == 4 }) {
            loadedEquipment.append(PlayerProfile.starterEquipment[4])
        }
        if !loadedInventory.contains(where: { $0.slot == 4 }) {
            loadedInventory.append(PlayerProfile.starterEquipment[4])
        }
        equipment = loadedEquipment.sorted(by: { $0.slot < $1.slot })
        inventory = loadedInventory
        totalKills = try container.decodeIfPresent(Int.self, forKey: .totalKills) ?? 0
        totalBosses = try container.decodeIfPresent(Int.self, forKey: .totalBosses) ?? 0
        bestCombo = try container.decodeIfPresent(Int.self, forKey: .bestCombo) ?? 0
        bestScore = try container.decodeIfPresent(Int.self, forKey: .bestScore) ?? 0
        totalRuns = try container.decodeIfPresent(Int.self, forKey: .totalRuns) ?? 0
        bossDropPity = try container.decodeIfPresent(Int.self, forKey: .bossDropPity) ?? 0
        achievements = try container.decodeIfPresent([String].self, forKey: .achievements) ?? []
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
    private let profileKey = "SwiftSurvivor.profile.v3"
    private let legacyProfileKeyV2 = "SwiftSurvivor.profile.v2"
    private let legacyProfileKeyV1 = "SwiftSurvivor.profile.v1"
    private let backupKey = "SwiftSurvivor.profile.v3.backup"
    private let rootDirectory: URL
    private let activeSlotMarkerURL: URL
    private(set) var activeSlot: Int
    private(set) var profile: PlayerProfile

    private init() {
        let root = SaveManager.gameRootDirectory()
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

        let needsMigration = profile.saveVersion < 5 || profile.equipment.count < 5
        if slotProfile == nil || needsMigration {
            save(profile)
        } else {
            persistActiveSlot()
        }
    }

    func save(_ value: PlayerProfile) {
        var normalized = value
        normalized.saveVersion = 5
        profile = normalized
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
        (0..<Self.slotCount).map { slot in
            let root = rootDirectory
            let loaded = SaveManager.loadProfile(at: SaveManager.slotURL(root: root, slot: slot))
                ?? SaveManager.loadProfile(at: SaveManager.backupURL(root: root, slot: slot))
            return SaveSlotSummary(slot: slot, profile: loaded)
        }
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
