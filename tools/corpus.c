/* Golden compatibility corpus. Drives the real PicoSlip editor with the same
   gestures as the integration tests and keeps everything it writes: TXT, RTF,
   notes.ini, plus the formatting runs and search results that a port must
   reproduce byte for byte. C17, no framework. Usage: corpus.exe <new-folder> */
#define UNICODE
#define _UNICODE
#define WIN32_LEAN_AND_MEAN
#define _WIN32_WINNT 0x0A00
#include <windows.h>
#include <stdarg.h>
#include <stdlib.h>
#include "../src/search.h"
#include "../src/picoslip.c"

#define LINE_CAP 8192
#define ITEMS_CAP 64
#define EFFECTS (CFE_BOLD | CFE_ITALIC | CFE_UNDERLINE | CFE_STRIKEOUT)

typedef struct Output { HANDLE file; } Output;
typedef struct Case { wchar_t id[80]; const wchar_t *archive, *origin, *description; BOOL absent; } Case;

static Case cases[ITEMS_CAP];
static int case_count;
static wchar_t output_root[PATH_CAP];
static const wchar_t *current_archive;

static void require(BOOL condition, const char *message) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s (Windows error %lu)\n", message, GetLastError());
        exit(1);
    }
}

/* ---- UTF-8 text output ------------------------------------------------- */

static void out_open(Output *out, const wchar_t *name) {
    wchar_t path[PATH_CAP];
    require(swprintf_s(path, PATH_CAP, L"%s\\%s", output_root, name) >= 0, "compose output path");
    out->file = CreateFileW(path, GENERIC_WRITE, 0, NULL, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL);
    require(out->file != INVALID_HANDLE_VALUE, "create output file");
}

static void out_close(Output *out) {
    require(FlushFileBuffers(out->file) && CloseHandle(out->file), "close output file");
    out->file = INVALID_HANDLE_VALUE;
}

static void out_write(Output *out, const wchar_t *format, ...) {
    static wchar_t line[LINE_CAP];
    static char bytes[LINE_CAP * 3];
    va_list arguments;
    int length, size;
    DWORD written;
    va_start(arguments, format);
    length = _vsnwprintf_s(line, LINE_CAP, _TRUNCATE, format, arguments);
    va_end(arguments);
    require(length >= 0, "output line fits its buffer");
    if (!length) return;
    size = WideCharToMultiByte(CP_UTF8, 0, line, length, bytes, (int)sizeof(bytes), NULL, NULL);
    require(size > 0, "convert output line to UTF-8");
    require(WriteFile(out->file, bytes, (DWORD)size, &written, NULL) && written == (DWORD)size, "write output line");
}

/* Tabs, line breaks and backslashes are escaped so every record stays on one line. */
static const wchar_t *escaped(const wchar_t *text, wchar_t *buffer, size_t capacity) {
    size_t used = 0;
    for (; *text && used + 7 < capacity; ++text) {
        if (*text == L'\\') { buffer[used++] = L'\\'; buffer[used++] = L'\\'; }
        else if (*text == L'\t') { buffer[used++] = L'\\'; buffer[used++] = L't'; }
        else if (*text == L'\r') { buffer[used++] = L'\\'; buffer[used++] = L'r'; }
        else if (*text == L'\n') { buffer[used++] = L'\\'; buffer[used++] = L'n'; }
        else if (*text < L' ') used += (size_t)swprintf_s(buffer + used, capacity - used, L"\\u%04X", (unsigned)*text);
        else buffer[used++] = *text;
    }
    require(!*text, "escaped text fits its buffer");
    buffer[used] = 0;
    return buffer;
}

/* UTF-16 code units, the unit every offset in this corpus is measured in. */
static const wchar_t *hex_units(const wchar_t *text, wchar_t *buffer, size_t capacity) {
    size_t used = 0;
    buffer[0] = 0;
    for (; *text; ++text) {
        require(used + 6 < capacity, "hex text fits its buffer");
        used += (size_t)swprintf_s(buffer + used, capacity - used, used ? L" %04X" : L"%04X", (unsigned)*text);
    }
    return buffer;
}

/* ---- Editor gestures, identical to tests/tests.c ------------------------ */

static void replace_text(Note *note, const wchar_t *text) {
    SendMessageW(note->edit, EM_SETSEL, 0, -1);
    SendMessageW(note->edit, EM_REPLACESEL, TRUE, (LPARAM)text);
}

static void type_text(Note *note, const wchar_t *text) {
    SendMessageW(note->edit, EM_REPLACESEL, TRUE, (LPARAM)text);
}

static void with_modifiers(BOOL control, BOOL shift, BYTE previous[256]) {
    BYTE state[256];
    require(GetKeyboardState(previous), "read keyboard state");
    memcpy(state, previous, sizeof(state));
    state[VK_CONTROL] = state[VK_LCONTROL] = control ? 0x80 : 0;
    state[VK_SHIFT] = state[VK_LSHIFT] = state[VK_RSHIFT] = shift ? 0x80 : 0;
    require(SetKeyboardState(state), "set keyboard modifiers");
}

static void press_enter(Note *note, BOOL shift) {
    BYTE previous[256];
    with_modifiers(FALSE, shift, previous);
    SendMessageW(note->edit, WM_KEYDOWN, VK_RETURN, 1);
    SendMessageW(note->edit, WM_CHAR, L'\r', 1);
    SendMessageW(note->edit, WM_KEYUP, VK_RETURN, 1);
    require(SetKeyboardState(previous), "restore keyboard state");
}

static void press_backspace(Note *note) {
    SendMessageW(note->edit, WM_KEYDOWN, VK_BACK, 1);
    SendMessageW(note->edit, WM_CHAR, L'\b', 1);
    SendMessageW(note->edit, WM_KEYUP, VK_BACK, 1);
}

static void shortcut(Note *note, UINT key, BOOL shift) {
    BYTE previous[256];
    with_modifiers(TRUE, shift, previous);
    SendMessageW(note->edit, WM_KEYDOWN, key, 1);
    SendMessageW(note->edit, WM_CHAR, key - 'A' + 1, 1);
    require(SetKeyboardState(previous), "restore shortcut keyboard state");
}

/* Select the first occurrence of a fragment of the editor text (no line breaks). */
static void select_fragment(Note *note, const wchar_t *fragment) {
    const wchar_t *found = wcsstr(note->accepted_text, fragment);
    LONG start, breaks = 0;
    const wchar_t *cursor;
    require(found != NULL, "fragment to format exists");
    /* Rich Edit stores each CRLF as a single paragraph mark. */
    for (cursor = note->accepted_text; cursor < found; ++cursor) if (*cursor == L'\r' && cursor[1] == L'\n') ++breaks;
    start = (LONG)(found - note->accepted_text) - breaks;
    SendMessageW(note->edit, EM_SETSEL, start, start + (LONG)wcslen(fragment));
}

static void format_fragment(Note *note, const wchar_t *fragment, const char *effects) {
    select_fragment(note, fragment);
    for (; *effects; ++effects) {
        if (*effects == 'B') shortcut(note, 'B', FALSE);
        else if (*effects == 'I') shortcut(note, 'I', FALSE);
        else if (*effects == 'U') shortcut(note, 'U', FALSE);
        else if (*effects == 'S') shortcut(note, 'X', TRUE);
    }
    SendMessageW(note->edit, EM_SETSEL, (WPARAM)-1, -1);
}

static void click_checkbox(Note *note, LONG position) {
    POINTL point;
    LPARAM click;
    SendMessageW(note->edit, EM_POSFROMCHAR, (WPARAM)&point, position);
    click = MAKELPARAM(point.x + 2, point.y + note->line_height / 2);
    SendMessageW(note->edit, WM_LBUTTONDOWN, MK_LBUTTON, click);
    SendMessageW(note->edit, WM_LBUTTONUP, 0, click);
}

/* Rich Edit position of the start of a paragraph (0-based); CRLF is one mark there. */
static LONG paragraph_start(Note *note, int paragraph) {
    const wchar_t *text = note->accepted_text;
    LONG position = 0;
    while (paragraph > 0 && *text) {
        if (*text == L'\r' && text[1] == L'\n') { --paragraph; ++text; }
        ++text; ++position;
    }
    require(paragraph == 0, "paragraph exists");
    return position;
}

/* ---- Archive construction --------------------------------------------- */

static void record_case(const wchar_t *id, const wchar_t *origin, const wchar_t *description) {
    require(case_count < ITEMS_CAP, "case table has room");
    wcscpy_s(cases[case_count].id, 80, id);
    cases[case_count].archive = current_archive;
    cases[case_count].origin = origin;
    cases[case_count].description = description;
    cases[case_count].absent = FALSE;
    ++case_count;
}

static Note *create_note(const wchar_t *id, const wchar_t *origin, const wchar_t *description) {
    Note *note = open_note(id, next_color, FALSE);
    require(note != NULL, "create note with a fixed corpus id");
    /* Same bookkeeping as new_note(): the next note takes the next color. */
    next_color = (next_color + 1) % COLOR_COUNT;
    require(write_setting(L"app", L"next_color", next_color), "save next color");
    record_case(id, origin, description);
    return note;
}

static void save(Note *note) { require(save_note(note), "save corpus note"); }

static void begin_archive(const wchar_t *name) {
    wchar_t root[PATH_CAP];
    require(swprintf_s(root, PATH_CAP, L"%s\\%s", output_root, name) >= 0, "compose archive path");
    require(CreateDirectoryW(root, NULL), "create empty archive folder");
    require(make_paths(root), "select archive folder");
    current_archive = name;
    next_color = 0; current_palette = 0;
}

static void end_archive(void) {
    require(save_all(), "save all open notes");
    while (notes) destroy_note(notes);
    /* Flush the private-profile cache so notes.ini is complete on disk. */
    WritePrivateProfileStringW(NULL, NULL, NULL, state_path);
}

static void write_raw_file(const wchar_t *name, const void *data, DWORD size) {
    wchar_t path[PATH_CAP];
    HANDLE file;
    DWORD written;
    require(swprintf_s(path, PATH_CAP, L"%s\\%s", directory, name) >= 0, "compose external file path");
    file = CreateFileW(path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    require(file != INVALID_HANDLE_VALUE, "create external file");
    require(WriteFile(file, data, size, &written, NULL) && written == size && CloseHandle(file), "write external file");
}

static void build_legacy_archive(void) {
    Note *note;
    begin_archive(L"archive-legacy");
    note = create_note(L"note-2025-01-10_08-00-00-000-000", L"app",
                       L"Legacy archive: plain text, never tagged, so notes.ini stays in the original ANSI encoding.");
    replace_text(note, L"Promemoria semplice\r\nSeconda riga");
    save(note);
    note = create_note(L"note-2025-01-11_08-00-00-000-000", L"app",
                       L"Legacy archive: title promoted with Enter.");
    replace_text(note, L"#Titolo storico");
    press_enter(note, FALSE);
    type_text(note, L"Corpo della nota");
    save(note);
    note = create_note(L"note-2025-01-12_08-00-00-000-000", L"app",
                       L"Legacy archive: Ctrl+B on one word (the default font is bold, so this removes bold) and Ctrl+I on another.");
    replace_text(note, L"Testo con grassetto e corsivo");
    format_fragment(note, L"grassetto", "B");
    format_fragment(note, L"corsivo", "I");
    save(note);
    end_archive();
}

static void build_main_archive(void) {
    Note *note, *second;
    static const char bom_text[] = "\xEF\xBB\xBF" "File esterno con BOM UTF-8\r\nScritto da un altro editor.";
    static const char edited_text[] = "Testo modificato fuori da PicoSlip";
    wchar_t id[80];
    begin_archive(L"archive");

    note = create_note(L"note-2025-03-14_09-26-53-589-000", L"app",
                       L"Plain multi-line Unicode text in many scripts, emoji outside the BMP.");
    replace_text(note, L"Appunti di oggi\r\nCaffè, perché, € e 😀\r\n"
                       L"Ελληνικά Русский 漢字かなカナ 한국어 हिन्दी\r\nSeconda riga.");
    save(note);

    note = create_note(L"note-2025-03-14_10-00-00-000-000", L"app",
                       L"#Title + Enter promotes a title; has_title=1 and TXT starts with #.");
    replace_text(note, L"#Spesa è urgente");
    press_enter(note, FALSE);
    type_text(note, L"Caffè e pane\r\nLatte");
    save(note);

    note = create_note(L"note-2025-03-15_11-11-11-111-000", L"app",
                       L"#line + Shift+Enter stays literal body text; has_title=0.");
    replace_text(note, L"#appunto");
    press_enter(note, TRUE);
    type_text(note, L"Resta nel testo");
    save(note);

    note = create_note(L"note-2025-04-01_12-00-00-000-000", L"app",
                       L"Title only with surrounding spaces and emoji: trimmed title, empty body.");
    replace_text(note, L"#  Titolo 😀  ");
    press_enter(note, FALSE);
    save(note);

    note = create_note(L"note-2025-04-02_08-30-00-000-000", L"app",
                       L"Shortcuts on single words: Ctrl+B (removes the default bold), Ctrl+I, Ctrl+U, Ctrl+Shift+X, all four, none.");
    replace_text(note, L"grassetto corsivo sottolineato barrato tutti normale");
    format_fragment(note, L"grassetto", "B");
    format_fragment(note, L"corsivo", "I");
    format_fragment(note, L"sottolineato", "U");
    format_fragment(note, L"barrato", "S");
    format_fragment(note, L"tutti", "BIUS");
    save(note);

    note = create_note(L"note-2025-04-02_08-30-00-000-001", L"app",
                       L"Ctrl+I, Ctrl+B, Ctrl+U over accents, an emoji surrogate pair and CJK; same second as the previous note (suffix 001).");
    replace_text(note, L"Città 😀 漢字\r\nRiga due in grassetto");
    format_fragment(note, L"Città", "I");
    format_fragment(note, L"😀", "B");
    format_fragment(note, L"漢字", "U");
    format_fragment(note, L"grassetto", "B");
    save(note);

    note = create_note(L"note-2025-05-20_18-45-00-000-000", L"app",
                       L"Checklist: * + Shift+Enter, Enter adds items, Backspace exits; items 1 and 3 checked and struck.");
    replace_text(note, L"*");
    press_enter(note, TRUE);
    type_text(note, L"Primo"); press_enter(note, FALSE);
    type_text(note, L"Secondo"); press_enter(note, FALSE);
    type_text(note, L"Terzo"); press_enter(note, FALSE);
    press_backspace(note);
    type_text(note, L"Testo normale");
    click_checkbox(note, paragraph_start(note, 0));
    click_checkbox(note, paragraph_start(note, 2));
    require(note->accepted_text[0] == L'\x2611', "first checklist item is checked");
    save(note);

    note = create_note(L"note-2025-06-01_07-00-00-000-000", L"app",
                       L"Title, checklist and formatting combined, with tags.");
    replace_text(note, L"#Viaggio");
    press_enter(note, FALSE);
    replace_text(note, L"*");
    press_enter(note, TRUE);
    type_text(note, L"Passaporto"); press_enter(note, FALSE);
    type_text(note, L"Biglietti importanti");
    format_fragment(note, L"importanti", "B");
    click_checkbox(note, paragraph_start(note, 0));
    require(set_tags(note, L"viaggi; Lavoro"), "set combined tags");
    save(note);

    note = create_note(L"note-2025-06-10_09-00-00-000-000", L"app",
                       L"Tags normalized: case and # removed, duplicates merged, accents kept, sorted ordinally.");
    replace_text(note, L"Riunione di progetto con il cliente");
    require(set_tags(note, L"Lavoro; project alpha; Città; #Work; ÉTÉ; work"), "set normalized tags");
    save(note);

    note = create_note(L"note-2025-06-11_09-00-00-000-000", L"app",
                       L"Single tag; body words used by tag-plus-text queries.");
    replace_text(note, L"riunione settimanale\r\nrelease plan per luglio");
    require(set_tags(note, L"personale"), "set single tag");
    save(note);

    note = create_note(L"note-2025-07-01_16-20-00-000-000", L"app",
                       L"Untagged note sharing a word with tagged notes (for -#).");
    replace_text(note, L"Idee per il progetto, senza tag");
    save(note);

    note = create_note(L"note-2025-07-02_16-20-00-000-000", L"app",
                       L"Closed with the close button: TXT kept, open=0, tags kept.");
    replace_text(note, L"Chiusa, ma conservata.");
    require(set_tags(note, L"archivio"), "set closed-note tag");
    save(note);
    SendMessageW(note->window, WM_CLOSE, 0, 0);

    /* The palette menu changes the app preference used by the next new note. */
    note_command(notes, CMD_PALETTE + 1);
    note = create_note(L"note-2025-08-08_08-08-08-008-000", L"app",
                       L"Collapsed note created with the black-and-white palette, opacity 70, size Large.");
    replace_text(note, L"Bianco e nero, compressa");
    note_command(note, CMD_OPACITY + 3);
    note_command(note, CMD_SIZE + 2);
    save(note);
    toggle_note(note);
    require(note->collapsed && note->palette == 1 && note->opacity == 70 && note->size == 2, "collapsed note options");

    note_command(note, CMD_PALETTE + 2);
    second = create_note(L"note-2025-09-09_09-09-09-009-000", L"app",
                         L"Yellow-only palette, enlarged twice with Ctrl+wheel (custom size, size=-1).");
    replace_text(second, L"Gialla e ridimensionata");
    wheel_resize(second, WHEEL_DELTA * 2);
    save(second);
    require(second->size == -1 && second->palette == 2, "wheel resize gives a custom size");
    note_command(second, CMD_PALETTE + 0);

    note = create_note(L"note-2025-10-10_10-10-10-010-000", L"app",
                       L"Whitespace kept verbatim: blank line, tab indent, trailing spaces.");
    replace_text(note, L"Riga 1\r\n\r\n\tIndentata con tab  \r\nFine con spazi   ");
    save(note);

    note = create_note(L"note-2025-10-11_10-10-10-010-000", L"app",
                       L"One long paragraph that wraps in the editor without line breaks.");
    replace_text(note, L"Questo paragrafo è lungo apposta per andare a capo automaticamente nella nota: "
                       L"non contiene interruzioni di riga e serve a verificare che la misura del testo "
                       L"e il salvataggio restino coerenti fra le piattaforme.");
    save(note);

    note = create_note(L"nota-2025-11-01_12-00-00-000-000", L"app",
                       L"Legacy Italian file prefix nota- (still restored by the app).");
    replace_text(note, L"Prefisso storico nota-");
    save(note);

    note = create_note(L"note-2025-11-02_12-00-00-000-000", L"app",
                       L"Case-folding and accent edge cases for search.");
    replace_text(note, L"Straße İstanbul ﬁnale ＦＵＬＬ ǅemal Σίσυφος résumé naïve Ångström Ωmega\r\n"
                       L"decomposta: cafe\x0301");
    save(note);

    note = create_note(L"note-2025-11-03_12-00-00-000-000", L"app",
                       L"Emoji sequences (ZWJ, skin tone, flag) and right-to-left scripts.");
    replace_text(note, L"Sviluppo 👩‍💻 ok 👍🏽 bandiera 🇮🇹\r\nעברית\r\nالعربية");
    save(note);

    note = create_note(L"note-2026-01-05_08-00-00-000-000", L"app",
                       L"Title set from the title dialog on an existing body (set_title).");
    replace_text(note, L"Corpo esistente");
    require(set_title(note, L"  Titolo dal menu  "), "set title from dialog");
    save(note);

    note = create_note(L"note-2026-01-06_08-00-00-000-000", L"app",
                       L"Created but left empty: no TXT, RTF or notes.ini section may exist.");
    save(note);
    require(!note->persisted, "empty note is not persisted");
    cases[case_count - 1].absent = TRUE;
    destroy_note(note);

    wcscpy_s(id, 80, L"note-2026-02-01_08-00-00-000-000");
    write_raw_file(L"note-2026-02-01_08-00-00-000-000.txt", bom_text, (DWORD)(sizeof(bom_text) - 1));
    record_case(id, L"generator",
                L"External TXT with a UTF-8 BOM and no notes.ini section; opened by the app, which adds layout only.");
    note = open_note(id, 0, TRUE);
    require(note && !wcscmp(note->accepted_text, L"File esterno con BOM UTF-8\r\nScritto da un altro editor."),
            "BOM is ignored when reading");

    note = create_note(L"note-2026-02-02_08-00-00-000-000", L"app+generator",
                       L"Formatted RTF saved by the app, then TXT replaced externally: the stale RTF must be ignored.");
    replace_text(note, L"Testo originale in grassetto");
    format_fragment(note, L"grassetto", "B");
    save(note);
    wcscpy_s(id, 80, note->id);
    destroy_note(note);
    write_raw_file(L"note-2026-02-02_08-00-00-000-000.txt", edited_text, (DWORD)(sizeof(edited_text) - 1));

    end_archive();
}

/* ---- Read-back: formatting runs exactly as Rich Edit reports them ------- */

static DWORD effects_between(Note *note, LONG start, LONG end) {
    CHARFORMAT2W format = {0};
    format.cbSize = sizeof(format);
    SendMessageW(note->edit, EM_SETSEL, start, end);
    SendMessageW(note->edit, EM_GETCHARFORMAT, SCF_SELECTION, (LPARAM)&format);
    return format.dwEffects & format.dwMask & EFFECTS;
}

static void flush_run(wchar_t *runs, size_t capacity, size_t start, size_t end, DWORD effects) {
    size_t used = wcslen(runs);
    if (!effects || end <= start) return;
    require(swprintf_s(runs + used, capacity - used, L"%s%zu+%zu:%s%s%s%s", used ? L" " : L"", start, end - start,
                       effects & CFE_BOLD ? L"B" : L"", effects & CFE_ITALIC ? L"I" : L"",
                       effects & CFE_UNDERLINE ? L"U" : L"", effects & CFE_STRIKEOUT ? L"S" : L"") >= 0,
            "formatting runs fit their buffer");
}

/* Offsets are UTF-16 code units of the TXT body, where CRLF counts as two. */
static void write_runs(Output *out, Note *note) {
    static wchar_t runs[LINE_CAP];
    GETTEXTLENGTHEX length = {GTL_PRECISE | GTL_NUMCHARS, 1200};
    LONG count = (LONG)SendMessageW(note->edit, EM_GETTEXTLENGTHEX, (WPARAM)&length, 0), position = 0;
    size_t offset = 0, run_start = 0;
    DWORD run = 0;
    runs[0] = 0;
    while (position < count) {
        wchar_t unit[3] = {0};
        TEXTRANGEW range;
        LONG width;
        DWORD effects;
        range.chrg.cpMin = position; range.chrg.cpMax = min(position + 2, count); range.lpstrText = unit;
        SendMessageW(note->edit, EM_GETTEXTRANGE, 0, (LPARAM)&range);
        width = IS_HIGH_SURROGATE(unit[0]) && position + 1 < count ? 2 : 1;
        effects = effects_between(note, position, position + width);
        if (effects != run) { flush_run(runs, LINE_CAP, run_start, offset, run); run = effects; run_start = offset; }
        offset += unit[0] == L'\r' ? 2 : (size_t)width;
        position += width;
    }
    flush_run(runs, LINE_CAP, run_start, offset, run);
    out_write(out, L"%s\t%zu\t%s\n", note->id, offset, runs);
}

static int case_compare(const void *a, const void *b) {
    return wcscmp(((const Case *)a)->id, ((const Case *)b)->id);
}

/* Reopening a note rewrites its layout (a closed note would become open), so
   formatting is read back from a disposable copy and the corpus stays untouched. */
static void copy_folder(const wchar_t *source, const wchar_t *target, BOOL remove) {
    WIN32_FIND_DATAW found;
    wchar_t pattern[PATH_CAP], from[PATH_CAP], to[PATH_CAP];
    HANDLE search;
    require(swprintf_s(pattern, PATH_CAP, L"%s\\*", source) >= 0, "compose copy pattern");
    if (!remove) require(CreateDirectoryW(target, NULL), "create read-back copy");
    search = FindFirstFileW(pattern, &found);
    require(search != INVALID_HANDLE_VALUE, "list folder to copy");
    do {
        if (found.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) continue;
        require(swprintf_s(from, PATH_CAP, L"%s\\%s", source, found.cFileName) >= 0 &&
                swprintf_s(to, PATH_CAP, L"%s\\%s", target, found.cFileName) >= 0, "compose copy paths");
        require(remove ? DeleteFileW(from) : CopyFileW(from, to, TRUE), remove ? "remove read-back file" : "copy archive file");
    } while (FindNextFileW(search, &found));
    FindClose(search);
    if (remove) require(RemoveDirectoryW(source), "remove read-back copy");
}

static void write_cases_and_runs(const wchar_t *archive, const wchar_t *runs_name, int first, int last) {
    Output out;
    wchar_t source[PATH_CAP], copy[PATH_CAP], temporary[PATH_CAP];
    int i;
    require(swprintf_s(source, PATH_CAP, L"%s\\%s", output_root, archive) >= 0, "compose archive path");
    require(GetTempPathW(PATH_CAP, temporary) != 0 &&
            swprintf_s(copy, PATH_CAP, L"%sPicoSlip-corpus-%s-%lu-%llu", temporary, archive,
                       GetCurrentProcessId(), GetTickCount64()) >= 0, "compose read-back path");
    copy_folder(source, copy, FALSE);
    require(make_paths(copy), "select read-back copy");
    out_open(&out, runs_name);
    out_write(&out, L"# id\tbody_utf16_length\truns (offset+length:BIUS, UTF-16 units of the TXT body, CRLF=2)\n");
    for (i = first; i < last; ++i) {
        Note *note;
        if (cases[i].absent) continue;
        note = open_note(cases[i].id, 0, TRUE);
        require(note != NULL, "reopen corpus note for read-back");
        write_runs(&out, note);
        destroy_note(note);
    }
    out_close(&out);
    WritePrivateProfileStringW(NULL, NULL, NULL, state_path);
    copy_folder(copy, copy, TRUE);
}

/* ---- Search expectations ---------------------------------------------- */

static SearchItem items[ITEMS_CAP];
static int item_count;

static int item_compare(const void *a, const void *b) {
    return wcscmp(((const SearchItem *)a)->id, ((const SearchItem *)b)->id);
}

static void load_items(void) {
    WIN32_FIND_DATAW found;
    wchar_t pattern[PATH_CAP];
    HANDLE search;
    int i;
    item_count = 0;
    require(swprintf_s(pattern, PATH_CAP, L"%s\\*.txt", directory) >= 0, "compose search pattern");
    search = FindFirstFileW(pattern, &found);
    require(search != INVALID_HANDLE_VALUE, "list archive notes");
    do {
        size_t length = wcslen(found.cFileName);
        require(item_count < ITEMS_CAP && length > 4 && length - 4 < 80, "archive note name fits");
        wcsncpy_s(items[item_count].id, 80, found.cFileName, length - 4);
        ++item_count;
    } while (FindNextFileW(search, &found));
    FindClose(search);
    qsort(items, (size_t)item_count, sizeof(items[0]), item_compare);
    for (i = 0; i < item_count; ++i) items[i].index = i;
}

static SearchResult *run_query(SearchWorker *worker, const wchar_t *query, const wchar_t *tag) {
    ULONGLONG deadline = GetTickCount64() + 60000;
    require(search_submit_filtered(worker, directory, state_path, query, tag, items, item_count), "submit search");
    do {
        MSG message;
        SearchResult *result;
        while (PeekMessageW(&message, NULL, 0, 0, PM_REMOVE)) DispatchMessageW(&message);
        result = search_take(worker);
        if (result) return result;
        MsgWaitForMultipleObjects(0, NULL, FALSE, 100, QS_ALLINPUT);
    } while (GetTickCount64() < deadline);
    require(FALSE, "search completes within a minute");
    return NULL;
}

static void write_search_golden(void) {
    static const wchar_t *queries[] = {
        L"", L"caffè", L"CAFFE", L"cafe", L"café", L"cafe\x0301", L"perche", L"😀", L"漢字", L"カナ",
        L"riga", L"RIGA", L"seconda riga", L"\"seconda riga\"", L"\"release plan\"", L"release plan",
        L"#lavoro", L"#LAVORO", L"#work", L"#\"project alpha\"", L"#project", L"#città", L"#citta", L"#été",
        L"#personale riunione", L"#personale \"release plan\"", L"-#", L"-# progetto", L"progetto",
        L"#archivio", L"chiusa", L"strasse", L"STRASSE", L"straße", L"istanbul", L"İstanbul", L"finale",
        L"ﬁnale", L"full", L"ＦＵＬＬ", L"dzemal", L"ǅemal", L"σίσυφος", L"ΣΙΣΥΦΟΣ", L"σισυφος", L"resume",
        L"naive", L"angstrom", L"Ωmega", L"ωmega", L"☑", L"☐", L"passaporto", L"importanti",
        L"👩‍💻", L"👍", L"🇮🇹", L"עברית", L"العربية", L"tab", L"\t", L"bom", L"modificato", L"originale",
        L"titolo", L"menu", L"spesa", L"#", L"\"\"", L"#a;b", L"#\"\"", L"a b c d e f g h i j k l m n o p",
        L"a b c d e f g h i j k l m n o p q", L"nota-", L"prefisso"
    };
    static const wchar_t *filtered[][2] = {
        {L"", L"lavoro"}, {L"riunione", L"lavoro"}, {L"riunione", L"personale"}, {L"", L"città"},
        {L"", L"citta"}, {L"progetto", L"work"}, {L"", L"viaggi"}
    };
    SearchWorker *worker;
    HWND window;
    Output out;
    wchar_t escape[1024], hex[4096];
    size_t i;
    int j;
    window = CreateWindowExW(0, L"STATIC", L"", 0, 0, 0, 0, 0, HWND_MESSAGE, NULL, instance, NULL);
    require(window != NULL, "create search message window");
    worker = search_create(window, WM_APP + 99);
    require(worker != NULL, "create search worker");
    load_items();
    out_open(&out, L"search-golden.tsv");
    out_write(&out, L"# kind\tquery\tquery_utf16\ttag\terror\tcount\tunreadable\tfiles_read\thits (id@byte_offset+byte_length, - = no excerpt)\n");
    for (i = 0; i < sizeof(queries) / sizeof(queries[0]) + sizeof(filtered) / sizeof(filtered[0]); ++i) {
        BOOL plain = i < sizeof(queries) / sizeof(queries[0]);
        const wchar_t *query = plain ? queries[i] : filtered[i - sizeof(queries) / sizeof(queries[0])][0];
        const wchar_t *tag = plain ? L"" : filtered[i - sizeof(queries) / sizeof(queries[0])][1];
        SearchResult *result = run_query(worker, query, tag);
        out_write(&out, L"%s\t%s\t%s\t%s\t%s\t%d\t%d\t%u\t", plain ? L"query" : L"filtered",
                  escaped(query, escape, 1024), hex_units(query, hex, 4096), tag,
                  result->error ? result->error : L"", result->count, result->unreadable, result->files_read);
        for (j = 0; j < result->count; ++j) {
            const SearchHit *hit = &result->hits[j];
            if (hit->offset == MAXDWORD) out_write(&out, L"%s%s@-", j ? L" " : L"", items[hit->index].id);
            else out_write(&out, L"%s%s@%lu+%lu", j ? L" " : L"", items[hit->index].id, hit->offset, hit->bytes);
        }
        out_write(&out, L"\n");
        search_result_free(result);
    }
    out_close(&out);
    search_destroy(worker);
    DestroyWindow(window);
}

/* ---- Manifest --------------------------------------------------------- */

typedef LONG (WINAPI *VersionFunction)(OSVERSIONINFOW *);

static void write_manifest(void) {
    OSVERSIONINFOW version = {sizeof(version)};
    NLSVERSIONINFOEX nls = {sizeof(nls)};
    VersionFunction get_version = (VersionFunction)GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "RtlGetVersion");
    wchar_t commit[64] = L"local", escape[1024];
    SYSTEMTIME now;
    Output out;
    int i;
    if (get_version) get_version(&version);
    GetNLSVersionEx(COMPARE_STRING, LOCALE_NAME_INVARIANT, &nls);
    if (!GetEnvironmentVariableW(L"GITHUB_SHA", commit, 64)) wcscpy_s(commit, 64, L"local");
    GetSystemTime(&now);
    out_open(&out, L"manifest.tsv");
    out_write(&out, L"# key\tvalue\n");
    out_write(&out, L"generator\ttools/corpus.c\ncommit\t%s\n", commit);
    out_write(&out, L"generated_utc\t%04u-%02u-%02uT%02u:%02u:%02uZ\n", now.wYear, now.wMonth, now.wDay,
              now.wHour, now.wMinute, now.wSecond);
    out_write(&out, L"windows\t%lu.%lu.%lu\nnls_version\t%08lX\nsystem_dpi\t%u\n", version.dwMajorVersion,
              version.dwMinorVersion, version.dwBuildNumber, nls.dwNLSVersion, GetDpiForSystem());
    out_close(&out);
    qsort(cases, (size_t)case_count, sizeof(cases[0]), case_compare);
    out_open(&out, L"cases.tsv");
    out_write(&out, L"# id\tarchive\tfiles present (txt, rtf, none)\torigin (app = written by PicoSlip, generator = written directly)\tdescription\n");
    for (i = 0; i < case_count; ++i) {
        wchar_t path[PATH_CAP];
        BOOL txt, rtf;
        require(swprintf_s(path, PATH_CAP, L"%s\\%s\\%s.txt", output_root, cases[i].archive, cases[i].id) >= 0, "compose case path");
        txt = GetFileAttributesW(path) != INVALID_FILE_ATTRIBUTES;
        require(swprintf_s(path, PATH_CAP, L"%s\\%s\\%s.rtf", output_root, cases[i].archive, cases[i].id) >= 0, "compose case path");
        rtf = GetFileAttributesW(path) != INVALID_FILE_ATTRIBUTES;
        require(txt != cases[i].absent, "file presence matches the case");
        out_write(&out, L"%s\t%s\t%s\t%s\t%s\n", cases[i].id, cases[i].archive,
                  txt && rtf ? L"txt+rtf" : txt ? L"txt" : rtf ? L"rtf" : L"none", cases[i].origin,
                  escaped(cases[i].description, escape, 1024));
    }
    out_close(&out);
}

int wmain(int argc, wchar_t **argv) {
    wchar_t main_root[PATH_CAP];
    int legacy_cases;
    if (argc != 2) { fputs("Usage: corpus.exe <new-output-folder>\n", stderr); return 2; }
    require(GetFullPathNameW(argv[1], PATH_CAP, output_root, NULL) > 0, "resolve output folder");
    require(CreateDirectoryW(output_root, NULL), "create a new output folder");
    instance = GetModuleHandleW(NULL); testing = TRUE;
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    app_icon = (HICON)LoadImageW(instance, MAKEINTRESOURCEW(IDI_APP), IMAGE_ICON, 32, 32, 0);
    require(app_icon != NULL && register_classes(), "register native window classes");
    controller = CreateWindowExW(WS_EX_TOOLWINDOW, APP_CLASS, L"PicoSlip corpus", WS_OVERLAPPED,
                                 0, 0, 0, 0, NULL, NULL, instance, NULL);
    require(controller != NULL, "create controller window");

    build_legacy_archive();
    legacy_cases = case_count;
    build_main_archive();
    write_cases_and_runs(L"archive-legacy", L"formatting-legacy.tsv", 0, legacy_cases);
    write_cases_and_runs(L"archive", L"formatting.tsv", legacy_cases, case_count);
    require(swprintf_s(main_root, PATH_CAP, L"%s\\archive", output_root) >= 0 && make_paths(main_root),
            "select main archive for search");
    write_search_golden();
    write_manifest();

    DestroyWindow(controller);
    if (app_icon) DestroyIcon(app_icon);
    printf("Corpus written: %d notes described in cases.tsv\n", case_count);
    return 0;
}
