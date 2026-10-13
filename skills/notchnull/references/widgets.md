# Widgets

A widget is one JSON file in `~/.notchnull/widgets/`. The file name without `.json` is its id.
Widgets show up as cards in the Widgets tab, in file order unless `order` says otherwise. The notch
starts with no widgets and no Widgets tab: the tab appears as soon as the first file is saved and
goes away when the last one is deleted.
Saving a file reloads it; a widget whose file did not change keeps its data.

## File

```json
{
  "title": "Open PRs",
  "symbol": "arrow.triangle.pull",
  "tint": "purple",
  "size": "medium",
  "refresh": 120,
  "command": "gh search prs --author @me --state open --json title,number,url,repository",
  "timeout": 15,
  "view": { "type": "text", "text": "{{data | count}} open" },
  "wing": { "when": "{{data | count}}", "trailingText": "{{data | count}} PRs" },
  "data": null,
  "order": 0,
  "enabled": true
}
```

| Key | Default | Meaning |
|---|---|---|
| `view` | required | The node tree to draw (below). |
| `title` | the id | Card header. |
| `symbol` | none | SF Symbol name in the header. |
| `tint` | `teal` | Header symbol and the default color for gauges, bars, badges and symbols. |
| `size` | `medium` | Card width: `small` 150, `medium` 220, `wide` 320 points. |
| `command` | none | Shell command whose output becomes `data`. Without one, `data` is the static `data` key. |
| `refresh` | run once | Seconds between runs; minimum 2. |
| `timeout` | 10 | Seconds before the command is stopped (1–120). |
| `data` | null | Static data, used when there is no command (or before it first runs). |
| `wing` | none | Show something beside the notch (below). |
| `home` | none | Show a row in the Home tab's quick list (below). |
| `order` | 0 | Lower comes first; ties sort by id. |
| `enabled` | true | `false` hides the widget without deleting the file. |
| `description` | none | One line about what it does and needs. Shown in Settings › Build › Examples; ignored otherwise. |

## The command

- Runs as `/bin/zsh -lc "<command>"` in `~/.notchnull`, with `NOTCHNULL_WIDGET=<id>` set,
  stdin closed and output capped at 512 KB.
- stdout that parses as JSON (object, array, number, string, bool) becomes `data` as is.
  Anything else becomes `{"text": "<whole output>", "lines": ["line 1", "line 2"]}`.
- A non-zero exit or a timeout puts the widget in the error state, with stderr in the message.
  The card shows the error in place of the view; `status.json` has the same text.
- Prefer tools that print JSON (`gh … --json`, `curl -s …`, `jq`). For longer logic, put a script
  next to the widgets (`~/.notchnull/scripts/…`, `chmod +x`) and call it.

Data can also be pushed from outside, replacing the command's result until its next run:
`notchnull widget <id> data '{"count": 3}'`.

## Templates

Any string value may contain `{{…}}`. Inside, `data` is the widget's data; in a `list`,
`item` and `index` are the current element.

- Paths: `{{data.build.status}}`, `{{data.items.0.title}}`, `{{item.repository.nameWithOwner}}`.
- A string that is exactly one `{{…}}` keeps the value's type: `"value": "{{data.ratio}}"` passes a
  number to a gauge, `"items": "{{data.prs}}"` passes an array to a list. Mixed text
  (`"{{data.n}} open"`) becomes a string.
- Missing paths are empty, never an error; use `default` for a fallback.
- Filters, chained with `|`:

| Filter | Result |
|---|---|
| `upper`, `lower` | Case. |
| `round` | Nearest whole number. |
| `percent` | `0.42` → `42%`; values above 1 are taken as already percent. |
| `bytes` | `1840000` → `1.8 MB`. |
| `count` | Length of an array, object or string. |
| `first`, `last` | First or last element of an array. |
| `default X` | X when the value is empty, zero, false or null. `X` may be `'quoted text'` or a number. |
| `not` | Boolean negation of truthiness. |
| `relative` | ISO 8601 date or Unix seconds/ms → `2 hours ago`. |
| `div N` | Divide by N: `{{data.used | div 100}}` for a bar from a percentage. |

Truthy: non-empty strings other than `"false"`/`"0"`, non-zero numbers, non-empty arrays and objects, `true`.

## Nodes

Every node is an object with a `type`. Any node accepts `when` (drawn only while truthy) and
`opacity` (0–1). An unknown `type` draws a red "Unknown type" label, so typos show up in renders.

| Type | Keys | Notes |
|---|---|---|
| `column` | `children`, `spacing` (4), `align` (`leading`/`center`/`trailing`), `fill` | Vertical stack; fills the card width unless `"fill": false`. |
| `row` | `children`, `spacing` (6), `align` (`center`/`top`/`bottom`/`baseline`) | Horizontal stack. |
| `stack` | `children` | Layers on top of each other. |
| `text` | `text`, `style`, `color`, `lines` (1), `align` | Styles: `body`, `strong`, `title`, `caption`, `label`, `mono`, `metric`, `large`, `hero`. |
| `value` | `value`, `unit`, `label`, `color`, `style` (`small`) | Big number, unit beside it, label under it. The notch's hero style. |
| `symbol` | `name`, `size` (14), `color` | SF Symbol. |
| `gauge` | `value` (0–1), `size` (44), `color`, `label` | Ring with the percentage (or `label`) inside. |
| `bar` | `value` (0–1), `color`, `height` (4) | Horizontal progress bar. |
| `sparkline` | `values` (array of numbers), `color`, `height` (28), `max` | Small line chart. |
| `list` | `items` (array), `item` (node), `limit` (20), `spacing` (4), `empty` | Repeats `item` for each element. |
| `button` | `title`, `symbol`, `color`, `action`, `help` | Capsule button (below). |
| `badge` | `text`, `color` | Small tinted capsule. |
| `image` | `path`, `size` (36), `radius` (7) | Local file only (`~` allowed); widgets never load from the network. |
| `spacer` | `min` | Flexible space in a row or column. |
| `divider` | | Hairline. |

The root `view` may also set `"animation"`: `spring` (default), `smooth`, `bouncy`, `snappy` or
`none`, used when data changes. Numbers roll, symbols cross-fade, bars and gauges ease.

Colors: `accent` (the user's accent), `primary`, `secondary`, `tertiary`, `green`, `red`,
`orange`, `yellow`, `blue`, `sky`, `purple`, `pink`, `teal`, `claude`, `codex`, `gray`, or
`#RRGGBB`. Prefer names; they follow the theme.

## Actions

Buttons (and wings, when clicked) take an `action` object. Keys can be combined and are templated:

| Key | Effect |
|---|---|
| `"open": "https://…"` or a path | Opens the URL or file. |
| `"copy": "text"` | Copies to the clipboard. |
| `"run": "shell command"` | Runs it (60 s timeout), then re-runs the widget's own command. |
| `"refresh": true` | Re-runs the widget's command. |

## Wings

A `wing` makes the widget slide out beside the notch while `when` is truthy, and go away when it
turns false (checked after every command run). Without `when`, the wing is always up.

```json
"wing": {
  "when": "{{data.failing | count}}",
  "symbol": "xmark.seal.fill",
  "tint": "red",
  "leadingText": "CI",
  "trailingText": "{{data.failing | count}} failing",
  "action": { "open": "{{data.url}}" }
}
```

| Key | Meaning |
|---|---|
| `symbol`, `tint` | Default to the widget's. |
| `leadingText`, `trailingText` | A few characters left and right of the camera. |
| `leading`, `trailing` | A node instead of text on that side (a small `gauge`, a `badge`). |
| `title`, `subtitle`, `progress` | Makes it a banner under the notch, with an optional 0–1 bar. |
| `action` | What a click does (see Actions); without it, a click opens the panel. |

The most recently changed activity owns the notch; system activities with higher priority
(an agent that needs the user, volume, brightness) still take over briefly.

## Home rows

A `home` block also puts the widget in the Home tab's quick list, as one row beside the music
player: its symbol, its title and a short value. Use it for a number the user wants at a glance
without opening the Widgets tab. The row is added below the built-in ones; the user reorders or
hides it in Settings › Tabs & Wings, or you place it in `settings.json` → `home.rows` as
`widget:<id>`.

```json
"home": {
  "text": "{{data.passing}}/{{data.total}} passing",
  "progress": "{{data.ratio}}",
  "action": { "open": "{{data.url}}" }
}
```

| Key | Meaning |
|---|---|
| `text` | The value at the right of the row. Keep it under about 20 characters. |
| `title`, `symbol`, `tint` | Default to the widget's. |
| `progress` | Optional 0–1 bar before the text. |
| `when` | The row shows only while this is truthy. |
| `action` | What a click does (see Actions). |

## Checklist before you finish

- `status.json` shows the widget `ready`, with the `data` you expected.
- `notchnull render /tmp/w.png --tab widgets` looks right: nothing truncated, no red labels.
- If it has a wing, render the condition: `notchnull widget <id> data '<json that makes when true>'`
  and look at the notch, or render a matching `--activity`.
- If it has a `home` block, `notchnull render /tmp/h.png --tab home` shows the row with its text
  in full.
