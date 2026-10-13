import Foundation

/// Minimal parser for Windows `.lnk` files (MS-SHLLINK), enough to find the
/// target executable, its arguments and working directory.
public struct ShellLink: Equatable, Sendable {
    public struct Flags: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static let hasLinkTargetIDList = Flags(rawValue: 1 << 0)
        public static let hasLinkInfo = Flags(rawValue: 1 << 1)
        public static let hasName = Flags(rawValue: 1 << 2)
        public static let hasRelativePath = Flags(rawValue: 1 << 3)
        public static let hasWorkingDir = Flags(rawValue: 1 << 4)
        public static let hasArguments = Flags(rawValue: 1 << 5)
        public static let hasIconLocation = Flags(rawValue: 1 << 6)
        public static let isUnicode = Flags(rawValue: 1 << 7)
    }

    /// Windows path of the target, e.g. `C:\Program Files\App\app.exe`.
    public var targetPath: String?
    public var relativePath: String?
    public var workingDirectory: String?
    public var arguments: String?
    public var linkDescription: String?
    public var iconLocation: String?

    public static let headerSize = 0x4C

    public init(contentsOf url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    public init(data: Data) throws {
        let bytes = [UInt8](data)
        guard bytes.count >= Self.headerSize, Self.readUInt32(bytes, at: 0) == UInt32(Self.headerSize) else {
            throw BlottleError.parseError("cabeçalho .lnk inválido")
        }
        let flags = Flags(rawValue: Self.readUInt32(bytes, at: 20))
        var offset = Self.headerSize

        if flags.contains(.hasLinkTargetIDList) {
            guard offset + 2 <= bytes.count else { throw BlottleError.parseError(".lnk truncado (IDList)") }
            let size = Int(Self.readUInt16(bytes, at: offset))
            offset += 2 + size
        }

        if flags.contains(.hasLinkInfo) {
            guard offset + 28 <= bytes.count else { throw BlottleError.parseError(".lnk truncado (LinkInfo)") }
            let start = offset
            let linkInfoSize = Int(Self.readUInt32(bytes, at: start))
            let headerSize = Int(Self.readUInt32(bytes, at: start + 4))
            let linkInfoFlags = Self.readUInt32(bytes, at: start + 8)
            let localBasePathOffset = Int(Self.readUInt32(bytes, at: start + 16))
            let commonPathSuffixOffset = Int(Self.readUInt32(bytes, at: start + 24))

            var base: String?
            var suffix: String?
            if headerSize >= 0x24 {
                let localBasePathOffsetUnicode = Int(Self.readUInt32(bytes, at: start + 28))
                let commonPathSuffixOffsetUnicode = Int(Self.readUInt32(bytes, at: start + 32))
                if localBasePathOffsetUnicode > 0 {
                    base = Self.readUTF16CString(bytes, at: start + localBasePathOffsetUnicode)
                }
                if commonPathSuffixOffsetUnicode > 0 {
                    suffix = Self.readUTF16CString(bytes, at: start + commonPathSuffixOffsetUnicode)
                }
            }
            if base == nil, linkInfoFlags & 0x1 != 0, localBasePathOffset > 0 {
                base = Self.readCString(bytes, at: start + localBasePathOffset)
            }
            if suffix == nil, commonPathSuffixOffset > 0 {
                suffix = Self.readCString(bytes, at: start + commonPathSuffixOffset)
            }
            if let base {
                var path = base
                if let suffix, !suffix.isEmpty {
                    if !path.hasSuffix("\\") { path += "\\" }
                    path += suffix
                }
                targetPath = path
            }
            offset = start + linkInfoSize
        }

        let unicode = flags.contains(.isUnicode)
        func readStringData() throws -> String {
            guard offset + 2 <= bytes.count else { throw BlottleError.parseError(".lnk truncado (StringData)") }
            let count = Int(Self.readUInt16(bytes, at: offset))
            offset += 2
            if unicode {
                guard offset + count * 2 <= bytes.count else { throw BlottleError.parseError(".lnk truncado (StringData)") }
                let slice = Array(bytes[offset..<(offset + count * 2)])
                offset += count * 2
                return Self.decodeUTF16LE(slice)
            } else {
                guard offset + count <= bytes.count else { throw BlottleError.parseError(".lnk truncado (StringData)") }
                let slice = Array(bytes[offset..<(offset + count)])
                offset += count
                return String(decoding: slice, as: UTF8.self)
            }
        }

        if flags.contains(.hasName) { linkDescription = try readStringData() }
        if flags.contains(.hasRelativePath) { relativePath = try readStringData() }
        if flags.contains(.hasWorkingDir) { workingDirectory = try readStringData() }
        if flags.contains(.hasArguments) { arguments = try readStringData() }
        if flags.contains(.hasIconLocation) { iconLocation = try readStringData() }
    }

    // MARK: - Byte helpers

    static func readUInt16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        guard offset + 1 < bytes.count else { return 0 }
        return UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    static func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        guard offset + 3 < bytes.count else { return 0 }
        return UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    static func readCString(_ bytes: [UInt8], at offset: Int) -> String? {
        guard offset < bytes.count else { return nil }
        var end = offset
        while end < bytes.count, bytes[end] != 0 { end += 1 }
        return String(decoding: bytes[offset..<end], as: UTF8.self)
    }

    static func readUTF16CString(_ bytes: [UInt8], at offset: Int) -> String? {
        guard offset + 1 < bytes.count else { return nil }
        var end = offset
        while end + 1 < bytes.count, !(bytes[end] == 0 && bytes[end + 1] == 0) { end += 2 }
        return decodeUTF16LE(Array(bytes[offset..<end]))
    }

    static func decodeUTF16LE(_ bytes: [UInt8]) -> String {
        var units: [UInt16] = []
        units.reserveCapacity(bytes.count / 2)
        var index = 0
        while index + 1 < bytes.count {
            units.append(UInt16(bytes[index]) | (UInt16(bytes[index + 1]) << 8))
            index += 2
        }
        return String(decoding: units, as: UTF16.self)
    }
}
