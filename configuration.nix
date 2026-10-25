{ config, pkgs, lib, inputs, caelestia-shell, hyprland, pkgsUnstable, ... }:

{
  imports =
    [
      inputs.home-manager.nixosModules.default
      ./hardware-configuration.nix

    ];

  #flakes
  nix.settings.experimental-features = ["nix-command" "flakes"];
  nix = {

	# make `nix run nixpkgs#package` use the same nixpkgs as the one used by this flake.
        registry.nixpkgs.flake = inputs.nixpkgs;

        # remove nix-channel related tools & configs, we use flakes instead.
        channel.enable = false;

        # Keep nixPath so we don't have to use flakes for dev shells
        nixPath = lib.mkDefault [ "nixpkgs=${inputs.nixpkgs}" ];
  };

  # Disable Power Key
  services.logind.settings.Login = {
    HandlePowerKey = "ignore";
    HandlePowerKeyLongPress = "ignore";
    InhibitDelayMaxSec = "0";
  };

  boot.blacklistedKernelModules = [ "tiny_power_button" ];

  #boot-loader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  #polkit
  security.polkit.enable = true;

  # Wayland and Hyprland
  services.xserver.enable = true;
  services.xserver.xkb = {
    layout = "de";
    variant = "";
  };

  services.displayManager.sddm = {
    enable = true;
    theme = "caelestia-locklike";

    extraPackages = [
      pkgs.qt6.qtdeclarative
      pkgs.qt6.qt5compat
      pkgs.qt6.qtmultimedia
      pkgs.qt6.qtsvg
      pkgs.roboto
      pkgs.rubik
      pkgs.nerd-fonts.caskaydia-cove
      pkgs.material-symbols
    ];

    wayland = {
      enable = true;
    };
  };

  programs.hyprland = {
    enable = true;
    package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
    portalPackage = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
  };

  qt = {
    enable = true;
    platformTheme = "gnome";
    style = "adwaita-dark";
  };



  # Network
  networking.hostName = "lk";
  networking.networkmanager.enable = true;


  # Time and Locale
  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "de_DE.UTF-8";
    LC_IDENTIFICATION = "de_DE.UTF-8";
    LC_MEASUREMENT = "de_DE.UTF-8";
    LC_MONETARY = "de_DE.UTF-8";
    LC_NAME = "de_DE.UTF-8";
    LC_NUMERIC = "de_DE.UTF-8";
    LC_PAPER = "de_DE.UTF-8";
    LC_TELEPHONE = "de_DE.UTF-8";
    LC_TIME = "de_DE.UTF-8";
  };
  console.keyMap = "de";

  # Keyring
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.sddm.enableGnomeKeyring = true;

  # User
  users.users."lk" = {
    isNormalUser = true;
    description = "Leonard Kagerer";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [];
  };
  services.getty.autologinUser = "lk";

  # Programs
  nixpkgs.config.allowUnfree = true;
  programs.fish.enable = true;
  environment.systemPackages = with pkgs; [
    neovim
    wget
    kitty
    waybar
    git
    hyprpaper
    where-is-my-sddm-theme
    vscode
    kdePackages.dolphin
    rofi
    zed-editor
    caelestia-shell.packages.${pkgs.stdenv.hostPlatform.system}.with-cli
    foot                        # Default terminal in Caelestia
    fish                        # Default shell
    starship                    # Prompt used by Caelestia fish config
    fastfetch                   # System info tool
    btop                        # System monitor
    zed-editor                  # Code editor
    wl-clipboard                # Clipboard utilities
    cliphist
    grim                        # Screenshot utilities
    slurp
    swappy
    awww                        # Wallpaper daemon
    xdg-desktop-portal-hyprland
    xdg-desktop-portal-gtk
    xdg-utils
    papirus-icon-theme
    adwaita-icon-theme
    hicolor-icon-theme
    librsvg                      # Crucial for rendering SVG theme icons in Qt/Quickshell
    gdk-pixbuf                   # Icon loader backend
    kdePackages.qtsvg
    obsidian
    pkgsUnstable.firefox
    pkgsUnstable.thunderbird
    pkgsUnstable.fetch
    slack
    pkgsUnstable.jetbrains.clion
    pkgsUnstable.jetbrains.rider
    pkgsUnstable.jetbrains.idea
    pkgsUnstable.jetbrains.pycharm
    github-desktop
    vencord
    whatsapp-electron
    xournalpp
    signal-desktop
    (stdenv.mkDerivation {
          pname = "caelestia-sddm";
          version = "latest";
          src = inputs.caelestia-sddm;
          installPhase = ''
            mkdir -p $out/share/sddm/themes/
            cp -r themes/locklike $out/share/sddm/themes/caelestia-locklike
          '';
        })
    iio-hyprland
    jq
    gcc
    cmake
    dotnet-sdk
    python3
    jdk17
    jdk21
    gradle
    p7zip
    desktop-file-utils
  ];
  services.upower.enable = true;
  services.power-profiles-daemon.enable = true;
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  hardware.sensor.iio.enable = true;
  programs.nm-applet.enable = true;
  environment.etc."hpiroot.cer".source = ./Wifi_Cert/hpiroot2026.cer;


  # Open Links in Apps
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      # Add your desktop environment's portal here (e.g., xdg-desktop-portal-kde, xdg-desktop-portal-gtk, etc.)
      xdg-desktop-portal-gtk
    ];
  };
  systemd.user.extraConfig = ''
    DefaultEnvironment="PATH=/run/current-system/sw/bin:/etc/profiles/per-user/%u/bin"
  '';

  /*
  (stdenv.mkDerivation {
    name = "hpi-cert";
    installPhase = ''
      mkdir -p $out
      cp ${.} $out/hpiroot.cer
    '';
  });
 */

  # Fonts
  fonts = {
    enableDefaultPackages = true;
    fontDir.enable = true;
    packages = with pkgs; [
      material-symbols
      material-icons
      material-design-icons
      nerd-fonts.caskaydia-cove
      nerd-fonts.jetbrains-mono
      rubik
    ];
    fontconfig.antialias = true;
    fontconfig.hinting.enable = true;
  };
  system.stateVersion = "26.05";
}
