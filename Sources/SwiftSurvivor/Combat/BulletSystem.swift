import Foundation
import WinSDK

// MARK: - Data-driven bullet system

enum BulletType: Int {
    case normal = 0
    case aimed = 1
    case boss = 2
    case laser = 3
    case explosive = 4
    case piercing = 5
    /// Large, low-damage projectile train released by a Cosmic Ray warning.
    case cosmicRayBarrage = 6
}

enum BulletPattern: Int {
    case single = 0
    case aimed = 1
    case triple = 2
    case spread = 3
    case ring = 4
    case spiral = 5
}

enum BulletModifier: Int {
    case constantVelocity = 0
    case accelerate = 1
    case homing = 2
    case sineWave = 3
    case delayedActivation = 4
    case lockDirection = 5
    case curve = 6
    case stopAndGo = 7
    case split = 8
    case bounce = 9
}

struct BulletEmitter {
    var pattern: BulletPattern
    var count: Int
    var speed: Double
    var damage: Double
    var radius: Double
    var lifetime: Double
    var tint: COLORREF
    var bulletType: BulletType
    var modifiers: [BulletModifier] = [.constantVelocity]
    var spread: Double = 0.45
    var rotation: Double = 0
    var homingDuration: Double = 0
    var maxTurnRate: Double = 0
    var acceleration: Double = 0
    var splitCount: Int = 0
    var splitSpread: Double = 0.3
    var bounceCount: Int = 1
    var activationDelay: Double = 0
}

struct Bullet {
    // Core state only. Movement and pattern behavior are applied by Game's
    // BulletSystem helpers using the modifiers below.
    var position: Vec2
    var velocity: Vec2
    var radius: Double
    var damage: Double
    var life: Double
    var playerOwned: Bool
    var tint: COLORREF
    var bulletType: Int = BulletType.normal.rawValue
    var modifiers: [BulletModifier] = [.constantVelocity]
    var age: Double = 0
    var grazeAwarded: Bool = false
    var pierceRemaining: Int = 0
    var weaponStyle: Int = WeaponType.cannon.rawValue
    var modifierPhase: Double = 0
    var homingTimeRemaining: Double = 0
    var maxTurnRate: Double = 0
    var acceleration: Double = 0
    var activationDelay: Double = 0
    var minForwardSpeed: Double = 70
    var baseVelocity: Vec2 = .zero
    var splitTriggered: Bool = false
    var splitChildCount: Int = 0
    var splitSpread: Double = 0.24
    var bounceRemaining: Int = 1
}
