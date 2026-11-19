{
  description = "Generated Elixir client for Chatto's Connect API";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      # The Chatto release mix chatto.generate generates from; bump with the servers.
      lib.chatto = rec {
        version = "0.5.0";
        src = fetchGit {
          url = "https://github.com/chattocorp/chatto.git";
          ref = "refs/tags/v${version}";
          rev = "761c6589cad0b18a72e1487334e785e825525c85";
        };
      };

      # Generation tools; bring your own Elixir, since only the protox version matters.
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            buf
            protobuf
          ];
        };
      });
    };
}
