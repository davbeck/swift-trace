import Foundation
import GRDB
import IssueReporting

/// Persists spans synchronously so a crash leaves a record of work in progress.
public struct SQLiteSpanMiddleware: SpanMiddleware {
	public static var defaultDatabaseURL: URL {
		FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
			.appending(path: "Trace/spans.sqlite")
	}

	public let databaseURL: URL
	private let database: DatabaseQueue

	public init(databaseURL: URL = Self.defaultDatabaseURL) throws {
		try FileManager.default.createDirectory(
			at: databaseURL.deletingLastPathComponent(),
			withIntermediateDirectories: true
		)
		let database = try DatabaseQueue(path: databaseURL.path)
		var migrator = DatabaseMigrator()
		migrator.registerMigration("createSpans") { db in
			try db.execute(sql: """
				CREATE TABLE spans (
				    id TEXT PRIMARY KEY NOT NULL,
				    parent_id TEXT REFERENCES spans(id),
				    operation TEXT NOT NULL,
				    context TEXT,
				    description TEXT,
				    file TEXT NOT NULL,
				    line INTEGER NOT NULL,
				    attributes TEXT NOT NULL,
				    started_at REAL NOT NULL,
				    finished_at REAL,
				    status TEXT NOT NULL,
				    error TEXT
				)
				""")
			try db.execute(sql: "CREATE INDEX spans_parent_id ON spans(parent_id)")
		}
		migrator.registerMigration("storeAttributesAsJSON") { db in
			try db.execute(sql: "ALTER TABLE spans ADD COLUMN attributes_json JSON NOT NULL DEFAULT '{}' CHECK (json_valid(attributes_json))")
			try db.execute(sql: "UPDATE spans SET attributes_json = json_object('_legacy', attributes)")
			try db.execute(sql: "ALTER TABLE spans DROP COLUMN attributes")
			try db.execute(sql: "ALTER TABLE spans RENAME COLUMN attributes_json TO attributes")
		}
		try migrator.migrate(database)
		try database.write { db in
			try db.execute(
				sql: "UPDATE spans SET status = 'failed', error = 'Interrupted before completion' WHERE status = 'started'"
			)
		}
		self.databaseURL = databaseURL
		self.database = database
	}

	public func spanStarted(_ span: Span) {
		write(span, finished: false)
	}

	public func spanFinished(_ span: Span) {
		write(span, finished: true)
	}

	public func spanAttributesUpdated(_ span: Span, updatedAttributes: [String: Any]) {
		guard case .started = span.state else { return }
		do {
			try database.write { db in
				try db.execute(
					sql: "UPDATE spans SET attributes = ? WHERE id = ?",
					arguments: [try Self.jsonAttributes(span.attributes), span.id.rawValue.uuidString]
				)
			}
		} catch {
			reportIssue("Failed to update span attributes in SQLite: \(error)")
		}
	}

	private func write(_ span: Span, finished: Bool) {
		let (status, errorDescription): (String, String?) = switch span.state {
		case .pending: ("pending", nil)
		case .started: ("started", nil)
		case .finished: ("finished", nil)
		case let .failed(error): ("failed", String(describing: error))
		}
		do {
			try database.write { db in
				try db.execute(
					sql: """
						INSERT INTO spans (
						    id, parent_id, operation, context, description, file, line,
						    attributes, started_at, finished_at, status, error
						) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
						ON CONFLICT(id) DO UPDATE SET
						    attributes = excluded.attributes,
						    finished_at = excluded.finished_at,
						    status = excluded.status,
						    error = excluded.error
						""",
					arguments: [
						span.id.rawValue.uuidString,
						span.parent?.rawValue.uuidString,
						span.operation,
						span.context,
						span.description,
						span.file.description,
						span.line,
						try Self.jsonAttributes(span.attributes),
						span.startedAt?.timeIntervalSince1970,
						span.finishedAt?.timeIntervalSince1970,
						status,
						errorDescription,
					]
					)
			}
		} catch {
			reportIssue("Failed to \(finished ? "finish" : "start") span in SQLite: \(error)")
		}
	}

	private static func jsonAttributes(_ attributes: [String: Any]) throws -> String {
		let object = attributes.mapValues(jsonValue)
		let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
		return String(decoding: data, as: UTF8.self)
	}

	private static func jsonValue(_ value: Any) -> Any {
		if let dictionary = value as? [String: Any] {
			return dictionary.mapValues(jsonValue)
		}
		if let array = value as? [Any] {
			return array.map(jsonValue)
		}
		if let number = value as? NSNumber, !number.doubleValue.isFinite {
			return String(describing: value)
		}
		if JSONSerialization.isValidJSONObject([value]) {
			return value
		}
		return String(describing: value)
	}
}
