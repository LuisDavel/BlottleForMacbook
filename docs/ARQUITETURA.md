# Arquitetura

```
Package.swift
├── Sources/BlottleKit      biblioteca: toda a lógica (sem UI)
│   ├── Core/               caminhos, erros, execução de processos, info do sistema
│   ├── Engine/             WineEngine, EngineCatalog (downloads), EngineManager (instalar/importar)
│   ├── Bottle/             Bottle (metadados), BottleSettings (env/registro), BottleStore, Program, WinePath
│   ├── Wine/               WineRunner (ambiente + processos), WineRegistry, Winetricks, ProgramLauncher
│   ├── Graphics/           DXVKInstaller, D3DMetalInstaller, DXMTInstaller
│   ├── Steam/              SteamInstaller (SteamSetup.exe, presets, wrapper do CEF, import de login)
│   ├── Programs/           ShellLink (.lnk), PEFile (cabeçalho PE), ProgramScanner
│   └── Util/               Downloader (URLSession + SHA-256), Archive (tar/zip/dmg), ArgumentSplitter, BlottleLog
├── Sources/blottle         CLI (swift-argument-parser)
├── Sources/BlottleApp      app SwiftUI (AppModel + Views)
├── Tests/BlottleKitTests   testes unitários (sem precisar de Wine instalado)
├── tools/steamwebhelper-wrapper   wrapper Windows em Go
├── catalog/engines.json    catálogo remoto de engines (mesmo formato de CatalogEntry)
├── scripts/                bootstrap.sh, make-app.sh
└── Packaging/Info.plist    bundle do app
```

## Conceitos

**Engine** = uma instalação de Wine (`bin/wine`, `lib/`). Fica em `Engines/<id>/` com um `engine.json` (nome, versão, *flavor*, caminho da raiz). Engines importadas de fora (CrossOver, GPTK) são apenas um link simbólico. O *flavor* decide o que faz sentido: só engines baseadas no GPTK (`gptk`, `whisky`, `crossover`) aceitam D3DMetal.

**Garrafa** = um `WINEPREFIX` com um `Blottle.json` dentro (id, nome, engine, `BottleSettings`, programas fixados). `BottleStore.create` cria a pasta, roda `wineboot --init`, espera o `wineserver` e aplica versão do Windows / Retina / DPI via `winecfg -v` e `reg add`.

**BottleSettings.environmentVariables()** é a única fonte das variáveis de ambiente derivadas das opções:

| Opção | Variável |
| --- | --- |
| sync = msync | `WINEMSYNC=1` + `WINEESYNC=1` |
| sync = esync | `WINEESYNC=1` |
| graphics = dxvk | `WINEDLLOVERRIDES=d3d9,d3d10core,d3d11,dxgi=n,b`, `DXVK_ASYNC`, `DXVK_HUD` |
| graphics = d3dmetal | (nada; o Wine do GPTK usa D3DMetal se `lib/external` existir), `D3DM_SUPPORT_DXR` |
| metalHUD | `MTL_HUD_ENABLED=1` |
| advertiseAVX | `ROSETTA_ADVERTISE_AVX=1` |
| wineDebug | `WINEDEBUG` |
| dllOverrides / environment | acrescentados por cima |

**WineRunner** monta o ambiente (herda o shell + `WINEPREFIX` + settings + `PATH` com `bin/` da engine) e tem dois modos: `run` (espera terminar, captura saída; usado em `wineboot`, `reg`, instaladores silenciosos) e `launch` (processo em segundo plano com saída direto num arquivo em `~/Library/Logs/Blottle`). O `run` nunca espera EOF do pipe porque o `wineserver` herda o pipe e pode mantê-lo aberto para sempre.

**ProgramLauncher** escolhe o comando pelo tipo do arquivo: `.exe` direto, `.msi` → `msiexec /i`, `.bat` → `cmd /c`, `.lnk` → `start /unix`, `.reg` → `regedit /S`. Programas do tipo `steam` reaplicam o wrapper do `steamwebhelper` antes de abrir.

**ProgramScanner** lê os atalhos `.lnk` do Menu Iniciar (parser próprio do formato MS-SHLLINK), converte `C:\…` para o caminho Unix da garrafa e complementa com uma varredura rasa de `Program Files`. Desinstaladores e binários de `windows/` são ignorados.

## App

`AppModel` (`@Observable`, `@MainActor`) guarda o estado e chama o `BlottleKit`. Operações longas rodam dentro de `perform(...)`, que mostra o overlay de progresso e converte erros em alertas. As views são pequenas e sem lógica: `ContentView` (sidebar), `BottleDetailView` (programas, drag & drop, toolbar), sheets de criação/configuração/Steam/winetricks/logs e a janela de Ajustes (engines, sistema).

## Testes

Os testes não precisam de Wine: usam prefixos falsos, `.lnk` e PE sintéticos, um `bin/wine` em shell script e um tarball de DXVK gerado na hora. Rode `swift test` em um Mac ou veja o workflow do GitHub Actions.

## Por que não compilar no Linux?

O `BlottleKit` usa `Process`, `URLSession` e `CryptoKit` da Foundation da Apple e assume ferramentas do macOS (`tar`, `ditto`, `hdiutil`, `xattr`). O app usa SwiftUI/AppKit. O CI roda em `macos-14`.
