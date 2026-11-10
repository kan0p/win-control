#!/usr/bin/env python3
# panel.py - el complemento Windows de GlassPad como ventana normal, para equipos sin ScreenPad
# kan0p - https://github.com/kan0p/win-control - GPL-3.0-or-later
import importlib.util
import os
import sys

import gi
gi.require_version("Gdk", "4.0")
gi.require_version("Gtk", "4.0")
from gi.repository import Gdk, GLib, Gtk  # noqa: E402

CARPETA = os.path.join(os.path.dirname(os.path.realpath(__file__)), "glasspad", "windows")
APP_ID = "io.github.kan0p.WinControl.Panel"

CSS = """
.panel-fondo { background: linear-gradient(135deg, #10204a, #2a1240 60%, #0b2a2a); color: white; }
.panel-aviso { background: alpha(black, 0.8); color: white; border-radius: 22px;
               padding: 14px 26px; margin-bottom: 26px; font-size: 22px; }
"""


class Api:
    """Lo mismo que GlassPad entrega a crear(api), adaptado a mouse y teclado."""

    def __init__(self, ventana, aviso):
        self.carpeta = CARPETA
        self._ventana = ventana
        self._aviso = aviso
        self._reloj_aviso = 0
        self._al_mostrar = []
        self._al_deslizar = None

    def accion(self, widget, al_tocar, al_mantener=None):
        widget.connect("clicked", lambda _w: al_tocar())
        if al_mantener:
            largo = Gtk.GestureLongPress()
            largo.connect("pressed", lambda *_a: al_mantener())
            widget.add_controller(largo)
        return widget

    def deslizable(self, widget, al_cambiar, al_soltar=None):
        return widget

    def tecla(self, al_tocar, texto=None, icono=None, clases=()):
        b = Gtk.Button(label=texto or "", icon_name=icono, css_classes=list(clases))
        return self.accion(b, al_tocar)

    def vaciar(self, contenedor):
        hijo = contenedor.get_first_child()
        while hijo:
            siguiente = hijo.get_next_sibling()
            contenedor.remove(hijo)
            hijo = siguiente

    def css(self, texto):
        prov = Gtk.CssProvider()
        prov.load_from_data(texto.encode())
        Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), prov,
                                                  Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 2)

    def al_mostrar(self, funcion):
        self._al_mostrar.append(funcion)

    def al_deslizar(self, funcion):
        self._al_deslizar = funcion

    def avisar(self, texto):
        self._aviso.set_label(texto)
        self._aviso.set_visible(True)
        if self._reloj_aviso:
            GLib.source_remove(self._reloj_aviso)

        def ocultar():
            self._aviso.set_visible(False)
            self._reloj_aviso = 0
            return False
        self._reloj_aviso = GLib.timeout_add(4000, ocultar)

    def escribir(self, texto):
        pass

    def atajo(self, combinacion):
        pass

    def abrir(self, app_id):
        pass

    def inicio(self):
        pass


def activar(app):
    if app.get_windows():
        app.get_windows()[0].present()
        return
    spec = importlib.util.spec_from_file_location("win_complemento",
                                                  os.path.join(CARPETA, "complemento.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)

    ventana = Gtk.ApplicationWindow(application=app, title="Panel de Windows",
                                    default_width=1600, default_height=900)
    capas = Gtk.Overlay(css_classes=["panel-fondo"])
    aviso = Gtk.Label(css_classes=["panel-aviso"], visible=False, wrap=True,
                      halign=Gtk.Align.CENTER, valign=Gtk.Align.END)
    api = Api(ventana, aviso)
    api.css(CSS)
    contenido = mod.crear(api)
    contenido.set_hexpand(True)
    contenido.set_vexpand(True)
    capas.set_child(contenido)
    capas.add_overlay(aviso)
    ventana.set_child(capas)

    # flechas del teclado y gesto de deslizar en el touchpad cambian de página
    teclas = Gtk.EventControllerKey()

    def tecla(_c, valor, _codigo, _estado):
        if api._al_deslizar and valor in (Gdk.KEY_Right, Gdk.KEY_Left):
            api._al_deslizar(1 if valor == Gdk.KEY_Right else -1)
            return True
        return False
    teclas.connect("key-pressed", tecla)
    ventana.add_controller(teclas)
    deslizar = Gtk.GestureSwipe()
    deslizar.connect("swipe", lambda _g, vx, vy: api._al_deslizar and abs(vx) > 2 * abs(vy)
                     and abs(vx) > 400 and api._al_deslizar(1 if vx < 0 else -1))
    ventana.add_controller(deslizar)

    def visible(si):
        for f in api._al_mostrar:
            f(si)
    ventana.connect("notify::is-active", lambda v, _p: visible(True) if v.is_active() else None)
    ventana.connect("close-request", lambda _v: visible(False) or False)
    ventana.present()
    visible(True)


def main():
    app = Gtk.Application(application_id=APP_ID)
    app.connect("activate", activar)
    return app.run(sys.argv[:1])


if __name__ == "__main__":
    sys.exit(main())
