# System-wide NixOS configuration for host "lk"
{ config, pkgs, lib, inputs, pkgsUnstable, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
in
{
  imports = [
    ./hardware-configuration.nix
  ];

  # ==========================================================================
  # Nix & Flakes
  # ==========================================================================
  nix = {
    settings.experimental-features = [ "nix-command" "flakes" ];

    # Make `nix run nixpkgs#package` use the same nixpkgs as this flake
    registry.nixpkgs.flake = inputs.nixpkgs;

    # Drop nix-channel tooling, flakes are used instead
    channel.enable = false;


    # Keep NIX_PATH so non-flake tools (e.g. nix-shell) still find nixpkgs
    nixPath = lib.mkDefault [ "nixpkgs=${inputs.nixpkgs}" ];
  };

  nixpkgs.config.allowUnfree = true;
  security.sudo.extraRules = [{
    users = [ "lk" ];
    commands = [{
      command = "/run/current-system/sw/bin/nixos-rebuild";
      options = [ "NOPASSWD" ];
    }];
  }];
  # VSCode 1.144 moved rg from @vscode/ripgrep to @vscode/ripgrep-universal; nixpkgs' postPatch still rm's the old path.
  # Remove once nixpkgs fixes it (the replace then simply stops matching).
  nixpkgs.overlays = [
    (final: prev: {
      vscode = prev.vscode.overrideAttrs (old: {
        postPatch = builtins.replaceStrings
          [ "@vscode/ripgrep/bin/rg" ]
          [ "@vscode/ripgrep-universal/bin/linux-x64/rg" ]
          old.postPatch
        + ''
          ln -sf ${final.ripgrep}/bin/rg resources/app/node_modules.asar.unpacked/@vscode/ripgrep-universal/bin/linux-x64/rg
        '';
      });
    })
  ];
  services.flatpak.enable = true;
  services.flatpak.packages = [
    { appId = "com.brave.Browser"; origin = "flathub";  }
    "com.obsproject.Studio"
  ];

  # ==========================================================================
  # Boot & Kernel
  # ==========================================================================
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Compressed swap in RAM
  zramSwap.enable = true;

  # ==========================================================================
  # Hardware
  # ==========================================================================
  hardware.enableRedistributableFirmware = true;

  # GPU (AMD)
  hardware.graphics = {
    enable = true;
    enable32Bit = true; # needed for gaming (Steam/Wine)
  };
  services.xserver.videoDrivers = [ "amdgpu" ];

  # Bluetooth
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  # Accelerometer / screen rotation sensor (used by iio-hyprland)
  hardware.sensor.iio.enable = true;

  # Power management
  services.upower.enable = true;
  services.power-profiles-daemon.enable = true;

  # Ignore the laptop power button so it can't shut down the system by accident
  services.logind.settings.Login = {
    HandlePowerKey = "ignore";
    HandlePowerKeyLongPress = "ignore";
    InhibitDelayMaxSec = "0";
  };
  boot.blacklistedKernelModules = [ "tiny_power_button" ];

  # ==========================================================================
  # Networking
  # ==========================================================================
  networking.hostName = "lk";
  networking.networkmanager.enable = true;
  programs.nm-applet.enable = true;

  # HPI root certificate for the university Wi-Fi (available at /etc/hpiroot.cer)
  environment.etc."hpiroot.cer".source = ./Wifi_Cert/hpiroot2026.cer;

  # ==========================================================================
  # Locale, Time & Keyboard
  # ==========================================================================
  time.timeZone = "Europe/Berlin";

  # English UI, German formats (dates, units, currency, ...)
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

  # German keyboard layout (graphical session and TTY)
  services.xserver.xkb.layout = "de";
  console.keyMap = "de";

  # ==========================================================================
  # User
  # ==========================================================================
  users.users.lk = {
    isNormalUser = true;
    description = "Leonard Kagerer";
    extraGroups = [ "networkmanager" "wheel" ];
  };
  services.getty.autologinUser = "lk";

  # ==========================================================================
  # Desktop: Hyprland + Caelestia
  # ==========================================================================
  services.xserver.enable = true;

  programs.hyprland = {
    enable = true;
    package = inputs.hyprland.packages.${system}.hyprland;
    portalPackage = inputs.hyprland.packages.${system}.xdg-desktop-portal-hyprland;
  };

  # Login screen: SDDM with the Caelestia theme (theme is installed below)
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
    theme = "caelestia-locklike";
    # Qt modules and fonts the theme needs
    extraPackages = with pkgs; [
      qt6.qtdeclarative
      qt6.qt5compat
      qt6.qtmultimedia
      qt6.qtsvg
      roboto
      rubik
      nerd-fonts.caskaydia-cove
      material-symbols
    ];
  };

  # Dark theme for Qt apps
  qt = {
    enable = true;
    platformTheme = "gnome";
    style = "adwaita-dark";
  };

  # Portals: needed for file pickers and opening links in apps
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

  # Let systemd user services (started by the desktop) find installed programs
  systemd.user.extraConfig = ''
    DefaultEnvironment="PATH=/run/current-system/sw/bin:/etc/profiles/per-user/%u/bin"
  '';

  # Keyring for stored passwords, unlocked at SDDM login
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.sddm.enableGnomeKeyring = true;
  programs.seahorse.enable = true; # GUI for the keyring

  # ==========================================================================
  # Fonts
  # ==========================================================================
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

  # ==========================================================================
  # Programs with NixOS modules
  # ==========================================================================
  programs.fish.enable = true;
  programs.direnv.enable = true; # auto-load per-project dev environments
  programs.nix-ld.enable = true; # run unpatched, non-Nix binaries
  programs.java.enable = true;

  # Gaming
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;               # Steam Remote Play
    dedicatedServer.openFirewall = true;          # Source Dedicated Server
    localNetworkGameTransfers.openFirewall = true; # Local network game transfers
    gamescopeSession.enable = true;
    extraPackages = [ pkgs.jdk ];
  };

  # npm global installs go to a writable dir in $HOME (Nix store is read-only)
  environment.sessionVariables = {
    NPM_CONFIG_PREFIX = "$HOME/.npm-global";
    PATH = [ "$HOME/.npm-global/bin" ];
  };

  # ==========================================================================
  # System packages
  # ==========================================================================
  environment.systemPackages = with pkgs; [
    # --- Caelestia shell & its dependencies ---
    inputs.caelestia-shell.packages.${system}.with-cli
    foot          # default terminal in Caelestia
    starship      # prompt used by the Caelestia fish config
    fastfetch     # system info
    btop          # system monitor
    wl-clipboard  # clipboard utilities
    cliphist
    grim          # screenshot utilities
    slurp
    swappy
    awww          # wallpaper daemon
    iio-hyprland  # auto screen rotation
    xdg-utils

    # Caelestia SDDM theme, built from the caelestia-sddm input
    (stdenv.mkDerivation {
      pname = "caelestia-sddm";
      version = "latest";
      src = inputs.caelestia-sddm;
      installPhase = ''
        mkdir -p $out/share/sddm/themes/
        cp -r themes/locklike $out/share/sddm/themes/caelestia-locklike
      '';
    })

    # --- Icons & theming ---
    papirus-icon-theme
    adwaita-icon-theme
    hicolor-icon-theme
    librsvg           # renders SVG theme icons in Qt/Quickshell
    gdk-pixbuf        # icon loader backend
    kdePackages.qtsvg

    # --- CLI tools ---
    neovim
    wget
    git
    jq
    p7zip
    desktop-file-utils

    # --- Development ---
    vscode
    zed-editor
    ripes         # RISC-V processor simulator
    github-desktop
    pkgsUnstable.jetbrains.clion
    pkgsUnstable.jetbrains.rider
    pkgsUnstable.jetbrains.idea
    pkgsUnstable.jetbrains.pycharm
    gcc
    cmake
    dotnet-sdk
    python3
    jdk17
    jdk21
    gradle
    claude-code
    nodejs        # Node.js + npm (needed by novamira CLI)
    inputs.claude-desktop.packages.${system}.default

    # --- Browsers & communication ---
    pkgsUnstable.firefox
    google-chrome
    pkgsUnstable.thunderbird
    signal-desktop
    whatsapp-electron

    # --- Productivity ---
    kdePackages.dolphin
    pkgsUnstable.obsidian
    pkgsUnstable.fetch
    # Xournal++ forced to X11 (runs under XWayland)
    (symlinkJoin {
      name = "xournalpp-x11";
      paths = [ xournalpp ];
      buildInputs = [ makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/xournalpp \
          --set GDK_BACKEND x11
      '';
    })

    # --- Media & gaming ---
    pkgsUnstable.cider-2  # Apple Music client
    pkgsUnstable.heroic   # Epic/GOG launcher
  ];

  # ==========================================================================
  # Don't change this, it's the NixOS release this system was first installed with
  # ==========================================================================
  system.stateVersion = "26.05";
}
