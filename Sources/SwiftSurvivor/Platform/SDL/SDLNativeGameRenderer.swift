import Foundation

/// Native SDL presentation for the full game.  Gameplay remains independent
/// of SDL; this layer translates the model into lightweight primitives.
enum SDLNativeGameRenderer {
    static func draw(_ renderer: GameRenderer, game: Game, width: Int, height: Int) {
        UIInteraction.pointer = game.mousePosition
        renderer.beginFrame(clear: RenderColor(5, 9, 24))
        drawSpace(renderer, game: game, width: width, height: height)
        switch game.phase {
        case .playing, .paused, .upgrade, .gameOver:
            drawBattle(renderer, game: game, width: width, height: height)
            if game.phase == .paused { drawPause(renderer, game: game, width: width, height: height) }
            if game.phase == .upgrade { drawUpgrade(renderer, game: game, width: width, height: height) }
            if game.phase == .gameOver { drawGameOver(renderer, game: game, width: width, height: height) }
        case .menu: drawMenu(renderer, game: game, width: width, height: height)
        case .saveSlots: drawSaveSlots(renderer, game: game, width: width, height: height)
        case .missionSelect: drawMissionSelect(renderer, game: game, width: width, height: height)
        case .controls: drawControls(renderer, game: game, width: width, height: height)
        case .hangar: drawHangar(renderer, game: game, width: width, height: height)
        case .settings: drawSettings(renderer, game: game, width: width, height: height)
        case .archive: drawArchive(renderer, game: game, width: width, height: height)
        }
        renderer.present()
    }

    private static func drawSpace(_ r: GameRenderer, game: Game, width: Int, height: Int) {
        r.fillRect(RenderRect(x: 0, y: 0, width: Float(width), height: Float(height)), color: UITheme.Color.background)
        for star in game.stars {
            r.fillCircle(center: (Float(star.position.x), Float(star.position.y)), radius: Float(max(1, star.radius)), color: color(star.tint))
        }
        let field = playfieldBounds(width: Double(width), height: Double(height))
        r.fillRect(RenderRect(x: 0, y: Float(field.top), width: Float(width), height: Float(field.bottom - field.top)), color: UITheme.Color.backgroundRaised)
        for lane in stride(from: 0, through: width, by: 96) {
            r.fillRect(RenderRect(x: Float(lane), y: Float(field.top), width: 1, height: Float(field.bottom - field.top)), color: RenderColor(18, 38, 70, 100))
        }
        r.fillRect(RenderRect(x: 0, y: 0, width: Float(width), height: 54), color: UITheme.Color.panel)
    }

    private static func drawBattle(_ r: GameRenderer, game: Game, width: Int, height: Int) {
        let field = playfieldBounds(width: Double(width), height: Double(height))
        let camera = game.combatFeedback.cameraOffset
        drawCombatHUD(r, game: game, field: field, width: width)

        for enemy in game.enemies {
            let p = enemy.position + enemy.visualOffset + camera
            let c = highlighted(color(enemy.tint), amount: enemy.hitFlash > 0 ? 0.82 : 0)
            r.fillCircle(center: (Float(p.x), Float(p.y)), radius: Float(max(6, enemy.radius)), color: c)
            r.fillRect(RenderRect(x: Float(p.x - enemy.radius), y: Float(p.y - enemy.radius - 8), width: Float(enemy.radius * 2), height: 3), color: RenderColor(55, 24, 47))
            r.fillRect(RenderRect(x: Float(p.x - enemy.radius), y: Float(p.y - enemy.radius - 8), width: Float(max(0, enemy.radius * 2 * enemy.health / max(1, enemy.maxHealth))), height: 3), color: RenderColor(255, 134, 126))
            if enemy.attackWarningActive {
                r.line(from: (Float(enemy.warningTargetX), Float(field.top)), to: (Float(enemy.warningTargetX), Float(field.bottom)), color: RenderColor(255, 79, 125, 160))
            }
        }
        if let boss = game.boss {
            let p = boss.position + boss.visualOffset + camera
            r.fillCircle(center: (Float(p.x), Float(p.y)), radius: 54, color: highlighted(RenderColor(119, 44, 159), amount: boss.hitFlash > 0 ? 0.75 : 0))
            r.fillCircle(center: (Float(p.x), Float(p.y)), radius: 35, color: highlighted(RenderColor(237, 102, 221), amount: boss.hitFlash > 0 ? 0.92 : 0))
            if boss.laserWarningTimer > 0 || boss.laserActiveTimer > 0 {
                let active = boss.laserActiveTimer > 0
                r.fillRect(RenderRect(x: Float(boss.laserX + camera.x - (active ? 12 : 3)), y: Float(field.top + camera.y), width: Float(active ? 24 : 6), height: Float(field.bottom - field.top)), color: active ? RenderColor(255, 71, 142, 175) : RenderColor(183, 48, 92, 130))
            }
        }
        for bullet in game.bullets {
            let p = bullet.position + camera
            let radius = Float(max(2, bullet.radius))
            r.fillCircle(center: (Float(p.x), Float(p.y)), radius: radius, color: color(bullet.tint))
            if bullet.playerOwned { r.line(from: (Float(p.x), Float(p.y + Double(radius) * 2)), to: (Float(p.x), Float(p.y - Double(radius) * 2)), color: color(bullet.tint)) }
        }
        for pickup in game.powerUps {
            let c: RenderColor = pickup.kind == 0 ? RenderColor(89, 236, 255) : (pickup.kind == 1 ? RenderColor(126, 196, 255) : RenderColor(255, 214, 110))
            let p = pickup.position + camera
            r.fillRect(RenderRect(x: Float(p.x - 10), y: Float(p.y - 10), width: 20, height: 20), color: c)
            text(r, pickup.kind == 0 ? "L" : (pickup.kind == 1 ? "S" : "+") , Float(p.x - 3), Float(p.y - 6), RenderColor(17, 33, 60))
        }
        for particle in game.particles {
            let life = max(0, min(1, particle.life / max(0.001, particle.maxLife)))
            let p = particle.position + camera
            let particleColor = color(particle.tint)
            switch particle.kind {
            case .coreFlash:
                r.fillCircle(center: (Float(p.x), Float(p.y)), radius: Float(max(4, particle.radius * (1 + (1 - life) * 1.8))), color: RenderColor(255, 248, 228, UInt8(220 * life)))
            case .shockwave:
                r.fillCircle(center: (Float(p.x), Float(p.y)), radius: Float(particle.radius * (1 + (1 - life) * 4)), color: RenderColor(particleColor.red, particleColor.green, particleColor.blue, UInt8(70 * life)))
            case .smoke:
                r.fillCircle(center: (Float(p.x), Float(p.y)), radius: Float(particle.radius * (1 + (1 - life) * 0.6)), color: RenderColor(particleColor.red, particleColor.green, particleColor.blue, UInt8(70 * life)))
            default:
                r.fillCircle(center: (Float(p.x), Float(p.y)), radius: Float(max(1, particle.radius)), color: RenderColor(particleColor.red, particleColor.green, particleColor.blue, UInt8(255 * life)))
            }
        }
        if let bossDeath = game.combatFeedback.bossDeath {
            let p = bossDeath.position + camera
            let pulse = 16 + Float(bossDeath.elapsed) * 40
            r.fillCircle(center: (Float(p.x), Float(p.y)), radius: pulse, color: RenderColor(255, 190, 244, 78))
        }
        for number in game.damageNumbers {
            let p = number.position + camera
            let remaining = max(0, min(1, number.life / max(0.001, number.maxLife)))
            let value = number.critical ? "\(number.amount)!" : "\(number.amount)"
            let nColor = color(number.tint)
            text(r, value, Float(p.x), Float(p.y), RenderColor(nColor.red, nColor.green, nColor.blue, UInt8(255 * remaining)))
            if number.critical { text(r, "!", Float(p.x + 16), Float(p.y - 3), RenderColor(255, 249, 180, UInt8(220 * remaining))) }
        }
        let playerP = game.player + game.playerVisualOffset + camera
        let playerColor = game.playerShieldFlash > 0 ? RenderColor(122, 232, 204) :
            (game.playerHitFlash > 0 ? RenderColor(255, 128, 150) : RenderColor(81, 205, 255))
        r.fillCircle(center: (Float(playerP.x), Float(playerP.y)), radius: 18, color: playerColor)
        r.fillCircle(center: (Float(playerP.x), Float(playerP.y - 7)), radius: 8, color: game.playerHitFlash > 0 ? RenderColor(255, 246, 248) : RenderColor(232, 250, 255))
        if game.playerShieldFlash > 0 { r.fillCircle(center: (Float(playerP.x), Float(playerP.y)), radius: 25, color: RenderColor(112, 224, 255, 68)) }
        if game.precisionMode { r.fillCircle(center: (Float(playerP.x), Float(playerP.y)), radius: 5, color: RenderColor(255, 229, 112)) }
        if game.damageEdgeFlash > 0 {
            let alpha = UInt8(min(115, game.damageEdgeFlash * 440))
            r.fillRect(RenderRect(x: 0, y: Float(field.top), width: Float(width), height: 14), color: RenderColor(255, 55, 80, alpha))
            r.fillRect(RenderRect(x: 0, y: Float(height - 14), width: Float(width), height: 14), color: RenderColor(255, 55, 80, alpha))
            r.fillRect(RenderRect(x: 0, y: Float(field.top), width: 14, height: Float(field.bottom - field.top)), color: RenderColor(255, 55, 80, alpha))
            r.fillRect(RenderRect(x: Float(width - 14), y: Float(field.top), width: 14, height: Float(field.bottom - field.top)), color: RenderColor(255, 55, 80, alpha))
        }
        if game.notificationTimer > 0 { text(r, game.notificationTitle, Float(width / 2 - 150), Float(height - 70), color(game.notificationTint)) }
    }

    private static func drawCombatHUD(_ r: GameRenderer, game: Game, field: PlayfieldBounds, width: Int) {
        text(r, t(game, "THUNDER SWIFT", "雷霆疾影"), 16, 16, UITheme.Color.text)
        text(r, t(game, "STAGE", "关卡") + " \(game.stage)", 190, 16, UITheme.Color.primary)
        text(r, t(game, "KILLS", "击杀") + " \(game.kills)", Float(width - 190), 16, UITheme.Color.boss)
        text(r, t(game, "SCORE", "分数") + " \(game.score)", Float(width - 92), 16, UITheme.Color.warning)

        let healthRatio = game.health / max(1, game.maxHealth)
        progress(r, UIProgressBar(rect: UIRect(x: 18, y: 39, width: 166, height: 10),
                                  value: game.healthLag / max(1, game.maxHealth),
                                  fill: RenderColor(255, 171, 93, game.healthBarFlash > 0 ? 245 : 165),
                                  back: RenderColor(61, 28, 53)), height: 10)
        progress(r, UIProgressBar(rect: UIRect(x: 18, y: 39, width: 166, height: 10),
                                  value: healthRatio, fill: UITheme.Color.danger, back: RenderColor(0, 0, 0, 0)), height: 10)
        text(r, t(game, "HP", "生命") + " \(Int(game.health))/\(Int(game.maxHealth))", 22, 42, UITheme.Color.text)

        let shieldValue = game.reflectorTime > 0 ? 1.0 : min(1, Double(game.armorShieldCharges) / 3.0)
        progress(r, UIProgressBar(rect: UIRect(x: 198, y: 39, width: 104, height: 10), value: shieldValue,
                                  fill: UITheme.Color.shield, back: RenderColor(22, 56, 79)), height: 10)
        text(r, game.reflectorTime > 0 ? t(game, "SHIELD", "护盾") : "SHIELD x\(game.armorShieldCharges)", 202, 42, UITheme.Color.shield)

        progress(r, UIProgressBar(rect: UIRect(x: 318, y: 39, width: 170, height: 10),
                                  value: Double(game.experience) / Double(max(1, game.experienceGoal)),
                                  fill: UITheme.Color.energy, back: RenderColor(22, 56, 79)), height: 10)
        text(r, t(game, "XP", "经验"), 324, 42, UITheme.Color.text)

        let thunderReady = game.thunderEnergy >= 100
        progress(r, UIProgressBar(rect: UIRect(x: 505, y: 39, width: 124, height: 10),
                                  value: game.thunderEnergy / 100,
                                  fill: thunderReady ? UITheme.Color.warning : UITheme.Color.energy,
                                  back: RenderColor(22, 56, 79)), height: 10)
        text(r, thunderReady ? t(game, "OVERLOAD READY", "超载就绪") : t(game, "THUNDER", "雷霆") + " \(Int(game.thunderEnergy))%",
             511, 42, thunderReady ? UITheme.Color.warning : UITheme.Color.energy)

        if game.combo > 1 { text(r, t(game, "COMBO", "连击") + " x\(game.combo)", 650, 16, UITheme.Color.warning) }
        if let comboBurst = game.combatFeedback.comboFeedback {
            let life = max(0, min(1, 1 - comboBurst.elapsed / 0.9))
            let burstColor = color(comboBurst.tint)
            let label = "\(comboBurst.count) " + t(game, "COMBO!", "连击!")
            text(r, label, Float(width / 2 - 42), Float(field.top + 58 - comboBurst.elapsed * 24),
                 RenderColor(burstColor.red, burstColor.green, burstColor.blue, UInt8(255 * life)))
        }

        if let boss = game.boss {
            let ratio = boss.health / max(1, boss.maxHealth)
            progress(r, UIProgressBar(rect: UIRect(x: Double(width / 2 - 220), y: 64, width: 440, height: 10),
                                      value: ratio, fill: UITheme.Color.boss, back: RenderColor(56, 24, 67)), height: 10)
            let bossName = BossType(rawValue: boss.kind)?.title(for: game.language) ?? t(game, "DREADNOUGHT", "无畏战舰")
            let phase = boss.health / max(1, boss.maxHealth) > 0.7 ? 1 : (boss.health / max(1, boss.maxHealth) > 0.3 ? 2 : 3)
            text(r, t(game, "BOSS", "首领") + "  " + bossName + "  •  " + t(game, "PHASE", "阶段") + " \(phase)",
                 Float(width / 2 - 135), 67, UITheme.Color.text)
        }
    }

    private static func drawMenu(_ r: GameRenderer, game: Game, width: Int, height: Int) {
        panel(r, x: 32, y: 32, width: width - 64, height: height - 64)
        text(r, t(game, "HANGAR CONTROL // READY", "机库控制 // 已就绪"), 64, 74, UITheme.Color.primary)
        text(r, t(game, "THUNDER SWIFT", "雷霆疾影"), 64, 112, UITheme.Color.text)
        text(r, t(game, "SINGLE PILOT SORTIE SYSTEM", "单人作战出击系统"), 66, 140, UITheme.Color.muted)

        let center = (x: Float(290), y: Float(318))
        drawShip(r, center: center, scale: 2.5, accent: UITheme.Color.primary)
        text(r, t(game, "ACTIVE AIRFRAME", "当前机体"), 154, 454, UITheme.Color.muted)
        let shipName = ShipType(rawValue: game.profile.selectedShip)?.label(for: game.language) ?? t(game, "THUNDER", "雷霆号")
        text(r, shipName, 154, 478, UITheme.Color.text)
        text(r, t(game, "COMBAT POWER", "战力") + "  \(game.combatPower())", 154, 504, UITheme.Color.warning)

        r.fillRect(RenderRect(x: 94, y: 184, width: 390, height: 1), color: UITheme.Color.border)
        text(r, t(game, "SORTIE PROFILE", "出击档案"), 94, 205, UITheme.Color.secondary)
        text(r, t(game, "BEST SCORE", "最高分") + "  \(game.profile.bestScore)", 94, 232, UITheme.Color.text)
        text(r, t(game, "BEST COMBO", "最高连击") + "  \(game.profile.bestCombo)", 94, 258, UITheme.Color.text)
        text(r, t(game, "BOSSES DOWN", "击破首领") + "  \(game.profile.totalBosses)", 94, 284, UITheme.Color.text)

        let buttons = mainMenuButtons(width: Double(width), height: Double(height))
        let labels = [t(game, "NEW GAME", "开始游戏"), t(game, "CONTROLS", "操作设置"), t(game, "HANGAR", "机库"), t(game, "SETTINGS", "设置"), t(game, "EXIT", "退出"), t(game, "ARCHIVE", "档案馆")]
        for i in buttons.indices { button(r, buttons[i], title: labels[i], selected: false) }
        text(r, t(game, "CREDITS", "金币") + "  \(game.profile.credits)", 500, 626, UITheme.Color.warning)
        text(r, t(game, "CORES", "核心") + "  \(game.profile.cores)", 690, 626, UITheme.Color.energy)
        text(r, t(game, "ALLOY", "合金") + "  \(game.profile.alloy)", 860, 626, UITheme.Color.secondary)
        text(r, t(game, "SAVE SLOT", "存档") + " \(SaveManager.shared.activeSlot + 1)  •  " + t(game, "AUTO-SAVE ON", "自动保存开启"), 64, 626, UITheme.Color.success)
    }

    private static func drawSaveSlots(_ r: GameRenderer, game: Game, width: Int, height: Int) {
        panel(r, x: width / 2 - 420, y: 78, width: 840, height: height - 130)
        text(r, t(game, "SAVE SELECT", "选择存档"), Float(width / 2 - 75), 120, RenderColor(230, 245, 255))
        for (i, card) in saveSlotCards(width: Double(width), height: Double(height)).enumerated() { button(r, card, title: t(game, "SAVE SLOT", "存档") + " \(i + 1)", selected: i == SaveManager.shared.activeSlot) }
        button(r, saveSlotsBackButton(width: Double(width), height: Double(height)), title: t(game, "BACK", "返回"), selected: false)
    }

    private static func drawMissionSelect(_ r: GameRenderer, game: Game, width: Int, height: Int) {
        panel(r, x: width / 2 - 390, y: 66, width: 780, height: height - 120)
        text(r, t(game, "MISSION SELECT", "选择关卡"), Float(width / 2 - 90), 92, RenderColor(230, 245, 255))
        for (i, card) in missionCards(width: Double(width), height: Double(height)).enumerated() { button(r, card, title: t(game, "SECTOR", "区域") + " \(i + 1)", selected: i == game.selectedMission) }
        for (i, card) in modeCards(width: Double(width), height: Double(height)).enumerated() { button(r, card, title: GameMode(rawValue: i)?.label(for: game.language) ?? t(game, "MODE", "模式"), selected: i == game.gameMode.rawValue) }
        button(r, missionLaunchButton(width: Double(width), height: Double(height)), title: t(game, "LAUNCH", "出击"), selected: true)
        button(r, missionBackButton(width: Double(width), height: Double(height)), title: t(game, "BACK", "返回"), selected: false)
    }

    private static func drawControls(_ r: GameRenderer, game: Game, width: Int, height: Int) {
        panel(r, x: width / 2 - 320, y: 70, width: 640, height: height - 125)
        text(r, t(game, "CONTROL DECK", "操作设置"), Float(width / 2 - 90), 120, RenderColor(230, 245, 255))
        let modes = controlModeButtons(width: Double(width), height: Double(height))
        button(r, modes[0], title: "WASD", selected: game.controlMode == .wasd)
        button(r, modes[1], title: t(game, "MOUSE FOLLOW", "鼠标跟随"), selected: game.controlMode == .mouse)
        button(r, controlsBackButton(width: Double(width), height: Double(height)), title: t(game, "BACK", "返回"), selected: false)
    }

    private static func drawSettings(_ r: GameRenderer, game: Game, width: Int, height: Int) {
        panel(r, x: width / 2 - 320, y: 70, width: 640, height: height - 125)
        text(r, t(game, "SETTINGS", "设置"), Float(width / 2 - 55), 120, RenderColor(230, 245, 255))
        let language = settingsLanguageButtons(width: Double(width), height: Double(height))
        button(r, language[0], title: t(game, "ENGLISH", "英文"), selected: game.language == .english)
        button(r, language[1], title: t(game, "CHINESE", "中文"), selected: game.language == .chinese)
        button(r, settingsBGMButton(width: Double(width), height: Double(height)), title: "BGM \(game.profile.bgmVolume)%", selected: false)
        button(r, settingsSFXButton(width: Double(width), height: Double(height)), title: "SFX \(game.profile.sfxVolume)%", selected: false)
        button(r, settingsShakeButton(width: Double(width), height: Double(height)), title: t(game, "CAMERA SHAKE", "镜头震动"), selected: false)
        button(r, settingsWindowModeButton(width: Double(width), height: Double(height)), title: game.profile.isFullscreen ? t(game, "DISPLAY: FULLSCREEN", "显示：全屏") : t(game, "DISPLAY: WINDOWED", "显示：窗口化"), selected: false)
        button(r, settingsResolutionButton(width: Double(width), height: Double(height)), title: t(game, "RESOLUTION", "分辨率") + ": \(game.profile.resolutionWidth)x\(game.profile.resolutionHeight)", selected: false)
        button(r, settingsBackButton(width: Double(width), height: Double(height)), title: t(game, "BACK", "返回"), selected: false)
    }

    private static func drawHangar(_ r: GameRenderer, game: Game, width: Int, height: Int) {
        panel(r, x: 32, y: 32, width: width - 64, height: height - 64)
        text(r, t(game, "HANGAR / LOADOUT", "机库 / 装备"), 64, 70, UITheme.Color.text)
        text(r, t(game, "AIRFRAME CONFIGURATION", "机体配置台"), 66, 96, UITheme.Color.muted)
        text(r, t(game, "POWER", "战力") + "  \(game.combatPower())", Float(width - 250), 70, UITheme.Color.warning)
        let resourceSummary = t(game, "CREDITS", "金币") + " \(game.profile.credits)   " + t(game, "CORES", "核心") + " \(game.profile.cores)"
        text(r, resourceSummary, Float(width - 390), 96, UITheme.Color.secondary)

        drawShip(r, center: (x: 156, y: 282), scale: 2.2, accent: UITheme.Color.primary)
        text(r, t(game, "SELECT AIRFRAME", "选择机体"), 76, 406, UITheme.Color.muted)
        for (i, card) in shipCards(width: Double(width), height: Double(height)).enumerated() {
            let ship = ShipType(rawValue: i) ?? .thunder
            button(r, card, title: ship.label(for: game.language), selected: ship == game.shipType)
        }
        for (i, tab) in hangarTabButtons(width: Double(width), height: Double(height)).enumerated() { button(r, tab, title: i == 0 ? t(game, "EQUIPMENT", "装备") : t(game, "VAULT", "仓库"), selected: i == game.hangarTab) }
        if game.hangarTab == 0 {
            for (i, card) in hangarCards(width: Double(width), height: Double(height)).enumerated() {
                guard game.profile.equipment.indices.contains(i) else { continue }
                let item = game.profile.equipment[i]
                button(r, card, title: game.equipmentDisplayName(item), selected: false)
                text(r, t(game, "SLOT", "槽位") + " \(i + 1)", Float(card.x + 12), Float(card.y + 12), UITheme.Color.muted)
                text(r, game.equipmentQualityName(item.rarity) + "  ★\(item.stars)", Float(card.x + 12), Float(card.y + 34), color(equipmentRarityColor(item.rarity)))
                text(r, "Lv.\(item.level)  •  \(t(game, "EQUIPPED", "已装备"))", Float(card.x + 12), Float(card.y + 78), UITheme.Color.secondary)
                let promote = equipmentPromoteButton(i, width: Double(width), height: Double(height))
                r.fillRect(RenderRect(x: Float(promote.x), y: Float(promote.y), width: Float(promote.width), height: Float(promote.height)), color: UITheme.Color.panelSelected)
                text(r, item.rarity >= 4 ? t(game, "MAX", "满阶") : t(game, "ADVANCE", "进阶"), Float(promote.x + 9), Float(promote.y + 7), UITheme.Color.text)
            }
        } else {
            for (i, card) in vaultCards(width: Double(width), height: Double(height)).enumerated() {
                let visible = game.visibleVaultIndices
                let absoluteIndex = game.vaultPage * 4 + i
                if visible.indices.contains(absoluteIndex) {
                    let item = game.profile.inventory[visible[absoluteIndex]]
                    button(r, card, title: game.equipmentDisplayName(item), selected: false)
                    text(r, game.equipmentQualityName(item.rarity) + "  Lv.\(item.level)  ★\(item.stars)", Float(card.x + 12), Float(card.y + 38), color(equipmentRarityColor(item.rarity)))
                    text(r, item.slot == 0 ? t(game, "AIRFRAME", "机体") : t(game, "MODULE", "模块"), Float(card.x + 12), Float(card.y + 78), UITheme.Color.secondary)
                } else {
                    r.fillRect(RenderRect(x: Float(card.x), y: Float(card.y), width: Float(card.width), height: Float(card.height)), color: RenderColor(15, 29, 49, 190))
                    text(r, t(game, "EMPTY SLOT", "空槽位"), Float(card.x + 14), Float(card.y + 48), UITheme.Color.muted)
                }
            }
        }
        button(r, hangarBackButton(width: Double(width), height: Double(height)), title: t(game, "BACK", "返回"), selected: false)
        if game.hangarMessageTimer > 0 {
            text(r, game.hangarMessageTitle, 66, 590, UITheme.Color.success)
            text(r, game.hangarMessageDetail, 66, 612, UITheme.Color.secondary)
        }
    }

    private static func drawShip(_ r: GameRenderer, center: (x: Float, y: Float), scale: Float, accent: RenderColor) {
        let x = center.x, y = center.y
        r.fillCircle(center: (x, y - 34 * scale), radius: 10 * scale, color: RenderColor(235, 250, 255))
        r.fillRect(RenderRect(x: x - 9 * scale, y: y - 28 * scale, width: 18 * scale, height: 62 * scale), color: accent)
        r.fillRect(RenderRect(x: x - 34 * scale, y: y + 4 * scale, width: 68 * scale, height: 9 * scale), color: accent)
        r.fillRect(RenderRect(x: x - 23 * scale, y: y + 18 * scale, width: 46 * scale, height: 8 * scale), color: RenderColor(196, 237, 255))
        r.fillCircle(center: (x, y + 37 * scale), radius: 8 * scale, color: RenderColor(255, 155, 92, 220))
        r.line(from: (x - 28 * scale, y + 13 * scale), to: (x - 42 * scale, y + 30 * scale), color: UITheme.Color.borderHighlight)
        r.line(from: (x + 28 * scale, y + 13 * scale), to: (x + 42 * scale, y + 30 * scale), color: UITheme.Color.borderHighlight)
    }

    private static func drawArchive(_ r: GameRenderer, game: Game, width: Int, height: Int) {
        panel(r, x: width / 2 - 340, y: 74, width: 680, height: height - 115)
        text(r, t(game, "ARCHIVE", "档案馆"), Float(width / 2 - 50), 100, RenderColor(230, 245, 255))
        let tabs = archiveTabButtons(width: Double(width), height: Double(height))
        button(r, tabs[0], title: t(game, "ACHIEVEMENTS", "成就"), selected: game.archiveTab == 0)
        button(r, tabs[1], title: t(game, "CODEX", "图鉴"), selected: game.archiveTab == 1)
        button(r, archiveBackButton(width: Double(width), height: Double(height)), title: t(game, "BACK", "返回"), selected: false)
    }

    private static func drawPause(_ r: GameRenderer, game: Game, width: Int, height: Int) {
        panel(r, x: width / 2 - 310, y: height / 2 - 175, width: 620, height: 350)
        text(r, t(game, "MISSION PAUSED", "战斗暂停"), Float(width / 2 - 85), Float(height / 2 - 140), RenderColor(240, 247, 255))
        let buttons = pauseButtons(width: Double(width), height: Double(height))
        let titles = [t(game, "RESUME", "继续"), t(game, "RESTART", "重新开始"), t(game, "SETTINGS", "设置"), t(game, "MAIN MENU", "主菜单"), t(game, "EXIT", "退出")]
        for (i, title) in titles.enumerated() { button(r, buttons[i], title: title, selected: false) }
    }

    private static func drawUpgrade(_ r: GameRenderer, game: Game, width: Int, height: Int) {
        text(r, t(game, "MODULE AVAILABLE", "新模块可用"), Float(width / 2 - 105), Float(height / 2 - 175), RenderColor(244, 211, 116))
        for (i, card) in upgradeCards(width: Double(width), height: Double(height)).enumerated() { button(r, card, title: i < game.upgradeOptions.count ? game.upgradeOptions[i].title : t(game, "MODULE", "模块"), selected: false) }
    }

    private static func drawGameOver(_ r: GameRenderer, game: Game, width: Int, height: Int) {
        panel(r, x: width / 2 - 250, y: height / 2 - 155, width: 500, height: 300)
        text(r, game.runWon ? t(game, "MISSION COMPLETE", "任务完成") : t(game, "SORTIE FAILED", "任务失败"), Float(width / 2 - 90), Float(height / 2 - 120), RenderColor(244, 211, 116))
        text(r, t(game, "SCORE", "分数") + "  \(game.score)", Float(width / 2 - 55), Float(height / 2 - 45), RenderColor(237, 246, 255))
        let buttons = gameOverButtons(width: Double(width), height: Double(height))
        button(r, buttons[0], title: t(game, "RESTART", "重新开始"), selected: true)
        button(r, buttons[1], title: t(game, "MAIN MENU", "主菜单"), selected: false)
    }

    private static func panel(_ r: GameRenderer, x: Int, y: Int, width: Int, height: Int) {
        let component = UIPanel(rect: UIRect(x: Double(x), y: Double(y), width: Double(width), height: Double(height)))
        r.fillRect(RenderRect(x: Float(component.rect.x), y: Float(component.rect.y), width: Float(component.rect.width), height: Float(component.rect.height)), color: UITheme.Color.panel)
        r.line(from: (Float(x), Float(y)), to: (Float(x + width), Float(y)), color: UITheme.Color.borderHighlight)
        r.line(from: (Float(x), Float(y + height)), to: (Float(x + width), Float(y + height)), color: UITheme.Color.border)
        r.line(from: (Float(x), Float(y)), to: (Float(x), Float(y + height)), color: UITheme.Color.border)
        r.line(from: (Float(x + width), Float(y)), to: (Float(x + width), Float(y + height)), color: UITheme.Color.border)
    }

    private static func button(_ r: GameRenderer, _ rect: UIRect, title: String, selected: Bool) {
        let component = UIButton(rect: rect, title: title, selected: selected)
        let state = UIInteraction.state(for: component.rect, selected: component.selected, enabled: component.enabled)
        let fill: RenderColor
        let border: RenderColor
        switch state {
        case .selected:
            fill = UITheme.Color.panelSelected; border = UITheme.Color.borderHighlight
        case .hover:
            fill = UITheme.Color.panelHover; border = UITheme.Color.primary
        case .disabled:
            fill = RenderColor(25, 34, 49, 190); border = RenderColor(57, 70, 86, 180)
        default:
            fill = UITheme.Color.panelRaised; border = UITheme.Color.border
        }
        r.fillRect(RenderRect(x: Float(rect.x), y: Float(rect.y), width: Float(rect.width), height: Float(rect.height)), color: fill)
        r.line(from: (Float(rect.x), Float(rect.y)), to: (Float(rect.x + rect.width), Float(rect.y)), color: border)
        r.line(from: (Float(rect.x), Float(rect.y + rect.height)), to: (Float(rect.x + rect.width), Float(rect.y + rect.height)), color: border)
        let labelColor = state == .disabled ? UITheme.Color.muted : UITheme.Color.text
        text(r, component.title, Float(rect.x + 14), Float(rect.y + rect.height * 0.5 - 5), labelColor)
    }

    private static func bar(_ r: GameRenderer, x: Float, y: Float, width: Float, value: Double, fill: RenderColor, back: RenderColor) {
        progress(r, UIProgressBar(rect: UIRect(x: Double(x), y: Double(y), width: Double(width), height: 10), value: value, fill: fill, back: back), height: 10)
    }

    private static func progress(_ r: GameRenderer, _ bar: UIProgressBar, height: Float) {
        let rect = bar.rect
        r.fillRect(RenderRect(x: Float(rect.x), y: Float(rect.y), width: Float(rect.width), height: height), color: bar.back)
        r.fillRect(RenderRect(x: Float(rect.x), y: Float(rect.y), width: Float(rect.width) * Float(min(1, max(0, bar.value))), height: height), color: bar.fill)
        r.line(from: (Float(rect.x), Float(rect.y)), to: (Float(rect.x + rect.width), Float(rect.y)), color: UITheme.Color.border)
    }

    private static func text(_ r: GameRenderer, _ value: String, _ x: Float, _ y: Float, _ c: RenderColor) { r.drawText(value, at: (x: x, y: y), color: c) }

    private static func t(_ game: Game, _ english: String, _ chinese: String) -> String {
        game.uiText(english, chinese)
    }

    private static func color(_ value: UInt32) -> RenderColor {
        let v = UInt32(value)
        return RenderColor(UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff))
    }

    private static func highlighted(_ color: RenderColor, amount: Double) -> RenderColor {
        guard amount > 0 else { return color }
        func blend(_ value: UInt8) -> UInt8 { UInt8(min(255, Double(value) + (255 - Double(value)) * min(1, amount))) }
        return RenderColor(blend(color.red), blend(color.green), blend(color.blue), color.alpha)
    }
}
