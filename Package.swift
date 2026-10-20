// swift-tools-version: 5.9
import Foundation
import PackageDescription

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let excludedPaths = [
    "artifacts", "analysis", "build", "dist", "tools", "docs", "NOTICE.md",
    "README.md", "f108-time", "同步键盘时间.command"
].filter { FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path) }

let package = Package(
    name: "F108Pro",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "F108Pro", targets: ["F108Pro"])],
    targets: [
        .executableTarget(
            name: "F108Pro",
            path: ".",
            exclude: excludedPaths,
            sources: ["f108-time.swift", "Sources"],
            swiftSettings: [.define("F108_APP")]
        )
    ]
)
