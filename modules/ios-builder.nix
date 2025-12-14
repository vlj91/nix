{ config, pkgs, lib, ... }:

{
  # iOS builder profile does NOT modify hostname
  # networking.hostName is left unset to preserve existing hostname

  # Install tart via Homebrew
  homebrew.brews = [
    "tart"
  ];
}
