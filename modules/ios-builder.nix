{ config, pkgs, lib, ... }:

{
  # iOS builder profile does NOT modify hostname

  # Install tart for macOS virtualization
  environment.systemPackages = [
    pkgs.tart
    pkgs.tailscale
  ];
}
