#!/usr/bin/env bash
# desinstalar-todo.sh - quita lo que instaló instalar-todo.sh: Windows (con Office y todo lo que
# tenga dentro), la configuración, win, los accesos y el complemento de GlassPad.
# No desinstala los paquetes del sistema (docker, freerdp, flatpak…).
# kan0p - https://github.com/kan0p/win-control - GPL-3.0-or-later
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
CONF_DIR="$HOME/.config/winapps"
THINCAST="com.thincast.client"

echo "Esto BORRA el Windows de win-control (con Office y todos los archivos que tenga dentro),"
echo "su configuración y los accesos. Tus archivos de Linux no se tocan."
read -r -p "Escribe BORRAR para continuar: " r
[ "$r" = BORRAR ] || { echo "Cancelado."; exit 1; }

if command -v docker >/dev/null && docker inspect WinApps >/dev/null 2>&1; then
    echo "== Apagando y borrando Windows (contenedor y su disco)…"
    for p in $(pgrep -u "$(id -u)" -x xfreerdp3; pgrep -u "$(id -u)" -x rdc); do kill -9 "$p" 2>/dev/null; done
    if [ -f "$CONF_DIR/compose.yaml" ]; then
        docker compose -f "$CONF_DIR/compose.yaml" down -v --timeout 120
    else
        docker stop -t 120 WinApps >/dev/null; docker rm WinApps >/dev/null
        docker volume rm winapps_data >/dev/null 2>&1
    fi
fi

echo "== Quitando win, accesos y complemento…"
systemctl --user disable --now win-auto.timer 2>/dev/null
rm -f "$HOME/.config/systemd/user/win-auto.service" "$HOME/.config/systemd/user/win-auto.timer"
systemctl --user daemon-reload 2>/dev/null
rm -f "$HOME"/.local/share/applications/win-*.desktop
[ -x "$DIR/install.sh" ] && "$DIR/install.sh" --desinstalar >/dev/null 2>&1
rm -f "$HOME/.local/bin/win"
rm -rf "$HOME/.local/share/glasspad/complementos/windows"
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null

echo "== Borrando configuración y datos de win-control…"
rm -rf "$HOME/.local/share/win-control" "$HOME/.local/share/win" "$HOME/.local/state/win"
rm -f "$CONF_DIR/winapps.conf" "$CONF_DIR/win.conf" "$CONF_DIR/compose.yaml"
rmdir "$CONF_DIR" 2>/dev/null

# instalación manual anterior con el instalador de WinApps (setup.sh)
if [ -e "$HOME/.local/bin/winapps" ] || [ -d "$HOME/.local/share/winapps" ]; then
    read -r -p "¿Quitar también una instalación anterior de WinApps (setup.sh y sus accesos)? [s/N] " r
    if [[ "$r" =~ ^[sS]$ ]]; then
        for a in "$HOME"/.local/share/winapps/apps/*/; do
            a="$(basename "$a")"
            # solo los archivos que son de WinApps (lanzan "winapps <app>")
            for f in "$HOME/.local/share/applications/$a.desktop" "$HOME/.local/bin/$a"; do
                grep -qs 'winapps' "$f" && rm -f "$f"
            done
        done
        rm -f "$HOME/.local/share/applications/windows.desktop" "$HOME/.local/bin/windows" \
              "$HOME/.local/share/applications/ms-office-protocol-handler.desktop" \
              "$HOME/.local/bin/winapps" "$HOME/.local/bin/winapps-setup"
        rm -rf "$HOME/.local/bin/winapps-src" "$HOME/.local/share/winapps"
        update-desktop-database "$HOME/.local/share/applications" 2>/dev/null
    fi
fi

if flatpak info --user "$THINCAST" >/dev/null 2>&1; then
    read -r -p "¿Desinstalar también Thincast (Flatpak)? [s/N] " r
    if [[ "$r" =~ ^[sS]$ ]]; then
        flatpak uninstall --user -y "$THINCAST"
        flatpak uninstall --user -y --unused
    fi
fi

echo "Listo. Para volver a instalar: ./instalar-todo.sh"
