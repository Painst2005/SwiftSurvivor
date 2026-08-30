import Foundation
import CSwiftSDL3

/// Small, self-contained bitmap font used by the SDL presentation path.
///
/// SDL_RenderDebugText is deliberately a diagnostics helper and is not
/// guaranteed to be visible on every renderer backend.  The game therefore
/// ships a pre-rasterized atlas (including the Chinese characters used by the
/// UI) and renders glyphs as ordinary SDL textures.  This keeps gameplay
/// independent of a platform font API and makes the portable build reliable.
final class SDLBitmapFont {
    private let context: OpaquePointer
    private let texture: SDLTexture
    private let cellSize: Float
    private let columns: Int
    private let glyphIndex: [Character: Int]

    private init(context: OpaquePointer, texture: SDLTexture, cellSize: Int, columns: Int, glyphIndex: [Character: Int]) {
        self.context = context
        self.texture = texture
        self.cellSize = Float(cellSize)
        self.columns = columns
        self.glyphIndex = glyphIndex
    }

    static func load(platform: SDLPlatform) -> SDLBitmapFont? {
        guard let path = assetURL()?.path else { return nil }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)), data.count >= 24 else {
            return nil
        }
        guard String(decoding: data.prefix(4), as: UTF8.self) == "SSFT" else { return nil }

        func uint32(_ offset: Int) -> Int {
            Int(data[offset]) | (Int(data[offset + 1]) << 8) |
            (Int(data[offset + 2]) << 16) | (Int(data[offset + 3]) << 24)
        }
        let width = uint32(4)
        let height = uint32(8)
        let cellSize = uint32(12)
        let columns = uint32(16)
        let mappingLength = uint32(20)
        let mappingStart = 24
        let pixelStart = mappingStart + mappingLength
        guard width > 0, height > 0, cellSize > 0, columns > 0,
              mappingLength > 0, pixelStart <= data.count,
              data.count - pixelStart >= width * height * 4 else { return nil }

        let mappingData = data[mappingStart..<pixelStart]
        let mapping = String(decoding: mappingData, as: UTF8.self)
        let pixels = Array(data[pixelStart..<(pixelStart + width * height * 4)])
        guard let texture = SDLTexture(platform: platform, width: width, height: height, rgbaPixels: pixels) else {
            return nil
        }
        _ = swift_sdl3_texture_set_nearest(texture.handle)
        var index: [Character: Int] = [:]
        for (offset, character) in mapping.enumerated() {
            index[character] = offset
        }
        return SDLBitmapFont(context: platform.context, texture: texture, cellSize: cellSize, columns: columns, glyphIndex: index)
    }

    func draw(_ value: String, at position: (x: Float, y: Float), scale: Float = 1, color: RenderColor) {
        var cursorX = position.x
        // Keep the atlas close to its native 20 px glyph size.  Rendering a
        // 24 px cell down to an 11 px destination makes SDL's linear sampler
        // soften the strokes until they look like missing text.
        let safeScale = min(1.35, max(0.65, scale))
        let height: Float = 20 * safeScale
        for character in value {
            if character == " " {
                cursorX += 8 * safeScale
                continue
            }
            guard let index = glyphIndex[character] else {
                cursorX += 11 * safeScale
                continue
            }
            let sourceX = Float(index % columns) * cellSize
            let sourceY = Float(index / columns) * cellSize
            let wide = character.unicodeScalars.first.map { $0.value > 0x7f } ?? false
            let advance: Float = (wide ? 20 : 14) * safeScale
            _ = swift_sdl3_draw_texture_region(
                context, texture.handle,
                sourceX, sourceY, cellSize, cellSize,
                cursorX, position.y, 20 * safeScale, height,
                color.red, color.green, color.blue, color.alpha
            )
            cursorX += advance
        }
    }

    private static func assetURL() -> URL? {
        var candidates: [URL] = []
        let fileManager = FileManager.default
        candidates.append(URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent("Resources/Fonts/ui_font.rgba"))
        if let executable = CommandLine.arguments.first {
            candidates.append(URL(fileURLWithPath: executable).deletingLastPathComponent()
                .appendingPathComponent("Resources/Fonts/ui_font.rgba"))
        }
        return candidates.first(where: { fileManager.fileExists(atPath: $0.path) })
    }

}
