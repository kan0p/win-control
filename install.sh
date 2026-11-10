#!/usr/bin/env bash
# Instala win y el complemento Windows de GlassPad para el usuario actual (sin root).
# kan0p - https://github.com/kan0p/win-control - GPL-3.0-or-later
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
BIN="$HOME/.local/bin"
COMPLEMENTO="$HOME/.local/share/glasspad/complementos/windows"
ESCRITORIO="$HOME/.local/share/applications"
UNIDADES="$HOME/.config/systemd/user"
APPS=(excel-o365 word-o365 powerpoint-o365)

reiniciar_launcher() {
    systemctl --user try-restart glasspad-launcher.service 2>/dev/null || true
}

if [ "${1:-}" = "--desinstalar" ]; then
    systemctl --user disable --now win-auto.timer 2>/dev/null || true
    rm -f "$UNIDADES/win-auto.service" "$UNIDADES/win-auto.timer"
    systemctl --user daemon-reload
    rm -f "$BIN/win"
    rm -rf "$COMPLEMENTO"
    for a in "${APPS[@]}"; do
        f="$ESCRITORIO/$a.desktop"
        [ -f "$f" ] && sed -i "s|^Exec=$BIN/win $a |Exec=$BIN/winapps $a |" "$f"
    done
    f="$ESCRITORIO/windows.desktop"
    [ -f "$f" ] && sed -i "s|^Exec=$BIN/win escritorio|Exec=$BIN/winapps windows|" "$f"
    reiniciar_launcher
    echo "win desinstalado."
    exit 0
fi

command -v docker >/dev/null || { echo "Falta docker." >&2; exit 1; }
[ -f "$HOME/.config/winapps/winapps.conf" ] || { echo "Falta ~/.config/winapps/winapps.conf (usa instalar-todo.sh)." >&2; exit 1; }

mkdir -p "$BIN"
ln -sfn "$DIR/win" "$BIN/win"
echo "win -> $BIN/win"

# accesos del menú de las apps elegidas (win-<app>.desktop)
"$BIN/win" _accesos && echo "menú: accesos de las apps elegidas"

f="$ESCRITORIO/windows.desktop"
if [ -f "$f" ]; then
    sed -i "s|^Exec=.*/winapps windows.*|Exec=$BIN/win escritorio|" "$f"
    echo "menú: escritorio de Windows usa win"
fi

# sin -gfx, FreeRDP 3 no recibe las ventanas sueltas (RemoteApp) de Windows 11 24H2
CONF_WINAPPS="$HOME/.config/winapps/winapps.conf"
if [ -f "$CONF_WINAPPS" ] && ! grep -qE '^RDP_FLAGS=.*-gfx' "$CONF_WINAPPS"; then
    sed -i -E 's|^(RDP_FLAGS="[^"]*)"|\1 -gfx"|' "$CONF_WINAPPS"
    echo "winapps.conf: agregado -gfx a RDP_FLAGS"
fi

if [ -d "$HOME/.local/share/glasspad" ] || command -v glasspad-launcher >/dev/null; then
    mkdir -p "$(dirname "$COMPLEMENTO")"
    rm -rf "$COMPLEMENTO"
    ln -sfn "$DIR/glasspad/windows" "$COMPLEMENTO"
    reiniciar_launcher
    echo "complemento de GlassPad -> $COMPLEMENTO"
fi

echo "Listo. Prueba: win"
