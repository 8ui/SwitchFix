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
            dependencies: ["Core", "Dictionary", "LanguageModel", "UI", "Utils"],
            path: "Sources/SwitchFixApp"
        ),
        .target(
            name: "Core",
            dependencies: ["Dictionary", "LanguageModel", "Utils"],
            path: "Sources/Core"
        ),
        .target(
            name: "Dictionary",
            dependencies: ["Utils"],
            path: "Sources/Dictionary",
            exclude: ["Resources/uk_full.txt"],
            resources: [
                .copy("Resources/en_US.txt"),
                .copy("Resources/ru_RU.txt"),
                .copy("Resources/uk_UA.txt"),
                .copy("Resources/overrides")
            ]
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
            dependencies: ["Core", "Dictionary", "LanguageModel", "Utils"],
            path: "Sources/TestRunner"
        ),
        .executableTarget(
            name: "InputPipelineTestRunner",
            dependencies: ["Core", "Utils"],
            path: "Sources/InputPipelineTestRunner"
        ),
    ]
)
