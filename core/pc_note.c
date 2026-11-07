/* Note identity, titles and checklist markers: rules from src/picoslip.c
   without any Win32 dependency. */
#include "pc_note.h"

size_t pc_strlen(const pc_char *text) {
    size_t length = 0;
    while (text[length]) ++length;
    return length;
}

static bool line_break(pc_char unit) { return unit == '\r' || unit == '\n'; }
static bool blank(pc_char unit) { return unit == ' ' || unit == '\t'; }

static size_t first_line_end(const pc_char *text, size_t length) {
    size_t end = 0;
    while (end < length && !line_break(text[end])) ++end;
    return end;
}

/* Zero-padded to at least `width` digits, like %0Nu. */
static bool put_number(pc_char *id, size_t *used, int value, int width) {
    pc_char digits[12];
    int count = 0;
    if (value < 0) return false;
    do { digits[count++] = (pc_char)('0' + value % 10); value /= 10; } while (value);
    while (count < width) digits[count++] = '0';
    if (*used + (size_t)count >= PC_ID_CAP) return false;
    while (count) id[(*used)++] = digits[--count];
    return true;
}

static bool put_char(pc_char *id, size_t *used, char unit) {
    if (*used + 1 >= PC_ID_CAP) return false;
    id[(*used)++] = (pc_char)unit;
    return true;
}

size_t pc_note_id_format(pc_char id[PC_ID_CAP], const PCDateTime *time, int suffix) {
    static const char prefix[] = "note-";
    size_t used = 0, i;
    id[0] = 0;
    if (time->year < 0 || time->year > 9999 || time->month < 1 || time->month > 12 ||
        time->day < 1 || time->day > 31 || time->hour < 0 || time->hour > 23 ||
        time->minute < 0 || time->minute > 59 || time->second < 0 || time->second > 59 ||
        time->millisecond < 0 || time->millisecond > 999 || suffix < 0 || suffix > 9999) return 0;
    for (i = 0; prefix[i]; ++i) id[used++] = (pc_char)prefix[i];
    if (!put_number(id, &used, time->year, 4) || !put_char(id, &used, '-') ||
        !put_number(id, &used, time->month, 2) || !put_char(id, &used, '-') ||
        !put_number(id, &used, time->day, 2) || !put_char(id, &used, '_') ||
        !put_number(id, &used, time->hour, 2) || !put_char(id, &used, '-') ||
        !put_number(id, &used, time->minute, 2) || !put_char(id, &used, '-') ||
        !put_number(id, &used, time->second, 2) || !put_char(id, &used, '-') ||
        !put_number(id, &used, time->millisecond, 3) || !put_char(id, &used, '-') ||
        !put_number(id, &used, suffix, 3)) { id[0] = 0; return 0; }
    id[used] = 0;
    return used;
}

static bool starts_with(const pc_char *text, const char *prefix) {
    size_t i;
    for (i = 0; prefix[i]; ++i) if (text[i] != (pc_char)prefix[i]) return false;
    return true;
}

static pc_char ascii_lower(pc_char unit) { return unit >= 'A' && unit <= 'Z' ? (pc_char)(unit + 32) : unit; }

bool pc_note_id_from_file_name(const pc_char *name, size_t length, pc_char id[PC_ID_CAP]) {
    size_t i;
    id[0] = 0;
    if (length < 9 || length - 4 >= PC_ID_CAP) return false;
    if (!starts_with(name, "note-") && !starts_with(name, "nota-")) return false;
    if (name[length - 4] != '.' || ascii_lower(name[length - 3]) != 't' ||
        ascii_lower(name[length - 2]) != 'x' || ascii_lower(name[length - 1]) != 't') return false;
    for (i = 0; i < length - 4; ++i) id[i] = name[i];
    id[length - 4] = 0;
    return true;
}

PCTitleSplit pc_title_split(const pc_char *text, size_t length, bool has_title_flag) {
    PCTitleSplit split = {false, 0, 0, 0};
    size_t end, body;
    if (!has_title_flag || !length || text[0] != '#') return split;
    end = first_line_end(text, length);
    if (end <= 1) return split;
    body = end;
    if (body < length && text[body] == '\r') ++body;
    if (body < length && text[body] == '\n') ++body;
    split.has_title = true;
    split.title_start = 1;
    split.title_length = end - 1;
    split.body_start = body;
    return split;
}

/* copy_title(): trim spaces and tabs; empty means no title. */
static bool trim_title(const pc_char *text, size_t start, size_t end, size_t *title_start, size_t *title_length) {
    while (start < end && blank(text[start])) ++start;
    while (end > start && blank(text[end - 1])) --end;
    *title_start = start;
    *title_length = end - start;
    return end > start;
}

bool pc_title_from_input(const pc_char *text, size_t length, size_t *start, size_t *title_length) {
    return trim_title(text, 0, first_line_end(text, length), start, title_length);
}

bool pc_title_promotion(const pc_char *text, size_t length, size_t caret, PCTitlePromotion *result) {
    size_t end, after;
    if (!length || text[0] != '#') return false;
    end = first_line_end(text, length);
    if (caret != end || !trim_title(text, 1, end, &result->title_start, &result->title_length)) return false;
    after = end;
    if (after < length && text[after] == '\r') ++after;
    if (after < length && text[after] == '\n') ++after;
    result->body_start = after;
    return true;
}

pc_char pc_todo_marker(const pc_char *paragraph, size_t length) {
    if (length < 2 || paragraph[1] != ' ') return 0;
    return paragraph[0] == PC_TODO_OPEN || paragraph[0] == PC_TODO_DONE ? paragraph[0] : 0;
}
