{
  description = "Armbian kernel flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    { nixpkgs, ... }:

    let
      # List of host systems we want to support
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      # Helper to generate attributes for all systems
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          let
            pkgs = import nixpkgs { inherit system; };
          in
          f {
            inherit pkgs system;
          }
        );

      # Function to create the kernel derivation for a given package set
      makeKernel =
        pkgs:
        pkgs.callPackage ./armbian-kernel.nix {
          name = "armbian-kernel-rockchip64-edge";
          url = "ghcr.io/armbian/os/kernel-rockchip64-edge";
          tag = "6.18.2-S78d8-D0054-P1d2c-Cd71cH25c0-HK01ba-Vc222-B3063-R448a";
          sha256 = "sha256-hfsySDmvLtidZV+UG7UXIl7r/0KsNp5qMvQEZ9kIAR4=";
        };
    in
    {
      # Packages are generated per host system
      packages = forAllSystems (
        { pkgs, system }:
        let
          kernel = makeKernel pkgs;
        in
        {
          default = kernel;
          kernel = kernel;
        }
      );

      # Host-native development shells
      devShells = forAllSystems (
        { pkgs, system }:
        let
          kernel = makeKernel pkgs;
        in
        {
          default = pkgs.mkShell {
            buildInputs = kernel.nativeBuildInputs;
          };
        }
      );
    };
}
