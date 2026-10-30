// swift-tools-version: 5.9
// Logica pura, senza dipendenze da iOS: si compila e si testa anche su Linux.
import PackageDescription

let package = Package(
    name: "RuleEngine",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RuleEngine", targets: ["RuleEngine"])
    ],
    targets: [
        .target(name: "RuleEngine"),
        .testTarget(name: "RuleEngineTests", dependencies: ["RuleEngine"])
    ]
)
