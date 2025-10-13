# armbian-kernel.nix test wrapper

# call with nix build -f test-armbian-kernel.nix, or Tasks: Run Build Task in VSCode

{
  pkgs ? import <nixpkgs> { },
}:

let
  armbianKernel = import ./armbian-kernel.nix {
    name = "armbian-kernel-rockchip64-edge";
    url = "ghcr.io/armbian/os/kernel-rockchip64-edge";
    tag = "6.17.1-S4a24-D54d4-P6f64-C992dH3e0d-HK01ba-Vc222-B14f4-R448a";
    sha256 = "sha256-nik4HzI1YndcGcWi7hIX1lpI22qZagCvxwfNqyRTZIM=";
  };
  lib = pkgs.lib;
in

# The kernel derivation itself is already the thing we want to test
armbianKernel
