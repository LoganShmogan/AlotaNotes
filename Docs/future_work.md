# Future Work

Known, intentional deferrals and gaps, not things discovered late and hidden.
The planning document this project grew from
(`Quiz-app-Ai/Docs/flutter_rewrite_plan.md`, in the sibling Python repo) has
the full history of decisions; this file is the current, standalone summary.

## Blocked on things only a human can provide

Not attempted, not faked with a stub that pretends to work:

- **Local notifications** (remind me when quizzes are due). Needs a real
  device to verify permission prompts and delivery actually work; this
  project's headless emulator testing already proved unreliable for
  verifying tap interactions (see `testing.md`), and is even less
  trustworthy for verifying platform permission/notification behavior.
- **Cloud storage integrations** (Dropbox, Google Drive, OneNote). Each
  needs a real developer-console app registration (client ID/secret) that
  only the project owner can create. Building OAuth flow scaffolding against
  nonexistent credentials would be unverifiable busywork, so nothing has
  been built here yet, not even a placeholder screen.
- **Exact savepoint.cc brand assets** (`gui_theming.md`). A text-only page
  fetch can't extract real hex codes, fonts, or spacing. The current theme
  is a direct port of the Python desktop app's own (also not fully verified)
  palette claims. Needs either the real CSS/brand guide or screenshots to
  check against.
- **Packaging and app store submission.** Needs an Apple Developer account
  (plus a Mac, for iOS) and a Google Play Console account; inherently a
  human/billing decision, not something to attempt autonomously.

## Deliberate design choices, not gaps

- **No real accounts or backend.** See `lib/auth/auth_service.dart`'s doc
  comment. `HardcodedAuthService` (a single local admin/1234 session) is
  meant to be swapped for a real provider later without touching any screen,
  the same reasoning as the Python desktop app's swappable `ApiKeyStore`.
- **No cross-device sync.** Falls out of the no-backend decision above.
- **Bulk import stages a flat, reorderable list into one destination
  folder, not a reconstructed source folder tree.** Standard mobile file
  pickers return individually-picked files, not an enumerated folder tree;
  there's no reliable cross-platform "pick a whole folder recursively" API
  the way a desktop file dialog has. See
  `bulk_import_staging_screen.dart`'s own doc comment. Revisit if a real
  need for nested-source import shows up.
- **No automatic note-linking / keyword extraction.** The Python desktop app
  cross-links notes that share concepts via local keyword matching, and
  feeds linked-note context into AI question generation. Not ported: this
  app's `LinkedNoteContext` type exists in `ai/base.dart` (matching the
  Python app's shape) but nothing ever populates it, so generation only ever
  sees a single note's own body. Worth porting once there's a folder
  structure large enough to make cross-note linking actually useful.
- **`.xlsx` import isn't implemented**, despite being mentioned in early
  planning. No note content is naturally spreadsheet-shaped, so this was
  deprioritized rather than forced. `.txt`/`.md`/`.pdf`/`.docx`/`.pptx` all
  work.

## Not yet built, no fundamental blocker

- **Automatic on-open question generation.** The plan was: check which
  notes are due for new questions when the app opens, generate without a
  manual button press. Right now, generation is always a manual "Generate"
  tap in the note editor.
- **Stats / accuracy view.** `question_history` (the append-only review
  audit log) exists and is written to on every answer, but nothing reads it
  back yet to show per-question or per-folder accuracy.
- **Soft-deleting a question.** The `active` column and the DB-level
  capability exist (see `database_schema.md`), but no screen exposes a way
  to deactivate a single question without deleting its entire parent note.
- **Quiz-to-note traceability only goes one level.** A question always
  belongs to exactly one source note (no note-linking, see above), so "which
  note did this come from" is a direct lookup, not a list. This was an open
  question in early planning ("should quizzes get independent folder
  placement, or always inherit their source note's") and was resolved this
  way: a question inherits its source note's folder implicitly, via
  `note_id`; there's no independent quiz-folder concept.

## Known rough edges

- Custom fonts aren't bundled (see `gui_theming.md`); the app uses
  Flutter's default Material font stack for now.
- The theme hasn't been checked against the real savepoint.cc site (see
  above); treat current colors as a reasonable placeholder, not a confirmed
  match.
