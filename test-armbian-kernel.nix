# armbian-kernel.nix test wrapper

# call with nix build -f test-armbian-kernel.nix, or Tasks: Run Build Task in VSCode

{
  pkgs ? import <nixpkgs> { },
}:

let
  armbianKernel = import ./armbian-kernel.nix {
    name = "armbian-kernel-rockchip64-edge";
    url = "ghcr.io/armbian/os/kernel-rockchip64-edge";
    tag = "6.18-rc2-S211d-Deeea-Pb94e-C5175H3e0d-HK01ba-Vc222-B14f4-R448a";
    sha256 = "sha256-H0LUFu7yFi9d6xKoHy1jw9yqmCxJL/9kz1aWNO4d0Mo=";
  };
  lib = pkgs.lib;
in

# The kernel derivation itself is already the thing we want to test
armbianKernel
