import Foundation

/// Windows version reported to programs (the `winecfg -v` identifiers).
public enum WindowsVersion: String, Codable, CaseIterable, Sendable {
    case win7
    case win8
    case win81
    case win10
    case win11

    public var displayName: String {
        switch self {
        case .win7: return "Windows 7"
        case .win8: return "Windows 8"
        case .win81: return "Windows 8.1"
        case .win10: return "Windows 10"
        case .win11: return "Windows 11"
        }
    }
}

/// Synchronisation primitive used by Wine for Windows sync objects.
public enum SyncMode: String, Codable, CaseIterable, Sendable {
    case none
    /// eventfd-based sync (upstream `WINEESYNC`).
    case esync
    /// Mach semaphore-based sync from Apple's GPTK (`WINEMSYNC`). Faster on macOS.
    case msync

    public var displayName: String {
        switch self {
        case .none: return "Nenhum"
        case .esync: return "ESync"
        case .msync: return "MSync (recomendado)"
        }
    }
}

/// How Direct3D calls are translated to Metal.
public enum GraphicsBackend: String, Codable, CaseIterable, Sendable {
    /// Wine's own OpenGL-based Direct3D (slow, but always available).
    case wined3d
    /// Apple's D3DMetal from the Game Porting Toolkit (DX11/DX12). Needs a GPTK-based engine.
    case d3dmetal
    /// DXVK over MoltenVK (DX10/DX11).
    case dxvk
    /// DXMT: Direct3D 11 straight to Metal (experimental).
    case dxmt

    public var displayName: String {
        switch self {
        case .wined3d: return "WineD3D (OpenGL)"
        case .d3dmetal: return "D3DMetal (Game Porting Toolkit)"
        case .dxvk: return "DXVK (MoltenVK)"
        case .dxmt: return "DXMT (experimental)"
        }
    }

    /// DLLs that must be overridden to the native (DXVK/DXMT) copies in `system32`.
    public var nativeDLLs: [String] {
        switch self {
        case .dxvk: return ["d3d9", "d3d10core", "d3d11", "dxgi"]
        case .dxmt: return ["d3d10core", "d3d11", "dxgi"]
        case .wined3d, .d3dmetal: return []
        }
    }
}

public enum DXVKHUD: String, Codable, CaseIterable, Sendable {
    case off
    case fps
    case partial
    case full

    public var displayName: String {
        switch self {
        case .off: return "Desligado"
        case .fps: return "FPS"
        case .partial: return "FPS + frametimes"
        case .full: return "Completo"
        }
    }

    var environmentValue: String? {
        switch self {
        case .off: return nil
        case .fps: return "fps"
        case .partial: return "devinfo,fps,frametimes"
        case .full: return "full"
        }
    }
}

/// Per-bottle configuration. Everything here maps to environment variables or
/// registry keys that Wine understands.
public struct BottleSettings: Codable, Hashable, Sendable {
    public var windowsVersion: WindowsVersion = .win10
    public var sync: SyncMode = .msync
    public var graphics: GraphicsBackend = .wined3d
    public var dxvkHUD: DXVKHUD = .off
    public var dxvkAsync: Bool = true
    public var metalHUD: Bool = false
    public var metalTrace: Bool = false
    public var dxrEnabled: Bool = false
    /// `ROSETTA_ADVERTISE_AVX`: lets games that require AVX start under Rosetta.
    public var advertiseAVX: Bool = false
    public var retinaMode: Bool = false
    public var dpi: Int = 96
    public var wineDebug: String = "fixme-all"
    /// Extra `WINEDLLOVERRIDES` entries, e.g. `["dinput8": "n,b"]`.
    public var dllOverrides: [String: String] = [:]
    /// Extra environment variables passed to every program in the bottle.
    public var environment: [String: String] = [:]
    /// Re-deploys the `steamwebhelper` wrapper before every Steam launch.
    public var steamWebHelperFix: Bool = true

    public init() {}

    enum CodingKeys: String, CodingKey {
        case windowsVersion, sync, graphics, dxvkHUD, dxvkAsync, metalHUD, metalTrace, dxrEnabled
        case advertiseAVX, retinaMode, dpi, wineDebug, dllOverrides, environment, steamWebHelperFix
    }

    /// Tolerant decoding: settings added in newer versions fall back to their defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = BottleSettings()
        windowsVersion = try c.decodeIfPresent(WindowsVersion.self, forKey: .windowsVersion) ?? defaults.windowsVersion
        sync = try c.decodeIfPresent(SyncMode.self, forKey: .sync) ?? defaults.sync
        graphics = try c.decodeIfPresent(GraphicsBackend.self, forKey: .graphics) ?? defaults.graphics
        dxvkHUD = try c.decodeIfPresent(DXVKHUD.self, forKey: .dxvkHUD) ?? defaults.dxvkHUD
        dxvkAsync = try c.decodeIfPresent(Bool.self, forKey: .dxvkAsync) ?? defaults.dxvkAsync
        metalHUD = try c.decodeIfPresent(Bool.self, forKey: .metalHUD) ?? defaults.metalHUD
        metalTrace = try c.decodeIfPresent(Bool.self, forKey: .metalTrace) ?? defaults.metalTrace
        dxrEnabled = try c.decodeIfPresent(Bool.self, forKey: .dxrEnabled) ?? defaults.dxrEnabled
        advertiseAVX = try c.decodeIfPresent(Bool.self, forKey: .advertiseAVX) ?? defaults.advertiseAVX
        retinaMode = try c.decodeIfPresent(Bool.self, forKey: .retinaMode) ?? defaults.retinaMode
        dpi = try c.decodeIfPresent(Int.self, forKey: .dpi) ?? defaults.dpi
        wineDebug = try c.decodeIfPresent(String.self, forKey: .wineDebug) ?? defaults.wineDebug
        dllOverrides = try c.decodeIfPresent([String: String].self, forKey: .dllOverrides) ?? defaults.dllOverrides
        environment = try c.decodeIfPresent([String: String].self, forKey: .environment) ?? defaults.environment
        steamWebHelperFix = try c.decodeIfPresent(Bool.self, forKey: .steamWebHelperFix) ?? defaults.steamWebHelperFix
    }

    /// Opinionated defaults for a bottle that will host Steam games.
    public static func gaming(engine: WineEngine?) -> BottleSettings {
        var settings = BottleSettings()
        settings.windowsVersion = .win10
        settings.sync = .msync
        if let engine, engine.supportsD3DMetal, SystemInfo.supportsD3DMetal {
            settings.graphics = .d3dmetal
        } else {
            settings.graphics = .wined3d
        }
        return settings
    }

    /// Environment variables derived from these settings.
    public func environmentVariables() -> [String: String] {
        var env: [String: String] = [:]
        env["WINEDEBUG"] = wineDebug.isEmpty ? "-all" : wineDebug

        switch sync {
        case .none:
            break
        case .esync:
            env["WINEESYNC"] = "1"
        case .msync:
            env["WINEMSYNC"] = "1"
            // GPTK's D3DMetal misbehaves when esync is off while msync is on.
            env["WINEESYNC"] = "1"
        }

        if metalHUD { env["MTL_HUD_ENABLED"] = "1" }
        if metalTrace { env["METAL_CAPTURE_ENABLED"] = "1" }
        if advertiseAVX { env["ROSETTA_ADVERTISE_AVX"] = "1" }

        var overrides: [String] = []
        switch graphics {
        case .wined3d:
            break
        case .d3dmetal:
            if dxrEnabled { env["D3DM_SUPPORT_DXR"] = "1" }
        case .dxvk:
            overrides.append(graphics.nativeDLLs.joined(separator: ",") + "=n,b")
            if dxvkAsync { env["DXVK_ASYNC"] = "1" }
            if let hud = dxvkHUD.environmentValue { env["DXVK_HUD"] = hud }
        case .dxmt:
            overrides.append(graphics.nativeDLLs.joined(separator: ",") + "=n,b")
        }
        for (dll, mode) in dllOverrides.sorted(by: { $0.key < $1.key }) {
            overrides.append("\(dll)=\(mode)")
        }
        if !overrides.isEmpty {
            env["WINEDLLOVERRIDES"] = overrides.joined(separator: ";")
        }

        for (key, value) in environment {
            env[key] = value
        }
        return env
    }
}
