# Rubric Desk — build plan

## Scope and architecture

Flutter stable, single Dart codebase. Enable `windows`, `android`, `ios` at M1. Target phone, tablet (Android/iPad), and resizable Windows desktop; no phone-only fixed widths. Clean modules: plain-Dart rubric/scoring domain (integer arithmetic, no platform imports); repository using SQLite with migrations; adaptive widget layer; export codec; thin platform share/save adapter. UI state derives from persisted marks, never vice versa. `ScoringWorkspaceLayout` chooses one-student cards on phones, roster × criteria grid on tablets, and grid + detail inspector on desktop.

`com.infinityball.rubricdesk` is Android applicationId, iOS bundle identifier, and Windows/MSIX identity name where applicable. ASC bundle ID registered: `CREATED com.infinityball.rubricdesk`. Four ASC secret names: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `ASC_TEAM_ID`. iOS store submission deferred.

### Domain contract

Rubric has criterion IDs, names, integer weights, and ordered score levels with integer points. Assignment pins a rubric revision at creation; editing the template does not silently mutate old marks. Mark ledger records student ID, criterion ID, selected level or explicit `excused`, timestamp, and optional note. `not_marked` is absence of mark, never score zero. A total is unavailable until all non-excused criteria are marked; excused criteria reduce denominator and are disclosed, including all-excused (no total). Compute rational weighted score using integer numerator/denominator until presentation rounding; configurable score bands require deterministic boundary rules. Restore rejects unknown schema versions and validates references before committing any rows.

### Platform-authentic UX: strategy A — platform-native adaptive

Utility app, so OS convention beats a branded game shell. Small adaptive-widget layer (`AdaptiveScaffold`, `AdaptiveButton`, `AdaptiveDialog`, nav adapter): Cupertino widgets and iOS navigation/scrolling on iPhone/iPad; Material 3 and Android back/navigation on Android; Fluent command bars, navigation pane, context menus, pointer hover, resize, and keyboard accelerators on Windows (e.g. `fluent_ui` only when M4 needs it). Screens and domain stay shared. No Material/Android look on iOS, no Cupertino/iOS look on Android, no phone UI on Windows. Native date/file pickers, system share sheets and platform-specific back behavior. Don't assume haptics available; graceful no-op. Text scales, high-contrast mode, focus order, keyboard-only scoring, and announced score state are acceptance criteria.

## Milestones and dependencies

1. **M1 scaffold + CI:** pinned Flutter project with `windows/`, `android/`, `ios/`, `flutter analyze`, `flutter test`, `flutter build windows --release` on `windows-latest`; Linux/Docker Android debug build and Dart tests; iOS compilation on macOS later. No Windows/iOS build claim until CI records it.
2. **M2 domain + storage:** rubric revision validation, mark ledger, integer weighted scorer, band boundaries, unknown-safe/excused semantics, SQLite migrations. Table-driven tests first.
3. **M3 authoring:** course/roster/assignment/rubric forms; rubric preview and revision pin; validation and accessible labels.
4. **M4 scoring:** student detail, responsive `ScoringWorkspaceLayout`, rubric grid, keyboard shortcuts, spoken feedback; golden/widget tests with `TargetPlatform.iOS`, `TargetPlatform.android`, `TargetPlatform.windows` at phone/tablet/desktop sizes.
5. **M5 data ownership:** transactional versioned JSON backup/restore preview, CSV grade export, plain-text feedback, printable rubric. Escape CSV spreadsheet formula prefixes; consent at system share/save boundary.
6. **M6 release:** generate `AppStore/icon.png` with `~/.local/bin/spark-media --project rubric-desk image` (OpenAI Images) using fleet brief; inspect output and wire Windows `.ico` runner resource plus Android/iOS launcher icons. Review `AppStore/description.txt` against shipped features. `.github/workflows/release.yml` triggers on `v*` tags or manual dispatch, builds Windows on `windows-latest`, zips portable binary and attaches it to GitHub release. No TestFlight/Play publish yet.
7. **M7 optional:** macOS iOS compile/TestFlight and Android store build; four ASC secrets already installed (names only).

## Testing

Domain: arithmetic with uneven weights, missing marks, explicit zero, excused denominator, empty rubric, score band boundaries, revision pinning. Persistence: migration, interrupted restore rollback, adversarial backup IDs. UI: golden/widget rendering at iOS/Android/Windows target platforms for key screens; keyboard-only traversal, text scaling, high contrast, voice semantics. Actions: Windows build + tests on `windows-latest`; Android debug APK + Dart checks in pinned Flutter Docker on Linux CI; iOS compile job when Apple lane lands. Host Linux tests in Docker. Never describe static scaffold checks as Flutter build results.

## Packaging and risks

Windows is primary download; keep Android/iOS phones and tablets compiling. Native store release is later and opt-in. Risk: roster contains student personal data — no network, no analytics, user controls exports, docs encourage anonymized codes. Risk: different teacher scoring schemes — ship one auditable weighted integer scheme, no claim to replace school policy. Risk: exported CSV formulas — neutralize leading `=`, `+`, `-`, `@`, tab and CR. Risk: desktop dense grid must remain keyboard accessible. No LMS, live sync, AI grading, native Swift-only, React Native, Expo, Kotlin Multiplatform, .NET MAUI, Unity, or cloud accounts.
