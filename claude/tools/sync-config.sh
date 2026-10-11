#!/usr/bin/env sh
# Copia la configuración compartida al proyecto Godot (res:// no puede salir de client/).
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
rm -rf "$ROOT/client/data/roles" "$ROOT/client/data/evidence" "$ROOT/client/data/scenarios" "$ROOT/client/data/skins" "$ROOT/client/data/progression" "$ROOT/client/data/abilities" "$ROOT/client/data/cosmetics"
cp -r "$ROOT/shared/config/roles" "$ROOT/shared/config/evidence" "$ROOT/shared/config/scenarios" "$ROOT/shared/config/skins" "$ROOT/shared/config/progression" "$ROOT/shared/config/abilities" "$ROOT/shared/config/cosmetics" "$ROOT/client/data/"
# Casos en formato libre de guion (se normalizan al cargarlos, sin modificarlos)
cp "$ROOT"/scenarios/*.json "$ROOT/client/data/scenarios/" 2>/dev/null || true
echo "Config sincronizada en client/data/"
