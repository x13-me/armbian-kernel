# armbian-kernel

A Nix flake that builds Armbian's kernels **from source** — Armbian's upstream tree
plus its patch series, compiled with `pkgs.buildLinux`. Unlike a `.deb` repack, this
yields a real kernel `dev` output, so `boot.kernelPackages` and out-of-tree modules work.

## Targets

Three branches, all `aarch64-linux`. Kernel version, source rev, patch series, and
`.config` are pinned in `kernels.json` (a given flake rev builds a fixed kernel):

| Target | Family | Branch | Kernel | Source |
|--------|--------|--------|--------|--------|
| `rockchip64-current` | rockchip64 | current | 6.18 | kernel.org tarball |
| `rockchip64-edge` | rockchip64 | edge | 7.1 | kernel.org tarball |
| `rk35xx-vendor` | rk35xx | vendor | 6.1 | Armbian `linux-rockchip` (git) |

### Config overrides

Each target's pinned `.config` is expanded with `make olddefconfig` at build time. A target
may also set `disableConfigs` in `kernels.json` — Kconfig symbols force-disabled *after*
expansion (`scripts/config --disable`, then a second `olddefconfig`). `rk35xx-vendor` uses
this to drop `MALI_CSF_INCLUDE_FW`: Armbian's vendor Mali driver `.incbin`s a CSF firmware
blob that isn't in the source tree, so compiling it in fails the build — disabling it makes
the driver load `/lib/firmware/mali_csffw.bin` at runtime instead.

## Flake outputs

```
├───linuxPackages.<system>.<target>   full kernel package set → boot.kernelPackages
├───packages.<system>.<target>        bare kernel derivation (nix build / CI)
├───nixosModules.default              slim-kernel NixOS integration (see Quick Start)
├───checks.<system>.<target>          structure assertion (image + modules + dev tree)
└───devShells.<system>.default        update tooling
```

## Quick Start

### Using with Flakes

Add this flake as an input to your `flake.nix`:

```nix
{
  inputs = {
    armbian-kernel = {
      url = "github:x13-me/armbian-kernel";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
```

Then, in a host that boots one of these kernels, select the kernel **and** import the
integration module:

```nix
{
  imports = [ inputs.armbian-kernel.nixosModules.default ];

  boot.kernelPackages =
    inputs.armbian-kernel.linuxPackages.aarch64-linux.rockchip64-current;
}
```

`nixosModules.default` is required for a bootable system. Armbian's `.config` is slim and
doesn't build NixOS's generic initrd module sets — `hardware.enableAllHardware`'s
`3w-9xxx…` and `boot.initrd.includeDefaultModules`' `ata_piix…`. Without the module,
`modules-closure` hits `modprobe: FATAL: Module … not found` and the toplevel won't build.
The module:

- turns off `hardware.enableAllHardware` (skip the installer-CD hardware zoo), and
- sets `boot.initrd.allowMissingModules = true` — the NixOS-native escape hatch for
  "kernels that don't provide as many modules as typical NixOS kernels", so the closure
  keeps every module that *is* built and skips the rest instead of failing.

It's kernel-agnostic — the same module works for every target; the kernel choice stays
explicit in `boot.kernelPackages`.

### Build directly

```sh
nix build github:x13-me/armbian-kernel#packages.aarch64-linux.rockchip64-current
```

## Out-of-tree modules

The reason for from-source over a repack: Armbian ships trimmed headers (no `modpost`),
so a repacked kernel can't build OOT modules. `buildLinux` produces a full `dev` tree, so
`linuxPackages.<target>.<module>` builds normally:

```sh
nix build .#linuxPackages.aarch64-linux.rockchip64-current.v4l2loopback
```

## Development

```sh
nix build .#packages.aarch64-linux.rockchip64-current   # build a kernel
nix flake check                                          # structure assertions
nix develop                                              # update tooling shell
```

Kernel compiles run on the target arch; on an `x86_64` host, aarch64 builds offload to a
remote aarch64 builder or qemu binfmt.

## CI

`dispatch.yml` — on push, dispatches to `x13-me/flake-build-action`, which builds the
flake and pushes closures to `cache.x13.me` (source builds are slow, so caching matters).
Repo config: var `BUILD_REPO=x13-me/flake-build-action`; secret `DISPATCH_PAT`.
