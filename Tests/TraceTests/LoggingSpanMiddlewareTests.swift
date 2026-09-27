import Testing
@testable import Trace

@Suite
struct LoggingSpanMiddlewareTests {
	@Test
	func formatsAttributesWithCustomDump() {
		let formatted = LoggingSpanMiddleware.formatAttributes(
			[
				"id": 42,
				"tags": ["checking", "monthly"],
			],
			maximumDepth: 3,
		)

		#expect(formatted.contains(#""id": 42"#))
		#expect(formatted.contains(#""tags": ["#))
		#expect(formatted.contains(#"[0]: "checking""#))
	}

	@Test
	func truncatesDeepAttributes() {
		let formatted = LoggingSpanMiddleware.formatAttributes(
			[
				"request": [
					"body": [
						"filters": [
							"account": "checking",
						],
					],
				],
			],
			maximumDepth: 2,
		)

		#expect(formatted.contains("\u{2026}"))
		#expect(!formatted.contains("checking"))
	}

	@Test
	func truncatesAttributesToMaximumBytes() {
		let formatted = LoggingSpanMiddleware.formatAttributes(
			[
				"message": "abcdefghijklmnopqrstuvwxyz",
			],
			maximumDepth: 1,
			maximumBytes: 18,
		)

		#expect(formatted.utf8.count <= 18)
	}

	@Test
	func canFormatAttributesWithUnlimitedDepthAndBytes() {
		let formatted = LoggingSpanMiddleware.formatAttributes(
			[
				"request": [
					"body": [
						"filters": [
							"account": "checking",
						],
					],
				],
			],
			maximumDepth: .unlimited,
			maximumBytes: .unlimited,
		)

		#expect(formatted.contains("checking"))
	}

	@Test
	func usesDefaultOptionsWithoutWildcardRule() {
		let configuration = LoggingSpanConfiguration(traceLoggingOptions: "BudgetView.load:level=verbose")
		let span = Span(
			operation: "refresh",
			context: "TransactionSync",
			middleware: [],
		)

		#expect(configuration.options(for: span) == .defaults)
	}

	@Test
	func appliesSelectorPrecedenceBySpecificity() {
		let configuration = LoggingSpanConfiguration(
			traceLoggingOptions: "*:level=errors;BudgetView.*:depth=4;*.load:level=summary;BudgetView.load:level=verbose,maxBytes=50",
		)

		let exact = Span(operation: "load", context: "BudgetView", middleware: [])
		#expect(configuration.options(for: exact) == .init(depth: 4, maxBytes: 50, level: .verbose))

		let operationWildcard = Span(operation: "load", context: "TransactionSync", middleware: [])
		#expect(configuration.options(for: operationWildcard) == .init(depth: 3, maxBytes: 1000, level: .summary))

		let contextWildcard = Span(operation: "refresh", context: "BudgetView", middleware: [])
		#expect(configuration.options(for: contextWildcard) == .init(depth: 4, maxBytes: 1000, level: .errors))
	}

	@Test
	func parsesUnlimitedDepthAndMaxBytes() {
		let configuration = LoggingSpanConfiguration(
			traceLoggingOptions: "*:depth=unlimited,maxBytes=unlimited,level=verbose",
		)
		let span = Span(operation: "load", context: "BudgetView", middleware: [])

		#expect(
			configuration.options(for: span)
				== .init(depth: .unlimited, maxBytes: .unlimited, level: .verbose),
		)
	}

	@Test
	func laterRulesWinWhenSpecificityTies() {
		let configuration = LoggingSpanConfiguration(
			traceLoggingOptions: "*.load:level=errors;*.load:level=none",
		)
		let span = Span(operation: "load", context: "BudgetView", middleware: [])

		#expect(configuration.options(for: span).level == .none)
	}

	@Test
	func launchArgumentsWinOverEnvironment() {
		let configuration = LoggingSpanConfiguration(
			environment: [
				"TRACE_LOGGING_OPTIONS": "*:level=errors",
			],
			arguments: [
				"ThinkBudget",
				"--trace-logging-options",
				"*:level=verbose",
			],
		)
		let span = Span(operation: "load", context: "BudgetView", middleware: [])

		#expect(configuration.options(for: span).level == .verbose)
	}

	@Test
	func parsesEqualsStyleLaunchArgument() {
		let configuration = LoggingSpanConfiguration(
			arguments: [
				"ThinkBudget",
				"--TRACE_LOGGING_OPTIONS=*:level=none",
			],
		)
		let span = Span(operation: "load", context: "BudgetView", middleware: [])

		#expect(configuration.options(for: span).level == .none)
	}
}
