#ifndef PC_NOTE_H
#define PC_NOTE_H

#include "pc_types.h"

/* Capacity of a note ID including its terminator, as in src/picoslip.c. */
#define PC_ID_CAP 80

#define PC_TODO_OPEN ((pc_char)0x2610)
#define PC_TODO_DONE ((pc_char)0x2611)

typedef struct PCDateTime {
    int year, month, day, hour, minute, second, millisecond;
} PCDateTime;

/* note-YYYY-MM-DD_HH-MM-SS-mmm-NNN in local time, as new_note(). The caller
   tries suffix 0, 1, 2... until no file has that name. Returns the length, or
   0 when a field is out of range. */
size_t pc_note_id_format(pc_char id[PC_ID_CAP], const PCDateTime *time, int suffix);

/* A file restore_notes() opens: "note-" or the legacy "nota-" prefix, ".txt"
   extension (any case) and an ID shorter than PC_ID_CAP. Copies the ID. */
bool pc_note_id_from_file_name(const pc_char *name, size_t length, pc_char id[PC_ID_CAP]);

/* Reading a TXT file (load_text): with has_title=1 and a first line "#Title",
   the title is that line without '#', taken verbatim, and the body starts
   after its line break. A bare "#" line is body text. */
typedef struct PCTitleSplit {
    bool has_title;
    size_t title_start, title_length, body_start;
} PCTitleSplit;
PCTitleSplit pc_title_split(const pc_char *text, size_t length, bool has_title_flag);

/* Title typed in the title dialog (set_title): first line only, spaces and
   tabs trimmed. Returns false when nothing remains, which removes the title. */
bool pc_title_from_input(const pc_char *text, size_t length, size_t *start, size_t *title_length);

/* Enter at the end of a first line "#Title" (promote_title). The title is
   trimmed like the dialog's; the body keeps everything after the line break. */
typedef struct PCTitlePromotion {
    size_t title_start, title_length, body_start;
} PCTitlePromotion;
bool pc_title_promotion(const pc_char *text, size_t length, size_t caret, PCTitlePromotion *result);

/* Checklist marker at the start of a paragraph ("☐ " or "☑ "), else 0. */
pc_char pc_todo_marker(const pc_char *paragraph, size_t length);

#endif
