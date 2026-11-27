# Changelog

## 0.1.0 (2026-11-27)

First release. The generated code matches Chatto 0.6.0.

### Added

- Protobuf message modules for Chatto's `admin`, `api`, `auth`, `discovery` and `realtime` API packages.
- A module for each of the 33 Connect services in those packages. Each RPC is a function that takes a client and a request struct. It returns `{:ok, response}` or `{:error, %Chatto.Connect.Error{}}`.
- `Chatto.Connect.new/3` builds a `Req` client that sends the token as a bearer token. Pass `request:` to build on an existing `Req.Request`. The function merges other options into the request as `Req` options.
- `Chatto.Connect.Error` has the Connect error code as an atom, the message and the error details. Transport failures return the `:unavailable` code.
- The client retries transient failures with the `Req` `:transient` retry mode.
