# setup-topgrade

[](https://github.com/Pat9496/setup-topgrade/actions/workflows/shellcheck.yml) [](LICENSE) [](https://www.gnu.org/software/bash/) [](https://www.kernel.org/)

Read this in [Deutsch](README.de.md).

A single Bash script that installs and configures [topgrade](https://github.com/topgrade-rs/topgrade) — the tool that runs all of your system's update commands (apt/dnf/flatpak/cargo/firmware/etc.) in one go — on any Linux distro, including OSTree-based atomic/immutable systems like Bazzite and Fedora Silverblue/Kinoite/Atomic, and bootc-based atomic hosts.

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Usage](#usage)
- [How it works](#how-it-works)
- [Configuration](#configuration)
- [Credits](#credits)
- [License](#license)

## Features

- **Works across distros.** Uses each distro's actual documented topgrade install method where one exists (Fedora/RHEL via COPR, Alpine via `apk`, Void via `xbps-install`, Homebrew/Linuxbrew), and falls back to downloading the prebuilt binary from GitHub Releases into `~/.local/bin` everywhere else.
- **Handles atomic/immutable systems correctly.** On rpm-ostree hosts (Bazzite, Fedora Silverblue/Kinoite/Atomic), it downloads the `lilay/topgrade` COPR repo file directly and layers the package with `rpm-ostree install` — no `dnf` binary required — and never reboots without asking first. On atomic hosts without `rpm-ostree` (bootc-only, or if the COPR/rpm-ostree layer fails), it falls back to the GitHub release binary instead.
- **Idempotent.** Safe to re-run. Already installed? It skips straight to configuration and verification. Already configured? Your config is never overwritten.
- **Ships a sensible default config**, with a few pieces (see [Configuration](#configuration)) only added when they're actually relevant to the machine it's running on.
- **Optional [chezmoi](https://www.chezmoi.io/) integration.** If chezmoi is installed and initialized, the generated config is automatically brought under chezmoi management.
- **No unattended surprises.** Meant to be run interactively by a human. It never reboots or overwrites an existing config without you being there to say so.

## Requirements

- Bash
- `curl` or `wget`
- `sudo`, if not already running as root and a privileged install step is needed

## Usage

```bash
./install-topgrade.sh
```

Run it again any time — it detects what's already done and picks up where it left off. This is expected on rpm-ostree atomic hosts: a fresh install there stages the package via `rpm-ostree`, which needs a reboot to become active, and the script won't reboot for you without asking. If you decline (or you're in a non-interactive shell, where it won't even ask), just reboot manually and re-run the script to finish. On bootc-only atomic hosts without `rpm-ostree`, topgrade is installed as the GitHub release binary instead, so no reboot is needed.

## How it works

topgrade is not packaged in Fedora, RHEL, or AlmaLinux's official repositories. On those distros (and on rpm-ostree/atomic hosts derived from them), this script installs topgrade from [lilay's `lilay/topgrade` COPR](https://copr.fedorainfracloud.org/coprs/lilay/topgrade/) — the documented way to get it via `dnf` or `rpm-ostree`.

The script picks its install strategy based on what it detects:

| System | Strategy |
|---|---|
| Bazzite, Fedora Silverblue/Kinoite/Atomic (rpm-ostree present) | Downloads the `lilay/topgrade` COPR repo file directly (no `dnf` needed) and layers the package with `rpm-ostree install`, prompts before rebooting |
| Atomic host without `rpm-ostree` (bootc-only), or if the COPR/rpm-ostree layer fails | Downloads the latest release binary from GitHub into `~/.local/bin/topgrade` |
| Fedora / RHEL / AlmaLinux (non-atomic) | Enables the `lilay/topgrade` COPR, installs with `dnf install` |
| Alpine | `apk add topgrade` |
| Void Linux | `xbps-install -Sy topgrade` |
| Homebrew / Linuxbrew present | `brew install topgrade` |
| Anything else (Debian, Ubuntu, Arch, openSUSE, or if a native path above fails) | Downloads the latest release binary from GitHub into `~/.local/bin/topgrade` |

Privileged steps run under `sudo` unless the script is already running as root, in which case `sudo` is skipped entirely — no `sudo` binary is required on systems where you're already root.

## Configuration

topgrade reads its config from `${XDG_CONFIG_HOME:-~/.config}/topgrade.toml`. If that file doesn't already exist, the script creates one. **It never touches or overwrites an existing config.**

The generated config includes a few pieces conditionally, based on what's actually present on the machine:

| Config piece | Included when |
|---|---|
| `[include] paths = ["/etc/ublue-os/topgrade.toml"]` | `/etc/ublue-os/topgrade.toml` exists (ublue-os/Bazzite theme-update commands) — since `~/.config/topgrade.toml` is shared into `toolbx`/`distrobox` containers, this may log a harmless `Unable to read /etc/ublue-os/topgrade.toml` error there; the script prints a heads-up about this when it adds the line |
| `[linux] rpm_ostree = true` | Running on an atomic host where `rpm-ostree` is available (takes precedence over `bootc`) |
| `[linux] bootc = true` | Running on an atomic host where `rpm-ostree` is not available, but `bootc` is (a bootc-only host without another supported package manager) |
| `[misc] no_self_update = true` | topgrade was actually installed via a package manager (COPR+`rpm-ostree install`, `dnf`, `apk`, `xbps-install`, or Homebrew) — not merely because the host is atomic. bootc-only hosts without `rpm-ostree` get the GitHub release binary instead and therefore do **not** get `no_self_update = true` |
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
- [lilay's Fedora/RHEL COPR](https://copr.fedorainfracloud.org/coprs/lilay/topgrade/) — the package source used on Fedora, RHEL, AlmaLinux, and rpm-ostree/atomic hosts.
- [Universal Blue / ublue-os](https://universal-blue.org/) — the theme-update custom commands pulled in via `[include]` on Bazzite and other ublue-os images.
- [chezmoi](https://www.chezmoi.io/) — the dotfiles manager this script can optionally hand the generated config off to.

## License

[MIT](LICENSE)
