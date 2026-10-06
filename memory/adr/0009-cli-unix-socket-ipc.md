# Use a per-user Unix socket for the command-line interface

**Status:** Accepted

## Context
The `traceapp` helper must dispatch operations into the matching running Trace
instance, including the separate Debug app, without exposing an unauthenticated
local service. The command-line tool also needs structured responses for
errors, device lists, and exported bytes. The command name is `traceapp` so it
does not shadow Apple's `/usr/bin/trace`.

## Decision
Use a newline-delimited, versioned JSON protocol over a Unix-domain socket
inside the user's Trace Application Support directory. Give the socket
owner-only permissions and verify the peer UID before accepting a request.
Derive the endpoint from the app bundle identifier so Debug and Release do not
collide.

## Rejected alternatives
- Distributed notifications: convenient for one-way file-open forwarding,
  but they do not provide a reliable request/reply channel for export bytes.
- AppleScript or URL schemes: introduce quoting and payload limits and do not
  provide the required typed completion response.
- XPC: offers strong service isolation but requires additional service,
  entitlement, and packaging machinery for a helper that ships inside the app.

## Consequences
- The app can return action status, device information, and export data through
  one local request/reply mechanism.
- The socket path and protocol version are compatibility boundaries and need
  explicit handling when the app or helper is upgraded.
- Owner-only permissions and same-UID peer validation remain mandatory.
