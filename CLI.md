# `traceapp` command-line guide

## How do I install `traceapp`?
Use Setup → Command-line tool, or link the helper manually. See
[`traceapp`](#traceapp).

## How do I capture the app I was just using?
Run `traceapp capture` in a terminal; Trace skips that terminal and inserts
into an open trace. See [`capture`](#capture).

## How do I capture a connected phone?
List devices, then capture by name or identifier. See
[`capture devices`](#capture-devices) and
[`capture --device NAME`](#capture---device-name).

## How do I add images to an open trace?
Pass one or more image paths; Trace inserts them into the current board. See
[`IMAGE...`](#image).

## How do I copy or export a trace?
Use `copy` for the pasteboard or `export` to write files. See
[`copy`](#copy) and [`export`](#export).

## How do I choose what to copy or export?
Pass one of four `--format` values; omitting it uses image plus dictation.
See [`--format FORMAT`](#--format-format).

## How do I stop Dictation from starting automatically?
Add `--no-recording` to a new trace, capture, or image import. See
[`--no-recording`](#--no-recording).

## Install

In Trace, open Setup → Command-line tool and choose **Install**. Trace links
the bundled helper at `/usr/local/bin/traceapp` and requests administrator
approval. Alternatively:

```sh
mkdir -p ~/.local/bin
ln -s /Applications/Trace.app/Contents/Helpers/traceapp ~/.local/bin/traceapp
```

Make sure `~/.local/bin` is on your `PATH`. Debug builds contain their own
helper at `Trace Debug.app/Contents/Helpers/traceapp`.

### Where is the tool stored?

Setup installs a symbolic link at `/usr/local/bin/traceapp`, not a separate
copy of the executable. The executable stays inside the app:

| Location | Purpose |
| --- | --- |
| `/usr/local/bin/traceapp` | Command installed by Setup; links to the app used to install it |
| `/Applications/Trace.app/Contents/Helpers/traceapp` | Bundled production executable |
| `/Applications/Trace Debug.app/Contents/Helpers/traceapp` | Bundled Debug executable |

If you keep Trace outside `/Applications`, the bundled executable is still at
`Contents/Helpers/traceapp` inside that app. To see which app your installed
command points to, run `readlink /usr/local/bin/traceapp`.

## A–Z command glossary

### `--`
**What it does:** Ends option parsing so later tokens are treated as file paths.
**Where:** `traceapp -- -capture.png`.

### `--format FORMAT`
**What it does:** Selects the copy or export format.
**Where:** `traceapp copy --format FORMAT`; `traceapp export PATH --format FORMAT`.
**Note:** Accepted values are `image-dictation` (default), `image`, `dictation`,
and `pdf`. A bare `--format` prints the formats and exits 64.

### `--help`
**What it does:** Prints command usage and the CLI guide link.
**Where:** `traceapp --help` or `traceapp COMMAND --help`.

### `--no-recording`
**What it does:** Suppresses automatic Dictation startup for this request.
**Where:** `traceapp --no-recording`, `traceapp capture --no-recording`, or
`traceapp IMAGE... --no-recording`.

### `capture`
**What it does:** Captures the app in front of the invoking terminal.
**Where:** `traceapp capture`.
**Note:** Inserts at the viewport center of an open trace, or creates a
screenshot trace if none is open. Requires Screen Recording permission.

### `capture --device NAME`
**What it does:** Captures an attached Android or paired iOS device.
**Where:** `traceapp capture --device NAME`.
**Note:** Matches a case-insensitive exact name, identifier, or unique prefix.
An unknown, ambiguous, unavailable, or missing name prints the device list
and exits 64.

### `capture devices`
**What it does:** Lists connected capture devices and availability hints.
**Where:** `traceapp capture devices`.

### `copy`
**What it does:** Copies the whole open trace to the pasteboard.
**Where:** `traceapp copy [--format FORMAT]`.
**Note:** Follows Trace's Close window after copy setting. An omitted format
uses `image-dictation`, independent of the Copy format setting.

### `Exit codes`
**What it does:** Indicates whether the request completed or why it failed.
**Where:** The process exit status.

| Code | Meaning | Example |
| --- | --- | --- |
| `0` | Completed successfully. | `traceapp capture devices` |
| `64` | Invalid command, unknown option, format, or missing option value. | `traceapp --bogus` |
| `66` | File is missing or unreadable. | `traceapp ./missing.png` |
| `69` | Trace could not be launched or reached. | `traceapp` when Trace is unavailable |
| `70` | Trace action failed, or no trace is open for copy/export. | `traceapp copy` with no open trace |
| `75` | Trace is busy with another CLI action. | A second mutation while a capture is running |

### `export`
**What it does:** Writes an export of the whole open trace without closing it.
**Where:** `traceapp export PATH [--format FORMAT]`.
**Note:** A directory path uses the trace name; a path with an extension sets
the filename. `image` writes PNG, `dictation` TXT, `pdf` PDF, and
`image-dictation` PNG plus a sibling TXT when a transcript exists.

### `Formats`
**What it does:** Names the content copied or exported by `--format`.
**Where:** `--format FORMAT`.

| Format | Copy result | Export result | Example |
| --- | --- | --- | --- |
| `image-dictation` | Image with embedded transcript metadata and transcript text. | PNG and, when a transcript exists, a sibling TXT file. | `traceapp copy --format image-dictation` |
| `image` | Image only; does not wait for Dictation to finish. | PNG. | `traceapp export out --format image` |
| `dictation` | Transcript text. | TXT. | `traceapp export out --format dictation` |
| `pdf` | PDF with the image and transcript. | PDF. | `traceapp export out --format pdf` |

**Note:** Copy uses available Dictation first, with up to 3 seconds for a
clipboard update unless something newer was copied. Dictation-only Copy with
no text waits for that bounded result; export waits for Dictation to finish.
Images frame visible content with 8 canvas units of padding; empty traces keep
their page dimensions. See [Copy trace](memory/features/copy-trace.md) for details.

### `IMAGE...`
**What it does:** Opens one or more images in Trace.
**Where:** `traceapp IMAGE...` or `traceapp -- IMAGE...`.
**Note:** Inserts into an open board; otherwise creates a blank trace.
Use `--` or a path such as `./capture.png` for a file whose name matches a
reserved command. Mixed image/traceboard arguments and multiple traceboards
are rejected.

### `traceapp`
**What it does:** Opens a blank trace.
**Where:** `traceapp [--no-recording]`.
**Note:** `traceapp --help` and `traceapp COMMAND --help` show usage.

### `TRACEBOARD`
**What it does:** Opens one editable `.traceboard` document.
**Where:** `traceapp PATH.traceboard`.
