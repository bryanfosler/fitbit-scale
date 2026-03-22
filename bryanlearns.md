# Bryan Learns — Fitbit Scale Sync

*The story of building a data pipeline from a Fitbit scale to Apple Health, because Apple and Google don't talk to each other.*

---

## Why This Exists

When Google acquired Fitbit, Apple quietly stopped playing nice with it. Your Aria scale data lives in Fitbit's cloud, but Apple Health won't pull it in automatically. The only way to bridge them is to become the bridge yourself.

This project builds that bridge: a Python script on a Raspberry Pi pulls weight data from the Fitbit API daily, writes it to a tiny JSON file, and an iPhone Shortcut fetches that file and logs it to Apple Health. The whole thing runs while you sleep.

---

## The Architecture

```
Fitbit Aria scale
       ↓ (Bluetooth)
Fitbit app → Fitbit cloud (API)
       ↓ (Python script on Pi, cron 8:05 AM)
latest-weight.json served on port 8766 (Tailscale only)
       ↓ (iPhone Shortcut, daily automation)
Apple Health
```

**Why Tailscale?** The Pi serves JSON on a local port, but your iPhone needs to reach it. Tailscale creates a private VPN between your Pi and your iPhone so you don't have to expose the Pi to the public internet. The Pi gets a stable Tailscale IP that never changes — no dynamic DNS needed.

**Why Python, not the Swift CLI?** The Swift tool (built in sessions 1-2) was great for bootstrapping OAuth, but Python is easier to deploy and update on the Pi without needing Xcode. It has zero dependencies — pure standard library, runs on any Pi.

**Why an iPhone Shortcut?** HealthKit (Apple Health's database) is heavily sandboxed. Only apps and Shortcuts running directly on your iPhone can write to it. There's no API for writing from a Pi or Mac. The Shortcut is the *only* path.

---

## How the Fitbit API Works

Fitbit uses OAuth 2.0 with PKCE (Proof Key for Code Exchange) — a security upgrade over the older OAuth flow. Instead of a shared secret, your app generates a random "code verifier", hashes it, and sends the hash when requesting authorization. Fitbit sends back an auth code, and you redeem it using the original unhashed verifier. This proves you're the same client that started the flow, without ever transmitting a secret.

After initial auth, Fitbit gives you two tokens:
- **Access token** — short-lived (8 hours), used for API calls
- **Refresh token** — long-lived, used to get a new access token when the old one expires

The daily Python script refreshes the access token on every run, then fetches the last 14 days of weight log entries. It picks the most recent one and writes it to `latest-weight.json`.

The body composition fields (`fatPercent`, `bmi`) only appear when the Aria scale actually measured them — manual weight entries from your phone won't have them. The script uses conditional inclusion (`if "fat" in entry`) so the JSON fields are simply absent for manual entries rather than being `null`.

---

## The iPhone Shortcuts — What Makes Them Hard

Shortcuts looks simple but has some genuinely weird behaviors that will make you question your sanity. Here's what we learned the hard way:

### 1. Magic Variables resolve by OUTPUT TYPE, not by position

This burned us in Session 1. When you use a magic variable (the colored pill that references a previous action's output), Shortcuts picks the variable based on what **type** the receiving action expects — not which output is physically closest above it.

The `Save File` action expects a FILE type. So when we had it referencing `logID`, Shortcuts was actually grabbing the FILE output of `Get File from Shortcuts` (the dedup file we just read), not the logID text string. Result: the dedup file was written as an empty file, every run re-logged the same weight, and Bryan ended up with ~12 duplicate entries for 161.4 lbs in Apple Health.

**The fix:** Add a `Text [logID]` action between your variable and `Save File`. This forces the output type to TEXT, so `Save File` sees text and saves it correctly.

### 2. HealthKit units look like bugs but aren't

When you set up a `Log Health Sample` for Body Mass Index, the unit shows as **"count"** — which looks completely wrong. "Count"? For BMI? But this is correct. BMI is dimensionless (it's kg/m², but the units cancel out), so HealthKit represents it as a plain number with no unit. Shortcuts displays this as "count."

Compare the units across the three health types:
- Weight → `lbs`
- Body Fat → `%`
- BMI → `count` ← looks scary, is correct

If you try to change it you'll find you can only choose between "count" and "%" anyway — and "count" is right.

### 3. The big number at the bottom of a running shortcut is not an action

When you run a Shortcut that ends with a `Save File` or similar, the last value the shortcut computed sometimes appears as a large number below the final `End If`. This is just the **runtime output display** — Shortcuts showing you what the last action returned. It's not an orphan action, it's not a bug, you don't need to delete it. It disappears when you close the shortcut.

### 4. If blocks must reference variables that already exist ABOVE them

This is subtle. The `If` action checks a condition against a magic variable — but that magic variable has to come from an action that runs *before* the If.

If you put `Get Value for bmi in entry` *inside* the If block, you can't use the bmi Dictionary Value as the If's condition — it hasn't been computed yet when the If evaluates. The If would instead reference whatever the *previous* action returned (the fatPercent Dictionary Value in our case), which is the wrong thing to check.

**The fix:** Move `Get Value for bmi` to just above the `If bmi has any value` block. Now the If condition correctly references the bmi output, and the Log Health Sample inside the block can use it too.

```
✗ Wrong:
If [old Dictionary Value] has any value
  → Get Value for bmi
  → Log Health Sample (bmi)
End If

✓ Right:
Get Value for bmi in entry        ← produce the value first
If [Dictionary Value] has any value   ← NOW check it
  → Log Health Sample (bmi)
End If
```

### 5. Body fat %: don't divide by 100

The Fitbit API returns body fat as a percentage in the 0–100 range (e.g., `15.746` meaning 15.7%). HealthKit internally stores body fat as 0–1 decimal, but when you use a `Log Health Sample` with unit `%`, Shortcuts handles the conversion for you. Pass the raw Fitbit value directly. Do NOT divide by 100 — that would log `0.15746` and Apple Health would show you as having 0.16% body fat, which would be impressively lean.

### 6. The "Set variable" dance

The `Get Value` action outputs a generic "Dictionary Value" magic variable. The problem is every `Get Value` call produces something called "Dictionary Value" — after two or three of them in a row, Shortcuts doesn't know which one to use where, and you get the wrong data flowing into the wrong action.

The solution is to immediately follow each `Get Value` with a `Set variable` to give it a real name:

```
Get Value for fatPercent in entry → "Dictionary Value"
Set variable fatPercent to Dictionary Value   ← give it a name!
If fatPercent has any value
  Log Health Sample (Body Fat %, value: fatPercent %)
End If
```

Now you're using `fatPercent` (clear, specific) instead of "Dictionary Value" (ambiguous).

---

## The Dedup System

Every weight entry in the Fitbit API has a unique `logID` (a large integer like `1773903869000`). The shortcut remembers the last logID it saw by saving it to a file in iCloud Drive: `Shortcuts/fitbit-last-log-id.txt`.

On each run:
1. Fetch the latest weight entry
2. Read the saved logID from the file (empty string if file doesn't exist yet)
3. `If [current logID] is not [saved logID]` → it's new, log it
4. After logging, save the new logID to the file

The `is not` check handles both cases: "first run" (file is empty, logID is definitely not empty) and "already seen" (logIDs match, skip it). One If block, no nesting needed.

---

## What's Running in Production

- **Cron job on Pi:** `5 8 * * *` → runs at 8:05 AM daily, after most morning weigh-ins
- **JSON server:** `fitbit-json.service` (systemd), port 8766, Tailscale-only
- **iPhone automation:** Shortcuts → Automation → Time of Day → daily → Fitbit Daily Weight Sync (Ask Before Running: OFF)
- **Dedup file:** `iCloud Drive/Shortcuts/fitbit-last-log-id.txt`

---

## Lessons for Next Time

- **Shortcuts are fragile to debug** — you can't console.log, you can't inspect types easily, and errors are often silent. Work one action at a time and test after each change.
- **Read the CLAUDE.md before adding new fields** — the Fitbit JSON format, unit conversions, and shortcut gotchas are all documented there. Don't guess.
- **mirroir-mcp is installed** — Claude can control iPhone Mirroring directly via MCP. Use it instead of screencapture workarounds. Just make sure iPhone Mirroring is open and unlocked.
- **Blue ">" circles in Shortcuts need manual taps** — mirroir-mcp can't tap the destination pickers in Shortcuts. Have Bryan tap those directly.
