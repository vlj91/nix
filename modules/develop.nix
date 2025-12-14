{ config, pkgs, lib, ... }:

{
  # Develop profile does NOT modify hostname
  # networking.hostName is left unset to preserve existing hostname

  # Install asdf version manager and common build dependencies
  environment.systemPackages = with pkgs; [
    asdf-vm

    # Build tools commonly needed by asdf plugins
    autoconf
    automake
    libtool
    pkg-config
    openssl
    readline
    zlib
    libffi
    libyaml
    ncurses
    xz
    bzip2
  ];

  # Configure asdf in zsh
  programs.zsh.interactiveShellInit = lib.mkAfter ''
    # asdf configuration
    export ASDF_DIR="${pkgs.asdf-vm}/share/asdf-vm"
    . "$ASDF_DIR/asdf.sh"

    # asdf completions
    fpath=(${pkgs.asdf-vm}/share/asdf-vm/completions $fpath)
  '';
}
