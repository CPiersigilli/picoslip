#ifndef PC_INI_H
#define PC_INI_H

#include "pc_types.h"

/* notes.ini as the Windows private-profile API sees it. Sections and keys
   match case-insensitively (ASCII), values are trimmed and lose one pair of
   enclosing double quotes. Every line that is not touched is written back
   unchanged, so settings from other versions survive.

   Encoding follows tags.c: a file starts as ANSI (Windows-1252) and becomes
   UTF-16LE with BOM; a UTF-8 BOM file is also read. Writing a value that
   ANSI cannot hold switches the file to UTF-16LE, as tags_write() does. */
typedef struct PCIni PCIni;

typedef enum PCIniEncoding { PC_INI_ANSI = 0, PC_INI_UTF8 = 1, PC_INI_UTF16LE = 2 } PCIniEncoding;

PCIni *pc_ini_create(void);
/* NULL for invalid text (odd UTF-16 length, invalid UTF-8) or no memory. */
PCIni *pc_ini_parse(const unsigned char *bytes, size_t size);
void pc_ini_free(PCIni *ini);

PCIniEncoding pc_ini_encoding(const PCIni *ini);
void pc_ini_set_encoding(PCIni *ini, PCIniEncoding encoding);

/* Strings are NUL-terminated. The value pointer stays valid until the next
   change to the file; it is not NUL-terminated. */
bool pc_ini_get(const PCIni *ini, const pc_char *section, const pc_char *key, const pc_char **value, size_t *length);
/* A NULL value deletes the key. */
bool pc_ini_set(PCIni *ini, const pc_char *section, const pc_char *key, const pc_char *value);
bool pc_ini_remove_section(PCIni *ini, const pc_char *section);

size_t pc_ini_section_count(const PCIni *ini);
/* Name of the n-th section header, not NUL-terminated. */
bool pc_ini_section_name(const PCIni *ini, size_t index, const pc_char **name, size_t *length);

/* CRLF after every line, BOM for UTF-16LE and UTF-8. Free with pc_ini_free_bytes. */
bool pc_ini_serialize(const PCIni *ini, unsigned char **bytes, size_t *size);
void pc_ini_free_bytes(unsigned char *bytes);

#endif
