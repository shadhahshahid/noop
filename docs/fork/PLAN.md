# Personal fork: plan and working notes

This file belongs to a personal fork of NOOP (`shadhahshahid/noop`), not to the upstream project.
It is the shared memory for anyone, human or AI, continuing the fork's redesign. It is public, so it
holds **no personal or health information**; keep it that way.

## What this fork is

One person's redesign of the iPhone app, installed on their own phone through AltStore over the
existing NOOP, keeping all data. Upstream is `ryanbr/noop`; this fork tracks its 12.0.0 release.
Only the iPhone app is built here. Android and macOS are out of scope: the cross-platform parity
contract in `AGENTS.md` does not bind fork-only interface work, but stored data, analytics and
the `.noopbak` format must stay exactly as upstream has them.

## Rules that must not be broken

1. **No health or personal data in this repository,** in code, tests, screenshots, commit messages
   or this file. Screenshots use the app's own synthetic demo data only.
2. **The app identity stays `com.noopapp.noop`** and the app group stays as upstream has it.
   A different identity would install as a second, empty app and strand the owner's data.
3. **Never change stored data destructively.** No edits to existing migrations, no schema changes
   without a versioned migration and a test, nothing that rewrites or deletes history.
4. **Strap commands:** send only commands the app already sends. Nothing firmware-related, nothing
   destructive (see the BLE safety contract in `docs/CONTRIBUTING.md`).
5. **No new network calls.** The app is offline by design.
6. **Nothing reaches the phone without the owner's say-so.** Work happens on work branches. Merging
   into `custom` and publishing to the AltStore source are the owner's decisions (see "Releasing").

## Branches

| Branch | What it is |
|---|---|
| `custom` | The released code: what the phone runs. Default branch. Do not push work in progress here |
| `main` | Upstream's development code, untouched. Never edit |
| `feel` | Mirror of `custom` from the first release; no longer used for work |
| `altstore` | Holds only `source.json`, the fork's AltStore source. Written by the build workflow |
| `ci-results/<branch>` | Written by the screenshot workflow. Latest result for one work branch |
| anything else | A work branch. Pushing app code to it runs the screenshot workflow |

## How to work without a Mac

The app needs Xcode 26 and cannot be compiled on Linux, so GitHub Actions is the compiler and the
eyes. The loop needs only `git push` and `git fetch`:

1. Create a work branch from `custom` and commit changes to it.
2. Push. `.github/workflows/custom-ios-screenshots.yml` builds the app for an iPhone simulator, fills
   it with synthetic data and photographs the screens (about 15 minutes).
3. Fetch the result: `git fetch origin ci-results/<branch-with-slashes-as-dashes>` and read the files
   from `FETCH_HEAD` (for example `git show FETCH_HEAD:status.txt`, or check it out into a scratch
   folder to open the pictures):
   - `status.txt`: the commit, and whether the build and the capture succeeded
   - `errors.txt`: compiler errors when the build failed
   - `screens/*.png`: one picture per screen
4. Look at every picture before claiming a screen is done. Compare with the design below.

Choosing screens: list names in `Tools/custom-screens.txt` on the branch (one or more per line, `#`
starts a comment). Without that file the script's default set is used. Names:

- `shell` is the whole app on the Today tab; `tab1` to `tab4` open it on Train, Sleep, Data, More.
- Any other name is passed to `--demo-screen <name>`, mapped in `DemoScreens` in
  `StrandiOS/App/StrandiOSApp.swift`. **Add a case there for every new screen** so it can be captured.
- Add `-light` to any name to capture it in the light theme.
- Add `+N` to any name to also capture N further screenfuls below the first (`shell+3`,
  `tab3-light+1`). They are written as `<name>_p1.png` …; a screen with anything animating may
  repeat its last screenful. **Capture every screen to its bottom before calling it done:** the
  lower half of Today went unreviewed through five releases because only the first screenful was
  photographed. A system notification can land on a capture; look, and re-run if one did.

Things the screenshots cannot show: taps, animation, Bluetooth, GPS, haptics, and real data. Say so
when reporting; the owner tests those on the phone.

Tests: upstream's `app-build.yml` (Mac build plus about 2,270 app tests) and `swift-packages.yml`
are kept disabled in this fork and are started by hand before a release. If a change touches
analytics, storage or anything with a test, say that the tests need running.

## How to write fork code

- **New front doors, same rooms.** Put new screens and components in new files under `Strand/Fork/`
  (shared code) or `StrandiOS/Fork/` (iPhone-only), and link to the existing upstream screens.
  Change upstream files as little as possible, and mark every such change with a comment starting
  `// Personal fork:` so a later upstream merge can find them.
- **Never compute a number twice.** A redesigned screen lays out values the existing screen already
  resolves. `Strand/Fork/ForkToday.swift` is the pattern: plain values in, no scoring inside.
- **Design tokens only:** `StrandPalette`, `StrandFont`, `NoopMetrics`, shared components. No
  hard-coded colours, fonts or spacing in screens.
- Everything DEBUG-only (demo screens, launch arguments) stays inside `#if DEBUG`.
- English, neutral voice in comments and commit messages. One concern per commit.

## The agreed design

**Look:** near-black canvas, cards told apart by fill alone (no outlines), white primary buttons,
colour only where it carries state. Dark theme values, set in
`Packages/StrandDesign/Sources/StrandDesign/NoopVisualStyle.swift`:

| Role | Value |
|---|---|
| Canvas | `#0B0D10` |
| Card | `#14181D` |
| Control (buttons, inputs, tracks) | `#1C2128` |
| Lines | `#232930`, `#2A3038` |
| Text | `#F2F4F7` primary, `#A9B1BD` secondary |
| State | good `#3DDC97`, caution `#F5B83D`, low `#FF7A6B` |
| Other | cool blue `#6CB6FF`, sleep violet `#A58BFF` |

One green accent is kept on purpose for switches, links and the selected tab: a white accent makes
switches unreadable.

**Tabs:** Today, Train, Sleep, Data, More.

**The owner's sessions:** HIIT (studio classes, partner sessions with a few stations, own workouts),
runs (by heart-rate zone for easy runs, by pace for intervals), yoga, morning stretch.

### Done: release "Feel"

Base look; Today (one Charge ring, one-word verdict, sentence, drivers, Effort against the day's
target band, four one-tap starts: HIIT, Run, Yoga, Stretch); five tabs; More as ten rows with search;
Settings split into eight groups; plain canvas behind the Sleep score. The owner's verdict after a
week of use: **Today looks good; the rest of the app looks basic and is awkward to use.**

### Done: release "Look"

A first pass over every other screen, mostly through the shared building blocks: page headers are the
title alone, each section has one header, metric tiles show neutral values with a trend chip that
wraps instead of truncating, pills and cards have no outlines, Settings cards have plain headers.
Screen fixes: plain titles (Live, Health, Data, Full day), the Workouts filters fold behind one
button, neutral labels and icons on Workouts and Explore, no repeated value on Stress. Still weak and
left for the redesigns below: large empty states on Live and Health when no strap is connected, and
wordy explanatory copy on several screens.

### Done: release "Runs"

- `TargetCoachEngine` and `IntervalClock` (`Packages/StrandAnalytics`, pure, 16 unit tests): a
  reading must hold a new position for 8 s before it counts; below the target cues "push on" (two
  short buzzes), above cues "ease off" (three long), returning after a cued excursion cues "back on
  target" (one short); cues repeat every 30 s while out; "push on" is held back for the first two
  minutes; gaps break the dwell and are not counted as time.
- `Strand/Fork/ForkRunCoach.swift`: a run's plan (Zone, Pace, Intervals or Free) and the coach
  that watches the live session against it, buzzing through `AppModel.buzz`. The older top-zone
  buzz (`coachZone`) stands down while it runs. The plan survives the app being closed mid-run.
- `Strand/Fork/ForkRunViews.swift`: the run setup sheet and the coach card at the top of the
  in-exercise screen. `StrandiOS/Fork/ForkTrainView.swift`: the Train tab (one-tap starts, recent
  sessions, tools); the full Workouts list is under "All sessions".
- Not proven, because it needs a strap and a real run: that the buzzes arrive and feel distinct,
  that the coach keeps running with the phone locked in a pocket, and how usable GPS pace is.
  Pace is shown per kilometre only.

### Done: release "HIIT"

- `EffortWaveEngine` (`Packages/StrandAnalytics`, pure, 9 unit tests): one rise and one fall of
  smoothed heart rate is a round; a turn counts once heart rate has come back 10 bpm from its
  extreme; a rise or fall shorter than 20 s is not a round; a brief dip inside one effort does not
  split it. Tested to count the rounds put in across 72 generated session shapes.
- `Strand/Fork/ForkSessionTracker.swift`: follows a live HIIT session (round, working or
  recovering), takes the strap's double-tap as a station mark while the gesture is free, and shows a
  summary with optional tags once the workout has been saved. Yoga and Stretch get a quiet card.
  Rounds, marks and tags live in `ForkSessionNotes` (app preferences, keyed by the workout's start);
  they are not in a `.noopbak` backup.
- `Strand/Fork/ForkSessionViews.swift`: the live card, the summary, and the host that presents it.
- Not proven, because it needs a strap and real sessions: how well rounds are found in real classes
  (strength stations raise heart rate much less than cardio ones and can be missed), whether the
  double-tap registers mid-session, and that the summary appears cleanly after ending.

### Done: release "Data"

- `TrainingOverview` (`Packages/StrandAnalytics`, pure, 9 unit tests): sessions grouped into
  calendar weeks, the newest week's load against the average of earlier weeks that had any, and a
  day streak that an unfinished today does not break.
- `StrandiOS/Fork/ForkDataView.swift`: the Data tab's first screen. Four headline numbers with
  their seven-day average, a search across every metric, and doors into the existing analysis
  screens. Trends is one of the doors.
- `StrandiOS/Fork/ForkTrainingView.swift`: sessions by type, this week's load so far against a usual
  week, the easy / steady / hard split of zone time, a marker per kind of session where data exists
  (recovery between HIIT rounds, average run pace with the heart rate it cost), and the stretch
  streak.
- Left out on purpose: the Sleep screen was not redesigned (it already leads with one score), and
  the Training screen shows no "pattern" line; the existing Patterns screen is linked from Data.

### Next: release "Polish"

Agreed with the owner after a review of the app as used, of Aura (another NOOP-based app whose
12.1.7 source is published under the same licence), of what is publicly described of the WHOOP
and Oura apps, and an independent critique of the first draft of this plan. In order; each step
is one pull request into `custom` and must prove what is listed before the next starts.

1. **See the whole screen.** `+N` paged screenshots (done, see "How to work without a Mac").
   Proves: the lower half of Today is visible, with its faults, on synthetic data.
2. **Today, lower half.** The owner's complaint is the banded dark-and-light gradient on every
   small ring and bar (`LiquidRender.progressGradient` in `Strand/Liquid/LiquidPrimitives.swift`,
   used in about 50 places); hero-size rings keep it (`Strand/Fork/ForkFlatMarks.swift`). Also:
   tiles in a row line up, and nothing draws under the clock
   (`StrandiOS/Fork/ForkStatusBarScrim.swift`). Proves: paged dark and light screenshots.
   After two independent reviews (one against Apple's Human Interface Guidelines, one product
   critique) the same pull request also took: one name per score on Today's tiles (Charge,
   Effort, Sleep), the Charge tile in the hero ring's state colour from one resolver
   (`ForkTodayHero.stateColor`), Effort with one decimal everywhere, a bar only on the three
   scores, state symbols beside the hero's drivers, nothing under 11 points, and 44-point tap
   areas (`forkTapTarget`).

   Decided by the owner and done in the same pull request:
   - Small rings in list rows (Recovery vitals, Your cards) are plain symbols now
     (`Strand/Fork/ForkRowSymbol.swift`), matching the Key metrics tile symbols.
   - Sleep's hero draws the same flat ring as Today's Charge (`Strand/Fork/ForkScoreRing.swift`).
   - Charge and Sleep tiles show bare scores, no "%", as the hero does.
   - Today's repeated HRV and resting heart rate: the owner trims Key metrics with its Edit button
     (HRV, Rest HR and Respiratory are already in the hero and Recovery vitals). No code: the saved
     layout is never overwritten, and upstream's default orders are pinned by its tests.

   Raised by the reviews and still waiting for the owner's decision:
   - Data sources, and the Heart rate card when there is neither a live nor a stored trace.
   - Sleep: Alarms and Sleep marks sit above the night; figures that look alike disagree (two
     efficiencies, two sleep debts) and are probably different windows that need labels.
   - Live session cards: state colour for working against recovering, and elapsed time.
3. **Data page.** The owner finds it "missing something" but cannot yet say what, so nothing is
   built on a guess: for a week the owner notes each question they opened Data to answer and
   whether it did. Candidates to check those notes against: a mark and a "against your usual" line
   per headline number (`TypicalRangeBar` in StrandDesign exists and is unused), a range control
   with small trend lines, one plain finding with its sample size. Done already: the Charge
   headline reads the same resolved Charge as Today (`Strand/Fork/ForkChargeNow.swift`), not the
   newest raw recovery value. The same range mark should then replace the bars
   on Today's Key metrics tiles: several of those bars are the value over an arbitrary constant
   (HRV over 120, resting heart rate over 100) and say nothing.
4. **Aura's type and primitives, as a trial on one screen.** Their design files need `#if os(iOS)`
   around them (this app also builds watch and Mac targets, Aura does not) and the three font
   licence texts shipped beside the fonts. Roll out only after the owner approves the trial.

Deliberately not in this release:

- **Upstream after 12.0.0.** `main` is an unreleased 12.1.0 test build: it adds a forward-only
  database migration and about 450 changed lines in the strap connection code. Take it as its own
  release, from an upstream release tag, after a `.noopbak` export, and never mixed with look work.
- **Aura's features, storage or tab bar.** Look only. Aura's builds carry later database
  migrations than this fork; installing one over this app is not reversible.

Still owed from earlier releases: everything listed as "not proven" above needs a strap. Record
what real use turns up as GitHub issues (no readings, no personal details: the repository is
public) and fix those before widening the redesign.

Pull requests: `gh`/the web UI default a fork's pull request to the parent repository. Always set
the base to `shadhahshahid/noop` `custom`. Upstream's `app-build.yml` and `swift-packages.yml`
trigger only on pull requests into `main`, so they do not run for pull requests into `custom`.

### Original briefs, kept for reference

**1. Whole-app look pass (done, see above; the brief is kept for reference).** Bring every other screen up to the standard of Today by restyling the
shared building blocks once, rather than screen by screen: page header (`ScreenScaffold`), section
labels, cards and nested tiles, segmented controls and filter rows, list rows, search fields, pills
and badges, chart frames and axes, pop-up sheets, empty states. Aim for fewer boxes inside boxes,
clearer hierarchy (one thing per card that matters most), calmer colour, consistent spacing.
Screens to judge it on: Train (`tab1`), Sleep (`tab2`), Data (`tab3`), `live`, `health`, `stress`,
`insights`, `explore`, `compare`, `devices`, and the Settings groups. Rarely used screens
(diagnostics, imports) get this pass only.

**2. Runs (done, see above; the brief is kept for reference).** A new Train tab replacing the Workouts list as the tab root (the list stays reachable):
tiles for the session types, recent sessions, a link to Training analytics. Starting a run offers
four modes: **Zone** (hold a heart-rate zone), **Pace** (hold a pace), **Intervals** (reps at a target
pace with recoveries), **Free**. Live run screen: large current value against its target, a clear
in / below / above state, time and distance. The **zone coach** buzzes the strap: below target two
short buzzes, above target three long, back in zone one; an 8-second dwell before a state change
counts; a reminder every 30 seconds while out of zone, silent in zone; active only while a session
runs and is not paused. It replaces the existing limited `coachZone` logic in
`Strand/App/AppModel.swift` and must use only the existing buzz layer
(`Packages/WhoopProtocol/Sources/WhoopProtocol/HapticClock.swift`, `LiveSessionHaptics.swift`).
The engine belongs in a package with unit tests that need no strap.

**3. HIIT (done, see above; the brief is kept for reference).** No setup: start and go. Rounds and rests are picked out from heart rate during the
session; a double-tap on the strap optionally marks a new station (the app already treats the
double-tap as a claimable event, see `AppModel.handleDoubleTap`). Live screen: working or recovering,
current round and station, heart rate. Afterwards a session summary (rounds, stations, peak and
average heart rate, recovery between rounds, Effort) and tags chosen after the fact: class, partner
or on my own; cardio, strength or mixed. Never split HIIT by brand of class. Yoga and Stretch get a
quiet live screen with no targets and no buzzes: elapsed time (or time left for a timed stretch) and
heart rate settling toward resting.

**4. Sleep and Data (done as release "Data", see above).** Sleep in the same single-score language as Today. Data home: search, a range
control, four headline metrics, and doors into the existing analysis screens. A Training screen:
weekly load against the usual, intensity mix by time in easy / steady / hard zones, one fitness
marker per session type (heart-rate recovery from HIIT, pace at a fixed heart rate from zone runs,
rep consistency from intervals), a morning-stretch streak, and one plainly worded pattern from the
owner's own data with its sample size.

Known risks: pace needs the phone on the run and lags a few seconds; heart rate under-reads
strength stations; round detection and station marks are unproven on real sessions.

## Releasing (the owner's part)

1. Work is reviewed from screenshots, then merged into `custom`.
2. The owner (or a session on the owner's Mac) runs the tests, then starts **Custom iPhone build**
   from the Actions tab with **publish_to_source** ticked. That builds the app with its own build
   number (`<project build>.<run number>`), checks it (`Tools/custom-verify-ios-ipa.sh`,
   `Tools/custom-altstore-source.py check`) and makes it the newest version in the AltStore source.
3. The owner updates on the phone and tries it. More → About shows the release name and build
   number; set the name in `ForkMoreIndex.releaseName` (`StrandiOS/Fork/ForkMoreMenu.swift`).

A session that cannot start workflows must stop at step 1 and say the work is ready for review.
