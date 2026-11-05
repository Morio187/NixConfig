# Home Manager config for user "lk" (per-user settings and dotfiles)
{ config, pkgs, ... }:

{
  # ==========================================================================
  # Basics
  # ==========================================================================
  home.username = "lk";
  home.homeDirectory = "/home/lk";
  home.stateVersion = "25.05"; # Don't change this, it isn't the HM version you're on

  # ==========================================================================
  # Packages
  # ==========================================================================
  home.packages = [ pkgs.slack ];

  # ==========================================================================
  # Default applications
  # ==========================================================================
  xdg.mime.enable = true;
  xdg.mimeApps.defaultApplications = {
    "x-scheme-handler/slack" = "slack.desktop"; # open slack:// login links in Slack
  };

  # ==========================================================================
  # Shell
  # ==========================================================================
  programs.bash = {
    enable = true;
    shellAliases = {
      btw = "echo i use hyprland btw";
    };
    # Start Hyprland automatically when logging in on TTY1
    profileExtra = ''
      if [ -z "$WAYLAND_DISPLAY" ] && [ "$XDG_VTNR" = 1 ]; then
        exec start-hyprland
      fi
    '';
  };
}
