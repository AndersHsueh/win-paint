// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WinPaint",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "WinPaint", targets: ["WinPaint"])
    ],
    targets: [
        .executableTarget(
            name: "WinPaint",
            path: "src"
        ),
        // 测试直接依赖可执行目标(SwiftPM 在 macOS 上支持,自动加 -parse-as-library)
        .testTarget(
            name: "WinPaintTests",
            dependencies: ["WinPaint"],
            path: "Tests/WinPaintTests"
        )
    ]
)
