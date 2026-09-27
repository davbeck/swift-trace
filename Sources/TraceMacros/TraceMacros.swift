import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct TracePlugin: CompilerPlugin {
	let providingMacros: [Macro.Type] = [
		TracedContextMacro.self,
		TracedMacro.self,
	]
}
