#!/bin/bash
# One-shot setup on a fresh Mac: Rosetta, Homebrew tools, Go, build of the app and CLI.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

step() { printf '\n\033[1m» %s\033[0m\n' "$*"; }

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Este script é para macOS." >&2
  exit 1
fi

step "Xcode Command Line Tools"
if ! xcode-select -p >/dev/null 2>&1; then
  xcode-select --install || true
  echo "Instale as Command Line Tools e rode este script de novo."
  exit 1
fi

if [[ "$(uname -m)" == "arm64" ]]; then
  step "Rosetta 2 (necessário para o Wine x86_64)"
  if [[ ! -f /Library/Apple/usr/share/rosetta/rosetta ]]; then
    softwareupdate --install-rosetta --agree-to-license
  else
    echo "já instalado"
  fi
fi

step "Homebrew: cabextract (winetricks) e go (wrapper do Steam)"
if command -v brew >/dev/null 2>&1; then
  brew list cabextract >/dev/null 2>&1 || brew install cabextract
  brew list go >/dev/null 2>&1 || brew install go
else
  echo "Homebrew não encontrado. Instale em https://brew.sh e depois: brew install cabextract go"
fi

step "Compilando Blottle (pode demorar alguns minutos na primeira vez)"
make app

step "Instalando wrappers do steamwebhelper em ~/Library/Application Support/Blottle/Tools"
mkdir -p "$HOME/Library/Application Support/Blottle/Tools"
cp build/tools/steamwebhelper-wrapper-*.exe "$HOME/Library/Application Support/Blottle/Tools/" 2>/dev/null || true

step "Instalando a CLI em /usr/local/bin (pode pedir senha)"
sudo install -m 755 .build/release/blottle /usr/local/bin/blottle || echo "pulei a CLI; use .build/release/blottle"

step "Baixando a engine Wine padrão"
blottle engine install gcenx-wine-devel-11.18 || .build/release/blottle engine install gcenx-wine-devel-11.18

cat <<MSG

Tudo pronto!
  • App:  open build/Blottle.app   (ou arraste para /Applications)
  • CLI:  blottle doctor
  • Primeira garrafa:  blottle bottle create Jogos --gaming
  • Steam:             blottle steam install Jogos && blottle steam run Jogos
MSG
