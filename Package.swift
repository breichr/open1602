// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "open1602",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AnnoFormats", targets: ["AnnoFormats"]),
        .executable(name: "anno-tool", targets: ["anno-tool"]),
    ],
    targets: [
        // Reine Parser für die Originaldaten. Nur Swift-Standardbibliothek und Foundation,
        // damit das Modul auch auf Linux/Windows baut.
        .target(name: "AnnoFormats"),
        .executableTarget(name: "anno-tool", dependencies: ["AnnoFormats"]),
        .testTarget(name: "AnnoFormatsTests", dependencies: ["AnnoFormats"]),
    ]
)
