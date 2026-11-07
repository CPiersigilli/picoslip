#ifndef PC_TYPES_H
#define PC_TYPES_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* One UTF-16 code unit. On Windows it is wchar_t, so the existing Win32 code
   passes its strings unchanged; elsewhere Swift sees it as UInt16 (unichar).
   Every length and offset in PicoCore counts these units, as Windows does. */
#if defined(_WIN32)
#include <wchar.h>
typedef wchar_t pc_char;
#else
typedef uint16_t pc_char;
#endif

_Static_assert(sizeof(pc_char) == 2, "pc_char must be one UTF-16 code unit");

size_t pc_strlen(const pc_char *text);

#endif
