#ifndef PC_PALETTE_H
#define PC_PALETTE_H

#include "pc_types.h"

/* Palettes from src/colors.h, in the order of the "New note palette" menu:
   0 Pastel, 1 Black and white, 2 Yellow only. Colors are 0xRRGGBB. */
#define PC_PALETTE_COUNT 3
#define PC_COLOR_COUNT 6

/* Out-of-range values fall back to palette 0 / color 0, as open_note() does. */
uint32_t pc_note_rgb(int palette, int color);
/* Text and outline color: white on the dark black-and-white cards, else black. */
uint32_t pc_ink_rgb(int palette, int color);
/* Title bar: the card color at 94%. */
uint32_t pc_bar_rgb(int palette, int color);

#endif
