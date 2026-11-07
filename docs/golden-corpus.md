# Golden compatibility corpus

The corpus is the Windows reference that any other PicoSlip implementation (the macOS port, a refactored portable core) must match. It is produced by the real Windows code, never by hand, so it answers "what does PicoSlip 1.2.0 actually write?" without needing a Windows machine.

## How to regenerate

Run the **Golden corpus** workflow from the Actions tab (`workflow_dispatch`), then download the `picoslip-golden-corpus` artifact. It also runs on pull requests that change `src/` or the generators, so every such change shows the corpus it would produce. Locally, on Windows with the MSVC Build Tools: `tools\corpus.cmd`, output in `build\corpus`.

Two generators, both C17 and built with the same `/W4 /WX` flags as the app:

- `tools/corpus.c` includes `src/picoslip.c` exactly like `tests/tests.c` and drives the native editor with the same gestures (Enter, Shift+Enter, Ctrl+B/I/U, Ctrl+Shift+X, checkbox clicks, menu commands, Ctrl+wheel). Note IDs are fixed, so file names are stable between runs.
- `tools/unicode_golden.c` includes `src/search.c` to call its private folding and query parser over every Unicode code point.

## Output

`corpus/`

| File | Content |
|---|---|
| `archive-legacy/` | Archive never tagged: `notes.ini` keeps the original ANSI encoding. |
| `archive/` | Main archive: titles, literal `#` lines, formatting, checklists, tags, closed and collapsed notes, palettes, opacity, sizes, Unicode, the legacy `nota-` prefix, an external BOM file and a stale RTF. `notes.ini` is UTF-16LE after the first tag save. |
| `cases.tsv` | One line per note: archive, files present, who wrote it (`app`, `generator`, `app+generator`) and what it covers. |
| `formatting.tsv`, `formatting-legacy.tsv` | Character effects as Rich Edit reports them after reopening each note: `offset+length:BIUS` runs. |
| `search-golden.tsv` | Results of the real search worker for plain, tag, phrase, `-#`, invalid and sidebar-filtered queries: error, count, unreadable files, files read and each hit with its UTF-8 excerpt range. |
| `manifest.tsv` | Commit, UTC time, Windows build, NLS version and system DPI. |

`unicode/`

| File | Content |
|---|---|
| `fold.tsv` | Search folding of each code point (NFD, invariant uppercase, nonspacing marks removed). Unlisted code points fold to themselves; `START..END` collapses ranges. |
| `fold-sequences.tsv` | Folding of multi-character samples, where normalization depends on context. |
| `tags-fold.tsv` | Canonical tag form of each code point used as a tag (NFC, invariant lowercase), or `EMPTY` / `REJECT`. |
| `tags-normalize.tsv` | Full tag lists: separators, `#`, duplicates, ordinal sort order, length and count limits. |
| `ordinal-upper.tsv` | Invariant uppercase of each BMP unit, checked against `CompareStringOrdinal(ignore case)`, which sorts and compares tags. |
| `crt-iswspace.tsv` | Code units where the MSVC CRT `iswspace()` is true: it splits query terms, trims tags and decides whether a note is empty. |
| `query-parse.tsv` | Terms built by the query parser: kind (`text`, `tag`, `untagged`) and pattern. |

## Conventions

- Text columns are UTF-8. Every `*_utf16` column lists UTF-16 code units in hex and is authoritative; the printable columns are only for review.
- Formatting offsets are UTF-16 code units of the TXT body (title line excluded), where CRLF counts as two units.
- Search hit ranges are byte offsets in the UTF-8 TXT file, as `src/search.c` stores them.

## Facts a port must reproduce

These come from the code and are visible in the corpus:

- TXT is UTF-8 without BOM, CRLF line breaks, no trailing line break. A leading BOM is accepted when reading.
- A promoted title is written as `#Title` + CRLF before the body and flagged `has_title=1`. A literal first line beginning with `#` keeps `has_title=0` and must not become a title when reopened.
- Checkboxes are `U+2610`/`U+2611` followed by a space; a checked item's text is struck through in the RTF.
- The editor's default font is bold Consolas, so all text carries the bold effect unless Ctrl+B removed it.
- The RTF companion is used only when its plain text equals the TXT body; otherwise the TXT wins and formatting is dropped.
- Empty notes leave no TXT, RTF or `notes.ini` section.
- `notes.ini` stays ANSI until the first non-empty tag save converts it once, atomically, to UTF-16LE with BOM, preserving every section and key.
- Layout `width` and `height` are stored at 96 DPI; `x` and `y` are Windows virtual-screen pixels.
- Note IDs are `note-YYYY-MM-DD_HH-MM-SS-mmm-NNN` in local time; `NNN` is the first free suffix for that millisecond. The legacy prefix `nota-` is still accepted.

The generated values depend on the Windows build recorded in `manifest.tsv`; regenerate the corpus when the runner image changes and review any difference before updating the fixtures.
