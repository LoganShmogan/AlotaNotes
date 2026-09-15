# Testing

## Running tests

```bash
flutter analyze
flutter test
```

45 tests, all passing as of the last work session.

## Structure

```
test/
├── core/
│   ├── scheduling_test.dart       # pure function, table-driven cases
│   ├── grading_test.dart          # pure function
│   └── text_extraction_test.dart  # hand-built .docx/.pptx fixtures
├── ai/
│   ├── base_test.dart             # JSON response parsing, no network
│   ├── openai_provider_test.dart  # HTTP mocked via http's MockClient
│   └── anthropic_provider_test.dart
├── storage/
│   └── repos_test.dart            # real in-memory SQLite via sqflite_common_ffi
└── screens/
    └── notes_home_screen_test.dart  # real widget tree, tester.tap()
```

## Why widget tests, not device-input simulation

This matters enough to spell out, because it cost real time to learn during
this project's first working session.

Early manual verification drove the running app on an Android emulator via
`adb shell input tap <x> <y>`, the same way you'd script input from outside
the app entirely. One specific interaction (tapping a floating action
button) reliably failed to register, while everything else worked. Chasing
it down (swapping release/debug builds, removing `IndexedStack`, replacing
the button with a plain synchronous counter, comparing `top:`-anchored vs.
`bottom:`-anchored `Positioned` widgets at identical screen coordinates)
eventually showed the real pattern: anything positioned via `bottom:` in
that particular screen had its hit-test region diverge from its paint
position, while identical `top:`-anchored widgets worked every time and a
plain bottom-nav tap (outside that screen entirely) also worked every time.

That's a property of how instantaneous, zero-duration synthetic ADB taps
race a specific headless, software-rendered emulator's gesture-arena
handling. It is not something a real finger tap on a real device would ever
reliably trigger, and it is not a bug in this app's code, which was proven
correct independently (see below).

`flutter_test`'s `tester.tap()` sidesteps this category of problem entirely:
it drives the widget tree directly at the framework level, with no real
touch/display/OS input pipeline involved, so it's both deterministic and the
actual right tool for verifying this kind of interaction. `flutter test` can
drive real widget trees headlessly without needing a display at all.

**The practical rule this leaves behind**: if you need to verify that a
button/gesture does the right thing, write a widget test for it. Manually
driving the running app via ADB is still useful for a final "does it look
right, does it crash on startup" sanity check (see `running_locally.md`),
but it is not a reliable way to verify that a specific tap does what it's
supposed to.

## Key testing patterns used throughout

- **Dependency injection over mocking real I/O**: every repo/service takes
  its dependencies (a `Database`, an `AIProvider`, an `http.Client`) via
  constructor, so tests pass real in-memory SQLite connections and
  `MockClient` instances instead of monkeypatching internals.
- **Real in-memory SQLite over hand-written fakes** for repo/widget tests
  (via `sqflite_common_ffi`'s `databaseFactoryFfi`), higher fidelity (catches
  real SQL/constraint bugs) and just as fast. Each test opens its own
  isolated in-memory database with `OpenDatabaseOptions(singleInstance:
  false)`; without that flag, sqflite caches connections by path, and every
  test in a file would share (and collide on) the same `:memory:` database.
- **`tester.runAsync()` for any widget test that touches real I/O.**
  `sqflite_common_ffi` does genuine async work (a real native/isolate round
  trip per query), and Flutter's default test zone (`FakeAsync`) doesn't
  drive that kind of real `Future` to completion on its own. Without
  `runAsync`, `pumpWidget` and a widget's own internal DB calls race each
  other and Flutter throws a "Guarded function conflict."
- **Poll for real async completion instead of `pumpAndSettle()`, when a
  `CircularProgressIndicator` might be on screen.** `pumpAndSettle()`
  refuses to work while an indeterminate spinner is present (its animation
  never "settles" on its own), so widget tests wait for the actual signal
  they care about (a specific widget's disappearance, a specific list item
  appearing) instead, with real delays.
- **HTTP mocked via `http`'s own `testing.dart`** for `ai/`: every error
  branch (non-2xx status, connection failure, invalid JSON, unexpected
  response shape) has a dedicated test case, with no real network or API key
  ever required.
- **Hand-built `.docx`/`.pptx` fixtures** (in `text_extraction_test.dart`,
  built with the `archive` package's `ZipEncoder` at test time) rather than
  checked-in binaries, so the exact shape of what's being parsed stays
  visible in the test itself.

## What's not covered

- `.pdf` extraction (`core/text_extraction.dart`'s Syncfusion branch) has no
  automated test; a realistic PDF structure isn't worth hand-building the
  way the `.docx`/`.pptx` fixtures are. Verified manually instead.
- No automated end-to-end test drives the real app on a device/emulator
  (the ADB-tap approach was tried and found unreliable, see above). Startup
  and cross-screen navigation are verified manually before considering a
  batch of changes done; this is a real gap worth a proper headless
  device-test setup eventually, not a solved problem.
