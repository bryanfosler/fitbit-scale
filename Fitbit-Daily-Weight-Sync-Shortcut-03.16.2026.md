# Fitbit Daily Weight Sync Shortcut

This Shortcut is the daily importer for the latest Fitbit weight entry into Apple Health with `logID` deduping.

## Shortcut name

`Fitbit Daily Weight Sync`

## Simplified flow

This version keeps the logic as simple as possible for the iPhone editor:

1. Fetch `latest-weight.json`
2. Pull `weights[0]`
3. Extract `logID`
4. Read `Shortcuts/fitbit-last-log-id.txt` from iCloud Drive if it exists
5. If the file exists, compare saved text to the current `logID`
6. If they differ, log the weight and overwrite the saved `logID`
7. If the file does not exist, log the weight and create the saved `logID`

## Actions

1. `Get Contents of URL`
   URL: your `latest-weight.json` endpoint

2. `Get Dictionary from Input`
   Input: `Contents of URL`

3. `Get Value for Key`
   Key: `weights`
   Input: `Dictionary`

4. `Get Item from List`
   Index: `1`
   Input: `Dictionary Value`

5. `Get Value for Key`
   Key: `logID`
   Input: `Item from List`

6. `Get File`
   Service: `Shortcuts`
   Path: `fitbit-last-log-id.txt`
   If Not Found: `Continue`

7. `If`
   Condition: `File has any value`

8. Inside that `If` block, add `Get Text from Input`
   Input: `File`

9. Still inside that `If` block, add another `If`
   Left side: `logID`
   Comparison: `is not`
   Right side: `Text`

10. Inside the inner `If`, add `Get Value for Key`
    Key: `kilograms`
    Input: `Item from List`

11. Inside the inner `If`, add `Get Value for Key`
    Key: `timestamp`
    Input: `Item from List`

12. Inside the inner `If`, add `Get Dates from Input`
    Input: `timestamp`

13. Inside the inner `If`, add `Log Health Sample`
    Type: `Weight`
    Value: `kilograms`
    Unit: `kg`
    Date: `Dates from Input`

14. Inside the inner `If`, add `Save File`
    Input: `logID`
    Service: `Shortcuts`
    Path: `fitbit-last-log-id.txt`
    Overwrite: `On`

15. End the inner `If`

16. In the outer `Otherwise` block, add `Get Value for Key`
    Key: `kilograms`
    Input: `Item from List`

17. In the outer `Otherwise` block, add `Get Value for Key`
    Key: `timestamp`
    Input: `Item from List`

18. In the outer `Otherwise` block, add `Get Dates from Input`
    Input: `timestamp`

19. In the outer `Otherwise` block, add `Log Health Sample`
    Type: `Weight`
    Value: `kilograms`
    Unit: `kg`
    Date: `Dates from Input`

20. In the outer `Otherwise` block, add `Save File`
    Input: `logID`
    Service: `Shortcuts`
    Path: `fitbit-last-log-id.txt`
    Overwrite: `On`

21. End the outer `If`

## Visual structure

```text
If File has any value
  Get Text from File
  If logID is not Text
    Log Health Sample
    Save File
  End If
Otherwise
  Log Health Sample
  Save File
End If
```

## Expected JSON shape

```json
{
  "weights": [
    {
      "kilograms": 81.6,
      "logID": "1234567890",
      "timestamp": "2026-03-15T12:01:00Z"
    }
  ]
}
```
