#if os(macOS)
	import MacroTesting
	import Testing
	import TraceMacros

	@Suite(.macros([TracedContextMacro.self, TracedMacro.self], record: .failed))
	struct TracedMacroTests {
		@Test func tracesFunctionInStruct() {
			assertMacro {
				"""
				struct Feature {
					@Traced
					func load(id: Int, named name: String) async throws -> String {
						try await fetch(id, name)
					}
				}
				"""
			} expansion: {
				"""
				struct Feature {
					func load(id: Int, named name: String) async throws -> String {
						return try await withSpan(
							operation: "load",
							context: "Feature",
							attributes: ["id": id as Any, "name": name as Any],
						) { _ in
							try await fetch(id, name)
						}
					}
				}
				"""
			}
		}

		@Test func tracesFreeFunctionWithoutContext() {
			assertMacro {
				"""
				@Traced
				func ping() {
					print("pong")
				}
				"""
			} expansion: {
				"""
				func ping() {
					return withSpan(
						operation: "ping",
						context: nil,
						attributes: [:],
					) { _ in
						print("pong")
					}
				}
				"""
			}
		}

		@Test func tracedContextOverridesContainerName() {
			assertMacro {
				"""
				@TracedContext("FeatureContext")
				struct Feature {
					@Traced
					func load(id: Int) {
						print(id)
					}
				}
				"""
			} expansion: {
				"""
				struct Feature {
					func load(id: Int) {
						return withSpan(
							operation: "load",
							context: "FeatureContext",
							attributes: ["id": id as Any],
						) { _ in
							print(id)
						}
					}
				}
				"""
			}
		}

		@Test func tracedFunctionContextOverridesTracedContext() {
			assertMacro {
				"""
				@TracedContext("FeatureContext")
				struct Feature {
					@Traced(context: "ExplicitContext")
					func load(id: Int) {
						print(id)
					}
				}
				"""
			} expansion: {
				"""
				struct Feature {
					func load(id: Int) {
						return withSpan(
							operation: "load",
							context: "ExplicitContext",
							attributes: ["id": id as Any],
						) { _ in
							print(id)
						}
					}
				}
				"""
			}
		}
	}
#endif
