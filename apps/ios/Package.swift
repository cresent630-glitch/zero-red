// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ZeroRedCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "ZeroRedCore", targets: ["ZeroRedCore"])],
    targets: [
        .target(name: "ZeroRedCore", path: "ZeroRed", exclude: ["BrowserEngine.swift", "BrowserSession.swift", "BrowserView.swift", "DownloadManager.swift", "Info.plist", "LibraryStore.swift", "LibraryView.swift", "LiquidGlass.swift", "NativePlayer.swift", "PageScripts.swift", "ReaderView.swift", "ReadingLibrary.swift", "SettingsView.swift", "StreamingDownloads.swift", "ZeroRedApp.swift"], sources: ["BrowserCore.swift", "FeaturesCore.swift"]),
        .testTarget(name: "ZeroRedCoreTests", dependencies: ["ZeroRedCore"])
    ],
    swiftLanguageModes: [.v5]
)
