# Fitbit Scale Sync

This repo now contains a Swift tool that can run locally or on a server and:

1. Authenticates against the Fitbit Web API
2. Refreshes and stores your Fitbit token
3. Pulls recent Fitbit weight logs
4. Writes a JSON file that an Apple Shortcut can import into Apple Health

## Why this is a server pull plus Apple-side write

A pure server or CLI cannot write directly into Apple Health by itself.

- Apple documents HealthKit authorization as something your app requests from the user inside the app experience.
- Apple also lists `HealthKit` as a supported capability for iOS-family platforms, but not for macOS in the supported-capabilities tables.

That means the cleanest setup without building a custom iPhone app is:

`Fitbit API -> OpenClaw cron job -> JSON at a private URL or shared file -> iPhone Shortcut automation -> Apple Health`

Official references:

- [Fitbit body API reference](https://dev.fitbit.com/build/reference/web-api/body/)
- [Fitbit authorization reference](https://dev.fitbit.com/build/reference/web-api/authorization/)
- [HealthKit authorization](https://developer.apple.com/documentation/healthkit/requesting_authorization_to_use_healthkit_data)
- [Supported capabilities (iOS)](https://developer.apple.com/help/account/reference/supported-capabilities-ios)
- [Supported capabilities (macOS)](https://developer.apple.com/help/account/reference/supported-capabilities-macos)

## Commands

Show help:

```bash
swift run fitbit-scale-exporter help
```

Generate a Fitbit authorization URL:

```bash
swift run fitbit-scale-exporter auth-url \
  --client-id YOUR_FITBIT_CLIENT_ID \
  --redirect-uri fitbitscalesync://auth/callback \
  --pkce
```

Exchange the returned authorization code for a token file:

```bash
swift run fitbit-scale-exporter exchange-code \
  --client-id YOUR_FITBIT_CLIENT_ID \
  --redirect-uri fitbitscalesync://auth/callback \
  --code THE_CODE_FROM_FITBIT \
  --code-verifier THE_PKCE_VERIFIER \
  --token-file ~/.fitbit-scale-sync/token.json
```

Export the latest Fitbit weight entry into iCloud Drive for Shortcut pickup:

```bash
swift run fitbit-scale-exporter export \
  --client-id YOUR_FITBIT_CLIENT_ID \
  --token-file ~/.fitbit-scale-sync/token.json \
  --output ~/Library/Mobile\ Documents/com~apple~CloudDocs/FitbitScale/latest-weight.json \
  --weight-unit pounds \
  --latest-only
```

First run bootstrap if you already have a Fitbit refresh token:

```bash
swift run fitbit-scale-exporter export \
  --client-id YOUR_FITBIT_CLIENT_ID \
  --refresh-token YOUR_REFRESH_TOKEN \
  --token-file ~/.fitbit-scale-sync/token.json \
  --output ~/Library/Mobile\ Documents/com~apple~CloudDocs/FitbitScale/latest-weight.json \
  --weight-unit pounds \
  --latest-only
```

## Output format

The exporter writes JSON like this:

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
      "value": 180.0
    }
  ]
}
```

`kilograms` is included so the Shortcut can write straight into Apple Health without doing unit math.

## Fitbit setup

1. Create a Fitbit developer app in the Fitbit developer console.
2. Give it the `weight` scope. `profile` is also included by default for future account metadata work.
3. Add a redirect URI that matches the one you use in the command line examples.
4. If Fitbit requires a client secret for your app registration, pass `--client-secret` on the relevant commands.

## OpenClaw server flow

This is the version that best matches your preference:

1. Run `fitbit-scale-exporter export --latest-only` from cron on OpenClaw.
2. Write the output JSON somewhere your iPhone can fetch it.
3. Have an iPhone Shortcut automation fetch that JSON and log it into Apple Health.

You have two good ways to publish the JSON:

- Serve a file like `/var/www/fitbit/latest-weight.json` behind your existing OpenClaw web stack.
- Write to `/dev/stdout` and pipe it into whatever storage layer OpenClaw already uses.

Example cron target:

```bash
swift run fitbit-scale-exporter export \
  --client-id YOUR_FITBIT_CLIENT_ID \
  --token-file /opt/fitbit-scale/token.json \
  --output /var/www/fitbit/latest-weight.json \
  --weight-unit pounds \
  --latest-only
```

If you prefer stdout for another deploy path:

```bash
swift run fitbit-scale-exporter export \
  --client-id YOUR_FITBIT_CLIENT_ID \
  --token-file /opt/fitbit-scale/token.json \
  --output /dev/stdout \
  --weight-unit pounds \
  --latest-only
```

An OpenClaw cron example lives at [openclaw-fitbit-scale.cron.example](/Users/bryan/Documents/Codex/Fitbit%20Scale/deploy/openclaw-fitbit-scale.cron.example).

## Suggested Shortcut flow

Create an iPhone Personal Automation that runs once each morning after your weigh-in.

Suggested steps:

1. `Get Contents of URL` from your OpenClaw endpoint, for example `https://openclaw.example.com/fitbit/latest-weight.json`
2. `Get Dictionary from Input`
3. `Get Dictionary Value` for `weights`
4. `Get Item from List` at index `1`
5. `Get Dictionary Value` for `logID`
6. `Get File` from `iCloud Drive/Shortcuts/fitbit-last-log-id.txt` with `If Not Found: Continue`
7. `If logID is not last imported log ID`
8. `Get Dictionary Value` for `kilograms`
9. `Get Dictionary Value` for `timestamp`
10. `Log Health Sample`
11. Health Type: `Weight`
12. Value: `kilograms`
13. Date: `timestamp`
14. `Save File` with `logID` to `iCloud Drive/Shortcuts/fitbit-last-log-id.txt`

That keeps Apple Health from getting duplicate writes if the same JSON file is read more than once.

## Automation examples

- A macOS `launchd` example lives at [com.bryan.fitbit-scale-exporter.plist.example](/Users/bryan/Documents/Codex/Fitbit%20Scale/LaunchAgents/com.bryan.fitbit-scale-exporter.plist.example).
- An OpenClaw cron example lives at [openclaw-fitbit-scale.cron.example](/Users/bryan/Documents/Codex/Fitbit%20Scale/deploy/openclaw-fitbit-scale.cron.example).

## Assumptions and caveats

- The Fitbit weight endpoint used here is the date-range body-weight log API.
- The exporter assumes the numeric values Fitbit returns are in the unit you pass via `--weight-unit`.
- If Fitbit rotates refresh tokens for your app, the tool handles that by overwriting the token file after each successful refresh.
- Shortcut is the Apple Health bridge here. Without a HealthKit-capable Apple-side process on iPhone or another supported Apple platform, there is no direct write path into Apple Health.

## Status

The Swift sources are in place, but I could not complete a full local build verification in this environment because the installed Swift toolchain and Apple SDK are mismatched on this machine.
