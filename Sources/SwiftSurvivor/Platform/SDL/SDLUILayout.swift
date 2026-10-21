import Foundation

func mainMenuButtons(width: Double, height: Double) -> [UIRect] {
    // Keep this order aligned with Game.handleMouseClick's existing actions.
    return [
        UIRect(x: width - 350, y: height - 174, width: 302, height: 72),
        UIRect(x: 40, y: 394, width: 220, height: 64),
        UIRect(x: 40, y: 238, width: 220, height: 64),
        UIRect(x: 40, y: 546, width: 220, height: 56),
        UIRect(x: 40, y: 614, width: 220, height: 40),
        UIRect(x: 40, y: 316, width: 220, height: 64)
    ]
}
func saveSlotButton(width: Double, height: Double) -> UIRect { UIRect(x: 40, y: 128, width: 220, height: 76) }
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
    let cardWidth = (width - 430 - 48) / 4
    return (0..<MissionCatalog.all.count).map {
        UIRect(x: 40 + Double($0 % 4) * (cardWidth + 16), y: 190 + Double($0 / 4) * 136, width: cardWidth, height: 120)
    }
}
func modeCards(width: Double, height: Double) -> [UIRect] {
    let cardWidth = (width - 446) / 2
    let gap = 16.0
    let totalWidth = Double(GameMode.allCases.count) * cardWidth + Double(max(0, GameMode.allCases.count - 1)) * gap
    let left = max(40, (width - 350 - totalWidth) / 2)
    return (0..<GameMode.allCases.count).map { UIRect(x: left + Double($0) * (cardWidth + gap), y: 494, width: cardWidth, height: 108) }
}
func missionLaunchButton(width: Double, height: Double) -> UIRect { UIRect(x: width - 350, y: height - 174, width: 302, height: 72) }
func missionBackButton(width: Double, height: Double) -> UIRect { UIRect(x: 40, y: height - 84, width: 220, height: 48) }
func controlsBackButton(width: Double, height: Double) -> UIRect { UIRect(x: width / 2 - 120, y: height - 92, width: 240, height: 50) }
func settingsLanguageButtons(width: Double, height: Double) -> [UIRect] {
    let left = width / 2 - 230
    return [UIRect(x: left, y: 158, width: 220, height: 56), UIRect(x: left + 240, y: 158, width: 220, height: 56)]
}
func settingsBGMButton(width: Double, height: Double) -> UIRect { UIRect(x: width / 2 - 230, y: 242, width: 220, height: 46) }
func settingsSFXButton(width: Double, height: Double) -> UIRect { UIRect(x: width / 2 + 10, y: 242, width: 220, height: 46) }
func settingsShakeButton(width: Double, height: Double) -> UIRect { UIRect(x: width / 2 - 230, y: 320, width: 460, height: 46) }
func settingsWindowModeButton(width: Double, height: Double) -> UIRect { UIRect(x: width / 2 - 230, y: 392, width: 460, height: 46) }
func settingsResolutionButton(width: Double, height: Double) -> UIRect { UIRect(x: width / 2 - 230, y: 454, width: 460, height: 46) }
func settingsUIScaleButton(width: Double, height: Double) -> UIRect { UIRect(x: width / 2 - 230, y: 516, width: 460, height: 46) }
func settingsBackButton(width: Double, height: Double) -> UIRect { UIRect(x: width / 2 - 120, y: height - 82, width: 240, height: 46) }
func pauseButtons(width: Double, height: Double) -> [UIRect] {
    let left = width / 2 - 145, top = height / 2 - 130
    return (0..<5).map { UIRect(x: left, y: top + Double($0) * 62, width: 290, height: 48) }
}
func confirmationPanel(width: Double, height: Double) -> UIRect {
    UIRect(x: width / 2 - 270, y: height / 2 - 112, width: 540, height: 224)
}
func confirmationConfirmButton(width: Double, height: Double) -> UIRect {
    let panel = confirmationPanel(width: width, height: height)
    return UIRect(x: panel.x + 34, y: panel.y + panel.height - 66, width: 220, height: 42)
}
func confirmationCancelButton(width: Double, height: Double) -> UIRect {
    let panel = confirmationPanel(width: width, height: height)
    return UIRect(x: panel.x + panel.width - 254, y: panel.y + panel.height - 66, width: 220, height: 42)
}
func gameOverButtons(width: Double, height: Double) -> [UIRect] {
    let left = width / 2 - 145, top = height / 2 + 95
    return [UIRect(x: left, y: top, width: 290, height: 50), UIRect(x: left, y: top + 62, width: 290, height: 50)]
}
func upgradeCards(width: Double, height: Double) -> [UIRect] {
    let cardWidth = 196.0
    let gap = 12.0
    let totalWidth = cardWidth * 3 + gap * 2
    let left = (width - totalWidth) * 0.5
    let top = min(height - 132, height * 0.64)
    return (0..<3).map { UIRect(x: left + Double($0) * (cardWidth + gap), y: top, width: cardWidth, height: 104) }
}
// 机库采用三栏栅格：左栏机体（x 64-330）/ 中栏内容（x 350-990）/ 右栏详情（x 1005-1215）。
// 所有热区与 SDLNativeGameRenderer 的绘制坐标共用同一组常量，避免绘制与点击错位。
/// 机库中栏内容区几何常量。
enum HangarLayout {
    static let contentLeft = 350.0
    static let contentRight = 990.0
    static let cardWidth = 300.0
    static let cardGap = 22.0
    static let cardHeight = 140.0
    /// 中栏卡片列 x 坐标（两列）。
    static var columnX: [Double] { [contentLeft, contentLeft + cardWidth + cardGap] }
}

func hangarCards(width: Double, height: Double) -> [UIRect] {
    (0..<4).map { index in
        UIRect(x: HangarLayout.columnX[index % 2], y: 190 + Double(index / 2) * 152,
               width: HangarLayout.cardWidth, height: HangarLayout.cardHeight)
    }
}
// 右栏按钮按主次分组：主操作（强化）居首并排，进阶 / 锁定依次全宽。
func hangarUpgradeButton(width: Double, height: Double) -> UIRect { UIRect(x: width - 275, y: 446, width: 100, height: 44) }
func hangarBatchUpgradeButton(width: Double, height: Double) -> UIRect { UIRect(x: width - 165, y: 446, width: 100, height: 44) }
func hangarAdvanceButton(width: Double, height: Double) -> UIRect { UIRect(x: width - 275, y: 500, width: 210, height: 44) }
func hangarLockButton(width: Double, height: Double) -> UIRect { UIRect(x: width - 275, y: 554, width: 210, height: 40) }
func hangarBackButton(width: Double, height: Double) -> UIRect { UIRect(x: 64, y: 634, width: 200, height: 46) }
/// 经验素材格（规格第 5 节：下方小格选经验素材，配置表 experienceSources 顺序）。
func hangarExpCells(width: Double, height: Double) -> [UIRect] {
    [UIRect(x: 350, y: 520, width: 156, height: 56), UIRect(x: 518, y: 520, width: 156, height: 56)]
}
/// Tab 栏（装备 / 战神两个页签）：左对齐内容区，40 高易点热区；选中态由绘制层补下划线指示条。
func hangarTabButtons(width: Double, height: Double) -> [UIRect] {
    (0..<2).map { UIRect(x: 350 + Double($0) * 180, y: 128, width: 170, height: 40) }
}
func warriorRecipeCards(width: Double, height: Double) -> [UIRect] {
    (0..<7).map { UIRect(x: 350, y: 214 + Double($0) * 46, width: 290, height: 40) }
}
func warriorSlotCards(width: Double, height: Double) -> [UIRect] {
    (0..<4).map { UIRect(x: 664, y: 214 + Double($0) * 82, width: 326, height: 74) }
}
func warriorFuseButton(width: Double, height: Double) -> UIRect { UIRect(x: width - 275, y: 410, width: 210, height: 44) }
func warriorLevelButton(width: Double, height: Double) -> UIRect { UIRect(x: width - 275, y: 462, width: 210, height: 44) }
func warriorAdvanceButton(width: Double, height: Double) -> UIRect { UIRect(x: width - 275, y: 514, width: 210, height: 44) }
func warriorDeployButton(width: Double, height: Double) -> UIRect { UIRect(x: width - 275, y: 568, width: 105, height: 40) }
func warriorDissolveButton(width: Double, height: Double) -> UIRect { UIRect(x: width - 165, y: 568, width: 105, height: 40) }
func warriorExpButton(width: Double, height: Double) -> UIRect { UIRect(x: width - 275, y: 616, width: 210, height: 36) }
func vaultCards(width: Double, height: Double) -> [UIRect] {
    (0..<4).map { index in
        UIRect(x: HangarLayout.columnX[index % 2], y: 238 + Double(index / 2) * 152,
               width: HangarLayout.cardWidth, height: HangarLayout.cardHeight)
    }
}
// 换装子视图工具行（位于 Tab 行下方）：返回居左，标题居中，翻页器居右；排序固定为战力优先，无排序按钮。
// 页码计数不占工具行位置，绘制在翻页按钮上方，避免与箭头按钮重叠。
func vaultBackToSlotsButton(width: Double, height: Double) -> UIRect { UIRect(x: 350, y: 190, width: 120, height: 34) }
func vaultPrevButton(width: Double, height: Double) -> UIRect { UIRect(x: 894, y: 190, width: 44, height: 34) }
func vaultNextButton(width: Double, height: Double) -> UIRect { UIRect(x: 946, y: 190, width: 44, height: 34) }
/// 页码计数中心（位于翻页按钮正上方）。
func vaultPageLabelCenterX(width: Double, height: Double) -> Double { 942 }
func vaultEquipButton(width: Double, height: Double) -> UIRect { UIRect(x: width - 275, y: 446, width: 210, height: 46) }
func vaultSelectedLockButton(width: Double, height: Double) -> UIRect { UIRect(x: width - 275, y: 502, width: 210, height: 40) }
/// 机体选择列表：视口内每行 2 个（行高 60，卡片 118x52），超出行数靠右侧滚动条查看。
/// 视口高度取两行整（112），保证行始终完整显示、不会出现被裁一半的卡片。
func shipListArea(width: Double, height: Double) -> UIRect { UIRect(x: 64, y: 480, width: 252, height: 112) }
func shipScrollTrack(width: Double, height: Double) -> UIRect {
    let area = shipListArea(width: width, height: height)
    return UIRect(x: area.x + area.width + 6, y: area.y, width: 8, height: area.height)
}
/// 机体列表内容总高（末行不留行距间隙）。
func shipListContentHeight() -> Double {
    let rows = Double((ShipType.allCases.count + 1) / 2)
    return rows * 60 - 8
}
func shipListMaxScroll(width: Double, height: Double) -> Double {
    max(0, shipListContentHeight() - shipListArea(width: width, height: height).height)
}
/// 滚动条滑块矩形（按当前滚动量）。
func shipScrollKnob(width: Double, height: Double, scroll: Double) -> UIRect {
    let track = shipScrollTrack(width: width, height: height)
    let content = shipListContentHeight()
    guard content > track.height else { return track }
    let knobHeight = max(28, (track.height * track.height / content).rounded())
    let maxScroll = content - track.height
    let ratio = maxScroll > 0 ? min(max(0, scroll), maxScroll) / maxScroll : 0
    return UIRect(x: track.x, y: track.y + ratio * (track.height - knobHeight), width: track.width, height: knobHeight)
}
/// 机体卡片未滚动前的绝对矩形（渲染与点击都需再减去当前滚动量、并裁剪到视口内）。
func shipCards(width: Double, height: Double) -> [UIRect] {
    let area = shipListArea(width: width, height: height)
    return ShipType.allCases.enumerated().map { index, _ in
        UIRect(x: area.x + Double(index % 2) * 128, y: area.y + Double(index / 2) * 60, width: 118, height: 52)
    }
}
/// 机体列表行距（与 shipCards 一致）：滚动量按行对齐，避免出现被裁一半的卡片。
func shipRowStride() -> Double { 60 }
/// 把任意滚动量对齐到整行，并夹在 [0, shipListMaxScroll] 内。
func alignedShipScroll(_ value: Double, width: Double, height: Double) -> Double {
    let maxScroll = shipListMaxScroll(width: width, height: height)
    guard maxScroll > 0 else { return 0 }
    let stride = shipRowStride()
    let steps = (maxScroll / stride).rounded(.up)
    let step = min(max(0, (value / stride).rounded()), steps)
    return min(maxScroll, step * stride)
}
/// 由滑块顶部 Y 反算滚动量（拖拽滚动条时使用）。
func shipScrollValue(forKnobY knobY: Double, width: Double, height: Double) -> Double {
    let track = shipScrollTrack(width: width, height: height)
    let knobHeight = shipScrollKnob(width: width, height: height, scroll: 0).height
    let travel = track.height - knobHeight
    guard travel > 0 else { return 0 }
    let ratio = (knobY - track.y) / travel
    return alignedShipScroll(ratio * shipListMaxScroll(width: width, height: height), width: width, height: height)
}
func powerUpTint(_ kind: Int) -> UInt32 {
    switch kind { case 0: return rgb(89, 236, 255); case 1: return rgb(126, 196, 255); default: return rgb(255, 214, 110) }
}
