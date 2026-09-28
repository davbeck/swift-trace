import Dependencies
import Foundation
import GRDB
import Testing
@testable import Trace

@Suite
struct SQLiteSpanMiddlewareTests {
	@Test
	func persistsLifecycleAttributesAndParent() throws {
		try withTestDate {
			let url = temporaryDatabaseURL()
			let middleware = try SQLiteSpanMiddleware(databaseURL: url)
			var parent = Span(operation: "parent", attributes: ["initial": 1], middleware: [middleware])
			parent.start()

			let database = try DatabaseQueue(path: url.path)
			let started = try row(for: parent, in: database)
			#expect(started?["status"] == "started")
			#expect(started?["finished_at"] as Double? == nil)
			#expect(try attributes(for: parent, in: database)?["initial"] as? Int == 1)

			var child = Span(parent: parent.id, operation: "child", middleware: [middleware])
			child.start()
			child.update(["answer": 42])
			let updated = try row(for: child, in: database)
			#expect(updated?["parent_id"] == parent.id.rawValue.uuidString)
			#expect(try attributes(for: child, in: database)?["answer"] as? Int == 42)

			child.finish()
			parent.finish()
			let finished = try row(for: child, in: database)
			#expect(finished?["status"] == "finished")
			#expect(finished?["finished_at"] as Double? != nil)
		}
	}

	@Test
	func convertsUnsupportedValuesToStringsWithinJSON() throws {
		try withTestDate {
			let url = temporaryDatabaseURL()
			let middleware = try SQLiteSpanMiddleware(databaseURL: url)
			let identifier = UUID()
			var span = Span(operation: "json", attributes: [
				"text": "hello",
				"enabled": true,
				"nothing": NSNull(),
				"nested": ["values": [1, identifier, Double.infinity] as [any Sendable]],
			], middleware: [middleware])
			span.start()

			let database = try DatabaseQueue(path: url.path)
			let storedAttributes = try attributes(for: span, in: database)
			let attributes = try #require(storedAttributes)
			#expect(attributes["text"] as? String == "hello")
			#expect(attributes["enabled"] as? Bool == true)
			#expect(attributes["nothing"] is NSNull)
			let nested = try #require(attributes["nested"] as? [String: Any])
			let values = try #require(nested["values"] as? [Any])
			#expect(values[0] as? Int == 1)
			#expect(values[1] as? String == identifier.uuidString)
			#expect(values[2] as? String == "inf")
			let valid = try database.read { db in
				try Int.fetchOne(db, sql: "SELECT json_valid(attributes) FROM spans WHERE id = ?", arguments: [span.id.rawValue.uuidString])
			}
			#expect(valid == 1)
		}
	}

	@Test
	func migratesTextAttributesToJSON() throws {
		let url = temporaryDatabaseURL()
		try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
		let database = try DatabaseQueue(path: url.path)
		var oldMigrator = DatabaseMigrator()
		oldMigrator.registerMigration("createSpans") { db in
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
		try oldMigrator.migrate(database)
		try database.write { db in
			try db.execute(sql: """
				INSERT INTO spans (id, operation, file, line, attributes, started_at, status)
				VALUES ('old', 'old', 'old.swift', 1, 'old attribute dump', 1, 'finished')
				""")
		}

		_ = try SQLiteSpanMiddleware(databaseURL: url)
		let migrated = try database.read { db in
			try String.fetchOne(db, sql: "SELECT attributes FROM spans WHERE id = 'old'")
		}
		let json = try #require(migrated)
		let attributes = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: String])
		#expect(attributes["_legacy"] == "old attribute dump")
		let columnType = try database.read { db in
			try Row.fetchAll(db, sql: "PRAGMA table_info(spans)")
				.first { $0["name"] as String? == "attributes" }?["type"] as String?
		}
		#expect(columnType == "JSON")
	}

	@Test
	func marksUnfinishedSpansFailedWhenReopened() throws {
		try withTestDate {
			let url = temporaryDatabaseURL()
			let middleware = try SQLiteSpanMiddleware(databaseURL: url)
			var unfinished = Span(operation: "unfinished", middleware: [middleware])
			unfinished.start()
			var completed = Span(operation: "completed", middleware: [middleware])
			completed.start()
			completed.finish()

			_ = try SQLiteSpanMiddleware(databaseURL: url)
			let database = try DatabaseQueue(path: url.path)
			let recovered = try row(for: unfinished, in: database)
			#expect(recovered?["status"] == "failed")
			#expect((recovered?["error"] as String?) == "Interrupted before completion")
			#expect(try row(for: completed, in: database)?["status"] == "finished")
		}
	}

	@Test
	func persistsFailedSpansAndEvents() throws {
		try withTestDate {
			let url = temporaryDatabaseURL()
			let middleware = try SQLiteSpanMiddleware(databaseURL: url)
			var failed = Span(operation: "failed", middleware: [middleware])
			failed.start()
			failed.finish(throwing: TestError.example)
			var event = Span(operation: "event", middleware: [middleware])
			event.trigger()

			let database = try DatabaseQueue(path: url.path)
			#expect(try row(for: failed, in: database)?["status"] == "failed")
			#expect((try row(for: failed, in: database)?["error"] as String?)?.contains("example") == true)
			let eventRow = try row(for: event, in: database)
			#expect(eventRow?["status"] == "finished")
			#expect(eventRow?["started_at"] as Double? == eventRow?["finished_at"] as Double?)
		}
	}

	private enum TestError: Error { case example }

	private func withTestDate(_ body: () throws -> Void) rethrows {
		try withDependencies {
			$0.date = .constant(Date(timeIntervalSince1970: 1_000))
		} operation: {
			try body()
		}
	}

	private func temporaryDatabaseURL() -> URL {
		FileManager.default.temporaryDirectory
			.appending(path: "TraceTests-\(UUID().uuidString)/spans.sqlite")
	}

	private func row(for span: Span, in database: DatabaseQueue) throws -> Row? {
		try database.read { db in
			try Row.fetchOne(db, sql: "SELECT * FROM spans WHERE id = ?", arguments: [span.id.rawValue.uuidString])
		}
	}

	private func attributes(for span: Span, in database: DatabaseQueue) throws -> [String: Any]? {
		guard let json: String = try row(for: span, in: database)?["attributes"] else { return nil }
		let data = Data(json.utf8)
		return try JSONSerialization.jsonObject(with: data) as? [String: Any]
	}
}
