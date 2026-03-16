#!/usr/bin/env python3
"""
Fitbit OAuth bootstrap — get your initial token.json

Run this once on any machine with a browser. After that, the cron job
handles all token refreshes automatically.

Usage:
  python3 oauth_bootstrap.py --client-id YOUR_CLIENT_ID --client-secret YOUR_CLIENT_SECRET

Output:
  token.json in the current directory
"""
import argparse
import base64
import hashlib
import json
import os
import secrets
import socket
import urllib.parse
import urllib.request
import webbrowser
from datetime import datetime, timezone, timedelta
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

REDIRECT_URI = "http://localhost:8765/callback"
SCOPE = "weight"
AUTH_URL = "https://www.fitbit.com/oauth2/authorize"
TOKEN_URL = "https://api.fitbit.com/oauth2/token"

captured_code = None
captured_state = None


def make_pkce():
    verifier = secrets.token_urlsafe(64)
    challenge = base64.urlsafe_b64encode(
        hashlib.sha256(verifier.encode()).digest()
    ).rstrip(b"=").decode()
    return verifier, challenge


def build_auth_url(client_id, state, challenge):
    params = urllib.parse.urlencode({
        "client_id": client_id,
        "response_type": "code",
        "scope": SCOPE,
        "redirect_uri": REDIRECT_URI,
        "state": state,
        "code_challenge": challenge,
        "code_challenge_method": "S256",
    })
    return f"{AUTH_URL}?{params}"


def exchange_code(client_id, client_secret, code, verifier):
    credentials = base64.b64encode(f"{client_id}:{client_secret}".encode()).decode()
    body = urllib.parse.urlencode({
        "client_id": client_id,
        "grant_type": "authorization_code",
        "redirect_uri": REDIRECT_URI,
        "code": code,
        "code_verifier": verifier,
    }).encode()
    req = urllib.request.Request(
        TOKEN_URL,
        data=body,
        headers={
            "Content-Type": "application/x-www-form-urlencoded",
            "Authorization": f"Basic {credentials}",
        },
        method="POST",
    )
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())


class CallbackHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        global captured_code, captured_state
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/callback":
            params = urllib.parse.parse_qs(parsed.query)
            captured_code = params.get("code", [None])[0]
            captured_state = params.get("state", [None])[0]
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.end_headers()
            self.wfile.write(b"""
                <html><body style="font-family:sans-serif;padding:2em">
                <h2>Authorization successful!</h2>
                <p>You can close this tab and return to the terminal.</p>
                </body></html>
            """)

    def log_message(self, fmt, *args):
        pass  # suppress request logs


def main():
    parser = argparse.ArgumentParser(description="Bootstrap Fitbit OAuth token")
    parser.add_argument("--client-id", required=True)
    parser.add_argument("--client-secret", required=True)
    parser.add_argument("--output", default="token.json")
    args = parser.parse_args()

    verifier, challenge = make_pkce()
    state = secrets.token_urlsafe(16)

    auth_url = build_auth_url(args.client_id, state, challenge)

    print("Opening Fitbit authorization in your browser...")
    print(f"\nIf it doesn't open automatically, visit:\n  {auth_url}\n")
    webbrowser.open(auth_url)

    print("Waiting for authorization callback on http://localhost:8765 ...")
    server = HTTPServer(("localhost", 8765), CallbackHandler)
    server.handle_request()

    if not captured_code:
        print("ERROR: No code received. Did you authorize the app?")
        raise SystemExit(1)

    if captured_state != state:
        print("ERROR: State mismatch. Possible CSRF attempt.")
        raise SystemExit(1)

    print("Exchanging code for token...")
    data = exchange_code(args.client_id, args.client_secret, captured_code, verifier)

    expires_at = (
        datetime.now(timezone.utc) + timedelta(seconds=data["expires_in"])
    ).isoformat()

    token = {
        "accessToken": data["access_token"],
        "refreshToken": data["refresh_token"],
        "scope": data["scope"],
        "tokenType": data["token_type"],
        "userID": data.get("user_id"),
        "expiresAt": expires_at,
    }

    output = Path(args.output)
    output.write_text(json.dumps(token, indent=2))
    print(f"\nToken saved to {output}")
    print(f"User ID: {token['userID']}")
    print(f"Expires: {expires_at}")
    print("\nNext step: copy token.json to your Pi:")
    print(f"  scp {output} pi-user@your-pi-ip:/opt/fitbit-scale/token.json")


if __name__ == "__main__":
    main()
