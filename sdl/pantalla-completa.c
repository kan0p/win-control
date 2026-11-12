// Arreglo para sdl-freerdp3 en COSMIC (Wayland) con varias pantallas.
//
// FreeRDP crea una ventana por pantalla: la "mueve" a su pantalla (SDL_SetWindowPosition)
// y pide pantalla completa de inmediato, antes de que la ventana se muestre. COSMIC ignora
// en ese momento la pantalla pedida (xdg_toplevel.set_fullscreen(output)) y las deja todas
// en la principal, una encima de otra. Si el pedido llega con la ventana ya visible, sí lo
// respeta. Esta librería (LD_PRELOAD) anota la posición pedida para cada ventana y, cuando
// la ventana se muestra, sale de pantalla completa y la vuelve a pedir en esa posición.
#define _GNU_SOURCE
#include <SDL3/SDL.h>
#include <dlfcn.h>
#include <stdint.h>

#define MAX_VENTANAS 16

static struct { SDL_WindowID id; int x, y, intentos; bool en_curso; } pedidas[MAX_VENTANAS];
static bool vigilando;

static bool (*real_fullscreen)(SDL_Window *, bool);
static bool (*real_position)(SDL_Window *, int, int);

static void cargar(void)
{
    if (!real_fullscreen)
        real_fullscreen = (bool (*)(SDL_Window *, bool))dlsym(RTLD_NEXT, "SDL_SetWindowFullscreen");
    if (!real_position)
        real_position = (bool (*)(SDL_Window *, int, int))dlsym(RTLD_NEXT, "SDL_SetWindowPosition");
}

static int buscar(SDL_WindowID id, bool crear)
{
    for (int i = 0; i < MAX_VENTANAS; i++)
        if (pedidas[i].id == id)
            return i;
    if (crear)
        for (int i = 0; i < MAX_VENTANAS; i++)
            if (pedidas[i].id == 0) {
                pedidas[i].id = id;
                return i;
            }
    return -1;
}

// ¿la ventana quedó en la pantalla que contiene la posición pedida?
static bool en_su_pantalla(SDL_Window *w, int x, int y)
{
    SDL_Rect r;
    if (!SDL_GetDisplayBounds(SDL_GetDisplayForWindow(w), &r))
        return true;
    return x >= r.x && x < r.x + r.w && y >= r.y && y < r.y + r.h;
}

// pasos con pausa entre medio, siempre en el hilo principal de SDL: si salir y volver a
// entrar a pantalla completa llegan juntos, COSMIC los toma como un solo cambio
static void paso_entrar(void *datos)
{
    int i = (int)(intptr_t)datos;
    SDL_Window *w = SDL_GetWindowFromID(pedidas[i].id);
    if (!w)
        return;
    real_position(w, pedidas[i].x, pedidas[i].y);
    real_fullscreen(w, true);
    pedidas[i].en_curso = false;
}

static Uint32 tras_pausa_entrar(void *datos, SDL_TimerID t, Uint32 ms)
{
    (void)t; (void)ms;
    SDL_RunOnMainThread(paso_entrar, datos, false);
    return 0;
}

static void paso_salir(void *datos)
{
    int i = (int)(intptr_t)datos;
    SDL_Window *w = SDL_GetWindowFromID(pedidas[i].id);
    if (!w) {
        pedidas[i].en_curso = false;
        return;
    }
    real_fullscreen(w, false);
    SDL_AddTimer(300, tras_pausa_entrar, datos);
}

static Uint32 tras_pausa_salir(void *datos, SDL_TimerID t, Uint32 ms)
{
    (void)t; (void)ms;
    SDL_RunOnMainThread(paso_salir, datos, false);
    return 0;
}

static bool al_cambiar(void *datos, SDL_Event *ev)
{
    (void)datos;
    if (ev->type != SDL_EVENT_WINDOW_ENTER_FULLSCREEN && ev->type != SDL_EVENT_WINDOW_DISPLAY_CHANGED &&
        ev->type != SDL_EVENT_WINDOW_EXPOSED)
        return true;
    int i = buscar(ev->window.windowID, false);
    if (i < 0 || pedidas[i].en_curso || pedidas[i].intentos >= 3)
        return true;
    SDL_Window *w = SDL_GetWindowFromID(ev->window.windowID);
    if (!w || !(SDL_GetWindowFlags(w) & SDL_WINDOW_FULLSCREEN) || en_su_pantalla(w, pedidas[i].x, pedidas[i].y))
        return true;
    pedidas[i].intentos++;
    pedidas[i].en_curso = true;
    SDL_Log("pantalla-completa: ventana %u fuera de su pantalla, intento %d", ev->window.windowID,
            pedidas[i].intentos);
    SDL_AddTimer(500, tras_pausa_salir, (void *)(intptr_t)i);
    return true;
}

bool SDL_SetWindowPosition(SDL_Window *window, int x, int y)
{
    cargar();
    int i = buscar(SDL_GetWindowID(window), true);
    if (i >= 0) {
        pedidas[i].x = x;
        pedidas[i].y = y;
    }
    if (!vigilando) {
        SDL_AddEventWatch(al_cambiar, NULL);
        vigilando = true;
    }
    return real_position(window, x, y);
}

bool SDL_SetWindowFullscreen(SDL_Window *window, bool fullscreen)
{
    cargar();
    return real_fullscreen(window, fullscreen);
}
