import Foundation
@testable import BlottleKit

enum TestSupport {
    /// Fresh temporary directory, removed by the caller.
    static func temporaryDirectory(_ name: String = "blottle-tests") -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A bottle folder with the bare minimum of a Wine prefix layout.
    static func makeBottle(named name: String = "Test", in root: URL, engineID: String = "engine") -> Bottle {
        let url = root.appendingPathComponent(name, isDirectory: true)
        let bottle = Bottle(name: name, engineID: engineID, url: url)
        for directory in [bottle.system32, bottle.sysWOW64, bottle.programFiles, bottle.programFilesX86, bottle.dosDevices,
                          bottle.userDirectory.appendingPathComponent("AppData/Roaming/Microsoft/Windows/Start Menu/Programs", isDirectory: true),
                          bottle.driveC.appendingPathComponent("ProgramData/Microsoft/Windows/Start Menu/Programs", isDirectory: true)] {
            try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return bottle
    }

    static func touch(_ url: URL, contents: Data = Data("x".utf8)) {
        try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: contents)
    }

    /// Creates a fake Wine root (`bin/wine` is a shell script) and returns it.
    static func makeFakeWineRoot(at root: URL, binaryName: String = "wine") -> URL {
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try! FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: root.appendingPathComponent("lib/wine", isDirectory: true), withIntermediateDirectories: true)
        let wine = bin.appendingPathComponent(binaryName)
        try! "#!/bin/sh\necho wine-9.0-fake\n".write(to: wine, atomically: true, encoding: .utf8)
        try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wine.path)
        return root
    }

    // MARK: - Synthetic binaries

    /// Builds a Windows shortcut (MS-SHLLINK) with a LinkInfo local base path and Unicode StringData.
    static func makeShellLink(
        target: String,
        arguments: String? = nil,
        workingDirectory: String? = nil,
        description: String? = nil,
        unicode: Bool = true
    ) -> Data {
        var flags: UInt32 = ShellLink.Flags.hasLinkInfo.rawValue
        if description != nil { flags |= ShellLink.Flags.hasName.rawValue }
        if workingDirectory != nil { flags |= ShellLink.Flags.hasWorkingDir.rawValue }
        if arguments != nil { flags |= ShellLink.Flags.hasArguments.rawValue }
        if unicode { flags |= ShellLink.Flags.isUnicode.rawValue }

        var data = Data()
        appendUInt32(&data, UInt32(ShellLink.headerSize))
        data.append(Data(repeating: 0, count: 16)) // CLSID
        appendUInt32(&data, flags)
        data.append(Data(repeating: 0, count: ShellLink.headerSize - 24)) // rest of header

        // LinkInfo
        let basePath = Data(target.utf8) + Data([0])
        let suffix = Data([0])
        let headerSize: UInt32 = 28
        let size = 28 + basePath.count + suffix.count
        appendUInt32(&data, UInt32(size))
        appendUInt32(&data, headerSize)
        appendUInt32(&data, 1) // VolumeIDAndLocalBasePath
        appendUInt32(&data, 0) // VolumeIDOffset
        appendUInt32(&data, headerSize) // LocalBasePathOffset
        appendUInt32(&data, 0) // CommonNetworkRelativeLinkOffset
        appendUInt32(&data, headerSize + UInt32(basePath.count)) // CommonPathSuffixOffset
        data.append(basePath)
        data.append(suffix)

        for string in [description, nil, workingDirectory, arguments, nil] {
            guard let string else { continue }
            appendUInt16(&data, UInt16(string.utf16.count))
            if unicode {
                for unit in string.utf16 { appendUInt16(&data, unit) }
            } else {
                data.append(Data(string.utf8))
            }
        }
        return data
    }

    /// Minimal PE image: MZ stub, PE signature, COFF header and optional header.
    static func makePE(machine: UInt16, magic: UInt16, subsystem: UInt16) -> Data {
        var data = Data(repeating: 0, count: 0x40)
        data[0] = 0x4D
        data[1] = 0x5A
        data.replaceSubrange(0x3C..<0x40, with: [0x40, 0, 0, 0])
        data.append(contentsOf: [0x50, 0x45, 0, 0])
        appendUInt16(&data, machine)
        appendUInt16(&data, 3) // NumberOfSections
        data.append(Data(repeating: 0, count: 12)) // timestamp, symbols
        let optionalSize: UInt16 = magic == 0x20B ? 240 : 224
        appendUInt16(&data, optionalSize)
        appendUInt16(&data, 0x22) // Characteristics
        var optional = Data(repeating: 0, count: Int(optionalSize))
        optional[0] = UInt8(magic & 0xFF)
        optional[1] = UInt8(magic >> 8)
        optional[68] = UInt8(subsystem & 0xFF)
        optional[69] = UInt8(subsystem >> 8)
        data.append(optional)
        return data
    }

    static func appendUInt16(_ data: inout Data, _ value: UInt16) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8(value >> 8))
    }

    static func appendUInt32(_ data: inout Data, _ value: UInt32) {
        for shift in stride(from: 0, to: 32, by: 8) {
            data.append(UInt8((value >> UInt32(shift)) & 0xFF))
        }
    }
}
