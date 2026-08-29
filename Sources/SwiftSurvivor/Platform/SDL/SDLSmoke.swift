import Foundation
import CSwiftSDL3

/// Small opt-in executable path used to validate SDL initialization and the
/// renderer contract without changing the established Win32 gameplay path.
enum SDLSmoke {
    static func run(duration: Double = 1.5) {
        do {
            let platform = try SDLPlatform(title: "SwiftSurvivor SDL3", width: 960, height: 540)
            let renderer = SDLRenderer(platform: platform)
            let input = SDLInputManager()
            let testPixels = (0..<32 * 32).flatMap { _ in [UInt8(255), UInt8(80), UInt8(120), UInt8(230)] }
            let testTexture = SDLTexture(platform: platform, width: 32, height: 32, rgbaPixels: testPixels)
            let start = Double(swift_sdl3_ticks_ns()) / 1_000_000_000
            var previous = start
            var clock = FixedStepClock()
            var running = true
            while running {
                let now = Double(swift_sdl3_ticks_ns()) / 1_000_000_000
                let delta = now - previous
                previous = now
                let events = platform.pollEvents()
                input.beginFrame(events: events)
                if input.shouldQuit || now - start >= duration { running = false }

                clock.advance(realDelta: delta) { _ in }
                renderer.beginFrame(clear: RenderColor(7, 12, 28))
                renderer.fillRect(RenderRect(x: 40, y: 40, width: 180, height: 70), color: RenderColor(30, 120, 230, 220))
                if let testTexture {
                    renderer.drawSprite(testTexture, in: RenderRect(x: 250, y: 55, width: 64, height: 64), alpha: 230)
                }
                renderer.line(from: (x: 40, y: 140), to: (x: 920, y: 140), color: RenderColor(80, 200, 255))
                renderer.drawText("SwiftSurvivor SDL3 renderer OK", at: (x: 60, y: 65), color: RenderColor(255, 255, 255))
                renderer.present()
                Thread.sleep(forTimeInterval: 1.0 / 120.0)
            }
        } catch {
            // This path is intended for build/launch diagnostics and should not
            // crash the normal game when SDL is unavailable on a developer PC.
            print("SDL smoke test failed: \(error)")
        }
    }
}
