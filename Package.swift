// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwitchFix",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "SwitchFixApp",
            dependencies: ["Core", "LanguageModel", "UI", "Utils"],
            path: "Sources/SwitchFixApp"
        ),
        .target(
            name: "Core",
            dependencies: ["LanguageModel", "Utils"],
            path: "Sources/Core"
        ),
        .target(
            name: "UI",
            dependencies: ["Core", "Utils"],
            path: "Sources/UI"
        ),
        .target(
            name: "Utils",
            dependencies: [],
            path: "Sources/Utils"
        ),
        .target(
            name: "LanguageModel",
            dependencies: [],
            path: "Sources/LanguageModel",
            resources: [
                .copy("Resources/en.sfng"),
                .copy("Resources/ru.sfng"),
                .copy("Resources/uk.sfng")
            ]
        ),
        .executableTarget(
            name: "ModelTrainer",
            dependencies: ["LanguageModel"],
            path: "Sources/ModelTrainer"
        ),
        .executableTarget(
            name: "TestRunner",
            dependencies: ["Core", "LanguageModel", "Utils"],
            path: "Sources/TestRunner"
        ),
        .executableTarget(
            name: "InputPipelineTestRunner",
            dependencies: ["Core", "LanguageModel", "Utils"],
            path: "Sources/InputPipelineTestRunner"
        ),
    ]
)
