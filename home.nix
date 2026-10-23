{config, pkgs, ...}:

{
  home.username = "lk";
  home.homeDirectory = "/home/lk";
  home.stateVersion = "25.05";
  home.packages = [ pkgs.slack ];

  xdg.mime.enable = true;
  xdg.mimeApps.defaultApplications = {
    "x-scheme-handler/slack" = "slack.desktop";
  };
  programs.bash = {
    enable = true;
    shellAliases = {
      btw = "echo i use hyprland btw";
    };
    profileExtra = ''
      if [ -z "$WAYLAND_DISPLAY" ] && [ "$XDG_VTNR" = 1 ]; then
        exec start-hyprland
      fi
    '';
  };
}
