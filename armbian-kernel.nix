{
  name,
  url,
  tag,
  sha256,
  pkgs ? import <nixpkgs> { },
  stdenv ? pkgs.stdenv,
  lib ? pkgs.lib,
}:

let

  # Pull the ORAS artifact using the fetch-oras helper
  fetchOras = import ./fetch-oras.nix {
    inherit (pkgs)
      stdenv
      lib
      fuc
      oras
      ;
  };

  kernelDebs = fetchOras {
    inherit
      name
      url
      tag
      sha256
      ;
  };

  # Extract semantic version (e.g., "6.16.7") from the tag
  version =
    let
      m = builtins.match "([0-9]+\\.[0-9]+\\.[0-9]+)-.*" tag;
    in
    if m == null || builtins.length m < 2 then tag else m [ 1 ];
in

stdenv.mkDerivation {
  pname = name;
  inherit version;

  src = kernelDebs;
  nativeBuildInputs = with pkgs; [
    dpkg
    fuc
  ];

  unpackPhase = ''
    # prep unpackPhase
      unpackDir=$(mktemp -d)
    # #

    # extract debs
      for deb in "$src"/*.deb; do
        [ -e "$deb" ] || return
        echo '$deb='"$deb"
        # dirName=$(basename "$deb" | sed -En 's/linux-(\w+-?\w+)-\w+-\w+_.*_\w+\.deb/\1/p')
        # [ -n "$dirName" ] || return
        # mkdir -p "$unpackDir/$dirName"
        # dpkg-deb -x "$deb" "$unpackDir/$dirName"
        dpkg-deb -x "$deb" "$unpackDir"
      done
    # #

    # cleanup empty dirs
      find "$unpackDir" -type d -empty -delete
    # #
  '';

  # buildPhase = true;

  installPhase = ''
    # prep installPhase
      mkdir -p "$out"
    # #

    # copy files
      cpz -f "$unpackDir" "$out"
    # #

    # make symlinks
      for versioned in "$out"/boot/*; do
        [ -e "$versioned" ] || return
        unversioned=$(basename "$versioned" | sed -En 's/([A-z\.]+)-.*/\1/p')
        [ -n "$unversioned" ] || return
        ln -s $versioned $out/$unversioned
      done
    # #


    echo "removing $unpackDir"
    rmz "$unpackDir"
  '';

  meta = with lib; {
    description = "Armbian kernel pulled via ORAS and repackaged";
    platforms = platforms.linux;
  };
}
