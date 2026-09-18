#!/bin/sh

set -eu

REPOSITORY_ROOT=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
INSTALLER=$REPOSITORY_ROOT/install.sh
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/c3pm-installer-test.XXXXXX")
ORIGINAL_PATH=$PATH

cleanup() {
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT HUP INT TERM

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_file_contains() {
    grep -F "$2" "$1" >/dev/null 2>&1 || fail "$1 does not contain: $2"
}

mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/fixture"

cat >"$TEST_ROOT/fixture/c3pm-linux-x86_64" <<'EOF'
#!/bin/sh
case ${1:-} in
    --version)
        printf 'c3pm test-version\n'
        ;;
    toolchain)
        if [ -n "${C3PM_TEST_LOG:-}" ]; then
            printf '%s\n' "$*" >>"$C3PM_TEST_LOG"
        fi
        ;;
    *)
        exit 0
        ;;
esac
EOF
chmod +x "$TEST_ROOT/fixture/c3pm-linux-x86_64"
fixture_checksum=$(sha256sum "$TEST_ROOT/fixture/c3pm-linux-x86_64" | awk '{ print $1 }')
printf '%s  c3pm-linux-x86_64\n' "$fixture_checksum" >"$TEST_ROOT/fixture/SHA256SUMS"
cat >"$TEST_ROOT/fixture/c3pm-bad-startup" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$TEST_ROOT/fixture/c3pm-bad-startup"
bad_startup_checksum=$(sha256sum "$TEST_ROOT/fixture/c3pm-bad-startup" | awk '{ print $1 }')
printf '%s  c3pm-linux-x86_64\n' "$bad_startup_checksum" >"$TEST_ROOT/fixture/SHA256SUMS.bad-startup"

cat >"$TEST_ROOT/bin/curl" <<'EOF'
#!/bin/sh
set -eu
output=
url=
while [ "$#" -gt 0 ]; do
    case $1 in
        --output)
            output=$2
            shift 2
            ;;
        --retry|--proto)
            shift 2
            ;;
        --fail|--location|--tlsv1.2)
            shift
            ;;
        *)
            url=$1
            shift
            ;;
    esac
done
[ -n "$output" ] || exit 2
case $url in
    */SHA256SUMS)
        if [ "${C3PM_TEST_BAD_CHECKSUM:-0}" = 1 ]; then
            printf '%064d  c3pm-linux-x86_64\n' 0 >"$output"
        elif [ "${C3PM_TEST_BAD_STARTUP:-0}" = 1 ]; then
            cp "$C3PM_TEST_FIXTURE/SHA256SUMS.bad-startup" "$output"
        else
            cp "$C3PM_TEST_FIXTURE/SHA256SUMS" "$output"
        fi
        ;;
    */c3pm-linux-x86_64)
        if [ "${C3PM_TEST_BAD_STARTUP:-0}" = 1 ]; then
            cp "$C3PM_TEST_FIXTURE/c3pm-bad-startup" "$output"
        else
            cp "$C3PM_TEST_FIXTURE/c3pm-linux-x86_64" "$output"
        fi
        ;;
    *)
        exit 3
        ;;
esac
EOF
chmod +x "$TEST_ROOT/bin/curl"

export C3PM_TEST_FIXTURE="$TEST_ROOT/fixture"
PATH=$TEST_ROOT/bin:$ORIGINAL_PATH
export PATH

sh -n "$INSTALLER"
sh "$INSTALLER" --help >/dev/null

if C3PM_TEST_UNAME_M=aarch64 sh "$INSTALLER" --nix none --yes >"$TEST_ROOT/unsupported.log" 2>&1; then
    fail 'unsupported architectures must be rejected'
fi
assert_file_contains "$TEST_ROOT/unsupported.log" "unsupported architecture 'aarch64'"

dry_home=$TEST_ROOT/dry-home
dry_prefix=$TEST_ROOT/dry-prefix
mkdir -p "$dry_home"
HOME=$dry_home sh "$INSTALLER" --nix none --yes --dry-run --prefix "$dry_prefix" >/dev/null
[ ! -e "$dry_prefix" ] || fail 'dry-run created the install directory'
[ ! -e "$dry_home/.profile" ] || fail 'dry-run modified the profile'

success_home=$TEST_ROOT/success-home
success_prefix=$success_home/.local/bin
mkdir -p "$success_home"
HOME=$success_home sh "$INSTALLER" --nix none --yes --prefix "$success_prefix" >/dev/null
[ -x "$success_prefix/c3pm" ] || fail 'c3pm was not installed'
[ "$("$success_prefix/c3pm" --version)" = 'c3pm test-version' ] || fail 'installed binary did not run'
assert_file_contains "$success_home/.profile" '# >>> c3pm PATH:'
sh -n "$success_home/.profile"

HOME=$success_home sh "$INSTALLER" --nix none --yes --prefix "$success_prefix" >/dev/null
marker_count=$(grep -F -c '# >>> c3pm PATH:' "$success_home/.profile")
[ "$marker_count" -eq 1 ] || fail 'PATH profile block is not idempotent'

failure_home=$TEST_ROOT/failure-home
failure_prefix=$failure_home/bin
mkdir -p "$failure_prefix"
printf 'existing installation\n' >"$failure_prefix/c3pm"
if HOME=$failure_home C3PM_TEST_BAD_CHECKSUM=1 \
    sh "$INSTALLER" --nix none --yes --no-modify-path --prefix "$failure_prefix" \
    >"$TEST_ROOT/checksum.log" 2>&1; then
    fail 'a bad checksum must fail installation'
fi
[ "$(sed -n '1p' "$failure_prefix/c3pm")" = 'existing installation' ] || fail 'checksum failure replaced the existing binary'
assert_file_contains "$TEST_ROOT/checksum.log" 'checksum verification failed'

startup_home=$TEST_ROOT/startup-home
startup_prefix=$startup_home/bin
mkdir -p "$startup_prefix"
printf 'existing installation\n' >"$startup_prefix/c3pm"
if HOME=$startup_home C3PM_TEST_BAD_STARTUP=1 \
    sh "$INSTALLER" --nix none --yes --no-modify-path --prefix "$startup_prefix" \
    >"$TEST_ROOT/startup.log" 2>&1; then
    fail 'a binary that fails to start must fail installation'
fi
[ "$(sed -n '1p' "$startup_prefix/c3pm")" = 'existing installation' ] || fail 'startup failure replaced the existing binary'
assert_file_contains "$TEST_ROOT/startup.log" 'existing installation was left untouched'

portable_home=$TEST_ROOT/portable-home
portable_prefix=$portable_home/bin
portable_log=$TEST_ROOT/portable.log
mkdir -p "$portable_home"
HOME=$portable_home C3PM_TEST_LOG=$portable_log \
    sh "$INSTALLER" --nix portable --yes --no-modify-path --prefix "$portable_prefix" >/dev/null
assert_file_contains "$portable_log" 'toolchain nix use portable'

printf 'install_script_test: all tests passed\n'
