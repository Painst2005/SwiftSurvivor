import Foundation

/// Design tokens shared by every SDL screen.  The UI renderer consumes these
/// values through GameRenderer, so changing the backend does not require
/// rewriting page or HUD code.
enum UITheme {
    enum Color {
        static let background = RenderColor(6, 10, 25)
        static let backgroundRaised = RenderColor(10, 20, 42)
        static let panel = RenderColor(12, 24, 51, 242)
        static let panelRaised = RenderColor(18, 39, 68, 248)
        static let panelHover = RenderColor(26, 67, 101, 252)
        static let panelSelected = RenderColor(35, 109, 158, 255)
        static let border = RenderColor(45, 92, 128, 235)
        static let borderHighlight = RenderColor(84, 190, 226, 255)
        static let primary = RenderColor(99, 215, 244)
        static let secondary = RenderColor(157, 182, 211)
        static let text = RenderColor(232, 243, 252)
        static let muted = RenderColor(139, 164, 190)
        static let danger = RenderColor(239, 83, 110)
        static let warning = RenderColor(255, 207, 105)
        static let success = RenderColor(111, 226, 174)
        static let shield = RenderColor(122, 232, 204)
        static let energy = RenderColor(106, 239, 255)
        static let boss = RenderColor(226, 108, 226)
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
        static let title: Float = 1.0
        static let body: Float = 1.0
        static let caption: Float = 1.0
    }

    enum Animation {
        static let hover = 0.10
        static let pressed = 0.06
        static let page = 0.20
        static let popup = 0.16
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
