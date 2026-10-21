{
  lib,
  pkgs,
  osConfig,
  ...
}:
{
  home.pointerCursor = {
    enable = true;
    package = pkgs.catppuccin-cursors.mochaMauve;
    name = "catppuccin-mocha-mauve-cursors";
    size = 24;
    gtk.enable = true;
    x11.enable = true;
  };

  gtk = {
    enable = true;
    iconTheme.name = "Papirus-Dark";
    gtk3.theme = {
      name = "adw-gtk3-dark";
      package = pkgs.adw-gtk3;
    };
  };

  xdg.userDirs.enable = true;
  xdg.userDirs.createDirectories = true;
  home.file."Pictures/Wallpapers".source = import ./wallpapers.nix { inherit pkgs; };
  xdg.dataFile."dbus-1/services/org.freedesktop.FileManager1.service".text = ''
    [D-BUS Service]
    Name=org.freedesktop.FileManager1
    Exec=${lib.getExe osConfig.programs.dux-files.package} run --hidden --dbus-activated
  '';
  xdg.mimeApps = {
    enable = true;
    defaultApplications =
      lib.genAttrs [
        "image/png"
        "image/jpeg"
        "image/webp"
        "image/avif"
        "image/gif"
        "image/bmp"
        "image/tiff"
        "image/svg+xml"
        "image/heic"
        "image/heif"
      ] (_: [ "org.kde.gwenview.desktop" ])
      // lib.genAttrs [
        "video/mp4"
        "video/x-matroska"
        "video/webm"
        "video/quicktime"
        "video/x-msvideo"
        "video/mpeg"
        "video/ogg"
        "video/mp2t"
        "video/x-flv"
      ] (_: [ "mpv.desktop" ])
      // lib.genAttrs [
        "application/zip"
        "application/x-7z-compressed"
        "application/vnd.rar"
        "application/x-rar"
        "application/x-rar-compressed"
        "application/x-tar"
        "application/gzip"
        "application/x-gzip"
        "application/x-bzip2"
        "application/x-xz"
        "application/zstd"
        "application/x-zstd"
        "application/x-compressed-tar"
        "application/x-bzip-compressed-tar"
        "application/x-xz-compressed-tar"
        "application/x-zstd-compressed-tar"
      ] (_: [ "org.kde.ark.desktop" ])
      // {
        "application/pdf" = [ "zen-beta.desktop" ];
        "text/html" = [ "zen-beta.desktop" ];
        "x-scheme-handler/http" = [ "zen-beta.desktop" ];
        "x-scheme-handler/https" = [ "zen-beta.desktop" ];
        "inode/directory" = [ "dev.duxlabs.files.desktop" ];
      };
  };

  xdg.configFile = {
    "alacritty/alacritty.toml".source = ../../home/dot_config/alacritty/alacritty.toml;
  };
}
