import CustomDump
import Dependencies
import Foundation
import IssueReporting
import OSLog

public struct LoggingSpanMiddleware: SpanMiddleware {
	private let configuration: LoggingSpanConfiguration
	private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "span")

	public init(configuration: LoggingSpanConfiguration = .process) {
		self.configuration = configuration
	}

	public init(maximumAttributeDepth: Int) {
		self.init(
			configuration: LoggingSpanConfiguration(
				traceLoggingOptions: "*:depth=\(maximumAttributeDepth),level=verbose"
			)
		)
	}

	public func spanStarted(_ span: Span) {
		configuration.reportInvalidComponents(in: span)
		let options = configuration.options(for: span)
		guard options.level == .verbose else { return }

		logger.debug(
			"\(span.id.logDescription) \(span.name) started parent: \(span.parent?.logDescription ?? "nil"), \(Self.formatAttributes(span.attributes, maximumDepth: options.depth, maximumBytes: options.maxBytes))"
		)
	}

	public func spanFinished(_ span: Span) {
		let options = configuration.options(for: span)

		switch span.state {
		case .pending, .started:
			assertionFailure("unexpected span state \(span.state)")
		case .finished:
			guard options.level.logsSuccessfulFinish else { return }

			if span.startedAt == span.finishedAt {
				let details = span.description.map { " \($0)" } ?? ""
				logger.debug("\(span.id.logDescription) \(span.name) event\(details) \(Self.formatAttributes(span.attributes, maximumDepth: options.depth, maximumBytes: options.maxBytes))")
			} else {
				logger.debug("\(span.id.logDescription) \(span.name) finished")
			}
		case let .failed(error):
			guard options.level.logsFailedFinish else { return }

			logger.error("\(span.id.logDescription) \(span.name) failed: \(error)")
		}
	}

	public func spanAttributesUpdated(_ span: Span, updatedAttributes: [String: any Sendable]) {
		let options = configuration.options(for: span)
		guard options.level == .verbose else { return }

		logger.debug(
			"\(span.id.logDescription) \(span.name) updated: \(Self.formatAttributes(updatedAttributes, maximumDepth: options.depth, maximumBytes: options.maxBytes))"
		)
	}

	static func formatAttributes(
		_ attributes: [String: Any],
		maximumDepth: Int,
		maximumBytes: Int = 1000
	) -> String {
		formatAttributes(
			attributes,
			maximumDepth: .limited(maximumDepth),
			maximumBytes: .limited(maximumBytes)
		)
	}

	static func formatAttributes(
		_ attributes: [String: Any],
		maximumDepth: LoggingSpanConfiguration.Limit,
		maximumBytes: LoggingSpanConfiguration.Limit
	) -> String {
		var output = ""
		customDump(attributes, to: &output, maxDepth: maximumDepth.rawValue ?? .max)
		output = output.trimmingCharacters(in: .newlines)

		guard case let .limited(byteCount) = maximumBytes else { return output }

		if case let .limited(depth) = maximumDepth, depth > 1, output.utf8.count > byteCount {
			return formatAttributes(attributes, maximumDepth: .limited(depth - 1), maximumBytes: maximumBytes)
		}

		return output.truncated(toMaximumUTF8ByteCount: byteCount)
	}
}

public struct LoggingSpanConfiguration: Sendable {
	public struct Options: Sendable, Equatable {
		public var depth: Limit
		public var maxBytes: Limit
		public var level: Level

		public init(
			depth: Limit = Self.defaults.depth,
			maxBytes: Limit = Self.defaults.maxBytes,
			level: Level = Self.defaults.level
		) {
			self.depth = depth
			self.maxBytes = maxBytes
			self.level = level
		}

		public init(
			depth: Int,
			maxBytes: Int = 1000,
			level: Level = Self.defaults.level
		) {
			self.init(depth: .limited(depth), maxBytes: .limited(maxBytes), level: level)
		}

		public static let defaults = Self(depth: .limited(3), maxBytes: .limited(1000), level: .summary)
	}

	public enum Limit: Sendable, Equatable {
		case limited(Int)
		case unlimited

		var rawValue: Int? {
			switch self {
			case let .limited(value):
				value
			case .unlimited:
				nil
			}
		}
	}

	public enum Level: String, Sendable, Equatable, CaseIterable {
		case verbose
		case summary
		case errors
		case none

		var logsSuccessfulFinish: Bool {
			self == .verbose || self == .summary
		}

		var logsFailedFinish: Bool {
			self == .verbose || self == .summary || self == .errors
		}
	}

	private struct Rule: Sendable {
		var selector: Selector
		var options: PartialOptions
	}

	fileprivate struct PartialOptions: Sendable, Equatable {
		var depth: Limit?
		var maxBytes: Limit?
		var level: Level?
	}

	fileprivate enum Selector: Sendable, Equatable {
		case all
		case context(String)
		case operation(String)
		case exact(context: String?, operation: String)

		var specificity: Int {
			switch self {
			case .all:
				0
			case .context:
				1
			case .operation:
				2
			case .exact:
				3
			}
		}

		func matches(_ span: Span) -> Bool {
			switch self {
			case .all:
				true
			case let .context(context):
				span.context == context
			case let .operation(operation):
				span.operation == operation
			case let .exact(context, operation):
				span.context == context && span.operation == operation
			}
		}
	}

	public static var process: Self {
		Self(environment: ProcessInfo.processInfo.environment, arguments: ProcessInfo.processInfo.arguments)
	}

	private var rules: [Rule]

	public init(environment: [String: String] = [:], arguments: [String] = []) {
		let value = Self.argumentTraceLoggingOptions(in: arguments)
			?? environment["TRACE_LOGGING_OPTIONS"]

		self.init(traceLoggingOptions: value)
	}

	public init(traceLoggingOptions: String?) {
		self.rules = []

		guard let traceLoggingOptions, !traceLoggingOptions.isEmpty else { return }

		self.rules = Self.parse(traceLoggingOptions)
	}

	func options(for span: Span) -> Options {
		var options = Options.defaults
		var depthSpecificity = -1
		var maxBytesSpecificity = -1
		var levelSpecificity = -1

		for rule in rules where rule.selector.matches(span) {
			let specificity = rule.selector.specificity

			if let depth = rule.options.depth, specificity >= depthSpecificity {
				options.depth = depth
				depthSpecificity = specificity
			}
			if let maxBytes = rule.options.maxBytes, specificity >= maxBytesSpecificity {
				options.maxBytes = maxBytes
				maxBytesSpecificity = specificity
			}
			if let level = rule.options.level, specificity >= levelSpecificity {
				options.level = level
				levelSpecificity = specificity
			}
		}

		return options
	}

	func reportInvalidComponents(in span: Span) {
		#if DEBUG
			if let context = span.context, !context.isAlphanumeric {
				reportIssue("Trace span context should be alphanumeric: \(context)")
			}
			if !span.operation.isAlphanumeric {
				reportIssue("Trace span operation should be alphanumeric: \(span.operation)")
			}
		#endif
	}

	private static func parse(_ string: String) -> [Rule] {
		string
			.split(separator: ";", omittingEmptySubsequences: true)
			.compactMap { rule in
				parseRule(String(rule))
			}
	}

	private static func parseRule(_ string: String) -> Rule? {
		let parts = string.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
		guard parts.count == 2 else {
			reportIssue("Trace logging rule is missing options: \(string)")
			return nil
		}

		let selectorString = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
		guard let selector = Selector(selectorString) else {
			reportIssue("Trace logging selector is invalid: \(selectorString)")
			return nil
		}

		return Rule(
			selector: selector,
			options: PartialOptions(String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines))
		)
	}

	private static func argumentTraceLoggingOptions(in arguments: [String]) -> String? {
		for (index, argument) in arguments.enumerated() {
			for key in ["TRACE_LOGGING_OPTIONS", "trace-logging-options"] {
				if argument == "-\(key)" || argument == "--\(key)" {
					let valueIndex = arguments.index(after: index)
					guard arguments.indices.contains(valueIndex) else { continue }
					return arguments[valueIndex]
				}

				let prefix = "--\(key)="
				if argument.hasPrefix(prefix) {
					return String(argument.dropFirst(prefix.count))
				}
			}

			let prefix = "TRACE_LOGGING_OPTIONS="
			if argument.hasPrefix(prefix) {
				return String(argument.dropFirst(prefix.count))
			}
		}

		return nil
	}
}

private extension LoggingSpanConfiguration.Selector {
	init?(_ string: String) {
		if string == "*" {
			self = .all
			return
		}

		let parts = string.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
		switch parts.count {
		case 1:
			let operation = String(parts[0])
			guard operation.isValidSelectorComponent else { return nil }
			self = .exact(context: nil, operation: operation)

		case 2:
			let context = String(parts[0])
			let operation = String(parts[1])

			switch (context, operation) {
			case ("*", _):
				guard operation.isValidSelectorComponent else { return nil }
				self = .operation(operation)

			case (_, "*"):
				guard context.isValidSelectorComponent else { return nil }
				self = .context(context)

			default:
				guard context.isValidSelectorComponent, operation.isValidSelectorComponent else { return nil }
				self = .exact(context: context, operation: operation)
			}

		default:
			return nil
		}
	}
}

private extension LoggingSpanConfiguration.PartialOptions {
	init(_ string: String) {
		self.init()

		for option in string.split(separator: ",", omittingEmptySubsequences: true) {
			let parts = option.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
			guard parts.count == 2 else {
				reportIssue("Trace logging option is invalid: \(option)")
				continue
			}

			let key = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
			let value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)

			switch key {
			case "depth":
				guard let depth = LoggingSpanConfiguration.Limit(value, minimum: 1) else {
					reportIssue("Trace logging depth must be a positive integer: \(value)")
					continue
				}
				self.depth = depth

			case "maxBytes":
				guard let maxBytes = LoggingSpanConfiguration.Limit(value, minimum: 0) else {
					reportIssue("Trace logging maxBytes must be a non-negative integer: \(value)")
					continue
				}
				self.maxBytes = maxBytes

			case "level":
				guard let level = LoggingSpanConfiguration.Level(rawValue: value) else {
					reportIssue("Trace logging level is invalid: \(value)")
					continue
				}
				self.level = level

			default:
				reportIssue("Trace logging option is unknown: \(key)")
			}
		}
	}
}

private extension LoggingSpanConfiguration.Limit {
	init?(_ value: String, minimum: Int) {
		if value == "unlimited" {
			self = .unlimited
			return
		}

		guard let integer = Int(value), integer >= minimum else { return nil }
		self = .limited(integer)
	}
}

private extension String {
	var isAlphanumeric: Bool {
		!isEmpty && unicodeScalars.allSatisfy(CharacterSet.alphanumerics.contains)
	}

	var isValidSelectorComponent: Bool {
		isAlphanumeric && !contains("*")
	}

	func truncated(toMaximumUTF8ByteCount count: Int) -> String {
		guard utf8.count > count else { return self }

		var result = ""
		for character in self {
			guard result.utf8.count + String(character).utf8.count <= count else { break }
			result.append(character)
		}
		return result
	}
}
