import Foundation

/// Launch-flag presets that work around Steam's Chromium (CEF) web views
/// misbehaving under Wine on macOS.
public enum SteamPreset: String, Codable, CaseIterable, Sendable {
    /// Replace `steamwebhelper.exe` with a wrapper that forces `--disable-gpu --single-process`
    /// and tell Steam not to restore its own binaries. Most reliable on Apple Silicon.
    case webHelperWrapper
    /// Only command-line flags; no files replaced.
    case cefFlags
    /// No tweaks at all.
    case plain

    public var displayName: String {
        switch self {
        case .webHelperWrapper: return "Wrapper do steamwebhelper (recomendado)"
        case .cefFlags: return "Apenas flags do CEF"
        case .plain: return "Sem ajustes"
        }
    }

    public var arguments: [String] {
        switch self {
        case .webHelperWrapper:
            return ["-noverifyfiles"]
        case .cefFlags:
            return ["-allosarches", "-cef-force-32bit", "-cef-in-process-gpu", "-no-cef-sandbox"]
        case .plain:
            return []
        }
    }
}

public struct SteamOptions: Sendable {
    public var preset: SteamPreset = .webHelperWrapper
    public var extraArguments: [String] = []
    /// Copies the login session from the native macOS Steam client, when present.
    public var importMacLogin: Bool = false

    public init() {}
}

/// Installs the Windows Steam client into a bottle and registers it as a program.
public enum SteamInstaller {
    public static let installerURL = URL(string: "https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe")!

    public static let wrapperFileNames: [(cefDirectory: String, wrapper: String)] = [
        ("bin/cef/cef.win7x64", "steamwebhelper-wrapper-x64.exe"),
        ("bin/cef/cef.win7", "steamwebhelper-wrapper-x86.exe"),
    ]

    public static func steamDirectory(in bottle: Bottle) -> URL {
        bottle.programFilesX86.appendingPathComponent("Steam", isDirectory: true)
    }

    public static func steamExecutable(in bottle: Bottle) -> URL {
        steamDirectory(in: bottle).appendingPathComponent("steam.exe")
    }

    public static func isInstalled(in bottle: Bottle) -> Bool {
        FileManager.default.fileExists(atPath: steamExecutable(in: bottle).path)
    }

    public static func program(for bottle: Bottle, options: SteamOptions) -> Program {
        let arguments = options.preset.arguments + options.extraArguments
        return Program(
            name: "Steam",
            path: steamExecutable(in: bottle).path,
            arguments: ArgumentSplitter.join(arguments),
            workingDirectory: steamDirectory(in: bottle).path,
            kind: .steam,
            source: .pinned
        )
    }

    /// Downloads SteamSetup.exe, runs it silently and pins Steam to the bottle.
    public static func install(
        into bottle: inout Bottle,
        engine: WineEngine,
        options: SteamOptions = SteamOptions(),
        progress: ((String) -> Void)? = nil
    ) async throws {
        guard bottle.isInitialized else {
            throw BlottleError.notSupported("a garrafa ainda não foi inicializada")
        }
        progress?("Baixando SteamSetup.exe…")
        let installer = try await Downloader.cached(installerURL)

        let runner = WineRunner(engine: engine, bottle: bottle)
        if !isInstalled(in: bottle) {
            progress?("Executando o instalador do Steam (silencioso)…")
            try await runner.check([installer.path, "/S"], logName: "steam-setup")
            try await runner.waitForWineserver()
        }
        guard isInstalled(in: bottle) else {
            throw BlottleError.fileNotFound(steamExecutable(in: bottle).path)
        }

        bottle.settings.steamWebHelperFix = options.preset == .webHelperWrapper
        if options.preset == .webHelperWrapper {
            progress?("Aplicando wrapper do steamwebhelper…")
            _ = try? applyWebHelperWrapper(to: bottle)
        }
        if options.importMacLogin {
            progress?("Importando sessão do Steam nativo…")
            _ = try? importMacLoginSession(into: bottle)
        }
        bottle.pin(program(for: bottle, options: options))
    }

    // MARK: - steamwebhelper wrapper

    /// Where to look for the wrapper binaries built from `tools/steamwebhelper-wrapper`.
    public static func wrapperDirectories() -> [URL] {
        var candidates: [URL] = []
        if let override = ProcessInfo.processInfo.environment["BLOTTLE_WRAPPER_DIR"] {
            candidates.append(URL(fileURLWithPath: override, isDirectory: true))
        }
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources)
        }
        candidates.append(BlottlePaths.tools)
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        candidates.append(executable)
        candidates.append(executable.appendingPathComponent("../tools", isDirectory: true).standardizedFileURL)
        return candidates
    }

    public static func locateWrapper(named name: String) -> URL? {
        for directory in wrapperDirectories() {
            let candidate = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    /// Replaces `steamwebhelper.exe` with the wrapper (keeping the original as
    /// `steamwebhelper.orig.exe`). Returns true when at least one copy was deployed.
    ///
    /// Steam downloads its CEF runtime on first launch, so this must run again
    /// right before every launch; `ProgramLauncher` does that.
    @discardableResult
    public static func applyWebHelperWrapper(to bottle: Bottle, wrapperDirectory: URL? = nil) throws -> Bool {
        let fm = FileManager.default
        var applied = false
        for entry in wrapperFileNames {
            let cefDirectory = steamDirectory(in: bottle).appendingPathComponent(entry.cefDirectory, isDirectory: true)
            guard fm.fileExists(atPath: cefDirectory.path) else { continue }
            let wrapper: URL?
            if let wrapperDirectory {
                let candidate = wrapperDirectory.appendingPathComponent(entry.wrapper)
                wrapper = fm.fileExists(atPath: candidate.path) ? candidate : nil
            } else {
                wrapper = locateWrapper(named: entry.wrapper)
            }
            guard let wrapper else { continue }

            let helper = cefDirectory.appendingPathComponent("steamwebhelper.exe")
            let original = cefDirectory.appendingPathComponent("steamwebhelper.orig.exe")
            guard fm.fileExists(atPath: helper.path) else { continue }

            if !fm.fileExists(atPath: original.path) {
                try fm.moveItem(at: helper, to: original)
            } else if try !filesAreIdentical(helper, wrapper) {
                // Steam restored its own binary: keep it as the new original.
                try fm.removeItem(at: original)
                try fm.moveItem(at: helper, to: original)
            } else {
                applied = true
                continue
            }
            try fm.copyItem(at: wrapper, to: helper)
            applied = true
        }
        return applied
    }

    static func filesAreIdentical(_ a: URL, _ b: URL) throws -> Bool {
        let fm = FileManager.default
        let sizeA = (try fm.attributesOfItem(atPath: a.path)[.size] as? NSNumber)?.int64Value ?? -1
        let sizeB = (try fm.attributesOfItem(atPath: b.path)[.size] as? NSNumber)?.int64Value ?? -2
        guard sizeA == sizeB else { return false }
        return fm.contentsEqual(atPath: a.path, andPath: b.path)
    }

    // MARK: - Login session import

    public static var macSteamDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Steam", isDirectory: true)
    }

    /// Copies `config/` and `userdata/` from the native Steam client so the
    /// Windows client starts logged in (works around the broken web login).
    @discardableResult
    public static func importMacLoginSession(into bottle: Bottle) throws -> Bool {
        let fm = FileManager.default
        let source = macSteamDirectory
        guard fm.fileExists(atPath: source.appendingPathComponent("config").path) else { return false }
        let destination = steamDirectory(in: bottle)
        var copied = false
        for folder in ["config", "userdata"] {
            let from = source.appendingPathComponent(folder, isDirectory: true)
            guard fm.fileExists(atPath: from.path) else { continue }
            let to = destination.appendingPathComponent(folder, isDirectory: true)
            if fm.fileExists(atPath: to.path) {
                let backup = destination.appendingPathComponent(folder + ".blottle-backup", isDirectory: true)
                try? fm.removeItem(at: backup)
                try fm.moveItem(at: to, to: backup)
            }
            try fm.copyItem(at: from, to: to)
            copied = true
        }
        return copied
    }
}
