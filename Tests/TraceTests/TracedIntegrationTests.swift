import Dependencies
import Foundation
import Testing
import Trace

@Traced
private func tracedValue(id: Int, name: String) -> String {
	"\(name): \(id)"
}

@Test
func tracedFunctionCompilesAndReturnsValue() {
	withDependencies {
		$0.date = .constant(Date(timeIntervalSince1970: 1_000))
	} operation: {
		#expect(tracedValue(id: 42, name: "answer") == "answer: 42")
	}
}
