{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    caelestia-shell = {
          url = "github:caelestia-dots/shell";
    };

    hyprland.url = "github:hyprwm/Hyprland";

    caelestia-sddm = {
      url = "github:ItsABigIgloo/caelestia-sddm";
      flake = false;
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self,  nixpkgs, nixpkgs-unstable, home-manager, caelestia-shell, hyprland, caelestia-sddm, ... }@inputs: {
    nixosConfigurations.lk = nixpkgs.lib.nixosSystem {
      specialArgs = { inherit inputs caelestia-shell hyprland; };
      modules = [
        ./configuration.nix
        {
          _module.args.pkgsUnstable = import nixpkgs-unstable {
            system = "x86_64-linux";
            config.allowUnfree = true;
          };
        }

        home-manager.nixosModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            users.lk = import ./home.nix;
            backupFileExtension = "backup";
          };
        }
       ];
     };
   };
 }
