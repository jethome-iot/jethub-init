# AGENTS.md

Guidance for AI agents working in this repository.

## Overview

`jethub-init` is a set of GPIO/LED/peripheral init scripts for JetHub
**J80**, **J100** and **J200** boards. The repository holds two parallel
**variants** of the same logic, one per top-level folder. They are independent
targets, not layers — a change usually belongs to *one* variant, and porting it
to the other is a deliberate, separate step.

## Layout

Each variant folder has the same shape:

```
<variant>/
  jethub-init                 # main entrypoint script
  jethub-initer.service       # systemd unit (oneshot, runs jethub-init at boot)
  j80/libjethubconfig.sh      # per-board config: LED map, GPIO chip, helpers
  j100/libjethubconfig.sh
  j200/libjethubconfig.sh
  README.md                   # one-line description of the variant
```

Each variant ships its own `jethub-initer.service` because both the interpreter
**and the install path** differ — armbian runs `/bin/bash /usr/lib/armbian/jethub-init`,
haos-ash runs `/bin/sh /usr/lib/jethome/jethub-init`. The service is only
*shipped*; enabling it is the OS build's job (armbian's `families/jethub.conf`
does `systemctl --no-reload enable jethub-initer.service` in the chroot).

| Folder       | Variant                         | Shell        |
|--------------|---------------------------------|--------------|
| `armbian`    | Legacy sysfs + libgpiod (v2); auto-selects backend by libgpiod major version | bash |
| `haos-ash`   | Home Assistant OS, gpiod v2 only | POSIX sh (ash) |

`jethub-init` sources `libjethubconfig.sh` from its own folder, picking the
board file at runtime. Board config files define `LEDS`, `GPIOCHIPNUMBER`,
`GPIO_ACTIVE_LOW` and helpers like `reset_zigbee` / `config_1wire`.

## Conventions

- Keep the two variants in sync **only when asked** — they intentionally
  diverge (backend support, shell dialect). State which variant(s) you changed.
- `armbian` is `#!/bin/bash`; `haos-ash` is POSIX `sh` — do not use
  bashisms (arrays, `[[ ]]`, `declare -A`) in `haos-ash`.
- These run early at boot as root and touch real hardware (`/sys/class/gpio`,
  `gpioset`, i2c). Be conservative: fail loud, never leave GPIOs half-configured.
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

- `jethub-init-j80_<ver>.deb` / `-j100` / `-j200` — one armbian package per
  board, built with `nfpm` (`secondlife/action-nfpm`) from the single template
  `.github/nfpm.yaml`. The workflow `sed`s `@BOARD@` per board, then nfpm fills
  `${VERSION}` (tag minus the `v`) into both the package and the file name. Each
  installs `jethub-init` + that board's `libjethubconfig.sh` into
  `/usr/lib/armbian/` and `jethub-initer.service` into `/lib/systemd/system/`
  (matching armbian's existing BSP layout), and they provide/conflict/replace
  the virtual `jethub-init` (mutually exclusive). The package does not enable the
  service — the armbian build does.
- `jethub-init-haos_<ver>.tar.gz` — the `haos-ash/` tree (including its
  `jethub-initer.service`), consumed by the buildroot OS build (which has no
  package manager).

Board selection is by *which package you install* — no runtime detection, no
maintainer scripts. There is no per-commit release; cut one by pushing a tag.

Local deb build (one board):

```sh
sed 's/@BOARD@/j100/g' .github/nfpm.yaml > /tmp/n.yaml
VERSION=1.0.0 nfpm pkg --packager deb --target dist/jethub-init-j100_1.0.0.deb -f /tmp/n.yaml
```
