{
  description = "Armbian kernel flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    { nixpkgs, ... }:

    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

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

      kernelVersion = import ./kernelversion.nix;

      makeKernel = pkgs: pkgs.callPackage ./armbian-kernel.nix kernelVersion;
    in
    {
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
    };
}
