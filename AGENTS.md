# AGENTS.md

Guidance for AI agents working in this repository.

## Overview

`jethub-init` is the GPIO/LED/peripheral init for JetHub **J80**, **J100**,
**J200** and **J310** boards: one POSIX `sh` script per board, the same for
Armbian and Home Assistant OS. A release packs the scripts two ways: a `.deb`
per board for Armbian and one tarball for HAOS.

## Layout

```
j80/jethub-init             # the board's whole init, one self-contained script
j100/jethub-init
j200/jethub-init
j310/jethub-init
jethub-initer.service       # Armbian's systemd unit (oneshot, runs jethub-init at boot)
.github/nfpm.yaml           # Armbian package template
```

On Armbian the package installs the script as `/usr/lib/armbian/jethub-init`
and ships `jethub-initer.service` with its `basic.target.wants` symlink, so
installing it enables the unit. HAOS installs the script as
`/usr/lib/jethome/jethub-init`; its unit lives in the HAOS tree's rootfs overlay
and enabling it is the OS build's job.

Each board's `jethub-init` stands alone: no code shared between boards, no
`ADDITIONALFUNC`, no local overrides (the old Armbian BSP read
`/etc/default/jethub`; these scripts ignore it). It runs the board's steps top
to bottom; a failed step is logged and the rest still run. Lines are set with
`gpioset --toggle 0 <line=value>...`: without `--toggle 0` the v2 gpioset keeps
running to hold the lines and would stall the boot; with it gpioset sets them
and exits, and the pin keeps the level. Lines are DT `gpio-line-names`, or
offsets with `-c <chip>`. Both systems use libgpiod v2 only.

## Conventions

- The scripts are POSIX `sh`: dash runs them on Armbian, busybox ash on HAOS.
  No bashisms (arrays, `[[ ]]`, `declare`, `local`).
- A path a script uses must be the same on both systems: J80 calls
  `/usr/sbin/jethub_set-eth_leds`, which the Armbian BSP and the HAOS overlay
  both install there.
- These run early at boot as root and touch real hardware (`gpioset`, i2c).
  Be conservative: fail loud, never leave GPIOs half-configured.
- Address lines by name; use `-c <chip>` with offsets only for lines the
  DT does not name (J80: the LED and the Zigbee BOOT line). A name only works if
  the board's DTB carries it — check the DTS before relying on a new one.
- Init drives each radio module's BOOT/MODE line to the application level. The
  module reads it only when its MCU starts, and that includes software resets
  (Z2M, ZHA and flasher probes reset an EZSP NCP when they connect): a leftover
  bootloader level sends it to the bootloader on the next such reset, and
  setting the line back does not bring it out. Only J310 also pulses RESET (all
  UXM slots at once, after MODE): the slots stay powered across a reboot, and
  the pulse restarts the whole module, the MG21 behind the CP2102N included, so
  it comes back to the application. The other boards do not reset. Polarity
  differs per board — see the comment next to each line.
- The unit waits only for `systemd-modules-load`, not for udev, so the GPIO
  chips it drives must exist by then: built into the kernel (J310 needs
  `CONFIG_AMLOGIC_I2C_MESON=y`) or loaded by the script itself (J200 runs
  `modprobe gpio-pca953x`: the shared meson64 kernels, Armbian and HAOS alike,
  build it as a module).
- Scripts are shellcheck-friendly; preserve existing `# shellcheck` directives.

## Checks

There is no build. Validate edits with shellcheck, as POSIX sh, before
committing:

```sh
shellcheck -s sh j*/jethub-init
```

## Releases

`.github/workflows/release.yml` runs on a version tag (`vX.Y.Z`) and publishes
**version-named** assets (pin a build to an exact version via the tagged URL,
`.../releases/download/vX.Y.Z/<name>`):

- `jethub-init-j80_<ver>.deb` / `-j100` / `-j200` / `-j310` — one Armbian package per
  board, built with `nfpm` (`secondlife/action-nfpm`) from the single template
  `.github/nfpm.yaml`. The workflow `sed`s `@BOARD@` per board, then nfpm fills
  `${VERSION}` (tag minus the `v`) into both the package and the file name. Each
  installs that board's `jethub-init` into `/usr/lib/armbian/` and
  `jethub-initer.service` into `/lib/systemd/system/`
  (matching armbian's existing BSP layout) and enables the unit via a
  `basic.target.wants` symlink. The packages provide/conflict/replace the
  virtual `jethub-init` (mutually exclusive), take these files over from the
  Armbian BSP, whose older versions ship the old sysfs ones (`Replaces:`
  `armbian-bsp-cli-jethub<board>` and one `-<branch>` variant per branch JetHub
  images are built with: current, edge, vendor and bleedingedge — dpkg needs
  real names, so add any branch you start building; unversioned, so dpkg also
  keeps our copies across BSP upgrades), and depend on `gpiod (>= 2)`:
  releases whose archive only has gpiod v1 (Ubuntu noble) need gpiod 2.x from
  the JetHome apt repo. The BSP's old `/usr/lib/armbian/libjethubconfig.sh` may
  stay behind; nothing reads it.
- `jethub-init-haos_<ver>.tar.gz` — the board folders under a
  `jethub-init-<ver>/` top directory. It is built reproducibly (sorted names,
  fixed owner and modes, commit time, `gzip -n`), so a rebuilt asset keeps the
  hash HAOS pins. The HAOS buildroot package (`package/jethub-init`) downloads
  it from the release and installs the board's `<board>/jethub-init` as
  `/usr/lib/jethome/jethub-init`; bump its version and `.hash` together.

In armbian-build the BSP no longer ships the init and depends on its board's
package instead (`EXTRA_BSPDEPS` in `config/sources/families/jethub.conf`), so
new images and BSP upgrades pull it in from the JetHome repo, which is added
early for that. A package has to be in repo.jethome.com, with gpiod 2 where the
release lacks it, before images are built or a BSP released with that dependency.

Board selection is by *which package you install* — no runtime detection, no
maintainer scripts. There is no per-commit release; cut one by pushing a tag.

Local deb build (one board):

```sh
sed 's/@BOARD@/j100/g' .github/nfpm.yaml > /tmp/n.yaml
VERSION=1.0.0 nfpm pkg --packager deb --target dist/jethub-init-j100_1.0.0.deb -f /tmp/n.yaml
```
