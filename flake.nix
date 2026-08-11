{
  # CPU port of localthunk's Balatro paint-swirl shader
  # (https://www.shadertoy.com/view/XXtBRr) as a `balatro` animation for the
  # ly TUI display manager, applied as a source patch.
  description = "Balatro paint-swirl animation for the ly display manager (port of shadertoy XXtBRr by localthunk)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # the patch targets ly 1.3.x (new animation: src/animations/Balatro.zig
      # + enum/config/main wiring; adds balatro_col1/2/3 config options)
      patchLy = ly: ly.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ./ly-balatro.patch ];
      });
    in
    {
      overlays.default = final: prev: { ly = patchLy prev.ly; };

      packages = forAllSystems (pkgs: rec {
        ly = patchLy pkgs.ly;
        default = ly;
      });

      # one-import setup: enables ly with the balatro animation.
      # everything uses mkDefault, so host config can override freely.
      nixosModules.default = { lib, pkgs, ... }: {
        services.displayManager.ly = {
          enable = lib.mkDefault true;
          package = patchLy pkgs.ly;
          settings = {
            animation = lib.mkDefault "balatro";
            # CRITICAL: without an explicit full_color key, ly's config
            # migrator assumes a pre-1.1 config and silently demotes the whole
            # greeter to 8-color mode (color values get &0xF-mangled)
            full_color = lib.mkDefault true;
          };
        };
      };
    };
}
