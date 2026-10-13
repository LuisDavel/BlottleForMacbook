import Foundation

/// Finds installed programs in a bottle: Start Menu shortcuts first, then a
/// shallow scan of `Program Files`.
public enum ProgramScanner {
    static let ignoredNameFragments = [
        "uninstall", "uninst", "desinstal", "unins0", "setup", "install", "update", "updater",
        "crashhandler", "crash_handler", "report", "redist", "vcredist", "dxsetup", "helper",
    ]

    public static func startMenuDirectories(in bottle: Bottle) -> [URL] {
        var directories = [
            bottle.driveC.appendingPathComponent("ProgramData/Microsoft/Windows/Start Menu/Programs", isDirectory: true),
            bottle.userDirectory.appendingPathComponent("AppData/Roaming/Microsoft/Windows/Start Menu/Programs", isDirectory: true),
            bottle.userDirectory.appendingPathComponent("Desktop", isDirectory: true),
        ]
        // Wine may also use "Public" and legacy names.
        directories.append(bottle.usersDirectory.appendingPathComponent("Public/Start Menu/Programs", isDirectory: true))
        return directories.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Programs discovered through `.lnk` shortcuts.
    public static func startMenuPrograms(in bottle: Bottle) -> [Program] {
        var programs: [String: Program] = [:]
        for directory in startMenuDirectories(in: bottle) {
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let file as URL in enumerator where file.pathExtension.lowercased() == "lnk" {
                guard let program = program(fromShortcut: file, in: bottle) else { continue }
                if programs[program.id] == nil {
                    programs[program.id] = program
                }
            }
        }
        return programs.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public static func program(fromShortcut file: URL, in bottle: Bottle) -> Program? {
        guard let link = try? ShellLink(contentsOf: file), let target = link.targetPath else { return nil }
        guard target.lowercased().hasSuffix(".exe"), let unix = WinePath.toUnix(target, bottle: bottle) else { return nil }
        guard FileManager.default.fileExists(atPath: unix.path) else { return nil }
        if isIgnored(name: unix.lastPathComponent) || isSystemBinary(unix, in: bottle) { return nil }
        let workingDirectory = link.workingDirectory.flatMap { WinePath.toUnix($0, bottle: bottle) }
        return Program(
            name: file.deletingPathExtension().lastPathComponent,
            path: unix.path,
            arguments: link.arguments ?? "",
            workingDirectory: workingDirectory?.path,
            source: .startMenu
        )
    }

    /// Executables found up to `depth` levels below `Program Files` and `Program Files (x86)`.
    public static func scannedPrograms(in bottle: Bottle, depth: Int = 3) -> [Program] {
        var programs: [String: Program] = [:]
        for root in [bottle.programFiles, bottle.programFilesX86] {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            let rootDepth = root.standardizedFileURL.pathComponents.count
            for case let file as URL in enumerator {
                let level = file.standardizedFileURL.pathComponents.count - rootDepth
                if level > depth {
                    enumerator.skipDescendants()
                    continue
                }
                guard file.pathExtension.lowercased() == "exe" else { continue }
                let name = file.lastPathComponent
                if isIgnored(name: name) { continue }
                if file.path.lowercased().contains("/windows ") || file.path.lowercased().contains("/common files/") { continue }
                let program = Program(
                    name: Program.name(forExecutable: file),
                    path: file.path,
                    source: .scanned
                )
                if programs[program.id] == nil {
                    programs[program.id] = program
                }
            }
        }
        return programs.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Pinned programs, then Start Menu entries, then scanned ones; duplicates removed.
    public static func allPrograms(in bottle: Bottle) -> [Program] {
        var seen = Set<String>()
        var result: [Program] = []
        for program in bottle.programs + startMenuPrograms(in: bottle) + scannedPrograms(in: bottle) {
            if seen.insert(program.id).inserted {
                result.append(program)
            }
        }
        return result
    }

    static func isIgnored(name: String) -> Bool {
        let lowered = name.lowercased()
        return ignoredNameFragments.contains { lowered.contains($0) }
    }

    static func isSystemBinary(_ url: URL, in bottle: Bottle) -> Bool {
        url.standardizedFileURL.path.hasPrefix(bottle.windowsDirectory.standardizedFileURL.path + "/")
    }
}
