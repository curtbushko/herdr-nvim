{
  description = "herdr workspace sidebar and Neovim annotations";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      mkPlugin =
        pkgs:
        pkgs.vimUtils.buildVimPlugin {
          pname = "herdr-nvim";
          version = (builtins.fromTOML (builtins.readFile ./Cargo.toml)).package.version;
          src = pkgs.lib.cleanSource self;
          # These modules use Neovim APIs; test them in a real headless instance.
          doCheck = false;
        };
      mkBinary =
        pkgs:
        pkgs.rustPlatform.buildRustPackage {
          pname = "herdr-nvim";
          version = (builtins.fromTOML (builtins.readFile ./Cargo.toml)).package.version;
          src = pkgs.lib.cleanSource self;
          cargoLock.lockFile = ./Cargo.lock;
          nativeBuildInputs = [
            pkgs.cmake
            pkgs.pkg-config
          ];
          buildInputs = [
            pkgs.openssl
            pkgs.zlib
          ];
          nativeCheckInputs = [
            pkgs.neovim
            pkgs.git
          ];
          preCheck = ''
            # The fff end-to-end test indexes files returned by git ls-files.
            # Flake source archives omit .git, so provide a sandbox-local index.
            export HOME="$TMPDIR/home"
            mkdir -p "$HOME"
            git -c init.defaultBranch=main init --quiet
            git add .
          '';
          postInstall = ''
            # plugin_root() walks up from bin/ to find the daemon's Lua runtime.
            cp -r lua plugin doc "$out/"
          '';
          meta = {
            description = "Persistent Neovim sidebar and file picker for herdr";
            homepage = "https://github.com/curtbushko/herdr-nvim";
            license = pkgs.lib.licenses.mit;
            mainProgram = "herdr-nvim";
            platforms = systems;
          };
        };
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        rec {
          nvim-plugin = mkPlugin pkgs;
          herdr-nvim = mkBinary pkgs;
          default = nvim-plugin;
        }
      );

      overlays.default = final: _prev: {
        herdr-nvim = mkBinary final;
        vimPlugins = _prev.vimPlugins // {
          herdr-nvim = mkPlugin final;
        };
      };

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            inputsFrom = [ self.packages.${system}.herdr-nvim ];
            packages = [
              pkgs.cargo
              pkgs.rustc
              pkgs.rustfmt
              pkgs.clippy
              pkgs.rust-analyzer
              pkgs.neovim
              pkgs.just
              pkgs.git
              pkgs.nixfmt
            ];
            RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";
          };
        }
      );

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          inherit (self.packages.${system}) nvim-plugin herdr-nvim;
          lua =
            pkgs.runCommand "herdr-nvim-lua-tests"
              {
                nativeBuildInputs = [
                  pkgs.neovim
                  pkgs.git
                ];
              }
              ''
                cp -r ${self} source
                chmod -R u+w source
                cd source
                export HOME="$TMPDIR/home"
                mkdir -p "$HOME"
                nvim --headless --noplugin -u NONE -l tests/run.lua
                touch "$out"
              '';
        }
      );
    };
}
