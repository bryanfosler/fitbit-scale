#!/usr/bin/env python3
"""
Backfill Fitbit weight data for a specific date range.
Writes to /opt/fitbit-scale/backfill-weights.json
"""
import json
import os
import sys
import urllib.request
import urllib.parse
import base64
from datetime import datetime, timezone, timedelta
from pathlib import Path

TOKEN_FILE = Path("/opt/fitbit-scale/token.json")
OUTPUT_FILE = Path("/opt/fitbit-scale/backfill-weights.json")
ENV_FILE = Path("/opt/fitbit-scale/env")

# Load env vars from env file
if ENV_FILE.exists():
    for line in ENV_FILE.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, _, v = line.partition("=")
            os.environ.setdefault(k.strip(), v.strip())

CLIENT_ID = os.environ.get("FITBIT_CLIENT_ID", "")
CLIENT_SECRET = os.environ.get("FITBIT_CLIENT_SECRET", "")

START_DATE = datetime(2025, 9, 8, tzinfo=timezone.utc)
END_DATE = datetime(2026, 2, 14, tzinfo=timezone.utc)

def load_token():
    with open(TOKEN_FILE) as f:
        return json.load(f)

def save_token(token):
    tmp = TOKEN_FILE.with_suffix(".tmp")
    with open(tmp, "w") as f:
        json.dump(token, f, indent=2)
    tmp.replace(TOKEN_FILE)

def refresh_token(token):
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

def fetch_chunk(token, start, end):
    start_str = start.strftime("%Y-%m-%d")
    end_str = end.strftime("%Y-%m-%d")
    url = f"https://api.fitbit.com/1/user/-/body/log/weight/date/{start_str}/{end_str}.json"
    req = urllib.request.Request(
        url,
        headers={
            "Authorization": f"Bearer {token['accessToken']}",
            "Accept-Language": "en_US",
        },
    )
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read())
    return data.get("weight", [])

def to_kg(lbs):
    return round(lbs / 2.20462, 4)

def main():
    print(f"Loading token...")
    token = load_token()

    print(f"Refreshing token...")
    token = refresh_token(token)
    save_token(token)
    print(f"Token refreshed.")

    # Fetch in 30-day chunks
    all_entries = []
    chunk_start = START_DATE
    while chunk_start <= END_DATE:
        chunk_end = min(chunk_start + timedelta(days=29), END_DATE)
        print(f"Fetching {chunk_start.date()} to {chunk_end.date()}...")
        entries = fetch_chunk(token, chunk_start, chunk_end)
        print(f"  Got {len(entries)} entries")
        all_entries.extend(entries)
        chunk_start = chunk_end + timedelta(days=1)

    # Deduplicate and sort
    seen = set()
    unique = []
    for e in sorted(all_entries, key=lambda x: (x["date"], x["time"])):
        key = (e["date"], e["time"])
        if key not in seen:
            seen.add(key)
            unique.append(e)

    print(f"\nTotal unique entries: {len(unique)}")

    weights = []
    for e in unique:
        ts = datetime.fromisoformat(f"{e['date']}T{e['time']}").replace(tzinfo=timezone.utc).isoformat()
        value = e["weight"]
        weights.append({
            "logID": str(e["logId"]),
            "timestamp": ts,
            "value": value,
            "kilograms": to_kg(value),
            "source": e.get("source"),
        })

    payload = {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "unit": "pounds",
        "weights": weights,
    }

    tmp = OUTPUT_FILE.with_suffix(".tmp")
    with open(tmp, "w") as f:
        json.dump(payload, f, indent=2)
    tmp.replace(OUTPUT_FILE)

    print(f"Written to {OUTPUT_FILE}")
    if weights:
        print(f"Date range: {weights[0]['timestamp'][:10]} to {weights[-1]['timestamp'][:10]}")

if __name__ == "__main__":
    main()
