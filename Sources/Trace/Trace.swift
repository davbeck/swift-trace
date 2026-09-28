import Dependencies
import Foundation

public enum Trace {
	public nonisolated(nonsending) static func withSpan<R>(
		operation: String = #function,
		context: String? = nil,
		description: String? = nil,
		file: StaticString = #file,
		line: Int = #line,
		attributes: [String: any Sendable] = [:],
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
	
	public static func withSpan<R>(
		operation: String = #function,
		context: String? = nil,
		description: String? = nil,
		file: StaticString = #file,
		line: Int = #line,
		attributes: [String: any Sendable] = [:],
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
	
	/// Trace an action without any duration.
	public static func event(
		operation: String = #function,
		context: String? = nil,
		_ description: String? = nil,
		file: StaticString = #file,
		line: Int = #line,
		attributes: [String: any Sendable] = [:],
	) {
		var span = Span(
			operation: operation,
			context: context,
			description: description,
			file: file,
			line: line,
			attributes: attributes,
		)
		span.trigger()
	}
}
