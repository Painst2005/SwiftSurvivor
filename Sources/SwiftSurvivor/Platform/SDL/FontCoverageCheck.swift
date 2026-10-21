import Foundation

/// 字体图集覆盖自检：`SwiftSurvivor --font-coverage`。
///
/// 校验随包发布的 Resources/Fonts/ui_font.rgba 是否覆盖界面可能显示的每一个字符。
/// 字符集口径必须与 Tools/generate_ui_font.py 的 ui_characters() 保持一致：
/// Sources 下的 .swift 文案，加上 Resources/Data 下的配置表（装备 / 材料名）。
///
/// 只扫源码会漏掉已外置到配置表里的汉字——那正是图集漂移、界面上出现
/// 缺字与串位的历史原因。运行时遇到图集没有的字符什么都不画，
/// 所以必须在打包前把缺失项拦下来。
enum FontCoverageCheck {
    /// 与生成脚本一致：为后续改文案预留常用中文标点。
    private static let punctuation = "，。！？：；、“”‘’（）【】《》—…·×→"
    private static let configSuffixes: Set<String> = ["json", "csv"]

    nonisolated(unsafe) private static var passed = 0
    nonisolated(unsafe) private static var failed = 0

    static func run() {
        print("===== FONT COVERAGE CHECK · 字体图集覆盖 =====")

        guard let url = SDLBitmapFont.assetURL(), let data = try? Data(contentsOf: url) else {
            fail("字体图集可读取", "未找到 Resources/Fonts/ui_font.rgba")
            finish()
            return
        }
        pass("字体图集可读取", "\(url.lastPathComponent) \(data.count) 字节")

        guard let atlas = Atlas(data: data) else {
            fail("字体图集可解析", "SSFT 头或映射段损坏")
            finish()
            return
        }
        pass("字体图集可解析", "\(atlas.width)×\(atlas.height)，\(atlas.glyphs.count) 字形")

        // 映射按码点逐条编号。若某一条与相邻码点合成同一个字素簇，
        // 运行时的下标会整体偏移、所有字都会画错，这里先拦住。
        let scalarCount = atlas.mapping.unicodeScalars.count
        if scalarCount == atlas.glyphs.count {
            pass("映射下标与码点一一对应", "\(scalarCount) 条")
        } else {
            fail("映射下标与码点一一对应", "码点 \(scalarCount) 个，但字素簇 \(atlas.glyphs.count) 个")
        }

        var scans: [(URL, Set<String>)] = []
        if let sources = resolveDirectory("Sources") { scans.append((sources, ["swift"])) }
        if let config = resolveDirectory("Resources/Data") { scans.append((config, configSuffixes)) }
        guard !scans.isEmpty else {
            fail("文案来源可扫描", "既没有 Sources 也没有 Resources/Data")
            finish()
            return
        }
        pass("文案来源可扫描", scans.map { $0.0.lastPathComponent }.joined(separator: "、"))

        let required = requiredCharacters(scans)
        let missing = required.subtracting(atlas.glyphs)
        if missing.isEmpty {
            pass("图集覆盖全部界面字符", "需要 \(required.count) 个，全部命中")
        } else {
            fail("图集覆盖全部界面字符", "缺 \(missing.count) 个：\(describe(missing))")
        }
        finish()
    }

    // MARK: - 输出助手

    private static func pass(_ item: String, _ detail: String = "") {
        passed += 1
        print("[PASS] \(item)" + (detail.isEmpty ? "" : " — \(detail)"))
    }

    private static func fail(_ item: String, _ detail: String = "") {
        failed += 1
        print("[FAIL] \(item)" + (detail.isEmpty ? "" : " — \(detail)"))
    }

    private static func finish() {
        print("===== SUMMARY: \(passed) PASS / \(failed) FAIL =====")
        exit(failed == 0 ? 0 : 1)
    }

    // MARK: - 字符集

    /// 与生成脚本同口径：ASCII 可见字符 + 标点白名单 + 文案与配置表里的全部非 ASCII 字符。
    private static func requiredCharacters(_ scans: [(URL, Set<String>)]) -> Set<Character> {
        var result = Set<Character>()
        for value in 33...126 {
            if let scalar = UnicodeScalar(value) { result.insert(Character(scalar)) }
        }
        result.formUnion(punctuation)
        for (root, suffixes) in scans {
            for file in files(under: root, suffixes: suffixes) {
                guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
                for scalar in text.unicodeScalars where scalar.value > 127 && !scalar.properties.isWhitespace {
                    result.insert(Character(scalar))
                }
            }
        }
        return result
    }

    private static func files(under root: URL, suffixes: Set<String>) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        return enumerator.compactMap { $0 as? URL }
            .filter { suffixes.contains($0.pathExtension.lowercased()) }
    }

    /// 先找当前工作目录，再找可执行文件同级目录（与图集定位规则一致）。
    private static func resolveDirectory(_ relative: String) -> URL? {
        let fileManager = FileManager.default
        var candidates = [URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent(relative)]
        if let executable = CommandLine.arguments.first {
            candidates.append(URL(fileURLWithPath: executable).deletingLastPathComponent()
                .appendingPathComponent(relative))
        }
        return candidates.first { fileManager.fileExists(atPath: $0.path) }
    }

    private static func describe(_ characters: Set<Character>) -> String {
        characters
            .sorted { ($0.unicodeScalars.first?.value ?? 0) < ($1.unicodeScalars.first?.value ?? 0) }
            .map(String.init)
            .joined(separator: " ")
    }

    // MARK: - 资产解析

    private struct Atlas {
        let width: Int
        let height: Int
        let mapping: String
        let glyphs: Set<Character>

        init?(data: Data) {
            guard data.count >= 24,
                  String(decoding: data.prefix(4), as: UTF8.self) == "SSFT" else { return nil }
            func uint32(_ offset: Int) -> Int {
                Int(data[offset]) | (Int(data[offset + 1]) << 8) |
                (Int(data[offset + 2]) << 16) | (Int(data[offset + 3]) << 24)
            }
            let width = uint32(4)
            let height = uint32(8)
            let mappingLength = uint32(20)
            let mappingStart = 24
            let pixelStart = mappingStart + mappingLength
            guard width > 0, height > 0, mappingLength > 0, pixelStart <= data.count else { return nil }
            self.width = width
            self.height = height
            self.mapping = String(decoding: data[mappingStart..<pixelStart], as: UTF8.self)
            self.glyphs = Set(self.mapping)
        }
    }
}
