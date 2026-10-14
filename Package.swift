// swift-tools-version: 6.0
import Foundation
import PackageDescription

// Workaround: Swift 6.4 aus den Command Line Tools (ohne Xcode) findet das Makro-Plugin
// von swift-testing beim Build mit Swift Build sporadisch nicht („plugin for module
// 'TestingMacros' not found“). Den Plugin-Pfad explizit mitzugeben, macht die Builds stabil.
let commandLineToolsTestingPlugins = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
let testSettings: [SwiftSetting] =
    FileManager.default.fileExists(atPath: commandLineToolsTestingPlugins)
    ? [.unsafeFlags(["-plugin-path", commandLineToolsTestingPlugins])]
    : []

let package = Package(
    name: "open1602",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AnnoFormats", targets: ["AnnoFormats"]),
        .executable(name: "Open1602", targets: ["Open1602"]),
        .executable(name: "anno-tool", targets: ["anno-tool"]),
    ],
    targets: [
        // Reine Parser für die Originaldaten. Nur Swift-Standardbibliothek und Foundation,
        // damit das Modul auch auf Linux/Windows baut.
        .target(name: "AnnoFormats"),
        // Metal-Renderer: Sprite-Atlanten, Palettenshader.
        .target(name: "AnnoRender", dependencies: ["AnnoFormats"]),
        // macOS-App (AppKit).
        .executableTarget(name: "Open1602", dependencies: ["AnnoFormats", "AnnoRender"]),
        .executableTarget(name: "anno-tool", dependencies: ["AnnoFormats"]),
        .testTarget(name: "AnnoFormatsTests", dependencies: ["AnnoFormats"], swiftSettings: testSettings),
        .testTarget(name: "AnnoRenderTests", dependencies: ["AnnoRender", "AnnoFormats"], swiftSettings: testSettings),
    ]
)
