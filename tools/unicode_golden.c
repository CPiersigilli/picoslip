/* Unicode reference tables for porting. Calls the exact folding, query and tag
   code that PicoSlip runs (search.c is included for its private helpers) over
   every code point, so a port can match Windows without the Windows NLS APIs.
   C17, no framework. Usage: unicode_golden.exe <new-folder> */
#include "../src/search.c"
#include <stdarg.h>

#define LINE_CAP 4096

typedef struct Output { HANDLE file; } Output;
static wchar_t output_root[1024];

static void require(BOOL condition, const char *message) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s (Windows error %lu)\n", message, GetLastError());
        exit(1);
    }
}

static void out_open(Output *out, const wchar_t *name) {
    wchar_t path[1024];
    require(swprintf_s(path, 1024, L"%s\\%s", output_root, name) >= 0, "compose output path");
    out->file = CreateFileW(path, GENERIC_WRITE, 0, NULL, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL);
    require(out->file != INVALID_HANDLE_VALUE, "create output file");
}

static void out_close(Output *out) {
    require(FlushFileBuffers(out->file) && CloseHandle(out->file), "close output file");
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

static const wchar_t *hex_units(const wchar_t *text, int length, wchar_t *buffer, size_t capacity) {
    size_t used = 0;
    int i;
    buffer[0] = 0;
    for (i = 0; i < length; ++i) {
        require(used + 6 < capacity, "hex text fits its buffer");
        used += (size_t)swprintf_s(buffer + used, capacity - used, used ? L" %04X" : L"%04X", (unsigned)text[i]);
    }
    return buffer;
}

/* Printable form for review only; the *_utf16 columns are authoritative. */
static const wchar_t *escaped(const wchar_t *text, wchar_t *buffer, size_t capacity) {
    size_t used = 0;
    for (; *text && used + 7 < capacity; ++text) {
        if (*text == L'\\') { buffer[used++] = L'\\'; buffer[used++] = L'\\'; }
        else if (*text < L' ') used += (size_t)swprintf_s(buffer + used, capacity - used, L"\\u%04X", (unsigned)*text);
        else buffer[used++] = *text;
    }
    require(!*text, "escaped text fits its buffer");
    buffer[used] = 0;
    return buffer;
}

static int encode(unsigned code_point, wchar_t text[3]) {
    if (code_point < 0x10000) { text[0] = (wchar_t)code_point; text[1] = 0; return 1; }
    code_point -= 0x10000;
    text[0] = (wchar_t)(0xd800 + (code_point >> 10));
    text[1] = (wchar_t)(0xdc00 + (code_point & 0x3ff));
    text[2] = 0;
    return 2;
}

/* Consecutive code points with the same verdict (ERR, EMPTY, REJECT) collapse
   into one START..END line, which keeps tables over unassigned planes small. */
typedef struct Range { Output *out; const wchar_t *label; unsigned start, end; } Range;

static void range_flush(Range *range) {
    if (!range->label) return;
    if (range->start == range->end) out_write(range->out, L"%04X\t%s\n", range->start, range->label);
    else out_write(range->out, L"%04X..%04X\t%s\n", range->start, range->end, range->label);
    range->label = NULL;
}

static void range_add(Range *range, unsigned code_point, const wchar_t *label) {
    if (range->label && (range->label != label || range->end + 1 != code_point)) range_flush(range);
    if (!range->label) { range->label = label; range->start = code_point; }
    range->end = code_point;
}

/* Search folding (fold_text): NFD, invariant uppercase, nonspacing marks removed.
   Only code points that do not map to themselves are listed. */
static void write_fold_table(void) {
    FoldBuffer buffer = {0};
    Output out;
    wchar_t text[3], hex[256];
    unsigned code_point;
    unsigned changed = 0, failed = 0;
    Range range = {0};
    out_open(&out, L"fold.tsv");
    range.out = &out;
    out_write(&out, L"# code_point\tfolded_utf16 (empty = removed, ERR = rejected, START..END = range). Unlisted code points fold to themselves.\n");
    for (code_point = 0; code_point <= 0x10ffff; ++code_point) {
        int length, folded;
        if (code_point >= 0xd800 && code_point <= 0xdfff) continue;
        length = encode(code_point, text);
        folded = fold_text(&buffer, text, length);
        if (folded < 0) { range_add(&range, code_point, L"ERR"); ++failed; continue; }
        if (folded == length && !memcmp(buffer.folded, text, (size_t)length * sizeof(wchar_t))) continue;
        range_flush(&range);
        out_write(&out, L"%04X\t%s\n", code_point, hex_units(buffer.folded, folded, hex, 256));
        ++changed;
    }
    range_flush(&range);
    out_close(&out);
    fold_free(&buffer);
    printf("fold.tsv: %u changed, %u rejected\n", changed, failed);
}

/* Context matters for normalization; these sequences are folded as one block. */
static void write_fold_sequences(void) {
    static const wchar_t *samples[] = {
        L"Caffè", L"cafe\x0301", L"CAFE\x0301", L"perché", L"Straße", L"ß", L"ẞ", L"İstanbul", L"ı", L"ﬁnale",
        L"ﬀ", L"ＦＵＬＬ", L"ǅemal", L"ǆ", L"Σίσυφος", L"ς", L"résumé", L"naïve", L"Ångström", L"Å", L"Ω",
        L"ệ", L"e\x0323\x0302", L"e\x0302\x0323", L"한국어", L"\x1112\x1161\x11AB", L"ﾊﾝｶｸ", L"ガ", L"か\x3099",
        L"عَرَبِيّ", L"שָׁלוֹם", L"हिन्दी", L"ภาษาไทย", L"👩‍💻", L"👍🏽", L"🇮🇹", L"😀", L"漢字", L"Ǆ", L"ǈ",
        L"½", L"²", L"™", L"ℌ", L"①", L"\x00A0", L"\x2003", L"\t", L"Œuvre", L"æ", L"ø", L"ł", L"đ", L"ħ",
        L"Ⅻ", L"ⓐ", L"ǰ", L"ŉ", L"ΐ", L"ﬆ", L"Ꭰ", L"ꭰ", L"𐐀", L"𐐨", L"ᲀ", L"K", L"µ", L"ſ"
    };
    FoldBuffer buffer = {0};
    Output out;
    wchar_t hex_in[512], hex_out[512], printable[256];
    size_t i;
    out_open(&out, L"fold-sequences.tsv");
    out_write(&out, L"# sample\tinput_utf16\tfolded_utf16 (ERR = rejected)\n");
    for (i = 0; i < sizeof(samples) / sizeof(samples[0]); ++i) {
        int length = (int)wcslen(samples[i]), folded = fold_text(&buffer, samples[i], length);
        out_write(&out, L"%s\t%s\t%s\n", escaped(samples[i], printable, 256), hex_units(samples[i], length, hex_in, 512),
                  folded < 0 ? L"ERR" : hex_units(buffer.folded, folded, hex_out, 512));
    }
    out_close(&out);
    fold_free(&buffer);
}

/* Tag canonical form (tags_normalize) of every single code point used as a tag. */
static void write_tag_table(void) {
    Output out;
    wchar_t text[3], normal[TAGS_CAP], hex[256];
    unsigned code_point, changed = 0;
    Range range = {0};
    out_open(&out, L"tags-fold.tsv");
    range.out = &out;
    out_write(&out, L"# code_point\tcanonical_utf16 (EMPTY = dropped, REJECT = invalid tag, START..END = range). Unlisted code points stay unchanged.\n");
    for (code_point = 0; code_point <= 0x10ffff; ++code_point) {
        int length;
        if (code_point >= 0xd800 && code_point <= 0xdfff) continue;
        length = encode(code_point, text);
        if (!tags_normalize(text, normal)) { range_add(&range, code_point, L"REJECT"); ++changed; continue; }
        if (!*normal) { range_add(&range, code_point, L"EMPTY"); ++changed; continue; }
        if ((int)wcslen(normal) == length && !wcscmp(normal, text)) continue;
        range_flush(&range);
        out_write(&out, L"%04X\t%s\n", code_point, hex_units(normal, (int)wcslen(normal), hex, 256));
        ++changed;
    }
    range_flush(&range);
    out_close(&out);
    printf("tags-fold.tsv: %u listed\n", changed);
}

static void write_tag_samples(void) {
    static const wchar_t *samples[] = {
        L"", L"lavoro", L"Lavoro", L"#lavoro", L"  lavoro  ", L"b;A;c", L"Città;citta;CITTÀ", L"#work; work ;WORK",
        L"project alpha", L"Lavoro; project alpha; Città; #Work; ÉTÉ; work", L"a;;b; ;c", L"ß;SS;ss", L"İ;i;I;ı",
        L"Ω;ω;\x2126", L"Å;\x212B;A\x030A", L"ǅ;Ǆ;ǆ", L"😀;😀", L"tag\"quoted", L"#", L"##doppio", L"a#b",
        L"\x0001", L"tab\there", L"\x00A0spazio\x00A0", L"ＦＵＬＬ;full", L"Zeta;alfa;Beta;_x;10;9;~",
        L"123456789012345678901234567890123456789012345678901234567890123",
        L"1234567890123456789012345678901234567890123456789012345678901234",
        L"a;b;c;d;e;f;g;h;i;j;k;l;m;n;o;p;q;r;s;t;u;v;w;x", L"a;b;c;d;e;f;g;h;i;j;k;l;m;n;o;p;q;r;s;t;u;v;w;x;y"
    };
    Output out;
    wchar_t normal[TAGS_CAP], printable[512], hex_in[2048], hex_out[2048];
    size_t i;
    out_open(&out, L"tags-normalize.tsv");
    out_write(&out, L"# input\tinput_utf16\tcanonical (REJECT = invalid)\tcanonical_utf16\n");
    for (i = 0; i < sizeof(samples) / sizeof(samples[0]); ++i) {
        BOOL ok = tags_normalize(samples[i], normal);
        out_write(&out, L"%s\t%s\t", escaped(samples[i], printable, 512),
                  hex_units(samples[i], (int)wcslen(samples[i]), hex_in, 2048));
        if (ok) out_write(&out, L"%s\t%s\n", escaped(normal, printable, 512),
                          hex_units(normal, (int)wcslen(normal), hex_out, 2048));
        else out_write(&out, L"REJECT\t\n");
    }
    out_close(&out);
}

/* Tag sorting and matching use CompareStringOrdinal(ignore case). This lists the
   invariant uppercase of each BMP code unit and flags any disagreement. */
static void write_ordinal_table(void) {
    Output out;
    unsigned unit, listed = 0, mismatches = 0;
    out_open(&out, L"ordinal-upper.tsv");
    out_write(&out, L"# utf16_unit\tinvariant_uppercase\tordinal_ignore_case_equal (1/0). Unlisted units map to themselves.\n");
    for (unit = 0; unit <= 0xffff; ++unit) {
        wchar_t source = (wchar_t)unit, upper = 0;
        int equal;
        if (LCMapStringEx(LOCALE_NAME_INVARIANT, LCMAP_UPPERCASE, &source, 1, &upper, 1, NULL, NULL, 0) != 1) upper = source;
        equal = CompareStringOrdinal(&source, 1, &upper, 1, TRUE) == CSTR_EQUAL;
        if (!equal) ++mismatches;
        if (upper == source && equal) continue;
        out_write(&out, L"%04X\t%04X\t%d\n", unit, (unsigned)upper, equal);
        ++listed;
    }
    out_close(&out);
    printf("ordinal-upper.tsv: %u listed, %u mismatches\n", listed, mismatches);
}

/* iswspace (MSVC CRT) splits query terms, trims tags and decides empty notes. */
static void write_space_table(void) {
    Output out;
    unsigned unit;
    out_open(&out, L"crt-iswspace.tsv");
    out_write(&out, L"# utf16_unit for which the MSVC CRT iswspace() is true\n");
    for (unit = 0; unit <= 0xffff; ++unit) if (iswspace((wint_t)unit)) out_write(&out, L"%04X\n", unit);
    out_close(&out);
}

/* Parsed terms exactly as query_compile builds them. */
static void write_query_table(void) {
    static const wchar_t *samples[] = {
        L"", L"   ", L"caffè", L"CAFFE perche", L"\"release plan\"", L"\"release plan", L"release\"plan\"",
        L"#lavoro", L"#LAVORO", L"#\"project alpha\"", L"#città", L"#", L"#\"\"", L"#a;b", L"-#", L"-#x", L"- #",
        L"-# progetto", L"\"\"", L"a\tb\x3000" L"c\x00A0" L"d", L"cafe\x0301", L"Straße", L"İ", L"ﬁ", L"😀",
        L"a b c d e f g h i j k l m n o p", L"a b c d e f g h i j k l m n o p q", L"\x0301", L"#personale \"release plan\""
    };
    FoldBuffer buffer = {0};
    Query query;
    Output out;
    wchar_t printable[1024], hex[2048];
    size_t i;
    int term;
    out_open(&out, L"query-parse.tsv");
    out_write(&out, L"# query\tquery_utf16\tvalid (1/0)\tterms: kind:pattern_utf16 separated by | (text = folded, tag = canonical, untagged = -#)\n");
    for (i = 0; i < sizeof(samples) / sizeof(samples[0]); ++i) {
        BOOL ok = query_compile(&query, samples[i], &buffer);
        out_write(&out, L"%s\t%s\t%d\t", escaped(samples[i], printable, 1024),
                  hex_units(samples[i], (int)wcslen(samples[i]), hex, 2048), ok ? 1 : 0);
        for (term = 0; ok && term < query.count; ++term) {
            const SearchTerm *item = &query.terms[term];
            const wchar_t *kind = item->untagged ? L"untagged" : item->tag ? L"tag" : L"text";
            const wchar_t *pattern = item->pattern ? item->pattern : L"";
            int length = item->untagged ? 0 : item->tag ? (int)wcslen(pattern) : item->length;
            out_write(&out, L"%s%s:%s", term ? L"|" : L"", kind, hex_units(pattern, length, hex, 2048));
        }
        out_write(&out, L"\n");
        query_free(&query);
    }
    out_close(&out);
    fold_free(&buffer);
}

int wmain(int argc, wchar_t **argv) {
    if (argc != 2) { fputs("Usage: unicode_golden.exe <new-output-folder>\n", stderr); return 2; }
    require(GetFullPathNameW(argv[1], 1024, output_root, NULL) > 0, "resolve output folder");
    require(CreateDirectoryW(output_root, NULL), "create a new output folder");
    write_fold_table();
    write_fold_sequences();
    write_tag_table();
    write_tag_samples();
    write_ordinal_table();
    write_space_table();
    write_query_table();
    puts("Unicode tables written.");
    return 0;
}
