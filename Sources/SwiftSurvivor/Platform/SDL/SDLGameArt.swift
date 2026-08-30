import Foundation

/// Loads small pre-converted RGBA art assets.  Keeping the decoder here means
/// gameplay and the renderer interface remain free of image-format details.
enum SDLGameArt {
    static func load(named name: String, platform: SDLPlatform) -> SDLTexture? {
        guard let url = assetURL(named: name),
              let data = try? Data(contentsOf: url),
              data.count >= 12,
              String(decoding: data.prefix(4), as: UTF8.self) == "SSAT" else { return nil }

        func uint32(_ offset: Int) -> Int {
            Int(data[offset]) | (Int(data[offset + 1]) << 8) |
            (Int(data[offset + 2]) << 16) | (Int(data[offset + 3]) << 24)
        }
        let width = uint32(4)
        let height = uint32(8)
        let pixelStart = 12
        guard width > 0, height > 0, data.count - pixelStart >= width * height * 4 else { return nil }
        let pixels = Array(data[pixelStart..<(pixelStart + width * height * 4)])
        return SDLTexture(platform: platform, width: width, height: height, rgbaPixels: pixels)
    }

    private static func assetURL(named name: String) -> URL? {
        let fileManager = FileManager.default
        var candidates = [URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent("Resources/Art/\(name).rgba")]
        if let executable = CommandLine.arguments.first {
            candidates.append(URL(fileURLWithPath: executable).deletingLastPathComponent()
                .appendingPathComponent("Resources/Art/\(name).rgba"))
        }
        return candidates.first(where: { fileManager.fileExists(atPath: $0.path) })
    }
}
