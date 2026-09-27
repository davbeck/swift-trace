import Foundation
import SwiftDiagnostics
import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacros

public enum TracedMacro: BodyMacro {
	public static func expansion(
		of node: AttributeSyntax,
		providingBodyFor declaration: some DeclSyntaxProtocol & WithOptionalCodeBlockSyntax,
		in context: some MacroExpansionContext,
	) throws -> [CodeBlockItemSyntax] {
		guard let function = declaration.as(FunctionDeclSyntax.self) else {
			throw diagnostic("Traced can only be attached to functions.", at: Syntax(declaration))
		}

		guard let body = declaration.body else {
			throw diagnostic("Traced requires a function body.", at: Syntax(declaration))
		}

		let operation = try stringArgument(named: "operation", in: node) ?? function.name.text
		let spanContext = try stringArgument(named: "context", in: node)
			?? tracedContext(in: context)
			?? containerName(in: context)
		let prefix = effectPrefix(for: function)
		let attributes = attributeDictionary(for: function.signature.parameterClause.parameters)
		let source = """
		return \(prefix)withSpan(
			operation: \(stringLiteral(operation)),
			context: \(spanContext.map(stringLiteral) ?? "nil"),
			attributes: \(attributes),
		) { _ in
		\(indent(body.statements.trimmedDescription))
		}
		"""

		return Array(Parser.parse(source: source).statements)
	}
}

public enum TracedContextMacro: MemberAttributeMacro {
	public static func expansion(
		of node: AttributeSyntax,
		attachedTo declaration: some DeclGroupSyntax,
		providingAttributesFor member: some DeclSyntaxProtocol,
		in context: some MacroExpansionContext,
	) throws -> [AttributeSyntax] {
		[]
	}
}

private func stringArgument(named name: String, in node: AttributeSyntax) throws -> String? {
	guard
		let arguments = node.arguments?.as(LabeledExprListSyntax.self),
		let argument = arguments.first(where: { $0.label?.text == name })
	else { return nil }

	if argument.expression.is(NilLiteralExprSyntax.self) {
		return nil
	}

	guard
		let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self),
		stringLiteral.segments.count == 1,
		let value = stringLiteral.segments.first?.as(StringSegmentSyntax.self)?.content.text
	else {
		throw diagnostic("'\(name)' must be a static string literal.", at: Syntax(argument.expression))
	}

	return value
}

private func tracedContext(in context: some MacroExpansionContext) throws -> String? {
	for syntax in context.lexicalContext.reversed() {
		guard let container = ContainerDeclaration(syntax),
		      let attribute = container.attributes.lazy.compactMap({ $0.as(AttributeSyntax.self) })
		      .first(where: { $0.attributeName.trimmedDescription == "TracedContext" })
		else { continue }

		return try stringArgument(named: "context", in: attribute)
			?? stringArgument(at: 0, in: attribute)
			?? container.name
	}

	return nil
}

private func containerName(in context: some MacroExpansionContext) -> String? {
	for syntax in context.lexicalContext.reversed() {
		if let container = ContainerDeclaration(syntax) {
			return container.name
		}
	}

	return nil
}

private func stringArgument(at index: Int, in node: AttributeSyntax) throws -> String? {
	guard
		let arguments = node.arguments?.as(LabeledExprListSyntax.self),
		let argument = arguments.dropFirst(index).first
	else { return nil }

	if argument.expression.is(NilLiteralExprSyntax.self) {
		return nil
	}

	guard
		let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self),
		stringLiteral.segments.count == 1,
		let value = stringLiteral.segments.first?.as(StringSegmentSyntax.self)?.content.text
	else {
		throw diagnostic("'context' must be a static string literal.", at: Syntax(argument.expression))
	}

	return value
}

private func effectPrefix(for function: FunctionDeclSyntax) -> String {
	var words: [String] = []
	if function.signature.effectSpecifiers?.throwsClause != nil {
		words.append("try")
	}
	if function.signature.effectSpecifiers?.asyncSpecifier != nil {
		words.append("await")
	}
	return words.isEmpty ? "" : words.joined(separator: " ") + " "
}

private func attributeDictionary(for parameters: FunctionParameterListSyntax) -> String {
	let elements = parameters.compactMap { parameter -> String? in
		let localName = parameter.secondName ?? parameter.firstName
		let expression = localName.trimmedDescription
		guard expression != "_" else { return nil }

		let key = expression.trimmingCharacters(in: CharacterSet(charactersIn: "`"))
		return "\(stringLiteral(key)): \(expression) as Any"
	}

	return elements.isEmpty ? "[:]" : "[\(elements.joined(separator: ", "))]"
}

private func indent(_ source: String) -> String {
	source
		.split(separator: "\n", omittingEmptySubsequences: false)
		.map { "\t\($0)" }
		.joined(separator: "\n")
}

private func stringLiteral(_ value: String) -> String {
	var result = "\""
	for scalar in value.unicodeScalars {
		switch scalar {
		case "\\":
			result += "\\\\"
		case "\"":
			result += "\\\""
		case "\n":
			result += "\\n"
		case "\r":
			result += "\\r"
		case "\t":
			result += "\\t"
		default:
			result.unicodeScalars.append(scalar)
		}
	}
	result += "\""
	return result
}

private func diagnostic(_ message: String, at node: Syntax) -> DiagnosticsError {
	DiagnosticsError(diagnostics: [
		Diagnostic(node: node, message: TracedDiagnostic(message: message)),
	])
}

private struct TracedDiagnostic: DiagnosticMessage {
	let message: String
	let diagnosticID = MessageID(domain: "TraceMacros", id: "Traced")
	let severity: DiagnosticSeverity = .error
}

private struct ContainerDeclaration {
	var attributes: AttributeListSyntax
	var name: String

	init?(_ syntax: Syntax) {
		if let declaration = syntax.as(ActorDeclSyntax.self) {
			self.attributes = declaration.attributes
			self.name = declaration.name.text
		} else if let declaration = syntax.as(ClassDeclSyntax.self) {
			self.attributes = declaration.attributes
			self.name = declaration.name.text
		} else if let declaration = syntax.as(EnumDeclSyntax.self) {
			self.attributes = declaration.attributes
			self.name = declaration.name.text
		} else if let declaration = syntax.as(StructDeclSyntax.self) {
			self.attributes = declaration.attributes
			self.name = declaration.name.text
		} else if let declaration = syntax.as(ExtensionDeclSyntax.self) {
			self.attributes = declaration.attributes
			self.name = declaration.extendedType.trimmedDescription
		} else {
			return nil
		}
	}
}
