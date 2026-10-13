import Foundation

/// Reads just enough of a Windows PE header to know what kind of binary it is.
public struct PEFile: Equatable, Sendable {
    public enum Machine: UInt16, Sendable {
        case i386 = 0x014C
        case amd64 = 0x8664
        case arm64 = 0xAA64
        case unknown = 0

        public var displayName: String {
            switch self {
            case .i386: return "32-bit (x86)"
            case .amd64: return "64-bit (x64)"
            case .arm64: return "ARM64"
            case .unknown: return "desconhecida"
            }
        }
    }

    public enum Subsystem: UInt16, Sendable {
        case native = 1
        case windowsGUI = 2
        case windowsConsole = 3
        case unknown = 0
    }

    public var machine: Machine
    public var subsystem: Subsystem
    public var is64Bit: Bool

    public init(contentsOf url: URL) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = handle.readData(ofLength: 4096)
        try self.init(data: data)
    }

    public init(data: Data) throws {
        let bytes = [UInt8](data)
        guard bytes.count >= 0x40, bytes[0] == 0x4D, bytes[1] == 0x5A else {
            throw BlottleError.parseError("não é um executável Windows (falta assinatura MZ)")
        }
        let peOffset = Int(ShellLink.readUInt32(bytes, at: 0x3C))
        guard peOffset + 24 <= bytes.count,
              bytes[peOffset] == 0x50, bytes[peOffset + 1] == 0x45, bytes[peOffset + 2] == 0, bytes[peOffset + 3] == 0 else {
            throw BlottleError.parseError("cabeçalho PE inválido")
        }
        let machineValue = ShellLink.readUInt16(bytes, at: peOffset + 4)
        machine = Machine(rawValue: machineValue) ?? .unknown
        let optionalHeaderSize = Int(ShellLink.readUInt16(bytes, at: peOffset + 20))
        let optionalHeader = peOffset + 24
        if optionalHeaderSize >= 70, optionalHeader + 70 <= bytes.count {
            let magic = ShellLink.readUInt16(bytes, at: optionalHeader)
            is64Bit = magic == 0x20B
            subsystem = Subsystem(rawValue: ShellLink.readUInt16(bytes, at: optionalHeader + 68)) ?? .unknown
        } else {
            is64Bit = machine == .amd64 || machine == .arm64
            subsystem = .unknown
        }
    }
}
