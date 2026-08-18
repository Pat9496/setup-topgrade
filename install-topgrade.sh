#!/usr/bin/env bash
set -euo pipefail

readonly COPR_REPO="lilay/topgrade"
readonly GITHUB_REPO="topgrade-rs/topgrade"
FORCE_CONFIG=0
PACKAGE_MANAGED=0
TOPGRADE_VERSION="${TOPGRADE_VERSION:-}"
INSTALL_METHOD="${TOPGRADE_INSTALL_METHOD:-}"
ATOMIC_INSTALL_METHOD=""

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

topgrade_package_managed() {
    if command -v rpm >/dev/null 2>&1 && rpm -q topgrade >/dev/null 2>&1; then
        return 0
    fi
    if command -v apk >/dev/null 2>&1 && apk info -e topgrade >/dev/null 2>&1; then
        return 0
    fi
    if command -v xbps-query >/dev/null 2>&1 && xbps-query topgrade >/dev/null 2>&1; then
        return 0
    fi
    if command -v brew >/dev/null 2>&1 && brew list --formula topgrade >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

is_atomic_host() {
    [[ -f /run/ostree-booted ]] && { command -v rpm-ostree >/dev/null 2>&1 || bootc_available; }
}

bootc_available() {
    command -v bootc >/dev/null 2>&1
}

validate_install_method() {
    local method="$1"
    case "$method" in
        ""|binary|copr) return 0 ;;
        *)
            log_error "Invalid install method '${method}'. Use --install-method=binary or --install-method=copr."
            return 1
            ;;
    esac
}

choose_atomic_install_method() {
    ATOMIC_INSTALL_METHOD="$INSTALL_METHOD"
    if [[ -n "$ATOMIC_INSTALL_METHOD" ]]; then
        validate_install_method "$ATOMIC_INSTALL_METHOD" || return 1
        return 0
    fi

    if [[ ! -t 0 ]]; then
        log "Atomic install method: no method specified in a non-interactive session; defaulting to official upstream binary"
        ATOMIC_INSTALL_METHOD="binary"
        return 0
    fi

    cat >&2 <<'EOF'
[install-topgrade] Topgrade can be installed in two ways on Fedora Atomic:
[install-topgrade]
[install-topgrade] 1. COPR / rpm-ostree
[install-topgrade]    - Integrates Topgrade into the host package manager
[install-topgrade]    - Adds the specific lilay/topgrade COPR repository
[install-topgrade]    - Restricts that repository to the topgrade package where supported
[install-topgrade]    - Requires sudo and a reboot
[install-topgrade]    - Topgrade updates through rpm-ostree
[install-topgrade]
[install-topgrade] 2. Official upstream binary
[install-topgrade]    - Installs to ~/.local/bin/topgrade
[install-topgrade]    - Does not add a COPR repository or layer a package into the OS
[install-topgrade]    - Does not require sudo or a reboot
[install-topgrade]    - Topgrade updates itself from topgrade-rs/topgrade
EOF

    local answer
    while true; do
        read -r -p "[install-topgrade] Choose installation method [1=copr, 2=binary, default 2]: " answer
        case "$answer" in
            1|copr|COPR) ATOMIC_INSTALL_METHOD="copr"; return 0 ;;
            ""|2|binary|BINARY) ATOMIC_INSTALL_METHOD="binary"; return 0 ;;
            *) log_error "Please choose 1 for COPR/rpm-ostree or 2 for the upstream binary." ;;
        esac
    done
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

download_file() {
    local url="$1" dest="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fL --retry 3 --retry-delay 2 \
            -H "User-Agent: setup-topgrade" \
            -o "$dest" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$dest" --header="User-Agent: setup-topgrade" "$url"
    else
        log_error "Neither curl nor wget is available to download ${url}"
        return 1
    fi
}

fetch_release_metadata() {
    local tag="$1" dest="$2"
    local api_url
    if [[ -n "$tag" ]]; then
        api_url="https://api.github.com/repos/${GITHUB_REPO}/releases/tags/${tag}"
    else
        api_url="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
    fi

    if command -v curl >/dev/null 2>&1; then
        local http_status
        http_status=$(curl -sS -L \
            -H "User-Agent: setup-topgrade" \
            -H "Accept: application/vnd.github+json" \
            -w '%{http_code}' \
            -o "$dest" \
            "$api_url") || {
            log_error "GitHub release lookup failed: network/TLS error. No changes were made."
            return 1
        }
        if [[ "$http_status" != "200" ]]; then
            case "$http_status" in
                403) log_error "GitHub release lookup failed: HTTP 403 (possibly API rate-limited). Retry later or use --version vX.Y.Z." ;;
                404) log_error "GitHub release lookup failed: HTTP 404 for ${tag:-latest release}. Check --version value." ;;
                429) log_error "GitHub release lookup failed: HTTP 429 (rate limited). Retry later or use --version vX.Y.Z." ;;
                5*) log_error "GitHub release lookup failed: HTTP ${http_status} from GitHub. Retry later or use --version vX.Y.Z." ;;
                *) log_error "GitHub release lookup failed: HTTP ${http_status}. No changes were made." ;;
            esac
            return 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$dest" \
            --header="User-Agent: setup-topgrade" \
            --header="Accept: application/vnd.github+json" \
            "$api_url" || {
            log_error "GitHub release lookup failed. Retry later or use --version vX.Y.Z."
            return 1
        }
    else
        log_error "Neither curl nor wget is available to query GitHub releases"
        return 1
    fi
}

parse_release_asset() {
    local metadata_file="$1" target_triple="$2"
    if ! command -v python3 >/dev/null 2>&1; then
        log_error "python3 is required to parse GitHub release metadata safely"
        return 1
    fi
    python3 - "$metadata_file" "$target_triple" <<'PY'
import json, re, sys
path, target = sys.argv[1], sys.argv[2]
try:
    data = json.load(open(path, encoding="utf-8"))
except Exception as exc:
    raise SystemExit(f"JSON parse failure: {exc}")
tag = data.get("tag_name")
if not isinstance(tag, str) or not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?", tag):
    raise SystemExit("Release metadata does not contain a valid tag_name")
expected = f"topgrade-{tag}-{target}.tar.gz"
matches = [a for a in data.get("assets", []) if a.get("name") == expected]
if len(matches) != 1:
    names = ", ".join(a.get("name", "<unnamed>") for a in data.get("assets", []))
    raise SystemExit(f"Expected exactly one asset named {expected}, found {len(matches)}. Available assets: {names}")
asset = matches[0]
url = asset.get("browser_download_url")
digest = asset.get("digest") or ""
if not isinstance(url, str) or not url.startswith("https://github.com/"):
    raise SystemExit("Selected release asset is missing a valid GitHub download URL")
if digest and not re.fullmatch(r"sha256:[0-9a-fA-F]{64}", digest):
    raise SystemExit("Selected release asset has an invalid digest field")
print(tag)
print(expected)
print(url)
print(digest)
PY
}

verify_archive_digest() {
    local archive="$1" expected_digest="$2"
    [[ -n "$expected_digest" ]] || {
        log "Release asset digest: not present in GitHub metadata; continuing without digest verification"
        return 0
    }
    command -v sha256sum >/dev/null 2>&1 || {
        log_error "sha256sum is required because this release asset includes a SHA-256 digest"
        return 1
    }
    local expected actual
    expected="${expected_digest#sha256:}"
    actual=$(sha256sum "$archive" | awk '{print $1}')
    if [[ "$actual" != "$expected" ]]; then
        log_error "Downloaded Topgrade release but SHA-256 verification failed. Existing Topgrade binary was left untouched."
        return 1
    fi
    log "Release asset digest: verified"
}

assert_safe_tar_archive() {
    local archive="$1" listing="$2"
    tar -tzf "$archive" > "$listing"
    if grep -Eq '(^/|(^|/)\.\.(/|$))' "$listing"; then
        log_error "Release archive contains an unsafe absolute or parent-directory path"
        return 1
    fi
}

backup_config_once() {
    local config_file="$1"
    local backup_file="${config_file}.bak.$(date +%Y%m%d%H%M%S)"
    cp -p "$config_file" "$backup_file"
    printf '%s\n' "$backup_file"
}

ensure_section_key() {
    local config_file="$1" section="$2" key="$3" value="$4"
    if grep -Eq "^[[:space:]]*${key}[[:space:]]*=" "$config_file"; then
        if grep -Eq "^[[:space:]]*${key}[[:space:]]*=[[:space:]]*${value}([[:space:]]*(#.*)?)?$" "$config_file"; then
            return 0
        fi
        python3 - "$config_file" "$key" "$value" <<'PY'
import re, sys
path, key, value = sys.argv[1:4]
lines = open(path, encoding='utf-8').read().splitlines()
pat = re.compile(rf'^(\s*{re.escape(key)}\s*=).*$')
for i, line in enumerate(lines):
    if pat.match(line):
        lines[i] = f'{key} = {value}'
        break
open(path, 'w', encoding='utf-8').write('\n'.join(lines) + '\n')
PY
        return 0
    fi

    python3 - "$config_file" "$section" "$key" "$value" <<'PY'
import re, sys
path, section, key, value = sys.argv[1:5]
lines = open(path, encoding='utf-8').read().splitlines()
header = f'[{section}]'
for i, line in enumerate(lines):
    if line.strip() == header:
        j = i + 1
        while j < len(lines) and not re.match(r'^\s*\[.*\]\s*$', lines[j]):
            j += 1
        lines.insert(j, f'{key} = {value}')
        break
else:
    if lines and lines[-1].strip():
        lines.append('')
    lines.extend([header, f'{key} = {value}'])
open(path, 'w', encoding='utf-8').write('\n'.join(lines) + '\n')
PY
}

repair_existing_config() {
    local config_file="$1"
    local changed=0 backup_file=""

    if ! command -v python3 >/dev/null 2>&1; then
        log "Existing config found at ${config_file}; python3 unavailable, leaving it untouched"
        return 0
    fi

    if is_atomic_host; then
        if command -v rpm-ostree >/dev/null 2>&1 && ! grep -Eq '^[[:space:]]*rpm_ostree[[:space:]]*=[[:space:]]*true([[:space:]]*(#.*)?)?$' "$config_file"; then
            [[ -n "$backup_file" ]] || backup_file=$(backup_config_once "$config_file")
            ensure_section_key "$config_file" "linux" "rpm_ostree" "true"
            log "Updated existing config: ensured [linux] rpm_ostree = true"
            changed=1
        elif ! command -v rpm-ostree >/dev/null 2>&1 && bootc_available && ! grep -Eq '^[[:space:]]*bootc[[:space:]]*=[[:space:]]*true([[:space:]]*(#.*)?)?$' "$config_file"; then
            [[ -n "$backup_file" ]] || backup_file=$(backup_config_once "$config_file")
            ensure_section_key "$config_file" "linux" "bootc" "true"
            log "Updated existing config: ensured [linux] bootc = true"
            changed=1
        fi
    fi

    if [[ "$PACKAGE_MANAGED" -eq 1 ]]; then
        if ! grep -Eq '^[[:space:]]*no_self_update[[:space:]]*=[[:space:]]*true([[:space:]]*(#.*)?)?$' "$config_file"; then
            [[ -n "$backup_file" ]] || backup_file=$(backup_config_once "$config_file")
            ensure_section_key "$config_file" "misc" "no_self_update" "true"
            log "Updated existing config: package-managed install uses [misc] no_self_update = true"
            changed=1
        fi
    else
        if grep -Eq '^[[:space:]]*no_self_update[[:space:]]*=[[:space:]]*true([[:space:]]*(#.*)?)?$' "$config_file"; then
            [[ -n "$backup_file" ]] || backup_file=$(backup_config_once "$config_file")
            ensure_section_key "$config_file" "misc" "no_self_update" "false"
            log "Updated existing config: user-local GitHub release binary uses [misc] no_self_update = false"
            changed=1
        fi
    fi

    if [[ "$changed" -eq 1 ]]; then
        log "Existing config was minimally repaired; backup saved to ${backup_file}"
    else
        log "Existing config found at ${config_file}; no installer policy changes needed"
    fi
}

configure_topgrade() {
    log "==> Ensuring topgrade configuration exists"
    local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
    local config_file="${config_dir}/topgrade.toml"

    mkdir -p "$config_dir"

    if [[ -f "$config_file" && "$FORCE_CONFIG" -ne 1 ]]; then
        repair_existing_config "$config_file"
    else
        if [[ -f "$config_file" ]]; then
            local backup_file="${config_file}.bak.$(date +%Y%m%d%H%M%S)"
            cp -p "$config_file" "$backup_file"
            log "--force-config: existing config backed up to ${backup_file}, regenerating"
        fi

        local include_paths_line=""
        if [[ -f /etc/ublue-os/topgrade.toml ]]; then
            log "ublue-os include: detected /etc/ublue-os/topgrade.toml, including it"
            log "Note: nested topgrade runs inside plain toolbx/distrobox containers may log a harmless 'Unable to read /etc/ublue-os/topgrade.toml' error for this include"
            include_paths_line='paths = ["/etc/ublue-os/topgrade.toml"]'
        else
            log "ublue-os include: not detected, skipping"
        fi

        local linux_rpm_ostree_line=""
        local linux_bootc_line=""
        if is_atomic_host; then
            if command -v rpm-ostree >/dev/null 2>&1; then
                log "rpm_ostree: atomic host detected and rpm-ostree available, enabling rpm_ostree = true"
                linux_rpm_ostree_line="rpm_ostree = true"
            elif bootc_available; then
                log "bootc: atomic host detected, rpm-ostree not available, enabling bootc = true"
                linux_bootc_line="bootc = true"
            fi
        else
            log "rpm_ostree: not an atomic host, skipping"
            log "bootc: not an atomic host, skipping"
        fi

        local disable_items=()
        if ! command -v waydroid >/dev/null 2>&1; then
            log "waydroid: not installed, disabling it in generated config"
            disable_items+=("waydroid")
        elif waydroid status 2>/dev/null | grep -q "Session:"; then
            log "waydroid: installed and initialized, including it in updates (not disabling)"
        else
            log "waydroid: installed but not initialized (run 'waydroid init' first), disabling it in generated config to avoid a topgrade crash (topgrade-rs/topgrade#869); re-run with --force-config once initialized to re-enable it"
            disable_items+=("waydroid")
        fi

        local chezmoi_push_line=""
        if chezmoi_available; then
            log "chezmoi: available, including Chezmoi Push command"
            disable_items+=("chezmoi")
            chezmoi_push_line="\"Chezmoi Push\" = '''chezmoi re-add && chezmoi git -- add -A && (chezmoi git -- diff --cached --quiet || chezmoi git -- commit -m \"\$(date '+%Y-%m-%d %H:%M:%S')\") && chezmoi git -- push'''"
        else
            log "chezmoi: not available, skipping"
        fi

        local disable_line
        if [[ ${#disable_items[@]} -eq 0 ]]; then
            disable_line="disable = []"
        else
            local disable_joined
            disable_joined="$(printf '"%s",' "${disable_items[@]}")"
            disable_line="disable = [${disable_joined%,}]"
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
        if [[ "$PACKAGE_MANAGED" -eq 1 ]]; then
            log "no_self_update: topgrade is package-managed on this host, enabling no_self_update = true"
            no_self_update_line="no_self_update = true"
        else
            log "no_self_update: topgrade is not package-managed on this host (GitHub release binary), leaving self-update enabled"
        fi

        local chezmoi_last_line=""
        if chezmoi_available; then
            log "chezmoi last: available, ensuring custom commands (including Chezmoi Push) run last"
            chezmoi_last_line='last = ["custom_commands"]'
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
        [[ -n "$linux_bootc_line" ]] && lines+=("$linux_bootc_line")
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

fedora_release_version() {
    local version
    command -v rpm >/dev/null 2>&1 || return 1
    version=$(rpm --eval '%fedora' 2>/dev/null) || return 1
    [[ "$version" =~ ^[0-9]+$ ]] || return 1
    printf '%s\n' "$version"
}

restrict_copr_repo_to_topgrade() {
    local repo_file="$1"
    if grep -Eq '^[[:space:]]*includepkgs[[:space:]]*=' "$repo_file"; then
        sed -i -E 's/^[[:space:]]*includepkgs[[:space:]]*=.*/includepkgs=topgrade/' "$repo_file"
    else
        printf '
includepkgs=topgrade
' >> "$repo_file"
    fi
    log "COPR repository scope: restricted to includepkgs=topgrade"
}

install_via_copr_rpmostree() {
    # Atomic hosts must never depend on dnf: some rpm-ostree images (e.g.
    # Bazzite/uBlue variants) don't ship a dnf binary at all, and dnf's own
    # package install/removal semantics don't apply on ostree systems anyway.
    # "dnf copr enable" only ever wrote a .repo file under /etc/yum.repos.d,
    # so write that file directly and let rpm-ostree/libdnf pick it up.
    log "Enabling specific COPR repo ${COPR_REPO} and layering topgrade via rpm-ostree"

    local fedora_version
    fedora_version=$(fedora_release_version) || {
        log_error "Could not determine the underlying Fedora release version (rpm --eval '%fedora' failed)"
        return 1
    }

    local repo_filename="${COPR_REPO//\//-}-fedora-${fedora_version}.repo"
    local repo_url="https://copr.fedorainfracloud.org/coprs/${COPR_REPO}/repo/fedora-${fedora_version}/${repo_filename}"

    local tmpfile
    tmpfile=$(mktemp)

    log "Downloading COPR repo file from ${repo_url}"
    download_file "$repo_url" "$tmpfile" || {
        rm -f "$tmpfile"
        log_error "Failed to download COPR repo file for ${COPR_REPO} (fedora-${fedora_version})"
        return 1
    }
    restrict_copr_repo_to_topgrade "$tmpfile"

    run_privileged install -m 0644 "$tmpfile" "/etc/yum.repos.d/${repo_filename}" && run_privileged rpm-ostree install -y topgrade
    local install_status=$?
    rm -f "$tmpfile"
    return "$install_status"
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
    log "==> Installing topgrade from official GitHub releases (${GITHUB_REPO})"
    log "Installation scope: user"
    log "COPR: not used"
    log "rpm-ostree package layering: not used"

    local kernel_arch target_triple
    kernel_arch=$(uname -m)
    case "$kernel_arch" in
        x86_64) target_triple="x86_64-unknown-linux-gnu" ;;
        aarch64) target_triple="aarch64-unknown-linux-gnu" ;;
        arm64) target_triple="aarch64-unknown-linux-gnu" ;;
        *)
            log_error "Unsupported architecture: ${kernel_arch}"
            return 1
            ;;
    esac

    local requested_tag="${TOPGRADE_VERSION}"
    if [[ -n "$requested_tag" && ! "$requested_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$ ]]; then
        log_error "Invalid --version value '${requested_tag}'. Expected a tag like v17.9.0."
        return 1
    fi

    local tmpdir
    tmpdir=$(mktemp -d)

    local metadata="${tmpdir}/release.json"
    fetch_release_metadata "$requested_tag" "$metadata" || { rm -rf "$tmpdir"; return 1; }

    local parsed tag asset_name asset_url asset_digest
    parsed=$(parse_release_asset "$metadata" "$target_triple") || {
        rm -rf "$tmpdir"
        log_error "Could not select a matching Linux release asset for ${target_triple}"
        return 1
    }
    tag=$(printf '%s\n' "$parsed" | sed -n '1p')
    asset_name=$(printf '%s\n' "$parsed" | sed -n '2p')
    asset_url=$(printf '%s\n' "$parsed" | sed -n '3p')
    asset_digest=$(printf '%s\n' "$parsed" | sed -n '4p')

    local archive="${tmpdir}/${asset_name}"
    log "Selected release: ${tag}"
    log "Selected asset: ${asset_name}"
    log "Downloading ${asset_url}"
    download_file "$asset_url" "$archive" || { rm -rf "$tmpdir"; log_error "Failed to download topgrade release asset. No changes were made."; return 1; }
    verify_archive_digest "$archive" "$asset_digest" || { rm -rf "$tmpdir"; return 1; }

    local listing="${tmpdir}/archive.list"
    assert_safe_tar_archive "$archive" "$listing" || { rm -rf "$tmpdir"; return 1; }
    tar -xzf "$archive" -C "$tmpdir"

    local candidates=()
    while IFS= read -r candidate; do
        candidates+=("$candidate")
    done < <(find "$tmpdir" -type f -name topgrade -print)
    if [[ ${#candidates[@]} -ne 1 ]]; then
        rm -rf "$tmpdir"
        log_error "Expected exactly one topgrade binary inside downloaded archive, found ${#candidates[@]}"
        return 1
    fi
    local bin_path="${candidates[0]}"

    chmod 0755 "$bin_path"
    if ! "$bin_path" --version | grep -F "${tag#v}" >/dev/null 2>&1; then
        rm -rf "$tmpdir"
        log_error "Downloaded topgrade binary did not report expected version ${tag}. Existing binary was left untouched."
        return 1
    fi

    mkdir -p "${HOME}/.local/bin"
    local install_path="${HOME}/.local/bin/topgrade"
    local new_path="${HOME}/.local/bin/.topgrade.new.$$"
    local previous_path="${HOME}/.local/bin/topgrade.previous"
    install -m 0755 "$bin_path" "$new_path"
    if [[ -e "$install_path" ]]; then
        cp -p "$install_path" "$previous_path"
    fi
    mv -f "$new_path" "$install_path"
    log "Installed topgrade binary to ${install_path}"
    log "Self-update mode: Topgrade built-in"
    log "Note: ensure \$HOME/.local/bin is on your PATH (e.g. in ~/.bashrc or ~/.profile) if it is not already."
    rm -rf "$tmpdir"
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
        if [[ -x "${HOME}/.local/bin/topgrade" && "$(command -v topgrade)" != "${HOME}/.local/bin/topgrade" ]]; then
            log "Warning: ${HOME}/.local/bin/topgrade exists but PATH resolves topgrade to $(command -v topgrade). Check PATH ordering or remove older package-managed installs."
        fi
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

usage() {
    cat <<'EOF'
Usage: install-topgrade.sh [--force-config] [--install-method binary|copr] [--version vX.Y.Z]

  --force-config         Regenerate ~/.config/topgrade.toml even if one already exists
                         (the existing file is backed up first)
  --install-method MODE  On Fedora Atomic hosts, choose 'binary' or 'copr'
                         (also available as TOPGRADE_INSTALL_METHOD=binary|copr)
  --binary               Alias for --install-method=binary
  --copr                 Alias for --install-method=copr
  --version TAG          Install a specific topgrade release tag for binary installs,
                         for example v17.9.0 (also available as TOPGRADE_VERSION=v17.9.0)
EOF
}

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force-config)
                FORCE_CONFIG=1
                shift
                ;;
            --install-method)
                if [[ $# -lt 2 ]]; then
                    log_error "--install-method requires 'binary' or 'copr'"
                    usage >&2
                    exit 1
                fi
                INSTALL_METHOD="$2"
                validate_install_method "$INSTALL_METHOD" || exit 1
                shift 2
                ;;
            --install-method=*)
                INSTALL_METHOD="${1#*=}"
                validate_install_method "$INSTALL_METHOD" || exit 1
                shift
                ;;
            --binary)
                INSTALL_METHOD="binary"
                shift
                ;;
            --copr)
                INSTALL_METHOD="copr"
                shift
                ;;
            --version)
                if [[ $# -lt 2 ]]; then
                    log_error "--version requires a tag such as v17.9.0"
                    usage >&2
                    exit 1
                fi
                TOPGRADE_VERSION="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unrecognized argument: $1"
                usage >&2
                exit 1
                ;;
        esac
    done

    log "==> Detecting environment"

    if topgrade_present; then
        log "topgrade is already installed; skipping installation"
        if topgrade_package_managed; then
            PACKAGE_MANAGED=1
        fi
        configure_topgrade
        verify_installation
        exit 0
    fi

    if is_atomic_host; then
        log "Detected OSTree-based atomic system"
        choose_atomic_install_method || exit 1
        if command -v rpm >/dev/null 2>&1 && rpm -q topgrade >/dev/null 2>&1; then
            log "Warning: an RPM-managed topgrade package is present. This script will not remove it automatically; consider migrating explicitly if PATH precedence is ambiguous."
        fi

        case "$ATOMIC_INSTALL_METHOD" in
            copr)
                if ! command -v rpm-ostree >/dev/null 2>&1; then
                    log_error "--install-method=copr requires rpm-ostree on Atomic hosts. Use --install-method=binary on bootc-only systems."
                    exit 1
                fi
                log "Atomic install method: COPR / rpm-ostree"
                install_via_copr_rpmostree
                PACKAGE_MANAGED=1
                configure_topgrade
                log "topgrade has been staged via rpm-ostree and requires a reboot to become active."
                offer_reboot
                log "After rebooting, re-run this script to finish verification."
                exit 0
                ;;
            binary)
                log "Atomic install method: official upstream binary"
                install_via_github_release
                PACKAGE_MANAGED=0
                configure_topgrade
                ;;
        esac
    else
        log "Detected traditional (non-atomic) Linux system"
        log "==> Installing topgrade"
        if install_traditional; then
            PACKAGE_MANAGED=1
        else
            log "No confirmed native package path succeeded; falling back to GitHub release binary"
            install_via_github_release
        fi
        configure_topgrade
    fi

    verify_installation
}

main "$@"
