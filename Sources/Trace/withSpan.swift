import Dependencies
import Foundation

public nonisolated(nonsending) func withSpan<R>(
	operation: String = #function,
	context: String? = nil,
	description: String? = nil,
	file: StaticString = #file,
	line: Int = #line,
	attributes: [String: Any] = [:],
	_ work: (inout Span) async throws -> R,
) async rethrows -> R {
	var span = Span(
		operation: operation,
		context: context,
		description: description,
		file: file,
		line: line,
		attributes: attributes,
	)
	span.start()

	do {
		let result = try await Span.$current.withValue(span.id) {
			try await work(&span)
		}

		span.finish()

		return result
	} catch {
		span.finish(throwing: error)

		throw error
	}
}

public func withSpan<R>(
	operation: String = #function,
	context: String? = nil,
	description: String? = nil,
	file: StaticString = #file,
	line: Int = #line,
	attributes: [String: Any] = [:],
	_ work: (inout Span) throws -> R,
) rethrows -> R {
	var span = Span(
		operation: operation,
		context: context,
		description: description,
		file: file,
		line: line,
		attributes: attributes,
	)
	span.start()

	do {
		let result = try Span.$current.withValue(span.id) {
			try work(&span)
		}

		span.finish()

		return result
	} catch {
		span.finish(throwing: error)

		throw error
	}
}
