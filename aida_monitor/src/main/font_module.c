#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <math.h>

#include "module_abi.h"

typedef struct font_instance_t font_instance_t;
static void *font_stb_alloc(size_t size, void *userdata);
static void font_stb_free(void *ptr, void *userdata);

#define STBTT_STATIC
#define STBTT_assert(value) ((void)0)
#define STBTT_malloc(size, userdata) font_stb_alloc((size), (userdata))
#define STBTT_free(ptr, userdata) font_stb_free((ptr), (userdata))
#define STB_TRUETYPE_IMPLEMENTATION
#include "stb_truetype.h"

#define FONT_MODULE_EXPORT __attribute__((visibility("default"), used))
#define FONT_VERSION "0.2.0"
#define FONT_CACHE_SLOTS 96u
#define FONT_CACHE_LIMIT (512u * 1024u)
#define FONT_MAX_FILE_BYTES (4u * 1024u * 1024u)
#define FONT_MAX_TEXT_BYTES 1024u
#define FONT_MAX_WIDTH 320
#define FONT_MAX_HEIGHT 240
#define FONT_SURFACE_SLOTS 2u

typedef struct cached_glyph_t {
    uint32_t codepoint;
    uint32_t stamp;
    uint16_t size_px;
    int16_t width;
    int16_t height;
    int16_t xoff;
    int16_t yoff;
    int16_t advance;
    uint8_t *bitmap;
    size_t bytes;
    uint8_t used;
} cached_glyph_t;

typedef struct premul_pixel_t {
    uint8_t r;
    uint8_t g;
    uint8_t b;
    uint8_t a;
} premul_pixel_t;

typedef struct software_surface_t {
    uint16_t *pixels;
    size_t bytes;
    uint16_t width;
    uint16_t height;
    uint8_t used;
} software_surface_t;

struct font_instance_t {
    module_host_api_v1 host;
    uint8_t *font_data;
    size_t font_size;
    stbtt_fontinfo font;
    cached_glyph_t cache[FONT_CACHE_SLOTS];
    size_t cache_bytes;
    uint32_t stamp;
    uint32_t render_count;
    uint32_t surface_flushes;
    uint32_t missing_glyphs;
    software_surface_t surfaces[FONT_SURFACE_SLOTS];
    char font_path[MODULE_PATH_MAX];
    uint8_t loaded;
};

static const module_host_api_v1 *s_host = NULL;

static const module_manifest_t s_manifest = {
    MODULE_MANIFEST_MAGIC,
    MODULE_SDK_VERSION,
    sizeof(module_manifest_t),
    "aida_font",
    FONT_VERSION,
    "Noto Sans SC TrueType rasterizer for AIDA RemoteSensor",
    0,
    MODULE_BOOTSTRAP_ABI_VERSION,
};

static void *font_alloc(font_instance_t *inst, size_t size)
{
    void *ptr = NULL;
    if (!inst || !inst->host.heap.malloc || size == 0) {
        return NULL;
    }
    ptr = inst->host.heap.malloc(size, MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT);
    if (!ptr) {
        ptr = inst->host.heap.malloc(size, MODULE_HEAP_INTERNAL | MODULE_HEAP_8BIT);
    }
    return ptr;
}

static void *font_calloc(font_instance_t *inst, size_t count, size_t size)
{
    void *ptr = NULL;
    if (!inst || !inst->host.heap.calloc || count == 0 || size == 0) {
        return NULL;
    }
    ptr = inst->host.heap.calloc(count, size, MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT);
    if (!ptr) {
        ptr = inst->host.heap.calloc(count, size, MODULE_HEAP_INTERNAL | MODULE_HEAP_8BIT);
    }
    return ptr;
}

static void font_release(font_instance_t *inst, void *ptr)
{
    if (inst && ptr && inst->host.heap.free) {
        inst->host.heap.free(ptr);
    }
}

static void *font_stb_alloc(size_t size, void *userdata)
{
    return font_alloc((font_instance_t *)userdata, size);
}

static void font_stb_free(void *ptr, void *userdata)
{
    font_release((font_instance_t *)userdata, ptr);
}

static int text_equal(const char *a, const char *b)
{
    if (!a || !b) {
        return 0;
    }
    while (*a && *b && *a == *b) {
        ++a;
        ++b;
    }
    return *a == *b;
}

static void text_copy(char *dst, size_t capacity, const char *src)
{
    size_t index = 0;
    if (!dst || capacity == 0) {
        return;
    }
    if (!src) {
        src = "";
    }
    while (src[index] && index + 1 < capacity) {
        dst[index] = src[index];
        ++index;
    }
    dst[index] = '\0';
}

static font_instance_t *instance_from_lua(lua_State *L)
{
    if (!s_host || !s_host->lua.touserdata || !s_host->lua.upvalue_index) {
        return NULL;
    }
    return (font_instance_t *)s_host->lua.touserdata(L, s_host->lua.upvalue_index(1));
}

static void set_function_field(lua_State *L,
                               const module_host_api_v1 *host,
                               const char *key,
                               module_lua_cfunction_t function,
                               font_instance_t *inst)
{
    host->lua.pushlightuserdata(L, inst);
    host->lua.pushcclosure(L, function, 1);
    host->lua.setfield(L, -2, key);
}

static int push_error(lua_State *L, const module_host_api_v1 *host, const char *message)
{
    host->lua.pushnil(L);
    host->lua.pushstring(L, message ? message : "font operation failed");
    return 2;
}

static int option_integer(lua_State *L,
                          const module_host_api_v1 *host,
                          int table_index,
                          const char *key,
                          int fallback)
{
    int top = 0;
    int value = fallback;
    if (!host->lua.istable(L, table_index)) {
        return fallback;
    }
    top = host->lua.gettop(L);
    host->lua.getfield(L, table_index, key);
    if (host->lua.isnumber(L, -1)) {
        value = (int)host->lua.tointeger(L, -1);
    }
    host->lua.settop(L, top);
    return value;
}

static int option_boolean(lua_State *L,
                          const module_host_api_v1 *host,
                          int table_index,
                          const char *key,
                          int fallback)
{
    int top = 0;
    int value = fallback;
    if (!host->lua.istable(L, table_index)) {
        return fallback;
    }
    top = host->lua.gettop(L);
    host->lua.getfield(L, table_index, key);
    if (!host->lua.isnil(L, -1)) {
        value = host->lua.toboolean(L, -1) ? 1 : 0;
    }
    host->lua.settop(L, top);
    return value;
}

static void cache_clear(font_instance_t *inst)
{
    size_t index = 0;
    if (!inst) {
        return;
    }
    for (index = 0; index < FONT_CACHE_SLOTS; ++index) {
        if (inst->cache[index].bitmap) {
            font_release(inst, inst->cache[index].bitmap);
        }
        memset(&inst->cache[index], 0, sizeof(inst->cache[index]));
    }
    inst->cache_bytes = 0;
}

static void surfaces_clear(font_instance_t *inst)
{
    size_t index = 0;
    if (!inst) {
        return;
    }
    for (index = 0; index < FONT_SURFACE_SLOTS; ++index) {
        if (inst->surfaces[index].pixels) {
            font_release(inst, inst->surfaces[index].pixels);
        }
        memset(&inst->surfaces[index], 0, sizeof(inst->surfaces[index]));
    }
}

static void font_close_internal(font_instance_t *inst)
{
    if (!inst) {
        return;
    }
    cache_clear(inst);
    surfaces_clear(inst);
    if (inst->font_data) {
        font_release(inst, inst->font_data);
    }
    inst->font_data = NULL;
    inst->font_size = 0;
    inst->font_path[0] = '\0';
    inst->loaded = 0;
    memset(&inst->font, 0, sizeof(inst->font));
}

static cached_glyph_t *cache_oldest(font_instance_t *inst)
{
    cached_glyph_t *oldest = NULL;
    size_t index = 0;
    for (index = 0; index < FONT_CACHE_SLOTS; ++index) {
        cached_glyph_t *entry = &inst->cache[index];
        if (!entry->used) {
            return entry;
        }
        if (!oldest || entry->stamp < oldest->stamp) {
            oldest = entry;
        }
    }
    return oldest;
}

static void cache_evict(font_instance_t *inst, cached_glyph_t *entry)
{
    if (!inst || !entry || !entry->used) {
        return;
    }
    if (entry->bitmap) {
        font_release(inst, entry->bitmap);
    }
    if (entry->bytes <= inst->cache_bytes) {
        inst->cache_bytes -= entry->bytes;
    } else {
        inst->cache_bytes = 0;
    }
    memset(entry, 0, sizeof(*entry));
}

static uint32_t normalize_codepoint(font_instance_t *inst, uint32_t codepoint)
{
    if (stbtt_FindGlyphIndex(&inst->font, (int)codepoint) != 0 || codepoint == 0) {
        return codepoint;
    }
    inst->missing_glyphs++;
    if (stbtt_FindGlyphIndex(&inst->font, 0x25A1) != 0) {
        return 0x25A1;
    }
    return (uint32_t)'?';
}

static cached_glyph_t *glyph_get(font_instance_t *inst, uint32_t requested, int size_px)
{
    cached_glyph_t *slot = NULL;
    uint32_t codepoint = 0;
    size_t index = 0;
    float scale = 1.0f;
    int advance = 0;
    int bearing = 0;
    int width = 0;
    int height = 0;
    int xoff = 0;
    int yoff = 0;
    uint8_t *bitmap = NULL;
    size_t bytes = 0;

    if (!inst || !inst->loaded) {
        return NULL;
    }
    codepoint = normalize_codepoint(inst, requested);
    for (index = 0; index < FONT_CACHE_SLOTS; ++index) {
        cached_glyph_t *entry = &inst->cache[index];
        if (entry->used && entry->codepoint == codepoint && entry->size_px == (uint16_t)size_px) {
            entry->stamp = ++inst->stamp;
            return entry;
        }
    }

    scale = stbtt_ScaleForPixelHeight(&inst->font, (float)size_px);
    stbtt_GetCodepointHMetrics(&inst->font, (int)codepoint, &advance, &bearing);
    (void)bearing;
    bitmap = stbtt_GetCodepointBitmap(&inst->font, scale, scale, (int)codepoint,
                                      &width, &height, &xoff, &yoff);
    if (width > 0 && height > 0 && !bitmap) {
        return NULL;
    }
    bytes = (size_t)width * (size_t)height;
    while (inst->cache_bytes + bytes > FONT_CACHE_LIMIT) {
        cached_glyph_t *victim = cache_oldest(inst);
        if (!victim || !victim->used) {
            break;
        }
        cache_evict(inst, victim);
    }
    slot = cache_oldest(inst);
    if (!slot) {
        if (bitmap) {
            stbtt_FreeBitmap(bitmap, inst);
        }
        return NULL;
    }
    if (slot->used) {
        cache_evict(inst, slot);
    }
    slot->used = 1;
    slot->codepoint = codepoint;
    slot->size_px = (uint16_t)size_px;
    slot->width = (int16_t)width;
    slot->height = (int16_t)height;
    slot->xoff = (int16_t)xoff;
    slot->yoff = (int16_t)yoff;
    slot->advance = (int16_t)floorf((float)advance * scale + 0.5f);
    slot->bitmap = bitmap;
    slot->bytes = bytes;
    slot->stamp = ++inst->stamp;
    inst->cache_bytes += bytes;
    return slot;
}

static uint32_t utf8_next(const char **cursor, const char *end)
{
    const unsigned char *text = (const unsigned char *)*cursor;
    uint32_t codepoint = 0xFFFD;
    if ((const char *)text >= end || !*text) {
        return 0;
    }
    if (text[0] < 0x80) {
        codepoint = text[0];
        text += 1;
    } else if ((text[0] & 0xE0) == 0xC0 && (const char *)(text + 1) < end) {
        codepoint = ((uint32_t)(text[0] & 0x1F) << 6) | (uint32_t)(text[1] & 0x3F);
        text += 2;
    } else if ((text[0] & 0xF0) == 0xE0 && (const char *)(text + 2) < end) {
        codepoint = ((uint32_t)(text[0] & 0x0F) << 12)
                  | ((uint32_t)(text[1] & 0x3F) << 6)
                  | (uint32_t)(text[2] & 0x3F);
        text += 3;
    } else if ((text[0] & 0xF8) == 0xF0 && (const char *)(text + 3) < end) {
        codepoint = ((uint32_t)(text[0] & 0x07) << 18)
                  | ((uint32_t)(text[1] & 0x3F) << 12)
                  | ((uint32_t)(text[2] & 0x3F) << 6)
                  | (uint32_t)(text[3] & 0x3F);
        text += 4;
    } else {
        text += 1;
    }
    *cursor = (const char *)text;
    return codepoint;
}

static int text_width(font_instance_t *inst,
                      const char *text,
                      size_t text_len,
                      int size_px,
                      int bold,
                      int italic)
{
    const char *cursor = text;
    const char *end = text + text_len;
    uint32_t previous = 0;
    float scale = stbtt_ScaleForPixelHeight(&inst->font, (float)size_px);
    int width = 0;
    while (cursor < end && *cursor) {
        uint32_t requested = utf8_next(&cursor, end);
        cached_glyph_t *glyph = glyph_get(inst, requested, size_px);
        if (!glyph) {
            continue;
        }
        if (previous) {
            width += (int)floorf((float)stbtt_GetCodepointKernAdvance(
                &inst->font, (int)previous, (int)glyph->codepoint) * scale + 0.5f);
        }
        width += glyph->advance;
        previous = glyph->codepoint;
    }
    if (bold) {
        width += (size_px + 15) / 16;
    }
    if (italic) {
        width += (size_px + 4) / 5;
    }
    return width;
}

static void blend_pixel(premul_pixel_t *pixel,
                        uint8_t red,
                        uint8_t green,
                        uint8_t blue,
                        uint8_t alpha)
{
    uint32_t inverse = 255u - alpha;
    if (!pixel || alpha == 0) {
        return;
    }
    pixel->r = (uint8_t)(((uint32_t)red * alpha + (uint32_t)pixel->r * inverse + 127u) / 255u);
    pixel->g = (uint8_t)(((uint32_t)green * alpha + (uint32_t)pixel->g * inverse + 127u) / 255u);
    pixel->b = (uint8_t)(((uint32_t)blue * alpha + (uint32_t)pixel->b * inverse + 127u) / 255u);
    pixel->a = (uint8_t)((uint32_t)alpha + ((uint32_t)pixel->a * inverse + 127u) / 255u);
}

static void draw_glyph(premul_pixel_t *surface,
                       int surface_width,
                       int surface_height,
                       const cached_glyph_t *glyph,
                       int pen_x,
                       int baseline,
                       int offset_x,
                       int offset_y,
                       int bold_strength,
                       int italic,
                       uint32_t color,
                       int opacity)
{
    int row = 0;
    int column = 0;
    int bold_offset = 0;
    uint8_t red = (uint8_t)((color >> 16) & 0xFF);
    uint8_t green = (uint8_t)((color >> 8) & 0xFF);
    uint8_t blue = (uint8_t)(color & 0xFF);
    if (!surface || !glyph || !glyph->bitmap) {
        return;
    }
    for (row = 0; row < glyph->height; ++row) {
        int y = baseline + glyph->yoff + row + offset_y;
        int shear = italic ? (baseline - y + 2) / 5 : 0;
        if (y < 0 || y >= surface_height) {
            continue;
        }
        for (column = 0; column < glyph->width; ++column) {
            uint8_t coverage = glyph->bitmap[row * glyph->width + column];
            uint8_t alpha = (uint8_t)(((uint32_t)coverage * (uint32_t)opacity + 127u) / 255u);
            if (!alpha) {
                continue;
            }
            for (bold_offset = 0; bold_offset <= bold_strength; ++bold_offset) {
                int x = pen_x + glyph->xoff + column + offset_x + shear + bold_offset;
                if (x >= 0 && x < surface_width) {
                    blend_pixel(&surface[y * surface_width + x], red, green, blue, alpha);
                }
            }
        }
    }
}

static void draw_rect(premul_pixel_t *surface,
                      int surface_width,
                      int surface_height,
                      int x,
                      int y,
                      int width,
                      int height,
                      uint32_t color,
                      int opacity)
{
    int row = 0;
    int column = 0;
    uint8_t red = (uint8_t)((color >> 16) & 0xFF);
    uint8_t green = (uint8_t)((color >> 8) & 0xFF);
    uint8_t blue = (uint8_t)(color & 0xFF);
    for (row = 0; row < height; ++row) {
        int py = y + row;
        if (py < 0 || py >= surface_height) {
            continue;
        }
        for (column = 0; column < width; ++column) {
            int px = x + column;
            if (px >= 0 && px < surface_width) {
                blend_pixel(&surface[py * surface_width + px], red, green, blue, (uint8_t)opacity);
            }
        }
    }
}

static void draw_text_pass(font_instance_t *inst,
                           premul_pixel_t *surface,
                           int surface_width,
                           int surface_height,
                           const char *text,
                           size_t text_len,
                           int size_px,
                           int origin_x,
                           int baseline,
                           int offset_x,
                           int offset_y,
                           int blur,
                           int bold_strength,
                           int italic,
                           uint32_t color,
                           int opacity)
{
    const char *cursor = text;
    const char *end = text + text_len;
    uint32_t previous = 0;
    float scale = stbtt_ScaleForPixelHeight(&inst->font, (float)size_px);
    int pen = origin_x;
    int glyph_count = 0;
    while (cursor < end && *cursor) {
        uint32_t requested = utf8_next(&cursor, end);
        cached_glyph_t *glyph = glyph_get(inst, requested, size_px);
        int by = 0;
        int bx = 0;
        if (!glyph) {
            continue;
        }
        if (previous) {
            pen += (int)floorf((float)stbtt_GetCodepointKernAdvance(
                &inst->font, (int)previous, (int)glyph->codepoint) * scale + 0.5f);
        }
        if (blur <= 0) {
            draw_glyph(surface, surface_width, surface_height, glyph, pen, baseline,
                       offset_x, offset_y, bold_strength, italic, color, opacity);
        } else {
            int diameter = blur * 2 + 1;
            int taps = diameter * diameter;
            int tap_opacity = opacity * 3 / taps;
            if (tap_opacity < 1) {
                tap_opacity = 1;
            }
            for (by = -blur; by <= blur; ++by) {
                for (bx = -blur; bx <= blur; ++bx) {
                    draw_glyph(surface, surface_width, surface_height, glyph, pen, baseline,
                               offset_x + bx, offset_y + by, bold_strength, italic,
                               color, tap_opacity);
                }
            }
        }
        pen += glyph->advance;
        previous = glyph->codepoint;
        ++glyph_count;
        if ((glyph_count & 7) == 0 && inst->host.time.yield) {
            inst->host.time.yield();
        }
    }
}

static uint16_t rgb565(uint8_t red, uint8_t green, uint8_t blue)
{
    return (uint16_t)(((uint16_t)(red & 0xF8) << 8)
                    | ((uint16_t)(green & 0xFC) << 3)
                    | ((uint16_t)blue >> 3));
}

static software_surface_t *surface_get(font_instance_t *inst, int id)
{
    if (!inst || id < 1 || id > (int)FONT_SURFACE_SLOTS) {
        return NULL;
    }
    if (!inst->surfaces[id - 1].used || !inst->surfaces[id - 1].pixels) {
        return NULL;
    }
    return &inst->surfaces[id - 1];
}

static uint16_t surface_blend_rgb565(uint16_t background, uint32_t foreground, int opacity)
{
    uint32_t alpha = (uint32_t)(opacity < 0 ? 0 : (opacity > 255 ? 255 : opacity));
    uint32_t inverse = 255u - alpha;
    uint32_t br = ((background >> 11) & 0x1Fu) * 255u / 31u;
    uint32_t bg = ((background >> 5) & 0x3Fu) * 255u / 63u;
    uint32_t bb = (background & 0x1Fu) * 255u / 31u;
    uint32_t fr = (foreground >> 16) & 0xFFu;
    uint32_t fg = (foreground >> 8) & 0xFFu;
    uint32_t fb = foreground & 0xFFu;
    return rgb565((uint8_t)((fr * alpha + br * inverse + 127u) / 255u),
                  (uint8_t)((fg * alpha + bg * inverse + 127u) / 255u),
                  (uint8_t)((fb * alpha + bb * inverse + 127u) / 255u));
}

static void surface_pixel(software_surface_t *surface,
                          int x,
                          int y,
                          uint32_t color,
                          int opacity)
{
    uint16_t *pixel = NULL;
    if (!surface || !surface->pixels || x < 0 || y < 0
        || x >= surface->width || y >= surface->height || opacity <= 0) {
        return;
    }
    pixel = &surface->pixels[(size_t)y * surface->width + (size_t)x];
    if (opacity >= 255) {
        *pixel = rgb565((uint8_t)(color >> 16), (uint8_t)(color >> 8), (uint8_t)color);
    } else {
        *pixel = surface_blend_rgb565(*pixel, color, opacity);
    }
}

static void surface_brush(software_surface_t *surface,
                          int x,
                          int y,
                          int width,
                          uint32_t color,
                          int opacity)
{
    int radius = width > 1 ? width / 2 : 0;
    int py = 0;
    int px = 0;
    for (py = y - radius; py <= y + radius; ++py) {
        for (px = x - radius; px <= x + radius; ++px) {
            surface_pixel(surface, px, py, color, opacity);
        }
    }
}

static int l_surface_create(lua_State *L)
{
    font_instance_t *inst = instance_from_lua(L);
    int width = 0;
    int height = 0;
    uint32_t color = 0;
    size_t index = 0;
    size_t count = 0;
    software_surface_t *surface = NULL;
    uint16_t value = 0;
    if (!inst) return 0;
    width = (int)inst->host.lua.checkinteger(L, 1);
    height = (int)inst->host.lua.checkinteger(L, 2);
    color = (uint32_t)inst->host.lua.checkinteger(L, 3);
    if (width < 1 || width > FONT_MAX_WIDTH || height < 1 || height > FONT_MAX_HEIGHT) {
        return push_error(L, &inst->host, "surface dimensions are invalid");
    }
    for (index = 0; index < FONT_SURFACE_SLOTS; ++index) {
        if (!inst->surfaces[index].used) {
            surface = &inst->surfaces[index];
            break;
        }
    }
    if (!surface) return push_error(L, &inst->host, "surface limit reached");
    count = (size_t)width * (size_t)height;
    surface->pixels = (uint16_t *)font_alloc(inst, count * sizeof(uint16_t));
    if (!surface->pixels) return push_error(L, &inst->host, "not enough memory for surface");
    surface->width = (uint16_t)width;
    surface->height = (uint16_t)height;
    surface->bytes = count * sizeof(uint16_t);
    surface->used = 1;
    value = rgb565((uint8_t)(color >> 16), (uint8_t)(color >> 8), (uint8_t)color);
    for (count = 0; count < (size_t)width * (size_t)height; ++count) {
        surface->pixels[count] = value;
    }
    inst->host.lua.pushinteger(L, (int64_t)(index + 1));
    return 1;
}

static int l_surface_free(lua_State *L)
{
    font_instance_t *inst = instance_from_lua(L);
    int id = 0;
    software_surface_t *surface = NULL;
    if (!inst) return 0;
    id = (int)inst->host.lua.checkinteger(L, 1);
    surface = surface_get(inst, id);
    if (!surface) return push_error(L, &inst->host, "surface is invalid");
    font_release(inst, surface->pixels);
    memset(surface, 0, sizeof(*surface));
    inst->host.lua.pushboolean(L, 1);
    return 1;
}

static int l_surface_clear(lua_State *L)
{
    font_instance_t *inst = instance_from_lua(L);
    software_surface_t *surface = NULL;
    uint32_t color = 0;
    uint16_t value = 0;
    size_t index = 0;
    if (!inst) return 0;
    surface = surface_get(inst, (int)inst->host.lua.checkinteger(L, 1));
    color = (uint32_t)inst->host.lua.checkinteger(L, 2);
    if (!surface) return push_error(L, &inst->host, "surface is invalid");
    value = rgb565((uint8_t)(color >> 16), (uint8_t)(color >> 8), (uint8_t)color);
    for (index = 0; index < (size_t)surface->width * surface->height; ++index) {
        surface->pixels[index] = value;
    }
    inst->host.lua.pushboolean(L, 1);
    return 1;
}

static int l_surface_rect(lua_State *L)
{
    font_instance_t *inst = instance_from_lua(L);
    software_surface_t *surface = NULL;
    int x = 0, y = 0, width = 0, height = 0, opacity = 255;
    uint32_t color = 0;
    int row = 0, column = 0;
    if (!inst) return 0;
    surface = surface_get(inst, (int)inst->host.lua.checkinteger(L, 1));
    x = (int)inst->host.lua.checkinteger(L, 2);
    y = (int)inst->host.lua.checkinteger(L, 3);
    width = (int)inst->host.lua.checkinteger(L, 4);
    height = (int)inst->host.lua.checkinteger(L, 5);
    color = (uint32_t)inst->host.lua.checkinteger(L, 6);
    opacity = (int)inst->host.lua.checkinteger(L, 7);
    if (!surface) return push_error(L, &inst->host, "surface is invalid");
    for (row = 0; row < height; ++row) {
        for (column = 0; column < width; ++column) {
            surface_pixel(surface, x + column, y + row, color, opacity);
        }
    }
    inst->host.lua.pushboolean(L, 1);
    return 1;
}

static int l_surface_circle(lua_State *L)
{
    font_instance_t *inst = instance_from_lua(L);
    software_surface_t *surface = NULL;
    int cx = 0, cy = 0, radius = 0, opacity = 255;
    uint32_t color = 0;
    int row = 0, column = 0;
    if (!inst) return 0;
    surface = surface_get(inst, (int)inst->host.lua.checkinteger(L, 1));
    cx = (int)inst->host.lua.checkinteger(L, 2);
    cy = (int)inst->host.lua.checkinteger(L, 3);
    radius = (int)inst->host.lua.checkinteger(L, 4);
    color = (uint32_t)inst->host.lua.checkinteger(L, 5);
    opacity = (int)inst->host.lua.checkinteger(L, 6);
    if (!surface) return push_error(L, &inst->host, "surface is invalid");
    if (radius < 0) radius = 0;
    for (row = -radius; row <= radius; ++row) {
        int half = (int)floorf(sqrtf((float)(radius * radius - row * row)) + 0.5f);
        for (column = -half; column <= half; ++column) {
            surface_pixel(surface, cx + column, cy + row, color, opacity);
        }
    }
    inst->host.lua.pushboolean(L, 1);
    return 1;
}

static int l_surface_line(lua_State *L)
{
    font_instance_t *inst = instance_from_lua(L);
    software_surface_t *surface = NULL;
    int x0 = 0, y0 = 0, x1 = 0, y1 = 0, opacity = 255, width = 1;
    int dx = 0, sx = 0, dy = 0, sy = 0, error = 0, twice = 0;
    uint32_t color = 0;
    if (!inst) return 0;
    surface = surface_get(inst, (int)inst->host.lua.checkinteger(L, 1));
    x0 = (int)inst->host.lua.checkinteger(L, 2);
    y0 = (int)inst->host.lua.checkinteger(L, 3);
    x1 = (int)inst->host.lua.checkinteger(L, 4);
    y1 = (int)inst->host.lua.checkinteger(L, 5);
    color = (uint32_t)inst->host.lua.checkinteger(L, 6);
    opacity = (int)inst->host.lua.checkinteger(L, 7);
    width = (int)inst->host.lua.checkinteger(L, 8);
    if (!surface) return push_error(L, &inst->host, "surface is invalid");
    if (width < 1) width = 1;
    dx = x1 > x0 ? x1 - x0 : x0 - x1;
    sx = x0 < x1 ? 1 : -1;
    dy = -(y1 > y0 ? y1 - y0 : y0 - y1);
    sy = y0 < y1 ? 1 : -1;
    error = dx + dy;
    for (;;) {
        surface_brush(surface, x0, y0, width, color, opacity);
        if (x0 == x1 && y0 == y1) break;
        twice = error * 2;
        if (twice >= dy) { error += dy; x0 += sx; }
        if (twice <= dx) { error += dx; y0 += sy; }
    }
    inst->host.lua.pushboolean(L, 1);
    return 1;
}

static int l_surface_arc(lua_State *L)
{
    font_instance_t *inst = instance_from_lua(L);
    software_surface_t *surface = NULL;
    int cx = 0, cy = 0, radius = 0, opacity = 255, width = 1;
    float start = 0.0f, finish = 0.0f, span = 0.0f;
    int steps = 0, step = 0;
    uint32_t color = 0;
    if (!inst) return 0;
    surface = surface_get(inst, (int)inst->host.lua.checkinteger(L, 1));
    cx = (int)inst->host.lua.checkinteger(L, 2);
    cy = (int)inst->host.lua.checkinteger(L, 3);
    radius = (int)inst->host.lua.checkinteger(L, 4);
    start = (float)inst->host.lua.checknumber(L, 5);
    finish = (float)inst->host.lua.checknumber(L, 6);
    color = (uint32_t)inst->host.lua.checkinteger(L, 7);
    opacity = (int)inst->host.lua.checkinteger(L, 8);
    width = (int)inst->host.lua.checkinteger(L, 9);
    if (!surface) return push_error(L, &inst->host, "surface is invalid");
    if (radius < 1) radius = 1;
    if (width < 1) width = 1;
    span = finish - start;
    steps = (int)ceilf(fabsf(span) * (float)radius * 0.01745329252f);
    if (steps < (int)ceilf(fabsf(span))) steps = (int)ceilf(fabsf(span));
    if (steps < 1) steps = 1;
    for (step = 0; step <= steps; ++step) {
        float angle = (start + span * (float)step / (float)steps - 90.0f) * 0.01745329252f;
        int x = cx + (int)floorf(cosf(angle) * radius + 0.5f);
        int y = cy + (int)floorf(sinf(angle) * radius + 0.5f);
        surface_brush(surface, x, y, width, color, opacity);
    }
    inst->host.lua.pushboolean(L, 1);
    return 1;
}

static int l_surface_text(lua_State *L)
{
    font_instance_t *inst = instance_from_lua(L);
    software_surface_t *destination = NULL;
    const char *text = NULL;
    size_t text_len = 0;
    int x = 0, y = 0, width = 0, height = 0, size_px = 0;
    uint32_t foreground = 0;
    int bold = 0, italic = 0, underline = 0, strike = 0, align = 0;
    int shadow_dx = 0, shadow_dy = 0, shadow_blur = 0, shadow_opacity = 0;
    uint32_t shadow_color = 0;
    int ascent = 0, descent = 0, line_gap = 0;
    float scale = 1.0f;
    int baseline = 0, measured = 0, origin_x = 0, bold_strength = 0;
    premul_pixel_t *layer = NULL;
    size_t pixel_count = 0, index = 0;
    if (!inst || !inst->loaded) {
        return push_error(L, inst ? &inst->host : s_host, "vector font is not loaded");
    }
    destination = surface_get(inst, (int)inst->host.lua.checkinteger(L, 1));
    x = (int)inst->host.lua.checkinteger(L, 2);
    y = (int)inst->host.lua.checkinteger(L, 3);
    width = (int)inst->host.lua.checkinteger(L, 4);
    height = (int)inst->host.lua.checkinteger(L, 5);
    text = inst->host.lua.checklstring(L, 6, &text_len);
    size_px = (int)inst->host.lua.checkinteger(L, 7);
    foreground = (uint32_t)inst->host.lua.checkinteger(L, 8);
    if (!destination) return push_error(L, &inst->host, "surface is invalid");
    if (!text || text_len > FONT_MAX_TEXT_BYTES || width < 1 || height < 1
        || width > FONT_MAX_WIDTH || height > FONT_MAX_HEIGHT) {
        return push_error(L, &inst->host, "surface text arguments are invalid");
    }
    if (size_px < 6) size_px = 6;
    if (size_px > 96) size_px = 96;
    bold = option_boolean(L, &inst->host, 9, "bold", 0);
    italic = option_boolean(L, &inst->host, 9, "italic", 0);
    underline = option_boolean(L, &inst->host, 9, "underline", 0);
    strike = option_boolean(L, &inst->host, 9, "strike", 0);
    align = option_integer(L, &inst->host, 9, "align", 0);
    shadow_dx = option_integer(L, &inst->host, 9, "shadow_dx", 0);
    shadow_dy = option_integer(L, &inst->host, 9, "shadow_dy", 0);
    shadow_blur = option_integer(L, &inst->host, 9, "shadow_blur", 0);
    shadow_opacity = option_integer(L, &inst->host, 9, "shadow_opacity", 0);
    shadow_color = (uint32_t)option_integer(L, &inst->host, 9, "shadow_color", 0);
    if (shadow_blur < 0) shadow_blur = 0;
    if (shadow_blur > 2) shadow_blur = 2;
    if (shadow_opacity < 0) shadow_opacity = 0;
    if (shadow_opacity > 255) shadow_opacity = 255;
    pixel_count = (size_t)width * (size_t)height;
    layer = (premul_pixel_t *)font_calloc(inst, pixel_count, sizeof(premul_pixel_t));
    if (!layer) return push_error(L, &inst->host, "not enough memory for text layer");
    scale = stbtt_ScaleForPixelHeight(&inst->font, (float)size_px);
    stbtt_GetFontVMetrics(&inst->font, &ascent, &descent, &line_gap);
    (void)descent; (void)line_gap;
    baseline = (int)ceilf((float)ascent * scale);
    measured = text_width(inst, text, text_len, size_px, bold, italic);
    if (align == 1) origin_x = (width - measured) / 2;
    else if (align == 2) origin_x = width - measured;
    if (origin_x < 0) origin_x = 0;
    bold_strength = bold ? (size_px + 15) / 16 : 0;
    if (shadow_opacity > 0 && (shadow_dx || shadow_dy || shadow_blur)) {
        draw_text_pass(inst, layer, width, height, text, text_len, size_px,
                       origin_x, baseline, shadow_dx, shadow_dy, shadow_blur,
                       bold_strength, italic, shadow_color, shadow_opacity);
    }
    draw_text_pass(inst, layer, width, height, text, text_len, size_px,
                   origin_x, baseline, 0, 0, 0, bold_strength, italic,
                   foreground, 255);
    if (underline) {
        int thickness = (size_px + 13) / 14;
        draw_rect(layer, width, height, origin_x,
                  baseline + ((size_px + 11) / 12), measured, thickness,
                  foreground, 255);
    }
    if (strike) {
        int thickness = (size_px + 13) / 14;
        draw_rect(layer, width, height, origin_x,
                  baseline - ((size_px * 5 + 8) / 16), measured, thickness,
                  foreground, 255);
    }
    for (index = 0; index < pixel_count; ++index) {
        premul_pixel_t *source = &layer[index];
        int row = (int)(index / (size_t)width);
        int column = (int)(index % (size_t)width);
        int dx = x + column;
        int dy = y + row;
        uint16_t *target = NULL;
        uint32_t inverse = 0, br = 0, bg = 0, bb = 0;
        if (!source->a || dx < 0 || dy < 0
            || dx >= destination->width || dy >= destination->height) continue;
        target = &destination->pixels[(size_t)dy * destination->width + (size_t)dx];
        inverse = 255u - source->a;
        br = ((*target >> 11) & 0x1Fu) * 255u / 31u;
        bg = ((*target >> 5) & 0x3Fu) * 255u / 63u;
        bb = (*target & 0x1Fu) * 255u / 31u;
        *target = rgb565((uint8_t)((uint32_t)source->r + (br * inverse + 127u) / 255u),
                         (uint8_t)((uint32_t)source->g + (bg * inverse + 127u) / 255u),
                         (uint8_t)((uint32_t)source->b + (bb * inverse + 127u) / 255u));
    }
    font_release(inst, layer);
    inst->render_count++;
    inst->host.lua.pushboolean(L, 1);
    return 1;
}

static int l_surface_pixels(lua_State *L)
{
    font_instance_t *inst = instance_from_lua(L);
    software_surface_t *surface = NULL;
    if (!inst) return 0;
    surface = surface_get(inst, (int)inst->host.lua.checkinteger(L, 1));
    if (!surface) return push_error(L, &inst->host, "surface is invalid");
    inst->host.lua.pushlstring(L, (const char *)surface->pixels, surface->bytes);
    inst->surface_flushes++;
    return 1;
}

static int l_font_measure(lua_State *L)
{
    font_instance_t *inst = instance_from_lua(L);
    const char *text = NULL;
    size_t text_len = 0;
    int size_px = 0, bold = 0, italic = 0, measured = 0;
    if (!inst || !inst->loaded) {
        return push_error(L, inst ? &inst->host : s_host, "vector font is not loaded");
    }
    text = inst->host.lua.checklstring(L, 1, &text_len);
    size_px = (int)inst->host.lua.checkinteger(L, 2);
    if (!text || text_len > FONT_MAX_TEXT_BYTES) {
        return push_error(L, &inst->host, "text is too long");
    }
    if (size_px < 6) size_px = 6;
    if (size_px > 96) size_px = 96;
    bold = option_boolean(L, &inst->host, 3, "bold", 0);
    italic = option_boolean(L, &inst->host, 3, "italic", 0);
    measured = text_width(inst, text, text_len, size_px, bold, italic);
    inst->host.lua.pushinteger(L, measured);
    return 1;
}

static int l_font_version(lua_State *L)
{
    font_instance_t *inst = instance_from_lua(L);
    if (!inst) {
        return 0;
    }
    inst->host.lua.pushstring(L, FONT_VERSION);
    return 1;
}

static int l_font_open(lua_State *L)
{
    font_instance_t *inst = instance_from_lua(L);
    const char *path = NULL;
    void *file = NULL;
    uint64_t file_size = 0;
    size_t offset = 0;
    int32_t result = MODULE_OK;
    int font_offset = -1;
    if (!inst) {
        return 0;
    }
    path = inst->host.lua.checkstring(L, 1);
    if (!path || !*path) {
        return push_error(L, &inst->host, "font path is empty");
    }
    if (inst->loaded && text_equal(inst->font_path, path)) {
        inst->host.lua.pushboolean(L, 1);
        return 1;
    }
    font_close_internal(inst);
    result = inst->host.sd.open(path, MODULE_FILE_READ, &file);
    if (result != MODULE_OK || !file) {
        return push_error(L, &inst->host, "cannot open vector font");
    }
    result = inst->host.file.size_bytes(file, &file_size);
    if (result != MODULE_OK || file_size < 1024 || file_size > FONT_MAX_FILE_BYTES) {
        inst->host.file.close(file);
        return push_error(L, &inst->host, "vector font size is invalid");
    }
    inst->font_data = (uint8_t *)font_alloc(inst, (size_t)file_size);
    if (!inst->font_data) {
        inst->host.file.close(file);
        return push_error(L, &inst->host, "not enough PSRAM for vector font");
    }
    while (offset < (size_t)file_size) {
        size_t requested = (size_t)file_size - offset;
        size_t received = 0;
        if (requested > 16384u) {
            requested = 16384u;
        }
        result = inst->host.file.read(file, inst->font_data + offset, requested, &received);
        if (result != MODULE_OK || received == 0) {
            inst->host.file.close(file);
            font_close_internal(inst);
            return push_error(L, &inst->host, "vector font read failed");
        }
        offset += received;
        if (inst->host.time.yield) {
            inst->host.time.yield();
        }
    }
    inst->host.file.close(file);
    inst->font_size = (size_t)file_size;
    memset(&inst->font, 0, sizeof(inst->font));
    font_offset = stbtt_GetFontOffsetForIndex(inst->font_data, 0);
    if (font_offset < 0 || !stbtt_InitFont(&inst->font, inst->font_data, font_offset)) {
        font_close_internal(inst);
        return push_error(L, &inst->host, "TrueType initialization failed");
    }
    inst->font.userdata = inst;
    inst->loaded = 1;
    text_copy(inst->font_path, sizeof(inst->font_path), path);
    inst->host.lua.pushboolean(L, 1);
    return 1;
}

static int l_font_render(lua_State *L)
{
    font_instance_t *inst = instance_from_lua(L);
    const char *text = NULL;
    size_t text_len = 0;
    int width = 0;
    int height = 0;
    int size_px = 0;
    uint32_t foreground = 0;
    uint32_t background = 0;
    uint32_t chroma = 0x00FF00u;
    int bold = 0;
    int italic = 0;
    int underline = 0;
    int strike = 0;
    int align = 0;
    int opaque = 0;
    int shadow_dx = 0;
    int shadow_dy = 0;
    int shadow_blur = 0;
    int shadow_opacity = 0;
    uint32_t shadow_color = 0;
    int ascent = 0;
    int descent = 0;
    int line_gap = 0;
    float scale = 1.0f;
    int baseline = 0;
    int measured = 0;
    int origin_x = 0;
    int bold_strength = 0;
    size_t pixel_count = 0;
    premul_pixel_t *surface = NULL;
    uint8_t *output = NULL;
    size_t index = 0;

    if (!inst || !inst->loaded) {
        return push_error(L, inst ? &inst->host : s_host, "vector font is not loaded");
    }
    text = inst->host.lua.checklstring(L, 1, &text_len);
    width = (int)inst->host.lua.checkinteger(L, 2);
    height = (int)inst->host.lua.checkinteger(L, 3);
    size_px = (int)inst->host.lua.checkinteger(L, 4);
    foreground = (uint32_t)inst->host.lua.checkinteger(L, 5);
    background = (uint32_t)inst->host.lua.checkinteger(L, 6);
    chroma = (uint32_t)inst->host.lua.checkinteger(L, 7);
    if (!text || text_len > FONT_MAX_TEXT_BYTES) {
        return push_error(L, &inst->host, "text is too long");
    }
    if (width < 1 || width > FONT_MAX_WIDTH || height < 1 || height > FONT_MAX_HEIGHT) {
        return push_error(L, &inst->host, "text surface dimensions are invalid");
    }
    if (size_px < 6) {
        size_px = 6;
    } else if (size_px > 96) {
        size_px = 96;
    }

    bold = option_boolean(L, &inst->host, 8, "bold", 0);
    italic = option_boolean(L, &inst->host, 8, "italic", 0);
    underline = option_boolean(L, &inst->host, 8, "underline", 0);
    strike = option_boolean(L, &inst->host, 8, "strike", 0);
    opaque = option_boolean(L, &inst->host, 8, "opaque", 0);
    align = option_integer(L, &inst->host, 8, "align", 0);
    shadow_dx = option_integer(L, &inst->host, 8, "shadow_dx", 0);
    shadow_dy = option_integer(L, &inst->host, 8, "shadow_dy", 0);
    shadow_blur = option_integer(L, &inst->host, 8, "shadow_blur", 0);
    shadow_opacity = option_integer(L, &inst->host, 8, "shadow_opacity", 0);
    shadow_color = (uint32_t)option_integer(L, &inst->host, 8, "shadow_color", 0);
    if (shadow_blur < 0) shadow_blur = 0;
    if (shadow_blur > 2) shadow_blur = 2;
    if (shadow_opacity < 0) shadow_opacity = 0;
    if (shadow_opacity > 255) shadow_opacity = 255;

    pixel_count = (size_t)width * (size_t)height;
    surface = (premul_pixel_t *)font_calloc(inst, pixel_count, sizeof(premul_pixel_t));
    output = (uint8_t *)font_alloc(inst, pixel_count * 2u);
    if (!surface || !output) {
        font_release(inst, surface);
        font_release(inst, output);
        return push_error(L, &inst->host, "not enough memory for text surface");
    }

    scale = stbtt_ScaleForPixelHeight(&inst->font, (float)size_px);
    stbtt_GetFontVMetrics(&inst->font, &ascent, &descent, &line_gap);
    (void)descent;
    (void)line_gap;
    baseline = (int)ceilf((float)ascent * scale);
    measured = text_width(inst, text, text_len, size_px, bold, italic);
    if (align == 1) {
        origin_x = (width - measured) / 2;
    } else if (align == 2) {
        origin_x = width - measured;
    }
    if (origin_x < 0) {
        origin_x = 0;
    }
    bold_strength = bold ? (size_px + 15) / 16 : 0;

    if (shadow_opacity > 0 && (shadow_dx || shadow_dy || shadow_blur)) {
        draw_text_pass(inst, surface, width, height, text, text_len, size_px,
                       origin_x, baseline, shadow_dx, shadow_dy, shadow_blur,
                       bold_strength, italic, shadow_color, shadow_opacity);
    }
    draw_text_pass(inst, surface, width, height, text, text_len, size_px,
                   origin_x, baseline, 0, 0, 0, bold_strength, italic,
                   foreground, 255);

    if (underline) {
        int thickness = (size_px + 13) / 14;
        draw_rect(surface, width, height, origin_x,
                  baseline + ((size_px + 11) / 12), measured, thickness,
                  foreground, 255);
    }
    if (strike) {
        int thickness = (size_px + 13) / 14;
        draw_rect(surface, width, height, origin_x,
                  baseline - ((size_px * 5 + 8) / 16), measured, thickness,
                  foreground, 255);
    }

    for (index = 0; index < pixel_count; ++index) {
        premul_pixel_t *pixel = &surface[index];
        uint16_t value = 0;
        if (pixel->a == 0 && !opaque) {
            value = rgb565((uint8_t)(chroma >> 16), (uint8_t)(chroma >> 8), (uint8_t)chroma);
        } else {
            uint32_t inverse = 255u - pixel->a;
            uint8_t red = (uint8_t)((uint32_t)pixel->r
                + (((background >> 16) & 0xFFu) * inverse + 127u) / 255u);
            uint8_t green = (uint8_t)((uint32_t)pixel->g
                + (((background >> 8) & 0xFFu) * inverse + 127u) / 255u);
            uint8_t blue = (uint8_t)((uint32_t)pixel->b
                + ((background & 0xFFu) * inverse + 127u) / 255u);
            value = rgb565(red, green, blue);
            if (!opaque && value == rgb565((uint8_t)(chroma >> 16),
                                           (uint8_t)(chroma >> 8),
                                           (uint8_t)chroma)) {
                value ^= 0x0020u;
            }
        }
        output[index * 2u] = (uint8_t)(value & 0xFFu);
        output[index * 2u + 1u] = (uint8_t)(value >> 8);
    }

    inst->render_count++;
    inst->host.lua.pushlstring(L, (const char *)output, pixel_count * 2u);
    font_release(inst, surface);
    font_release(inst, output);
    return 1;
}

static int l_font_stats(lua_State *L)
{
    font_instance_t *inst = instance_from_lua(L);
    size_t entries = 0;
    size_t surface_bytes = 0;
    size_t surface_count = 0;
    size_t index = 0;
    if (!inst) {
        return 0;
    }
    for (index = 0; index < FONT_CACHE_SLOTS; ++index) {
        if (inst->cache[index].used) {
            ++entries;
        }
    }
    for (index = 0; index < FONT_SURFACE_SLOTS; ++index) {
        if (inst->surfaces[index].used) {
            surface_count++;
            surface_bytes += inst->surfaces[index].bytes;
        }
    }
    inst->host.lua.newtable(L);
    inst->host.lua.pushstring(L, "stb_truetype");
    inst->host.lua.setfield(L, -2, "engine");
    inst->host.lua.pushstring(L, FONT_VERSION);
    inst->host.lua.setfield(L, -2, "version");
    inst->host.lua.pushboolean(L, inst->loaded ? 1 : 0);
    inst->host.lua.setfield(L, -2, "loaded");
    inst->host.lua.pushinteger(L, (int64_t)inst->font_size);
    inst->host.lua.setfield(L, -2, "font_bytes");
    inst->host.lua.pushinteger(L, (int64_t)inst->cache_bytes);
    inst->host.lua.setfield(L, -2, "cache_bytes");
    inst->host.lua.pushinteger(L, (int64_t)entries);
    inst->host.lua.setfield(L, -2, "cache_entries");
    inst->host.lua.pushinteger(L, inst->render_count);
    inst->host.lua.setfield(L, -2, "renders");
    inst->host.lua.pushinteger(L, (int64_t)surface_count);
    inst->host.lua.setfield(L, -2, "surface_count");
    inst->host.lua.pushinteger(L, (int64_t)surface_bytes);
    inst->host.lua.setfield(L, -2, "surface_bytes");
    inst->host.lua.pushinteger(L, inst->surface_flushes);
    inst->host.lua.setfield(L, -2, "surface_flushes");
    inst->host.lua.pushinteger(L, inst->missing_glyphs);
    inst->host.lua.setfield(L, -2, "missing_glyphs");
    inst->host.lua.pushinteger(L, inst->host.heap.free_size(MODULE_HEAP_INTERNAL | MODULE_HEAP_8BIT));
    inst->host.lua.setfield(L, -2, "internal_free");
    inst->host.lua.pushinteger(L, inst->host.heap.free_size(MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT));
    inst->host.lua.setfield(L, -2, "psram_free");
    inst->host.lua.pushinteger(L, inst->host.heap.largest_free_block(MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT));
    inst->host.lua.setfield(L, -2, "psram_largest");
    return 1;
}

FONT_MODULE_EXPORT const module_manifest_t *module_query_v1(void)
{
    return &s_manifest;
}

FONT_MODULE_EXPORT int32_t module_create_v2(module_host_resolve_v1_fn resolve,
                                            void *resolve_ctx,
                                            const module_open_info_t *info,
                                            void **out_instance)
{
    module_host_api_v1 host;
    font_instance_t *inst = NULL;
    int32_t result = MODULE_OK;
    (void)info;
    if (!out_instance) {
        return MODULE_ERR_INVALID_ARG;
    }
    *out_instance = NULL;
    module_sdk_zero_host_v1(&host);
    result = module_sdk_resolve_host_v1(resolve, resolve_ctx, &host);
    if (result != MODULE_OK) {
        return result;
    }
    inst = (font_instance_t *)host.heap.calloc(1, sizeof(font_instance_t),
                                               MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT);
    if (!inst) {
        inst = (font_instance_t *)host.heap.calloc(1, sizeof(font_instance_t),
                                                   MODULE_HEAP_INTERNAL | MODULE_HEAP_8BIT);
    }
    if (!inst) {
        return MODULE_ERR_NO_MEMORY;
    }
    inst->host = host;
    s_host = &inst->host;
    *out_instance = inst;
    return MODULE_OK;
}

FONT_MODULE_EXPORT int32_t module_luaopen_v1(void *instance, lua_State *L)
{
    font_instance_t *inst = (font_instance_t *)instance;
    const module_host_api_v1 *host = inst ? &inst->host : s_host;
    if (!inst || !host) {
        return MODULE_ERR_INVALID_ARG;
    }
    s_host = host;
    host->lua.newtable(L);
    host->lua.pushstring(L, FONT_VERSION);
    host->lua.setfield(L, -2, "VERSION");
    set_function_field(L, host, "version", l_font_version, inst);
    set_function_field(L, host, "open", l_font_open, inst);
    set_function_field(L, host, "render", l_font_render, inst);
    set_function_field(L, host, "measure", l_font_measure, inst);
    set_function_field(L, host, "surface_create", l_surface_create, inst);
    set_function_field(L, host, "surface_free", l_surface_free, inst);
    set_function_field(L, host, "surface_clear", l_surface_clear, inst);
    set_function_field(L, host, "surface_rect", l_surface_rect, inst);
    set_function_field(L, host, "surface_circle", l_surface_circle, inst);
    set_function_field(L, host, "surface_line", l_surface_line, inst);
    set_function_field(L, host, "surface_arc", l_surface_arc, inst);
    set_function_field(L, host, "surface_text", l_surface_text, inst);
    set_function_field(L, host, "surface_pixels", l_surface_pixels, inst);
    set_function_field(L, host, "stats", l_font_stats, inst);
    return MODULE_OK;
}

FONT_MODULE_EXPORT void module_destroy_v1(void *instance)
{
    font_instance_t *inst = (font_instance_t *)instance;
    if (!inst) {
        return;
    }
    font_close_internal(inst);
    inst->host.heap.free(inst);
    if (s_host == &inst->host) {
        s_host = NULL;
    }
}
