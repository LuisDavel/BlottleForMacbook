# Steam no Blottle

O Blottle instala o **cliente Steam para Windows** dentro de uma garrafa e aplica os contornos que a comunidade (Whisky, Game Porting Toolkit, CrossOver) descobriu ao longo dos anos. Jogos que rodam no Proton/Linux tendem a rodar aqui também, com desempenho dependente do backend gráfico.

## Instalação

**App:** selecione a garrafa › **Instalar Steam**.
**CLI:**

```bash
blottle bottle create Jogos --gaming
blottle steam install Jogos --import-mac-login
blottle steam run Jogos
```

O que acontece:

1. Baixa `SteamSetup.exe` do CDN oficial da Valve e roda `SteamSetup.exe /S` (instalação silenciosa) na garrafa.
2. Registra o programa "Steam" na garrafa com os argumentos do preset escolhido.
3. Na primeira abertura, o Steam baixa o cliente completo (~400 MB) e o *CEF* (Chromium embutido). Isso pode demorar e a janela pode ficar em branco enquanto isso.

## O problema do CEF e os presets

O Steam desenha quase toda a interface (login, loja, biblioteca) com o Chromium embutido (`steamwebhelper.exe`). Sob Wine no macOS ele costuma falhar de dois jeitos: **janela preta** (o renderer abre sua própria swapchain D3D11) e **login que nunca completa** (o serviço de rede fora do processo não consegue fazer TLS pelo winsock do Wine).

| Preset | O que faz | Quando usar |
| --- | --- | --- |
| **Wrapper do steamwebhelper** (padrão) | Substitui `steamwebhelper.exe` por um mini-launcher que chama o original com `--disable-gpu --single-process`. O Steam é aberto com `-noverifyfiles` para não restaurar o binário, e o Blottle reaplica o wrapper antes de cada abertura. | Apple Silicon. É a solução mais confiável conhecida. |
| **Apenas flags do CEF** | `-allosarches -cef-force-32bit -cef-in-process-gpu -no-cef-sandbox` | Quando o wrapper não está disponível ou para comparar. |
| **Sem ajustes** | nada | Testes. |

O wrapper é compilado a partir de `tools/steamwebhelper-wrapper` (Go) com `make wrapper`, e é procurado em:

1. `$BLOTTLE_WRAPPER_DIR`
2. `Blottle.app/Contents/Resources/`
3. `~/Library/Application Support/Blottle/Tools/`

Se **Ajustes › Sistema** disser que o wrapper não foi encontrado, rode `make wrapper` e copie os dois `.exe` para a pasta `Tools` acima (o `scripts/bootstrap.sh` faz isso).

> Importante: a Valve retirou as flags antigas `-noreactlogin` e `-no-browser`; elas não funcionam mais nos clientes atuais.

## Login

Se a tela de login ficar em branco mesmo com o wrapper, marque **Importar login do Steam nativo do macOS** (ou `--import-mac-login`). O Blottle copia `config/` e `userdata/` de `~/Library/Application Support/Steam` para dentro da garrafa; é preciso estar logado no Steam nativo antes. Alternativa: fazer login uma vez no CrossOver e copiar a mesma pasta.

## Jogos

- **DirectX 11/12** em Apple Silicon: use D3DMetal (engine GPTK/WhiskyWine + bibliotecas da Apple). Sem isso, DirectX 12 não roda; DirectX 11 roda com DXVK.
- **DirectX 9/10**: WineD3D ou DXVK.
- **Anti-cheat de kernel** (EAC em modo kernel, BattlEye, Vanguard): não funciona em nenhum Wine.
- **Jogos 32 bits**: precisam de uma engine com WoW64 (todos os builds do Gcenx têm).
- Launchers extras (Ubisoft Connect, EA App, Rockstar) costumam exigir `winetricks corefonts vcrun2022` e ainda assim podem falhar.
- Ative **Configurar › Gráficos › HUD do Metal** para ver FPS.
- Jogos que exigem AVX: ligue **Anunciar AVX ao Rosetta**.

Para rodar um jogo direto sem abrir a loja, use os argumentos por programa: edite o programa "Steam" e coloque `-applaunch <appid>`.

## Dicas de desempenho

- MSync (padrão) é bem mais rápido que ESync no macOS.
- Modo Retina desligado = o jogo roda em metade da resolução nativa (o Mac faz upscale). Ligue só se a GPU der conta.
- Desative o DXVK assíncrono se houver artefatos gráficos.

## Quando desistir

Verifique o jogo em <https://www.applegamingwiki.com> e no ProtonDB. Se não roda no CrossOver nem no Whisky, não vai rodar aqui.
