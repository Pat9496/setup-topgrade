#!/usr/bin/env bash
set -euo pipefail

readonly COPR_REPO="lilay/topgrade"
readonly GITHUB_REPO="topgrade-rs/topgrade"

log() {
    printf '[install-topgrade] %s\n' "$*"
}

log_error() {
    printf '[install-topgrade] ERROR: %s\n' "$*" >&2
}

on_error() {
    local line="$1" cmd="$2"
    log_error "Failed at line ${line}: ${cmd}"
}

trap 'on_error "$LINENO" "$BASH_COMMAND"' ERR

topgrade_present() {
    if command -v topgrade >/dev/null 2>&1; then
        return 0
    fi
    if command -v rpm >/dev/null 2>&1 && rpm -q topgrade >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

is_atomic_host() {
    [[ -f /run/ostree-booted ]] && command -v rpm-ostree >/dev/null 2>&1
}

chezmoi_available() {
    local source_path
    command -v chezmoi >/dev/null 2>&1 || return 1
    source_path=$(chezmoi source-path 2>/dev/null) || return 1
    [[ -n "$source_path" && -d "$source_path" ]]
}

run_privileged() {
    if [[ "$(id -u)" -eq 0 ]]; then
        log "Running as root; skipping sudo"
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        log_error "This step needs root privileges, but sudo is not installed and the script is not running as root. Re-run as root or install sudo."
        return 1
    fi
}

fetch_url() {
    local url="$1"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- "$url"
    else
        log_error "Neither curl nor wget is available to reach ${url}"
        return 1
    fi
}

download_file() {
    local url="$1" dest="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$dest" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$dest" "$url"
    else
        log_error "Neither curl nor wget is available to download ${url}"
        return 1
    fi
}

fetch_latest_tag() {
    local api_url="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
    local response
    response=$(fetch_url "$api_url") || return 1
    printf '%s\n' "$response" | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/'
}

configure_topgrade() {
    log "==> Ensuring topgrade configuration exists"
    local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
    local config_file="${config_dir}/topgrade.toml"

    mkdir -p "$config_dir"

    if [[ -f "$config_file" ]]; then
        log "Existing config found at ${config_file}; leaving it untouched"
    else
        local include_paths_line=""
        if [[ -f /etc/ublue-os/topgrade.toml ]]; then
            log "ublue-os include: detected /etc/ublue-os/topgrade.toml, including it"
            include_paths_line='paths = ["/etc/ublue-os/topgrade.toml"]'
        else
            log "ublue-os include: not detected, skipping"
        fi

        local linux_rpm_ostree_line=""
        if is_atomic_host; then
            log "rpm_ostree: atomic host detected, enabling rpm_ostree = true"
            linux_rpm_ostree_line="rpm_ostree = true"
        else
            log "rpm_ostree: not an atomic host, skipping"
        fi

        local disable_line='disable = ["waydroid"]'
        local chezmoi_push_line=""
        if chezmoi_available; then
            log "chezmoi: available, including Chezmoi Push command"
            disable_line='disable = ["waydroid","chezmoi"]'
            chezmoi_push_line="\"Chezmoi Push\" = '''chezmoi re-add && chezmoi git -- add -A && (chezmoi git -- diff --cached --quiet || chezmoi git -- commit -m \"\$(date '+%Y-%m-%d %H:%M:%S')\") && chezmoi git -- push'''"
        else
            log "chezmoi: not available, skipping"
        fi

        local scummvm_line=""
        if command -v scummvm-nightly-update >/dev/null 2>&1; then
            log "scummvm: scummvm-nightly-update found, including ScummVM Nightly command"
            scummvm_line='"ScummVM Nightly" = "scummvm-nightly-update"'
        else
            log "scummvm: scummvm-nightly-update not found, skipping"
        fi

        local podman_runtime_line=""
        if command -v podman >/dev/null 2>&1 && ! command -v docker >/dev/null 2>&1; then
            log "podman runtime: podman found and docker absent, setting runtime = podman"
            podman_runtime_line='runtime = "podman"'
        else
            log "podman runtime: skipping (docker present, or podman not found)"
        fi

        local no_self_update_line=""
        if is_atomic_host; then
            log "no_self_update: atomic host detected, enabling no_self_update = true"
            no_self_update_line="no_self_update = true"
        else
            log "no_self_update: not an atomic host, skipping"
        fi

        local chezmoi_last_line=""
        if chezmoi_available; then
            log "chezmoi last: available, ensuring Chezmoi Push runs last"
            chezmoi_last_line='last = ["Chezmoi Push"]'
        else
            log "chezmoi last: not available, skipping"
        fi

        local lines=()
        lines+=("[include]")
        [[ -n "$include_paths_line" ]] && lines+=("$include_paths_line")
        lines+=("")
        lines+=("[misc]")
        lines+=("$disable_line")
        [[ -n "$chezmoi_last_line" ]] && lines+=("$chezmoi_last_line")
        lines+=("pre_sudo = false")
        lines+=("assume_yes = true")
        lines+=("ask_retry = false")
        lines+=("cleanup = true")
        lines+=('notify_end = "on_failure"')
        [[ -n "$no_self_update_line" ]] && lines+=("$no_self_update_line")
        lines+=('ignore_failures = ["powershell","toolbx","distrobox"]')
        lines+=("show_skipped = false")
        lines+=("")
        lines+=("[pre_commands]")
        lines+=("")
        lines+=("[post_commands]")
        lines+=("")
        lines+=("[commands]")
        [[ -n "$chezmoi_push_line" ]] && lines+=("$chezmoi_push_line")
        [[ -n "$scummvm_line" ]] && lines+=("$scummvm_line")
        lines+=("")
        lines+=("[python]")
        lines+=("enable_pip_review = false")
        lines+=("enable_pip_review_local = false")
        lines+=("enable_pipupgrade = false")
        lines+=("")
        lines+=("[conda]")
        lines+=("")
        lines+=("[composer]")
        lines+=("self_update = true")
        lines+=("")
        lines+=("[brew]")
        lines+=("")
        lines+=("[linux]")
        lines+=("show_arch_news = false")
        lines+=("redhat_distro_sync = false")
        lines+=("suse_dup = false")
        [[ -n "$linux_rpm_ostree_line" ]] && lines+=("$linux_rpm_ostree_line")
        lines+=("")
        lines+=("[mandb]")
        lines+=("enable = false")
        lines+=("")
        lines+=("[pkgfile]")
        lines+=("enable = false")
        lines+=("")
        lines+=("[git]")
        lines+=("max_concurrency = 5")
        lines+=("pull_predefined = false")
        lines+=("fetch_only = true")
        lines+=("")
        lines+=("[windows]")
        lines+=("")
        lines+=("[mise]")
        lines+=("bump = false")
        lines+=("jobs = 4")
        lines+=("interactive = false")
        lines+=("")
        lines+=("[go]")
        lines+=("")
        lines+=("[npm]")
        lines+=("")
        lines+=("[yarn]")
        lines+=("")
        lines+=("[deno]")
        lines+=("")
        lines+=("[viteplus]")
        lines+=("")
        lines+=("[vim]")
        lines+=("")
        lines+=("[firmware]")
        lines+=("upgrade = true")
        lines+=("")
        lines+=("[vagrant]")
        lines+=("")
        lines+=("[flatpak]")
        lines+=("")
        lines+=("[distrobox]")
        lines+=("")
        lines+=("[containers]")
        [[ -n "$podman_runtime_line" ]] && lines+=("$podman_runtime_line")
        lines+=("system_prune = false")
        lines+=("use_sudo = false")
        lines+=("")
        lines+=("[lensfun]")
        lines+=("use_sudo = false")
        lines+=("")
        lines+=("[julia]")
        lines+=("startup_file = true")
        lines+=("")
        lines+=("[zigup]")
        lines+=("")
        lines+=("[vscode]")
        lines+=("")
        lines+=("[pixi]")
        lines+=("include_release_notes = false")
        lines+=("")
        lines+=("[doom]")
        lines+=("")
        lines+=("[cargo]")
        lines+=("git = true")
        lines+=("quiet = false")
        lines+=("")
        lines+=("[rustup]")

        printf '%s\n' "${lines[@]}" > "$config_file"
        log "Created default config at ${config_file}"
    fi

    if chezmoi_available; then
        if chezmoi add "$config_file"; then
            log "Added ${config_file} to chezmoi-managed dotfiles"
        else
            log_error "chezmoi add failed for ${config_file}; continuing without chezmoi integration"
        fi
    else
        log "chezmoi not available; skipping chezmoi integration"
    fi
}

install_via_copr_dnf() {
    log "Enabling COPR repo ${COPR_REPO} and installing topgrade via dnf"
    run_privileged dnf -y copr enable "$COPR_REPO" && run_privileged dnf -y install topgrade
}

install_via_copr_rpmostree() {
    # "dnf copr enable" only writes a .repo file under /etc/yum.repos.d, which
    # remains writable on ostree systems even though /usr is read-only. The
    # actual package layer must go through rpm-ostree, not dnf install.
    log "Enabling COPR repo ${COPR_REPO} and layering topgrade via rpm-ostree"
    run_privileged dnf -y copr enable "$COPR_REPO" && run_privileged rpm-ostree install -y topgrade
}

install_via_apk() {
    log "Installing topgrade via apk"
    run_privileged apk add topgrade
}

install_via_xbps() {
    log "Installing topgrade via xbps-install"
    run_privileged xbps-install -Sy topgrade
}

install_via_brew() {
    log "Installing topgrade via Homebrew"
    brew install topgrade
}

install_via_github_release() {
    log "==> Installing topgrade from GitHub releases"

    local kernel_arch arch
    kernel_arch=$(uname -m)
    case "$kernel_arch" in
        x86_64) arch="x86_64" ;;
        aarch64) arch="aarch64" ;;
        arm64) arch="aarch64" ;;
        *)
            log_error "Unsupported architecture: ${kernel_arch}"
            return 1
            ;;
    esac

    local tag
    tag=$(fetch_latest_tag) || { log_error "Failed to determine latest topgrade release tag"; return 1; }
    if [[ -z "$tag" ]]; then
        log_error "Could not parse latest release tag from GitHub API response"
        return 1
    fi

    local asset_url="https://github.com/${GITHUB_REPO}/releases/download/${tag}/topgrade-${tag}-${arch}-unknown-linux-gnu.tar.gz"

    local tmpdir
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' RETURN

    local archive="${tmpdir}/topgrade.tar.gz"
    log "Downloading ${asset_url}"
    download_file "$asset_url" "$archive" || { log_error "Failed to download topgrade release asset"; return 1; }

    tar -xzf "$archive" -C "$tmpdir"

    local bin_path
    bin_path=$(find "$tmpdir" -type f -name topgrade -print -quit)
    if [[ -z "$bin_path" ]]; then
        log_error "topgrade binary not found inside downloaded archive"
        return 1
    fi

    mkdir -p "${HOME}/.local/bin"
    install -m 0755 "$bin_path" "${HOME}/.local/bin/topgrade"
    log "Installed topgrade binary to ${HOME}/.local/bin/topgrade"
    log "Note: ensure \$HOME/.local/bin is on your PATH (e.g. in ~/.bashrc or ~/.profile) if it is not already."
}

install_traditional() {
    if command -v dnf >/dev/null 2>&1; then
        log "Detected dnf; using it to install topgrade"
        install_via_copr_dnf
    elif command -v apk >/dev/null 2>&1; then
        log "Detected apk; using it to install topgrade"
        install_via_apk
    elif command -v xbps-install >/dev/null 2>&1; then
        log "Detected xbps-install; using it to install topgrade"
        install_via_xbps
    elif command -v brew >/dev/null 2>&1; then
        log "Detected brew; using it to install topgrade"
        install_via_brew
    else
        log "No supported package manager detected (dnf, apk, xbps-install, brew)"
        return 1
    fi
}

offer_reboot() {
    if [[ ! -t 0 ]]; then
        log "Non-interactive session detected; reboot manually later and re-run this script when ready."
        return 0
    fi

    local answer
    read -r -p "[install-topgrade] Reboot now to activate topgrade? [y/N] " answer
    case "$answer" in
        [yY]|[yY][eE][sS])
            log "Rebooting now"
            systemctl reboot
            ;;
        *)
            log "Reboot deferred. Reboot manually later, then re-run this script to finish setup."
            ;;
    esac
}

verify_installation() {
    log "==> Verifying installation"

    local topgrade_bin
    if command -v topgrade >/dev/null 2>&1; then
        topgrade_bin="topgrade"
        log "Using topgrade found on PATH"
    elif [[ -x "${HOME}/.local/bin/topgrade" ]]; then
        topgrade_bin="${HOME}/.local/bin/topgrade"
        log "Using topgrade at ${HOME}/.local/bin/topgrade"
    else
        log_error "topgrade was not found after installation"
        return 1
    fi

    "$topgrade_bin" --version
    log "topgrade installation complete."
}

main() {
    log "==> Detecting environment"

    if topgrade_present; then
        log "topgrade is already installed; skipping installation"
        configure_topgrade
        verify_installation
        exit 0
    fi

    if is_atomic_host; then
        log "Detected OSTree-based atomic system (rpm-ostree)"
        configure_topgrade

        log "==> Installing topgrade"
        if install_via_copr_rpmostree; then
            log "topgrade has been staged via rpm-ostree and requires a reboot to become active."
            offer_reboot
            log "After rebooting, re-run this script to finish verification."
            exit 0
        fi

        log "COPR/rpm-ostree install path failed; falling back to GitHub release binary"
        install_via_github_release
    else
        log "Detected traditional (non-atomic) Linux system"
        log "==> Installing topgrade"
        if ! install_traditional; then
            log "No confirmed native package path succeeded; falling back to GitHub release binary"
            install_via_github_release
        fi
        configure_topgrade
    fi

    verify_installation
}

main "$@"
