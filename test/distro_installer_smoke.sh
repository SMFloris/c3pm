#!/bin/sh
set -eu

expected_manager=$1
test_root=$(mktemp -d "${TMPDIR:-/tmp}/c3pm-distro-smoke.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
mkdir -p "$test_root/bin" "$test_root/fixture"

printf '#!/bin/sh\nprintf "c3pm distro-smoke\\n"\n' >"$test_root/fixture/c3pm-linux-x86_64"
chmod +x "$test_root/fixture/c3pm-linux-x86_64"
checksum=$(sha256sum "$test_root/fixture/c3pm-linux-x86_64" | awk '{ print $1 }')
printf '%s  c3pm-linux-x86_64\n' "$checksum" >"$test_root/fixture/SHA256SUMS"

cat >"$test_root/bin/curl" <<'EOF'
#!/bin/sh
set -eu
output=
url=
while [ "$#" -gt 0 ]; do
    case $1 in
        --output) output=$2; shift 2 ;;
        --retry|--proto) shift 2 ;;
        --fail|--location|--tlsv1.2) shift ;;
        *) url=$1; shift ;;
    esac
done
case $url in
    */c3pm-linux-x86_64|*/SHA256SUMS)
        cp "$C3PM_SMOKE_FIXTURE/${url##*/}" "$output" ;;
    *) exit 2 ;;
esac
EOF
chmod +x "$test_root/bin/curl"

export C3PM_SMOKE_FIXTURE="$test_root/fixture"
export C3PM_TEST_MISSING_PREREQUISITES=1
PATH="$test_root/bin:$PATH"
export PATH

plan=$(sh install.sh --nix none --yes --dry-run --no-modify-path)
printf '%s\n' "$plan" | grep -F "prerequisites: install with $expected_manager"
sh install.sh --nix none --yes --no-modify-path --prefix "$test_root/install"
test "$("$test_root/install/c3pm" --version)" = 'c3pm distro-smoke'
