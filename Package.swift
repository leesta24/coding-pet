// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AgentPet",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AgentPet", targets: ["AgentPet"])
    ],
    targets: [
        .executableTarget(
            name: "AgentPet",
            path: "Sources/AgentPet"
        ),
        .testTarget(
            name: "AgentPetTests",
            dependencies: ["AgentPet"],
            path: "Tests/AgentPetTests"
        )
    ]
)

