$ErrorActionPreference = "Stop"
swift build -c release --scratch-path .build-game
swift run -c release --scratch-path .build-game
