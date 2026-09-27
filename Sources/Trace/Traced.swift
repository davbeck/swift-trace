@attached(body)
public macro Traced(
	operation: String? = nil,
	context: String? = nil,
) = #externalMacro(module: "TraceMacros", type: "TracedMacro")

@attached(memberAttribute)
public macro TracedContext(
	_ context: String? = nil,
) = #externalMacro(module: "TraceMacros", type: "TracedContextMacro")
