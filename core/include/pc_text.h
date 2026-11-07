#ifndef PC_TEXT_H
#define PC_TEXT_H

#include "pc_types.h"

/* TXT note files are UTF-8 without BOM, CRLF line breaks, no added final
   line break. A title is written as "#Title" CRLF before the body.

   Bytes needed for pc_txt_encode: 3 per UTF-16 unit plus '#' and CRLF. */
size_t pc_txt_capacity(size_t title_length, size_t body_length);

/* save_text(): fails, writing nothing useful, on an unpaired surrogate so an
   invalid editor snapshot never replaces a valid file. title may be NULL. */
bool pc_txt_encode(const pc_char *title, size_t title_length, const pc_char *body, size_t body_length,
                   char *out, size_t capacity, size_t *written);

/* load_text(): skips one leading UTF-8 BOM and rejects invalid UTF-8
   (overlong forms, encoded surrogates, values above U+10FFFF, truncation).
   With out == NULL only the required length is computed. */
bool pc_utf8_decode(const char *bytes, size_t size, pc_char *out, size_t capacity, size_t *length);

#endif
