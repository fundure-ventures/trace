---
name: trace-release
description: Publish a production Trace release to GitHub Releases from a clean, current main checkout. Builds and notarizes Trace locally, prepares reviewed release notes, verifies version metadata and artifacts, then creates the GitHub release with the signed ZIP and checksum.
---

# Trace release

Use this skill when the user asks to publish, upload, create, or prepare a new
Trace release on the repository's GitHub Releases page.

The release is intentionally local and human-gated. Do not use GitHub Actions
for release signing. Do not create a release from a feature branch, detached
commit, dirty checkout, or stale `main`.

## Collect the release inputs

Obtain:

- `VERSION` in `MAJOR.MINOR.PATCH` form.
- `BUILD_NUMBER` as a positive integer greater than the previous published
  build.

Use the tag `v$VERSION`, title `Trace $VERSION`, and artifact basename
`Trace-$VERSION-$BUILD_NUMBER`.

Ask one question at a time with `ask_user` when either value is missing. Do not
infer a production version or build number.

## Prove the source is current main

Before building:

1. Run `git fetch origin main --tags`.
2. Require that the current branch is exactly `main`.
3. Require that the working tree and index are clean, including untracked
   files other than ignored build outputs.
4. Require that `HEAD` equals `origin/main`.
5. Require that `v$VERSION` does not exist locally, remotely, or as a GitHub
   Release.

Stop and explain the mismatch instead of switching branches, merging, pulling,
stashing, deleting files, or publishing from another commit. The user must
bring a dedicated `main` session to the exact release commit.

Record the release commit SHA and use it as the release target.

## Draft and review release notes

Find the most recent version tag, if any. Build release notes from merged work
between that tag and `HEAD`, favoring user-visible changes over internal
implementation details. GitHub's generated notes may be used as source
material, but edit them into concise sections such as:

- Highlights
- Improvements
- Fixes

Start the body with:

```text
Trace VERSION (build BUILD_NUMBER)
```

Include the exact release commit SHA at the end. Do not include credentials,
private paths, contributor email addresses, or unreviewed commit-message noise.

Show the complete release notes and use `ask_user` to obtain explicit approval
before building or publishing. If the user requests edits, revise and ask
again. Save temporary notes outside the repository, in the session artifact
directory or a secure temporary file.

## Build and sign locally

Verify the local prerequisites without scanning or dumping keychains:

```sh
security find-identity -v -p codesigning
xcrun notarytool history --keychain-profile trace-notary
```

Require exactly one valid `Developer ID Application` identity and a working
`trace-notary` profile.

Build and sign:

```sh
./tools/build-release "$VERSION" "$BUILD_NUMBER"
./tools/sign-release "$VERSION" "$BUILD_NUMBER"
```

Do not pass certificate files, API keys, or passwords on the command line. Do
not copy credentials into the repository. Do not upload caches or intermediate
`.app` bundles.

## Verify the release output

Set:

```sh
APP=".build/Trace.app"
ZIP=".build/release/Trace-$VERSION-$BUILD_NUMBER.zip"
CHECKSUM="$ZIP.sha256"
```

Require all of the following:

```sh
test "$(plutil -extract CFBundleShortVersionString raw -o - \
  "$APP/Contents/Info.plist")" = "$VERSION"
test "$(plutil -extract CFBundleVersion raw -o - \
  "$APP/Contents/Info.plist")" = "$BUILD_NUMBER"
codesign --verify --deep --strict --verbose=2 "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=4 "$APP"
test -f "$ZIP"
test -f "$CHECKSUM"
(cd "$(dirname "$ZIP")" && shasum -a 256 -c "$(basename "$CHECKSUM")")
```

Inspect the ZIP file list and reject it if it contains `.env`, `.p8`, `.p12`,
keychain, provisioning-profile, or private-key files. Confirm the archive
contains exactly one top-level `Trace.app`.

## Publish the GitHub Release

Immediately before publishing, recheck:

- The working tree is still clean.
- `HEAD` still equals the recorded SHA and `origin/main`.
- The tag and GitHub Release still do not exist.
- The approved release notes file is unchanged.

Then create the release:

```sh
gh release create "v$VERSION" \
  "$ZIP" \
  "$CHECKSUM" \
  --target "$RELEASE_SHA" \
  --title "Trace $VERSION" \
  --notes-file "$NOTES_FILE"
```

This atomically creates the tag at `RELEASE_SHA`. Do not create or push the tag separately; release creation must be the first persistent remote mutation.

After creation, verify with `gh release view "v$VERSION"` that:

- The release is published, not draft or prerelease unless explicitly asked.
- The target commit is `RELEASE_SHA`.
- The title and approved release notes are present.
- Both `"$ZIP"` and `"$CHECKSUM"` are attached.

Report the release URL, version, build number, commit SHA, and uploaded asset
names. Remove only temporary notes files created by this skill; keep ignored
local build artifacts unless the user asks to clean them.
