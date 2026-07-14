// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CodingPet",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CodingPet", targets: ["CodingPet"]),
        .executable(name: "CodingPetHook", targets: ["CodingPetHook"])
    ],
    targets: [
        .target(
            name: "CodingPetBridge",
            path: "Sources/CodingPetBridge"
        ),
        .executableTarget(
            name: "CodingPet",
            dependencies: ["CodingPetBridge"],
            path: "Sources/CodingPet",
            resources: [.copy("Resources/Pets")]
        ),
        .executableTarget(
            name: "CodingPetHook",
            dependencies: ["CodingPetBridge"],
            path: "Sources/CodingPetHook"
        ),
        .testTarget(
            name: "CodingPetTests",
            dependencies: ["CodingPet", "CodingPetBridge"],
            path: "Tests/CodingPetTests",
            resources: [.copy("Fixtures")]
        )
    ]
)
