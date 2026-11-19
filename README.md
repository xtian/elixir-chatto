# chatto

Generated Elixir client for [Chatto](https://github.com/chattocorp/chatto)'s [Connect](https://connectrpc.com) API

```elixir
client = Chatto.Connect.new("https://chat.example", token)

Chatto.Admin.V1.AdminUserService.get_member(
  client,
  %Chatto.Admin.V1.GetMemberRequest{target: {:login, "ada"}}
)
```

Pass `request:` to `Chatto.Connect.new/3` to build on an existing `Req.Request`. Other options are merged into the request as `Req` options.

## Regenerating

`lib/chatto/generated` is generated from the Chatto release pinned in `flake.nix`
(`lib.chatto`). After bumping the pin:

```sh
nix develop -c mix chatto.generate
```
