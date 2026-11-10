#!/usr/bin/env python3
# ventanas.py - lista los títulos de las ventanas visibles de la sesión de win (XWayland)
# kan0p - https://github.com/kan0p/win-control - GPL-3.0-or-later
import ctypes
import ctypes.util
import os
import sys

CLASES = (b"Windows", b"RDC")   # /wm-class de win con FreeRDP; Thincast usa siempre "RDC"
INTERNAS = ("RDC", "CiceroUIWndFrame")   # ventanas propias del cliente o de Windows
MINIMO = 80             # px: descarta las ventanas auxiliares de RemoteApp


class Atributos(ctypes.Structure):
    _fields_ = [("x", ctypes.c_int), ("y", ctypes.c_int), ("w", ctypes.c_int),
                ("h", ctypes.c_int), ("borde", ctypes.c_int), ("prof", ctypes.c_int),
                ("visual", ctypes.c_void_p), ("raiz", ctypes.c_ulong), ("clase", ctypes.c_int),
                ("bit_gravity", ctypes.c_int), ("win_gravity", ctypes.c_int),
                ("backing_store", ctypes.c_int), ("backing_planes", ctypes.c_ulong),
                ("backing_pixel", ctypes.c_ulong), ("save_under", ctypes.c_int),
                ("colormap", ctypes.c_ulong), ("map_installed", ctypes.c_int),
                ("map_state", ctypes.c_int), ("all_event_masks", ctypes.c_long),
                ("your_event_mask", ctypes.c_long), ("do_not_propagate", ctypes.c_long),
                ("override_redirect", ctypes.c_int), ("pantalla", ctypes.c_void_p)]


class Pista(ctypes.Structure):
    _fields_ = [("nombre", ctypes.c_void_p), ("clase", ctypes.c_void_p)]


def main():
    nombre_lib = ctypes.util.find_library("X11")
    if not nombre_lib or not os.environ.get("DISPLAY"):
        return
    x = ctypes.CDLL(nombre_lib)
    x.XOpenDisplay.restype = ctypes.c_void_p
    x.XDefaultRootWindow.restype = ctypes.c_ulong
    x.XInternAtom.restype = ctypes.c_ulong
    x.XSetErrorHandler(ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_void_p, ctypes.c_void_p)(
        lambda d, e: 0))
    d = ctypes.c_void_p(x.XOpenDisplay(None))
    if not d.value:
        return
    nombre_net = x.XInternAtom(d, b"_NET_WM_NAME", False)
    utf8 = x.XInternAtom(d, b"UTF8_STRING", False)

    def titulo(v):
        tipo, formato = ctypes.c_ulong(), ctypes.c_int()
        n, resto = ctypes.c_ulong(), ctypes.c_ulong()
        datos = ctypes.POINTER(ctypes.c_ubyte)()
        if x.XGetWindowProperty(d, ctypes.c_ulong(v), ctypes.c_ulong(nombre_net), 0, 1024,
                                False, ctypes.c_ulong(utf8), ctypes.byref(tipo),
                                ctypes.byref(formato), ctypes.byref(n), ctypes.byref(resto),
                                ctypes.byref(datos)) != 0 or not datos:
            return ""
        texto = bytes(datos[:n.value]).decode("utf-8", "replace")
        x.XFree(ctypes.cast(datos, ctypes.c_void_p))
        return texto

    def recorrer(v, nivel=0):
        raiz, padre = ctypes.c_ulong(), ctypes.c_ulong()
        hijos, n = ctypes.POINTER(ctypes.c_ulong)(), ctypes.c_uint()
        if not x.XQueryTree(d, ctypes.c_ulong(v), ctypes.byref(raiz), ctypes.byref(padre),
                            ctypes.byref(hijos), ctypes.byref(n)):
            return
        lista = [hijos[i] for i in range(n.value)]
        if hijos:
            x.XFree(ctypes.cast(hijos, ctypes.c_void_p))
        for h in lista:
            pista = Pista()
            if x.XGetClassHint(d, ctypes.c_ulong(h), ctypes.byref(pista)):
                es_nuestra = bool(pista.clase) and ctypes.string_at(pista.clase) in CLASES
                for puntero in (pista.nombre, pista.clase):
                    if puntero:
                        x.XFree(ctypes.c_void_p(puntero))
                if es_nuestra:
                    a = Atributos()
                    x.XGetWindowAttributes(d, ctypes.c_ulong(h), ctypes.byref(a))
                    if a.map_state == 2 and a.w >= MINIMO and a.h >= MINIMO:
                        t = titulo(h)
                        if t and not t.startswith(INTERNAS):
                            print(t)
                    continue
            if nivel < 2:
                recorrer(h, nivel + 1)

    recorrer(x.XDefaultRootWindow(d))


if __name__ == "__main__":
    sys.exit(main())
