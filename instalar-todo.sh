#!/usr/bin/env bash
# instalar-todo.sh - deja Windows con Office funcionando como apps de Linux, desde cero:
# paquetes, contenedor de Windows (dockur/windows), Office, win y el complemento de GlassPad.
# Lo único que queda para después es iniciar sesión en Office con tu cuenta (licencia).
#   ./instalar-todo.sh             instala (pide sudo solo para los paquetes)
#   ./instalar-todo.sh --simular   pregunta todo y genera la configuración en una carpeta
#                                  temporal, sin instalar nada
# kan0p - https://github.com/kan0p/win-control - GPL-3.0-or-later
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SIMULAR=0
[ "${1:-}" = "--simular" ] && SIMULAR=1

BASE="$HOME"
if [ "$SIMULAR" = 1 ]; then
    BASE="$(mktemp -d /tmp/win-control-simulacion.XXXXXX)"
fi
CONF_DIR="$BASE/.config/winapps"
DATOS="$BASE/.local/share/win-control"
ICONOS="$BASE/.local/share/win/iconos"
ESTADO="$BASE/.local/state/win"
WINAPPS_GIT="https://github.com/winapps-org/winapps.git"
THINCAST="com.thincast.client"

paso() { printf '\n\033[1m== %s\033[0m\n' "$*"; }
info() { printf '   %s\n' "$*"; }
morir() { printf '\n\033[31mError:\033[0m %s\n' "$*" >&2; exit 1; }

# preguntar "texto" "valor por defecto" -> respuesta
preguntar() {
    local r
    read -r -p "   $1 [$2]: " r
    echo "${r:-$2}"
}

# elegir "texto" opción… -> índice (desde 1)
elegir() {
    local texto="$1" i=1 r; shift
    echo "   $texto" >&2
    for o in "$@"; do echo "     $i) $o" >&2; i=$((i + 1)); done
    while true; do
        read -r -p "   Opción [1]: " r
        r="${r:-1}"
        [[ "$r" =~ ^[0-9]+$ ]] && [ "$r" -ge 1 ] && [ "$r" -le $# ] && { echo "$r"; return; }
        echo "   Escribe un número entre 1 y $#." >&2
    done
}

# elegir_varios "texto" "clave|nombre"… -> claves elegidas separadas por espacio
elegir_varios() {
    local texto="$1" i=1 r n claves=() salida=""; shift
    echo "   $texto" >&2
    for o in "$@"; do echo "     $i) ${o#*|}" >&2; claves+=("${o%%|*}"); i=$((i + 1)); done
    read -r -p "   Números separados por espacio (Enter = ninguna): " r
    for n in $r; do
        [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le ${#claves[@]} ] &&
            salida="$salida ${claves[$((n - 1))]}"
    done
    echo "$salida"
}

catalogo() {
    sed -e 's/#.*//' -e 's/[[:space:]]*|[[:space:]]*/|/g' -e 's/^[[:space:]]*//' \
        -e 's/[[:space:]]*$//' "$DIR/apps.conf" | grep '|'
}

# ----- comprobaciones ---------------------------------------------------------------

[ "$(id -u)" -ne 0 ] || morir "ejecútalo como tu usuario normal, no con sudo (el script pide sudo cuando lo necesita)."
[ -e /dev/kvm ] || morir "no existe /dev/kvm: activa la virtualización (VT-x/AMD-V) en la BIOS."
[ -f "$DIR/apps.conf" ] || morir "falta apps.conf junto al instalador."
if [ "$SIMULAR" = 0 ] && command -v docker >/dev/null && docker inspect WinApps >/dev/null 2>&1; then
    morir "ya existe un Windows instalado (contenedor WinApps). Para empezar de cero: ./desinstalar-todo.sh"
fi

echo "Instalador de win-control: Windows con Office como apps de Linux."
[ "$SIMULAR" = 1 ] && echo "MODO SIMULACIÓN: no se instala nada; la configuración queda en $BASE"

# ----- preguntas ------------------------------------------------------------------------

paso "Cliente para abrir las apps de Windows"
case "$(elegir "¿Qué cliente RDP usar para las apps sueltas?" \
        "Thincast (recomendado: más estable; las ventanas se mueven con Super + arrastrar)" \
        "FreeRDP (xfreerdp3; en COSMIC puede congelarse al abrir ventanas)")" in
    1) CLIENTE=thincast ;;
    *) CLIENTE=freerdp ;;
esac

paso "Licencia de Office"
case "$(elegir "¿Qué plan de Microsoft 365 tienes? (en Excel: Archivo → Cuenta)" \
        "Microsoft 365 Apps para empresas (Business Standard/Premium)" \
        "Microsoft 365 Apps para grandes empresas (E3/E5) o educación (A3/A5)")" in
    1) PRODUCTO=O365BusinessRetail ;;
    *) PRODUCTO=O365ProPlusRetail ;;
esac

paso "Apps"
info "Siempre se instalan Word, Excel y PowerPoint."
mapfile -t OPC_OFFICE < <(catalogo | awk -F'|' '$3 == "office" && $1 !~ /^(word|excel|ppt)$/ { print $1 "|" $2 }')
mapfile -t OPC_WINDOWS < <(catalogo | awk -F'|' '$3 == "windows" { print $1 "|" $2 }')
EXTRA_OFFICE="$(elegir_varios "¿Otras apps de Office? (se instalan en Windows)" "${OPC_OFFICE[@]}")"
EXTRA_WINDOWS="$(elegir_varios "¿Apps de Windows para el menú y la ScreenPad?" "${OPC_WINDOWS[@]}")"
APPS_ELEGIDAS="$(echo word excel ppt $EXTRA_OFFICE $EXTRA_WINDOWS)"
OFFICE_APPS="Word Excel PowerPoint"
for clave in $EXTRA_OFFICE; do
    OFFICE_APPS="$OFFICE_APPS $(catalogo | awk -F'|' -v c="$clave" '$1 == c { print $5 }')"
done

paso "Panel de Windows"
if [ -d "$HOME/.local/share/glasspad" ] || command -v glasspad-launcher >/dev/null; then
    info "Tienes GlassPad: el panel ya está en la ScreenPad (página Windows)."
    PANEL_DEF=n
else
    PANEL_DEF=s
fi
PANEL=0
[ "$(preguntar "¿Agregar también el Panel de Windows al menú? (ventana con estado, apps y botones) (s/n)" "$PANEL_DEF")" = s ] && PANEL=1

paso "Recursos para Windows"
RAM_TOTAL_GB=$(( $(awk '/MemTotal/ { print $2 }' /proc/meminfo) / 1048576 ))
RAM_DEF=$(( RAM_TOTAL_GB * 2 / 5 )); [ "$RAM_DEF" -gt 6 ] && RAM_DEF=6; [ "$RAM_DEF" -lt 4 ] && RAM_DEF=4
NUCLEOS_DEF=$(( $(nproc) / 2 )); [ "$NUCLEOS_DEF" -gt 4 ] && NUCLEOS_DEF=4; [ "$NUCLEOS_DEF" -lt 2 ] && NUCLEOS_DEF=2
info "Tu equipo: ${RAM_TOTAL_GB} GB de RAM y $(nproc) hilos de CPU. Windows solo los usa mientras está encendido."
RAM_GB="$(preguntar "RAM para Windows en GB (mínimo 4)" "$RAM_DEF")"
NUCLEOS="$(preguntar "Núcleos de CPU para Windows" "$NUCLEOS_DEF")"
[[ "$RAM_GB" =~ ^[0-9]+$ ]] && [ "$RAM_GB" -ge 4 ] || morir "la RAM debe ser un número de GB, 4 o más."
[[ "$NUCLEOS" =~ ^[0-9]+$ ]] && [ "$NUCLEOS" -ge 1 ] || morir "los núcleos deben ser un número."

paso "Imagen de Windows 11 (ISO)"

# describe una ISO oficial de Windows por su etiqueta (CCCOMA_X64FRE_ES-MX_DV9) y su nombre;
# no imprime nada si no es una ISO oficial de Windows
describir_iso() {
    local iso="$1" etiqueta idioma version arq
    etiqueta="$(blkid -o value -s LABEL "$iso" 2>/dev/null)"
    [[ "$etiqueta" =~ ^(CCCOMA|CCSA|CPBA|CENA|J_CCSA)_([A-Z0-9]+)FRE_([A-Za-z]{2}-[A-Za-z]{2}) ]] || return 1
    arq="${BASH_REMATCH[2]}"; idioma="${BASH_REMATCH[3]^^}"
    [ "$arq" = X64 ] || return 1
    case "$idioma" in
        ES-MX) idioma="español (México)" ;; ES-ES) idioma="español (España)" ;;
        EN-US) idioma="inglés (EE. UU.)" ;; EN-GB) idioma="inglés (Reino Unido)" ;;
        PT-BR) idioma="portugués (Brasil)" ;; PT-PT) idioma="portugués (Portugal)" ;;
        FR-FR) idioma="francés" ;; DE-DE) idioma="alemán" ;; IT-IT) idioma="italiano" ;;
    esac
    case "$(basename "$iso")" in
        *11*) version="Windows 11" ;;
        *10*) version="Windows 10 (no recomendado)" ;;
        *) version="Windows (versión no indicada en el nombre)" ;;
    esac
    echo "$version · $idioma · 64 bits · $(du -h "$iso" | cut -f1)"
}

# pendrives conectados pero sin montar: se montan como lo haría el gestor de archivos
montar_pendrives() {
    command -v udisksctl >/dev/null || return 0
    while read -r dev rm tam fs punto; do
        [ "$rm" = 1 ] && [ -z "$punto" ] && [ "$tam" -ge 1073741824 ] &&
            [[ "$fs" =~ ^(vfat|exfat|ntfs|ext4)$ ]] &&
            udisksctl mount -b "/dev/$dev" --no-user-interaction >/dev/null 2>&1 &&
            info "Pendrive /dev/$dev montado para buscar la ISO."
    done < <(lsblk -brno NAME,HOTPLUG,SIZE,FSTYPE,MOUNTPOINT 2>/dev/null)
    return 0
}

# busca ISO oficiales de Windows en las carpetas dadas y deja elegir; ISO="" si no hay
buscar_iso() {
    local isos=() opciones=() iso d otras=0 n
    while IFS= read -r iso; do
        if d="$(describir_iso "$iso")"; then
            isos+=("$iso"); opciones+=("$(basename "$iso") — $d")
        else
            otras=$((otras + 1))
        fi
    done < <(find "$@" -maxdepth 3 -type f -iname '*.iso' 2>/dev/null | sort -u)
    if [ "$otras" -gt 0 ]; then info "Se ignoraron $otras ISO que no son de Windows oficial de 64 bits."; fi
    case ${#isos[@]} in
        0) info "No encontré ISO oficiales de Windows ahí."; ISO="" ;;
        1) info "Encontré: ${opciones[0]}"
           info "En: ${isos[0]}"
           if [ "$(preguntar "¿Usar esta ISO? (s/n)" "s")" = s ]; then ISO="${isos[0]}"; else ISO=""; fi ;;
        *) n="$(elegir "Encontré ${#isos[@]} ISO de Windows. ¿Cuál usar?" "${opciones[@]}")"
           ISO="${isos[$((n - 1))]}"
           info "En: $ISO" ;;
    esac
}

ISO=""
while [ -z "$ISO" ]; do
    case "$(elegir "¿De dónde sale Windows?" \
            "Buscar una ISO en Descargas, Documentos, Escritorio y pendrives (recomendado)" \
            "Indicar la ruta de una ISO o de una carpeta donde buscar" \
            "Descargarla de Microsoft durante la instalación (~6 GB; puede quedar en inglés)")" in
        1)  montar_pendrives
            CARPETAS_ISO=()
            for c in "$(xdg-user-dir DOWNLOAD 2>/dev/null || true)" "$(xdg-user-dir DOCUMENTS 2>/dev/null || true)" \
                     "$(xdg-user-dir DESKTOP 2>/dev/null || true)" "$HOME/Descargas" "$HOME/Downloads" \
                     "$HOME/Documentos" "$HOME/Documents" "$HOME/Escritorio" "$HOME/Desktop" /run/media/"$USER"/*; do
                [ -n "$c" ] && [ -d "$c" ] && [ "$c" != "$HOME" ] && CARPETAS_ISO+=("$c")
            done
            buscar_iso "${CARPETAS_ISO[@]}" ;;
        2)  r="$(preguntar "Ruta de la ISO o de una carpeta" "")"
            r="${r/#\~/$HOME}"
            if [ -d "$r" ]; then
                buscar_iso "$r"
            elif [ -f "$r" ]; then
                if d="$(describir_iso "$r")"; then
                    info "$d"; ISO="$r"
                else
                    info "Esa ISO no parece un Windows oficial de 64 bits."
                    [ "$(preguntar "¿Usarla igual? (s/n)" "n")" = s ] && ISO="$r"
                fi
            else
                info "No existe: $r"
            fi ;;
        *)  ISO="descargar" ;;
    esac
done
[ "$ISO" = descargar ] && ISO=""

# idioma y teclado según el sistema
LOCAL="${LANG%%.*}"
REGION="${LOCAL/_/-}"; [ -n "$REGION" ] && [ "$REGION" != C ] || REGION="es-ES"
TECLADO="$(preguntar "Distribución de teclado para Windows (es-ES, es-MX, en-US…)" \
    "$( [ "${REGION#es-}" != "$REGION" ] && [ "$REGION" != es-ES ] && echo es-MX || echo "$REGION")")"

paso "Resumen"
info "Cliente:        $CLIENTE"
info "Office:         $OFFICE_APPS ($PRODUCTO)"
info "Apps en menú:   $APPS_ELEGIDAS"
info "Panel en menú:  $([ "$PANEL" = 1 ] && echo sí || echo no)"
info "Windows:        ${RAM_GB} GB de RAM, $NUCLEOS núcleos, disco de hasta 64 GB"
info "ISO:            ${ISO:-descargar de Microsoft}"
info "Región/teclado: $REGION / $TECLADO"
[ "$(preguntar "¿Continuar? (s/n)" "s")" = s ] || morir "cancelado."

# ----- paquetes del sistema -------------------------------------------------------------------

instalar_paquetes() {
    local pm
    for pm in pacman apt-get dnf zypper; do command -v "$pm" >/dev/null && break; done
    case "$pm" in
        pacman) sudo pacman -S --needed docker docker-compose freerdp flatpak git python \
                    openbsd-netcat curl xdg-utils ;;
        apt-get) sudo apt-get update
                 sudo apt-get install -y docker.io docker-compose-v2 freerdp3-x11 flatpak git \
                    python3 netcat-openbsd curl xdg-utils ;;
        dnf) sudo dnf install -y moby-engine docker-compose freerdp flatpak git python3 \
                 nmap-ncat curl xdg-utils ;;
        zypper) sudo zypper install -y docker docker-compose freerdp flatpak git python3 \
                    netcat-openbsd curl xdg-utils ;;
        *) morir "no reconozco el gestor de paquetes; instala a mano: docker, docker compose, FreeRDP 3, flatpak, git, python3, netcat, curl." ;;
    esac
    sudo systemctl enable --now docker
    if ! id -nG | tr ' ' '\n' | grep -qx docker; then
        sudo usermod -aG docker "$USER"
        info "Te agregué al grupo docker; el resto se ejecuta con ese grupo (al reiniciar sesión ya es permanente)."
    fi
}

# docker con el grupo recién agregado sin cerrar sesión
dk() {
    if docker info >/dev/null 2>&1; then docker "$@"
    else sg docker -c "$(printf '%q ' docker "$@")"; fi
}

if [ "$SIMULAR" = 0 ]; then
    paso "Paquetes del sistema (pide tu contraseña de sudo)"
    instalar_paquetes
fi

# ----- archivos de configuración -----------------------------------------------------------------

paso "Configuración"
mkdir -p "$CONF_DIR" "$DATOS" "$ICONOS" "$ESTADO"
if [ -d "$DATOS/winapps/.git" ]; then
    git -C "$DATOS/winapps" pull -q --ff-only || true
elif [ "$SIMULAR" = 0 ] || command -v git >/dev/null; then
    git clone -q --depth 1 "$WINAPPS_GIT" "$DATOS/winapps"
fi
info "WinApps (archivos de preparación de Windows e íconos): $DATOS/winapps"

CLAVE_RDP="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 20 || true)"
umask 077
cat >"$CONF_DIR/winapps.conf" <<EOF
RDP_USER="$USER"
RDP_PASS="$CLAVE_RDP"
RDP_DOMAIN=""
RDP_IP="127.0.0.1"
RDP_PORT="3389"
WAFLAVOR="docker"
RDP_SCALE="100"
RDP_FLAGS="/cert:tofu /sound /microphone +home-drive -gfx"
FREERDP_COMMAND="xfreerdp3"
EOF
cat >"$CONF_DIR/win.conf" <<EOF
APPS_ELEGIDAS="$APPS_ELEGIDAS"
OFFICE_APPS="$OFFICE_APPS"
OFFICE_PRODUCTO="$PRODUCTO"
CLIENTE_RDP=$CLIENTE
AUTO_APAGADO=0
PANEL=$PANEL
EOF
umask 022

# preparación de Windows: la de WinApps (escritorio remoto para apps sueltas) más Office
OEM="$DATOS/oem"
rm -rf "$OEM"; mkdir -p "$OEM"
cp "$DATOS/winapps/oem/"* "$OEM/"
cp "$DIR/windows/office.ps1" "$OEM/office.ps1"
MARCA_WIN='\\host.lan\Data'"${ESTADO#"$BASE"}"'\office.txt'
MARCA_WIN="${MARCA_WIN//\//\\}"
cat >>"$OEM/install.bat" <<EOF

:: win-control: Office (solo las apps elegidas); el resultado queda en ~/.local/state/win/office.txt
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0office.ps1" -Apps "$OFFICE_APPS" -Producto $PRODUCTO -Marca "$MARCA_WIN"
EOF
sed -i 's/\r*$/\r/' "$OEM/install.bat"
info "Preparación de Windows: $OEM"

ISO_LINEA="#"
[ -n "$ISO" ] && ISO_LINEA="      - $ISO:/custom.iso"
cat >"$CONF_DIR/compose.yaml" <<EOF
# generado por win-control (instalar-todo.sh)
name: "winapps"
volumes:
  data:
services:
  windows:
    image: ghcr.io/dockur/windows:latest
    container_name: WinApps
    environment:
      VERSION: "11"
      RAM_SIZE: "${RAM_GB}G"
      CPU_CORES: "$NUCLEOS"
      DISK_SIZE: "64G"
      USERNAME: "$USER"
      PASSWORD: "$CLAVE_RDP"
      LANGUAGE: "Spanish"
      REGION: "$REGION"
      KEYBOARD: "$TECLADO"
      HOME: "\${HOME}"
    ports:
      - "127.0.0.1:8006:8006"
      - "127.0.0.1:3389:3389/tcp"
      - "127.0.0.1:3389:3389/udp"
    cap_add:
      - NET_ADMIN
      - NET_RAW
    stop_grace_period: 120s
    restart: on-failure
    volumes:
      - data:/storage
      - \${HOME}:/shared
      - $OEM:/oem
$ISO_LINEA
    devices:
      - /dev/kvm
      - /dev/net/tun
EOF
chmod 600 "$CONF_DIR/compose.yaml"
info "Contenedor: $CONF_DIR/compose.yaml"

for clave in $(catalogo | cut -d'|' -f1); do
    icono="$(catalogo | awk -F'|' -v c="$clave" '$1 == c { print $6 }')"
    [ -f "$DATOS/winapps/apps/$icono/icon.svg" ] && cp "$DATOS/winapps/apps/$icono/icon.svg" "$ICONOS/$clave.svg"
done
rm -f "$ESTADO/office.txt"

if [ "$SIMULAR" = 1 ]; then
    paso "Simulación lista"
    info "Revisa lo generado en: $BASE"
    exit 0
fi

# ----- Windows ---------------------------------------------------------------------------

paso "Instalando Windows (automático; 20 a 40 minutos)"
info "Puedes mirar el avance en http://127.0.0.1:8006 — no hace falta tocar nada."
dk compose -f "$CONF_DIR/compose.yaml" up -d
t=0
until [ -f "$ESTADO/office.txt" ]; do
    sleep 20; t=$((t + 20))
    printf '\r   %d min… %s\033[K' $((t / 60)) "$(dk logs --tail 1 WinApps 2>&1 | tr -d '\r' | cut -c1-70)"
    [ "$t" -ge 7200 ] && { echo; morir "pasaron 2 horas sin terminar; revisa http://127.0.0.1:8006"; }
done
echo
# la ISO solo hace falta para instalar: sin esto, Windows no arrancaría si la ISO (o el
# pendrive donde está) ya no está disponible
if [ -n "$ISO" ]; then
    sed -i '\|:/custom.iso|d' "$CONF_DIR/compose.yaml"
    dk compose -f "$CONF_DIR/compose.yaml" up -d >/dev/null 2>&1
    info "La ISO ya no hace falta: puedes guardar o borrar $ISO"
fi
if grep -q '^ok' "$ESTADO/office.txt"; then
    info "Windows y Office instalados."
else
    info "Windows quedó instalado, pero Office falló: $(cat "$ESTADO/office.txt")"
    info "Puedes reintentar después con: win agregar-app word"
fi

# ----- Linux: win, complemento, Thincast ------------------------------------------------------

paso "win, menú y ScreenPad"
if [ "$CLIENTE" = thincast ]; then
    flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    flatpak install --user -y --noninteractive flathub "$THINCAST"
fi
"$DIR/install.sh"
"$HOME/.local/bin/win" cliente "$CLIENTE" >/dev/null
"$HOME/.local/bin/win" _accesos

paso "Listo"
info "Abre Word (menú, ScreenPad o: win word) e inicia sesión con tu cuenta de Microsoft 365."
info "Ese es el único paso que falta: activa la licencia de Office."
info "Comandos: win (estado) · win on/off · win apps-disponibles · win log"
