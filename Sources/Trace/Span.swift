import Dependencies
import Foundation
import Dependencies

public struct SpanID: Sendable, Hashable {
	public let rawValue: UUID

	public init() {
		self.rawValue = UUID()
	}

	public var logDescription: Substring {
		rawValue.uuidString.prefix(8)
	}
}

public struct Span: Identifiable {
	@TaskLocal public static var current: Span.ID?
	
	@Dependency(\.date) private var date

	public let id: SpanID
	public let parent: Span.ID?
	public let operation: String
	public let context: String?
	public let description: String?
	public let file: StaticString
	public let line: Int
	public var attributes: [String: Any]
	public var startedAt: Date?
	public var finishedAt: Date?

	public let middleware: [any SpanMiddleware]

	public enum State: Sendable {
		case pending
		case started
		case finished
		case failed(Error)
	}

	public private(set) var state: State

	public var name: String {
		if let context {
			"\(context).\(operation)"
		} else {
			operation
		}
	}

	public init(
		parent: Span.ID? = Span.current,
		operation: String = #function,
		context: String? = nil,
		description: String? = nil,
		file: StaticString = #file,
		line: Int = #line,
		attributes: [String: Any] = [:],
	) {
		@Dependency(\.spanMiddleware) var middleware

		self.init(
			parent: parent,
			operation: operation,
			context: context,
			description: description,
			file: file,
			line: line,
			attributes: attributes,
			middleware: middleware,
		)
	}

	public init(
		parent: Span.ID? = Span.current,
		operation: String = #function,
		context: String? = nil,
		description: String? = nil,
		file: StaticString = #file,
		line: Int = #line,
		attributes: [String: Any] = [:],
		middleware: [any SpanMiddleware],
	) {
		self.id = SpanID()
		self.parent = parent
		self.operation = operation
		self.context = context
		self.description = description
		self.file = file
		self.line = line
		self.attributes = attributes
		self.middleware = middleware
		self.state = .pending
	}

	public mutating func start() {
		switch self.state {
		case .started, .finished, .failed:
			assertionFailure("Span started started more than once.")

		case .pending:
			self.startedAt = date.now
			self.state = .started

			for middleware in middleware {
				middleware.spanStarted(self)
			}
		}
	}

	public mutating func finish() {
		switch self.state {
		case .pending:
			assertionFailure("Span finished without being started.")

		case .finished, .failed:
			assertionFailure("Span finished more than once.")

		case .started:
			self.finishedAt = date.now
			self.state = .finished

			for middleware in middleware {
				middleware.spanFinished(self)
			}
		}
	}

	public mutating func finish(throwing error: Error) {
		switch self.state {
		case .pending:
			assertionFailure("Span finished without being started.")

		case .finished, .failed:
			assertionFailure("Span finished more than once.")

		case .started:
			self.finishedAt = date.now
			self.state = .failed(error)

			for middleware in middleware {
				middleware.spanFinished(self)
			}
		}
	}

	public mutating func update(_ attributes: [String: Any]) {
		switch self.state {
		case .finished, .failed:
			assertionFailure("Span updated after being finished.")

		case .pending, .started:
			self.attributes.merge(attributes, uniquingKeysWith: { _, new in new })

			for middleware in middleware {
				middleware.spanAttributesUpdated(self, updatedAttributes: attributes)
			}
		}
	}
	
	/// A start and finish the span in a single action.
	///
	/// Use this for tracking events.
	public mutating func trigger() {
		switch self.state {
		case .started, .finished, .failed:
			assertionFailure("Span started started more than once.")

		case .pending:
			self.startedAt = date.now
			self.finishedAt = self.startedAt
			
			self.state = .finished

			for middleware in middleware {
				middleware.spanFinished(self)
			}
		}
	}
}
