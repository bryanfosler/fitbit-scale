# Fitbit Scale — Session Log

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
