// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SoupDesk",
    platforms: [.macOS(.v14)],
    targets: [
        // Soup Engine sources copied unmodified from the 7D port, plus soup_bridge.c.
        .target(name: "SoupEngine",
                cSettings: [.define("SE_HOSTED"), .unsafeFlags(["-O2", "-w"])]),
        .target(name: "SoupKit", dependencies: ["SoupEngine"]),
        .executableTarget(name: "SoupDesk", dependencies: ["SoupKit"]),
        .executableTarget(name: "soupcheck", dependencies: ["SoupKit"]),
    ]
)
