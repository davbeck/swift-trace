import Dependencies
import Foundation
import Sentry
import Testing
import Trace
import struct Trace.Span
@testable import TraceSentry

@Suite
struct SentrySpanMiddlewareTests {
	@Test
	func mirrorsParentChildAttributesAndCapturesAnErrorOnce() throws {
		SentrySDK.start(configureOptions: { options in
			options.dsn = "http://public@localhost:1/1"
			options.tracesSampleRate = 1
		})

		let capturedErrors = CapturedErrors()
		try withDependencies {
			$0.date = .constant(Date(timeIntervalSince1970: 1_000))
			$0.sentrySDK = SentrySDKClient(
				startTransaction: SentrySDKClient.liveValue.startTransaction,
				captureError: { _ in capturedErrors.record() },
				logInfo: { _, _ in }
			)
		} operation: {
			let middleware = SentrySpanMiddleware()
			var parent = Span(operation: "load", context: "Screen", middleware: [middleware])
			parent.start()
			let transaction = try #require(middleware.sentrySpan(for: parent.id))
			#expect(transaction.operation == "load")
			#expect(transaction.startTimestamp == parent.startedAt)

			var child = Span(
				parent: parent.id,
				operation: "fetch",
				description: "Fetch data",
				attributes: ["count": 1],
				middleware: [middleware]
			)
			child.start()
			let sentryChild = try #require(middleware.sentrySpan(for: child.id))
			#expect(sentryChild.parentSpanId == transaction.spanId)
			#expect(sentryChild.startTimestamp == child.startedAt)
			#expect(sentryChild.data["count"] as? Int == 1)
			child.update(["count": 2])
			_ = middleware.sentrySpan(for: child.id)
			#expect(sentryChild.data["count"] as? Int == 2)

			child.finish(throwing: TestError())
			#expect(middleware.sentrySpan(for: child.id) == nil)
			#expect(sentryChild.status == .unknownError)
			#expect(sentryChild.isFinished)
			#expect(sentryChild.timestamp == child.finishedAt)
			#expect(capturedErrors.count == 1)

			parent.finish(throwing: TestError())
			#expect(middleware.sentrySpan(for: parent.id) == nil)
			#expect(transaction.status == .unknownError)
			#expect(transaction.isFinished)
			#expect(transaction.timestamp == parent.finishedAt)
			#expect(capturedErrors.count == 1)
		}
	}

	private struct TestError: Error {}

	private final class CapturedErrors: @unchecked Sendable {
		private let lock = NSLock()
		private var value = 0

		var count: Int { lock.withLock { value } }

		func record() {
			lock.withLock { value += 1 }
		}
	}
}
