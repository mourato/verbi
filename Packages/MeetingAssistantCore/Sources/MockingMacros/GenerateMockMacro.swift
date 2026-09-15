import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct GenerateMockMacro: PeerMacro {
    public static func expansion(
        of _: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in _: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let protocolDecl = declaration.as(ProtocolDeclSyntax.self) else {
            return []
        }

        let protocolName = protocolDecl.name.text
        let mockName = "MacroMock\(protocolName)"

        var members: [DeclSyntax] = []
        var overloadCounts: [String: Int] = [:]

        for member in protocolDecl.memberBlock.members {
            guard let functionDecl = member.decl.as(FunctionDeclSyntax.self) else {
                continue
            }

            let functionName = functionDecl.name.text
            let signature = functionDecl.signature

            let overloadIndex = (overloadCounts[functionName] ?? 0) + 1
            overloadCounts[functionName] = overloadIndex

            let suffix = overloadIndex == 1 ? "" : "_\(overloadIndex)"
            let id = "\(functionName)\(suffix)"

            let params = signature.parameterClause.parameters
            let paramDecls: [ParameterDecl] = params.enumerated().map { index, param in
                ParameterDecl(from: param, position: index + 1)
            }

            let argsTypeName = "\(pascalCase(functionName))\(overloadIndex == 1 ? "" : String(overloadIndex))Args"
            let returnType = signature.returnClause?.type.trimmedDescription ?? "Void"

            if !paramDecls.isEmpty {
                let argsStruct = argsStructDecl(name: argsTypeName, params: paramDecls)
                members.append(argsStruct)

                members.append(
                    DeclSyntax(
                        """
                        private(set) var \(raw: id)Calls: [\(raw: argsTypeName)] = []
                        """
                    )
                )

                members.append(
                    DeclSyntax(
                        """
                        var \(raw: id)Handler: (\(raw: handlerTypeString(signature: signature, parameters: paramDecls)))?
                        """
                    )
                )

                members.append(
                    DeclSyntax(
                        """
                        \(raw: functionSignatureSource(from: functionDecl)) {
                            \(raw: id)Calls.append(.init(\(raw: argsInitArgs(params: paramDecls))))
                            guard let handler = \(raw: id)Handler else {
                                fatalError("Unhandled call to \(raw: functionName)")
                            }
                            \(raw: handlerCallSource(signature: signature, returnType: returnType, callArgs: callArgsString(from: paramDecls)))
                        }
                        """
                    )
                )

                continue
            }

            members.append(
                DeclSyntax(
                    """
                    private(set) var \(raw: id)CallCount: Int = 0
                    """
                )
            )

            members.append(
                DeclSyntax(
                    """
                    var \(raw: id)Handler: (\(raw: handlerTypeString(signature: signature, parameters: paramDecls)))?
                    """
                )
            )

            members.append(
                DeclSyntax(
                    """
                    \(raw: functionSignatureSource(from: functionDecl)) {
                        \(raw: id)CallCount += 1
                        guard let handler = \(raw: id)Handler else {
                            fatalError("Unhandled call to \(raw: functionName)")
                        }
                        \(raw: handlerCallSource(signature: signature, returnType: returnType, callArgs: callArgsString(from: paramDecls)))
                    }
                    """
                )
            )
        }

        let memberBlock = members.map(\.description).joined(separator: "\n\n")

        return [
            DeclSyntax(
                """
                #if DEBUG
                final class \(raw: mockName): \(raw: protocolName), @unchecked Sendable {
                \(raw: memberBlock)
                }
                #endif
                """
            )
        ]
    }
}

private struct ParameterDecl {
    let name: String
    let internalName: String
    let type: String

    init(from parameter: FunctionParameterSyntax, position: Int) {
        let firstName = parameter.firstName.text
        let secondName = parameter.secondName?.text

        let internalName = secondName ?? firstName
        if internalName == "_" {
            self.internalName = "arg\(position)"
        } else {
            self.internalName = internalName
        }

        // Prefer the internal name for recorded args.
        name = self.internalName
        type = parameter.type.trimmedDescription
    }
}

private func pascalCase(_ input: String) -> String {
    guard !input.isEmpty else { return input }
    let parts = input.split(separator: "_").map(String.init)
    return parts.map { part in
        guard let first = part.first else { return part }
        return String(first).uppercased() + part.dropFirst()
    }.joined()
}

private func argsStructDecl(name: String, params: [ParameterDecl]) -> DeclSyntax {
    let properties = params
        .map { "let \($0.name): \($0.type)" }
        .joined(separator: "\n")

    return DeclSyntax(
        """
        struct \(raw: name) {
            \(raw: properties)
        }
        """
    )
}

private func argsInitArgs(params: [ParameterDecl]) -> String {
    params.map { "\($0.name): \($0.internalName)" }.joined(separator: ", ")
}

private func callArgsString(from params: [ParameterDecl]) -> String {
    params.map(\.internalName).joined(separator: ", ")
}

private func handlerTypeString(signature: FunctionSignatureSyntax, parameters: [ParameterDecl]) -> String {
    let paramTypes = parameters.map(\.type).joined(separator: ", ")
    let paramsSource = "(\(paramTypes))"

    let asyncSource = signature.effectSpecifiers?.asyncSpecifier != nil ? " async" : ""
    let throwsSource = signature.effectSpecifiers?.throwsClause != nil ? " throws" : ""

    let returnType = signature.returnClause?.type.trimmedDescription ?? "Void"
    return "\(paramsSource)\(asyncSource)\(throwsSource) -> \(returnType)"
}

private func functionSignatureSource(from functionDecl: FunctionDeclSyntax) -> String {
    let name = functionDecl.name.text
    let signature = functionDecl.signature.trimmedDescription
    return "func \(name)\(signature)"
}

private func handlerCallSource(signature: FunctionSignatureSyntax, returnType: String, callArgs: String) -> String {
    let asyncKeyword = signature.effectSpecifiers?.asyncSpecifier != nil
    let throwsKeyword = signature.effectSpecifiers?.throwsClause != nil

    let awaitKeyword = asyncKeyword ? " await" : ""
    let tryKeyword = throwsKeyword ? "try " : ""

    if returnType == "Void" {
        return "\(tryKeyword)\(awaitKeyword) handler(\(callArgs))".replacingOccurrences(of: "  ", with: " ")
    }

    return "return \(tryKeyword)\(awaitKeyword) handler(\(callArgs))".replacingOccurrences(of: "  ", with: " ")
}
