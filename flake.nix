{
  # Animated shader themes for the ly TUI display manager, applied as source
  # patches:
  #  - `balatro`: CPU port of localthunk's Balatro paint swirl
  #    (https://www.shadertoy.com/view/XXtBRr) as a built-in animation
  #  - `shader`: a generic animation that plays ANY shadertoy-format fragment
  #    shader (mainImage) - rendered offscreen through EGL (llvmpipe on CPU by
  #    default, GPU opt-in) and quantized to terminal cells. Ships with a
  #    single-pass port of sonicether's "Gargantua With HDR Bloom" black hole
  #    (https://www.shadertoy.com/view/lstSRS) and a classic plasma.
  description = "Shader themes for the ly display manager: Balatro paint swirl, Gargantua black hole, or any shadertoy-format fragment shader";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # both patches target ly 1.4.1; ly-shadertoy.patch applies on top of
      # ly-balatro.patch (the shader animation falls back to balatro on any
      # runtime error, so the balatro patch is a hard prerequisite)
      patchLy = ly: ly.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
          ./patches/ly-balatro.patch
          ./patches/ly-shadertoy.patch
        ];
      });
    in
    {
      overlays.default = final: prev: { ly = patchLy prev.ly; };

      packages = forAllSystems (pkgs: rec {
        ly = patchLy pkgs.ly;
        default = ly;
      });

      # one-import setup: enables ly with the balatro animation by default;
      # pick a shader theme (or bring your own shadertoy) via `ly-themes.*`.
      # everything written to services.displayManager.ly is mkDefault, so
      # host config can override any of it freely.
      nixosModules.default = { config, lib, pkgs, ... }:
        let
          cfg = config.ly-themes;

          builtinShaders = {
            blackhole = ./shaders/blackhole.frag;
            plasma = ./shaders/plasma.frag;
            balatro-gl = ./shaders/balatro.frag;
          };

          customShader =
            if cfg.shader == null then null
            else if builtins.isPath cfg.shader then "${cfg.shader}"
            else if lib.hasPrefix "/" cfg.shader then cfg.shader
            else "${pkgs.writeText "ly-theme-shader.frag" cfg.shader}";

          shaderFile =
            if customShader != null then customShader
            else if cfg.theme == "balatro" then null
            else "${builtinShaders.${cfg.theme}}";
        in
        {
          options.ly-themes = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Enable ly with a theme from this flake (importing the module opts in; set false to keep the module inert).";
            };

            theme = lib.mkOption {
              type = lib.types.enum [ "balatro" "blackhole" "plasma" "balatro-gl" ];
              default = "balatro";
              description = ''
                Built-in theme. `balatro` is a pure-CPU animation compiled
                into ly (no GL involved). The rest run on the generic shader
                animation: `blackhole` (sonicether's Gargantua, single-pass
                port), `plasma` (cheap classic), `balatro-gl` (the original
                Balatro GLSL through the shader path instead of the CPU port).
              '';
            };

            shader = lib.mkOption {
              type = with lib.types; nullOr (either path lines);
              default = null;
              example = lib.literalExpression "./my-shadertoy.frag";
              description = ''
                Custom shadertoy-format fragment shader (defines
                mainImage(out vec4, in vec2)) as a file path or inline GLSL
                string; overrides `theme` when set. iTime/iResolution/iFrame/
                iDate etc. are provided; iChannel0/2 sample built-in RGBA
                noise, iChannel1/3 a smooth fbm texture (single-pass shaders
                only, no buffers). Any failure - bad GLSL, no EGL stack -
                is logged to the ly log and the greeter falls back to the
                balatro animation, so a broken shader cannot brick login.
              '';
            };

            gpu = lib.mkOption {
              type = with lib.types; either bool str;
              default = false;
              example = "/dev/dri/by-path/pci-0000:c4:00.0-render";
              description = ''
                GPU rendering for shader themes. `false` renders on the CPU
                via mesa's llvmpipe and never opens a GPU - fine for light
                shaders (~30% of one core at 30 fps), heavy raymarchers like
                the black hole want a GPU. `true` lets mesa pick a GPU (the
                first usable render node - on hybrid laptops that can be the
                dGPU). A DRM node path (by-path symlinks work) pins a
                specific card; if it doesn't exist, ly falls back to mesa's
                default pick.
              '';
            };

            cellMode = lib.mkOption {
              type = lib.types.enum [ "halfblock16" "shade16" "halfblock" ];
              default = "halfblock16";
              description = ''
                How shader pixels map to terminal cells. `halfblock16`:
                upper-half-blocks dithered to the 16 VT colors (best on the
                console; needs U+2580 in the console font). `shade16`: one
                color per cell approximated with dithered ░▒▓█ blends (safest
                glyph set). `halfblock`: truecolor half-blocks (gorgeous in
                kmscon/graphical terminals; the kernel VT bands it to 16
                colors without dithering).
              '';
            };

            fps = lib.mkOption {
              type = lib.types.ints.between 1 60;
              default = 30;
              description = "Shader frame-rate cap. Frames slower than this pace themselves down automatically so input stays responsive.";
            };

            supersample = lib.mkOption {
              type = lib.types.ints.between 1 4;
              default = 2;
              description = "Supersampling factor: the shader renders at (cells*S) x (cells*2*S) pixels and is box-filtered down.";
            };
          };

          config = lib.mkIf cfg.enable {
            services.displayManager.ly = {
              enable = lib.mkDefault true;
              package = lib.mkDefault (patchLy pkgs.ly);
              settings = {
                animation = lib.mkDefault (if shaderFile != null then "shader" else "balatro");
                # CRITICAL: without an explicit full_color key, ly's config
                # migrator assumes a pre-1.1 config and silently demotes the
                # whole greeter to 8-color mode (color values get &0xF-mangled)
                full_color = lib.mkDefault true;
              } // lib.optionalAttrs (shaderFile != null) ({
                shader_path = lib.mkDefault shaderFile;
                # glvnd dispatch library; ly points glvnd at the mesa ICD via
                # /run/opengl-driver/share/glvnd/egl_vendor.d itself
                shader_egl_lib = lib.mkDefault "${pkgs.libglvnd}/lib/libEGL.so.1";
                shader_software = lib.mkDefault (cfg.gpu == false);
                shader_cell_mode = lib.mkDefault cfg.cellMode;
                shader_fps = lib.mkDefault cfg.fps;
                shader_supersample = lib.mkDefault cfg.supersample;
              } // lib.optionalAttrs (lib.isString cfg.gpu) {
                shader_drm_device = lib.mkDefault cfg.gpu;
              });
            };
          };
        };
    };
}
