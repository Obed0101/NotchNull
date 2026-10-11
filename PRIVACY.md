# Privacy

NotchNull has no analytics, no telemetry, no accounts and no server. This page lists everything it reads, writes and sends, so you can check it against the source.

## Network

| Request | When | What is sent |
|---|---|---|
| `GET https://api.anthropic.com/api/oauth/usage` | Every 90 seconds while Claude usage is enabled, after you allow the keychain read | Your existing Claude Code access token, read from the macOS keychain item `Claude Code-credentials`. NotchNull never refreshes, copies or stores the token. |
| `GET https://api.github.com/repos/Obed0101/NotchNull/releases/latest` | Once a day while **Check automatically** is on (Settings › About, on by default), and when you press Check or run `notchnull update` | Nothing beyond the request itself: no token, no identifier, no version. GitHub sees your IP address, as any site does. |
| `GET https://github.com/Obed0101/NotchNull/releases/download/…/NotchNull.zip` | Only when you press Update or run `notchnull update install` | Nothing beyond the request itself. The download is checked against GitHub's published SHA-256, the app's identifier and version, and its signature before it replaces the app. |
| `GET https://api.z.ai/api/monitor/usage/quota/limit` (or `open.bigmodel.cn`) | Every 3 minutes, only when a GLM Coding Plan key is found | That key |
| `GET https://api.kimi.com/coding/v1/usages` | Every 3 minutes, only when a Kimi Code key is found | That key |
| `GET https://api.minimax.io/v1/api/openplatform/coding_plan/remains` (or `api.minimaxi.com`) | Every 3 minutes, only when a MiniMax key is found | That key |
| `GET https://opencode.ai/zen/go/v1/usage` | Every 3 minutes, only when an OpenCode key is found | That key |
| `GET https://api.github.com/copilot_internal/user` | Every 3 minutes, only when a Copilot sign-in is found | That GitHub token |

Codex sessions and token totals are read from local files. While Codex monitoring is enabled, NotchNull also launches the installed `codex app-server --stdio` every 90 seconds and requests `account/rateLimits/read` for current account limits. Codex handles the network request and its own authentication using its existing configuration; NotchNull does not read or store Codex credentials or start model turns. If Codex is unavailable, local log limits remain a fallback and old readings are marked as last known rather than current.

opencode sessions are read from a local database. The other plans (Settings › Agents › Other plans, on by default) use keys your tools already saved: the `env` block of `~/.claude/settings.json` when `ANTHROPIC_BASE_URL` points at the provider, `~/.local/share/opencode/auth.json`, `~/.config/github-copilot/apps.json` / `hosts.json`, or environment variables such as `Z_AI_API_KEY`, `KIMI_CODE_API_KEY`, `MINIMAX_API_KEY` and `OPENCODE_API_KEY`. Each key is sent only to its own provider, and is never stored, copied or refreshed. With no key for a provider, nothing is sent to it.

## Files read

| Path | Why |
|---|---|
| `~/.claude/projects/*/*.jsonl` | Live Claude Code sessions, the last message of a turn, tokens used today |
| `~/.codex/sessions/**/*.jsonl` | Codex sessions and rate limits |
| `~/.local/share/opencode/opencode.db` | opencode sessions and token totals (read-only; v2 `session_v2`/`session_message` tables, pre-2.0 `session` history ignored) |
| `~/.claude/settings.json` | Only when you click **Enable** for approval alerts |
| `~/Downloads` | Download progress, AirDrop arrivals and cleanup deadlines (file names, sizes, the quarantine record and the site a file came from) |
| `~/.notchnull/` | Your settings file and widgets, watched while the app runs |
| Screenshots (Spotlight query) | The screenshot preview |
| The pasteboard | Clipboard history, only while enabled; password managers' concealed items are skipped |

## Files written

Everything lives in `~/Library/Application Support/NotchNull/`:

| File | Contents |
|---|---|
| `clipboard.sealed` | Clipboard history, encrypted with AES-GCM |
| `clipboard.key` | The key for it, readable only by your user |
| `Tray/`, `tray.json` | Files you parked in the Tray |
| `hook-token` | The per-install secret for the local API and hooks, readable only by you |
| `claude-hook.sh` | Only after you enable approval alerts |
| `download-cleanup.json` | Downloads waiting for their deadline: file name, size, source site, a bookmark to follow renames, and when it expires |
| `~/.config/opencode/plugins/notchnull.js` | Only after you enable the opencode plugin in Settings → Agents |

And `~/.notchnull/`, the folder you (or your agent) edit to change the notch:

| File | Contents |
|---|---|
| `settings.json`, `settings.reference.md` | Every setting, rewritten when you change one in the app; the generated reference |
| `widgets/*.json` | Your widgets. The app writes one example (`disk.json`) the first time only and never touches the rest |
| `status.json` | Errors in your files and each widget's latest data |
| `presets/*.json`, `themes/*.json` | Presets and looks of your own; the app only reads them |
| `backups/` | Copies of `settings.json`, `widgets/`, `presets/`, `themes/` and `scripts/`, taken the first time a new version runs, before `notchnull apply` or `restore`, and on `notchnull backup`. The twelve newest of each kind are kept; older ones go to the Trash |
| `bin/notchnull`, `skill/`, `README.md` | The CLI, the agent skill and a guide, refreshed on every launch |
| `token` | A copy of `hook-token` for scripts, readable only by you |

Widget files can contain shell commands. NotchNull runs them in your login shell with a timeout, exactly as written, and only from files in that folder. Their output stays on your Mac, but a command you or your agent write can do anything a command in Terminal can, network included. Read a widget before you drop it in.

**Install** in Settings › Build creates one symbolic link, `~/.claude/skills/notchnull` or `~/.codex/skills/notchnull`, pointing at `~/.notchnull/skill`. **Remove** deletes only that link.

## Local API

NotchNull listens on `127.0.0.1:47823`, never on the network. Every request must carry the token in an `X-NotchNull-Token` header, so web pages cannot call it. It shows activities, opens tabs, pushes widget data, reads or changes settings and can start an update to the official release; it cannot run arbitrary commands by itself, though an activity or widget button can run the command it was given when you click it.

When you enable approval alerts, NotchNull adds its hook to `~/.claude/settings.json`, keeps your other hooks and saves a backup next to it. The hook talks to NotchNull over `127.0.0.1` with a per-install token. The opencode plugin (`POST 127.0.0.1:47823/opencode`) uses the same token. No new external network.

## Permissions

All optional, and none is requested at launch: macOS only asks after you press Allow in Setup, in Settings › Permissions or next to the feature. Claude Code sign-in (reads the keychain item `Claude Code-credentials` for its limits), Bluetooth (device connections and the Bluetooth switch), Calendars (Up next), Accessibility (to replace the system volume/brightness HUD, and to paste with Return from the Clipboard shortcut), Automation (Music and Spotify controls), Camera (the mirror tab, off by default).

## Removing NotchNull

Quit it, delete the app, delete `~/Library/Application Support/NotchNull/` and `~/.notchnull/` (plus the skill links above if you installed them), and — if you enabled approval alerts — click **Disconnect** in Settings → Agents first, or delete the `notchnull-hook` entries from `~/.claude/settings.json`.
