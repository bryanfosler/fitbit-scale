# Fitbit Scale Sync — Project Context

## What this project does

Pulls weight data from the Fitbit API and writes it into Apple Health via an iPhone Shortcut. The architecture is:

`Fitbit API → Swift exporter (cron on OpenClaw) → latest-weight.json → iPhone Shortcut → Apple Health`

## Key URLs

- Latest weight endpoint: `http://100.99.74.37:8766/latest-weight.json` (Tailscale, requires Tailscale connected on iPhone)
- Backfill endpoint: `http://100.99.74.37:8766/backfill-weights.json`

## JSON format from the server

```json
{
  "generatedAt": "2026-03-15T23:00:00Z",
  "unit": "pounds",
  "weights": [
    {
      "kilograms": 81.6,
      "logID": "1234567890",
      "source": "Aria",
      "timestamp": "2026-03-15T12:01:00Z",
      "value": 180.0,
      "fatPercent": 15.746,
      "bmi": 22.54
    }
  ]
}
```

- `value` = weight in **pounds** (use this for Apple Health logging)
- `kilograms` = converted value (not used in shortcut)
- `logID` = Fitbit's unique ID for each weigh-in, used for deduplication
- `fatPercent` = body fat % (e.g. `15.746`) — only present when Aria measured it (absent on manual entries)
- `bmi` = body mass index — only present when Aria measured it
- **HealthKit unit for body fat:** divide `fatPercent` by 100 before logging (HealthKit expects 0–1 decimal, not 0–100)

## Shortcuts built so far

### Fitbit Weight Backfill (COMPLETE)
One-time importer. Fetches `backfill-weights.json`, loops through all entries, logs each to Apple Health in lb. See `FITBIT_WEIGHT_BACKFILL_SHORTCUT.md` for full build steps.

### Fitbit Daily Weight Sync (IN PROGRESS)
Daily automation. Fetches `latest-weight.json`, checks if logID is new (dedup via `iCloud Drive/Shortcuts/fitbit-last-log-id.txt`), logs weight to Apple Health in lb, saves logID.

**Status:** Shortcut partially built on iPhone. URL fixed to `latest-weight.json`. Still needs:
1. `Get Value for Key` → key: `value` → input: Item from List
2. `Get Value for Key` → key: `timestamp` → input: Item from List
3. `Get Dates from Input` → input: timestamp Value
4. `Log Health Sample` → Type: Weight, Value: value (lbs), Unit: lb, Date: Date
5. `Save File` → logID → iCloud Drive/Shortcuts/fitbit-last-log-id.txt → Overwrite ON

Also needs a **Personal Automation** trigger: Shortcuts app → Automation tab → Time of Day → Daily → Run Shortcut → "Fitbit Daily Weight Sync" → Ask Before Running: OFF

## iOS / tooling notes

- Running iOS 26 — unsigned `.shortcut` file imports are unreliable, build directly in app
- **mirroir-mcp** is installed and configured for Claude to control iPhone Mirroring directly
  - Installed via: `npm install -g mirroir-mcp`
  - Added to Claude: `claude mcp add --transport stdio mirroir -- npx -y mirroir-mcp`
  - Permissions file: `~/.mirroir-mcp/permissions.json`
  - To use: make sure iPhone Mirroring is open and unlocked, then ask Claude to control it
  - **Known limitation:** Blue ">" circle/arrow buttons in Shortcuts action configs are completely unresponsive to mirroir taps — have Bryan tap these manually on the phone
  - **Known limitation:** `Save File` destination picker (the ">" next to "Shortcuts") also needs manual tap
  - Coordinate space: 326×720 points; `describe_screen` and `tap` are 1:1

## User preferences

- Weight unit: **pounds (lb)** — always use `value` field, never `kilograms`
- Deduplication: yes — store last logID in `iCloud Drive/Shortcuts/fitbit-last-log-id.txt`
- Learning vibe coding — explain what you're doing, share tips, flag assumptions
