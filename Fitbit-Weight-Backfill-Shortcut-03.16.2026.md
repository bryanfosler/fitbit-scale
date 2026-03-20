# Fitbit Weight Backfill Shortcut

This Shortcut is a one-time importer from a Tailscale-reachable JSON endpoint into Apple Health.

## Shortcut name

`Fitbit Weight Backfill`

## Build on iPhone

These steps use the action names shown in the current Shortcuts app on recent iOS releases.

1. Open `Shortcuts` on iPhone.
2. Tap `+` to create a new shortcut.
3. Tap the title area at the top and name it `Fitbit Weight Backfill`.
4. Tap `Add Action`.
5. Search for `Get Contents of URL` and add it.
6. Tap the URL field and enter `http://YOUR_PI_TAILSCALE_IP:8766/backfill-weights.json`.
7. Leave the method as `GET`.
8. Tap `Search Actions`.
9. Search for `Get Dictionary from Input` and add it.
10. Tap `Search Actions`.
11. Search for `Get Value for Key` and add it.
12. In that action, set the key to `weights`.
13. Confirm the input is the dictionary from the previous action.
14. Tap `Search Actions`.
15. Search for `Repeat with Each` and add it.
16. Make sure `Repeat with Each` uses the `weights` value from step 12 as its input list.
17. Inside the `Repeat` block, tap `Search Actions`.
18. Search for `Get Value for Key` and add it.
19. Set that key to `value`.
20. Set its input to `Repeat Item`.
21. Still inside the `Repeat` block, tap `Search Actions`.
22. Search for `Get Value for Key` and add a second copy.
23. Set that key to `timestamp`.
24. Set its input to `Repeat Item`.
25. Still inside the `Repeat` block, tap `Search Actions`.
26. Search for `Get Dates from Input` and add it.
27. Set its input to the `timestamp` value from step 23.
28. Still inside the `Repeat` block, tap `Search Actions`.
29. Search for `Log Health Sample` and add it.
30. Set `Type` to `Weight`.
31. Set `Value` to the `value` output from step 19.
32. Set `Unit` to `lb`.
33. Set `Date` to the `Date` output from step 27.
34. Leave the `Repeat` block in place and tap `Done`.

## Import and permissions

1. Before running the shortcut, make sure `Tailscale` is connected on your iPhone.
2. Run the shortcut once from the Shortcuts app.
3. If prompted, allow:
   - network access for the URL fetch
   - Health access to write `Weight`
4. Open the `Health` app after the run and confirm the imported entries appear under weight.

## Export as a file from iPhone

Once you build and test it, you can export it for reuse:

1. Open the shortcut in `Shortcuts`.
2. Tap the shortcut name or share menu.
3. Choose the export/share option.
4. In `Options`, choose `File` if you want a `.shortcut` file.
5. Save it to `Files` or `iCloud Drive`.
6. On another iPhone, open that `.shortcut` file and tap `Add Shortcut`.

## Expected JSON shape

```json
{
  "weights": [
    {
      "value": 180.0,
      "timestamp": "2026-03-15T08:28:34+00:00"
    }
  ]
}
```

## Notes

- The `timestamp` value must be an ISO 8601 string so `Get Dates from Input` converts it into a Shortcuts `Date`.
- This Shortcut is for one-time backfill only.
- Your later daily Shortcut can separately use `latest-weight.json` and compare `logID` against a file in iCloud Drive for deduping.
