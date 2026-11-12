# Windows - enciende, apaga y abre Office del Windows de WinApps (complemento de GlassPad)
# kan0p - https://github.com/kan0p/win-control - GPL-3.0-or-later
import os

from gi.repository import Gio, GLib, Gtk

NOMBRE = "Windows"
ICONO = "icono.svg"

WIN = os.path.expanduser("~/.local/bin/win")
ICONOS_APPS = os.path.expanduser("~/.local/share/winapps/apps")
APPS = [("word", "Word", "word-o365", "WINWORD"), ("excel", "Excel", "excel-o365", "EXCEL"),
        ("ppt", "PowerPoint", "powerpoint-o365", "POWERPNT")]
ICONO_DE = {proc: carpeta for _, _, carpeta, proc in APPS}
PAGINAS = [("lanzador", "Lanzador"), ("ventanas", "Ventanas"), ("windows", "Windows")]
AUTO = [(0, "No"), (15, "15 min"), (30, "30 min"), (60, "1 h")]
REFRESCO_MS = 3000
REFRESCO_CARGA_MS = 1000
DOBLE_MS = 450
ESTADOS = {"encendido": "Encendido", "arrancando": "Arrancando…", "pausado": "Pausado",
           "apagado": "Apagado", "ausente": "No instalado", "apagando": "Apagando…",
           "reiniciando": "Reiniciando…"}
PRENDIDO = ("encendido", "arrancando", "pausado", "apagando", "reiniciando")
OCUPADO = ("arrancando", "apagando", "reiniciando")

CSS = """
.win { margin: 28px 60px 24px 60px; }
.win-punto { min-width: 24px; min-height: 24px; border-radius: 12px; background: #8a93a6; }
.win-punto.encendido { background: #3ddc84; }
.win-punto.arrancando, .win-punto.pausado, .win-punto.apagando, .win-punto.reiniciando {
    background: #ffd23f; }
.win-punto.ausente { background: #e5484d; }
.win-estado { font-size: 28px; font-weight: 600; }
.win-gris { font-size: 26px; color: alpha(white, 0.6); }
.win-alerta { font-size: 26px; color: #ffb4ad; }
.win-segmentos { background: alpha(black, 0.35); border-radius: 30px; padding: 6px; }
.win-pestana { background: transparent; border: none; box-shadow: none;
               outline: none; border-radius: 24px; color: alpha(white, 0.7); font-size: 28px;
               font-weight: 600; min-height: 70px; padding: 0 40px; }
.win-pestana.elegida { background: alpha(#6aa8ff, 0.3); color: white; }
.win-pestana.presionado { background: alpha(white, 0.25); }
.win-app { background: alpha(black, 0.42); border: 2px solid alpha(white, 0.1);
           box-shadow: none; outline: none; border-radius: 44px; color: white; padding: 24px; }
.win-app.presionado { background: alpha(white, 0.2); }
.win-app.cargando { border-color: alpha(#6aa8ff, 0.8); }
.win-app.fallo { border-color: alpha(#e5484d, 0.8); }
.win-app .nombre { font-size: 40px; font-weight: 600; }
.win-app .etapa { font-size: 26px; color: alpha(white, 0.75); }
.win-app.fallo .etapa { color: #ffb4ad; }
.win-fila { background: alpha(black, 0.38); border-radius: 30px; padding: 14px 16px 14px 28px; }
.win-fila-nombre { font-size: 34px; font-weight: 600; }
.win-boton { background: alpha(black, 0.4); border: 1px solid alpha(white, 0.14);
             box-shadow: none; outline: none; border-radius: 28px; color: white;
             font-size: 30px; min-height: 120px; padding: 0 30px; }
.win-boton.presionado { background: alpha(white, 0.25); }
.win-boton.peligro { background: alpha(#e5484d, 0.3); color: #ffd0cc; }
.win-boton.chico { min-height: 80px; font-size: 27px; padding: 0 26px; }
.win-boton.inactivo { opacity: 0.4; }
.win-chip { background: alpha(white, 0.08); border: 2px solid transparent; box-shadow: none;
            outline: none; border-radius: 24px; color: white; font-size: 26px;
            min-height: 80px; padding: 0 30px; }
.win-chip.elegido { border-color: #6aa8ff; background: alpha(#6aa8ff, 0.2); }
.win-chip.presionado { background: alpha(white, 0.25); }
.win-tarjeta { background: alpha(black, 0.38); border-radius: 30px; padding: 18px 28px; }
.win-tarjeta .titulo { font-size: 22px; color: alpha(white, 0.6); }
.win-tarjeta .valor { font-size: 40px; font-weight: 700; }
.win-medidor trough { min-height: 10px; border-radius: 5px; background: alpha(white, 0.12); }
.win-medidor progress { min-height: 10px; border-radius: 5px; background: #6aa8ff; }
.win-medidor.alto progress { background: #ffb347; }
.win-grilla .win-boton { min-height: 116px; }
.win-boton .icono-boton { opacity: 0.9; }
.win-confirmar { background: #2a1416; border: 2px solid alpha(#e5484d, 0.6);
                 border-radius: 30px; padding: 16px 16px 16px 32px; }
.win-confirmar-texto { font-size: 28px; font-weight: 600; color: #ffd0cc; }
"""


def crear(api):
    api.css(CSS)
    estado = {"e": "apagado", "apps": 0, "auto": 0, "agente": True, "orden": False, "escritorio": False,
              "ram": 0, "pagina": 0}
    reloj = [0]
    reloj_carga = [0]
    toques = {}
    confirmacion = {"si": None}
    ventanas = []           # títulos de las ventanas visibles de la sesión
    mosaicos = {}           # clave -> (botón, ruedita, etiqueta de etapa)
    cargando = {}           # clave -> {"nombre", "base", "inicio", "limite"}
    firma = [None]

    def clase(w, nombre, si):
        (w.add_css_class if si else w.remove_css_class)(nombre)

    def correr(args, despues=None):
        try:
            lanzador = Gio.SubprocessLauncher.new(Gio.SubprocessFlags.STDOUT_PIPE
                                                  | Gio.SubprocessFlags.STDERR_MERGE)
            lanzador.setenv("WIN_GLASSPAD", "1", True)
            p = lanzador.spawnv([WIN, *args])
        except GLib.Error as e:
            api.avisar("No se pudo ejecutar win: " + e.message)
            return

        def fin(proc, res):
            try:
                _, salida, _ = proc.communicate_utf8_finish(res)
            except GLib.Error as e:
                salida = e.message
            if despues:
                despues(proc.get_successful(), (salida or "").strip())
        p.communicate_utf8_async(None, None, fin)

    def ultima(salida, defecto="Listo."):
        lineas = [l for l in salida.splitlines() if l.strip()]
        return lineas[-1] if lineas else defecto

    # un toque: al_tocar tras DOBLE_MS; dos toques seguidos: al_doble (y no al_tocar)
    def doble(clave, al_tocar, al_doble):
        def tocar():
            pendiente = toques.pop(clave, None)
            if pendiente:
                GLib.source_remove(pendiente)
                al_doble()
                return

            def simple():
                toques.pop(clave, None)
                al_tocar()
                return False
            toques[clave] = GLib.timeout_add(DOBLE_MS, simple)
        return tocar

    # ----- marco: cabecera, pestañas y confirmación ---------------------------

    raiz = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=22, css_classes=["win"])

    cabeza = Gtk.Box(spacing=16)
    segmentos = Gtk.Box(spacing=4, css_classes=["win-segmentos"])
    pestanas = []
    for i, (_, texto) in enumerate(PAGINAS):
        b = api.accion(Gtk.Button(label=texto, css_classes=["win-pestana"]),
                       lambda n=i: ir(n))
        pestanas.append(b)
        segmentos.append(b)
    cabeza.append(segmentos)
    cabeza.append(Gtk.Box(hexpand=True))
    punto = Gtk.Box(css_classes=["win-punto"], valign=Gtk.Align.CENTER)
    texto_estado = Gtk.Label(css_classes=["win-estado"])
    cabeza.append(punto)
    cabeza.append(texto_estado)
    raiz.append(cabeza)

    confirmar_caja = Gtk.Box(spacing=18, css_classes=["win-confirmar"], visible=False)
    confirmar_texto = Gtk.Label(css_classes=["win-confirmar-texto"], xalign=0, hexpand=True,
                                wrap=True)
    confirmar_caja.append(confirmar_texto)

    def responder(si):
        accion = confirmacion["si"]
        confirmacion["si"] = None
        confirmar_caja.set_visible(False)
        if si and accion:
            accion()

    confirmar_si = Gtk.Button(label="Forzar", css_classes=["win-boton", "peligro", "chico"])
    confirmar_caja.append(api.accion(confirmar_si, lambda: responder(True)))
    confirmar_caja.append(api.accion(
        Gtk.Button(label="Cancelar", css_classes=["win-boton", "chico"]),
        lambda: responder(False)))
    raiz.append(confirmar_caja)

    def preguntar(texto, accion, etiqueta="Forzar"):
        confirmacion["si"] = accion
        confirmar_si.set_label(etiqueta)
        confirmar_texto.set_label(texto)
        confirmar_caja.set_visible(True)

    paginas = Gtk.Stack(vexpand=True, transition_duration=220,
                        transition_type=Gtk.StackTransitionType.SLIDE_LEFT_RIGHT)
    raiz.append(paginas)

    def ir(n):
        n = max(0, min(len(PAGINAS) - 1, n))
        estado["pagina"] = n
        paginas.set_visible_child_name(PAGINAS[n][0])
        for i, b in enumerate(pestanas):
            clase(b, "elegida", i == n)

    # deslizar el dedo en horizontal cambia de página (launcher con api.al_deslizar)
    if hasattr(api, "al_deslizar"):
        api.al_deslizar(lambda hacia: ir(estado["pagina"] + hacia))

    # ----- página Lanzador ----------------------------------------------------

    lanzador_caja = Gtk.Box(spacing=30, homogeneous=True)
    for clave, nombre, carpeta, _ in APPS:
        caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=22,
                       valign=Gtk.Align.CENTER)
        caja.append(Gtk.Image(file=os.path.join(ICONOS_APPS, carpeta, "icon.svg"),
                              pixel_size=220))
        caja.append(Gtk.Label(label=nombre, css_classes=["nombre"]))
        abajo = Gtk.Box(spacing=12, halign=Gtk.Align.CENTER)
        ruedita = Gtk.Spinner(visible=False)
        ruedita.set_size_request(30, 30)
        etapa = Gtk.Label(css_classes=["etapa"], visible=False, wrap=True,
                          justify=Gtk.Justification.CENTER)
        abajo.append(ruedita)
        abajo.append(etapa)
        caja.append(abajo)
        b = api.accion(Gtk.Button(child=caja, css_classes=["win-app"]),
                       lambda c=clave, n=nombre: abrir(c, n))
        mosaicos[clave] = (b, ruedita, etapa)
        lanzador_caja.append(b)
    paginas.add_named(lanzador_caja, "lanzador")

    # ----- página Ventanas ----------------------------------------------------

    ventanas_caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
    ventanas_caja.append(Gtk.Label(
        label="Un toque en Cerrar la cierra normal; dos toques preguntan si forzar.",
        css_classes=["win-gris"], xalign=0))
    lista = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
    ventanas_caja.append(Gtk.ScrolledWindow(child=lista, vexpand=True,
                                            hscrollbar_policy=Gtk.PolicyType.NEVER))
    paginas.add_named(ventanas_caja, "ventanas")

    # ----- página Windows -----------------------------------------------------

    windows_caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=22)

    def tarjeta(titulo):
        caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8,
                       css_classes=["win-tarjeta"], hexpand=True)
        caja.append(Gtk.Label(label=titulo, css_classes=["titulo"], xalign=0))
        valor = Gtk.Label(css_classes=["valor"], xalign=0)
        caja.append(valor)
        return caja, valor

    tarjetas = Gtk.Box(spacing=22, homogeneous=True)
    caja_cpu, dato_cpu = tarjeta("CPU de Windows")
    medidor_cpu = Gtk.ProgressBar(css_classes=["win-medidor"])
    caja_cpu.append(medidor_cpu)
    caja_ram, dato_ram = tarjeta("RAM")
    caja_apps, dato_apps = tarjeta("Apps abiertas")
    for c in (caja_cpu, caja_ram, caja_apps):
        tarjetas.append(c)
    windows_caja.append(tarjetas)
    detalle = Gtk.Label(css_classes=["win-gris"], xalign=0, wrap=True)
    windows_caja.append(detalle)

    grilla = Gtk.Grid(column_spacing=22, row_spacing=22, column_homogeneous=True,
                      row_homogeneous=True, vexpand=True, css_classes=["win-grilla"])

    def boton(texto, icono, al_tocar, columna, fila, clases=()):
        hijo = Gtk.Box(spacing=16, halign=Gtk.Align.CENTER)
        imagen = Gtk.Image(icon_name=icono, pixel_size=40, css_classes=["icono-boton"])
        etiqueta = Gtk.Label(label=texto)
        hijo.append(imagen)
        hijo.append(etiqueta)
        b = api.accion(Gtk.Button(child=hijo, css_classes=["win-boton", *clases]), al_tocar)
        b.imagen, b.etiqueta = imagen, etiqueta
        grilla.attach(b, columna, fila, 1, 1)
        return b

    b_on = boton("Encender", "system-shutdown-symbolic", lambda: encender(), 0, 0)
    b_off = boton("Apagar", "system-shutdown-symbolic",
                  doble("off", lambda: apagar(False), lambda: apagar(True)), 1, 0, ("peligro",))
    b_reiniciar = boton("Reiniciar", "system-reboot-symbolic",
                        doble("restart", lambda: reiniciar(False), lambda: reiniciar(True)), 2, 0)
    b_escritorio = boton("Escritorio", "video-display-symbolic", lambda: escritorio(), 0, 1)
    b_rescatar = boton("Rescatar", "edit-undo-symbolic", lambda: rescatar(), 1, 1)
    b_reparar = boton("Reparar", "applications-system-symbolic", lambda: reparar(), 2, 1,
                      ("peligro",))
    windows_caja.append(grilla)

    fila_auto = Gtk.Box(spacing=16)
    fila_auto.append(Gtk.Label(label="Apagar solo si no lo uso:", css_classes=["win-gris"],
                               xalign=0, hexpand=True))
    chips = {}
    for minutos, texto in AUTO:
        chips[minutos] = api.accion(Gtk.Button(label=texto, css_classes=["win-chip"]),
                                    lambda m=minutos: poner_auto(m))
        fila_auto.append(chips[minutos])
    windows_caja.append(fila_auto)
    paginas.add_named(windows_caja, "windows")

    # ----- carga de apps --------------------------------------------------------

    def contar(nombre):
        # "Word", "Documento1 - Word" o "Microsoft Word" (mientras arranca)
        return sum(1 for t in ventanas if t == nombre or t.endswith(" " + nombre))

    def mostrar_carga(clave, texto, modo):
        b, ruedita, etapa = mosaicos[clave]
        clase(b, "cargando", modo == "cargando")
        clase(b, "fallo", modo == "fallo")
        ruedita.set_visible(modo == "cargando")
        ruedita.set_spinning(modo == "cargando")
        etapa.set_visible(bool(texto))
        etapa.set_label(texto or "")

    def terminar_carga(clave, texto, modo, ms):
        cargando.pop(clave, None)
        mostrar_carga(clave, texto, modo)

        def limpiar():
            if clave not in cargando:
                mostrar_carga(clave, "", "")
            return False
        GLib.timeout_add(ms, limpiar)
        if not cargando and reloj_carga[0]:
            GLib.source_remove(reloj_carga[0])
            reloj_carga[0] = 0

    def revisar_cargas():
        ahora = GLib.get_monotonic_time() / 1e6
        for clave, c in list(cargando.items()):
            # con la app ya abierta, Office puede reutilizar su ventana en vez de abrir otra
            if contar(c["nombre"]) > c["base"] or (c["base"] and ahora - c["inicio"] >= 6):
                terminar_carga(clave, "¡Lista!", "", 2500)
            elif ahora - c["inicio"] > c["limite"]:
                terminar_carga(clave, "No se abrió. Toca para reintentar.", "fallo", 8000)
            elif estado["e"] in ("apagado", "arrancando"):
                mostrar_carga(clave, "Encendiendo Windows…", "cargando")
            else:
                mostrar_carga(clave, f"Abriendo {c['nombre']}…", "cargando")

    # ----- estado ---------------------------------------------------------------

    def mostrar(e, ram, apps, auto, agente, cpu=0, esc=False):
        estado.update(e=e, apps=apps, auto=auto, agente=agente, ram=ram, escritorio=esc)
        texto_estado.set_label(ESTADOS.get(e, e))
        punto.set_css_classes(["win-punto", e])
        prendido = e in PRENDIDO
        dato_cpu.set_label(f"{cpu} %" if prendido else "—")
        medidor_cpu.set_fraction(min(cpu, 100) / 100 if prendido else 0)
        clase(medidor_cpu, "alto", cpu >= 70)
        dato_ram.set_label(f"{ram / 1024:.1f} GB".replace(".", ",") if prendido and ram
                           else "Libre")
        dato_apps.set_label(str(apps))
        if not agente:
            detalle.set_label("Windows no responde. Toca Rescatar para recuperar tus apps "
                              "sin perder nada, o Reparar para reiniciarlo.")
            detalle.set_css_classes(["win-alerta"])
        else:
            detalle.set_css_classes(["win-gris"])
            detalle.set_label({
                "apagado": "Apagado: no usa RAM. Toca una app en Lanzador para encenderlo.",
                "ausente": "No se encontró el contenedor WinApps.",
            }.get(e, "Apagar y Reiniciar: un toque cierra las apps de forma normal; "
                     "dos toques preguntan si forzar."))
        ocupado_ = e in OCUPADO or estado["orden"]
        clase(b_on, "inactivo", prendido or ocupado_)
        clase(b_off, "inactivo", not prendido or e == "apagando")
        clase(b_reiniciar, "inactivo", not prendido or e in ("apagando", "reiniciando"))
        # con un escritorio abierto el mismo botón lo desconecta
        b_escritorio.etiqueta.set_label("Desconectar" if esc else "Escritorio")
        b_escritorio.imagen.set_from_icon_name("network-offline-symbolic" if esc
                                               else "video-display-symbolic")
        clase(b_escritorio, "inactivo", (ocupado_ or apps > 0) and not esc)
        clase(b_rescatar, "inactivo", apps == 0 or ocupado_ or esc)
        clase(b_reparar, "inactivo", not prendido or ocupado_)
        for m, chip in chips.items():
            clase(chip, "elegido", m == auto)

    def mostrar_abiertas(apps):
        nueva = tuple(apps)
        if nueva == firma[0]:
            return
        firma[0] = nueva
        api.vaciar(lista)
        if not apps:
            lista.append(Gtk.Label(label="Ninguna app abierta.", css_classes=["win-gris"],
                                   xalign=0))
            return
        for proc, nombre in nueva:
            fila = Gtk.Box(spacing=22, css_classes=["win-fila"])
            carpeta = ICONO_DE.get(proc)
            if carpeta:
                fila.append(Gtk.Image(file=os.path.join(ICONOS_APPS, carpeta, "icon.svg"),
                                      pixel_size=72))
            fila.append(Gtk.Label(label=nombre, css_classes=["win-fila-nombre"], xalign=0,
                                  hexpand=True))
            fila.append(api.accion(
                Gtk.Button(label="Maximizar", css_classes=["win-boton", "chico"]),
                lambda p=proc, n=nombre: maximizar(p, n)))
            fila.append(api.accion(
                Gtk.Button(label="Cerrar", css_classes=["win-boton", "peligro", "chico"]),
                doble("cerrar-" + proc, lambda p=proc, n=nombre: cerrar(p, n, False),
                      lambda p=proc, n=nombre: cerrar(p, n, True))))
            lista.append(fila)

    def refrescar():
        def listo(ok, salida):
            lineas = salida.splitlines()
            partes = lineas[0].split() if lineas else []
            if not ok or len(partes) not in (5, 6, 7):
                return
            e, ram, apps, auto, agente = partes[:5]
            cpu = int(partes[5]) if len(partes) >= 6 and partes[5].isdigit() else 0
            esc = len(partes) == 7 and partes[6] == "1"
            mostrar(e, int(ram or 0), int(apps or 0), int(auto or 0), agente == "1", cpu, esc)
            ventanas[:] = [l[8:] for l in lineas[1:] if l.startswith("ventana|")]
            mostrar_abiertas([tuple(l.split("|", 1)) for l in lineas[1:]
                              if "|" in l and not l.startswith("ventana|")])
            revisar_cargas()
        correr(["_corto"], listo)

    # ----- órdenes ----------------------------------------------------------------

    def orden(args, aviso=None):
        estado["orden"] = True
        if aviso:
            api.avisar(aviso)

        def listo(ok, salida):
            estado["orden"] = False
            if not ok and salida:
                api.avisar(ultima(salida))
            refrescar()
        correr(args, listo)
        GLib.timeout_add(600, lambda: refrescar() and False)

    def ocupado(aviso=True):
        e = estado["e"]
        if e in ("apagando", "reiniciando") or estado["orden"]:
            if aviso:
                api.avisar("Espera: Windows está " + {"apagando": "apagándose",
                           "reiniciando": "reiniciándose"}.get(e, "ocupado") + ".")
            return True
        return False

    def encender():
        if estado["e"] in PRENDIDO:
            api.avisar("Windows ya está encendido." if estado["e"] == "encendido"
                       else "Espera: Windows está " + ESTADOS[estado["e"]].lower())
            return
        if ocupado():
            return
        orden(["on"], "Encendiendo Windows…")

    def abrir(clave, nombre):
        if clave in cargando:
            api.avisar(f"{nombre} ya se está abriendo…")
            return
        if ocupado():
            return
        apagado = estado["e"] in ("apagado", "pausado", "arrancando")
        cargando[clave] = {"nombre": nombre, "base": contar(nombre),
                           "inicio": GLib.get_monotonic_time() / 1e6,
                           "limite": 150 if apagado else 75}
        mostrar_carga(clave, "Encendiendo Windows…" if apagado else f"Abriendo {nombre}…",
                      "cargando")
        if not reloj_carga[0]:
            reloj_carga[0] = GLib.timeout_add(REFRESCO_CARGA_MS, lambda: refrescar() or True)

        def listo(ok, salida):
            if not ok:
                terminar_carga(clave, ultima(salida, "No se pudo abrir."), "fallo", 8000)
            refrescar()
        correr([clave], listo)

    def apagar(forzar):
        if estado["e"] not in PRENDIDO:
            api.avisar("Windows ya está apagado.")
            return
        if forzar:
            preguntar("¿Forzar el apagado? Se pierde lo que no hayas guardado.",
                      lambda: orden(["off", "-f"], "Apagando Windows a la fuerza…")
                      if not estado["orden"] else correr(["off", "-f"]))
            return
        if ocupado():
            return
        orden(["off"], "Cerrando las apps y apagando Windows…" if estado["apps"]
              else "Apagando Windows…")

    def reiniciar(forzar):
        if estado["e"] not in PRENDIDO:
            api.avisar("Windows está apagado: usa Encender.")
            return
        if forzar:
            preguntar("¿Forzar el reinicio? Se pierde lo que no hayas guardado.",
                      lambda: orden(["restart", "-f"], "Reiniciando Windows a la fuerza…")
                      if not estado["orden"] else correr(["restart", "-f"]))
            return
        if ocupado():
            return
        orden(["restart"], "Cerrando las apps y reiniciando Windows…" if estado["apps"]
              else "Reiniciando Windows…")

    def escritorio():
        if estado["escritorio"]:
            preguntar("¿Desconectar el escritorio de Windows? Guarda antes tu trabajo: "
                      "Windows se reinicia y se pierde lo que no hayas guardado.",
                      lambda: orden(["desconectar"], "Desconectando el escritorio…"),
                      "Desconectar")
            return
        if estado["apps"]:
            api.avisar("Cierra primero las apps abiertas (página Ventanas).")
            return
        if ocupado():
            return
        api.avisar("Abriendo el escritorio de Windows a pantalla completa…")

        def listo(ok, salida):
            if not ok:
                api.avisar(ultima(salida))
            refrescar()
        # escritorio a pantalla completa (con proyector extendido, en las dos pantallas) donde el
        # lanzador abre las apps; el escritorio en ventana queda en «win escritorio»
        correr(["presentar"], listo)

    def rescatar():
        if not estado["apps"]:
            api.avisar("No hay apps abiertas que rescatar.")
            return
        if ocupado():
            return
        api.avisar("Rescatando: en la ventana de Windows responde «Sí» para tomar la sesión.")

        def listo(ok, salida):
            api.avisar(ultima(salida))
            refrescar()
        correr(["rescatar"], listo)

    def reparar():
        if estado["e"] not in PRENDIDO:
            api.avisar("Windows está apagado: usa Encender.")
            return
        if ocupado():
            return
        preguntar("¿Reparar? Reinicia Windows y cierra todo SIN guardar. Si tus apps "
                  "quedaron congeladas, prueba antes con Rescatar.",
                  lambda: orden(["reparar"], "Reparando: reiniciando Windows…"), "Reparar")

    def maximizar(proc, nombre):
        def listo(ok, salida):
            api.avisar(f"Maximizando {nombre}." if ok else ultima(salida))
        correr(["maximizar", proc], listo)

    def cerrar(proc, nombre, forzar):
        def listo(ok, salida):
            if not ok and salida:
                api.avisar(ultima(salida))
            refrescar()
        if forzar:
            preguntar(f"¿Forzar el cierre de {nombre}? Se pierde lo que no hayas guardado.",
                      lambda: correr(["cerrar", "-f", proc], listo))
            return
        api.avisar(f"Cerrando {nombre}: si hay cambios, Windows pregunta si guardar.")
        correr(["cerrar", proc], listo)

    def poner_auto(minutos):
        def listo(ok, salida):
            api.avisar(ultima(salida))
            refrescar()
        correr(["auto", str(minutos or "off")], listo)

    def visible(si):
        if reloj[0]:
            GLib.source_remove(reloj[0])
            reloj[0] = 0
        if si:
            refrescar()
            reloj[0] = GLib.timeout_add(REFRESCO_MS, lambda: refrescar() or True)
        else:
            responder(False)

    api.al_mostrar(visible)
    ir(0)
    mostrar("apagado", 0, 0, 0, True)
    return raiz
