// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "F108Pro",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "F108Pro", targets: ["F108Pro"])],
    targets: [
        .executableTarget(
            name: "F108Pro",
            path: ".",
            exclude: ["artifacts", "analysis", "build", "dist", "tools", "docs", "NOTICE.md", "README.md", "f108-time", "同步键盘时间.command"],
            sources: ["f108-time.swift", "Sources"],
            swiftSettings: [.define("F108_APP")]
        )
    ]
)
