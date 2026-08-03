{ pkgs }:

pkgs.writeShellApplication {
  name = "update-kernels";
  runtimeInputs = with pkgs; [
    nix-prefetch-git
    jq
    curl
    git
  ];
  text = builtins.readFile ../scripts/update-kernels.sh;
}
