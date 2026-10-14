import Foundation

public enum BlottleError: LocalizedError, Equatable {
    case engineNotFound(String)
    case engineInvalid(String)
    case bottleNotFound(String)
    case bottleAlreadyExists(String)
    case fileNotFound(String)
    case processFailed(command: String, exitCode: Int32, output: String)
    case downloadFailed(String)
    case checksumMismatch(expected: String, actual: String)
    case notSupported(String)
    case parseError(String)
    case missingDependency(String)
    case timedOut(command: String, seconds: TimeInterval)

    public var errorDescription: String? {
        switch self {
        case .engineNotFound(let id):
            return "Engine Wine não encontrada: \(id). Instale uma com `blottle engine install`."
        case .engineInvalid(let path):
            return "A pasta \(path) não contém um Wine válido (esperado bin/wine ou bin/wine64)."
        case .bottleNotFound(let name):
            return "Garrafa não encontrada: \(name)."
        case .bottleAlreadyExists(let name):
            return "Já existe uma garrafa chamada \(name)."
        case .fileNotFound(let path):
            return "Arquivo não encontrado: \(path)."
        case .processFailed(let command, let code, let output):
            let tail = output.split(separator: "\n").suffix(15).joined(separator: "\n")
            return "O comando `\(command)` terminou com código \(code).\n\(tail)"
        case .downloadFailed(let reason):
            return "Falha no download: \(reason)"
        case .checksumMismatch(let expected, let actual):
            return "Checksum inválido. Esperado \(expected), obtido \(actual)."
        case .notSupported(let reason):
            return "Não suportado: \(reason)"
        case .parseError(let reason):
            return "Erro ao interpretar dados: \(reason)"
        case .missingDependency(let dep):
            return "Dependência ausente: \(dep)"
        case .timedOut(let command, let seconds):
            return "O comando `\(command)` não terminou em \(Int(seconds)) segundos e foi encerrado."
        }
    }
}
