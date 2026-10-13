import Foundation

/// Splits a command-line string the way a shell would (quotes and backslashes),
/// so users can type `-arg "with spaces"` in a text field.
public enum ArgumentSplitter {
    public static func split(_ input: String) -> [String] {
        var result: [String] = []
        var current = ""
        var hasToken = false
        var quote: Character? = nil
        var escaping = false

        for character in input {
            if escaping {
                current.append(character)
                escaping = false
                hasToken = true
                continue
            }
            if character == "\\" && quote != "'" {
                escaping = true
                continue
            }
            if let open = quote {
                if character == open {
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                hasToken = true
                continue
            }
            if character.isWhitespace {
                if hasToken {
                    result.append(current)
                    current = ""
                    hasToken = false
                }
                continue
            }
            current.append(character)
            hasToken = true
        }
        if escaping {
            current.append("\\")
            hasToken = true
        }
        if hasToken {
            result.append(current)
        }
        return result
    }

    /// Inverse of `split`, quoting tokens that need it.
    public static func join(_ arguments: [String]) -> String {
        arguments.map { token in
            if token.isEmpty { return "\"\"" }
            let needsQuotes = token.contains { $0.isWhitespace || $0 == "\"" || $0 == "'" }
            if !needsQuotes { return token }
            let escaped = token.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }.joined(separator: " ")
    }
}
