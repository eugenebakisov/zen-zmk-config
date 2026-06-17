{
  description = "ZMK firmware for splitkb Aurora Corne (nice_nano_v2)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    zmk-nix = {
      url = "github:lilyinstarlight/zmk-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, zmk-nix }: let
    forAllSystems = nixpkgs.lib.genAttrs (nixpkgs.lib.attrNames zmk-nix.packages);
  in {
    packages = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in rec {
      default = firmware;

      firmware = zmk-nix.legacyPackages.${system}.buildSplitKeyboard {
        name = "firmware";

        # Include ".h" so config/base.keymap can pull in ../helper/*.h
        src = nixpkgs.lib.sourceFilesBySuffices self [ ".board" ".cmake" ".conf" ".defconfig" ".dts" ".dtsi" ".h" ".json" ".keymap" ".overlay" ".shield" ".yml" "_defconfig" ];

        board = "nice_nano_v2";
        shield = "splitkb_aurora_corne_%PART%";

        # West dependency hash. Re-run `nix run .#update` after changing west.yml.
        zephyrDepsHash = "sha256-nEABWjRGMS0XCt5MeUU6fLMg0MWXMK0mULsxxJHeRHM=";

        meta = {
          description = "ZMK firmware";
          license = nixpkgs.lib.licenses.mit;
          platforms = nixpkgs.lib.platforms.all;
        };
      };

      flash = zmk-nix.packages.${system}.flash.override { inherit firmware; };
      update = zmk-nix.packages.${system}.update;

      # macOS-native flasher. The nice!nano in bootloader mode mounts as a
      # volume under /Volumes containing INFO_UF2.TXT; we just copy the .uf2.
      # Reused helper text for the volume-detection logic.
      flashScript = name: parts: pkgs.writeShellApplication {
        inherit name;
        # SC2043: a single-part list (flash-master) makes the for-loop run once.
        excludeShellChecks = [ "SC2043" ];
        text = ''
          find_vol() {
            for v in /Volumes/*; do
              [ -f "$v/INFO_UF2.TXT" ] && { printf '%s\n' "$v"; return 0; }
            done
            return 1
          }

          # Make sure no bootloader volume is already mounted, so we don't
          # mistake a still-present half for the next one.
          wait_gone() {
            while find_vol >/dev/null; do sleep 1; done
          }

          flash_part() {
            part="$1"
            fw="${firmware}/zmk_$part.uf2"
            echo "Put the $part half into bootloader mode (double-tap reset)."
            printf 'Waiting for a UF2 bootloader volume under /Volumes '
            while ! vol="$(find_vol)"; do printf '.'; sleep 1; done
            echo
            echo "Found bootloader volume at $vol"
            # The board reboots the instant the image is fully written, so cp
            # often errors on the final fsync as the volume vanishes -- ignore.
            cp "$fw" "$vol/" || true
            echo "Flashed $part firmware to $vol"
          }

          for p in ${toString parts}; do
            wait_gone
            flash_part "$p"
          done
          echo "Done."
        '';
      };

      # Flash the left (central) half only -- the fast keymap-iteration loop,
      # since the keymap lives only on the central half.
      flash-left = flashScript "zmk-flash-left" [ "left" ];

      # Flash both halves sequentially (left, then right).
      flash-mac = flashScript "zmk-flash-mac" [ "left" "right" ];
    });

    devShells = forAllSystems (system: {
      default = zmk-nix.devShells.${system}.default;
    });
  };
}
