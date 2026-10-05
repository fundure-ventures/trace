# `traceapp` command-line guide

Install from Trace → Setup → **Command-line tool**. The Install action adds
`/usr/local/bin/traceapp` and asks for administrator approval. Alternatively,
link the helper yourself:

```sh
mkdir -p ~/.local/bin
ln -s /Applications/Trace.app/Contents/Helpers/traceapp ~/.local/bin/traceapp
```

Make sure `~/.local/bin` is on your `PATH`. Debug builds contain their own
helper at `Trace Debug.app/Contents/Helpers/traceapp`.

## Commands

| Command | Behavior | Example |
| --- | --- | --- |
| `traceapp` | Opens a blank trace. | `traceapp` |
| `traceapp --no-recording` | Opens a blank trace without starting Dictation. | `traceapp --no-recording` |
| `traceapp capture` | Captures the app in front of the invoking terminal. Inserts into the open trace, or creates a screenshot trace if none is open. | `traceapp capture` |
| `traceapp capture devices` | Lists connected capture devices and any availability hints. | `traceapp capture devices` |
| `traceapp capture --device NAME` | Captures a device by exact name or identifier, or by a unique prefix. | `traceapp capture --device Pixel` |
| `traceapp IMAGE...` | Inserts images into the open trace, or creates a blank trace if none is open. One `.traceboard` path opens that document instead. | `traceapp ./design.png ./flow.jpg` |
| `traceapp copy` | Copies the whole trace in the default image-and-dictation format. Follows Trace's Close window after copy setting. | `traceapp copy` |
| `traceapp copy --format FORMAT` | Copies in the selected format. | `traceapp copy --format image` |
| `traceapp export PATH [--format FORMAT]` | Writes export file(s) under a directory, or uses a path with an extension as the filename. | `traceapp export ~/Desktop/trace-export --format pdf` |

`capture`, `copy`, `export`, and `devices` are reserved subcommands; use
`--` or a path such as `./capture.png` when a file has a reserved name.
Images must be image files Trace can read. A mixed image/document batch,
multiple `.traceboard` files, or an unreadable path is rejected. Use
`--no-recording` with capture or image imports to suppress Dictation from
starting for that request.

## Formats

`--format` accepts:

| Format | Copy result | Export result |
| --- | --- | --- |
| `image-dictation` | Image with embedded transcript metadata and transcript text. This is the default; it does not use the Copy format setting. | PNG and, when a transcript exists, a sibling TXT file. |
| `image` | Image only; does not wait for Dictation to finish. | PNG. |
| `dictation` | Transcript text. | TXT. |
| `pdf` | PDF document with image and transcript. | PDF. |

Dictation-containing formats finish an active recording before returning.
Export does not close the open trace. A directory path uses the trace's name;
a path ending in an extension supplies the output filename.

## Options and help

- `--no-recording` suppresses Dictation auto-start for a new trace or capture.
- `--format FORMAT` selects one of the four formats above. If the option has
  no value, `traceapp` prints the available formats and exits with code 64.
- `capture --device NAME` selects a connected device. Without a name, the
  device list is printed and the command exits with code 64.
- `--` ends option and subcommand parsing for file paths.
- `traceapp --help` and `traceapp COMMAND --help` print usage.

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Completed successfully. |
| `64` | Invalid command or missing option value. |
| `66` | File is missing or unreadable. |
| `69` | Trace could not be launched or reached. |
| `70` | Trace action failed, or no trace is open for copy/export. |
| `75` | Trace is busy. |
