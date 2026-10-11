# Claude usage from MendCode

NotchNull 1.4.9 can reuse the Claude quota readings in MendCode's footer. This optional integration avoids a second usage request and does not read credentials. Codex and other providers are unchanged.

## Setup

1. In MendCode, run `mendcode docs extensions` to find your user extensions directory.
2. Copy [`scripts/notchnull-usage-export.ts`](../scripts/notchnull-usage-export.ts) into that directory. The extension writes only Claude quota percentages, reset times and observation times to `~/Library/Application Support/NotchNull/mendcode-usage.json`.
3. Reload extensions (or restart MendCode) and then restart NotchNull. Leave Claude usage enabled in NotchNull.

MendCode must support `api.usage()`. Ordinary Claude turns populate its readings. To refresh while idle, optionally configure MendCode's `quotaRefresh` with a Claude entry whose `everyMinutes` is 20, preserving any other entries you already use. **This consumes quota:** MendCode runs a minimal Claude Code Haiku turn. It is not one token total. The exporter does not enable probes or change that setting automatically.

## Behavior

- The exporter checks existing readings every 10 seconds without making provider requests. NotchNull also reads the local file every 10 seconds.
- NotchNull preserves the original observation time. After 20 minutes a reading is marked as last known. Expired windows are omitted, not shown as full quota.
- Empty or invalid exports show an unavailable state; they do not trigger Anthropic requests. After selecting the export, NotchNull waits for it if it disappears until the app restarts.
- No subscription name is inferred from percentages, so the Max/Pro badge is not supplied by this integration.
- Without this integration, the existing direct Claude usage endpoint remains in use with consent. This release does not add an independent Haiku launcher to NotchNull or guarantee that the direct endpoint will stop returning HTTP 429.

## Remove

Remove the exporter from MendCode and reload extensions, then move `mendcode-usage.json` out of NotchNull's Application Support folder and restart NotchNull. The prior consent-controlled direct usage method becomes available again.
