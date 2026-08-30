import Foundation
import CSwiftSDL3

enum SDLPlatformError: Error, CustomStringConvertible {
    case initialization(String)
    case windowCreation(String)

    var description: String {
        switch self {
        case .initialization(let message): return "SDL 初始化失败：\(message)"
        case .windowCreation(let message): return "SDL 窗口创建失败：\(message)"
        }
    }
}

struct SDLInputEvent {
    enum Kind { case quit, keyDown, keyUp, mouseMotion, mouseButtonDown, mouseButtonUp, windowResized }
    var kind: Kind
    var key: Int32 = 0
    var repeated = false
    var button: UInt8 = 0
    var x: Float = 0
    var y: Float = 0
    var width = 0
    var height = 0
}

/// Owns SDL lifetime and converts C event structs into Swift values.
final class SDLPlatform {
    private(set) var context: OpaquePointer
    private(set) var windowSize: (width: Int, height: Int)

    init(title: String, width: Int, height: Int, resizable: Bool = true) throws {
        guard swift_sdl3_startup() else {
            throw SDLPlatformError.initialization(Self.lastError())
        }
        guard let context = title.withCString({ swift_sdl3_create($0, Int32(width), Int32(height), resizable) }) else {
            swift_sdl3_shutdown()
            throw SDLPlatformError.windowCreation(Self.lastError())
        }
        self.context = context
        self.windowSize = (width, height)
    }

    deinit {
        swift_sdl3_destroy(context)
        swift_sdl3_shutdown()
    }

    func pollEvents() -> [SDLInputEvent] {
        var result: [SDLInputEvent] = []
        var raw = SwiftSDL3Event()
        while swift_sdl3_poll_event(&raw) {
            switch raw.kind {
            case UInt32(bitPattern: SWIFT_SDL3_EVENT_QUIT.rawValue):
                result.append(SDLInputEvent(kind: .quit))
            case UInt32(bitPattern: SWIFT_SDL3_EVENT_KEY_DOWN.rawValue):
                result.append(SDLInputEvent(kind: .keyDown, key: raw.key, repeated: raw.repeat != 0))
            case UInt32(bitPattern: SWIFT_SDL3_EVENT_KEY_UP.rawValue):
                result.append(SDLInputEvent(kind: .keyUp, key: raw.key))
            case UInt32(bitPattern: SWIFT_SDL3_EVENT_MOUSE_MOTION.rawValue):
                result.append(SDLInputEvent(kind: .mouseMotion, x: raw.x, y: raw.y))
            case UInt32(bitPattern: SWIFT_SDL3_EVENT_MOUSE_BUTTON_DOWN.rawValue):
                result.append(SDLInputEvent(kind: .mouseButtonDown, button: raw.button, x: raw.x, y: raw.y))
            case UInt32(bitPattern: SWIFT_SDL3_EVENT_MOUSE_BUTTON_UP.rawValue):
                result.append(SDLInputEvent(kind: .mouseButtonUp, button: raw.button, x: raw.x, y: raw.y))
            case UInt32(bitPattern: SWIFT_SDL3_EVENT_WINDOW_RESIZED.rawValue):
                windowSize = (Int(raw.width), Int(raw.height))
                result.append(SDLInputEvent(kind: .windowResized, width: Int(raw.width), height: Int(raw.height)))
            default:
                break
            }
        }
        return result
    }

    @discardableResult
    func setWindowSize(width: Int, height: Int) -> Bool {
        let success = swift_sdl3_set_window_size(context, Int32(width), Int32(height))
        if success { windowSize = (width, height) }
        return success
    }

    @discardableResult
    func setFullscreen(_ fullscreen: Bool) -> Bool {
        swift_sdl3_set_window_fullscreen(context, fullscreen)
    }

    func refreshWindowSize() {
        var width: Int32 = 0
        var height: Int32 = 0
        if swift_sdl3_get_window_size(context, &width, &height), width > 0, height > 0 {
            windowSize = (Int(width), Int(height))
        }
    }

    @discardableResult
    func setLogicalPresentation(width: Int, height: Int) -> Bool {
        swift_sdl3_set_logical_presentation(context, Int32(width), Int32(height))
    }

    static func lastError() -> String {
        guard let pointer = swift_sdl3_error() else { return "未知错误" }
        return String(cString: pointer)
    }
}

final class SDLRenderer: GameRenderer {
    private let platform: SDLPlatform
    private let bitmapFont: SDLBitmapFont?
    private var drawColor = RenderColor(255, 255, 255)
    private var artTextures: [String: SDLTexture] = [:]

    init(platform: SDLPlatform) {
        self.platform = platform
        self.bitmapFont = SDLBitmapFont.load(platform: platform)
    }

    var drawableSize: (width: Int, height: Int) { platform.windowSize }

    func artTexture(named name: String) -> SDLTexture? {
        if let cached = artTextures[name] { return cached }
        guard let texture = SDLGameArt.load(named: name, platform: platform) else { return nil }
        artTextures[name] = texture
        return texture
    }

    func beginFrame(clear color: RenderColor) {
        swift_sdl3_begin_frame(platform.context, color.red, color.green, color.blue, color.alpha)
        drawColor = color
    }

    func fillRect(_ rect: RenderRect, color: RenderColor) {
        setColor(color)
        _ = swift_sdl3_fill_rect(platform.context, rect.x, rect.y, rect.width, rect.height)
    }

    func fillCircle(center: (x: Float, y: Float), radius: Float, color: RenderColor) {
        setColor(color)
        _ = swift_sdl3_fill_circle(platform.context, center.x, center.y, radius)
    }

    func line(from start: (x: Float, y: Float), to end: (x: Float, y: Float), color: RenderColor) {
        setColor(color)
        _ = swift_sdl3_line(platform.context, start.x, start.y, end.x, end.y)
    }

    func drawSprite(_ texture: GameTexture, in destination: RenderRect, alpha: UInt8 = 255) {
        guard let texture = texture as? SDLTexture else { return }
        _ = swift_sdl3_draw_texture(platform.context, texture.handle,
                                    destination.x, destination.y,
                                    destination.width, destination.height, alpha)
    }

    func drawText(_ text: String, at position: (x: Float, y: Float), color: RenderColor) {
        drawTextScaled(text, at: position, scale: 1, color: color)
    }

    func drawTextScaled(_ text: String, at position: (x: Float, y: Float), scale: Float, color: RenderColor) {
        if let bitmapFont {
            bitmapFont.draw(text, at: position, scale: scale, color: color)
        } else {
            // Keep a visible diagnostic fallback if a damaged portable package
            // is missing its font asset.
            setColor(color)
            text.withCString { _ = swift_sdl3_debug_text(platform.context, position.x, position.y, $0) }
        }
    }

    func present() { swift_sdl3_present(platform.context) }

    private func setColor(_ color: RenderColor) {
        swift_sdl3_set_draw_color(platform.context, color.red, color.green, color.blue, color.alpha)
        drawColor = color
    }
}

final class SDLTexture: GameTexture {
    let handle: OpaquePointer
    let width: Int
    let height: Int

    init?(platform: SDLPlatform, width: Int, height: Int, rgbaPixels: [UInt8]) {
        guard width > 0, height > 0, rgbaPixels.count >= width * height * 4 else { return nil }
        let pitch = width * 4
        let created: OpaquePointer? = rgbaPixels.withUnsafeBytes { bytes in
            swift_sdl3_texture_create(platform.context, Int32(width), Int32(height), bytes.baseAddress, Int32(pitch))
        }
        guard let created else { return nil }
        handle = created
        self.width = width
        self.height = height
    }

    deinit { swift_sdl3_texture_destroy(handle) }

    func update(rgbaPixels: [UInt8]) -> Bool {
        guard rgbaPixels.count >= width * height * 4 else { return false }
        return rgbaPixels.withUnsafeBytes { bytes in
            swift_sdl3_texture_update(handle, bytes.baseAddress, Int32(width * 4))
        }
    }
}

enum GameAction: Hashable {
    case moveUp, moveDown, moveLeft, moveRight
    case precisionMove, specialAttack, pause, confirm, cancel
}

/// SDL events mapped to stable gameplay actions instead of raw key codes.
final class SDLInputManager {
    private(set) var mousePosition: (x: Float, y: Float) = (0, 0)
    private var heldKeys: Set<Int32> = []
    private var pressedKeys: Set<Int32> = []
    private var releasedKeys: Set<Int32> = []
    private var quitRequested = false
    private var clickPosition: (x: Float, y: Float)?
    private var primaryButtonHeld = false

    func beginFrame(events: [SDLInputEvent]) {
        pressedKeys.removeAll(keepingCapacity: true)
        releasedKeys.removeAll(keepingCapacity: true)
        clickPosition = nil
        for event in events {
            switch event.kind {
            case .quit: quitRequested = true
            case .keyDown:
                if !event.repeated { pressedKeys.insert(event.key) }
                heldKeys.insert(event.key)
            case .keyUp:
                heldKeys.remove(event.key); releasedKeys.insert(event.key)
            case .mouseMotion:
                mousePosition = (event.x, event.y)
            case .mouseButtonDown:
                if event.button == 1 { clickPosition = (event.x, event.y); primaryButtonHeld = true }
            case .mouseButtonUp:
                if event.button == 1 { primaryButtonHeld = false }
            case .windowResized:
                break
            }
        }
    }

    var shouldQuit: Bool { quitRequested }

    func isHeld(_ action: GameAction) -> Bool { mappedCodes(for: action).contains { heldKeys.contains($0) } }
    func isPressed(_ action: GameAction) -> Bool { mappedCodes(for: action).contains { pressedKeys.contains($0) } }
    func isReleased(_ action: GameAction) -> Bool { mappedCodes(for: action).contains { releasedKeys.contains($0) } }
    func isPressed(keyCode: Int32) -> Bool { pressedKeys.contains(keyCode) }
    func isPressedQ() -> Bool { pressedKeys.contains(swift_sdl3_keycode_q()) }
    func isPressedFeedbackDebug() -> Bool { pressedKeys.contains(swift_sdl3_keycode_f8()) }
    func isPressedUIDebug() -> Bool { pressedKeys.contains(swift_sdl3_keycode_f9()) }
    func isPrimaryButtonHeld() -> Bool { primaryButtonHeld }
    func consumePrimaryClick() -> (x: Float, y: Float)? {
        defer { clickPosition = nil }
        return clickPosition
    }

    private func mappedCodes(for action: GameAction) -> [Int32] {
        switch action {
        case .moveUp: return [swift_sdl3_keycode_w(), swift_sdl3_keycode_up()]
        case .moveDown: return [swift_sdl3_keycode_s(), swift_sdl3_keycode_down()]
        case .moveLeft: return [swift_sdl3_keycode_a(), swift_sdl3_keycode_left()]
        case .moveRight: return [swift_sdl3_keycode_d(), swift_sdl3_keycode_right()]
        case .precisionMove: return [swift_sdl3_keycode_shift()]
        case .specialAttack: return [swift_sdl3_keycode_space()]
        case .pause: return [swift_sdl3_keycode_escape()]
        case .confirm: return [swift_sdl3_keycode_enter(), swift_sdl3_keycode_space()]
        case .cancel: return [swift_sdl3_keycode_escape()]
        }
    }
}
