// swift-tools-version: 6.4
import PackageDescription

/// The pinned upstream source is prepared by script/prepare-swiftmail.py.
let package = Package(
    name: "SwiftMail",
    platforms: [.macOS(.v26)],
    products: [.library(name: "SwiftMail", targets: ["SwiftMail"])],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio", from: "2.101.3"),
        .package(url: "https://github.com/apple/swift-nio-imap", from: "0.3.0"),
        .package(url: "https://github.com/apple/swift-nio-transport-services", exact: "1.28.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-collections", from: "1.0.0"),
        .package(url: "https://github.com/Cocoanetics/SwiftCross", from: "1.2.0"),
    ],
    targets: [
        .target(
            name: "SwiftMail",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOIMAP", package: "swift-nio-imap"),
                .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "OrderedCollections", package: "swift-collections"),
                .product(name: "SwiftCross", package: "SwiftCross"),
            ],
            exclude: [
                "SMTP",
                "IMAP/IMAPServer+Send.swift",
                "IMAP/IMAPConnection+TLS.swift",
                "SwiftMail.docc",
                "MIME/MSG",
                "MIME/EMLSerializer.swift",
            ],
            swiftSettings: [.treatAllWarnings(as: .error)],
        ),
    ],
    swiftLanguageModes: [.v5],
)
