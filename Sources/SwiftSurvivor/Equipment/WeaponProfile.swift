import Foundation

/// 弹道原型代号。复用现有五种武器实现（App.swift fireWeapon 的五个分支），
/// 每系装备通过 WeaponProfile 参数化获得唯一弹道签名，而不是换皮。
enum WeaponArchetype: String, CaseIterable, Codable {
    case cannon
    case laser
    case scatter
    case missile
    case emp
}

/// 单件装备的弹道签名（规格第 2 节：每架战机必须有唯一弹道签名）。
/// 由 equipment_series.json 的 weaponProfile 字段驱动。
struct WeaponProfile: Codable, Equatable, Hashable {
    var archetype: WeaponArchetype
    var damageScale: Double
    var fireRateScale: Double
    var projectileCount: Int
    /// 单发扇面张角（弧度），cannon/scatter 等多弹丸原型使用。
    var spread: Double
    var speedScale: Double
    var pierce: Int
    /// 导弹类原型的转向速率（弧度/秒），0 表示不追踪。
    var homingTurn: Double
    var radiusScale: Double
}
