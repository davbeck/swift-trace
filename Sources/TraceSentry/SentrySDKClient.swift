import Dependencies
import IssueReporting
import Sentry

/// The Sentry SDK operations used by `SentrySpanMiddleware`.
public struct SentrySDKClient: Sendable {
	public var startTransaction: @Sendable (_ name: String, _ operation: String, _ bindToScope: Bool) -> any Sentry.Span
	public var captureError: @Sendable (any Error) -> Void
	public var logInfo: @Sendable (_ message: String, _ attributes: [String: any Sendable]) -> Void

	public init(
		startTransaction: @escaping @Sendable (_ name: String, _ operation: String, _ bindToScope: Bool) -> any Sentry.Span,
		captureError: @escaping @Sendable (any Error) -> Void,
		logInfo: @escaping @Sendable (_ message: String, _ attributes: [String: any Sendable]) -> Void
	) {
		self.startTransaction = startTransaction
		self.captureError = captureError
		self.logInfo = logInfo
	}
}

extension SentrySDKClient: DependencyKey {
	public static var liveValue: Self {
		Self(
			startTransaction: { name, operation, bindToScope in
				SentrySDK.startTransaction(name: name, operation: operation, bindToScope: bindToScope)
			},
			captureError: { error in
				_ = SentrySDK.capture(error: error)
			},
			logInfo: { message, attributes in
				SentrySDK.logger.info(message, attributes: attributes)
			}
		)
	}

	public static var testValue: Self {
		Self(
			startTransaction: { name, operation, bindToScope in
				reportIssue("Unimplemented SentrySDKClient.startTransaction")
				return SentrySDK.startTransaction(name: name, operation: operation, bindToScope: bindToScope)
			},
			captureError: unimplemented("SentrySDKClient.captureError"),
			logInfo: unimplemented("SentrySDKClient.logInfo")
		)
	}
}

public extension DependencyValues {
	var sentrySDK: SentrySDKClient {
		get { self[SentrySDKClient.self] }
		set { self[SentrySDKClient.self] = newValue }
	}
}
