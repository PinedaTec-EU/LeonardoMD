// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LeonardoMD",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.executable(name: "LeonardoMD", targets: ["LeonardoApp"]), .library(name: "LeonardoDesktopSync", targets: ["LeonardoDesktopSync"]), .library(name: "LeonardoSyncTransport", targets: ["LeonardoSyncTransport"]), .library(name: "LeonardoSync", targets: ["LeonardoSync"]), .library(name: "LeonardoCore", targets: ["LeonardoCore"]), .library(name: "LeonardoRender", targets: ["LeonardoRender"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")],
    targets: [
        .target(name: "LeonardoCore"),
        .target(name: "LeonardoSync"),
        .target(name: "LeonardoSyncTransport", dependencies: ["LeonardoSync"]),
        .target(name: "LeonardoDesktopSync", dependencies: ["LeonardoSync", "LeonardoSyncTransport"]),
        .testTarget(name: "LeonardoDesktopSyncTests", dependencies: ["LeonardoDesktopSync"]),
        .testTarget(name: "LeonardoSyncTransportTests", dependencies: ["LeonardoSyncTransport"]),
        .testTarget(name: "LeonardoSyncTests", dependencies: ["LeonardoSync"]),
        .target(name: "LeonardoRender", dependencies: ["LeonardoCore"], resources: [.process("Resources")]),
        .executableTarget(name: "LeonardoApp", dependencies: ["LeonardoCore", "LeonardoRender", "LeonardoDesktopSync", .product(name: "Sparkle", package: "Sparkle")], resources: [.process("Resources")], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]) ]),
        .testTarget(name: "LeonardoIntegrationTests", dependencies: ["LeonardoRender"]),
        .testTarget(name: "LeonardoAppTests", dependencies: ["LeonardoApp"]),
        .testTarget(name: "LeonardoCoreTests", dependencies: ["LeonardoCore"]),
        .testTarget(name: "LeonardoRenderTests", dependencies: ["LeonardoRender"])
    ]
)
