# AGENTS.md

Guidance for AI agents working in this repository.

## Overview

`jethub-init` is a set of GPIO/LED/peripheral init scripts for JetHub
**J80**, **J100**, **J200** and **J310** boards. The repository holds two parallel
**variants** of the same logic, one per top-level folder. They are independent
targets, not layers — a change usually belongs to *one* variant, and porting it
to the other is a deliberate, separate step.

## Layout

Each variant folder has the same shape:

```
<variant>/
  jethub-init                 # main entrypoint script
  jethub-initer.service       # systemd unit (oneshot, runs jethub-init at boot)
  j80/libjethubconfig.sh      # per-board init functions + ADDITIONALFUNC
  j100/libjethubconfig.sh
  j200/libjethubconfig.sh
  j310/libjethubconfig.sh
```

Each variant ships its own `jethub-initer.service` because both the interpreter
**and the install path** differ — armbian runs `/bin/bash /usr/lib/armbian/jethub-init`,
haos-ash runs `/bin/sh /usr/lib/jethome/jethub-init`. The armbian package also
ships the `basic.target.wants` symlink, so installing it enables the unit; on
HAOS enabling is the OS build's job (the HAOS tree carries its own copy of the
unit in its rootfs overlay).

| Folder       | Variant                         | Shell        |
|--------------|---------------------------------|--------------|
| `armbian`    | Armbian, libgpiod v2 only (package depends on `gpiod (>= 2)`) | bash |
| `haos-ash`   | Home Assistant OS, libgpiod v2 only | POSIX sh (ash) |

`jethub-init` defines three line helpers, then sources the installed board's
`libjethubconfig.sh` (armbian: from its own folder; haos-ash:
`/usr/lib/jethome/`) and `/etc/default/jethub` (local overrides), and runs the
functions listed in `ADDITIONALFUNC` (`configure_leds`, `reset_zigbee`,
`config_1wire`, `reset_uxm1`, ...). The helpers, same in both variants:

- `gset [gpioset options] <line=value>...` — set and exit, the pin keeps the
  level. Lines are DT `gpio-line-names`, or offsets with `-c <chip>`.
- `gpulse <name>` — 500 ms high pulse.
- `wait_line <name>` — wait up to 5 s for a line to appear (i2c expanders).

## Conventions

- Keep the two variants in sync **only when asked** — they intentionally
  diverge (shell dialect, install paths). State which variant(s) you changed.
- `armbian` is `#!/bin/bash`; `haos-ash` is POSIX `sh` — do not use
  bashisms (arrays, `[[ ]]`, `declare -A`) in `haos-ash`.
- These run early at boot as root and touch real hardware (`gpioset`, i2c).
  Be conservative: fail loud, never leave GPIOs half-configured.
- Address lines by name; use `gset -c <chip>` with offsets only for lines the
  DT does not name (currently the J80 LED and Z-Wave lines). A name only works if
  the board's DTB carries it — check the DTS before relying on a new one.
- Scripts are shellcheck-friendly; preserve existing `# shellcheck` directives.

## Checks

There is no build. Validate edits with shellcheck before committing:

```sh
shellcheck armbian/jethub-init armbian/j*/libjethubconfig.sh
# for haos-ash, lint as POSIX sh:
shellcheck -s sh haos-ash/jethub-init haos-ash/j*/libjethubconfig.sh
```

## Releases

`.github/workflows/release.yml` runs on a version tag (`vX.Y.Z`) and publishes
**version-named** assets (pin a build to an exact version via the tagged URL,
`.../releases/download/vX.Y.Z/<name>`):

- `jethub-init-j80_<ver>.deb` / `-j100` / `-j200` / `-j310` — one armbian package per
  board, built with `nfpm` (`secondlife/action-nfpm`) from the single template
  `.github/nfpm.yaml`. The workflow `sed`s `@BOARD@` per board, then nfpm fills
  `${VERSION}` (tag minus the `v`) into both the package and the file name. Each
  installs `jethub-init` + that board's `libjethubconfig.sh` into
  `/usr/lib/armbian/` and `jethub-initer.service` into `/lib/systemd/system/`
  (matching armbian's existing BSP layout) and enables the unit via a
  `basic.target.wants` symlink. The packages provide/conflict/replace the
  virtual `jethub-init` (mutually exclusive), take these files over from the
  Armbian BSP, which still ships the old sysfs versions (`Replaces:`
  `armbian-bsp-cli-jethub<board>` and one `-<branch>` variant per branch JetHub
  images are built with: current, edge, vendor and bleedingedge — dpkg needs
  real names, so add any branch you start building; unversioned, so dpkg also
  keeps our copies across BSP upgrades), and depend on `gpiod (>= 2)`:
  releases whose archive only has gpiod v1 (Ubuntu noble) need gpiod 2.x from
  the JetHome apt repo.
- `jethub-init-haos_<ver>.tar.gz` — the `haos-ash/` tree (including its
  `jethub-initer.service`). The HAOS buildroot package (`package/jethub-init`)
  fetches this repo by git and installs `haos-ash/jethub-init` plus the board's
  `libjethubconfig.sh` into `/usr/lib/jethome/`; pin it to a release tag, not a
  bare commit.

Board selection is by *which package you install* — no runtime detection, no
maintainer scripts. There is no per-commit release; cut one by pushing a tag.

Local deb build (one board):

```sh
sed 's/@BOARD@/j100/g' .github/nfpm.yaml > /tmp/n.yaml
VERSION=1.0.0 nfpm pkg --packager deb --target dist/jethub-init-j100_1.0.0.deb -f /tmp/n.yaml
```
