# Fitbit Scale — Session Log

## Session 6 — Body fat % backfill + daily sync shortcut debugging

**Date:** 03.21.2026
**Time spent:** ~2h30m

### What We Built
- Updated `fitbit_backfill.py` to include `fatPercent` and `bmi` in JSON output (were silently dropped before)
- Updated start date to Sept 17 and end date to dynamic `datetime.now()`
- Body Fat % Backfill automation shortcut: body-comp-only (no weight to avoid dupes), with `Set Variable fatPct` pattern to avoid Dictionary Value ambiguity
- Rewrote daily sync shortcut doc with full visual diagram and `Set Variable` pattern for all key values

### What Shipped
- `fitbit_backfill.py` updated and pushed to Pi + committed
- Body fat % backfill ran successfully — 153 entries from Sept 17 2025 to present logged to Health
- Shortcut docs updated with lessons learned (no ÷100, Set Variable pattern, Item from List workarounds)

### Bugs Fixed
- **`fatPercent` and `bmi` missing from backfill JSON** — `build_payload()` never included them; added conditional `if "fat" in e` / `if "bmi" in e`
- **Body fat logging 0%** — shortcut was using `÷ 100` on raw percent value; Shortcuts handles `%` unit conversion internally, pass raw value (15.746 not 0.15746)
- **Body fat logging 22% (BMI value)** — Dictionary Value ambiguity; `Get Value for bmi` output overwrote `Dictionary Value`, so body fat Log Health Sample used BMI value. Fix: `Set Variable fatPct` immediately after `Get Value for fatPercent`

### Decisions Made
- Body comp backfill runs as body-comp-only (no weight logging) to avoid duplicating existing weight data
- Use `Set Variable` after every `Get Value` to avoid Dictionary Value magic variable collisions
- Daily sync weight issue (0 lbs) still unresolved — continuing next session

---

## Session 5 — Complete Daily Weight Sync shortcut (BMI + body fat %)

**Date:** 03.21.2026
**Time spent:** ~30m

### What We Built
- n/a (no new code — shortcut fixes on iPhone)

### What Shipped
- "Fitbit Daily Weight Sync" shortcut fully working: weight + body fat % + BMI all logging to Apple Health
- BMI `If` block restructured: `Get Value for bmi in entry` moved above the `If` so the condition correctly references it
- Confirmed `Dictionary... count` unit for BMI is correct (HealthKit uses "count" for dimensionless values)

### Bugs Fixed
- **BMI If block condition was broken (red reference):** `Get Value for bmi` was inside the If, so the If's `Dictionary Value` condition referenced the wrong (previous) action's output. Fix: drag `Get Value for bmi` above the If so the If's condition sees the correct bmi Dictionary Value.
- **BMI Log Health Sample showed "count" as unit:** This looked like an error but is correct — HealthKit represents BMI as dimensionless (no unit), which Shortcuts displays as "count".

### Decisions Made
- No divide-by-100 on body fat %: pass raw value (e.g. 15.746) with `%` unit — Shortcuts handles the conversion internally

---

## Session 4 — Make repo public, security cleanup

**Date:** 03.20.2026
**Time spent:** ~45m

### What We Built
- n/a (no new features)

### What Shipped
- Repo flipped to public on GitHub
- Cleaned Tailscale IP → `YOUR_PI_TAILSCALE_IP` in `CLAUDE.md` and backfill shortcut doc
- Fixed absolute local paths → relative/generic in `README.md` and plist.example

### Bugs Fixed
- n/a

### Decisions Made
- Single public repo rather than private/public fork — personal config belongs in `.env`, not code
- Git history was clean (no committed secrets), so no squash needed before publishing

---

## Session 1 — Fix Daily Weight Sync dedup bug + backfill

**Date:** 03.16.2026
**Time spent:** ~2h

### What We Built
- `fitbit_backfill.py` — Python script to fetch historical weight from Fitbit API in 30-day chunks, deduplicate, and write to `/opt/fitbit-scale/backfill-weights.json`
- Fixed "Fitbit Daily Weight Sync" iPhone shortcut — dedup now works correctly

### What Shipped
- 129 entries (Sept 8, 2025 – Feb 14, 2026) written to Pi backfill endpoint
- `fitbit-last-log-id.txt` dedup file now creates/updates correctly in iCloud Drive/Shortcuts

### Bugs Fixed
- **Root cause:** iOS Shortcuts magic variable type-matching — `Save File` action was grabbing the FILE-type output of `Get file from Shortcuts` (empty) instead of the TEXT-type `logID` variable. This meant the dedup file was never written, so every run re-logged the same weight (~12 duplicates of 161.4 lbs accumulated).
- **Fix:** Delete broken Save File, add `Text [logID]` action (forces TEXT type), then `Save File [Text] → Shortcuts/fitbit-last-log-id.txt`.

### Decisions Made
- Use `value` field (pounds) for Apple Health logging per user preference
- Backfill covers the exact gap: Sept 8, 2025 → Feb 14, 2026 (day before existing data resumes)
- Dedup file path: `iCloud Drive/Shortcuts/fitbit-last-log-id.txt` (no leading slash in Save File)

---

## Session 2 — Community guide and public scripts

**Date:** 03.16.2026
**Time spent:** ~15m

### What We Built
- `GUIDE.md` — complete end-to-end setup guide for Fitbit → Apple Health (public-facing)
- `oauth_bootstrap.py` — Python PKCE OAuth bootstrap, no deps, opens browser and captures callback
- Added `fitbit_export.py` and `fitbit_backfill.py` to repo (were Pi-only before)
- Reddit post draft at `~/Documents/Claude/Drafts/iOS-Shortcuts-Magic-Variable-Type-Bug/Reddit-Fitbit-Guide.md`

### What Shipped
- All 4 scripts committed and pushed to `bryanfosler/fitbit-scale`

### Decisions Made
- Targeting r/fitbit + r/shortcuts for the post
- Shortcut iCloud links pending — Bryan needs to update URLs and export from phone before posting

---

## Session 3 — Add body fat % and BMI to export

**Date:** 03.19.2026
**Time spent:** ~20m

### What We Built
- `fatPercent` and `bmi` fields added to `fitbit_export.py` payload (conditionally — only present when scale measured them)

### What Shipped
- `fitbit_export.py` updated on Pi and committed to `bryanfosler/fitbit-scale` (`f4181b9`)
- GitHub issue #4 created as open Notion item for the Shortcut update

### Bugs Fixed
- `build_payload()` was dropping Fitbit Aria body composition data silently — Fitbit API returns `fat` and `bmi` in weight log entries but the script never included them

### Decisions Made
- Conditional inclusion (`if "fat" in e`) rather than `.get()` → field absent vs null when not measured, cleaner for Shortcut parsing
- Shortcut update is an open item (issue #4) — HealthKit expects 0–1 decimal for body fat %, so divide by 100 before logging
