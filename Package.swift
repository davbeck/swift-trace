// swift-tools-version: 6.2

import CompilerPluginSupport
import PackageDescription

let package = Package(
	name: "Trace",
	platforms: [
		.iOS(.v26),
		.macOS(.v26),
	],
	products: [
		.library(name: "Trace", targets: ["Trace"]),
	],
	dependencies: [
		.package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
		.package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.0.0"),
		.package(url: "https://github.com/pointfreeco/swift-dependencies.git", from: "1.9.3"),
		.package(url: "https://github.com/pointfreeco/swift-macro-testing", from: "0.6.3"),
		.package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.10.1"),
		.package(url: "https://github.com/swiftlang/swift-syntax", from: "602.0.0"),
	],
	targets: [
		.target(
			name: "Trace",
			dependencies: [
				.product(name: "GRDB", package: "GRDB.swift"),
				.product(name: "CustomDump", package: "swift-custom-dump"),
				.product(name: "Dependencies", package: "swift-dependencies"),
				.product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
				"TraceMacros",
			],
			swiftSettings: [
				.enableExperimentalFeature("BodyMacros"),
				.enableUpcomingFeature("NonisolatedNonsendingByDefault"),
				.enableUpcomingFeature("InferIsolatedConformances"),
			],
		),
		.macro(
			name: "TraceMacros",
			dependencies: [
				.product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
				.product(name: "SwiftDiagnostics", package: "swift-syntax"),
				.product(name: "SwiftParser", package: "swift-syntax"),
				.product(name: "SwiftSyntax", package: "swift-syntax"),
				.product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
				.product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
			],
			swiftSettings: [
				.enableExperimentalFeature("BodyMacros"),
				.enableUpcomingFeature("NonisolatedNonsendingByDefault"),
				.enableUpcomingFeature("InferIsolatedConformances"),
			],
		),
		.testTarget(
			name: "TraceTests",
			dependencies: [
				"Trace",
				.product(name: "GRDB", package: "GRDB.swift"),
			],
			swiftSettings: [
				.enableExperimentalFeature("BodyMacros"),
				.enableUpcomingFeature("NonisolatedNonsendingByDefault"),
				.enableUpcomingFeature("InferIsolatedConformances"),
			],
		),
		.testTarget(
			name: "TraceMacrosTests",
			dependencies: [
				.product(name: "MacroTesting", package: "swift-macro-testing"),
				"TraceMacros",
			],
			swiftSettings: [
				.enableExperimentalFeature("BodyMacros"),
				.enableUpcomingFeature("NonisolatedNonsendingByDefault"),
				.enableUpcomingFeature("InferIsolatedConformances"),
			],
		),
	],
)
