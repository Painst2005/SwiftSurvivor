import Foundation

struct RenderColor: Equatable, Sendable {
    var red: UInt8
    var green: UInt8
    var blue: UInt8
    var alpha: UInt8

    init(_ red: UInt8, _ green: UInt8, _ blue: UInt8, _ alpha: UInt8 = 255) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }
}

struct RenderRect: Equatable, Sendable {
    var x: Float
    var y: Float
    var width: Float
    var height: Float
}

protocol GameTexture: AnyObject {}

/// Optional resource lookup capability shared by render backends and UI
/// transform proxies. Presentation code asks for a logical texture name
/// without depending on SDL-specific texture types.
protocol GameTextureProvider: AnyObject {
    func gameTexture(named name: String) -> GameTexture?
}

/// Gameplay-facing rendering contract. No SDL or Win32 types cross this boundary.
protocol GameRenderer: AnyObject {
    var drawableSize: (width: Int, height: Int) { get }
    func beginFrame(clear color: RenderColor)
    func fillRect(_ rect: RenderRect, color: RenderColor)
    func fillCircle(center: (x: Float, y: Float), radius: Float, color: RenderColor)
    func line(from start: (x: Float, y: Float), to end: (x: Float, y: Float), color: RenderColor)
    func drawSprite(_ texture: GameTexture, in destination: RenderRect, alpha: UInt8)
    func drawText(_ text: String, at position: (x: Float, y: Float), color: RenderColor)
    /// Optional typography scaling hook used by the UI accessibility scale.
    /// Backends that only expose a fixed-size font can keep the default.
    func drawTextScaled(_ text: String, at position: (x: Float, y: Float), scale: Float, color: RenderColor)
    func present()
}

extension GameRenderer {
    func drawTextScaled(_ text: String, at position: (x: Float, y: Float), scale: Float, color: RenderColor) {
        drawText(text, at: position, color: color)
    }
}
