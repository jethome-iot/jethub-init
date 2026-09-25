# jethub-init
Init scripts for JetHub J80/J100/J200/J310 boards: one POSIX sh script per board
(`j80/`, `j100/`, `j200/`, `j310/`), shared by Armbian and Home Assistant OS
(libgpiod v2).

- Armbian: per-board `.deb` packages that install the script with `jethub-initer.service`
- HAOS: a tarball of the board scripts, installed by the HAOS `jethub-init` package
