/* Card colors from src/colors.h and the ink/bar rules of src/picoslip.c. */
#include "pc_palette.h"

static const uint32_t palettes[PC_PALETTE_COUNT][PC_COLOR_COUNT] = {
    {0xffee97, 0xc7e5ff, 0xd5efbb, 0xffd2da, 0xe5d6ff, 0xffdeb4},
    {0xffffff, 0x1c1c1c, 0xffffff, 0x1c1c1c, 0xffffff, 0x1c1c1c},
    {0xffee97, 0xffe070, 0xfff5b8, 0xfada80, 0xffef69, 0xfffacd}
};

static bool valid(int palette, int color) {
    return palette >= 0 && palette < PC_PALETTE_COUNT && color >= 0 && color < PC_COLOR_COUNT;
}

uint32_t pc_note_rgb(int palette, int color) {
    return valid(palette, color) ? palettes[palette][color] : palettes[0][0];
}

uint32_t pc_ink_rgb(int palette, int color) {
    if (!valid(palette, color)) return 0x000000;
    return palette == 1 && (color & 1) ? 0xffffff : 0x000000;
}

uint32_t pc_bar_rgb(int palette, int color) {
    uint32_t rgb = pc_note_rgb(palette, color);
    uint32_t red = ((rgb >> 16) & 0xff) * 94 / 100, green = ((rgb >> 8) & 0xff) * 94 / 100, blue = (rgb & 0xff) * 94 / 100;
    return red << 16 | green << 8 | blue;
}
