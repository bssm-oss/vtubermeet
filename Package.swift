// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VTuberMeet",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "VTuberMeet", targets: ["VTuberMeet"]),
        .executable(name: "VTuberMeetCoreChecks", targets: ["VTuberMeetCoreChecks"]),
        .library(name: "VTuberMeetCore", targets: ["VTuberMeetCore"])
    ],
    targets: [
        .target(name: "VTuberMeetCore"),
        .executableTarget(
            name: "VTuberMeetCoreChecks",
            dependencies: ["VTuberMeetCore"]
        ),
        .executableTarget(
            name: "VTuberMeet",
            dependencies: ["VTuberMeetCore"],
            resources: [.copy("Resources")]
        ),
        .testTarget(
            name: "VTuberMeetCoreTests",
            dependencies: ["VTuberMeetCore"]
        )
    ]
)
