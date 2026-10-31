# Rubric Desk

**Pitch:** Offline rubric scoring for teachers: mark criterion evidence, calculate transparent totals, and export feedback on phone, tablet, and Windows without accounts or cloud LMS.

Rubric Desk is a local-first Flutter app (Windows + Android + iOS from one codebase) for standards- and criterion-based grading. A teacher authors a rubric once (criteria, levels, weights), then walks a roster marking evidence per student per criterion. Totals, band placement, and per-student feedback text are derived by a deterministic, explainable scoring engine — every number traces back to the marks that produced it.

## Motivation

Rubric grading tools live inside LMS platforms: accounts, cloud rosters, subscription fees, and opaque weighted-average math a teacher cannot audit or adjust. Teachers who want rubric discipline for a 25-student class mid-lesson need something that opens instantly offline, shows its arithmetic, and never uploads a student's name. Rubric Desk does exactly that job, well, on the device already in the teacher's hand or on the classroom PC.

## Target users

- K-12 and adult-education teachers who grade with rubrics or criteria checklists
- Tutors, coaches, and music/art instructors running repeated evaluated sessions
- Department leads building shared rubrics to keep marking consistent

## Concrete use cases

1. **Live class walk-through:** tablet propped on the desk, roster visible, tap a level per criterion per student while students work; totals fill as you go.
2. **Portable-device conferencing:** phone in hand, one student at a time; per-criterion notes become the spoken feedback script.
3. **Department prep on Windows:** full keyboard at home; author a 6-criterion weighted rubric, print a clean rubric sheet, sync the file to a tablet by export/backup file.
4. **End-of-term feedback:** export per-student feedback text and a CSV grade sheet from the app without ever opening a spreadsheet formula.

## How to use (intended workflow)

1. Create a course, add a roster (local labels only; you choose real names or anonymized codes).
2. Author a rubric: criteria, ordered levels per criterion, optional weights, optional score bands (e.g. A/B/C thresholds).
3. Create an assignment bound to a rubric and open the scoring grid.
4. Mark each student/criterion cell with a level, `not_marked`, or `excused`. Only fully-marked or band-complete students enter totals; unknown is never silently zero.
5. Review the totals wall: each total opens a breakdown showing per-criterion levels, weights, and the exact derivation.
6. Export: CSV grade sheet, per-student feedback text, printable rubric sheet, and a JSON backup of the whole store.

## MVP features

- Courses, rosters (local labels), assignments, rubric authoring (criteria × levels, integer weights, optional bands)
- Append-only scoring mark ledger per student/criterion with timestamps and optional short notes
- Deterministic scoring engine: weighted-level totals, band assignment, explainable breakdown, unknown-safe (unmarked ≠ 0, excused excluded and disclosed)
- Scoring grid sized for touch (tablet/phone) and keyboard/mouse (Windows: arrow-key cell navigation, number-key level entry)
- Per-student feedback assembly from criterion notes + template line
- CSV / plain-text / printable-rubric export; versioned JSON backup/restore
- App icon generated via `~/.local/bin/spark-media --project rubric-desk image` per the fleet icon brief, wired into Windows/Android/iOS icon sets (no placeholders)
- Store listing copy maintained in `AppStore/description.txt`

## Non-goals

- No other build framework: React Native, Expo, Kotlin Multiplatform, .NET MAUI, Unity, and native Swift-only are all prohibited — the app is Flutter (Windows + Android + iOS from one codebase)
- Platform-native adaptive strategy A: Cupertino on iOS, Material 3 on Android, Fluent on Windows; never copy another OS's look. The scoring grid is a single `ScoringWorkspaceLayout` seam (grid + detail).
- Production `AppStore/icon.png` generated via spark-media OpenAI Images; platform icon resources generated from that source.
- No accounts, no cloud sync, no backend, no analytics — the app performs zero network requests on any platform
- No LMS/SIS integration, no gradebook import/export beyond plain CSV/text
- No AI grading, no essay scoring, no OCR of handwritten work
- No attendance, behavior, or IEP/special-education record keeping
- No medical, psychological, or behavioral diagnosis of students
- Not an official transcript system: totals are teacher working data, and the app says so

## Privacy, permissions, and data storage

- All data lives in the app's local database (SQLite via `sqflite`/`sqflite_common_ffi`); no network permission is requested on any platform
- Roster entries are user-chosen labels; the app never contacts a school system and never identifies a student to any third party
- CSV/feedback export uses the platform share/save sheet; the user chooses where files go
- JSON backup is a single user-owned file with an explicit version field; restore previews counts before overwriting
- Removal: deleting the app deletes the data; export first is surfaced in settings

## Platform identifiers

- Android `applicationId`, iOS bundle identifier, and Windows/MSIX identity all use `com.infinityball.rubricdesk` (bundle ID registered in App Store Connect: `CREATED com.infinityball.rubricdesk`)
- GitHub Actions secrets configured for the later iOS milestone (names only): `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `ASC_TEAM_ID`

## Current status

Flutter app, scoring and export tests, and native platform icon assets are tracked. Windows release packaging remains pending; see GitHub Actions CI for exact build status.

**Milestones:** M0 scaffold (done) → M1 Flutter skeleton + CI → M2 domain engine → M3 rubric authoring → M4 scoring workflow → M5 exports/backup → M6 icon + packaging/release → M7 store builds (later).

## Development quickstart

Flutter stable (see `toolchain.json`), then:

```sh
flutter create . --platforms=windows,android,ios   # M1: adds project around these docs
flutter pub get
flutter test
flutter run -d windows
```

Windows is the primary CI/release target (`windows-latest`); Android/iOS (phones and tablets) must keep compiling; release flow is a `v*` tag → `.github/workflows/release.yml` → zipped Windows build attached to a GitHub release. See `PLAN.md`.
