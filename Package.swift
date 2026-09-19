// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Recordi", platforms: [.macOS(.v13)], products: [.executable(name: "Recordi", targets: ["Recordi"])], targets: [
    .target(name: "RecordiCore", path: "app/Core"),
    .executableTarget(name: "Recordi", dependencies: ["RecordiCore"], path: "app/Recordi"),
    .executableTarget(name: "RecordiTests", dependencies: ["RecordiCore"], path: "tests", exclude: ["fixtures"])
])
