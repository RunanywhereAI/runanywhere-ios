//
//  CalculateTool.swift
//  RunAnywhereAI
//
//  calculate — one arithmetic expression, evaluated on a parser this app owns.
//

import Foundation
import RunAnywhere

enum CalculateTool {
    static var definition: ToolDefinition {
        ToolDefinition(
            name: "calculate",
            description: "Evaluates one arithmetic expression, such as (12 * 7) + 3, and returns the number.",
            parameters: [
                ToolParameter(
                    name: "expression",
                    type: .string,
                    description: "The arithmetic expression to evaluate."
                )
            ],
            category: "Utility"
        )
    }

    static var executor: ToolExecutor {
        { args in
            guard let expression = args["expression"]?.string, !expression.isEmpty else {
                return ["error": RAToolValue("No expression given")]
            }
            guard let value = SafeMath.evaluate(expression) else {
                return ["error": RAToolValue("Could not evaluate \(expression)")]
            }
            return ["result": RAToolValue(value)]
        }
    }
}

/// A recursive-descent evaluator, deliberately not `NSExpression`.
///
/// `NSExpression(format:)` raises an Objective-C exception on malformed input,
/// which Swift cannot catch: an empty or half-written expression from a model
/// terminates the process rather than returning nil.
enum SafeMath {
    static func evaluate(_ input: String) -> Double? {
        var parser = Parser(Array(input))
        guard let value = parser.expression(), parser.atEnd else { return nil }
        return value.isFinite ? value : nil
    }

    private struct Parser {
        private let characters: [Character]
        private var index = 0

        init(_ characters: [Character]) {
            self.characters = characters
        }

        var atEnd: Bool {
            var probe = index
            while probe < characters.count, characters[probe] == " " { probe += 1 }
            return probe == characters.count
        }

        mutating func expression() -> Double? {
            guard var value = term() else { return nil }
            while let op = peek(), op == "+" || op == "-" {
                advance()
                guard let rhs = term() else { return nil }
                value = op == "+" ? value + rhs : value - rhs
            }
            return value
        }

        private mutating func term() -> Double? {
            guard var value = factor() else { return nil }
            while let op = peek(), op == "*" || op == "/" {
                advance()
                guard let rhs = factor() else { return nil }
                if op == "/" {
                    guard rhs != 0 else { return nil }
                    value /= rhs
                } else {
                    value *= rhs
                }
            }
            return value
        }

        private mutating func factor() -> Double? {
            guard let character = peek() else { return nil }

            if character == "-" {
                advance()
                guard let value = factor() else { return nil }
                return -value
            }

            if character == "(" {
                advance()
                guard let value = expression(), peek() == ")" else { return nil }
                advance()
                return value
            }

            return number()
        }

        private mutating func number() -> Double? {
            skipSpaces()
            var digits = ""
            var sawDot = false
            while index < characters.count {
                let character = characters[index]
                if character.isNumber {
                    digits.append(character)
                } else if character == ".", !sawDot {
                    sawDot = true
                    digits.append(character)
                } else {
                    break
                }
                index += 1
            }
            return digits.isEmpty ? nil : Double(digits)
        }

        private mutating func skipSpaces() {
            while index < characters.count, characters[index] == " " { index += 1 }
        }

        private mutating func peek() -> Character? {
            skipSpaces()
            return index < characters.count ? characters[index] : nil
        }

        private mutating func advance() {
            skipSpaces()
            if index < characters.count { index += 1 }
        }
    }
}
