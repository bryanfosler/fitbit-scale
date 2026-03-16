#!/usr/bin/env python3
"""
Fitbit weight exporter for OpenClaw cron.
Refreshes token, fetches recent weight logs, writes latest-weight.json.
"""
import json
import os
import sys
import urllib.request
import urllib.parse
from datetime import datetime, timezone, timedelta
from pathlib import Path

TOKEN_FILE = Path(os.environ.get("FITBIT_TOKEN_FILE", "/opt/fitbit-scale/token.json"))
OUTPUT_FILE = Path(os.environ.get("FITBIT_OUTPUT_FILE", "/opt/fitbit-scale/latest-weight.json"))
CLIENT_ID = os.environ.get("FITBIT_CLIENT_ID", "")
CLIENT_SECRET = os.environ.get("FITBIT_CLIENT_SECRET", "")
DAYS = int(os.environ.get("FITBIT_DAYS", "14"))
LATEST_ONLY = os.environ.get("FITBIT_LATEST_ONLY", "1") == "1"
WEIGHT_UNIT = os.environ.get("FITBIT_WEIGHT_UNIT", "en_US")  # en_US=lbs, METRIC=kg


def log(msg):
    print(f"[fitbit-export] {msg}", flush=True)


def die(msg):
    print(f"[fitbit-export] ERROR: {msg}", file=sys.stderr, flush=True)
    sys.exit(1)


def load_token():
    if not TOKEN_FILE.exists():
        die(f"Token file not found: {TOKEN_FILE}")
    with open(TOKEN_FILE) as f:
        return json.load(f)


def save_token(token):
    TOKEN_FILE.parent.mkdir(parents=True, exist_ok=True)
    tmp = TOKEN_FILE.with_suffix(".tmp")
    with open(tmp, "w") as f:
        json.dump(token, f, indent=2)
    tmp.replace(TOKEN_FILE)


def refresh_token(token):
    if not CLIENT_ID:
        die("FITBIT_CLIENT_ID not set")

    import base64
    credentials = base64.b64encode(f"{CLIENT_ID}:{CLIENT_SECRET}".encode()).decode()

    body = urllib.parse.urlencode({
        "grant_type": "refresh_token",
        "refresh_token": token["refreshToken"],
        "client_id": CLIENT_ID,
    }).encode()

    req = urllib.request.Request(
        "https://api.fitbit.com/oauth2/token",
        data=body,
        headers={
            "Content-Type": "application/x-www-form-urlencoded",
            "Authorization": f"Basic {credentials}",
        },
        method="POST",
    )

    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read())

    expires_at = (datetime.now(timezone.utc) + timedelta(seconds=data["expires_in"])).isoformat()
    return {
        "accessToken": data["access_token"],
        "refreshToken": data["refresh_token"],
        "scope": data["scope"],
        "tokenType": data["token_type"],
        "userID": data.get("user_id"),
        "expiresAt": expires_at,
    }


def fetch_weights(token):
    end = datetime.now(timezone.utc)
    start = end - timedelta(days=DAYS - 1)
    start_str = start.strftime("%Y-%m-%d")
    end_str = end.strftime("%Y-%m-%d")

    url = f"https://api.fitbit.com/1/user/-/body/log/weight/date/{start_str}/{end_str}.json"
    req = urllib.request.Request(
        url,
        headers={
            "Authorization": f"Bearer {token['accessToken']}",
            "Accept-Language": WEIGHT_UNIT,
        },
    )

    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read())

    entries = sorted(data.get("weight", []), key=lambda x: (x["date"], x["time"]))
    return entries


def to_kg(value, unit):
    if unit == "en_US":
        return round(value / 2.20462, 4)
    return value  # already kg


def build_payload(entries):
    now = datetime.now(timezone.utc).isoformat()
    unit_label = "pounds" if WEIGHT_UNIT == "en_US" else "kilograms"

    weights = []
    for e in entries:
        ts = datetime.fromisoformat(f"{e['date']}T{e['time']}").replace(tzinfo=timezone.utc).isoformat()
        value = e["weight"]
        weights.append({
            "logID": str(e["logId"]),
            "timestamp": ts,
            "value": value,
            "kilograms": to_kg(value, WEIGHT_UNIT),
            "source": e.get("source"),
        })

    if LATEST_ONLY and weights:
        weights = [weights[-1]]

    return {
        "generatedAt": now,
        "unit": unit_label,
        "weights": weights,
    }


def write_output(payload):
    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    tmp = OUTPUT_FILE.with_suffix(".tmp")
    with open(tmp, "w") as f:
        json.dump(payload, f, indent=2)
    tmp.replace(OUTPUT_FILE)


def main():
    log("Loading token...")
    token = load_token()

    log("Refreshing token...")
    try:
        token = refresh_token(token)
        save_token(token)
        log("Token refreshed and saved.")
    except Exception as e:
        die(f"Token refresh failed: {e}")

    log("Fetching weights...")
    try:
        entries = fetch_weights(token)
    except Exception as e:
        die(f"Weight fetch failed: {e}")

    if not entries:
        log("No weight entries returned from Fitbit.")
        sys.exit(0)

    payload = build_payload(entries)
    write_output(payload)

    count = len(payload["weights"])
    log(f"Exported {count} entr{'y' if count == 1 else 'ies'} to {OUTPUT_FILE}")

    if payload["weights"]:
        latest = payload["weights"][-1]
        log(f"Latest: {latest['value']} {payload['unit']} on {latest['timestamp'][:10]}")


if __name__ == "__main__":
    main()
