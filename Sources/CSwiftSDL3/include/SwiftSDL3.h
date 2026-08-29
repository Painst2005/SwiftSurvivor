#ifndef SWIFT_SURVIVOR_SDL3_H
#define SWIFT_SURVIVOR_SDL3_H

#include <stdbool.h>
#include <stdint.h>

typedef struct SwiftSDL3Context SwiftSDL3Context;
typedef struct SwiftSDL3Texture SwiftSDL3Texture;
typedef struct SwiftSDL3Audio SwiftSDL3Audio;

typedef enum SwiftSDL3EventKind {
    SWIFT_SDL3_EVENT_NONE = 0,
    SWIFT_SDL3_EVENT_QUIT = 1,
    SWIFT_SDL3_EVENT_KEY_DOWN = 2,
    SWIFT_SDL3_EVENT_KEY_UP = 3,
    SWIFT_SDL3_EVENT_MOUSE_MOTION = 4,
    SWIFT_SDL3_EVENT_MOUSE_BUTTON_DOWN = 5,
    SWIFT_SDL3_EVENT_MOUSE_BUTTON_UP = 6,
    SWIFT_SDL3_EVENT_WINDOW_RESIZED = 7
} SwiftSDL3EventKind;

typedef struct SwiftSDL3Event {
    uint32_t kind;
    int32_t key;
    uint8_t repeat;
    uint8_t button;
    float x;
    float y;
    int32_t width;
    int32_t height;
} SwiftSDL3Event;

bool swift_sdl3_startup(void);
void swift_sdl3_shutdown(void);
SwiftSDL3Context *swift_sdl3_create(const char *title, int width, int height, bool resizable);
void swift_sdl3_destroy(SwiftSDL3Context *context);
bool swift_sdl3_poll_event(SwiftSDL3Event *event);
void swift_sdl3_begin_frame(SwiftSDL3Context *context, uint8_t r, uint8_t g, uint8_t b, uint8_t a);
void swift_sdl3_set_draw_color(SwiftSDL3Context *context, uint8_t r, uint8_t g, uint8_t b, uint8_t a);
bool swift_sdl3_fill_rect(SwiftSDL3Context *context, float x, float y, float width, float height);
bool swift_sdl3_fill_circle(SwiftSDL3Context *context, float centerX, float centerY, float radius);
bool swift_sdl3_line(SwiftSDL3Context *context, float x1, float y1, float x2, float y2);
bool swift_sdl3_debug_text(SwiftSDL3Context *context, float x, float y, const char *utf8);
SwiftSDL3Texture *swift_sdl3_texture_create(SwiftSDL3Context *context, int width, int height, const void *pixels, int pitch);
bool swift_sdl3_texture_update(SwiftSDL3Texture *texture, const void *pixels, int pitch);
void swift_sdl3_texture_destroy(SwiftSDL3Texture *texture);
bool swift_sdl3_draw_texture(SwiftSDL3Context *context, SwiftSDL3Texture *texture, float x, float y, float width, float height, uint8_t alpha);
SwiftSDL3Audio *swift_sdl3_audio_create(const char *path, bool loop);
bool swift_sdl3_audio_tick(SwiftSDL3Audio *audio);
void swift_sdl3_audio_destroy(SwiftSDL3Audio *audio);
void swift_sdl3_present(SwiftSDL3Context *context);
uint64_t swift_sdl3_ticks_ns(void);
const char *swift_sdl3_error(void);
int32_t swift_sdl3_keycode_w(void);
int32_t swift_sdl3_keycode_a(void);
int32_t swift_sdl3_keycode_s(void);
int32_t swift_sdl3_keycode_d(void);
int32_t swift_sdl3_keycode_up(void);
int32_t swift_sdl3_keycode_down(void);
int32_t swift_sdl3_keycode_left(void);
int32_t swift_sdl3_keycode_right(void);
int32_t swift_sdl3_keycode_space(void);
int32_t swift_sdl3_keycode_shift(void);
int32_t swift_sdl3_keycode_escape(void);
int32_t swift_sdl3_keycode_enter(void);

#endif
