import Dependencies
import Foundation
import Sentry
import Trace
import struct Trace.Span

/// Mirrors Trace's span tree into Sentry transactions and child spans.
///
/// Initialize the Sentry SDK in the app before installing this middleware in
/// `DependencyValues.spanMiddleware`. Each middleware instance tracks its own
/// active spans, so use the same instance throughout a trace.
public final class SentrySpanMiddleware: SpanMiddleware, @unchecked Sendable {
	private let queue = DispatchQueue(label: "SentrySpanMiddleware")
	private var activeSpans: [SpanID: any Sentry.Span] = [:]
	private var errorCapturedByChild: [SpanID: Bool] = [:]
	@Dependency(\.sentrySDK) private var sentrySDK

	public init() {}

	public func spanStarted(_ span: Span) {
		queue.async {
			let sentrySpan = if
				let parent = span.parent,
				let sentryParent = self.activeSpans[parent]
			{
				sentryParent.startChild(operation: span.operation, description: span.description)
			} else {
				self.sentrySDK.startTransaction(span.name, span.operation, true)
			}

			sentrySpan.startTimestamp = span.startedAt
			for (key, value) in span.attributes {
				sentrySpan.setData(value: value, key: key)
			}

			self.activeSpans[span.id] = sentrySpan
		}
	}

	public func spanAttributesUpdated(_ span: Span, updatedAttributes: [String: any Sendable]) {
		queue.async {
			guard let sentrySpan = self.activeSpans[span.id] else { return }
			for (key, value) in updatedAttributes {
				sentrySpan.setData(value: value, key: key)
			}
		}
	}

	public func spanFinished(_ span: Span) {
		queue.async {
			let errorCapturedByChild = self.errorCapturedByChild.removeValue(forKey: span.id) == true
			if let sentrySpan = self.activeSpans.removeValue(forKey: span.id) {
				sentrySpan.timestamp = span.finishedAt

				switch span.state {
				case .finished:
					sentrySpan.finish(status: .ok)
				case let .failed(error):
					if !errorCapturedByChild {
						self.sentrySDK.captureError(error)
					}
					if let parent = span.parent {
						self.errorCapturedByChild[parent] = true
					}

					sentrySpan.finish(status: .unknownError)
				case .pending, .started:
					assertionFailure("Unexpected Trace span state when finishing: \(span.state)")
				}
			} else {
				// Trace.event() reports a finished span without a preceding start.
				let message = if let description = span.description {
					"\(span.name) \(description)"
				} else {
					span.name
				}

				switch span.state {
				case .finished:
					var attributes = span.attributes
					attributes["trace.operation"] = span.operation
					attributes["trace.context"] = span.context
					attributes["trace.description"] = span.description
					attributes["trace.file"] = span.file.description
					attributes["trace.line"] = span.line

					self.sentrySDK.logInfo(message, attributes)
				case let .failed(error):
					self.sentrySDK.captureError(error)
				case .pending, .started:
					assertionFailure("Unexpected Trace span state when finishing: \(span.state)")
				}
			}
		}
	}

	func sentrySpan(for spanID: Span.ID) -> (any Sentry.Span)? {
		queue.sync {
			self.activeSpans[spanID]
		}
	}
}
