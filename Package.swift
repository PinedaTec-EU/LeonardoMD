// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LeonardoMD",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LeonardoMD", targets: ["LeonardoApp"]), .library(name: "LeonardoCore", targets: ["LeonardoCore"]), .library(name: "LeonardoRender", targets: ["LeonardoRender"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")],
    targets: [
        .target(name: "LeonardoCore"),
        .target(name: "LeonardoRender", dependencies: ["LeonardoCore"], resources: [.process("Resources")]),
        .executableTarget(name: "LeonardoApp", dependencies: ["LeonardoCore", "LeonardoRender", .product(name: "Sparkle", package: "Sparkle")], resources: [.process("Resources")], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]) ]),
        .testTarget(name: "LeonardoIntegrationTests", dependencies: ["LeonardoRender"]),
        .testTarget(name: "LeonardoAppTests", dependencies: ["LeonardoApp"]),
        .testTarget(name: "LeonardoCoreTests", dependencies: ["LeonardoCore"]),
        .testTarget(name: "LeonardoRenderTests", dependencies: ["LeonardoRender"])
    ]
)
