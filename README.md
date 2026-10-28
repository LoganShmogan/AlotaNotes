# QuillFin

*by Save Point*

A mobile-first notes app built around spaced repetition. Keep notes in subject
folders, turn them into quiz questions with your own AI account, track practice
problems LeetCode-style, and let the FSRS forgetting curve bring each one back
right before you'd forget it, with a reminder when something's due.

This is a from-scratch Flutter rewrite of an earlier Python/Tkinter desktop app
([`Quiz-app-Ai`](https://github.com/LoganShmogan/Quiz-app-Ai)): it reuses that project's *ideas* (and,
where useful, its algorithms ported to Dart), not its code. See
`Docs/architecture.md` for how the two relate.

- **Optional accounts and sync.** Sign in to a QuillFin account to sync
  notes, questions and problems across devices, offline-first, and use
  QuillFin's AI within your plan. Or continue on this device with no account
  at all. Builds without cloud config are device-only (see
  `Docs/accounts_and_sync.md`).
- **Bring your own AI key.** Connect OpenAI (or any OpenAI-compatible
  endpoint: OpenRouter, Groq, a local Ollama/LM Studio server) or Anthropic
  directly from the Account tab. The app itself is never billed.
- **Import your own files.** `.txt`, `.md`, `.pdf`, `.docx`, `.pptx`, single
  file or bulk, with a preview/reorder step before anything is actually
  imported.
- **FSRS scheduling** (the algorithm Anki uses) for every quiz question and
  problem. Answers are auto-graded and then rated Again/Hard/Good/Easy, each
  button showing when that rating brings the item back. Target recall is
  adjustable in Settings. See `Docs/scheduling_algorithm.md`.
- **Problem tracker.** Log practice problems with difficulty, tags, link and
  your solution; time and log each attempt; re-solve them on their own FSRS
  schedule.
- **Today dashboard and reminders.** What's due, reviews done today, average
  recall and a 7-day forecast, plus an optional daily study notification
  (scheduled by the OS on Android/iOS/macOS, shown while open on
  Linux/Windows).
- **Works at every size.** Phone-first with a bottom bar; a rail on tablets
  and landscape phones; a sidebar, list-detail panes, a table view and
  keyboard shortcuts on desktop. Light and dark themes. See
  `Docs/quillfin_plan.md` section 5.

QuillFin is moving to accounts (Clerk), sync (Convex) and a Pro plan
(Stripe), with a Next.js web app alongside this Flutter app. The plan,
including per-screen-size layouts, is in `Docs/quillfin_plan.md`. The
Convex backend is in `backend/` (see `Docs/backend.md`), and this app syncs
with it when signed in.

## Quick start

Requires the Flutter SDK (this project was built against 3.47.2) and either a
connected device, a running emulator, or `flutter build apk` for a standalone
install.

```bash
flutter pub get
flutter run
```

See `Docs/running_locally.md` for full setup, first-run notes, and where data
lives on-device.

## Testing

```bash
flutter analyze
flutter test
```

394 tests covering pure logic (scheduling, grading, text extraction), storage
repositories (real in-memory SQLite), AI providers (HTTP-mocked, no real
network/API key needed), sign-in and sync (two devices through an in-memory
backend), and widget tests for every screen (real
`tester.tap()` interaction, not device input simulation). Line coverage of
`lib/` is 100%; `flutter test --coverage && dart run tool/check_coverage.dart`
checks it. See `Docs/testing.md` for why the device-input distinction
matters: it's the difference between a test that's actually reliable and one
that isn't, and this project hit that difference the hard way once already.

There's also one end-to-end test that runs the real app on Linux desktop
(real SQLite file, real settings and keychain, real HTTP to a local fake AI
server), from sign-in through quiz, problem tracking, import and export:

```bash
flutter test integration_test -d linux
```

It needs the Linux desktop toolchain installed; see `Docs/testing.md`.

The Convex backend has its own suite (vitest + convex-test, 100% line
coverage of `backend/convex/`), run from the repo root with Node 24:

```bash
npm install
npm run backend:test
```

## Documentation

Everything needed to understand and extend this codebase lives in `Docs/`:

- `architecture.md`, module map, layering, how this relates to the original
  Python desktop app
- `database_schema.md`, the SQLite schema
- `scheduling_algorithm.md`, FSRS scheduling, ratings and the v1 migration
- `ai_providers.md`, the AI provider abstraction (OpenAI/Anthropic), how to
  add a third
- `accounts_and_sync.md`, signing in from the app, the local sync columns
  and triggers, the sync engine, Settings > Sync / Plan, build config
- `backend.md`, the Convex backend: sync protocol, plans and usage, AI
  generation, billing, environment variables
- `setup_guide.md`, creating the Convex, Clerk, Stripe and Anthropic
  accounts and keys
- `quillfin_plan.md`, the production plan: architecture, sync, pricing,
  layouts per screen size, phases
- `gui_theming.md`, the (placeholder) QuillFin brand tokens and theme
- `testing.md`, how to run tests and check coverage, the test fakes and
  patterns, what's not covered, and the ADB-tap
  cautionary tale behind why widget tests are the trustworthy path here
- `running_locally.md`, setup, first run, where data lives, known Android
  build gotchas
- `packaging.md`, the Windows installer / Linux AppImage release build,
  triggered automatically on a GitHub release
- `hosting.md`, the web build in Docker, and putting it behind a reverse
  proxy at alotanotes.savepoint.co.nz
- `pdf/`, the docs above as Save Point branded PDFs, rebuilt with
  `dart run tool/build_docs.dart`
- `future_work.md`, known, deliberate deferrals: what's blocked on things
  only a human can provide (developer accounts, real devices, brand assets),
  and what's just not built yet
