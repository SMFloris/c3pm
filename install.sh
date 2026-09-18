#!/bin/sh

set -eu
umask 022

REPOSITORY=https://github.com/SMFloris/c3pm
ASSET=c3pm-linux-x86_64
VERSION=${C3PM_VERSION:-latest}
INSTALL_DIR=${C3PM_INSTALL_DIR:-${HOME:-}/.local/bin}
NIX_MODE=${C3PM_NIX_MODE:-auto}
ASSUME_YES=${C3PM_YES:-0}
MODIFY_PATH=1
DRY_RUN=0
TEMP_DIR=
STAGED_BINARY=
NIX_BIN=

say() {
    printf '%s\n' "$*"
}

warn() {
    printf 'warning: %s\n' "$*" >&2
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

is_true() {
    case ${1:-} in
        1|true|TRUE|yes|YES|on|ON) return 0 ;;
        *) return 1 ;;
    esac
}

if is_true "${C3PM_NO_MODIFY_PATH:-0}"; then
    MODIFY_PATH=0
fi

usage() {
    cat <<'EOF'
Install c3pm and, when needed, a Nix backend.

Usage: sh install.sh [OPTIONS]

Options:
  --version VERSION       Release tag to install (default: latest)
  --prefix DIRECTORY     Install directory (default: ~/.local/bin)
  --nix MODE             auto, daemon, single-user, portable, or none
                         (default: auto)
  --yes                  Do not ask for confirmation
  --no-modify-path       Do not update ~/.profile
  --dry-run              Print the plan without changing the system
  -h, --help             Show this help

Environment equivalents:
  C3PM_VERSION, C3PM_INSTALL_DIR, C3PM_NIX_MODE,
  C3PM_YES, C3PM_NO_MODIFY_PATH
EOF
}

need_value() {
    [ "$#" -ge 2 ] || die "$1 requires a value"
    [ -n "$2" ] || die "$1 requires a non-empty value"
}

while [ "$#" -gt 0 ]; do
    case $1 in
        --version)
            need_value "$@"
            VERSION=$2
            shift 2
            ;;
        --prefix)
            need_value "$@"
            INSTALL_DIR=$2
            shift 2
            ;;
        --nix)
            need_value "$@"
            NIX_MODE=$2
            shift 2
            ;;
        --yes)
            ASSUME_YES=1
            shift
            ;;
        --no-modify-path)
            MODIFY_PATH=0
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            [ "$#" -eq 0 ] || die "unexpected argument: $1"
            ;;
        *)
            die "unknown option: $1 (try --help)"
            ;;
    esac
done

case $NIX_MODE in
    auto|daemon|single-user|portable|none) ;;
    *) die "invalid --nix mode '$NIX_MODE'; expected auto, daemon, single-user, portable, or none" ;;
esac

case $VERSION in
    latest) ;;
    *[!A-Za-z0-9._-]*|'') die "invalid release version: $VERSION" ;;
esac

[ -n "${HOME:-}" ] || die 'HOME is not set'
[ -n "$INSTALL_DIR" ] || die 'the install directory is empty'
case $INSTALL_DIR in
    /*) ;;
    *) die "the install directory must be an absolute path: $INSTALL_DIR" ;;
esac

SYSTEM_NAME=${C3PM_TEST_UNAME_S:-$(uname -s)}
MACHINE_NAME=${C3PM_TEST_UNAME_M:-$(uname -m)}
[ "$SYSTEM_NAME" = Linux ] || die "unsupported operating system '$SYSTEM_NAME'; c3pm currently publishes Linux x86_64 releases"
case $MACHINE_NAME in
    x86_64|amd64) ;;
    *) die "unsupported architecture '$MACHINE_NAME'; c3pm currently publishes Linux x86_64 releases" ;;
esac

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

can_run_as_root() {
    [ "$(id -u)" -eq 0 ] || command_exists sudo
}

as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif command_exists sudo; then
        sudo "$@"
    else
        die "administrator access is required to run: $*"
    fi
}

detect_package_manager() {
    for candidate in apt-get dnf yum pacman zypper apk; do
        if command_exists "$candidate"; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

ca_certificates_available() {
    for certificate_bundle in \
        "${SSL_CERT_FILE:-}" \
        "${NIX_SSL_CERT_FILE:-}" \
        /etc/ssl/certs/ca-certificates.crt \
        /etc/pki/tls/certs/ca-bundle.crt \
        /etc/ssl/cert.pem \
        /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem
    do
        if [ -n "$certificate_bundle" ] && [ -r "$certificate_bundle" ]; then
            return 0
        fi
    done
    return 1
}

bootstrap_needed=0
for required_command in git curl xz tar; do
    if ! command_exists "$required_command"; then
        bootstrap_needed=1
    fi
done
if ! ca_certificates_available; then
    bootstrap_needed=1
fi

PACKAGE_MANAGER=
if [ "$bootstrap_needed" -eq 1 ]; then
    PACKAGE_MANAGER=$(detect_package_manager) || die 'git, curl, xz, or tar is missing and no supported package manager was found'
fi

selinux_is_enforcing() {
    command_exists getenforce && [ "$(getenforce 2>/dev/null || true)" = Enforcing ]
}

daemon_is_supported() {
    [ -d /run/systemd/system ] && command_exists systemctl && can_run_as_root && ! selinux_is_enforcing
}

load_nix_environment() {
    if command_exists nix; then
        return 0
    fi
    if [ -r /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
        # shellcheck disable=SC1091
        . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
    elif [ -r "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
        # shellcheck disable=SC1091
        . "$HOME/.nix-profile/etc/profile.d/nix.sh"
    fi
}

find_nix() {
    load_nix_environment
    if command_exists nix; then
        NIX_BIN=$(command -v nix)
        return 0
    fi
    for candidate in /nix/var/nix/profiles/default/bin/nix "$HOME/.nix-profile/bin/nix"; do
        if [ -x "$candidate" ]; then
            NIX_BIN=$candidate
            PATH=$(dirname "$candidate"):$PATH
            export PATH
            return 0
        fi
    done
    return 1
}

SELECTED_NIX_MODE=$NIX_MODE
if find_nix; then
    if [ "$NIX_MODE" = auto ]; then
        SELECTED_NIX_MODE=existing
    fi
elif [ "$NIX_MODE" = auto ]; then
    if daemon_is_supported; then
        SELECTED_NIX_MODE=daemon
    elif [ "$(id -u)" -eq 0 ]; then
        SELECTED_NIX_MODE=portable
    else
        SELECTED_NIX_MODE=single-user
    fi
fi

case $SELECTED_NIX_MODE in
    daemon)
        daemon_is_supported || die 'daemon Nix requires systemd, root or sudo, and SELinux not enforcing; use --nix single-user or portable'
        ;;
    single-user)
        [ "$(id -u)" -ne 0 ] || die 'single-user Nix cannot be installed as root; use --nix daemon or portable'
        ;;
esac

if [ "$VERSION" = latest ]; then
    RELEASE_BASE=$REPOSITORY/releases/latest/download
else
    RELEASE_BASE=$REPOSITORY/releases/download/$VERSION
fi
RELEASE_BASE=${C3PM_RELEASE_BASE_URL:-$RELEASE_BASE}
NIX_INSTALL_URL=${C3PM_NIX_INSTALL_URL:-https://nixos.org/nix/install}

say 'c3pm installation plan:'
say "  release:       $VERSION"
say "  destination:   $INSTALL_DIR/c3pm"
say "  platform:      Linux x86_64"
say "  Nix backend:   $SELECTED_NIX_MODE"
if [ "$bootstrap_needed" -eq 1 ]; then
    say "  prerequisites: install with $PACKAGE_MANAGER"
else
    say '  prerequisites: already available'
fi
if [ "$MODIFY_PATH" -eq 1 ]; then
    say "  PATH profile:  $HOME/.profile"
else
    say '  PATH profile:  unchanged'
fi

if [ "$DRY_RUN" -eq 1 ]; then
    say 'Dry run complete; no changes were made.'
    exit 0
fi

if ! is_true "$ASSUME_YES"; then
    [ -r /dev/tty ] || die 'cannot prompt without a terminal; rerun with --yes'
    printf 'Continue? [y/N] ' >/dev/tty
    read -r answer </dev/tty || answer=
    case $answer in
        y|Y|yes|YES) ;;
        *) die 'installation cancelled' ;;
    esac
fi

cleanup() {
    if [ -n "$STAGED_BINARY" ] && [ -e "$STAGED_BINARY" ]; then
        if [ -w "$(dirname "$STAGED_BINARY")" ]; then
            rm -f "$STAGED_BINARY"
        elif can_run_as_root; then
            as_root rm -f "$STAGED_BINARY"
        fi
    fi
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
}
trap cleanup EXIT HUP INT TERM

install_prerequisites() {
    [ "$bootstrap_needed" -eq 1 ] || return 0
    say "Installing prerequisites with $PACKAGE_MANAGER..."
    case $PACKAGE_MANAGER in
        apt-get)
            as_root apt-get update
            as_root apt-get install --yes git curl ca-certificates xz-utils tar
            ;;
        dnf)
            as_root dnf install -y git curl ca-certificates xz tar
            ;;
        yum)
            as_root yum install -y git curl ca-certificates xz tar
            ;;
        pacman)
            as_root pacman -S --needed --noconfirm git curl ca-certificates xz tar
            ;;
        zypper)
            as_root zypper --non-interactive install git curl ca-certificates xz tar
            ;;
        apk)
            as_root apk add --no-cache git curl ca-certificates xz tar bash
            ;;
    esac
    for required_command in git curl xz tar; do
        command_exists "$required_command" || die "failed to install prerequisite: $required_command"
    done
}

download() {
    source_url=$1
    destination=$2
    curl --fail --location --retry 3 --proto '=https' --tlsv1.2 \
        --output "$destination" "$source_url"
}

install_prerequisites
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/c3pm-install.XXXXXX")

install_nix() {
    mode=$1
    installer=$TEMP_DIR/nix-install.sh
    say "Installing Nix ($mode)..."
    download "$NIX_INSTALL_URL" "$installer"
    chmod 0755 "$installer"

    if [ "$mode" = daemon ]; then
        nix_arguments=--daemon
    else
        nix_arguments=--no-daemon
    fi

    if is_true "$ASSUME_YES"; then
        NIX_INSTALLER_YES=1 sh "$installer" "$nix_arguments"
    elif [ -r /dev/tty ]; then
        sh "$installer" "$nix_arguments" </dev/tty
    else
        sh "$installer" "$nix_arguments"
    fi

    NIX_BIN=
    find_nix || die 'Nix installation completed, but the nix executable could not be found'
    "$NIX_BIN" --version >/dev/null 2>&1 || die 'the installed Nix executable did not run successfully'
}

case $SELECTED_NIX_MODE in
    daemon|single-user)
        install_nix "$SELECTED_NIX_MODE"
        ;;
    existing)
        "$NIX_BIN" --version >/dev/null 2>&1 || die "the existing Nix executable failed: $NIX_BIN"
        ;;
esac

enable_flakes_if_needed() {
    [ -n "$NIX_BIN" ] || return 0
    if "$NIX_BIN" flake --help >/dev/null 2>&1; then
        return 0
    fi

    nix_config_dir=${XDG_CONFIG_HOME:-$HOME/.config}/nix
    nix_config=$nix_config_dir/nix.conf
    mkdir -p "$nix_config_dir"
    if [ ! -f "$nix_config" ] || ! grep -F 'extra-experimental-features = nix-command flakes' "$nix_config" >/dev/null 2>&1; then
        {
            printf '\n# Added by the c3pm installer\n'
            printf 'extra-experimental-features = nix-command flakes\n'
        } >>"$nix_config"
    fi
    "$NIX_BIN" flake --help >/dev/null 2>&1 || die 'Nix is installed, but nix-command and flakes could not be enabled'
}

case $SELECTED_NIX_MODE in
    existing|daemon|single-user) enable_flakes_if_needed ;;
esac

download "$RELEASE_BASE/$ASSET" "$TEMP_DIR/$ASSET"
download "$RELEASE_BASE/SHA256SUMS" "$TEMP_DIR/SHA256SUMS"

expected_checksum=$(awk -v asset="$ASSET" '$2 == asset || $2 == "*" asset { print $1 }' "$TEMP_DIR/SHA256SUMS")
checksum_count=$(awk -v asset="$ASSET" '$2 == asset || $2 == "*" asset { count++ } END { print count + 0 }' "$TEMP_DIR/SHA256SUMS")
[ "$checksum_count" -eq 1 ] || die "SHA256SUMS does not contain exactly one checksum for $ASSET"
[ "${#expected_checksum}" -eq 64 ] || die "SHA256SUMS contains an invalid checksum for $ASSET"
case $expected_checksum in
    *[!0-9A-Fa-f]*) die "SHA256SUMS contains an invalid checksum for $ASSET" ;;
esac

if command_exists sha256sum; then
    actual_checksum=$(sha256sum "$TEMP_DIR/$ASSET" | awk '{ print $1 }')
elif command_exists shasum; then
    actual_checksum=$(shasum -a 256 "$TEMP_DIR/$ASSET" | awk '{ print $1 }')
elif command_exists openssl; then
    actual_checksum=$(openssl dgst -sha256 "$TEMP_DIR/$ASSET" | awk '{ print $NF }')
else
    die 'no SHA-256 implementation found (install sha256sum, shasum, or openssl)'
fi
[ "$actual_checksum" = "$expected_checksum" ] || die "checksum verification failed for $ASSET"

if [ ! -d "$INSTALL_DIR" ]; then
    if ! mkdir -p "$INSTALL_DIR" 2>/dev/null; then
        as_root mkdir -p "$INSTALL_DIR"
    fi
fi

STAGED_BINARY=$INSTALL_DIR/.c3pm.installing.$$
if [ -w "$INSTALL_DIR" ]; then
    install -m 0755 "$TEMP_DIR/$ASSET" "$STAGED_BINARY"
else
    as_root install -m 0755 "$TEMP_DIR/$ASSET" "$STAGED_BINARY"
fi

"$STAGED_BINARY" --version >/dev/null 2>&1 || die 'downloaded c3pm failed its startup check; the existing installation was left untouched'

if [ -w "$INSTALL_DIR" ]; then
    mv -f "$STAGED_BINARY" "$INSTALL_DIR/c3pm"
else
    as_root mv -f "$STAGED_BINARY" "$INSTALL_DIR/c3pm"
fi
STAGED_BINARY=

case $SELECTED_NIX_MODE in
    portable)
        "$INSTALL_DIR/c3pm" toolchain nix use portable
        ;;
    existing|daemon|single-user)
        "$INSTALL_DIR/c3pm" toolchain nix use "$NIX_BIN"
        ;;
    none) ;;
esac

path_contains() {
    case :$PATH: in
        *:"$1":*) return 0 ;;
        *) return 1 ;;
    esac
}

if [ "$MODIFY_PATH" -eq 1 ] && ! path_contains "$INSTALL_DIR"; then
    profile=$HOME/.profile
    marker="# >>> c3pm PATH: $INSTALL_DIR >>>"
    if [ ! -f "$profile" ] || ! grep -F "$marker" "$profile" >/dev/null 2>&1; then
        escaped_install_dir=$(printf '%s\n' "$INSTALL_DIR" | sed 's/[\\"$`]/\\&/g')
        {
            printf '\n%s\n' "$marker"
            # The dollar signs below intentionally belong in the generated profile.
            # shellcheck disable=SC2016
            printf 'case ":$PATH:" in\n'
            printf '    *:"%s":*) ;;\n' "$escaped_install_dir"
            # shellcheck disable=SC2016
            printf '    *) export PATH="%s:$PATH" ;;\n' "$escaped_install_dir"
            printf 'esac\n'
            printf '# <<< c3pm PATH: %s <<<\n' "$INSTALL_DIR"
        } >>"$profile"
    fi
fi

say "Installed $("$INSTALL_DIR/c3pm" --version) at $INSTALL_DIR/c3pm"
if ! path_contains "$INSTALL_DIR"; then
    say "Open a new shell or run: export PATH=\"$INSTALL_DIR:\$PATH\""
fi
case $SELECTED_NIX_MODE in
    none) warn 'Nix setup was skipped; select a backend later with c3pm toolchain nix use system|portable' ;;
esac
