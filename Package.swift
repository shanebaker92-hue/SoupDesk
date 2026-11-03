// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SoupDesk",
    platforms: [.macOS(.v12)],
    targets: [
        // Soup Engine sources copied from the 7D port, plus soup_bridge.c. One local
        // change: look.c's grain_row interpolates its cells instead of flat blocks.
        .target(name: "SoupEngine",
                cSettings: [.define("SE_HOSTED"), .unsafeFlags(["-O2", "-w"])]),
        .target(name: "SoupKit", dependencies: ["SoupEngine"]),
        .executableTarget(name: "SoupDesk", dependencies: ["SoupKit"]),
        .executableTarget(name: "soupcheck", dependencies: ["SoupKit"]),
    ]
)
