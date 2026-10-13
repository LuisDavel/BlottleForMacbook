#!/bin/bash
# Wraps the SwiftPM release binary into a proper Blottle.app bundle.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-build}"
APP="$ROOT/$OUT/Blottle.app"
BIN="$ROOT/.build/release/BlottleApp"
CLI="$ROOT/.build/release/blottle"
VERSION="${BLOTTLE_VERSION:-0.1.0}"

if [[ ! -x "$BIN" ]]; then
  echo "Binário não encontrado: $BIN — rode 'swift build -c release' primeiro." >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Blottle"
[[ -x "$CLI" ]] && cp "$CLI" "$APP/Contents/MacOS/blottle"
sed "s/__VERSION__/$VERSION/g" "$ROOT/Packaging/Info.plist" > "$APP/Contents/Info.plist"
echo -n "APPL????" > "$APP/Contents/PkgInfo"

# steamwebhelper wrappers (optional, built by `make wrapper`)
for f in "$ROOT/$OUT"/tools/steamwebhelper-wrapper-*.exe; do
  [[ -f "$f" ]] && cp "$f" "$APP/Contents/Resources/"
done

# Ad-hoc signature so macOS runs it without complaining about a damaged bundle.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "aviso: codesign falhou (sem problemas para uso local)"

echo "Pronto: $APP"
echo "Dica: arraste para /Applications. Na primeira abertura use clique direito › Abrir."
