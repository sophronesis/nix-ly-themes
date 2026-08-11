# nix-ly-balatro-theme

[Balatro](https://www.playbalatro.com)'s animated paint-swirl background as a login-screen animation for the [ly](https://codeberg.org/fairyglade/ly) TUI display manager, packaged as a Nix flake.

It is a CPU port of the **original shader by localthunk: <https://www.shadertoy.com/view/XXtBRr>**, applied to ly as a source patch that adds a new `balatro` animation (next to `doom`, `matrix`, `colormix`, ...).

![preview](preview.png)

*left: truecolor rendering - right: the linux VT's 16-color approximation, i.e. what the greeter actually shows on the console (regenerate with `tools/preview.py`)*

How the port works:

- terminal cells act as pixels (a cell counts as 1 unit wide, 2 tall, so the swirl stays round)
- the shader's final color is a pure function of its `paint_res` field, so the exact gradient - three-color paint mix **plus the white gloss streaks** - collapses into a 48-entry LUT of pre-dithered `░▒▓█` cells; each frame only evaluates the swirl field
- time is wall-clock, so the swirl moves at the same speed as the shadertoy preview regardless of frame pacing; the field recomputes at most ~30 fps (cheaper than ly's stock `colormix`, which redraws at up to ~200 fps)

## usage

Flake input + one module import:

```nix
{
  inputs.ly-balatro.url = "github:sophronesis/nix-ly-balatro-theme";

  # in your nixosSystem:
  modules = [
    ly-balatro.nixosModules.default
    # ...
  ];
}
```

That enables `services.displayManager.ly` with the patched package, `animation = balatro` and `full_color = true` (all `mkDefault`, override freely).

Alternatively take just the pieces:

- `overlays.default` - replaces `pkgs.ly` with the patched build
- `packages.<system>.ly` / `.default` - patched ly from this flake's pinned nixpkgs (`nixos-25.11`)
- `ly-balatro.patch` - plain `-p1` patch if you want to wire it yourself

The patch targets **ly 1.3.x**.

## tweaking

Colors are runtime config (`0xRRGGBB`, or `0x20000000` for termbox true black):

```nix
services.displayManager.ly.settings = {
  balatro_col1 = "0x00DE443B"; # paint 1 (default: balatro red)
  balatro_col2 = "0x000055B4"; # paint 2 (default: balatro blue)
  balatro_col3 = "0x20000000"; # boundary paint (default: true black)
};
```

Defaults are tuned so the kernel VT's truecolor→16-color quantization lands exactly on bright red / bright blue / black. Speed, contrast, lighting and the LUT size mirror the shader's `#define`s as constants at the top of `src/animations/Balatro.zig` inside the patch.

## the `full_color` gotcha

ly's config migrator treats any config file **without an explicit `full_color` key** as predating truecolor support and silently demotes the whole greeter to 8-color mode, mangling every 24-bit color value through `&0xF`. The NixOS ly module doesn't set the key by default, so this bites stock setups too (your `colormix` colors were probably never what you configured). This flake's module sets `full_color = true`; keep it if you write your own settings block.

## credits & license

- shader: [localthunk](https://www.playbalatro.com) - <https://www.shadertoy.com/view/XXtBRr>. Shadertoy's default license is CC BY-NC-SA 3.0; the `Balatro.zig` animation in the patch is a derivative of that shader and keeps that license
- [ly](https://codeberg.org/fairyglade/ly) is WTFPL; the flake/scaffolding here is WTFPL too
