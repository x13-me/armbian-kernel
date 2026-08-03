{
  description = "Armbian kernels built from source as NixOS kernelPackages, with full out-of-tree module support";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Armbian's build framework is the source of truth for every target's patch
    # series, kernel `.config`, and device-tree overlays. Pinned (flake=false)
    # so one content-addressed fetch supplies all of them for all targets.
    armbian-build = {
      url = "git+https://github.com/armbian/build.git?rev=fe6d222247096fd58dbcfaa235cc3a998d712886";
      flake = false;
    };
  };

  outputs =
    { nixpkgs, armbian-build, ... }:
    let
      inherit (nixpkgs) lib;

      # Host systems that get devShells + formatter.
      hostSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      kernels = builtins.fromJSON (builtins.readFile ./kernels.json);

      forSystems = systems: f: lib.genAttrs systems f;

      # Buildable entries for a system: target arch matches AND a real source is
      # pinned — either a kernel.org tarball (`kernelHash`) or a git branch
      # (`kernelGit`). Entries with neither are catalogue-only (enumerated from
      # armbian/build but not built/cached).
      entriesFor =
        system:
        lib.filterAttrs (
          _: e: e.arch == system && ((e.kernelHash or null) != null || e ? kernelGit)
        ) kernels;

      # Systems that own at least one buildable target.
      targetSystems = lib.unique (lib.mapAttrsToList (_: e: e.arch) kernels);

      allSystems = lib.unique (targetSystems ++ hostSystems);

      # A from-source kernel must be compiled on its target arch (unlike the old
      # repack, which only copied files). On an x86_64 host, aarch64 builds
      # offload to the remote aarch64 builder / qemu binfmt.
      packagesForSystem =
        system:
        lib.mapAttrs (
          _: entry:
          import ./linux-packages.nix {
            inherit lib entry;
            pkgs = nixpkgs.legacyPackages.${system};
            armbianBuild = armbian-build;
          }
        ) (entriesFor system);
    in
    {
      # Full kernel package sets — `boot.kernelPackages = …<family>-<branch>`.
      linuxPackages = forSystems targetSystems packagesForSystem;

      # Generic NixOS integration for a host running any of these slim kernels.
      # Import alongside your explicit kernel choice:
      #   boot.kernelPackages = armbian-kernel.linuxPackages.<system>.<family>-<branch>;
      #   imports = [ armbian-kernel.nixosModules.default ];
      # Armbian's slim config doesn't build NixOS's generic initrd module sets
      # (all-hardware's 3w-9xxx…, includeDefaultModules' ata_piix…), so we skip the
      # installer hardware zoo and tolerate the base-set modules the kernel legitimately
      # lacks (`modules-closure` would otherwise FATAL). Kernel-agnostic → one module.
      nixosModules.default =
        { lib, ... }:
        {
          hardware.enableAllHardware = lib.mkForce false;
          boot.initrd.allowMissingModules = true;
        };

      # The bare kernel derivation per target (for `nix build` / CI / checks).
      packages = forSystems allSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        (lib.optionalAttrs (lib.elem system targetSystems) (
          lib.mapAttrs (_: lp: lp.kernel) (packagesForSystem system)
        ))
        // {
          update-kernels = import ./packages/update-kernels.nix { inherit pkgs; };
        }
      );

      # Cheap structure assertion per target: a kernel image, a modules tree,
      # and the `dev` build tree — the thing that makes OOT modules buildable
      # and the entire reason this builds from source.
      checks = forSystems targetSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        lib.mapAttrs (
          key: lp:
          let
            k = lp.kernel;
          in
          pkgs.runCommand "check-${key}" { } ''
            shopt -s nullglob
            imgs=( ${k}/Image* ${k}/vmlinuz* ${k}/boot/Image* ${k}/boot/vmlinuz* )
            mods=( ${k.modules}/lib/modules/*/ )
            [ ''${#imgs[@]} -gt 0 ] || { echo "${key}: no kernel image"; exit 1; }
            [ ''${#mods[@]} -gt 0 ] || { echo "${key}: no /lib/modules/<ver>/"; exit 1; }
            [ -e "${k.dev}/lib/modules/${k.modDirVersion}/build/Makefile" ] \
              || { echo "${key}: no dev build tree (OOT modules would fail)"; exit 1; }
            touch "$out"
          ''
        ) (packagesForSystem system)
      );

      devShells = forSystems hostSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              nix-prefetch-git
              jq
              yq-go
              curl
              gh
              git
            ];
          };
        }
      );

      formatter = forSystems hostSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}
