{
  stdenv,
  fuc,
  oras,
  lib,
}:

{
  name,
  tag,
  url,
  sha256,
}:

stdenv.mkDerivation {
  pname = name;
  version = "0.2";

  # Fixed-output derivation for reproducibility
  fixedOutput = true;
  outputHashAlgo = "sha256";
  outputHashMode = "recursive";
  outputHash = sha256;

  nativeBuildInputs = [
    oras
    fuc
  ];

  unpackPhase = "true";

  buildPhase = ''
    tmpdir=$(mktemp -d)
    echo "Pulling ORAS artifact ${url}:${tag}"
    oras pull "${url}:${tag}" -o "$tmpdir"

    echo "Untarring artifact into temporary directory"
    for f in "$tmpdir"/*.tar; do
      tar -xf "$f" -C "$tmpdir"
      rmz "$f"
    done

    echo "Creating output directory"
    mkdir -p "$out"

    echo "Copying all files into $out"
    # recursively find files anywhere under tmpdir and copy them to $out
    find "$tmpdir" -type f -exec cpz {} "$out/" \;

    echo "Cleaning up temporary directory"
    rm -rf "$tmpdir"
  '';

  installPhase = "true";

  meta = with lib; {
    description = "Fetch ${name} from ORAS registry and flatten .deb files";
    platforms = platforms.linux;
  };
}
