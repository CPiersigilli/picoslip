/* Strict UTF-16 <-> UTF-8 for note files, matching the WC_ERR_INVALID_CHARS
   and MB_ERR_INVALID_CHARS conversions used by src/picoslip.c. */
#include "pc_text.h"

size_t pc_txt_capacity(size_t title_length, size_t body_length) {
    return (title_length + body_length) * 3 + 3;
}

static bool is_high(pc_char unit) { return unit >= 0xd800 && unit <= 0xdbff; }
static bool is_low(pc_char unit) { return unit >= 0xdc00 && unit <= 0xdfff; }

static bool encode_utf8(const pc_char *text, size_t length, char *out, size_t capacity, size_t *used) {
    size_t i;
    for (i = 0; i < length; ++i) {
        uint32_t code_point = text[i];
        if (is_low(text[i])) return false;
        if (is_high(text[i])) {
            if (i + 1 >= length || !is_low(text[i + 1])) return false;
            code_point = 0x10000 + (((uint32_t)text[i] - 0xd800) << 10) + ((uint32_t)text[i + 1] - 0xdc00);
            ++i;
        }
        if (code_point < 0x80) {
            if (*used + 1 > capacity) return false;
            out[(*used)++] = (char)code_point;
        } else if (code_point < 0x800) {
            if (*used + 2 > capacity) return false;
            out[(*used)++] = (char)(0xc0 | (code_point >> 6));
            out[(*used)++] = (char)(0x80 | (code_point & 0x3f));
        } else if (code_point < 0x10000) {
            if (*used + 3 > capacity) return false;
            out[(*used)++] = (char)(0xe0 | (code_point >> 12));
            out[(*used)++] = (char)(0x80 | ((code_point >> 6) & 0x3f));
            out[(*used)++] = (char)(0x80 | (code_point & 0x3f));
        } else {
            if (*used + 4 > capacity) return false;
            out[(*used)++] = (char)(0xf0 | (code_point >> 18));
            out[(*used)++] = (char)(0x80 | ((code_point >> 12) & 0x3f));
            out[(*used)++] = (char)(0x80 | ((code_point >> 6) & 0x3f));
            out[(*used)++] = (char)(0x80 | (code_point & 0x3f));
        }
    }
    return true;
}

bool pc_txt_encode(const pc_char *title, size_t title_length, const pc_char *body, size_t body_length,
                   char *out, size_t capacity, size_t *written) {
    size_t used = 0;
    *written = 0;
    if (title) {
        if (capacity < 1) return false;
        out[used++] = '#';
        if (!encode_utf8(title, title_length, out, capacity, &used) || used + 2 > capacity) return false;
        out[used++] = '\r';
        out[used++] = '\n';
    }
    if (!encode_utf8(body, body_length, out, capacity, &used)) return false;
    *written = used;
    return true;
}

bool pc_utf8_decode(const char *bytes, size_t size, pc_char *out, size_t capacity, size_t *length) {
    const unsigned char *data = (const unsigned char *)bytes;
    size_t i = 0, used = 0;
    *length = 0;
    if (size >= 3 && data[0] == 0xef && data[1] == 0xbb && data[2] == 0xbf) i = 3;
    while (i < size) {
        uint32_t code_point;
        size_t extra, k;
        unsigned char lead = data[i];
        if (lead < 0x80) { code_point = lead; extra = 0; }
        else if (lead >= 0xc2 && lead <= 0xdf) { code_point = lead & 0x1fu; extra = 1; }
        else if (lead >= 0xe0 && lead <= 0xef) { code_point = lead & 0x0fu; extra = 2; }
        else if (lead >= 0xf0 && lead <= 0xf4) { code_point = lead & 0x07u; extra = 3; }
        else return false;
        if (extra && i + extra >= size) return false;
        for (k = 1; k <= extra; ++k) {
            if ((data[i + k] & 0xc0) != 0x80) return false;
            code_point = (code_point << 6) | (data[i + k] & 0x3fu);
        }
        /* Overlong three/four-byte forms, encoded surrogates, beyond Unicode. */
        if ((extra == 2 && code_point < 0x800) || (extra == 3 && code_point < 0x10000) ||
            (code_point >= 0xd800 && code_point <= 0xdfff) || code_point > 0x10ffff) return false;
        i += extra + 1;
        if (code_point >= 0x10000) {
            if (out) {
                if (used + 2 > capacity) return false;
                out[used] = (pc_char)(0xd800 + ((code_point - 0x10000) >> 10));
                out[used + 1] = (pc_char)(0xdc00 + ((code_point - 0x10000) & 0x3ff));
            }
            used += 2;
        } else {
            if (out) {
                if (used + 1 > capacity) return false;
                out[used] = (pc_char)code_point;
            }
            ++used;
        }
    }
    *length = used;
    return true;
}
