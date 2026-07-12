# Wrap a from-source Armbian kernel derivation into a full nixpkgs kernel
# package set (`linuxPackagesFor`). This is what makes
# `boot.kernelPackages = …rockchip64-current` work: the set carries the kernel
# plus every out-of-tree module package (zfs, nvidia, wireguard, …) built
# against the kernel's `dev` build tree.
{
  lib,
  pkgs,
  armbianBuild,
  entry,
}:

let
  kernel = import ./linux-source.nix {
    inherit lib pkgs armbianBuild entry;
  };
in
pkgs.linuxPackagesFor kernel
