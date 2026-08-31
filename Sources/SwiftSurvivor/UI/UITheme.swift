import Foundation

/// Design tokens shared by every SDL screen.  The UI renderer consumes these
/// values through GameRenderer, so changing the backend does not require
/// rewriting page or HUD code.
enum UITheme {
    enum Color {
        // A restrained navy palette keeps the interface legible without the
        // harsh "neon dashboard" look. Bright accents are reserved for state
        // changes, rewards and combat warnings.
        static let background = RenderColor(7, 12, 24)
        static let backgroundRaised = RenderColor(12, 23, 40)
        static let panel = RenderColor(14, 27, 47, 224)
        static let panelRaised = RenderColor(22, 40, 61, 236)
        static let panelSoft = RenderColor(18, 34, 54, 210)
        static let panelHover = RenderColor(30, 55, 77, 244)
        static let panelSelected = RenderColor(36, 73, 96, 248)
        static let border = RenderColor(69, 96, 116, 138)
        static let borderHighlight = RenderColor(105, 158, 172, 176)
        static let primary = RenderColor(116, 196, 207)
        static let primaryDeep = RenderColor(42, 103, 116)
        static let secondary = RenderColor(173, 190, 204)
        static let text = RenderColor(232, 239, 243)
        static let muted = RenderColor(143, 162, 178)
        static let danger = RenderColor(231, 100, 119)
        static let warning = RenderColor(239, 202, 126)
        static let success = RenderColor(127, 210, 174)
        static let shield = RenderColor(131, 211, 195)
        static let energy = RenderColor(116, 213, 226)
        static let boss = RenderColor(208, 130, 205)
    }

    enum Spacing {
        static let xs: Float = 4
        static let small: Float = 8
        static let normal: Float = 16
        static let section: Float = 24
        static let large: Float = 32
        static let page: Float = 48
    }

    enum Typography {
        // The bitmap atlas is authored around a 20 px glyph. These restrained
        // ratios create hierarchy without blurring it through extreme scaling.
        static let display: Float = 1.30
        static let pageTitle: Float = 1.18
        static let sectionTitle: Float = 1.02
        static let body: Float = 0.90
        static let label: Float = 0.78
        static let caption: Float = 0.72
        static let number: Float = 1.12
        static let compactNumber: Float = 0.92

        static let bodyLineHeight: Float = 19
        static let compactLineHeight: Float = 16
    }

    enum Animation {
        static let hover = 0.14
        static let pressed = 0.08
        static let page = 0.24
        static let popup = 0.18
    }

    static func rarity(_ value: Int) -> RenderColor {
        switch value {
        case 0: return RenderColor(187, 199, 219)
        case 1: return RenderColor(97, 209, 255)
        case 2: return RenderColor(204, 143, 255)
        case 3: return RenderColor(255, 211, 105)
        default: return RenderColor(255, 110, 136)
        }
    }
}

enum UIControlState {
    case normal
    case hover
    case pressed
    case disabled
    case selected
}

/// Shared pointer state for the presentation layer.  SDLInputManager updates
/// Game.mousePosition; the SDL renderer copies it here once per frame.  This
/// keeps widgets independent from SDL events and gives every screen identical
/// hover behavior.
enum UIInteraction {
    nonisolated(unsafe) static var pointer = Vec2.zero
    nonisolated(unsafe) static var time = 0.0
    nonisolated(unsafe) static var primaryHeld = false
    nonisolated(unsafe) static var screenID = ""
    nonisolated(unsafe) static var transitionStart = 0.0

    static func state(for rect: UIRect, selected: Bool, enabled: Bool = true) -> UIControlState {
        guard enabled else { return .disabled }
        if selected { return .selected }
        if primaryHeld, rect.contains(pointer) { return .pressed }
        return rect.contains(pointer) ? .hover : .normal
    }
}

enum UIAnimationSystem {
    static func easeOutCubic(_ value: Double) -> Double {
        let t = min(1, max(0, value))
        return 1 - pow(1 - t, 3)
    }

    static func pulse(time: Double, speed: Double = 4.0, amount: Double = 0.5) -> Double {
        1 + sin(time * speed) * amount
    }
}

struct UILabel {
    var value: String
    var color: RenderColor = UITheme.Color.text
    var scale: Float = UITheme.Typography.body
    var alignment: UITextAlignment = .leading
    var maxWidth: Float? = nil
}

enum UITextAlignment { case leading, center, trailing }

enum UITextRole {
    case display, pageTitle, sectionTitle, body, secondary, label, caption, number, warning, danger

    var scale: Float {
        switch self {
        case .display: return UITheme.Typography.display
        case .pageTitle: return UITheme.Typography.pageTitle
        case .sectionTitle: return UITheme.Typography.sectionTitle
        case .number: return UITheme.Typography.number
        case .body, .secondary, .warning, .danger: return UITheme.Typography.body
        case .label: return UITheme.Typography.label
        case .caption: return UITheme.Typography.caption
        }
    }

    var defaultColor: RenderColor {
        switch self {
        case .secondary: return UITheme.Color.secondary
        case .label, .caption: return UITheme.Color.muted
        case .warning: return UITheme.Color.warning
        case .danger: return UITheme.Color.danger
        default: return UITheme.Color.text
        }
    }
}

struct UIPanel {
    var rect: UIRect
    var raised = false
}

struct UIButton {
    var rect: UIRect
    var title: String
    var selected = false
    var enabled = true
}

struct UIProgressBar {
    var rect: UIRect
    var value: Double
    var fill: RenderColor
    var back: RenderColor = RenderColor(20, 35, 57)
}

/// Lightweight presentation proxy for the UI layer.  Gameplay keeps using
/// the native logical canvas, while menus/HUD can opt into a comfortable
/// readability scale without teaching SDL or gameplay about UI transforms.
/// The transform is deliberately centered so the crosshair and battle field
/// never move when a player changes the UI setting.
final class UITransformRenderer: GameRenderer {
    private let base: GameRenderer
    private let geometryScale: Float
    private let textScale: Float
    private let offsetX: Float
    private let offsetY: Float

    init(base: GameRenderer, canvasWidth: Int, canvasHeight: Int, scalePercent: Int) {
        self.base = base
        let requested = Float(min(1.2, max(0.8, Double(scalePercent) / 100.0)))
        // Enlarging the entire 1280x720 page would crop its outer panels.
        // Keep geometry inside the authored canvas and let typography carry
        // the high-scale accessibility gain; compact scales shrink both.
        self.geometryScale = min(1, requested)
        self.textScale = requested
        self.offsetX = (Float(canvasWidth) - Float(canvasWidth) * self.geometryScale) * 0.5
        self.offsetY = (Float(canvasHeight) - Float(canvasHeight) * self.geometryScale) * 0.5
    }

    var drawableSize: (width: Int, height: Int) { base.drawableSize }

    func beginFrame(clear color: RenderColor) { base.beginFrame(clear: color) }
    func present() { base.present() }

    private func point(_ x: Float, _ y: Float) -> (x: Float, y: Float) {
        (x: offsetX + x * geometryScale, y: offsetY + y * geometryScale)
    }

    private func rect(_ value: RenderRect) -> RenderRect {
        RenderRect(x: offsetX + value.x * geometryScale,
                   y: offsetY + value.y * geometryScale,
                   width: value.width * geometryScale,
                   height: value.height * geometryScale)
    }

    func fillRect(_ value: RenderRect, color: RenderColor) { base.fillRect(rect(value), color: color) }

    func fillCircle(center: (x: Float, y: Float), radius: Float, color: RenderColor) {
        let p = point(center.x, center.y)
        base.fillCircle(center: p, radius: radius * geometryScale, color: color)
    }

    func line(from start: (x: Float, y: Float), to end: (x: Float, y: Float), color: RenderColor) {
        base.line(from: point(start.x, start.y), to: point(end.x, end.y), color: color)
    }

    func drawSprite(_ texture: GameTexture, in destination: RenderRect, alpha: UInt8) {
        base.drawSprite(texture, in: rect(destination), alpha: alpha)
    }

    func drawText(_ text: String, at position: (x: Float, y: Float), color: RenderColor) {
        let p = point(position.x, position.y)
        base.drawTextScaled(text, at: p, scale: textScale, color: color)
    }

    func drawTextScaled(_ text: String, at position: (x: Float, y: Float), scale: Float, color: RenderColor) {
        let p = point(position.x, position.y)
        base.drawTextScaled(text, at: p, scale: textScale * scale, color: color)
    }
}
