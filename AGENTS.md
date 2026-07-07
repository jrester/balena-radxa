# AGENTS.md

This file provides guidance to AI coding agents when working with code in this repository.

## What this repo is

A fork of `balena-os/balena-radxa` that builds balenaOS for the **Radxa ROCK 5T** (RK3588) using Yocto Scarthgap (5.0). The upstream repo supported other Radxa boards (Rock Pi 4B, CM3, Zero); this fork adds the ROCK 5T and migrates from Dunfell to Scarthgap.

The implementation plan lives at `/home/jw/projects/work/wemolo/playground/igors-balena-images/radxa-playground/docs/scarthgap-fork-plan.md`.

## Building

**Containerized build (Docker, recommended):**
```bash
./balena-yocto-scripts/build/balena-build.sh \
    -d rockchip-rk3588-rock-5t \
    -s ~/balena-build-shared \
    > ~/balena-build.log 2>&1
```

**Native build setup (then run bitbake manually):**
```bash
# Dry-run to create build/ without building
./balena-yocto-scripts/build/barys --remove-build --dry-run

# Activate the Yocto build environment
source layers/poky/oe-init-build-env

# Build the image
MACHINE=rockchip-rk3588-rock-5t bitbake balena-image
```

Build artifacts land in `build/tmp/deploy/images/rockchip-rk3588-rock-5t/`. The target artifact is `balena-image-rockchip-rk3588-rock-5t.balenaos-img`.

**Shared state and downloads** are configured in `build/conf/local.conf` to use `/yocto/shared-sstate` and `/yocto/shared-downloads`. Change these for a different build host.

**Recover from `do_rootfs` SIGABRT** (pseudo DB corruption — exit 134, no visible error):
```bash
rm -rf build/tmp/work/*/balena-image build/tmp/work/*/balena-image-flasher
```

## Layer architecture

All Yocto layers live under `layers/`. Most are git submodules pinned in `.gitmodules`:

| Layer | Source | Role |
|-------|--------|------|
| `meta-balena/meta-balena-scarthgap` | submodule (balena-os/meta-balena) | balena OS base (Scarthgap distro) |
| `meta-balena/meta-balena-common` | same submodule | common balena recipes |
| `meta-balena/meta-balena-rust` | same submodule | Rust toolchain for balena |
| `meta-rockchip` | submodule (radxa/meta-rockchip, `scarthgap-vendor`) | Rockchip BSP: machine configs, kernel, U-Boot |
| `meta-balena-rockpi` | **in-tree** (not a submodule) | board-specific balena overrides (this is where most Rock 5T work lives) |
| `meta-openembedded` | submodule | OE layers (oe, filesystems, networking, python, perl) |
| `poky` | submodule (balena fork, `scarthgap` branch) | Yocto base |

`meta-balena-rockpi` is the primary layer for board-specific customization. It sits at priority 1337 in `conf/layer.conf`, overriding both upstream BSP and balena defaults. Its `LAYERSERIES_COMPAT` is still set to `dunfell` — this needs updating to `scarthgap` when compatibility issues arise.

## Device type definition

Each supported board has a `.coffee` file in the repo root (e.g. `rockchip-rk3588-rock-5t.coffee`). `balena-yocto-scripts` reads these files to determine `MACHINE`, the image name, and deployment artifact. The `yocto.machine` field must match a machine config in `layers/meta-rockchip/conf/machine/`.

The corresponding `.json` files (`rockchip-rk3588-rock-5t.json`) are generated/committed artifacts — do not hand-edit them.

## Build configuration files

- `layers/meta-balena-rockpi/conf/templates/default/bblayers.conf.sample` — template for `build/conf/bblayers.conf`; lists all layers in build order. `barys` uses this to generate the actual conf.
- `layers/meta-balena-rockpi/conf/templates/default/local.conf.sample` — template for `build/conf/local.conf`. Contains the ROCK 5T / Scarthgap-specific additions (cargo user-agent spoof, `BB_SIGNATURE_HANDLER = "OEBasicHash"`, `BB_HASHSERVE = ""`).

## Kernel (ROCK 5T)

The ROCK 5T kernel is `armbian/linux-rockchip` branch `rk-6.1-rkr5.1` (6.1.115), pinned by
SRCREV in `layers/meta-rockchip/recipes-kernel/linux/linux-rockchip_6.1.bb`. This is the
tree the NixOS Rock 5B+/5T reference (`rock5b+-nixos/edge-os`) builds and runs on real
hardware with working GPU/NIC/WiFi + docker. The full kernel config is that reference's
`.config`, staged at `linux-rockchip_6.1/rk35xx_vendor_config` and installed as the
`KBUILD_DEFCONFIG` by the rock-5t bbappend (armbian has no `rk3588_linux_defconfig`).
`ROCKCHIP_KERNEL_IMAGES = "0"` for rock-5t so it builds a plain `Image` (not the rockchip
`<dtb>.img` make target). Small balena deltas layer on top: `docker.cfg` (container/
netfilter/NIC) and `overlay.cfg` (`OVERLAY_FS=y`).

**Driver notes (this kernel):**
- NIC: RTL8125B 2.5GbE (dual, PCIe) via `CONFIG_R8169=m`. Kept modular + `r8169-late-load`
  (blacklisted in initramfs, loaded by a systemd oneshot post-boot) so boot does not depend
  on link state.
- WiFi: RTL8852BE via the **in-tree** `rtw89` driver (`CONFIG_RTW89_8852BE=m`) — no
  out-of-tree recipe. CFG80211/MAC80211/WL_ROCKCHIP are built-in (per the NixOS config).
- The older radxa `rkr4.1` kernel needed a modular WiFi stack + `maxcpus=1` to dodge an
  early-boot vmalloc/Mali race. This kernel boots all cores with the stack built-in, so
  those crutches are gone. If a ~T+3s race reappears, re-add `maxcpus=1 udev.children_max=1`
  to the extlinux APPEND and make CFG80211/MAC80211 modular in `docker.cfg`.

**Kernel command-line args** (extlinux template in `recipes-bsp/u-boot/u-boot-rockchip.bbappend`),
following the NixOS reference:
```
coherent_pool=2M   irqchip.gicv3_pseudo_nmi=0   console=ttyS2,1500000n8
```
Do NOT add `swiotlb=force` — it breaks RK3588 NPU IOMMU mappings.

**balenaCloud device type:** The ROCK 5T is not an official balena device type. The `device-type.json` baked into the image uses slug `rockchip-rk3588-rock-5t`, but must be patched to `generic-aarch64` at flash time for balenaCloud registration to succeed (or baked in via a `do_deploy:append` override).

**No CI workflow yet:** `.github/workflows/` has workflows for the other boards (`radxa-cm3-io-rk3566.yml`, `rockpi-4b-rk3399.yml`, `radxa-zero-s905y2.yml`) but not for `rockchip-rk3588-rock-5t`. One will need to be added following the same pattern as the others.

**crates.io 403:** If Rust recipes (`healthdog`, `fatrw`) fail to fetch `.crate` files, crates.io is blocking the build host's IP. The `FETCHCMD_wget` spoof in `local.conf.sample` is the primary mitigation; alternatively, seed the sstate downloads from another machine.

## Commit format

Commits must follow this format (required for automated changelog):

```
<component>: Short description (max 72 chars)

Longer explanation of what and why.

Changelog-entry: User-facing description of the change
Signed-off-by: Name <email>
```

Every PR needs at least one commit with a `Changelog-entry` footer. When updating `meta-balena`, include `Updated meta-balena from X to Y` in the body so the changelog links to the diff.
