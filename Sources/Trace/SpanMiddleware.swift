import Dependencies

public protocol SpanMiddleware: Sendable {
	func spanStarted(_ span: Span)
	func spanFinished(_ span: Span)
	func spanAttributesUpdated(_ span: Span, updatedAttributes: [String: any Sendable])
}

enum SpanMiddlewareDependencyKey: DependencyKey {
	static var liveValue: [any SpanMiddleware] {
		[LoggingSpanMiddleware()]
	}

	static var testValue: [any SpanMiddleware] {
		[]
	}
}

public extension DependencyValues {
	var spanMiddleware: [any SpanMiddleware] {
		get { self[SpanMiddlewareDependencyKey.self] }
		set { self[SpanMiddlewareDependencyKey.self] = newValue }
	}
}
