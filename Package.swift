// swift-tools-version: 6.4
import PackageDescription

let checked: [SwiftSetting] = [
    .treatAllWarnings(as: .error),
    .strictMemorySafety(),
    .unsafeFlags(["-warn-implicit-overrides"]),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]
let userInterface = checked + [.defaultIsolation(MainActor.self)]
let package = Package(
    name: "MailSearch",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "MailSearchDomain", targets: ["MailSearchDomain"]),
        .library(name: "MailSearchData", targets: ["MailSearchData"]),
        .library(name: "MailSearchFeatures", targets: ["MailSearchFeatures"]),
    ],
    dependencies: [
        .package(path: "vendor/SwiftMail"),
        .package(url: "https://github.com/scinfu/SwiftSoup", exact: "2.13.9"),
        .package(url: "https://github.com/apple/swift-log", from: "1.0.0"),
    ],
    targets: [
        .target(name: "MailSearchDomain", swiftSettings: checked),
        .target(
            name: "MailSearchData",
            dependencies: [
                "MailSearchDomain",
                "SwiftSoup",
                .product(name: "SwiftMail", package: "SwiftMail"),
                .product(name: "Logging", package: "swift-log"),
            ],
            swiftSettings: checked,
        ),
        .target(name: "MailSearchFeatures", dependencies: ["MailSearchDomain"], swiftSettings: userInterface),
        .target(
            name: "MailSearchAppSources",
            dependencies: ["MailSearchData", "MailSearchFeatures"],
            path: "App",
            exclude: ["Info.plist", "MailSearch.entitlements", "Icons", "Assets.xcassets"],
            swiftSettings: userInterface,
        ),
        .testTarget(name: "MailSearchDomainTests", dependencies: ["MailSearchDomain"], swiftSettings: checked),
        .testTarget(
            name: "MailSearchDataTests",
            dependencies: ["MailSearchData"],
            resources: [.copy("Fixtures")],
            swiftSettings: checked,
        ),
        .testTarget(
            name: "MailSearchFeaturesTests",
            dependencies: ["MailSearchFeatures"],
            swiftSettings: userInterface,
        ),
    ],
    swiftLanguageModes: [.v6],
)
