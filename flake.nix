{
  description = "NixOS configuration for lk";

  # ==========================================================================
  # Inputs: everything this config is built from
  # ==========================================================================
  inputs = {
    # --- Package sets ---
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";            # stable base system
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable"; # newer versions of selected apps

    # --- User environment ---
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # --- Desktop (Hyprland + Caelestia) ---
    hyprland.url = "github:hyprwm/Hyprland";
    caelestia-shell.url = "github:caelestia-dots/shell";
    caelestia-sddm = {
      url = "github:ItsABigIgloo/caelestia-sddm";
      flake = false; # plain source repo, only the theme files are used
    };

    # --- Apps not in nixpkgs ---
    claude-desktop.url = "github:poeck/claude-desktop-nix-flake";
  };

  # ==========================================================================
  # Outputs: the actual system definition
  # ==========================================================================
  outputs = { nixpkgs, nixpkgs-unstable, home-manager, ... }@inputs: {
    nixosConfigurations.lk = nixpkgs.lib.nixosSystem {
      # Makes `inputs` available as a module argument (inputs.hyprland, ...)
      specialArgs = { inherit inputs; };

      modules = [
        ./configuration.nix

        # Unstable package set, usable as `pkgsUnstable.<name>` in modules
        {
          _module.args.pkgsUnstable = import nixpkgs-unstable {
            system = "x86_64-linux";
            config.allowUnfree = true;
          };
        }

        # Home Manager, configured per user in ./home.nix
        home-manager.nixosModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;        # share nixpkgs (and allowUnfree) with the system
            useUserPackages = true;      # install user packages into /etc/profiles
            backupFileExtension = "backup"; # rename conflicting files instead of failing
            users.lk = import ./home.nix;
          };
        }
      ];
    };
  };
}
