// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LeonardoMD",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "LeonardoGit", targets: ["LeonardoGit"]), .executable(name: "LeonardoMD", targets: ["LeonardoApp"]), .library(name: "LeonardoDesktopSync", targets: ["LeonardoDesktopSync"]), .library(name: "LeonardoSyncTransport", targets: ["LeonardoSyncTransport"]), .library(name: "LeonardoSync", targets: ["LeonardoSync"]), .library(name: "LeonardoCore", targets: ["LeonardoCore"]), .library(name: "LeonardoRender", targets: ["LeonardoRender"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6"),
        // SwiftNIO SSH supplies the SSHv2 protocol and authentication building
        // blocks.  Keep the versions exact so the host-key/authentication
        // surface cannot drift independently of the transport implementation.
        .package(url: "https://github.com/apple/swift-nio-ssh.git", exact: "0.15.0"),
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", exact: "1.28.0"),
        .package(url: "https://github.com/apple/swift-nio.git", exact: "2.104.0"),
        // NIOSSH is built against Swift Crypto (rather than CryptoKit).  Keep
        // the same exact resolved package visible to LeonardoGit so its key
        // material uses the nominal types expected by NIOSSH.
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "4.5.2")
    ],
    targets: [
        .target(name: "LeonardoCore"),
        .target(name: "CLeonardoZlib", linkerSettings: [.linkedLibrary("z")]),
        .target(name: "LeonardoGit", dependencies: [
            "CLeonardoZlib", "LeonardoSync",
            .product(name: "NIOSSH", package: "swift-nio-ssh"),
            .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
            .product(name: "Crypto", package: "swift-crypto")
        ]),
        .testTarget(name: "LeonardoGitTests", dependencies: [
            "LeonardoGit",
            .product(name: "NIOCore", package: "swift-nio"),
            .product(name: "NIOPosix", package: "swift-nio"),
            .product(name: "NIOSSH", package: "swift-nio-ssh"),
            .product(name: "Crypto", package: "swift-crypto")
        ]),
        .target(name: "LeonardoSync"),
        .target(name: "LeonardoSyncTransport", dependencies: ["LeonardoSync"]),
        .target(name: "LeonardoDesktopSync", dependencies: ["LeonardoSync", "LeonardoSyncTransport"]),
        .testTarget(name: "LeonardoDesktopSyncTests", dependencies: ["LeonardoDesktopSync"]),
        .testTarget(name: "LeonardoSyncTransportTests", dependencies: ["LeonardoSyncTransport"]),
        .testTarget(name: "LeonardoSyncTests", dependencies: ["LeonardoSync"]),
        .target(name: "LeonardoRender", dependencies: ["LeonardoCore"], resources: [.process("Resources")]),
        .executableTarget(name: "LeonardoApp", dependencies: ["LeonardoCore", "LeonardoRender", "LeonardoDesktopSync", "LeonardoGit", .product(name: "Sparkle", package: "Sparkle")], resources: [.process("Resources")], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]) ]),
        .testTarget(name: "LeonardoIntegrationTests", dependencies: ["LeonardoRender"]),
        .testTarget(name: "LeonardoAppTests", dependencies: ["LeonardoApp"]),
        .testTarget(name: "LeonardoCoreTests", dependencies: ["LeonardoCore"]),
        .testTarget(name: "LeonardoRenderTests", dependencies: ["LeonardoRender"])
    ]
)
