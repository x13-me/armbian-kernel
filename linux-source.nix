# Build one Armbian kernel target from source, full fidelity.
#
# Given a `kernels.json` entry and the pinned `armbian/build` tree, this:
#   1. fetches the exact upstream kernel release tarball (pinned by hash),
#   2. applies Armbian's full patch series for the family/branch, in the same
#      lexicographic order Armbian uses (no `.series` file for rockchip64-6.18),
#   3. reproduces the family's `0000.patching_config.yaml` in `postPatch`
#      (copy bare `dt/` + `overlay/`, then the add-only DT-Makefile patch),
#   4. builds via `linuxManualConfig` with Armbian's `.config` used verbatim and
#      `LOCALVERSION` passed as a make flag — exactly as `armbian/build` does
#      (`lib/functions/compilation/kernel-make.sh`: `LOCALVERSION=-${BRANCH}-${LINUXFAMILY}`).
#
# The result is a real nixpkgs kernel derivation (with a `dev` build tree), so
# `linuxPackagesFor` and out-of-tree modules work — the whole point of building
# from source rather than repacking Armbian's trimmed-header `.deb`s.
{
  lib,
  pkgs,
  armbianBuild,
  entry,
}:

let
  inherit (entry)
    version
    patchDir
    configFile
    modDirVersion
    localversion
    dtsDirectories
    overlayDirectories
    autopatchMakefile
    ;

  # Two source flavours:
  #  * mainline branches (current/edge) ship as a pinned kernel.org tarball
  #    (`kernelTarball` + `kernelHash`).
  #  * the BSP "vendor" branch is a git branch of Armbian's linux-rockchip fork
  #    (`kernelGit` = { url, rev, hash }) — no upstream tarball exists.
  src =
    if entry ? kernelGit then
      pkgs.fetchgit {
        inherit (entry.kernelGit) url rev hash;
      }
    else
      pkgs.fetchurl {
        url = entry.kernelTarball;
        hash = entry.kernelHash;
      };

  absPatchDir = armbianBuild + "/${patchDir}";

  # Full patch series, lexicographic order (builtins.attrNames is sorted) —
  # matches Armbian's NORMAL_PATCH_FILES ordering (lib/tools/patching.py).
  patchNames = lib.filter (lib.hasSuffix ".patch") (builtins.attrNames (builtins.readDir absPatchDir));
  kernelPatches = map (n: {
    name = n;
    patch = absPatchDir + "/${n}";
  }) patchNames;

  # --- 0000.patching_config.yaml reproduction (runs in postPatch) ------------
  # Copy "bare" directories as-is into the build tree (dts-directories /
  # overlay-directories). Single source dir per target, so "later overwrite
  # earlier" is moot.
  copyDir = d: ''
    install -d "${d.target}"
    cp -f "${absPatchDir}/${d.source}"/* "${d.target}/"
  '';
  dtsCopy = lib.concatMapStringsSep "\n" copyDir dtsDirectories;
  overlayCopy = lib.concatMapStringsSep "\n" copyDir overlayDirectories;

  # The overlay Makefile appends a plain-text README to the DT install list:
  #   dtb-y += $(dtbo-y) $(scr-y) $(dtbotxt-y)   # $(dtbotxt-y) = README.rockchip-overlays
  # It has no build rule, so the kernel's native out-of-tree `make dtbs_install`
  # (O=$buildRoot: compiled .dtbo/.scr land in the build tree, the source-only
  # README does not) aborts with "No rule to make target … README.rockchip-overlays".
  # Armbian's own DTB-install path tolerates it; we don't ship the doc in $out, so
  # drop $(dtbotxt-y) from dtb-y — removing it from both the build and install lists.
  stripOverlayDoc = d: ''
    if [ -f "${d.target}/Makefile" ]; then
      sed -i 's/ *\$(dtbotxt-y)//' "${d.target}/Makefile"
    fi
  '';
  overlayDocStrip = lib.concatMapStringsSep "\n" stripOverlayDoc overlayDirectories;

  # auto-patch-dt-makefile, add-only:true (the Armbian default — the rockchip
  # yaml does not override it). dt_makefile_patcher.py simply APPENDS a
  # `dtb-$(CONFIG_VAR) += <name>.dtb` line for each bare-copied .dts, plus an
  # overlay `subdir-y` line when the copied overlay dir carries a Makefile.
  autopatchOne =
    a:
    let
      srcs = lib.filter (d: d.target == a.directory) dtsDirectories;
      globs = lib.concatMapStringsSep " " (d: ''"${absPatchDir}/${d.source}"/*.dts'') srcs;
    in
    ''
      {
        printf '\n\n# Added by Armbian autopatcher in add-only:true mode\n'
        for f in ${globs}; do
          [ -e "$f" ] || continue
          printf '\ndtb-$(${a.configVar}) += %s.dtb\n' "$(basename "$f" .dts)"
        done
        if [ -f "${a.directory}/overlay/Makefile" ]; then
          printf '\n# Added by Armbian autopatcher for DT overlay\n'
          printf 'subdir-y       := $(dts-dirs) overlay\n'
        fi
      } >> "${a.directory}/Makefile"
    '';
  makefileAutopatch = lib.concatMapStringsSep "\n" autopatchOne autopatchMakefile;

  # Armbian's config is savedefconfig-style (CONFIG_EXPERT=y omits default-y
  # options like EPOLL/PROC_FS/CGROUPS). linuxManualConfig parses `configfile`
  # verbatim into the `config` passthru that NixOS reads for its kernel-feature
  # assertions, so those defaults read as absent and a NixOS toplevel won't
  # build. Expand to a full .config with `make olddefconfig` against the patched
  # source (host-only Kconfig resolution, no cross-compile) so the passthru
  # carries the resolved defaults; the built kernel is unchanged.
  patchedForConfig = pkgs.stdenv.mkDerivation {
    pname = "linux-${modDirVersion}-src-for-config";
    inherit version src;
    patches = map (p: p.patch) kernelPatches;
    dontConfigure = true;
    dontBuild = true;
    installPhase = "cp -a . $out";
  };
  # Optional per-target Kconfig overrides: symbols to force-disable after
  # olddefconfig. rk35xx-vendor disables MALI_CSF_INCLUDE_FW — otherwise the Mali
  # CSF driver `.incbin`s a firmware blob (mali_csffw.bin) not present in the tree
  # and the build fails; disabled, the driver loads it at runtime from /lib/firmware.
  # `# … is not set` survives the follow-up olddefconfig. Empty list → the script is
  # byte-identical to the no-override case, so targets without overrides don't rebuild.
  disableConfigs = entry.disableConfigs or [ ];
  # Symbols to force-enable after olddefconfig (parallel to disableConfigs).
  # rockchip64-current/edge enable FW_LOADER_COMPRESS + FW_LOADER_COMPRESS_ZSTD so
  # panthor can decompress the zstd-packed Mali firmware at runtime. Listed parent-first
  # so the follow-up olddefconfig keeps the child (deps satisfied). Empty list → no-op.
  enableConfigs = entry.enableConfigs or [ ];
  expandedConfig = pkgs.runCommand "linux-${modDirVersion}.config" {
    nativeBuildInputs = with pkgs; [ gnumake gcc bison flex bc ];
  } (
    ''
      cp -a ${patchedForConfig} src && chmod -R u+w src && cd src
      cp ${armbianBuild + "/${configFile}"} .config
      make ARCH=arm64 olddefconfig
    ''
    + lib.optionalString (disableConfigs != [ ]) (
      lib.concatMapStringsSep "\n" (c: "bash scripts/config --file .config --disable ${c}") disableConfigs
      + "\nmake ARCH=arm64 olddefconfig\n"
    )
    + lib.optionalString (enableConfigs != [ ]) (
      lib.concatMapStringsSep "\n" (c: "bash scripts/config --file .config --enable ${c}") enableConfigs
      + "\nmake ARCH=arm64 olddefconfig\n"
    )
    + ''
      cp .config "$out"
    ''
  );

  kernel = pkgs.linuxManualConfig {
    inherit version src modDirVersion kernelPatches;
    configfile = expandedConfig;
    # Parse the .config into the passthru `config` attrset (needed by
    # linuxPackagesFor / OOT module packages). IFD on a plain config file.
    allowImportFromDerivation = true;
    # Armbian sets the kernel's internal version this way; reproduces
    # modDirVersion = <version>-<branch>-<family> from a config with empty
    # CONFIG_LOCALVERSION + LOCALVERSION_AUTO off.
    extraMakeFlags = [ "LOCALVERSION=${localversion}" ];
  };
in
kernel.overrideAttrs (old: {
  # Armbian's rockchip overlay/ Makefile has a `rockchip-fixup.scr` target built
  # with u-boot's `mkimage`. Once the autopatcher wires `subdir-y := overlay`
  # into the DT Makefile, `make dtbs` descends into overlay/ and needs mkimage on
  # PATH — Armbian's own build env has it, nixpkgs' linuxManualConfig does not.
  nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.ubootTools ];

  postPatch = (old.postPatch or "") + ''
    echo "Armbian autopatcher: bare DTS + overlay copy, add-only DT Makefile patch"
    ${dtsCopy}
    ${overlayCopy}
    ${overlayDocStrip}
    ${makefileAutopatch}
  '';
})
