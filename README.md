# Blottle

**Rode programas Windows (.exe) e jogos da Steam no seu MacBook**, do jeito que o CrossOver faz, mas com código aberto.

O Blottle organiza o Wine em *garrafas* (bottles): cada garrafa é um "Windows" isolado com suas próprias configurações, programas e versão de Wine. Por baixo ele usa:

| Camada | O que é | Para quê |
| --- | --- | --- |
| **Wine** (builds do [Gcenx](https://github.com/Gcenx/macOS_Wine_builds), GPTK ou CrossOver) | Camada de compatibilidade Win32 → macOS | Rodar `.exe`, `.msi`, instaladores, launchers |
| **Rosetta 2** | Tradução x86_64 → arm64 | Wine e os jogos são x86_64 |
| **D3DMetal** (Game Porting Toolkit da Apple) | DirectX 11/12 → Metal | Jogos modernos em Apple Silicon |
| **DXVK** (fork macOS do Gcenx, via MoltenVK) | DirectX 10/11 → Vulkan → Metal | Alternativa quando não há D3DMetal |
| **MSync/ESync** | Sincronização rápida | Menos travadas em jogos |
| **winetricks** | Instala Visual C++, .NET, fontes… | Programas que dependem de componentes do Windows |

Inclui um app SwiftUI (`Blottle.app`) e uma CLI (`blottle`) que fazem exatamente as mesmas coisas.

> **Status:** projeto novo. O código foi escrito e testado em CI (macOS), mas a experiência real depende muito do jogo/programa, do macOS e da engine Wine escolhida. Leia [docs/STEAM.md](docs/STEAM.md) antes de esperar que todo jogo funcione.

## Requisitos

- macOS 14 Sonoma ou mais recente (macOS 15 recomendado).
- Mac com Apple Silicon (M1 ou superior) para D3DMetal. Macs Intel funcionam com WineD3D/DXVK.
- Xcode 15+ ou Command Line Tools (`xcode-select --install`) para compilar.
- [Homebrew](https://brew.sh) com `cabextract` (winetricks) e `go` (wrapper do Steam).
- Rosetta 2: `softwareupdate --install-rosetta --agree-to-license`.

## Instalação rápida

```bash
git clone https://github.com/LuisDavel/BlottleForMacbook.git
cd BlottleForMacbook
scripts/bootstrap.sh
```

O script instala Rosetta, `cabextract`, `go`, compila `build/Blottle.app` e a CLI `blottle`, e baixa a engine Wine padrão. Depois disso:

```bash
open build/Blottle.app        # interface gráfica
blottle doctor                # checa o sistema
```

Ou manualmente:

```bash
make app          # build/Blottle.app  (+ wrappers do Steam se o Go estiver instalado)
make cli          # .build/release/blottle
make test         # testes unitários
```

## Primeiro uso (app)

1. **Ajustes › Engines**: clique em *Instalar* em "Wine Devel 11.18" (ou importe um Wine que você já tenha: CrossOver, Game Porting Toolkit, WhiskyWine, `Wine Devel.app`).
2. **Nova garrafa** (⌘N): dê um nome, escolha a engine e deixe "Otimizar para jogos" ligado.
3. **Executar arquivo…** (⌘O) ou arraste um `.exe`/`.msi` para a janela. Os programas instalados aparecem na lista (lidos do Menu Iniciar e de `Program Files`).
4. **Garrafa em SSD externo**: em *Nova garrafa › Local › Escolher…* aponte uma pasta do disco externo (precisa ser APFS). Os programas dessa garrafa ficam lá; se o disco for desconectado, ela some da lista até voltar.
5. **Instalar Steam**: botão na garrafa. Veja [docs/STEAM.md](docs/STEAM.md) para os detalhes e os contornos dos bugs conhecidos.

## Primeiro uso (CLI)

```bash
blottle engine catalog                          # engines disponíveis
blottle engine install gcenx-wine-devel-11.18   # baixa (~180 MB) e instala
blottle engine detect                           # acha CrossOver/GPTK/Wine.app já instalados
blottle engine import "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver"

blottle bottle create Jogos --gaming            # cria a garrafa (wineboot + config)
blottle bottle create Jogos --gaming --location /Volumes/SSD/Bottles   # mesma coisa, mas no SSD externo (APFS)
blottle run Jogos ~/Downloads/instalador.exe    # roda qualquer .exe/.msi/.bat/.lnk
blottle bottle programs Jogos                   # lista o que foi instalado
blottle run Jogos "Demo Game"                   # roda pelo nome listado

blottle steam install Jogos --import-mac-login  # instala o Steam (Windows)
blottle steam run Jogos                         # abre o Steam

blottle winetricks Jogos corefonts vcrun2022    # componentes extras
blottle dxvk install Jogos                      # DirectX 10/11 via MoltenVK
blottle d3dmetal install whisky-wine-gptk ~/Downloads/Game_Porting_Toolkit_3.0.dmg
blottle bottle config Jogos --windows win11 --retina true --dpi 144 --env MY_VAR=1
blottle bottle kill Jogos                       # encerra tudo na garrafa
blottle bottle logs Jogos                       # último log
```

## D3DMetal (jogos DirectX 11/12 em Apple Silicon)

A Apple não permite redistribuir o D3DMetal, então o Blottle não o inclui. Para usar:

1. Use uma engine **baseada no GPTK** (WhiskyWine do catálogo, o próprio Game Porting Toolkit importado, ou CrossOver). Os builds puros do Gcenx **não** suportam D3DMetal.
2. Baixe o *Game Porting Toolkit* em <https://developer.apple.com/download/all/?q=Game%20Porting%20Toolkit> (conta de desenvolvedor gratuita).
3. **Ajustes › Engines › Instalar D3DMetal…** e aponte para o `.dmg`, ou `blottle d3dmetal install <engine> <dmg>`.
4. Na garrafa, **Configurar › Gráficos › D3DMetal**.

Sem D3DMetal, instale o **DXVK** (DirectX 10/11) ou fique no WineD3D (mais lento).

## Onde ficam as coisas

| | Caminho |
| --- | --- |
| Garrafas | `~/Library/Application Support/Blottle/Bottles/<nome>/` (o `WINEPREFIX`) |
| Engines | `~/Library/Application Support/Blottle/Engines/<id>/` |
| Cache de downloads | `~/Library/Application Support/Blottle/Cache/` |
| Wrappers do Steam | `~/Library/Application Support/Blottle/Tools/` |
| Logs | `~/Library/Logs/Blottle/<garrafa>/` |

Defina `BLOTTLE_HOME=/Volumes/SSD/Blottle` para mover tudo para outro disco.

## Documentação

- [docs/STEAM.md](docs/STEAM.md) — instalar e rodar a Steam e os jogos.
- [docs/ARQUITETURA.md](docs/ARQUITETURA.md) — como o código é organizado.
- [docs/SOLUCAO-DE-PROBLEMAS.md](docs/SOLUCAO-DE-PROBLEMAS.md) — erros comuns.

## Licença

MIT. O Wine é LGPL (WineHQ); o D3DMetal é propriedade da Apple e **não** é distribuído aqui; o Steam é da Valve.
