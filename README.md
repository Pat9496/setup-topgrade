# setup-topgrade

[![ShellCheck](https://github.com/Pat9496/setup-topgrade/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/Pat9496/setup-topgrade/actions/workflows/shellcheck.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE) [![Bash](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/) [![Linux](https://img.shields.io/badge/Linux-FCC624?style=flat&logo=linux&logoColor=black)](https://www.kernel.org/)

A single Bash script that installs and configures [topgrade](https://github.com/topgrade-rs/topgrade) — the tool that runs all of your system's update commands (apt/dnf/flatpak/cargo/firmware/etc.) in one go — on any Linux distro, including OSTree-based atomic/immutable systems like Bazzite and Fedora Silverblue/Kinoite/Atomic, and bootc-based atomic hosts.

[Deutsche Version](README.de.md)

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Usage](#usage)
- [How it works](#how-it-works)
- [Fedora Atomic / Kinoite installation methods](#fedora-atomic--kinoite-installation-methods)
- [Configuration](#configuration)
- [Credits](#credits)
- [License](#license)

## Features

- **Works across distros.** Uses each distro's actual documented topgrade install method where one exists (Fedora/RHEL via COPR on traditional hosts, Alpine via `apk`, Void via `xbps-install`, Homebrew/Linuxbrew), and falls back to downloading the prebuilt binary from GitHub Releases into `~/.local/bin` everywhere else.
- **Gives Fedora Atomic users an explicit choice.** On rpm-ostree hosts (Bazzite, Fedora Silverblue/Kinoite/Atomic), choose either COPR/rpm-ostree package integration or the official upstream binary. On bootc-only Atomic hosts, use the binary method.
- **Hardens both Atomic paths.** The COPR path restricts the added `lilay/topgrade` repo to `includepkgs=topgrade`; the GitHub release path selects the expected Linux asset from release metadata, verifies the GitHub-provided SHA-256 digest when present, smoke-tests `topgrade --version`, and atomically activates the new binary only after validation.
- **Idempotent.** Safe to re-run. Already installed? It skips straight to configuration and verification. Already configured? Your config is not regenerated unless you pass `--force-config`; small installer-policy repairs may be applied with a timestamped backup.
- **Ships a sensible default config**, with a few pieces (see [Configuration](#configuration)) only added when they're actually relevant to the machine it's running on.
- **Optional [chezmoi](https://www.chezmoi.io/) integration.** If chezmoi is installed and initialized, the generated config is automatically brought under chezmoi management.
- **No unattended surprises.** Meant to be run interactively by a human. It never reboots or overwrites an existing config without you being there to say so.

## Requirements

- Bash
- `curl` or `wget`
- `sudo`, if not already running as root and a privileged install step is needed
- `python3`, for safe GitHub release metadata parsing when installing the upstream release binary

## Usage

```bash
./install-topgrade.sh
```

Run it again any time — it detects what's already done and picks up where it left off.

On Fedora Atomic / Kinoite, choose an installation method explicitly:

```bash
./install-topgrade.sh --install-method=binary
./install-topgrade.sh --install-method=copr
```

Aliases are also available:

```bash
./install-topgrade.sh --binary
./install-topgrade.sh --copr
```

Interactive Atomic sessions prompt when no method is provided. Non-interactive Atomic sessions default to the binary method because it does not require root privileges, host package layering, or a reboot.

To install a specific upstream binary release, use:

```bash
./install-topgrade.sh --binary --version v17.9.0
```

or set `TOPGRADE_VERSION=v17.9.0`.

## How it works

topgrade is not packaged in Fedora, RHEL, or AlmaLinux's official repositories. On traditional Fedora/RHEL-family hosts, this script can install topgrade from [lilay's `lilay/topgrade` COPR](https://copr.fedorainfracloud.org/coprs/lilay/topgrade/) via `dnf`. On Fedora Atomic hosts, the script supports both the COPR/rpm-ostree package-managed model and the official upstream binary model.

The script picks its install strategy based on what it detects:

| System | Strategy |
|---|---|
| Bazzite, Fedora Silverblue/Kinoite/Atomic (rpm-ostree present) | Prompt or explicit `--install-method`: COPR/rpm-ostree package integration or upstream binary in `~/.local/bin/topgrade` |
| Atomic host without `rpm-ostree` (bootc-only) | Downloads the official upstream GitHub release binary into `~/.local/bin/topgrade` |
| Fedora / RHEL / AlmaLinux (non-atomic) | Enables the `lilay/topgrade` COPR, installs with `dnf install` |
| Alpine | `apk add topgrade` |
| Void Linux | `xbps-install -Sy topgrade` |
| Homebrew / Linuxbrew present | `brew install topgrade` |
| Anything else (Debian, Ubuntu, Arch, openSUSE, or if a native path above fails) | Downloads the latest release binary from GitHub into `~/.local/bin/topgrade` |

Privileged steps run under `sudo` unless the script is already running as root, in which case `sudo` is skipped entirely — no `sudo` binary is required on systems where you're already root.

## Fedora Atomic / Kinoite installation methods

Fedora Atomic users can choose between two supported ownership models. Neither is inherently wrong; they make different tradeoffs.

| Topic | COPR / rpm-ostree | Upstream binary |
|---|---|---|
| Install location | Host deployment (`/usr/bin/topgrade`) | `~/.local/bin/topgrade` |
| Root required | Yes | No |
| Reboot required | Yes | No |
| Adds third-party RPM repo | Yes, the specific `lilay/topgrade` COPR | No |
| Repo scope | Restricted with `includepkgs=topgrade` where supported | N/A |
| Topgrade updates | rpm-ostree | Built-in self-update from `topgrade-rs/topgrade` |
| Host package layering | Yes | No |
| Package-manager integration | Excellent | None |
| Easy uninstall | `rpm-ostree uninstall topgrade` + reboot | remove `~/.local/bin/topgrade` |

The COPR method adds the specific `lilay/topgrade` repository to your system and installs Topgrade as a layered RPM through rpm-ostree. This does not enable arbitrary COPR repositories. The installer restricts that repository to the `topgrade` package with `includepkgs=topgrade`, but you still trust the maintainer of that COPR project to provide the Topgrade RPM and updates.

The binary method installs the official Topgrade release directly into `~/.local/bin` without adding an RPM repository or layering a package into the operating system. Topgrade then updates itself from the official `topgrade-rs/topgrade` upstream releases.

## Configuration

topgrade reads its config from `${XDG_CONFIG_HOME:-~/.config}/topgrade.toml`. If that file doesn't already exist, the script creates one. Existing configs are not regenerated unless you pass `--force-config`, but the script may make small policy repairs with a timestamped backup: for example, ensuring `rpm_ostree = true` on Atomic hosts or changing `no_self_update = true` to `false` when Topgrade is installed as the user-local upstream binary.

The generated config includes a few pieces conditionally, based on what's actually present on the machine:

| Config piece | Included when |
|---|---|
| `[include] paths = ["/etc/ublue-os/topgrade.toml"]` | `/etc/ublue-os/topgrade.toml` exists (ublue-os/Bazzite theme-update commands) — since `~/.config/topgrade.toml` is shared into `toolbx`/`distrobox` containers, this may log a harmless `Unable to read /etc/ublue-os/topgrade.toml` error there; the script prints a heads-up about this when it adds the line |
| `[linux] rpm_ostree = true` | Running on an atomic host where `rpm-ostree` is available (takes precedence over `bootc`) |
| `[linux] bootc = true` | Running on an atomic host where `rpm-ostree` is not available, but `bootc` is (a bootc-only host without another supported package manager) |
| `[misc] no_self_update = true` | topgrade was actually installed via a package manager (`dnf`, COPR/rpm-ostree, `apk`, `xbps-install`, or Homebrew). Atomic binary installs leave self-update enabled |
| `"chezmoi"` in `disable`, `[misc] last = ["custom_commands"]`, plus a `"Chezmoi Push"` custom command | chezmoi is installed and initialized |
| `"ScummVM Nightly"` custom command | `scummvm-nightly-update` is on `$PATH` |
| `[containers] runtime = "podman"` | `podman` is on `$PATH` and `docker` is not |
| `"waydroid"` in `disable` | added unless waydroid is both installed **and** initialized (`waydroid status` reports a `Session:` line) |

> **Why waydroid is disabled by default:** if waydroid is installed but never initialized (`waydroid init` was never run), `waydroid status` doesn't print a `Session:` line, and topgrade crashes outright when it parses that — an upstream bug ([topgrade-rs/topgrade#869](https://github.com/topgrade-rs/topgrade/issues/869)). To avoid that crash, the script disables the `waydroid` step unless it can confirm waydroid is actually initialized.
>
> To let topgrade manage waydroid, run `waydroid init`, then re-run `./install-topgrade.sh --force-config` to regenerate the config — the script will detect the initialized session and leave `waydroid` enabled. (You can also just delete `"waydroid"` from `disable = [...]` in `topgrade.toml` by hand.)

### chezmoi integration

If [chezmoi](https://www.chezmoi.io/) is installed and initialized (i.e. `chezmoi init` has already been run), the script runs `chezmoi add` on the topgrade config after ensuring it exists — bringing it under chezmoi's management if it isn't already.

The script also disables topgrade's built-in `chezmoi` step (by adding `"chezmoi"` to `disable`) and replaces it with its own `"Chezmoi Push"` command in `[commands]`. This serves two purposes:

1. **Direction/safety:** topgrade's built-in `chezmoi` step runs `chezmoi update` — a pure pull-and-apply operation that automatically and unattended applies changes from the chezmoi remote to the local system. That conflicts with this script's design principle of no unattended surprises. Instead, the script's own command only ensures local changes (particularly the newly generated or adjusted `topgrade.toml`) are saved and pushed to the remote — a write operation, where there's no risk of unwanted changes landing on the local system.
2. **Order/completeness:** the custom `"Chezmoi Push"` command is guaranteed to run after all other topgrade steps, via `[misc] last = ["custom_commands"]`. This ensures any local changes made during that topgrade run are captured in a single commit. topgrade's built-in `chezmoi` step has no controllable position relative to other steps, so it's replaced by the custom command rather than run alongside it (which could cause conflicts between pull and push in the same run).

The script itself only stages the config file into chezmoi's source directory; it never commits or pushes on its own — that happens later, when topgrade runs the `"Chezmoi Push"` command.

## Credits

- [topgrade](https://github.com/topgrade-rs/topgrade) — the tool this script installs and configures.
- [lilay's Fedora/RHEL COPR](https://copr.fedorainfracloud.org/coprs/lilay/topgrade/) — the package source used on traditional Fedora/RHEL-family hosts and optional COPR/rpm-ostree Atomic installs.
- [Universal Blue / ublue-os](https://universal-blue.org/) — the theme-update custom commands pulled in via `[include]` on Bazzite and other ublue-os images.
- [chezmoi](https://www.chezmoi.io/) — the dotfiles manager this script can optionally hand the generated config off to.

## License

[MIT](LICENSE)
