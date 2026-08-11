// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LectureCaption",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "LectureCaption",
            targets: ["LectureCaption"]
        )
    ],
    targets: [
        .executableTarget(
            name: "LectureCaption"
        ),
        .testTarget(
            name: "LectureCaptionTests",
            dependencies: ["LectureCaption"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
