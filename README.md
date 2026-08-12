# setup-topgrade

A single Bash script that installs and configures [topgrade](https://github.com/topgrade-rs/topgrade) — the tool that runs all of your system's update commands (apt/dnf/flatpak/cargo/firmware/etc.) in one go — on any Linux distro, including OSTree-based atomic/immutable systems like Bazzite and Fedora Silverblue/Kinoite/Atomic, and bootc-based atomic hosts.

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
| `[linux] bootc = true` | Running on an atomic host where `bootc` is available (takes precedence over `rpm_ostree`) |
| `[linux] rpm_ostree = true` | Running on an rpm-ostree atomic host without `bootc` available |
| `[misc] no_self_update = true` | topgrade is package-managed on this host (installed via COPR/rpm-ostree, `apk`, `xbps`, or Homebrew) rather than the GitHub release binary |
| `"chezmoi"` in `disable`, `[misc] last = ["custom_commands"]`, plus a `"Chezmoi Push"` custom command | chezmoi is installed and initialized |
| `"ScummVM Nightly"` custom command | `scummvm-nightly-update` is on `$PATH` |
| `[containers] runtime = "podman"` | `podman` is on `$PATH` and `docker` is not |
| `"waydroid"` in `disable` | added unless waydroid is both installed **and** initialized (`waydroid status` reports a `Session:` line) |

> **Why waydroid is disabled by default:** if waydroid is installed but never initialized (`waydroid init` was never run), `waydroid status` doesn't print a `Session:` line, and topgrade crashes outright when it parses that — an upstream bug ([topgrade-rs/topgrade#869](https://github.com/topgrade-rs/topgrade/issues/869)). To avoid that crash, the script disables the `waydroid` step unless it can confirm waydroid is actually initialized.
>
> To let topgrade manage waydroid, run `waydroid init`, then re-run `./install-topgrade.sh --force-config` to regenerate the config — the script will detect the initialized session and leave `waydroid` enabled. (You can also just delete `"waydroid"` from `disable = [...]` in `topgrade.toml` by hand.)

### chezmoi integration

If [chezmoi](https://www.chezmoi.io/) is installed and initialized (i.e. `chezmoi init` has already been run), the script runs `chezmoi add` on the topgrade config after ensuring it exists — bringing it under chezmoi's management if it isn't already. It only stages the file into chezmoi's source directory; it never commits or pushes on its own.

## Credits

- [topgrade](https://github.com/topgrade-rs/topgrade) — the tool this script installs and configures.
- [lilay's Fedora/RHEL COPR](https://copr.fedorainfracloud.org/coprs/lilay/topgrade/) — the package source used on Fedora, RHEL, AlmaLinux, and rpm-ostree/atomic hosts.
- [Universal Blue / ublue-os](https://universal-blue.org/) — the theme-update custom commands pulled in via `[include]` on Bazzite and other ublue-os images.
- [chezmoi](https://www.chezmoi.io/) — the dotfiles manager this script can optionally hand the generated config off to.

## License

[MIT](LICENSE)
