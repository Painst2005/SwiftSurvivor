import Foundation

/// Native SDL presentation for the full game.  Gameplay remains independent
/// of SDL; this layer translates the model into lightweight primitives.
enum SDLNativeGameRenderer {
    static func draw(_ renderer: GameRenderer, game: Game, width: Int, height: Int) {
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
        r.fillRect(RenderRect(x: 0, y: 0, width: Float(width), height: Float(height)), color: RenderColor(6, 10, 25))
        for star in game.stars {
            r.fillCircle(center: (Float(star.position.x), Float(star.position.y)), radius: Float(max(1, star.radius)), color: color(star.tint))
        }
        let field = playfieldBounds(width: Double(width), height: Double(height))
        r.fillRect(RenderRect(x: 0, y: Float(field.top), width: Float(width), height: Float(field.bottom - field.top)), color: RenderColor(8, 17, 43))
        for lane in stride(from: 0, through: width, by: 96) {
            r.fillRect(RenderRect(x: Float(lane), y: Float(field.top), width: 1, height: Float(field.bottom - field.top)), color: RenderColor(18, 38, 70, 100))
        }
        r.fillRect(RenderRect(x: 0, y: 0, width: Float(width), height: 54), color: RenderColor(15, 27, 53))
    }

    private static func drawBattle(_ r: GameRenderer, game: Game, width: Int, height: Int) {
        let field = playfieldBounds(width: Double(width), height: Double(height))
        let camera = game.combatFeedback.cameraOffset
        text(r, t(game, "THUNDER SWIFT", "雷霆疾影"), 16, 16, RenderColor(225, 242, 255))
        text(r, t(game, "STAGE", "关卡") + " \(game.stage)", 190, 16, RenderColor(126, 190, 255))
        text(r, t(game, "KILLS", "击杀") + " \(game.kills)", Float(width - 170), 16, RenderColor(235, 187, 255))
        text(r, t(game, "SCORE", "分数") + " \(game.score)", Float(width - 90), 16, RenderColor(255, 219, 125))
        bar(r, x: 18, y: 39, width: 190, value: game.healthLag / max(1, game.maxHealth), fill: RenderColor(255, 171, 93, game.healthBarFlash > 0 ? 245 : 165), back: RenderColor(61, 28, 53))
        bar(r, x: 18, y: 39, width: 190, value: game.health / max(1, game.maxHealth), fill: RenderColor(239, 70, 105), back: RenderColor(0, 0, 0, 0))
        text(r, t(game, "HP", "生命") + " \(Int(game.health))/\(Int(game.maxHealth))", 22, 42, RenderColor(255, 244, 247))
        bar(r, x: 225, y: 39, width: 190, value: Double(game.experience) / Double(max(1, game.experienceGoal)), fill: RenderColor(138, 229, 255), back: RenderColor(22, 56, 79))
        text(r, t(game, "XP", "经验"), 232, 42, RenderColor(215, 245, 255))
        text(r, t(game, "THUNDER", "雷霆") + " \(Int(game.thunderEnergy))%", 430, 42, RenderColor(106, 239, 255))
        if game.combo > 1 { text(r, t(game, "COMBO", "连击") + " x\(game.combo)", 640, 16, RenderColor(255, 181, 91)) }

        if let boss = game.boss {
            bar(r, x: Float(width / 2 - 220), y: 64, width: 440, value: boss.health / max(1, boss.maxHealth), fill: RenderColor(226, 71, 226), back: RenderColor(56, 24, 67))
            let bossName = BossType(rawValue: boss.kind)?.title(for: game.language) ?? t(game, "DREADNOUGHT", "无畏战舰")
            text(r, t(game, "BOSS", "首领") + "  " + bossName, Float(width / 2 - 110), 67, RenderColor(255, 225, 255))
        }

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

    private static func drawMenu(_ r: GameRenderer, game: Game, width: Int, height: Int) {
        panel(r, x: width / 2 - 300, y: 78, width: 600, height: height - 130)
        text(r, t(game, "THUNDER SWIFT", "雷霆疾影"), Float(width / 2 - 120), 122, RenderColor(230, 245, 255))
        text(r, t(game, "NEON SKY // ARCADE FLIGHT SYSTEM", "霓虹天际 // 街机飞行系统"), Float(width / 2 - 155), 160, RenderColor(89, 195, 246))
        let buttons = mainMenuButtons(width: Double(width), height: Double(height))
        let labels = [t(game, "NEW GAME", "开始游戏"), t(game, "CONTROLS", "操作设置"), t(game, "HANGAR", "机库"), t(game, "SETTINGS", "设置"), t(game, "EXIT", "退出"), t(game, "ARCHIVE", "档案馆")]
        for i in buttons.indices { button(r, buttons[i], title: labels[i], selected: false) }
        text(r, t(game, "CREDITS", "金币") + " \(game.profile.credits)   " + t(game, "CORES", "核心") + " \(game.profile.cores)   " + t(game, "ALLOY", "合金") + " \(game.profile.alloy)", Float(width / 2 - 170), 250, RenderColor(255, 211, 112))
        text(r, t(game, "SAVE SLOT", "存档") + " \(SaveManager.shared.activeSlot + 1)  •  " + t(game, "AUTO-SAVE ON", "自动保存开启"), 30, 42, RenderColor(137, 238, 180))
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
        panel(r, x: width / 2 - 390, y: 52, width: 780, height: height - 100)
        text(r, t(game, "HANGAR / LOADOUT", "机库 / 装备"), Float(width / 2 - 120), 90, RenderColor(230, 245, 255))
        for (i, tab) in hangarTabButtons(width: Double(width), height: Double(height)).enumerated() { button(r, tab, title: i == 0 ? t(game, "EQUIPMENT", "装备") : t(game, "VAULT", "仓库"), selected: i == game.hangarTab) }
        for (i, card) in hangarCards(width: Double(width), height: Double(height)).enumerated() { button(r, card, title: t(game, "MODULE", "模块") + " \(i + 1)", selected: false) }
        button(r, hangarBackButton(width: Double(width), height: Double(height)), title: t(game, "BACK", "返回"), selected: false)
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
        let titles = [t(game, "RESUME", "继续"), t(game, "RESTART", "重新开始"), t(game, "SETTINGS", "设置"), t(game, "HANGAR", "机库"), t(game, "EXIT", "退出")]
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
        r.fillRect(RenderRect(x: Float(x), y: Float(y), width: Float(width), height: Float(height)), color: RenderColor(12, 24, 51, 245))
        r.line(from: (Float(x), Float(y)), to: (Float(x + width), Float(y)), color: RenderColor(53, 151, 214))
    }

    private static func button(_ r: GameRenderer, _ rect: UIRect, title: String, selected: Bool) {
        let c = selected ? RenderColor(40, 137, 206) : RenderColor(24, 55, 90)
        r.fillRect(RenderRect(x: Float(rect.x), y: Float(rect.y), width: Float(rect.width), height: Float(rect.height)), color: c)
        text(r, title, Float(rect.x + 12), Float(rect.y + rect.height * 0.5 - 5), RenderColor(236, 246, 255))
    }

    private static func bar(_ r: GameRenderer, x: Float, y: Float, width: Float, value: Double, fill: RenderColor, back: RenderColor) {
        r.fillRect(RenderRect(x: x, y: y, width: width, height: 10), color: back)
        r.fillRect(RenderRect(x: x, y: y, width: width * Float(min(1, max(0, value))), height: 10), color: fill)
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
