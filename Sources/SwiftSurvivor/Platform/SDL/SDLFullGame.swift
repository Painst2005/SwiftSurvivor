import Foundation
import CSwiftSDL3

nonisolated(unsafe) private var sdlQuitRequested = false

/// Full SDL presentation path. Gameplay, menus and overlays are rendered with
/// the SDL renderer directly; no legacy Windows drawing layer is involved.
enum SDLFullGame {
    static func run() {
        // Keep gameplay/UI in a stable 16:9 coordinate system. The actual
        // window is scaled into this canvas with a centered letterbox, so a
        // 1920x1080 fullscreen display never makes the fighter look tiny.
        let logicalWidth = 1280
        let logicalHeight = 720
        var windowWidth = Game.shared.profile.resolutionWidth == 1024 ? 1024 : 1280
        var windowHeight = Game.shared.profile.resolutionHeight == 768 ? 768 : 720
        do {
            sdlQuitRequested = false
            let platform = try SDLPlatform(title: "SwiftSurvivor", width: windowWidth, height: windowHeight, resizable: true)
            let renderer = SDLRenderer(platform: platform)
            _ = platform.setLogicalPresentation(width: logicalWidth, height: logicalHeight)
            let input = SDLInputManager()
            let sdlAudio = SDLAudioService()
            AudioManager.shared.setExternalMusicActive(true)
            synchronizeMusic(sdlAudio, fadeDuration: 0)
            var clock = FixedStepClock()
            var previous = Double(swift_sdl3_ticks_ns()) / 1_000_000_000
            var running = true
            var appliedResolution = (windowWidth, windowHeight)
            var appliedFullscreen = Game.shared.profile.isFullscreen
            platform.setFullscreen(appliedFullscreen)

            while running {
                let now = Double(swift_sdl3_ticks_ns()) / 1_000_000_000
                let realDelta = now - previous
                previous = now
                let events = platform.pollEvents()
                platform.refreshWindowSize()
                input.beginFrame(events: events)
                sdlAudio.musicVolume = Float(Game.shared.profile.bgmVolume) / 100
                sdlAudio.tick(delta: realDelta)
                if input.shouldQuit || sdlQuitRequested { running = false }
                let requestedWidth = Game.shared.profile.resolutionWidth == 1024 ? 1024 : 1280
                let requestedHeight = Game.shared.profile.resolutionHeight == 768 ? 768 : 720
                let requestedFullscreen = Game.shared.profile.isFullscreen
                if requestedFullscreen != appliedFullscreen {
                    appliedFullscreen = requestedFullscreen
                    platform.setFullscreen(requestedFullscreen)
                    if !requestedFullscreen {
                        _ = platform.setWindowSize(width: requestedWidth, height: requestedHeight)
                        windowWidth = requestedWidth
                        windowHeight = requestedHeight
                        appliedResolution = (windowWidth, windowHeight)
                    }
                } else if !requestedFullscreen && appliedResolution != (requestedWidth, requestedHeight) {
                    _ = platform.setWindowSize(width: requestedWidth, height: requestedHeight)
                    windowWidth = requestedWidth
                    windowHeight = requestedHeight
                    appliedResolution = (windowWidth, windowHeight)
                }
                if requestedFullscreen, platform.windowSize.width > 0, platform.windowSize.height > 0 {
                    windowWidth = platform.windowSize.width
                    windowHeight = platform.windowSize.height
                } else if !requestedFullscreen {
                    windowWidth = platform.windowSize.width
                    windowHeight = platform.windowSize.height
                }
                let viewport = SDLViewport(logicalWidth: logicalWidth, logicalHeight: logicalHeight,
                                            windowWidth: max(1, windowWidth), windowHeight: max(1, windowHeight))
                handleInput(input, viewport: viewport)
                let logicalMouse = viewport.logicalPoint(x: input.mousePosition.x, y: input.mousePosition.y)
                Game.shared.updateMousePosition(Vec2(x: Double(logicalMouse.x), y: Double(logicalMouse.y)))
                Game.shared.mousePrimaryDown = input.isPrimaryButtonHeld()
                clock.advance(realDelta: realDelta) { delta in
                    Game.shared.update(delta: delta, width: Double(logicalWidth), height: Double(logicalHeight))
                }
                synchronizeMusic(sdlAudio)

                // SDL is the only presentation path. Gameplay is drawn
                // directly with SDL primitives each frame.
                SDLNativeGameRenderer.draw(renderer, game: Game.shared,
                                            width: logicalWidth, height: logicalHeight)
                Thread.sleep(forTimeInterval: 1.0 / 120.0)
            }
            sdlAudio.stopMusic()
            Game.shared.persistProfile()
        } catch {
            print("SDL full presentation failed: \(error)")
        }
    }

    private static func synchronizeMusic(_ audio: SDLAudioService, fadeDuration: Double = 0.75) {
        let game = Game.shared
        let filename: String
        if game.phase == .playing || game.phase == .paused || game.phase == .upgrade {
            if game.boss != nil {
                filename = "music_boss.wav"
            } else {
                let pressure: Int
                if game.gameMode == .campaign {
                    pressure = game.selectedMission
                } else {
                    pressure = max(0, game.endlessWaveNumber - 1)
                }
                switch pressure {
                case 0...1: filename = "music_battle_intro.wav"
                case 2...3: filename = "music_battle_advance.wav"
                case 4: filename = "music_battle_assault.wav"
                case 5: filename = "music_battle_blood.wav"
                default: filename = "music_battle_laststand.wav"
                }
            }
        } else {
            filename = "music_lobby.wav"
        }
        let path = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/Audio/\(filename)").path
        audio.transitionMusic(named: path, duration: fadeDuration)
    }

    private static func handleInput(_ input: SDLInputManager, viewport: SDLViewport) {
        if let click = input.consumePrimaryClick() {
            let point = viewport.logicalPoint(x: click.x, y: click.y)
            let logicalPoint = Vec2(x: Double(point.x), y: Double(point.y))
            let uiPoint = Game.shared.uiPoint(for: logicalPoint,
                                              width: Double(viewport.logicalWidth),
                                              height: Double(viewport.logicalHeight))
            if Game.shared.phase == .paused && Game.shared.confirmation == nil && pauseButtons(width: Double(viewport.logicalWidth), height: Double(viewport.logicalHeight))[4].contains(uiPoint) {
                sdlQuitRequested = true
                return
            }
            Game.shared.handleClick(at: uiPoint, width: Double(viewport.logicalWidth), height: Double(viewport.logicalHeight))
            if Game.shared.exitRequested {
                sdlQuitRequested = true
                return
            }
        }
        if input.isPressed(keyCode: 13) {
            switch Game.shared.phase {
            case .menu, .missionSelect: Game.shared.start(width: Double(viewport.logicalWidth), height: Double(viewport.logicalHeight))
            case .gameOver: Game.shared.start(width: Double(viewport.logicalWidth), height: Double(viewport.logicalHeight))
            default: break
            }
        }
        if input.isPressed(.specialAttack), Game.shared.phase == .playing {
            Game.shared.activateThunderOverload()
        }
        if input.isPressed(.pause) {
            if Game.shared.confirmation != nil {
                Game.shared.resolveConfirmation(confirmed: false)
            } else {
                switch Game.shared.phase {
                case .playing, .paused: Game.shared.togglePause()
                case .gameOver: Game.shared.phase = .menu
                case .settings: Game.shared.phase = Game.shared.phaseBeforeSettings
                case .controls: Game.shared.phase = Game.shared.phaseBeforeControls
                case .saveSlots: Game.shared.phase = Game.shared.phaseBeforeSaveSlots
                case .missionSelect, .hangar, .archive: Game.shared.phase = .menu
                default: break
                }
            }
        }
        if input.isPressedQ(), Game.shared.phase == .playing { Game.shared.cycleWeapon() }
        if input.isPressedDash(), Game.shared.phase == .playing {
            Game.shared.tryDash(width: Double(viewport.logicalWidth), height: Double(viewport.logicalHeight))
        }
        if input.isPressedBossDebug() {
            Game.shared.debugBossControl(width: Double(viewport.logicalWidth), height: Double(viewport.logicalHeight))
        }
        if input.isPressedFeedbackDebug() { Game.shared.debugFeedbackTest() }
        if input.isPressedUIDebug() { Game.shared.uiDebugOverlay.toggle() }
        if Game.shared.upgradeSelectionActive || Game.shared.phase == .upgrade {
            if input.isPressed(keyCode: 49) { Game.shared.chooseUpgrade(0) }
            if input.isPressed(keyCode: 50) { Game.shared.chooseUpgrade(1) }
            if input.isPressed(keyCode: 51) { Game.shared.chooseUpgrade(2) }
        }
        injectGameInput(input)
    }

    private static func injectGameInput(_ input: SDLInputManager) {
        var keys: Set<Int32> = []
        if input.isHeld(.moveLeft) { keys.insert(0x41) }
        if input.isHeld(.moveRight) { keys.insert(0x44) }
        if input.isHeld(.moveUp) { keys.insert(0x57) }
        if input.isHeld(.moveDown) { keys.insert(0x53) }
        if input.isHeld(.precisionMove) { keys.insert(0x10) }
        setInjectedKeyboardState(keys)
    }
}

private struct SDLViewport {
    let logicalWidth: Int
    let logicalHeight: Int
    let windowWidth: Int
    let windowHeight: Int

    var scale: Float {
        min(Float(windowWidth) / Float(logicalWidth), Float(windowHeight) / Float(logicalHeight))
    }

    var destination: RenderRect {
        let width = Float(logicalWidth) * scale
        let height = Float(logicalHeight) * scale
        return RenderRect(x: (Float(windowWidth) - width) * 0.5,
                          y: (Float(windowHeight) - height) * 0.5,
                          width: width, height: height)
    }

    func logicalPoint(x: Float, y: Float) -> (x: Float, y: Float) {
        let target = destination
        return ((x - target.x) / max(0.001, scale), (y - target.y) / max(0.001, scale))
    }
}
