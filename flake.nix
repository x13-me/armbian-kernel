{
  description = "Armbian kernel flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
  };

  outputs =
    inputs:
    let

      systems = [
        "aarch64-linux"
      ];

      pkgs = inputs.nixpkgs.legacyPackages.aarch64-linux;

    in
    {
      packages.aarch64-linux.kernel = pkgs.callPackage ./armbian-kernel.nix {
        name = "armbian-kernel-rockchip64-edge";
        url = "ghcr.io/armbian/os/kernel-rockchip64-edge";
        tag = "6.18-rc2-S211d-Deeea-Pb94e-C5175H3e0d-HK01ba-Vc222-B14f4-R448a";
        sha256 = "sha256-H0LUFu7yFi9d6xKoHy1jw9yqmCxJL/9kz1aWNO4d0Mo=";
      };
      default = packages.aarch64-linux.kernel;
    };
}
