# Solução de problemas

Comece sempre por `blottle doctor` (ou **Ajustes › Sistema** no app) e pelo log mais recente em `~/Library/Logs/Blottle/<garrafa>/` (`blottle bottle logs <garrafa>`).

## "bad CPU type in executable" / o Wine não abre em Apple Silicon

Falta o Rosetta 2:

```bash
softwareupdate --install-rosetta --agree-to-license
```

## "Wine Devel.app está danificado" ou o macOS bloqueia

O Blottle remove a flag de quarentena ao instalar (`xattr -dr com.apple.quarantine`). Para um Wine que você baixou por fora:

```bash
xattr -dr com.apple.quarantine "/Applications/Wine Devel.app"
```

## A engine WhiskyWine não baixa

O Whisky foi descontinuado e `data.getwhisky.app` pode estar fora do ar. Alternativas que suportam D3DMetal:

- Importar o **Game Porting Toolkit** da Apple (`blottle engine import "/Applications/Game Porting Toolkit.app"` ou a pasta do Homebrew `/usr/local/opt/game-porting-toolkit`).
- Importar o Wine do **CrossOver** (`/Applications/CrossOver.app/Contents/SharedSupport/CrossOver`), se você tiver o CrossOver instalado.
- Editar `catalog/engines.json` apontando para um espelho e usar `blottle engine install`.

## Steam abre com janela preta

Ver [STEAM.md](STEAM.md): use o preset do wrapper, confirme em **Ajustes › Sistema** que o wrapper foi encontrado e rode `blottle steam fix <garrafa>` depois que o Steam baixar o CEF na primeira abertura.

## Steam: "steamwebhelper is not responding"

1. `blottle bottle kill <garrafa>`
2. `blottle steam fix <garrafa>`
3. Abra de novo. Se persistir, tente o preset "Apenas flags do CEF".

## Jogo DirectX 12 não abre / tela preta

Sem D3DMetal não há DirectX 12. Confirme em **Ajustes › Engines** que a engine mostra "D3DMetal" e, na garrafa, **Configurar › Gráficos › D3DMetal**. Macs Intel não têm D3DMetal.

## Jogo DirectX 11 lento

Troque de WineD3D para DXVK (`blottle dxvk install <garrafa>`) ou D3DMetal.

## winetricks falha com "cabextract: command not found"

```bash
brew install cabextract
```

## Textos minúsculos em telas Retina

Ou desligue o **Modo Retina**, ou suba o **DPI** para 144/192 em **Configurar › Geral**.

## Programa precisa de .NET / Visual C++

```bash
blottle winetricks <garrafa> dotnet48 vcrun2022 corefonts
```

## Resetar uma garrafa

Apague-a e crie outra. Para manter os jogos, antes copie `drive_c/Program Files (x86)/Steam/steamapps` para fora.

## Ver o que o Wine está reclamando

```bash
blottle bottle config <garrafa> --wine-debug "+loaddll,+seh"
blottle run <garrafa> jogo.exe
blottle bottle logs <garrafa> -l 200
```

Volte para `fixme-all` depois; logs verbosos derrubam o desempenho.
