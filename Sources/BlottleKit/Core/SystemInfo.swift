import Foundation

/// Facts about the Mac we are running on that influence how Wine is set up.
public enum SystemInfo {
    /// `arm64` on Apple Silicon, `x86_64` on Intel (or when running under Rosetta).
    public static var machineArchitecture: String {
        var uts = utsname()
        uname(&uts)
        let size = MemoryLayout.size(ofValue: uts.machine)
        return withUnsafePointer(to: &uts.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: size) { String(cString: $0) }
        }
    }

    /// True when the process is an x86_64 binary translated by Rosetta.
    public static var isTranslatedByRosetta: Bool {
        var translated: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let status = sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0)
        return status == 0 && translated == 1
    }

    public static var isAppleSilicon: Bool {
        machineArchitecture == "arm64" || isTranslatedByRosetta
    }

    /// Rosetta 2 is required to run the x86_64 Wine builds on Apple Silicon.
    public static var isRosettaInstalled: Bool {
        let markers = [
            "/Library/Apple/usr/share/rosetta/rosetta",
            "/Library/Apple/usr/libexec/oah/libRosettaRuntime",
        ]
        return markers.contains { FileManager.default.fileExists(atPath: $0) }
    }

    public static var rosettaInstallCommand: String {
        "softwareupdate --install-rosetta --agree-to-license"
    }

    public static var macOSVersion: OperatingSystemVersion {
        ProcessInfo.processInfo.operatingSystemVersion
    }

    public static var macOSVersionString: String {
        let v = macOSVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    /// Game Porting Toolkit / D3DMetal needs macOS 14 Sonoma or newer.
    public static var supportsD3DMetal: Bool {
        isAppleSilicon && macOSVersion.majorVersion >= 14
    }

    public static var homebrewPrefix: URL? {
        for path in ["/opt/homebrew", "/usr/local"] where FileManager.default.fileExists(atPath: path + "/bin/brew") {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return nil
    }
}
