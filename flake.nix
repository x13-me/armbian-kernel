{
  description = "Armbian kernel flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixpkgs-unstable";
  };

  outputs =
    inputs:
    let

      systems = [
        "aarch64-linux"
        "x86_64-linux"
      ];

      forAllSystems =
        f:
        inputs.nixpkgs.lib.genAttrs systems (
          system:
          f {
            pkgs = inputs.nixpkgs.legacyPackages.${system};
          }
        );

    in
    {

      packages.aarch64-linux =
        let

          pkgs = inputs.nixpkgs.legacyPackages.aarch64-linux;

        in
        {
          kernel = pkgs.callPackage ./armbian-kernel.nix {
            name = "armbian-kernel-rockchip64-edge";
            url = "ghcr.io/armbian/os/kernel-rockchip64-edge";
            tag = "6.17.1-S4a24-D54d4-P6f64-C992dH3e0d-HK01ba-Vc222-B14f4-R448a";
            sha256 = "sha256-nik4HzI1YndcGcWi7hIX1lpI22qZagCvxwfNqyRTZIM=";
          };
        };

      devShells = forAllSystems (
        { pkgs }:
        {
          default = pkgs.mkShell {

          };
        }
      );
    };
}
