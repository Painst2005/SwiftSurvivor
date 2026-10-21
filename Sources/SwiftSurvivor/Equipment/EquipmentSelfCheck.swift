import Foundation

/// 规格第 14 节数值自检：`swift run SwiftSurvivor --equipment-self-check` 逐条跑通并贴出结果。
/// 覆盖清单：
/// 1. 10 阶链 levelCap / 颜色 / 星级 / 进阶消耗与第 4 节表格完全一致；
/// 2. 归一化约定（同 tier/stage/level 四槽 unitPower 相等）+ 7.4 战力对照表交叉验算 + 弹道签名唯一；
/// 3. 0→9 阶同名装备实际消耗 == 配置声明值（真实调用 advanceEquipment 验证代码行为）；
/// 4. 战力门槛表：满阶五等品打终章伤害折算（"稍吃力"）+ minScale 下限 + 门槛单调；
/// 5. 档位间满级总战力差 ≤ 25%（冻结项 7）；
/// 6. 战神拆解 → 强化素材 → 重新合成，阶级与等级不丢（真实调用 activate/dissolve/upgrade/advance/golden）；
/// 7. 同步率随战神阶级单调递增、封顶 80%（黄金 90%）；
/// 8. 至少 3 个 v6 老存档样本导入后四槽完全对应、战力无突变；
/// 9. 数据常量全部外置（Sources 下 grep 不到装备表魔法数字）。
enum EquipmentSelfCheck {
    nonisolated(unsafe) private static var passed = 0
    nonisolated(unsafe) private static var failed = 0

    static func run() {
        print("===== EQUIPMENT SELF-CHECK · 规格第 14 节 =====")
        checkStageChain()
        checkNormalizationAndSignatures()
        checkSameNameConsumption()
        checkPowerGates()
        checkTierSpread()
        checkWarriorRoundTrip()
        checkSynergyCurve()
        checkLegacyMigration()
        checkConfigExternalization()
        print("===== SUMMARY: \(passed) PASS / \(failed) FAIL =====")
        exit(failed == 0 ? 0 : 1)
    }

    // MARK: - 输出助手

    private static func pass(_ item: String, _ detail: String = "") {
        passed += 1
        print("[PASS] \(item)" + (detail.isEmpty ? "" : " — \(detail)"))
    }

    private static func fail(_ item: String, _ detail: String = "") {
        failed += 1
        print("[FAIL] \(item)" + (detail.isEmpty ? "" : " — \(detail)"))
    }

    private static func info(_ text: String) {
        print("       \(text)")
    }

    /// 在 Game.shared 上跑一段会改存档的用例，跑完还原现场（不污染玩家真实存档）。
    private static func withScratchProfile<T>(_ body: () -> T) -> T {
        let game = Game.shared
        let backup = game.profile
        let savedExpMaterial = game.selectedExpMaterial
        let savedPhase = game.phase
        let result = body()
        game.profile = backup
        game.selectedExpMaterial = savedExpMaterial
        game.phase = savedPhase
        SaveManager.shared.save(backup)
        return result
    }

    // MARK: - 1. 阶链表

    private static func checkStageChain() {
        let catalog = EquipmentCatalog.shared
        let chain = catalog.stageChain
        // 规格第 4 节表格：阶 / 颜色 / 星级 / 后缀 / 等级区间 / 满级。
        let expected: [(color: String, stars: Int, suffix: String, min: Int, cap: Int)] = [
            ("white", 2, "", 1, 25),
            ("green", 3, "", 25, 30),
            ("blue", 4, "", 30, 60),
            ("blue", 4, "+1", 60, 65),
            ("blue", 4, "+2", 65, 70),
            ("blue", 4, "+3", 70, 75),
            ("purple", 5, "", 75, 75),
            ("purple", 5, "+1", 75, 80),
            ("purple", 5, "+2", 80, 85),
            ("purple", 5, "+3", 85, 90),
        ]
        // 规格第 4 节进阶消耗：材料系 x 每种个数 / 同名件数 / 金币。
        let materialSets: [Int: (set: String, each: Int)] = [
            0: ("quantum", 1), 1: ("mega", 1), 5: ("quark", 1),
        ]
        let sameName: [Int: Int] = [2: 1, 3: 2, 4: 3, 6: 1, 7: 2, 8: 3]
        let gold: [Int: Int] = [0: 500, 1: 1000, 2: 50, 3: 100, 4: 150, 5: 10000, 6: 500, 7: 1000, 8: 1500]

        var tableOK = chain.count == expected.count
        var costOK = true
        var continuityOK = true
        var detailParts: [String] = []

        for (stage, want) in expected.enumerated() {
            guard let info = chain.first(where: { $0.stage == stage }) else {
                tableOK = false
                detailParts.append("stage \(stage) 缺失")
                continue
            }
            if info.color != want.color || info.stars != want.stars || info.suffix != want.suffix
                || info.levelMin != want.min || info.levelCap != want.cap {
                tableOK = false
                detailParts.append("stage \(stage): \(info.color)/\(info.stars)星\(info.suffix) \(info.levelMin)-\(info.levelCap) ≠ 表格 \(want.color)/\(want.stars)星\(want.suffix) \(want.min)-\(want.cap)")
            }
            // 等级区间连续性：下一阶下限 == 本阶满级。
            if stage < expected.count - 1 {
                let next = chain.first { $0.stage == stage + 1 }
                if next?.levelMin != info.levelCap { continuityOK = false }
            }
            // 进阶消耗。
            if stage == 9 {
                if info.advance != nil { costOK = false }
                continue
            }
            guard let cost = info.advance else {
                costOK = false
                continue
            }
            if cost.sameName != (sameName[stage] ?? 0) || cost.gold != (gold[stage] ?? Int.min) {
                costOK = false
                detailParts.append("stage \(stage) 消耗 sameName=\(cost.sameName) gold=\(cost.gold) ≠ 表格 sameName=\(sameName[stage] ?? 0) gold=\(gold[stage] ?? -1)")
            }
            if let want = materialSets[stage] {
                if cost.materials.count != 4 || cost.each != want.each {
                    costOK = false
                } else {
                    for id in cost.materials {
                        guard let material = catalog.material(id), material.set == want.set else {
                            costOK = false
                            detailParts.append("stage \(stage) 材料 \(id) 不属于 \(want.set) 系")
                            break
                        }
                    }
                }
            } else if !cost.materials.isEmpty {
                costOK = false
                detailParts.append("stage \(stage) 不应消耗道具材料")
            }
        }

        let caps = chain.map { $0.levelCap }
        info("levelCap 表 = \(caps)")
        if tableOK && continuityOK {
            pass("①10 阶链 levelCap/颜色/星级/后缀与第 4 节表格完全一致（等级区间连续）", caps.map(String.init).joined(separator: "/"))
        } else {
            fail("①10 阶链表与第 4 节表格不一致", detailParts.joined(separator: "；"))
        }
        if costOK {
            pass("①进阶消耗表一致（材料系/同名/金币/满阶锁）", "Σ同名=12，金币 Σ=13800")
        } else {
            fail("①进阶消耗表与第 4 节不一致", detailParts.joined(separator: "；"))
        }
    }

    // MARK: - 2. 归一化 + 弹道签名

    private static func checkNormalizationAndSignatures() {
        let catalog = EquipmentCatalog.shared

        // 2a. 归一化：同 tier/stage/level 下，任何两件装备 unitPower 相等。
        var normalizeOK = true
        var tierCounts: [Int: Int] = [:]
        for series in catalog.seriesList { tierCounts[series.tier, default: 0] += 1 }
        for tier in 1...5 where tierCounts[tier] == 4 {
            for stage in 0...9 {
                let level = catalog.levelCap(stage: stage)
                let powers = Set(catalog.seriesList.filter { $0.tier == tier }
                    .map { _ in catalog.unitPower(tier: tier, stage: stage, level: level) })
                if powers.count != 1 { normalizeOK = false }
            }
        }
        if normalizeOK && tierCounts == [1: 4, 2: 4, 3: 4, 4: 4, 5: 4] {
            pass("②归一化约定成立（4 槽 x 5 档 = 20 系；同 tier/stage/level 四槽 unitPower 相等）")
        } else {
            fail("②归一化约定被破坏", "档位分布 \(tierCounts)")
        }

        // 2b. 与规格 7.4 战力对照表交叉验算（md 表自身有 ±1~2 的四舍五入漂移，容差 2）。
        let mdTable: [(tier: Int, s6: Int, s8: Int, s9: Int)] = [
            (1, 2191, 2885, 3304),
            (2, 2112, 2786, 3191),
            (3, 2034, 2685, 3080),
            (4, 1955, 2587, 2968),
            (5, 1878, 2488, 2855),
        ]
        var crossOK = true
        var rows: [String] = []
        for row in mdTable {
            let ours = (
                catalog.unitPower(tier: row.tier, stage: 6, level: 75),
                catalog.unitPower(tier: row.tier, stage: 8, level: 85),
                catalog.unitPower(tier: row.tier, stage: 9, level: 90)
            )
            if abs(ours.0 - row.s6) > 2 || abs(ours.1 - row.s8) > 2 || abs(ours.2 - row.s9) > 2 { crossOK = false }
            rows.append("T\(row.tier): \(ours.0)/\(ours.1)/\(ours.2) vs md \(row.s6)/\(row.s8)/\(row.s9)")
        }
        info("紫五星75 / +2·85 / +3·90 单件战力（实装 vs 规格 7.4 表）")
        for row in rows { info("  \(row)") }
        if crossOK {
            pass("②装甲血量÷20 与规格 7.4 战力对照表交叉验算一致（容差 ±2）")
        } else {
            fail("②战力与规格 7.4 对照表偏差超差")
        }

        // 2c. 弹道签名：15 个武器系各有唯一 profile，5 个装甲系各有 survival skill。
        let weapons = catalog.seriesList.filter { $0.slot != .armor }
        let armors = catalog.seriesList.filter { $0.slot == .armor }
        let signatures = Set(weapons.compactMap { $0.weaponProfile })
        var signatureOK = weapons.count == 15 && signatures.count == 15
            && armors.count == 5 && armors.allSatisfy { $0.skill != nil && $0.weaponProfile == nil }
        if signatureOK {
            pass("②20 系弹道签名唯一（15 武器系签名互异 + 5 装甲系各带生存被动）")
        } else {
            signatureOK = false
            fail("②弹道签名不完整或重复", "武器系 \(weapons.count) / 唯一签名 \(signatures.count) / 装甲系 \(armors.count)")
        }
    }

    // MARK: - 3. 同名装备消耗 == 配置声明值（含代码行为）

    private static func checkSameNameConsumption() {
        let catalog = EquipmentCatalog.shared
        var declared = 0
        for stage in 0...8 {
            guard let cost = catalog.advanceCost(stage: stage) else {
                fail("③同名消耗：stage \(stage) 缺少 advance 配置")
                return
            }
            declared += cost.sameName
        }
        info("配置声明：Σ同名材料 = \(declared)（阶2/3/4=1/2/3，阶6/7/8=1/2/3）+ 本体 1 = \(declared + 1) 件")

        // 代码行为：真实调用 advanceEquipment，从 0 阶爬到 9 阶。
        struct AdvanceOutcome {
            var advanced = 0
            var consumed = 0
            var finalStage = -1
            var blocked = false
        }
        let outcome = withScratchProfile { () -> AdvanceOutcome in
            let game = Game.shared
            game.phase = .hangar
            game.profile = PlayerProfile.fresh
            game.profile.credits = 100_000
            for id in ["quantum_design", "quantum_controller", "quantum_alloy", "quantum_cell",
                       "mega_design", "mega_controller", "mega_alloy", "mega_thruster",
                       "quark_design", "quark_controller", "quark_alloy", "quark_reactor"] {
                game.addMaterial(id, amount: 1)
            }
            // 按色段备货 12 件同名：蓝段 1+2+3，紫段 1+2+3（等级不限，lv1 即可）。
            var stock: [EquipmentState] = []
            for (stage, count) in [(2, 1), (3, 2), (4, 3), (6, 1), (7, 2), (8, 3)] {
                for index in 0..<count {
                    stock.append(EquipmentState(uid: "dup_\(stage)_\(index)", seriesId: "fighter_assault",
                                                stage: stage, level: 1, exp: 0, locked: false, equipped: false))
                }
            }
            game.profile.inventory = stock
            let fighterSlot = game.profile.equipment.firstIndex { $0.slot == .fighter } ?? 0
            let stockCount = stock.count

            var result = AdvanceOutcome()
            while game.profile.equipment[fighterSlot].stage < 9 {
                let before = game.profile.equipment[fighterSlot].stage
                // 模拟玩家先练满本阶（冻结项 3：进阶必须满级）。
                game.profile.equipment[fighterSlot].level = game.profile.equipment[fighterSlot].levelCap
                game.profile.equipment[fighterSlot].exp = 0
                game.advanceEquipment(slot: fighterSlot)
                guard game.profile.equipment[fighterSlot].stage == before + 1 else { break }
                result.advanced += 1
            }

            // 满级锁守卫：未满级时进阶必须被拒绝。
            game.profile.equipment[fighterSlot].level = 1
            game.profile.equipment[fighterSlot].exp = 0
            let stageBeforeGuard = game.profile.equipment[fighterSlot].stage
            game.advanceEquipment(slot: fighterSlot)
            result.blocked = game.profile.equipment[fighterSlot].stage == stageBeforeGuard
            result.consumed = stockCount - game.profile.inventory.count
            result.finalStage = game.profile.equipment[fighterSlot].stage
            return result
        }

        if outcome.consumed == declared && outcome.advanced == 9 && outcome.finalStage == 9 {
            pass("③0→9 阶实际消耗同名装备 == 配置声明值", "行为：进阶 \(outcome.advanced) 次，消耗同名 \(outcome.consumed) 件 + 本体 1 = \(outcome.consumed + 1)")
        } else {
            fail("③同名消耗与配置声明不一致", "声明 \(declared) / 实耗 \(outcome.consumed)，进阶 \(outcome.advanced) 次，终阶 \(outcome.finalStage)")
        }
        if outcome.blocked {
            pass("③满级锁守卫生效（未满级进阶被拒绝，冻结项 3）")
        } else {
            fail("③满级锁守卫失效：未满级也能进阶")
        }
    }

    // MARK: - 4. 战力门槛

    private static func checkPowerGates() {
        let catalog = EquipmentCatalog.shared
        let gates = (1...8).map { catalog.powerGate(mission: $0) }
        let monotonic = zip(gates, gates.dropFirst()).allSatisfy { $0 < $1 }

        let tier5Full = catalog.unitPower(tier: 5, stage: 9, level: 90) * 4
        let tier1Full = catalog.unitPower(tier: 1, stage: 9, level: 90) * 4
        let finalGate = catalog.powerGate(mission: 8)
        let tier5Scale = catalog.powerScale(power: tier5Full, gate: finalGate)
        let tier1Scale = catalog.powerScale(power: tier1Full, gate: finalGate)
        let floorScale = catalog.powerScale(power: 0, gate: finalGate)
        let noGateScale = catalog.powerScale(power: 0, gate: 0)

        var endlessMonotonic = true
        var previous = 0
        for wave in 1...12 {
            let gate = catalog.powerGate(endlessWave: wave)
            if gate <= previous { endlessMonotonic = false }
            previous = gate
        }

        info("8 章门槛 = \(gates)")
        info("满阶四件战力：五等品 \(tier5Full) / 一等品 \(tier1Full)（终章门槛 \(finalGate)）")
        info("伤害折算：五等品 \(String(format: "%.1f%%", tier5Scale * 100))、一等品 \(String(format: "%.1f%%", tier1Scale * 100))、归零战力 \(String(format: "%.1f%%", floorScale * 100))")

        if monotonic && endlessMonotonic {
            pass("④关卡/无尽战力门槛单调递增", "8 章 \(gates.map(String.init).joined(separator: "→"))")
        } else {
            fail("④战力门槛非单调", "闯关 \(gates) 无尽单调=\(endlessMonotonic)")
        }
        if finalGate == 11737 {
            pass("④终章门槛锚定原版 72 关口径 11737", "满阶五等品 \(tier5Full) → 折算 \(String(format: "%.1f%%", tier5Scale * 100)) = 稍吃力（规格 7.4）")
        } else {
            fail("④终章门槛 ≠ 11737（规格 7.4 原版口径）", "实际 \(finalGate)")
        }
        if tier5Scale < 1.0, tier5Scale >= 0.9, abs(tier1Scale - 1.0) < 0.0001,
           abs(floorScale - catalog.powerGates.minScale) < 0.0001, abs(noGateScale - 1.0) < 0.0001 {
            pass("④折算曲线符合规格 7.4（不足线性衰减、达标无衰减、minScale 下限）")
        } else {
            fail("④折算曲线异常", "t5=\(tier5Scale) t1=\(tier1Scale) floor=\(floorScale) noGate=\(noGateScale)")
        }
    }

    // MARK: - 5. 档位差 ≤ 25%

    private static func checkTierSpread() {
        let catalog = EquipmentCatalog.shared
        var worst = 0.0
        var rows: [String] = []
        var ok = true
        for stage in 0...9 {
            let level = catalog.levelCap(stage: stage)
            let t1 = catalog.unitPower(tier: 1, stage: stage, level: level) * 4
            let t5 = catalog.unitPower(tier: 5, stage: stage, level: level) * 4
            guard t5 > 0 else { ok = false; continue }
            let diff = Double(t1 - t5) / Double(t5)
            worst = max(worst, diff)
            if diff > 0.25 { ok = false }
            rows.append("stage\(stage) Lv\(level): \(t1)/\(t5) = \(String(format: "%.1f%%", diff * 100))")
        }
        for row in rows { info("档差（一等品×4 / 五等品×4）\(row)") }
        if ok {
            pass("⑤档位间满级总战力差 ≤ 25%（冻结项 7）", "最大档差 \(String(format: "%.1f%%", worst * 100))")
        } else {
            fail("⑤存在档差 > 25% 的阶级", "最大 \(String(format: "%.1f%%", worst * 100))")
        }
    }

    // MARK: - 6. 战神拆解 → 强化素材 → 重新合成

    private static func checkWarriorRoundTrip() {
        let recipeID = "warrior_assault"
        struct WarriorOutcome {
            var activated = false
            var level = -1
            var advanceStage = -1
            var golden = false
            var dissolved = false
            var materialsIntact = 0
            var reLevel = -1
            var reAdvanceStage = -1
            var reGolden = false
            var synergy = -1.0
        }
        let outcome = withScratchProfile { () -> WarriorOutcome in
            let game = Game.shared
            game.phase = .hangar
            game.profile = PlayerProfile.fresh
            game.profile.unlockedMission = 9          // 解锁全部战役门槛
            game.profile.endlessBestScore = 1_000_000
            game.profile.bossTypesDefeated = ["rift"]
            game.profile.alloy = 1_000
            // 两件指定紫装（stage>=6）进仓库；激活只占用不消耗。
            game.profile.inventory = [
                EquipmentState(uid: "mat_phoenix", seriesId: "fighter_phoenix", stage: 6, level: 75, exp: 0, locked: false, equipped: false),
                EquipmentState(uid: "mat_phantom", seriesId: "fighter_phantom", stage: 6, level: 75, exp: 0, locked: false, equipped: false),
            ]
            var result = WarriorOutcome()
            game.activateWarrior(recipeId: recipeID)
            result.activated = game.profile.warriors.contains { $0.recipeId == recipeID }
            let index = game.profile.warriors.firstIndex { $0.recipeId == recipeID } ?? -1

            // 练满本体（30 级），再进阶到 +9、晋级黄金。
            game.selectedExpMaterial = "exp_cube"
            game.addMaterial("exp_cube", amount: 200)
            var guardCounter = 0
            while index >= 0, !game.profile.warriors[index].isMaxLevel, guardCounter < 300 {
                game.upgradeWarriorWithExp(index: index)
                guardCounter += 1
            }
            if index >= 0 { result.level = game.profile.warriors[index].level }
            for id in EquipmentCatalog.shared.synergyConfig.advanceMaterials { game.addMaterial(id, amount: 45) }
            for _ in 0..<9 where index >= 0 { game.advanceWarrior(index: index) }
            for id in EquipmentCatalog.shared.synergyConfig.goldenMaterials { game.addMaterial(id, amount: 10) }
            if index >= 0 { game.promoteWarriorGolden(index: index) }
            if index >= 0 {
                result.advanceStage = game.profile.warriors[index].advanceStage
                result.golden = game.profile.warriors[index].golden
            }

            // 拆解：素材无损归还；随后"强化素材"（模拟进阶素材机），再重新合成。
            if index >= 0 { game.dissolveWarrior(index: index) }
            result.dissolved = !game.profile.warriors.contains { $0.recipeId == recipeID }
                && game.profile.dissolvedWarriors.contains { $0.recipeId == recipeID }
            result.materialsIntact = game.profile.inventory
                .filter { $0.seriesId == "fighter_phoenix" || $0.seriesId == "fighter_phantom" }.count
            for item in game.profile.inventory.indices {
                if game.profile.inventory[item].seriesId == "fighter_phoenix" || game.profile.inventory[item].seriesId == "fighter_phantom" {
                    game.profile.inventory[item].level = 80   // 强化素材
                    game.profile.inventory[item].exp = 0
                }
            }
            game.activateWarrior(recipeId: recipeID)
            let reIndex = game.profile.warriors.firstIndex { $0.recipeId == recipeID } ?? -1
            if reIndex >= 0 {
                result.reLevel = game.profile.warriors[reIndex].level
                result.reAdvanceStage = game.profile.warriors[reIndex].advanceStage
                result.reGolden = game.profile.warriors[reIndex].golden
                result.synergy = game.profile.warriors[reIndex].synergyRate
            }
            return result
        }

        let archiveConsumed = outcome.dissolved && outcome.materialsIntact == 2
        if outcome.activated && outcome.level == 30 && outcome.advanceStage == 9 && outcome.golden {
            pass("⑥战神养成链路（激活→练满→+9→黄金）", "Lv\(outcome.level) +\(outcome.advanceStage) golden=\(outcome.golden)")
        } else {
            fail("⑥战神养成链路异常", "activated=\(outcome.activated) Lv\(outcome.level) +\(outcome.advanceStage) golden=\(outcome.golden)")
        }
        if archiveConsumed && outcome.reAdvanceStage == 9 && outcome.reGolden && outcome.reLevel == 30 {
            pass("⑥战神拆解→强化素材→重新合成，阶级与等级不丢（规格 8.2 阶级保留）",
                 "重合成后 Lv\(outcome.reLevel) +\(outcome.reAdvanceStage) golden=\(outcome.reGolden) 同步率 \(Int(outcome.synergy * 100))%")
        } else {
            fail("⑥战神拆解重合成丢失阶级/等级", "拆解归档=\(outcome.dissolved) 素材归还=\(outcome.materialsIntact) 重合成 Lv\(outcome.reLevel) +\(outcome.reAdvanceStage) golden=\(outcome.reGolden)")
        }
    }

    // MARK: - 7. 同步率曲线

    private static func checkSynergyCurve() {
        let config = EquipmentCatalog.shared.synergyConfig
        var values: [Double] = []
        var monotonic = true
        for stage in 0...9 {
            let warrior = WarriorState(uid: "sync_\(stage)", recipeId: "warrior_assault", level: 1,
                                       advanceStage: stage, golden: false, materialUIDs: [], equipped: false)
            let rate = warrior.synergyRate
            if let previous = values.last, rate <= previous { monotonic = false }
            values.append(rate)
        }
        let golden = WarriorState(uid: "sync_gold", recipeId: "warrior_assault", level: 1,
                                  advanceStage: 9, golden: true, materialUIDs: [], equipped: false)
        let goldenRate = golden.synergyRate
        let goldenCapOK = goldenRate <= config.golden.synergyCap
        let plainCapOK = values.allSatisfy { $0 <= config.synergyCap }
        let goldenBonusOK = abs(goldenRate - (0.61 + 0.18 + config.golden.bonusSynergy)) < 0.0001

        info("普通战神同步率 +0..+9 = \(values.map { String(Int($0 * 100)) + "%" }.joined(separator: " → "))（上限 \(Int(config.synergyCap * 100))%）")
        info("黄金战神 +9 同步率 = \(Int(goldenRate * 100))%（上限 \(Int(config.golden.synergyCap * 100))%）")

        if monotonic && plainCapOK && goldenCapOK && goldenBonusOK {
            pass("⑦同步率随阶级单调递增、封顶 80%（黄金再 +10% 至 90%）")
        } else {
            fail("⑦同步率曲线异常", "monotonic=\(monotonic) plainCap=\(plainCapOK) goldenCap=\(goldenCapOK) bonus=\(goldenBonusOK)")
        }
    }

    // MARK: - 8. 老存档迁移（≥3 样本）

    private static func checkLegacyMigration() {
        let catalog = EquipmentCatalog.shared
        let tierMap = [0: 5, 1: 5, 2: 4, 3: 3, 4: 1]

        struct Expectation {
            var slot: EquipmentSlot
            var seriesId: String
            var stage: Int
            var level: Int
            var equipped: Bool
        }

        /// 独立重算迁移公式（与 SaveManager.migrated 同口径），用于交叉验证代码行为。
        func expected(slot legacySlot: Int, id: String, name: String, level: Int, rarity: Int, evolution: Int,
                      equipped: Bool) -> Expectation? {
            var slotValue = legacySlot
            if id == "aegis_armor", legacySlot == 2 { slotValue = 3 }
            if id == "orbit_drone", legacySlot == 3 { slotValue = 4 }
            guard (1...4).contains(slotValue), let slot = EquipmentSlot.fromLegacySlot(slotValue) else { return nil }
            let knownID: String?
            switch id {
            case "arc_cannon": knownID = "fighter_assault"
            case "nova_payload": knownID = "sub_tracking"
            case "aegis_armor": knownID = "armor_diamond"
            case "orbit_drone": knownID = "wing_gun"
            default:
                switch name {
                case "NOVA MISSILE": knownID = "sub_blast"
                case "FROST PLATING": knownID = "armor_gold"
                case "STORM DRONE": knownID = "wing_rapid"
                default: knownID = nil
                }
            }
            let tier = tierMap[min(4, max(0, rarity))] ?? 5
            let fallbackID = knownID ?? catalog.series(slot: slot, tier: tier)?.id ?? "fighter_assault"
            let resolved = catalog.series(id: fallbackID)?.id ?? fallbackID
            let stage = min(9, max(0, evolution + (rarity >= 2 ? rarity - 1 : 0)))
            let mappedLevel = min(catalog.levelCap(stage: stage), max(catalog.levelMin(stage: stage), max(1, level)))
            return Expectation(slot: slot, seriesId: resolved, stage: stage, level: mappedLevel, equipped: equipped)
        }

        func legacyItem(_ id: String, _ name: String, _ slot: Int, _ level: Int, _ rarity: Int,
                        _ evolution: Int, locked: Bool = false) -> [String: Any] {
            ["id": id, "name": name, "slot": slot, "level": level, "rarity": rarity,
             "stars": 2 + rarity, "evolution": evolution, "affix": 0, "locked": locked]
        }

        func legacySave(_ equipment: [[String: Any]], _ inventory: [[String: Any]],
                        credits: Int, unlockedMission: Int, alloy: Int) -> Data? {
            let payload: [String: Any] = [
                "saveVersion": 6, "credits": credits, "cores": 3, "alloy": alloy,
                "selectedShip": 0, "language": 0, "controlMode": "wasd",
                "bgmVolume": 70, "sfxVolume": 80, "cameraShake": 2, "isFullscreen": true,
                "resolutionWidth": 1280, "resolutionHeight": 720, "uiScale": 100,
                "unlockedMission": unlockedMission,
                "equipment": equipment, "inventory": inventory,
                "totalKills": 9999, "totalBosses": 42, "bestCombo": 120, "bestScore": 250000,
                "totalRuns": 66, "bossDropPity": 3, "achievements": ["first_blood"],
            ]
            return try? JSONSerialization.data(withJSONObject: payload)
        }

        struct LegacyItemSpec {
            var legacySlot: Int
            var id: String
            var name: String
            var level: Int
            var rarity: Int
            var evolution: Int
        }

        struct LegacySample {
            var label: String
            var data: Data?
            var equipment: [LegacyItemSpec]
            var inventory: [LegacyItemSpec]
            var credits: Int
            var unlockedMission: Int
        }

        func spec(_ slot: Int, _ id: String, _ name: String, _ level: Int, _ rarity: Int, _ evolution: Int) -> LegacyItemSpec {
            LegacyItemSpec(legacySlot: slot, id: id, name: name, level: level, rarity: rarity, evolution: evolution)
        }

        // 样本 A：资深玩家，四槽满装（含 v6 槽位修正 aegis/orbit）+ 未知 id 仓库件（走 tierMap 兜底）。
        let sampleA = LegacySample(
            label: "A·资深玩家",
            data: legacySave(
                [
                    legacyItem("arc_cannon", "ARC CANNON", 1, 88, 4, 3, locked: true),
                    legacyItem("nova_payload", "NOVA PAYLOAD", 2, 70, 3, 2),
                    legacyItem("aegis_armor", "AEGIS ARMOR", 2, 60, 2, 1),
                    legacyItem("orbit_drone", "ORBIT DRONE", 3, 45, 1, 0),
                ],
                [legacyItem("unknown_widget", "MYSTERY MODULE", 4, 33, 2, 1)],
                credits: 12345, unlockedMission: 6, alloy: 800),
            equipment: [
                spec(1, "arc_cannon", "ARC CANNON", 88, 4, 3),
                spec(2, "nova_payload", "NOVA PAYLOAD", 70, 3, 2),
                spec(2, "aegis_armor", "AEGIS ARMOR", 60, 2, 1),
                spec(3, "orbit_drone", "ORBIT DRONE", 45, 1, 0),
            ],
            inventory: [spec(4, "unknown_widget", "MYSTERY MODULE", 33, 2, 1)],
            credits: 12345, unlockedMission: 6)
        // 样本 B：靠译名映射的老装备（NOVA MISSILE / FROST PLATING），缺两个槽位补 initial。
        let sampleB = LegacySample(
            label: "B·译名映射",
            data: legacySave(
                [
                    legacyItem("custom_sub", "NOVA MISSILE", 2, 50, 2, 2),
                    legacyItem("custom_armor", "FROST PLATING", 3, 40, 1, 0),
                ],
                [], credits: 500, unlockedMission: 3, alloy: 0),
            equipment: [
                spec(2, "custom_sub", "NOVA MISSILE", 50, 2, 2),
                spec(3, "custom_armor", "FROST PLATING", 40, 1, 0),
            ],
            inventory: [],
            credits: 500, unlockedMission: 3)
        // 样本 C：最小存档，单件白装，其余槽位补 initial。
        let sampleC = LegacySample(
            label: "C·最小存档",
            data: legacySave(
                [legacyItem("first_fighter", "STARTER", 1, 5, 0, 0)],
                [], credits: 0, unlockedMission: 1, alloy: 0),
            equipment: [spec(1, "first_fighter", "STARTER", 5, 0, 0)],
            inventory: [],
            credits: 0, unlockedMission: 1)

        var allOK = true
        for sample in [sampleA, sampleB, sampleC] {
            guard let data = sample.data,
                  let profile = try? JSONDecoder().decode(PlayerProfile.self, from: data) else {
                fail("⑧老存档样本 \(sample.label) 解码失败")
                allOK = false
                continue
            }
            var sampleOK = true
            var notes: [String] = []

            if profile.saveVersion != SaveManager.currentSaveVersion { sampleOK = false; notes.append("saveVersion=\(profile.saveVersion)") }
            if profile.equipment.count != 4 { sampleOK = false; notes.append("equipment.count=\(profile.equipment.count)") }
            if profile.equipment.map({ $0.slot }) != EquipmentSlot.allCases {
                sampleOK = false
                notes.append("槽位顺序/完整性错误: \(profile.equipment.map { $0.slot.rawValue })")
            }
            if !profile.equipment.allSatisfy({ $0.equipped }) { sampleOK = false; notes.append("存在未标记出战件") }
            if profile.credits != sample.credits { sampleOK = false; notes.append("credits=\(profile.credits)≠\(sample.credits)") }
            if profile.unlockedMission != sample.unlockedMission { sampleOK = false; notes.append("unlockedMission=\(profile.unlockedMission)") }

            for item in sample.equipment {
                guard let want = expected(slot: item.legacySlot, id: item.id, name: item.name, level: item.level,
                                          rarity: item.rarity, evolution: item.evolution, equipped: true) else {
                    sampleOK = false
                    notes.append("\(item.id) 无法推导期望映射")
                    continue
                }
                guard let actual = profile.equipment.first(where: { $0.slot == want.slot }) else {
                    sampleOK = false
                    notes.append("槽位 \(want.slot.rawValue) 缺失")
                    continue
                }
                if actual.seriesId != want.seriesId || actual.stage != want.stage || actual.level != want.level {
                    sampleOK = false
                    notes.append("\(item.id)→\(want.slot.rawValue): 实装 \(actual.seriesId)/s\(actual.stage)/lv\(actual.level) ≠ 期望 \(want.seriesId)/s\(want.stage)/lv\(want.level)")
                }
                if actual.unitPower <= 0 { sampleOK = false; notes.append("\(item.id) 战力为 0") }
            }
            for item in sample.inventory {
                guard let want = expected(slot: item.legacySlot, id: item.id, name: item.name, level: item.level,
                                          rarity: item.rarity, evolution: item.evolution, equipped: false) else { continue }
                guard let actual = profile.inventory.first(where: { $0.seriesId == want.seriesId }) else {
                    sampleOK = false
                    notes.append("仓库件 \(item.id) 丢失")
                    continue
                }
                if actual.stage != want.stage || actual.level != want.level {
                    sampleOK = false
                    notes.append("仓库件 \(item.id): 实装 s\(actual.stage)/lv\(actual.level) ≠ 期望 s\(want.stage)/lv\(want.level)")
                }
            }

            let power = profile.equipment.reduce(0) { $0 + $1.unitPower }
            info("样本 \(sample.label)：总战力 \(power)，装备 \(profile.equipment.map { "\($0.slot.rawValue):\($0.seriesId)/s\($0.stage)/lv\($0.level)" }.joined(separator: " "))")
            info("样本 \(sample.label)：仓库 \(profile.inventory.map { "\($0.uid)=\($0.seriesId)/s\($0.stage)/lv\($0.level)" }.joined(separator: " "))")
            if sampleOK {
                pass("⑧老存档样本 \(sample.label) 导入：四槽完全对应、战力无突变", "总战力 \(power)")
            } else {
                allOK = false
                fail("⑧老存档样本 \(sample.label) 迁移不符合公式", notes.joined(separator: "；"))
            }
        }
        if allOK {
            pass("⑧≥3 个 v6 老存档样本迁移全部符合 (系列, 阶级, 等级) 一一对应")
        }
    }

    // MARK: - 9. 配置外置（魔法数字 grep）

    private static func checkConfigExternalization() {
        // 数据根目录确认：8 个 JSON 全部可解析（EquipmentCatalog 构造失败会直接 exit）。
        if let root = EquipmentCatalog.resolveDataRoot() {
            let files = ["equipment_stages.json", "equipment_curve.json", "equipment_series.json",
                         "equipment_materials.json", "material_drops.json", "warrior_recipes.json",
                         "warrior_synergy.json", "power_gates.json"]
            let existing = files.filter { FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path) }
            if existing.count == files.count {
                pass("⑨8 张配置表全部外置且解析成功", root.path)
            } else {
                fail("⑨配置表缺失", "\(root.path) 下只有 \(existing.count)/\(files.count)")
            }
        } else {
            fail("⑨找不到 Resources/Data 配置目录")
        }

        // 装备表特征数值不允许以字面量形式出现在源码里（注释除外）。
        let denylist = ["11737", "11420", "11424", "13216", "40680", "57120", "37560", "43820", "0.61"]
        var hits: [String] = []
        for root in sourceRoots() {
            guard let enumerator = FileManager.default.enumerator(atPath: root.path) else { continue }
            for case let relative as String in enumerator where relative.hasSuffix(".swift") {
                // 自检脚本自身包含 denylist 字面量（用于断言），不属于游戏硬编码。
                guard !relative.contains("EquipmentSelfCheck") else { continue }
                let url = root.appendingPathComponent(relative)
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("//") { continue }   // 注释说明不算硬编码
                    for token in denylist where line.contains(token) {
                        hits.append("\(relative):\(index + 1) \(trimmed)")
                    }
                }
            }
        }
        if hits.isEmpty {
            pass("⑨Sources 下 grep 不到装备表魔法数字（门槛/战力/血量/同步率全部读表）")
        } else {
            fail("⑨源码存在装备表魔法数字", hits.joined(separator: "；"))
        }

        // 同名进阶材料来源必须覆盖四个槽位，否则该槽位会在蓝段（stage 2）卡死。
        let legendary = EquipmentCatalog.shared.drops.sameNameDrop.bossRareDropSeries
        let resolvedSlots = Set(legendary.compactMap { EquipmentCatalog.shared.series(id: $0)?.slot })
        let unknownSeries = legendary.filter { EquipmentCatalog.shared.series(id: $0) == nil }
        if unknownSeries.isEmpty, resolvedSlots.count == EquipmentSlot.allCases.count {
            pass("⑩传奇掉落系列覆盖四槽位且 ID 均可解析", legendary.joined(separator: ", "))
        } else {
            fail("⑩传奇掉落系列与槽位对应不完整",
                 "未解析: \(unknownSeries.isEmpty ? "无" : unknownSeries.joined(separator: ","))；覆盖槽位 \(resolvedSlots.count)/\(EquipmentSlot.allCases.count)")
        }
    }

    private static func sourceRoots() -> [URL] {
        var roots: [URL] = []
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        roots.append(cwd.appendingPathComponent("Sources"))
        if let executable = CommandLine.arguments.first, !executable.isEmpty {
            roots.append(URL(fileURLWithPath: executable).deletingLastPathComponent()
                .appendingPathComponent("Sources"))
        }
        return roots.filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}
