// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LiftingCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "LiftingCore", targets: ["LiftingCore"])],
    targets: [
        .target(name: "LiftingCore"),
        .testTarget(name: "LiftingCoreTests", dependencies: ["LiftingCore"],
                    resources: [.copy("Fixtures")])
    ]
)
