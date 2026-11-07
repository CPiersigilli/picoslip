/* Line-preserving notes.ini reader and writer, compatible with the Windows
   private-profile functions used by src/picoslip.c and src/tags.c. */
#include "pc_ini.h"
#include "pc_text.h"
#include <stdlib.h>
#include <string.h>

typedef struct Line { pc_char *text; size_t length; } Line;

struct PCIni {
    Line *lines;
    size_t count, capacity;
    PCIniEncoding encoding;
};

/* Windows-1252 0x80..0x9F; 0 marks the five undefined bytes. */
static const uint16_t CP1252[32] = {
    0x20ac, 0, 0x201a, 0x0192, 0x201e, 0x2026, 0x2020, 0x2021, 0x02c6, 0x2030, 0x0160, 0x2039, 0x0152, 0, 0x017d, 0,
    0, 0x2018, 0x2019, 0x201c, 0x201d, 0x2022, 0x2013, 0x2014, 0x02dc, 0x2122, 0x0161, 0x203a, 0x0153, 0, 0x017e, 0x0178
};

static bool is_blank(pc_char unit) { return unit == ' ' || unit == '\t'; }
static pc_char fold(pc_char unit) { return unit >= 'A' && unit <= 'Z' ? (pc_char)(unit + 32) : unit; }

static bool same(const pc_char *a, size_t a_length, const pc_char *b) {
    size_t i;
    for (i = 0; i < a_length; ++i) if (!b[i] || fold(a[i]) != fold(b[i])) return false;
    return b[a_length] == 0;
}

static void trim(const pc_char *text, size_t *start, size_t *end) {
    while (*start < *end && is_blank(text[*start])) ++*start;
    while (*end > *start && is_blank(text[*end - 1])) --*end;
}

/* "[name]" with optional blanks; the name is what lies between the brackets. */
static bool header(const Line *line, size_t *start, size_t *length) {
    size_t begin = 0, end = line->length, close;
    trim(line->text, &begin, &end);
    if (begin >= end || line->text[begin] != '[') return false;
    for (close = begin + 1; close < end && line->text[close] != ']'; ++close) {}
    if (close >= end) return false;
    begin += 1;
    trim(line->text, &begin, &close);
    *start = begin; *length = close - begin;
    return true;
}

/* "key=value"; both sides trimmed, one pair of quotes removed from the value. */
static bool entry(const Line *line, size_t *key, size_t *key_length, size_t *value, size_t *value_length) {
    size_t equals = 0, begin = 0, end;
    while (equals < line->length && line->text[equals] != '=') ++equals;
    if (equals >= line->length) return false;
    end = equals;
    trim(line->text, &begin, &end);
    *key = begin; *key_length = end - begin;
    begin = equals + 1; end = line->length;
    trim(line->text, &begin, &end);
    if (end - begin >= 2 && line->text[begin] == '"' && line->text[end - 1] == '"') { ++begin; --end; }
    *value = begin; *value_length = end - begin;
    return true;
}

static bool reserve(PCIni *ini, size_t count) {
    Line *grown;
    size_t capacity = ini->capacity ? ini->capacity : 16;
    if (count <= ini->capacity) return true;
    while (capacity < count) capacity *= 2;
    grown = (Line *)realloc(ini->lines, capacity * sizeof(Line));
    if (!grown) return false;
    ini->lines = grown; ini->capacity = capacity;
    return true;
}

static bool insert_line(PCIni *ini, size_t index, const pc_char *text, size_t length) {
    pc_char *copy;
    if (!reserve(ini, ini->count + 1)) return false;
    copy = (pc_char *)malloc((length ? length : 1) * sizeof(pc_char));
    if (!copy) return false;
    if (length) memcpy(copy, text, length * sizeof(pc_char));
    memmove(ini->lines + index + 1, ini->lines + index, (ini->count - index) * sizeof(Line));
    ini->lines[index].text = copy; ini->lines[index].length = length;
    ++ini->count;
    return true;
}

static void remove_lines(PCIni *ini, size_t index, size_t count) {
    size_t i;
    for (i = index; i < index + count; ++i) free(ini->lines[i].text);
    memmove(ini->lines + index, ini->lines + index + count, (ini->count - index - count) * sizeof(Line));
    ini->count -= count;
}

PCIni *pc_ini_create(void) {
    return (PCIni *)calloc(1, sizeof(PCIni));
}

void pc_ini_free(PCIni *ini) {
    if (!ini) return;
    remove_lines(ini, 0, ini->count);
    free(ini->lines);
    free(ini);
}

static PCIni *split_lines(const pc_char *text, size_t length, PCIniEncoding encoding) {
    PCIni *ini = pc_ini_create();
    size_t start = 0, i = 0;
    if (!ini) return NULL;
    ini->encoding = encoding;
    while (i < length) {
        if (text[i] == '\r' || text[i] == '\n') {
            if (!insert_line(ini, ini->count, text + start, i - start)) { pc_ini_free(ini); return NULL; }
            if (text[i] == '\r' && i + 1 < length && text[i + 1] == '\n') ++i;
            start = ++i;
        } else ++i;
    }
    if (start < length && !insert_line(ini, ini->count, text + start, length - start)) { pc_ini_free(ini); return NULL; }
    return ini;
}

PCIni *pc_ini_parse(const unsigned char *bytes, size_t size) {
    pc_char *text;
    size_t length = 0, i;
    PCIni *ini;
    if (size >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe) {
        if (size & 1) return NULL;
        length = size / 2 - 1;
        text = (pc_char *)malloc((length ? length : 1) * sizeof(pc_char));
        if (!text) return NULL;
        for (i = 0; i < length; ++i) text[i] = (pc_char)(bytes[2 + i * 2] | bytes[3 + i * 2] << 8);
        ini = split_lines(text, length, PC_INI_UTF16LE);
    } else if (size >= 3 && bytes[0] == 0xef && bytes[1] == 0xbb && bytes[2] == 0xbf) {
        if (!pc_utf8_decode((const char *)bytes, size, NULL, 0, &length)) return NULL;
        text = (pc_char *)malloc((length ? length : 1) * sizeof(pc_char));
        if (!text) return NULL;
        if (!pc_utf8_decode((const char *)bytes, size, text, length, &length)) { free(text); return NULL; }
        ini = split_lines(text, length, PC_INI_UTF8);
    } else {
        length = size;
        text = (pc_char *)malloc((length ? length : 1) * sizeof(pc_char));
        if (!text) return NULL;
        for (i = 0; i < length; ++i) {
            unsigned char byte = bytes[i];
            text[i] = byte >= 0x80 && byte < 0xa0 && CP1252[byte - 0x80] ? (pc_char)CP1252[byte - 0x80] : (pc_char)byte;
        }
        ini = split_lines(text, length, PC_INI_ANSI);
    }
    free(text);
    return ini;
}

PCIniEncoding pc_ini_encoding(const PCIni *ini) { return ini->encoding; }
void pc_ini_set_encoding(PCIni *ini, PCIniEncoding encoding) { ini->encoding = encoding; }

/* Header line of a section, and the line after its last line. */
static bool find_section(const PCIni *ini, const pc_char *section, size_t *first, size_t *after) {
    size_t i, start, length;
    for (i = 0; i < ini->count; ++i) {
        if (!header(&ini->lines[i], &start, &length) || !same(ini->lines[i].text + start, length, section)) continue;
        *first = i;
        for (++i; i < ini->count && !header(&ini->lines[i], &start, &length); ++i) {}
        *after = i;
        return true;
    }
    return false;
}

static bool find_key(const PCIni *ini, size_t first, size_t after, const pc_char *key, size_t *index) {
    size_t i, start, length, value, value_length;
    for (i = first + 1; i < after; ++i) {
        if (entry(&ini->lines[i], &start, &length, &value, &value_length) &&
            same(ini->lines[i].text + start, length, key)) { *index = i; return true; }
    }
    return false;
}

bool pc_ini_get(const PCIni *ini, const pc_char *section, const pc_char *key, const pc_char **value, size_t *length) {
    size_t first, after, index, start, key_length, value_start;
    if (!find_section(ini, section, &first, &after) || !find_key(ini, first, after, key, &index)) return false;
    entry(&ini->lines[index], &start, &key_length, &value_start, length);
    *value = ini->lines[index].text + value_start;
    return true;
}

static bool ansi_can_hold(const pc_char *text) {
    size_t i;
    int j;
    for (i = 0; text[i]; ++i) {
        if (text[i] < 0x80 || (text[i] >= 0xa0 && text[i] <= 0xff)) continue;
        for (j = 0; j < 32 && CP1252[j] != text[i]; ++j) {}
        if (j == 32) return false;
    }
    return true;
}

static bool compose(PCIni *ini, size_t index, bool replace, const pc_char *key, const pc_char *value) {
    size_t key_length = pc_strlen(key), value_length = pc_strlen(value), length = key_length + 1 + value_length;
    pc_char *text = (pc_char *)malloc(length * sizeof(pc_char));
    bool ok;
    if (!text) return false;
    memcpy(text, key, key_length * sizeof(pc_char));
    text[key_length] = '=';
    memcpy(text + key_length + 1, value, value_length * sizeof(pc_char));
    if (replace) {
        free(ini->lines[index].text);
        ini->lines[index].text = text; ini->lines[index].length = length;
        return true;
    }
    ok = insert_line(ini, index, text, length);
    free(text);
    return ok;
}

bool pc_ini_set(PCIni *ini, const pc_char *section, const pc_char *key, const pc_char *value) {
    size_t first, after, index, last, start, length, value_start, value_length;
    if (!find_section(ini, section, &first, &after)) {
        size_t section_length = pc_strlen(section);
        pc_char *name;
        bool ok;
        if (!value) return true;
        name = (pc_char *)malloc((section_length + 2) * sizeof(pc_char));
        if (!name) return false;
        name[0] = '[';
        memcpy(name + 1, section, section_length * sizeof(pc_char));
        name[section_length + 1] = ']';
        ok = insert_line(ini, ini->count, name, section_length + 2);
        free(name);
        if (!ok) return false;
        first = ini->count - 1; after = ini->count;
    }
    if (find_key(ini, first, after, key, &index)) {
        if (!value) { remove_lines(ini, index, 1); return true; }
        if (ini->encoding == PC_INI_ANSI && !ansi_can_hold(value)) ini->encoding = PC_INI_UTF16LE;
        return compose(ini, index, true, key, value);
    }
    if (!value) return true;
    if (ini->encoding == PC_INI_ANSI && !ansi_can_hold(value)) ini->encoding = PC_INI_UTF16LE;
    /* New keys go after the section's last entry, before trailing blank lines. */
    last = first;
    for (index = first + 1; index < after; ++index)
        if (entry(&ini->lines[index], &start, &length, &value_start, &value_length)) last = index;
    return compose(ini, last + 1, false, key, value);
}

bool pc_ini_remove_section(PCIni *ini, const pc_char *section) {
    size_t first, after;
    if (!find_section(ini, section, &first, &after)) return true;
    remove_lines(ini, first, after - first);
    return true;
}

size_t pc_ini_section_count(const PCIni *ini) {
    size_t i, count = 0, start, length;
    for (i = 0; i < ini->count; ++i) if (header(&ini->lines[i], &start, &length)) ++count;
    return count;
}

bool pc_ini_section_name(const PCIni *ini, size_t index, const pc_char **name, size_t *length) {
    size_t i, start;
    for (i = 0; i < ini->count; ++i) {
        if (!header(&ini->lines[i], &start, length)) continue;
        if (!index--) { *name = ini->lines[i].text + start; return true; }
    }
    return false;
}

static bool to_ansi(pc_char unit, unsigned char *byte) {
    int j;
    if (unit < 0x80 || (unit >= 0xa0 && unit <= 0xff)) { *byte = (unsigned char)unit; return true; }
    for (j = 0; j < 32; ++j) if (CP1252[j] == unit) { *byte = (unsigned char)(0x80 + j); return true; }
    return false;
}

bool pc_ini_serialize(const PCIni *ini, unsigned char **bytes, size_t *size) {
    size_t units = 0, i, j, used = 0, capacity;
    unsigned char *out;
    for (i = 0; i < ini->count; ++i) units += ini->lines[i].length + 2;
    capacity = ini->encoding == PC_INI_UTF16LE ? units * 2 + 2 : units * 3 + 3;
    out = (unsigned char *)malloc(capacity ? capacity : 1);
    *bytes = NULL; *size = 0;
    if (!out) return false;
    if (ini->encoding == PC_INI_UTF16LE) { out[used++] = 0xff; out[used++] = 0xfe; }
    if (ini->encoding == PC_INI_UTF8) { out[used++] = 0xef; out[used++] = 0xbb; out[used++] = 0xbf; }
    for (i = 0; i < ini->count; ++i) {
        const Line *line = &ini->lines[i];
        if (ini->encoding == PC_INI_UTF16LE) {
            for (j = 0; j < line->length; ++j) { out[used++] = (unsigned char)(line->text[j] & 0xff); out[used++] = (unsigned char)(line->text[j] >> 8); }
            out[used++] = '\r'; out[used++] = 0; out[used++] = '\n'; out[used++] = 0;
        } else if (ini->encoding == PC_INI_UTF8) {
            size_t written;
            if (!pc_txt_encode(NULL, 0, line->text, line->length, (char *)out + used, capacity - used, &written)) {
                free(out); return false;
            }
            used += written;
            out[used++] = '\r'; out[used++] = '\n';
        } else {
            for (j = 0; j < line->length; ++j) if (!to_ansi(line->text[j], &out[used++])) { free(out); return false; }
            out[used++] = '\r'; out[used++] = '\n';
        }
    }
    *bytes = out; *size = used;
    return true;
}

void pc_ini_free_bytes(unsigned char *bytes) { free(bytes); }
