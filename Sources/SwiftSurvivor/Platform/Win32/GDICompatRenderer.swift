import Foundation
import WinSDK

/// Compatibility adapter for the mature Win32 presentation path. It lets
/// migrated systems depend on GameRenderer while the existing full Chinese UI
/// continues to use its proven GDI text and back-buffer implementation.
final class GDICompatRenderer: GameRenderer {
    private let hdc: HDC?
    private(set) var drawableSize: (width: Int, height: Int)

    init(hdc: HDC?, width: Int, height: Int) {
        self.hdc = hdc
        self.drawableSize = (width, height)
    }

    func beginFrame(clear color: RenderColor) {
        fill(hdc, RECT(left: 0, top: 0, right: LONG(drawableSize.width), bottom: LONG(drawableSize.height)), colorRef(color))
    }

    func fillRect(_ rect: RenderRect, color: RenderColor) {
        fill(hdc, RECT(left: LONG(rect.x), top: LONG(rect.y), right: LONG(rect.x + rect.width), bottom: LONG(rect.y + rect.height)), colorRef(color))
    }

    func fillCircle(center: (x: Float, y: Float), radius: Float, color: RenderColor) {
        circle(hdc, center: Vec2(x: Double(center.x), y: Double(center.y)), radius: Double(radius), color: colorRef(color))
    }

    func line(from start: (x: Float, y: Float), to end: (x: Float, y: Float), color: RenderColor) {
        let points = [POINT(x: LONG(start.x), y: LONG(start.y)), POINT(x: LONG(end.x), y: LONG(end.y))]
        polygon(hdc, points, colorRef(color))
    }

    func drawSprite(_ texture: GameTexture, in destination: RenderRect, alpha: UInt8) {
        // Texture migration is intentionally handled by SDLRenderer first;
        // existing GDI sprites continue through their legacy drawing helpers.
    }

    func drawText(_ text: String, at position: (x: Float, y: Float), color: RenderColor) {
        SwiftSurvivor.drawText(hdc, text, RECT(left: LONG(position.x), top: LONG(position.y), right: LONG(position.x + 600), bottom: LONG(position.y + 24)), colorRef(color), 14)
    }

    func present() {}

    private func colorRef(_ color: RenderColor) -> COLORREF {
        rgb(UInt32(color.red), UInt32(color.green), UInt32(color.blue))
    }
}
