{
  description = "Koka neovim plugin";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    neorocks.url = "github:nvim-neorocks/neorocks";
    gen-luarc.url = "github:mrcjkb/nix-gen-luarc-json";
    git-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";
    # Pinned nixpkgs that provides koka 3.2.9 (matches the other koka projects).
    koka-nixpkgs.url = "github:NixOS/nixpkgs/1c89083e451e891152365b799595cf7790a43325";
  };

  outputs = {
    self,
    nixpkgs,
    neorocks,
    gen-luarc,
    git-hooks,
    flake-utils,
    koka-nixpkgs,
    ...
  }: let
    name = "kokanvim";

    plugin-overlay = import ./nix/plugin-overlay.nix {inherit name self;};
    ci-overlay = import ./nix/ci-overlay.nix {
      inherit self;
      plugin-name = name;
    };

    systems = [
      "aarch64-linux"
      "aarch64-darwin"
      "x86_64-darwin"
      "x86_64-linux"
    ];
  in
    flake-utils.lib.eachSystem systems (system: let
      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          plugin-overlay
          ci-overlay
          neorocks.overlays.default
          gen-luarc.overlays.default
        ];
      };

      # koka 3.2.9 from the pinned nixpkgs, not the floating one above.
      koka = koka-nixpkgs.legacyPackages.${system}.koka;

      luarc-plugins = with pkgs.lua51Packages; (with pkgs.vimPlugins; [
        toggleterm-nvim
        telescope-nvim
        nvim-dap
      ]);

      luarc-nightly = pkgs.mk-luarc {
        nvim = pkgs.neovim-nightly;
        plugins = luarc-plugins;
      };

      luarc-stable = pkgs.mk-luarc {
        nvim = pkgs.neovim-unwrapped;
        plugins = luarc-plugins;
        disabled-diagnostics = [
          "undefined-doc-name"
          "redundant-parameter"
          "invisible"
        ];
      };

      mkTypeCheck = luarc:
        git-hooks.lib.${system}.run {
          src = self;
          hooks.lua-ls = {
            enable = true;
            settings.configuration = luarc;
          };
        };

      type-check-nightly = mkTypeCheck luarc-nightly;
      type-check-stable = mkTypeCheck luarc-stable;

      pre-commit-check = git-hooks.lib.${system}.run {
        src = self;
        hooks = {
          alejandra.enable = true;
          stylua.enable = true;
          luacheck.enable = true;
          editorconfig-checker.enable = true;
          markdownlint.enable = true;
        };
      };

      kokanvim-shell = pkgs.mkShell {
        name = "koka.nvim-devShell";
        shellHook = ''
          ${pre-commit-check.shellHook}
          ln -fs ${pkgs.luarc-to-json luarc-nightly} .luarc.json
        '';
        buildInputs =
          self.checks.${system}.pre-commit-check.enabledPackages
          ++ (with pkgs; [
            lua-language-server
            busted-nlua
            koka
            (lua5_1.withPackages (ps: with ps; [luarocks]))
          ]);
      };
    in {
      devShells = rec {
        default = kokanvim;
        kokanvim = kokanvim-shell;
      };

      packages = rec {
        default = kokanvim;
        kokanvim = pkgs.kokanvim-dev;
        inherit (pkgs) nvim-minimal-stable nvim-minimal-nightly;
      };

      checks = {
        inherit type-check-stable type-check-nightly pre-commit-check;
        inherit (pkgs) nvim-stable-tests nvim-nightly-tests;
      };

      formatter = pkgs.alejandra;
    })
    // {
      overlays = {
        inherit ci-overlay plugin-overlay;
        default = plugin-overlay;
      };
    };
}
