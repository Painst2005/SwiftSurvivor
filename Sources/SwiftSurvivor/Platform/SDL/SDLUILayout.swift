import Foundation

func mainMenuButtons(width: Double, height: Double) -> [UIRect] {
    let left = width / 2 - 145, top = height / 2 - 80
    var buttons = (0..<5).map { UIRect(x: left, y: top + Double($0) * 54, width: 290, height: 48) }
    buttons.append(UIRect(x: left, y: top + 5 * 54, width: 290, height: 48))
    return buttons
}
func saveSlotButton(width: Double, height: Double) -> UIRect { UIRect(x: 28, y: 28, width: 270, height: 92) }
func saveSlotCards(width: Double, height: Double) -> [UIRect] {
    let left = width / 2 - 350
    return (0..<SaveManager.slotCount).map { UIRect(x: left + Double($0) * 235, y: 230, width: 220, height: 190) }
}
func saveSlotsBackButton(width: Double, height: Double) -> UIRect { UIRect(x: width / 2 - 120, y: height - 92, width: 240, height: 50) }
func archiveTabButtons(width: Double, height: Double) -> [UIRect] {
    let left = width / 2 - 190
    return [UIRect(x: left, y: 142, width: 180, height: 38), UIRect(x: left + 200, y: 142, width: 180, height: 38)]
}
func archiveBackButton(width: Double, height: Double) -> UIRect { UIRect(x: width / 2 - 120, y: height - 82, width: 240, height: 50) }
func codexCategoryButtons(width: Double, height: Double) -> [UIRect] {
    let left = width / 2 - 300
    return (0..<3).map { UIRect(x: left + Double($0) * 205, y: 198, width: 190, height: 32) }
}
func codexPrevButton(width: Double, height: Double) -> UIRect { UIRect(x: width / 2 - 300, y: height - 135, width: 120, height: 36) }
func codexNextButton(width: Double, height: Double) -> UIRect { UIRect(x: width / 2 + 180, y: height - 135, width: 120, height: 36) }
func missionCards(width: Double, height: Double) -> [UIRect] {
    let left = width / 2 - 380
    return (0..<MissionCatalog.all.count).map { let row = $0 / 4, column = $0 % 4; return UIRect(x: left + Double(column) * 194, y: 180 + Double(row) * 112, width: 182, height: 100) }
}
func modeCards(width: Double, height: Double) -> [UIRect] {
    let left = width / 2 - 380
    return (0..<GameMode.allCases.count).map { UIRect(x: left + Double($0) * 194, y: 430, width: 182, height: 82) }
}
func missionLaunchButton(width: Double, height: Double) -> UIRect { UIRect(x: width / 2 + 20, y: height - 86, width: 180, height: 50) }
func missionBackButton(width: Double, height: Double) -> UIRect { UIRect(x: width / 2 - 200, y: height - 86, width: 180, height: 50) }
func controlModeButtons(width: Double, height: Double) -> [UIRect] {
    let left = width / 2 - 230, top = height / 2 - 36
    return [UIRect(x: left, y: top, width: 220, height: 104), UIRect(x: left + 240, y: top, width: 220, height: 104)]
}
func controlsBackButton(width: Double, height: Double) -> UIRect { UIRect(x: width / 2 - 120, y: height - 92, width: 240, height: 50) }
func settingsLanguageButtons(width: Double, height: Double) -> [UIRect] {
    let left = width / 2 - 230
    return [UIRect(x: left, y: 220, width: 220, height: 70), UIRect(x: left + 240, y: 220, width: 220, height: 70)]
}
func settingsBGMButton(width: Double, height: Double) -> UIRect { UIRect(x: width / 2 - 230, y: 310, width: 220, height: 52) }
func settingsSFXButton(width: Double, height: Double) -> UIRect { UIRect(x: width / 2 + 10, y: 310, width: 220, height: 52) }
func settingsShakeButton(width: Double, height: Double) -> UIRect { UIRect(x: width / 2 - 230, y: 380, width: 460, height: 52) }
func settingsWindowModeButton(width: Double, height: Double) -> UIRect { UIRect(x: width / 2 - 230, y: 450, width: 460, height: 52) }
func settingsResolutionButton(width: Double, height: Double) -> UIRect { UIRect(x: width / 2 - 230, y: 518, width: 460, height: 52) }
func settingsBackButton(width: Double, height: Double) -> UIRect { UIRect(x: width / 2 - 120, y: height - 92, width: 240, height: 50) }
func pauseButtons(width: Double, height: Double) -> [UIRect] {
    let left = width / 2 - 145, top = height / 2 - 112
    return (0..<5).map { UIRect(x: left, y: top + Double($0) * 62, width: 290, height: 48) }
}
func gameOverButtons(width: Double, height: Double) -> [UIRect] {
    let left = width / 2 - 145, top = height / 2 + 62
    return [UIRect(x: left, y: top, width: 290, height: 50), UIRect(x: left, y: top + 62, width: 290, height: 50)]
}
func upgradeCards(width: Double, height: Double) -> [UIRect] {
    let left = width / 2 - 350, top = height / 2 - 20
    return (0..<3).map { UIRect(x: left + Double($0) * 235, y: top, width: 220, height: 130) }
}
func hangarCards(width: Double, height: Double) -> [UIRect] {
    let left = width / 2 - 350, top = 210.0
    return (0..<5).map { index in
        let row = index < 3 ? 0 : 1, column = index < 3 ? index : index - 3
        return UIRect(x: left + (row == 0 ? 0 : 117.5) + Double(column) * 235, y: top + Double(row) * 135, width: 220, height: 118)
    }
}
func equipmentPromoteButton(_ slot: Int, width: Double, height: Double) -> UIRect {
    let card = hangarCards(width: width, height: height)[min(4, max(0, slot))]
    return UIRect(x: card.x + card.width - 92, y: card.y + 87, width: 78, height: 24)
}
func equipmentLockButton(_ slot: Int, width: Double, height: Double) -> UIRect {
    let card = hangarCards(width: width, height: height)[min(4, max(0, slot))]
    return UIRect(x: card.x + card.width - 64, y: card.y + 10, width: 54, height: 22)
}
func hangarBackButton(width: Double, height: Double) -> UIRect { UIRect(x: width / 2 - 120, y: height - 82, width: 240, height: 50) }
func hangarTabButtons(width: Double, height: Double) -> [UIRect] {
    let left = width / 2 - 170
    return [UIRect(x: left, y: 180, width: 160, height: 30), UIRect(x: left + 180, y: 180, width: 160, height: 30)]
}
func vaultCards(width: Double, height: Double) -> [UIRect] {
    let left = width / 2 - 320, top = 210.0
    return (0..<4).map { UIRect(x: left + Double($0 % 2) * 330, y: top + Double($0 / 2) * 135, width: 300, height: 118) }
}
func vaultFilterButton(width: Double, height: Double) -> UIRect { UIRect(x: width / 2 - 320, y: 144, width: 150, height: 30) }
func vaultSortButton(width: Double, height: Double) -> UIRect { UIRect(x: width / 2 - 160, y: 144, width: 150, height: 30) }
func vaultPrevButton(width: Double, height: Double) -> UIRect { UIRect(x: width / 2 + 10, y: 144, width: 90, height: 30) }
func vaultNextButton(width: Double, height: Double) -> UIRect { UIRect(x: width / 2 + 110, y: 144, width: 90, height: 30) }
func vaultLockButton(_ cardIndex: Int, width: Double, height: Double) -> UIRect {
    let card = vaultCards(width: width, height: height)[min(3, max(0, cardIndex))]
    return UIRect(x: card.x + card.width - 64, y: card.y + 10, width: 54, height: 22)
}
func shipCards(width: Double, height: Double) -> [UIRect] {
    let left = width / 2 - 335
    return ShipType.allCases.map { UIRect(x: left + Double($0.rawValue) * 136, y: 490, width: 126, height: 68) }
}
func powerUpTint(_ kind: Int) -> UInt32 {
    switch kind { case 0: return rgb(89, 236, 255); case 1: return rgb(126, 196, 255); default: return rgb(255, 214, 110) }
}
