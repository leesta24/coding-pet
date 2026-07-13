// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CodingPet",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CodingPet", targets: ["CodingPet"])
    ],
    targets: [
        .executableTarget(
            name: "CodingPet",
            path: "Sources/CodingPet"
        ),
        .testTarget(
            name: "CodingPetTests",
            dependencies: ["CodingPet"],
            path: "Tests/CodingPetTests"
        )
    ]
)
