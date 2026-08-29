#include "SwiftSDL3.h"
#include <SDL3/SDL.h>

struct SwiftSDL3Context {
    SDL_Window *window;
    SDL_Renderer *renderer;
};

struct SwiftSDL3Texture {
    SDL_Texture *texture;
};

bool swift_sdl3_startup(void) {
    return SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO | SDL_INIT_GAMEPAD);
}

void swift_sdl3_shutdown(void) {
    SDL_Quit();
}

SwiftSDL3Context *swift_sdl3_create(const char *title, int width, int height, bool resizable) {
    SwiftSDL3Context *context = (SwiftSDL3Context *)SDL_calloc(1, sizeof(SwiftSDL3Context));
    if (context == NULL) {
        return NULL;
    }

    SDL_WindowFlags flags = resizable ? SDL_WINDOW_RESIZABLE : 0;
    context->window = SDL_CreateWindow(title, width, height, flags);
    if (context->window == NULL) {
        SDL_free(context);
        return NULL;
    }

    context->renderer = SDL_CreateRenderer(context->window, NULL);
    if (context->renderer == NULL) {
        SDL_DestroyWindow(context->window);
        SDL_free(context);
        return NULL;
    }
    return context;
}

void swift_sdl3_destroy(SwiftSDL3Context *context) {
    if (context == NULL) {
        return;
    }
    if (context->renderer != NULL) {
        SDL_DestroyRenderer(context->renderer);
    }
    if (context->window != NULL) {
        SDL_DestroyWindow(context->window);
    }
    SDL_free(context);
}

bool swift_sdl3_poll_event(SwiftSDL3Event *output) {
    if (output == NULL) {
        return false;
    }
    SDL_Event event;
    if (!SDL_PollEvent(&event)) {
        return false;
    }

    output->kind = SWIFT_SDL3_EVENT_NONE;
    output->key = 0;
    output->repeat = 0;
    output->button = 0;
    output->x = 0.0f;
    output->y = 0.0f;
    output->width = 0;
    output->height = 0;

    switch (event.type) {
        case SDL_EVENT_QUIT:
            output->kind = SWIFT_SDL3_EVENT_QUIT;
            break;
        case SDL_EVENT_KEY_DOWN:
            output->kind = SWIFT_SDL3_EVENT_KEY_DOWN;
            output->key = (int32_t)event.key.key;
            output->repeat = event.key.repeat ? 1 : 0;
            break;
        case SDL_EVENT_KEY_UP:
            output->kind = SWIFT_SDL3_EVENT_KEY_UP;
            output->key = (int32_t)event.key.key;
            break;
        case SDL_EVENT_MOUSE_MOTION:
            output->kind = SWIFT_SDL3_EVENT_MOUSE_MOTION;
            output->x = event.motion.x;
            output->y = event.motion.y;
            break;
        case SDL_EVENT_MOUSE_BUTTON_DOWN:
            output->kind = SWIFT_SDL3_EVENT_MOUSE_BUTTON_DOWN;
            output->button = event.button.button;
            output->x = event.button.x;
            output->y = event.button.y;
            break;
        case SDL_EVENT_MOUSE_BUTTON_UP:
            output->kind = SWIFT_SDL3_EVENT_MOUSE_BUTTON_UP;
            output->button = event.button.button;
            output->x = event.button.x;
            output->y = event.button.y;
            break;
        case SDL_EVENT_WINDOW_RESIZED:
            output->kind = SWIFT_SDL3_EVENT_WINDOW_RESIZED;
            output->width = event.window.data1;
            output->height = event.window.data2;
            break;
        default:
            break;
    }
    return true;
}

void swift_sdl3_begin_frame(SwiftSDL3Context *context, uint8_t r, uint8_t g, uint8_t b, uint8_t a) {
    if (context == NULL || context->renderer == NULL) {
        return;
    }
    SDL_SetRenderDrawColor(context->renderer, r, g, b, a);
    SDL_RenderClear(context->renderer);
}

void swift_sdl3_set_draw_color(SwiftSDL3Context *context, uint8_t r, uint8_t g, uint8_t b, uint8_t a) {
    if (context != NULL && context->renderer != NULL) {
        SDL_SetRenderDrawColor(context->renderer, r, g, b, a);
    }
}

bool swift_sdl3_fill_rect(SwiftSDL3Context *context, float x, float y, float width, float height) {
    if (context == NULL || context->renderer == NULL) {
        return false;
    }
    SDL_FRect rect = { x, y, width, height };
    return SDL_RenderFillRect(context->renderer, &rect);
}

bool swift_sdl3_fill_circle(SwiftSDL3Context *context, float centerX, float centerY, float radius) {
    if (context == NULL || context->renderer == NULL || radius <= 0.0f) {
        return false;
    }
    int minY = (int)(centerY - radius);
    int maxY = (int)(centerY + radius);
    for (int y = minY; y <= maxY; ++y) {
        float dy = (float)y - centerY;
        float span = SDL_sqrtf(SDL_max(0.0f, radius * radius - dy * dy));
        if (!SDL_RenderLine(context->renderer, centerX - span, (float)y, centerX + span, (float)y)) {
            return false;
        }
    }
    return true;
}

bool swift_sdl3_line(SwiftSDL3Context *context, float x1, float y1, float x2, float y2) {
    if (context == NULL || context->renderer == NULL) {
        return false;
    }
    return SDL_RenderLine(context->renderer, x1, y1, x2, y2);
}

bool swift_sdl3_debug_text(SwiftSDL3Context *context, float x, float y, const char *utf8) {
    if (context == NULL || context->renderer == NULL || utf8 == NULL) {
        return false;
    }
    return SDL_RenderDebugText(context->renderer, x, y, utf8);
}

SwiftSDL3Texture *swift_sdl3_texture_create(SwiftSDL3Context *context, int width, int height, const void *pixels, int pitch) {
    if (context == NULL || context->renderer == NULL || width <= 0 || height <= 0) {
        return NULL;
    }
    SwiftSDL3Texture *result = (SwiftSDL3Texture *)SDL_calloc(1, sizeof(SwiftSDL3Texture));
    if (result == NULL) {
        return NULL;
    }
    result->texture = SDL_CreateTexture(context->renderer, SDL_PIXELFORMAT_RGBA32,
                                        SDL_TEXTUREACCESS_STATIC, width, height);
    if (result->texture == NULL) {
        SDL_free(result);
        return NULL;
    }
    SDL_SetTextureBlendMode(result->texture, SDL_BLENDMODE_BLEND);
    if (pixels != NULL && !SDL_UpdateTexture(result->texture, NULL, pixels, pitch)) {
        SDL_DestroyTexture(result->texture);
        SDL_free(result);
        return NULL;
    }
    return result;
}

bool swift_sdl3_texture_update(SwiftSDL3Texture *texture, const void *pixels, int pitch) {
    if (texture == NULL || texture->texture == NULL || pixels == NULL || pitch <= 0) {
        return false;
    }
    return SDL_UpdateTexture(texture->texture, NULL, pixels, pitch);
}

void swift_sdl3_texture_destroy(SwiftSDL3Texture *texture) {
    if (texture == NULL) {
        return;
    }
    if (texture->texture != NULL) {
        SDL_DestroyTexture(texture->texture);
    }
    SDL_free(texture);
}

bool swift_sdl3_draw_texture(SwiftSDL3Context *context, SwiftSDL3Texture *texture, float x, float y, float width, float height, uint8_t alpha) {
    if (context == NULL || context->renderer == NULL || texture == NULL || texture->texture == NULL) {
        return false;
    }
    SDL_SetTextureAlphaMod(texture->texture, alpha);
    SDL_FRect destination = { x, y, width, height };
    return SDL_RenderTexture(context->renderer, texture->texture, NULL, &destination);
}

void swift_sdl3_present(SwiftSDL3Context *context) {
    if (context != NULL && context->renderer != NULL) {
        SDL_RenderPresent(context->renderer);
    }
}

uint64_t swift_sdl3_ticks_ns(void) {
    return (uint64_t)SDL_GetTicksNS();
}

const char *swift_sdl3_error(void) {
    return SDL_GetError();
}

int32_t swift_sdl3_keycode_w(void) { return (int32_t)SDLK_W; }
int32_t swift_sdl3_keycode_a(void) { return (int32_t)SDLK_A; }
int32_t swift_sdl3_keycode_s(void) { return (int32_t)SDLK_S; }
int32_t swift_sdl3_keycode_d(void) { return (int32_t)SDLK_D; }
int32_t swift_sdl3_keycode_up(void) { return (int32_t)SDLK_UP; }
int32_t swift_sdl3_keycode_down(void) { return (int32_t)SDLK_DOWN; }
int32_t swift_sdl3_keycode_left(void) { return (int32_t)SDLK_LEFT; }
int32_t swift_sdl3_keycode_right(void) { return (int32_t)SDLK_RIGHT; }
int32_t swift_sdl3_keycode_space(void) { return (int32_t)SDLK_SPACE; }
int32_t swift_sdl3_keycode_shift(void) { return (int32_t)SDLK_LSHIFT; }
int32_t swift_sdl3_keycode_escape(void) { return (int32_t)SDLK_ESCAPE; }
int32_t swift_sdl3_keycode_enter(void) { return (int32_t)SDLK_RETURN; }
