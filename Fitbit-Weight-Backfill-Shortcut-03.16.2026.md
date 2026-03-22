# Fitbit Weight Backfill Shortcut

This Shortcut is a one-time importer from a Tailscale-reachable JSON endpoint into Apple Health. It logs weight, body fat %, and BMI for each entry that has them.

## Shortcut name

`Fitbit Weight Backfill`

## Build on iPhone

1. Open `Shortcuts` on iPhone.
2. Tap `+` to create a new shortcut.
3. Tap the title area at the top and name it `Fitbit Weight Backfill`.
4. Tap `Add Action`.
5. Search for `Get Contents of URL` and add it.
6. Tap the URL field and enter `http://YOUR_PI_TAILSCALE_IP:8766/backfill-weights.json`.
7. Leave the method as `GET`.
8. Add `Get Dictionary from Input`. Input: `Contents of URL`.
9. Add `Get Value for Key`. Key: `weights`. Input: `Dictionary`.
10. Add `Repeat with Each`. Input: `Dictionary Value` (weights list).

**Inside the `Repeat` block:**

11. Add `Get Value for Key`. Key: `value`. Input: `Repeat Item`.
12. Add `Get Value for Key`. Key: `timestamp`. Input: `Repeat Item`.
13. Add `Get Dates from Input`. Input: `timestamp` Dictionary Value.
14. Add `Log Health Sample`.
    Type: `Weight`, Value: `value` Dictionary Value, Unit: `lb`, Date: `Dates from Input`.

15. Add `Get Value for Key`. Key: `fatPercent`. Input: `Repeat Item`.
16. Add `If`. Condition: `Dictionary Value` (fatPercent) `has any value`.
17. Inside that `If`, add `Calculate`.
    Input: `Dictionary Value` (fatPercent), Operation: `÷`, Operand: `100`.
18. Inside that `If`, add `Log Health Sample`.
    Type: `Body Fat Percentage`, Value: `Calculation Result`, Unit: `%`, Date: `Dates from Input`.
19. `End If`.

20. Add `Get Value for Key`. Key: `bmi`. Input: `Repeat Item`.
21. Add `If`. Condition: `Dictionary Value` (bmi) `has any value`.
22. Inside that `If`, add `Log Health Sample`.
    Type: `Body Mass Index`, Value: `Dictionary Value` (bmi), Unit: `count`, Date: `Dates from Input`.
23. `End If`.

**End the `Repeat` block**, then tap `Done`.

## Visual structure

```text
Get Contents of URL
Get Dictionary from Input
Get Value for Key (weights)
Repeat with Each
  Get Value for Key (value)
  Get Value for Key (timestamp)
  Get Dates from Input
  Log Health Sample (Weight, lb)
  Get Value for Key (fatPercent)
  If fatPercent has any value
    Calculate (÷ 100)
    Log Health Sample (Body Fat Percentage, %)
  End If
  Get Value for Key (bmi)
  If bmi has any value
    Log Health Sample (Body Mass Index, count)
  End If
End Repeat
```

## Import and permissions

1. Make sure `Tailscale` is connected on your iPhone before running.
2. Run the shortcut once from the Shortcuts app.
3. If prompted, allow:
   - Network access for the URL fetch
   - Health access to write `Weight`, `Body Fat Percentage`, and `Body Mass Index`
4. Open the `Health` app after the run and confirm entries appear.

## Expected JSON shape

```json
{
  "weights": [
    {
      "value": 180.0,
      "timestamp": "2026-03-15T08:28:34+00:00",
      "fatPercent": 15.746,
      "bmi": 22.54
    }
  ]
}
```

- `fatPercent` and `bmi` are optional — only present for Aria-measured weigh-ins, absent on manual entries
- `value` is in pounds
- HealthKit body fat expects 0–1, so divide `fatPercent` by 100 before logging
