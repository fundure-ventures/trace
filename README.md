# Trace

Trace is a macOS menu-bar app for capturing an app window, annotating it with
built-in drawing tools while you speak, and copying the image and Dictation
together with one command.

## Requirements

- macOS 13 or later
- Screen Recording permission for screenshot capture
- Microphone permission and an OpenRouter API key for Dictation

## Using Trace

- [App guide](APP.md) — capture, annotate, use Dictation, and copy traces
- [CLI guide](CLI.md) — install `traceapp` and use Trace from Terminal

A pen is optional. Trace is physically tested with the **Neo Smartpen M1
(`NWP-F50`)** over Bluetooth, using compatible **Neo Ncode paper** and
calibration. Other Neo models have not been validated.

Dictation accepts a personal OpenRouter API key in Setup, stored in macOS
Keychain, or an externally supplied key.

## Build from source

See the [development guide](DEVELOPMENT.md) for prerequisites, local
configuration, and build commands. From a configured checkout, run:

```sh
./tools/trace
```

## More detail

- [Development guide](DEVELOPMENT.md) — setup, commands, architecture,
  and diagnostics
- [Troubleshooting](TROUBLESHOOTING.md) — known issues and fixes
- [Features](FEATURES.md) — every user-facing feature and its rules
- [Architecture decision records](ADR.md) — current durable
  implementation decisions

## License and contributing

Trace is source-available, not open source. Individuals may view, clone,
modify, and build it solely for their own personal, noncommercial use.
Commercial use and redistribution of source, forks, or binaries are not
permitted. See the [personal-use license](LICENSE) for the complete terms.
Issues are welcome. Code and documentation contributions are accepted under
the terms in [CONTRIBUTING.md](CONTRIBUTING.md).
