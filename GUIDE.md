# Fitbit → Apple Health: The Complete Guide

Apple Health doesn't have a native Fitbit sync. Google bought Fitbit and they're not exactly motivated to fix that. This guide walks through a self-hosted solution that runs fully automatically once you set it up.

**What you'll have when you're done:**
- A daily automation that syncs your most recent weigh-in to Apple Health, deduplicated so it never adds the same entry twice
- An optional one-time backfill to import your full Fitbit weight history

**Time to set up:** about 30–60 minutes

---

## How it works

```
Fitbit API
    ↓  (cron job, 8 AM daily)
Raspberry Pi — fitbit_export.py
    ↓  (Python HTTP server, port 8766)
latest-weight.json
    ↓  (Tailscale private network)
iPhone Shortcut — daily automation
    ↓
Apple Health
```

The Pi handles token refreshes and API calls. Your iPhone Shortcut fetches the JSON, checks if the `logID` is new (vs. what's saved in iCloud Drive), and writes to Apple Health only if it is.

---

## What you need

- A Fitbit scale (Aria 2, Aria Air, or any scale that logs to the Fitbit app)
- A Raspberry Pi (any model) or another always-on Linux box running Python 3
- A Mac or PC to run the one-time OAuth bootstrap
- [Tailscale](https://tailscale.com) installed on both the Pi and your iPhone (free personal plan)
- An iPhone with the Shortcuts app

---

## Step 1 — Create a Fitbit developer app

1. Go to [dev.fitbit.com](https://dev.fitbit.com) and sign in with your Fitbit account
2. Click **Manage** → **Register An App**
3. Fill in the form:
   - **Application Name:** anything (e.g., "My Weight Sync")
   - **Application Type:** Personal
   - **OAuth 2.0 Application Type:** Personal
   - **Redirect URI:** `http://localhost:8765/callback`
   - **Default Access Type:** Read-Only
4. Under **Permissions**, check **Weight** (and **Profile** if you want)
5. Click **Register**
6. Save your **OAuth 2.0 Client ID** and **Client Secret** — you'll need both

---

## Step 2 — Bootstrap your OAuth token (one time, on your Mac/PC)

Download [`oauth_bootstrap.py`](oauth_bootstrap.py) from this repo and run it:

```bash
python3 oauth_bootstrap.py \
  --client-id YOUR_CLIENT_ID \
  --client-secret YOUR_CLIENT_SECRET \
  --output token.json
```

This opens Fitbit's authorization page in your browser. Sign in, allow the **Weight** permission, and the script captures the callback automatically and saves `token.json`.

No third-party libraries required — pure Python standard library.

---

## Step 3 — Set up the Pi

### 3a. Install the scripts

SSH into your Pi and run:

```bash
sudo mkdir -p /opt/fitbit-scale
sudo chown $USER:$USER /opt/fitbit-scale
```

Download [`fitbit_export.py`](fitbit_export.py) from this repo and copy it to the Pi:

```bash
scp fitbit_export.py pi-user@your-pi-ip:/opt/fitbit-scale/fitbit_export.py
```

Copy your token file:

```bash
scp token.json pi-user@your-pi-ip:/opt/fitbit-scale/token.json
chmod 600 /opt/fitbit-scale/token.json
```

### 3b. Store your credentials

On the Pi, create `/opt/fitbit-scale/env`:

```bash
cat > /opt/fitbit-scale/env << 'EOF'
FITBIT_CLIENT_ID=your_client_id_here
FITBIT_CLIENT_SECRET=your_client_secret_here
EOF
chmod 600 /opt/fitbit-scale/env
```

Test that the script runs:

```bash
set -a && source /opt/fitbit-scale/env && set +a
python3 /opt/fitbit-scale/fitbit_export.py
cat /opt/fitbit-scale/latest-weight.json
```

You should see a JSON file with your most recent weight entry.

### 3c. Set up the daily cron job

```bash
crontab -e
```

Add this line (runs at 8:05 AM daily — adjust to after your usual weigh-in time):

```
5 8 * * * set -a && source /opt/fitbit-scale/env && set +a && python3 /opt/fitbit-scale/fitbit_export.py >> /var/log/fitbit-export.log 2>&1
```

### 3d. Set up the JSON file server

Create the systemd service:

```bash
sudo tee /etc/systemd/system/fitbit-json.service << 'EOF'
[Unit]
Description=Fitbit weight JSON file server
After=network.target

[Service]
Type=simple
User=YOUR_USERNAME
WorkingDirectory=/opt/fitbit-scale
ExecStart=/usr/bin/python3 -m http.server 8766 --directory /opt/fitbit-scale --bind 0.0.0.0
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

Replace `YOUR_USERNAME` with your Pi username. Then enable and start it:

```bash
sudo systemctl daemon-reload
sudo systemctl enable fitbit-json
sudo systemctl start fitbit-json
```

Verify it's running:

```bash
curl http://localhost:8766/latest-weight.json
```

---

## Step 4 — Connect with Tailscale

Tailscale creates a private network between your devices. Your iPhone can reach your Pi without exposing anything to the internet.

1. [Install Tailscale on your Pi](https://tailscale.com/download/linux) and run `sudo tailscale up`
2. Install the [Tailscale iOS app](https://apps.apple.com/us/app/tailscale/id1470499037) on your iPhone
3. Sign in to the same Tailscale account on both
4. Find your Pi's Tailscale IP in the Tailscale admin console (looks like `100.x.x.x`)
5. Test from your iPhone (with WiFi off): open Safari and navigate to `http://100.x.x.x:8766/latest-weight.json` — you should see your weight JSON

---

## Step 5 — Install the iPhone Shortcuts

> **Before installing:** you'll need to edit the URL in each shortcut to replace `100.x.x.x` with your Pi's actual Tailscale IP.

### Daily Weight Sync

**[Install "Fitbit Daily Weight Sync" →](SHORTCUT_LINK_DAILY)**

This shortcut:
1. Fetches `latest-weight.json` from your Pi
2. Reads the last saved `logID` from `iCloud Drive/Shortcuts/fitbit-last-log-id.txt`
3. If the logID is new (or the file doesn't exist), logs the weight to Apple Health and saves the new logID
4. If the logID matches, does nothing (no duplicate entry)

After installing, tap the shortcut → tap the three dots (•••) to edit → tap the URL and replace `100.x.x.x` with your Pi's Tailscale IP.

### Weight Backfill (one time)

**[Install "Fitbit Weight Backfill" →](SHORTCUT_LINK_BACKFILL)**

This shortcut loops through all entries in `backfill-weights.json` and logs each one to Apple Health. Run it once after setup to import your history. You'll need to generate the backfill file on the Pi first (see below).

After installing, tap the shortcut → tap the three dots to edit → update the URL to `http://YOUR-PI-IP:8766/backfill-weights.json`.

---

## Step 6 — Backfill your history (optional)

To import a date range of historical weight data:

Download [`fitbit_backfill.py`](fitbit_backfill.py) from this repo. Edit the `START_DATE` and `END_DATE` near the top, then copy it to your Pi and run it:

```bash
scp fitbit_backfill.py pi-user@your-pi-ip:/tmp/fitbit_backfill.py
ssh pi-user@your-pi-ip "set -a && source /opt/fitbit-scale/env && set +a && python3 /tmp/fitbit_backfill.py"
```

This writes `/opt/fitbit-scale/backfill-weights.json`. Then run the **Fitbit Weight Backfill** shortcut on your iPhone with Tailscale connected.

---

## Step 7 — Set up the daily automation

This makes the Daily Weight Sync run automatically every morning without you having to open Shortcuts.

1. Open **Shortcuts** → **Automation** tab
2. Tap **+** → **Personal Automation**
3. Choose **Time of Day**
4. Set a time after your usual weigh-in (e.g., 9:00 AM)
5. Set to run **Daily**
6. Tap **Next** → **New Blank Automation**
7. Add action: **Run Shortcut** → choose **Fitbit Daily Weight Sync**
8. Tap **Done**
9. On the automation detail screen, turn off **Ask Before Running**

---

## Troubleshooting

**"The shortcut can't connect to the URL"**
- Make sure Tailscale is connected on your iPhone
- Check the Pi's Tailscale IP hasn't changed
- Verify the JSON server is running: `sudo systemctl status fitbit-json`

**Duplicate weight entries in Apple Health**
- The `Save File` action in the shortcut must receive a **Text** action as input — not a direct variable. If you're building the shortcut by hand, see the note on iOS Shortcuts type-matching below.
- Check `iCloud Drive/Shortcuts/fitbit-last-log-id.txt` exists and contains a logID

**Token expired / "401 Unauthorized" in cron logs**
- The script auto-refreshes the token on every run. Check `/var/log/fitbit-export.log` for the error
- If the refresh token itself expired (Fitbit invalidates them after ~1 year of no use), run `oauth_bootstrap.py` again to get a fresh token

**Cron job not running**
- Check `grep CRON /var/log/syslog` on the Pi
- Make sure the cron line sources the env file: `set -a && source /opt/fitbit-scale/env && set +a`

---

## A note on iOS Shortcuts type-matching (if you build by hand)

If you rebuild the Daily Weight Sync shortcut from scratch rather than installing the shared version, watch out for this: iOS Shortcuts resolves "magic variables" (the blue auto-complete tokens) by **output type**, not by which action is closest.

If your action chain has both a `Get File` action (FILE type) and a `Get Variable: logID` action (TEXT type), and a later `Save File` action scans backwards for input — it'll grab the FILE output, not the TEXT. This means it silently saves an empty file every time and your deduplication never works.

The fix: add a **Text** action containing `[logID]` immediately before `Save File`. This forces TEXT type into the pipeline and `Save File` coerces it correctly to file content.

---

## Files in this repo

| File | Purpose |
|------|---------|
| `fitbit_export.py` | Daily cron script — refreshes token, fetches latest weight, writes JSON |
| `oauth_bootstrap.py` | One-time OAuth setup — opens browser, captures callback, saves token.json |
| `fitbit_backfill.py` | Historical backfill — fetches a date range, writes backfill-weights.json |
| `GUIDE.md` | This guide |
