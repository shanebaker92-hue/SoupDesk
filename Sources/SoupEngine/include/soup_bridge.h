/* soup_bridge.h - the small C surface SoupDesk calls. */
#ifndef SOUP_BRIDGE_H
#define SOUP_BRIDGE_H
#include <stddef.h>
#include <stdint.h>

typedef struct soup_stock soup_stock;

/* Parse a .fs file. NULL on parse failure. */
soup_stock *soup_stock_load(const char *text, size_t len);
void        soup_stock_free(soup_stock *s);
const char *soup_stock_name(const soup_stock *s);
const char *soup_stock_desc(const soup_stock *s);

/* Grade packed RGB8 (3 bytes/pixel, rows `stride` bytes apart) into `out`
 * (packed, width*3 per row). `scale` 1/2/4 as on the camera: grain and
 * halation shrink with it. Rows are streamed through the look in strips
 * like the camera job does. Returns 0 on success. */
int soup_grade(const soup_stock *s, int scale,
               const uint8_t *rgb, int width, int height, size_t stride,
               uint8_t *out);

/* Reference path for verification: decode a JPEG with the engine's own
 * decoder (scale 1) into a malloc'd packed RGB buffer. Caller frees. */
uint8_t *soup_engine_decode_jpeg(const void *buf, size_t len, int *w, int *h);

/* Camera-shaped reference (decoder rows straight into the look). Caller frees. */
uint8_t *soup_engine_reference(const soup_stock *s, const void *buf, size_t len, int *w, int *h);

#endif
