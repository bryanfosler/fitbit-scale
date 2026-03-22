# Fitbit Daily Weight Sync Shortcut

Daily importer: fetches latest Fitbit entry, dedupes via logID, logs weight + body fat % + BMI to Apple Health.

---

## iPhone Build Diagram

```
┌─────────────────────────────────────────┐
│ 🌐  Get contents of                     │
│     http://PI_IP:8766/latest-weight.json│
└─────────────────────────────────────────┘
┌─────────────────────────────────────────┐
│ 🟧  Get dictionary from                 │
│     Contents of URL                     │
└─────────────────────────────────────────┘
┌─────────────────────────────────────────┐
│ 🟧  Get Value for  weights  in          │
│     Dictionary                          │
└─────────────────────────────────────────┘
┌─────────────────────────────────────────┐
│ 🔢  Get item from list                  │
│     Index: 1   in  Dictionary Value     │
└─────────────────────────────────────────┘
┌─────────────────────────────────────────┐
│ 🟧  Get Value for  logID  in            │
│     Item from List                      │
└─────────────────────────────────────────┘
┌─────────────────────────────────────────┐
│ 📄  Get File                            │
│     Shortcuts/fitbit-last-log-id.txt    │
│     If Not Found: Continue              │
└─────────────────────────────────────────┘
┌─────────────────────────────────────────┐
│ 💬  Get Text from Input                 │
│     File                                │
│     (empty string if file missing)      │
└─────────────────────────────────────────┘
┌─────────────────────────────────────────┐
│ ☑️  If  logID  is not  Text             │
├─────────────────────────────────────────┤
│   ┌───────────────────────────────────┐ │
│   │ 🟧  Get Value for  value  in      │ │
│   │     Item from List                │ │
│   └───────────────────────────────────┘ │
│   ┌───────────────────────────────────┐ │
│   │ 🟧  Get Value for  timestamp  in  │ │
│   │     Item from List                │ │
│   └───────────────────────────────────┘ │
│   ┌───────────────────────────────────┐ │
│   │ 📅  Get Dates from Input          │ │
│   │     Dictionary Value              │ │
│   └───────────────────────────────────┘ │
│   ┌───────────────────────────────────┐ │
│   │ ❤️  Log Health Sample             │ │
│   │     Type:  Weight                 │ │
│   │     Value: Dictionary Value       │ │
│   │     Unit:  lb                     │ │
│   │     Date:  Dates                  │ │
│   └───────────────────────────────────┘ │
│   ┌───────────────────────────────────┐ │
│   │ 🟧  Get Value for  fatPercent  in │ │
│   │     Item from List                │ │
│   └───────────────────────────────────┘ │
│   ┌───────────────────────────────────┐ │
│   │ 🅧  Set variable  fatPct          │ │
│   │     to  Dictionary Value          │ │
│   └───────────────────────────────────┘ │
│   ┌───────────────────────────────────┐ │
│   │ ☑️  If  Dictionary Value          │ │
│   │     has any value                 │ │
│   ├───────────────────────────────────┤ │
│   │   ┌─────────────────────────────┐ │ │
│   │   │ ❤️  Log Health Sample       │ │ │
│   │   │     Type:  Body Fat %       │ │ │
│   │   │     Value: fatPct  %        │ │ │
│   │   │     Date:  Dates            │ │ │
│   │   └─────────────────────────────┘ │ │
│   │ End If                            │ │
│   └───────────────────────────────────┘ │
│   ┌───────────────────────────────────┐ │
│   │ 🟧  Get Value for  bmi  in        │ │
│   │     Item from List                │ │
│   └───────────────────────────────────┘ │
│   ┌───────────────────────────────────┐ │
│   │ ☑️  If  Dictionary Value          │ │
│   │     has any value                 │ │
│   ├───────────────────────────────────┤ │
│   │   ┌─────────────────────────────┐ │ │
│   │   │ ❤️  Log Health Sample       │ │ │
│   │   │     Type:  Body Mass Index  │ │ │
│   │   │     Value: Dictionary Value │ │ │
│   │   │     Unit:  count            │ │ │
│   │   │     Date:  Dates            │ │ │
│   │   └─────────────────────────────┘ │ │
│   │ End If                            │ │
│   └───────────────────────────────────┘ │
│   ┌───────────────────────────────────┐ │
│   │ 💾  Save File                     │ │
│   │     logID →                       │ │
│   │     Shortcuts/fitbit-last-log-id  │ │
│   │     .txt   Overwrite: ON          │ │
│   └───────────────────────────────────┘ │
│ End If                                  │
└─────────────────────────────────────────┘
```

---

## Key notes

- **`Get File` + `Get Text`** — if the file doesn't exist, `Get Text` returns `""`. So `logID is not Text` handles both "first run" and "new entry" in one `If`. No nesting needed.
- **`Set variable fatPct`** — captures the fatPercent Dictionary Value immediately after `Get Value for fatPercent`, before any other `Get Value` can overwrite it. Use `fatPct` (not `Dictionary Value`) in the body fat Log Health Sample.
- **Body fat unit** — pass the raw value (e.g. `15.746`) with unit `%`. Shortcuts handles the conversion internally. Do NOT divide by 100.
- **BMI unit** — `count` (dimensionless)
- **`value` field** — weight in pounds. Use `lb` as unit.

---

## Automation trigger

Shortcuts app → Automation tab → New Automation → Time of Day → daily (pick a time after your usual weigh-in) → Run Shortcut → `Fitbit Daily Weight Sync` → Ask Before Running: OFF

---

## Expected JSON shape

```json
{
  "weights": [
    {
      "logID": "1234567890",
      "value": 161.5,
      "timestamp": "2026-03-19T07:04:29+00:00",
      "fatPercent": 15.746,
      "bmi": 22.54
    }
  ]
}
```

`fatPercent` and `bmi` are optional — only present on Aria-measured entries, absent on manual ones.
