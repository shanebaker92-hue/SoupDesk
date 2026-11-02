#include <stdlib.h>
#include <string.h>
#include "soup_bridge.h"
#include "se.h"
#include "stock.h"
#include "look.h"
#include "jpeg_dec.h"

struct soup_stock { se_stock st; };

soup_stock *soup_stock_load(const char *text, size_t len)
{
    soup_stock *s = malloc(sizeof *s);
    if (!s) return NULL;
    se_stock_init(&s->st);
    if (se_stock_parse(text, len, &s->st) != SE_OK) { free(s); return NULL; }
    return s;
}

void        soup_stock_free(soup_stock *s) { free(s); }
const char *soup_stock_name(const soup_stock *s) { return s->st.name; }
const char *soup_stock_desc(const soup_stock *s) { return s->st.desc; }

typedef struct { uint8_t *out; size_t pitch; int y; int height; } sink;

static int emit(void *ctx, const uint8_t *row, int width)
{
    sink *k = ctx;
    if (k->y >= k->height) return -1;
    memcpy(k->out + (size_t)k->y++ * k->pitch, row, (size_t)width * 3);
    return 0;
}

int soup_grade(const soup_stock *s, int scale,
               const uint8_t *rgb, int width, int height, size_t stride,
               uint8_t *out)
{
    se_look lk; se_arena ar; se_look_run *run; sink k = { out, (size_t)width * 3, 0, height };
    se_look_from_stock(&s->st, scale, &lk);
    /* Same budget as the camera, so halation radius matches a camera frame. */
    size_t need = se_look_fit(&lk, width, SE_LOOK_BUDGET);
    void *mem = malloc(need + 64);
    if (!mem) return -1;
    se_arena_init(&ar, mem, need + 64);
    int rc = -1;
    if (se_look_begin(&run, &lk, width, &ar) != SE_OK) goto done;
    uint8_t *strip = malloc((size_t)width * 3 * 16);
    if (!strip) goto done;
    for (int y = 0; y < height; y += 16) {
        int n = height - y < 16 ? height - y : 16;
        for (int i = 0; i < n; i++)
            memcpy(strip + (size_t)i * width * 3, rgb + (size_t)(y + i) * stride, (size_t)width * 3);
        if (se_look_rows(run, strip, n, emit, &k) != SE_OK) { free(strip); goto done; }
    }
    free(strip);
    if (se_look_end(run, emit, &k) == SE_OK && k.y == height) rc = 0;
done:
    free(mem);
    return rc;
}

typedef struct { uint8_t *buf; int w; int y; } dsink;

static int drow(void *ctx, const uint8_t *rgb, int nrows, int width)
{
    dsink *d = ctx;
    memcpy(d->buf + (size_t)d->y * width * 3, rgb, (size_t)nrows * width * 3);
    d->y += nrows;
    return 0;
}

uint8_t *soup_engine_decode_jpeg(const void *buf, size_t len, int *w, int *h)
{
    se_jdec_info ji; se_arena ar;
    if (se_jpeg_dec_info(buf, len, &ji) != SE_OK) return NULL;
    size_t asz = (size_t)ji.width * 16 * 6 * 4 + (1 << 20);
    void *mem = malloc(asz);
    dsink d = { malloc((size_t)ji.width * (ji.height + 16) * 3), ji.width, 0 };
    if (!mem || !d.buf) { free(mem); free(d.buf); return NULL; }
    se_arena_init(&ar, mem, asz);
    se_err e = se_jpeg_decode_scaled(buf, len, 1, &ar, drow, &d, &ji);
    free(mem);
    if (e != SE_OK) { free(d.buf); return NULL; }
    *w = ji.width; *h = ji.height;
    return d.buf;
}

/* The camera job's own shape: decoder rows go straight into the look as the
 * decoder produces them, no intermediate frame. Used only by soupcheck. */
typedef struct { se_look_run *run; sink k; } camsink;

static int camrow(void *ctx, const uint8_t *rgb, int nrows, int width)
{
    camsink *c = ctx; (void)width;
    return se_look_rows(c->run, rgb, nrows, emit, &c->k) == SE_OK ? 0 : -1;
}

uint8_t *soup_engine_reference(const soup_stock *s, const void *buf, size_t len, int *w, int *h)
{
    se_jdec_info ji; se_arena ar, la; se_look lk; camsink c;
    if (se_jpeg_dec_info(buf, len, &ji) != SE_OK) return NULL;
    se_look_from_stock(&s->st, 1, &lk);
    size_t ls = se_look_fit(&lk, ji.width, SE_LOOK_BUDGET);
    size_t asz = (size_t)ji.width * 16 * 6 * 4 + (1 << 20);
    void *mem = malloc(asz), *lmem = malloc(ls + 64);
    uint8_t *out = malloc((size_t)ji.width * ji.height * 3);
    if (!mem || !lmem || !out) goto fail;
    se_arena_init(&ar, mem, asz); se_arena_init(&la, lmem, ls + 64);
    c.k.out = out; c.k.pitch = (size_t)ji.width * 3; c.k.y = 0; c.k.height = ji.height;
    if (se_look_begin(&c.run, &lk, ji.width, &la) != SE_OK) goto fail;
    if (se_jpeg_decode_scaled(buf, len, 1, &ar, camrow, &c, &ji) != SE_OK) goto fail;
    if (se_look_end(c.run, emit, &c.k) != SE_OK || c.k.y != ji.height) goto fail;
    free(mem); free(lmem); *w = ji.width; *h = ji.height; return out;
fail:
    free(mem); free(lmem); free(out); return NULL;
}
