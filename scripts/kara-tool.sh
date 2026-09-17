#!/bin/sh
set -eu

PROJECTIVY_REPO=spocky/miproja1
PROJECTIVY_PACKAGE=com.spocky.projengmenu
PROJECTIVY_HOME=com.spocky.projengmenu/.ui.home.MainActivity
PROJECTIVY_CERT_SHA256=f6697bf4082ee97511e4de07863193884a015b7ab5860430321bda1042b0aadd
AURORA_PACKAGE=com.aurora.store
AURORA_CERT_SHA256=4c626157ad02bda3401a7263555f68a79663fc3e13a4d4369a12570941aa280f
KARA_SETTINGS_SHA256=56f45a726a98a237d91a43e90f34b8a51e1b42a41b397b2d7388c614c1c9a373
SUPPORTED_DEVICE=kara
SUPPORTED_MODEL=AFTKA
SUPPORTED_BUILD=0035334210436
SUPPORTED_API=28
SUPPORTED_KERNEL=4.14.87+
SUPPORTED_MACHINE=armv7l
SUPPORTED_ABI=armeabi-v7a
SUPPORTED_CPUS=4
SUPPORTED_CPU_ONLINE=0-3
KARA_EXPLOIT_REPO=Delitants/GhostLock
KARA_EXPLOIT_TAG=kara-PS7713-5443-v1
KARA_EXPLOIT_ASSET=kara-ghostlock-PS7713-5443.arm
KARA_EXPLOIT_EXPECTED_SHA256=${KARA_EXPLOIT_EXPECTED_SHA256:-a42185d743ee1d4c9c46c1e35f5fa0a40f5e9a7f81450308c3eab297677847d5}
KARA_EXPERIMENTAL_TAG=kara-experimental-newer-v1
KARA_EXPERIMENTAL_ASSET=kara-ghostlock-experimental-newer.arm
KARA_EXPERIMENTAL_EXPECTED_SHA256=${KARA_EXPERIMENTAL_EXPECTED_SHA256:-d0978d3fcc938150cdc8992243b7a70eedc285ac833ff7a20e99e7b49610a8be}
KARA_EXPERIMENTAL_CONFIRMATION=RUN-KARA-EXPERIMENTAL-NEWER-I-ACCEPT-WATCHDOG-REBOOT
KARA_ROOT_WAIT_ATTEMPTS=${KARA_ROOT_WAIT_ATTEMPTS:-20}

base=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
manifest=${KARA_REMOVE_MANIFEST:-"$base/manifests/remove-user0.txt"}
privileged_manifest=${KARA_PRIVILEGED_MANIFEST:-"$base/manifests/remove-privileged.txt"}
cache_dir=${KARA_CACHE_DIR:-"$base/cache"}
backup_root=${KARA_BACKUP_DIR:-"$base/backups"}
ADB=${ADB:-adb}
CURL=${CURL:-curl}
AAPT=${AAPT:-aapt}
APKSIGNER=${APKSIGNER:-apksigner}
serial=${KARA_SERIAL:-}
bridge=${KARA_BRIDGE:-}
release=latest
aurora_release=latest
backup_dir=
root_helper=
assume_yes=0
accept_watchdog_reboot=0
newer_build=
temp_dir=
current_backup=
rollback_needed=0
rollback_cec_only=0
bridge_temp=

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "$1 is required"; }
expand_home_tool_path() {
    tool_path=$1
    case "$tool_path" in
        '~/'*)
            [ -n "${HOME:-}" ] || fail "HOME is required to expand $tool_path"
            printf '%s/%s\n' "$HOME" "${tool_path#\~/}"
            ;;
        *) printf '%s\n' "$tool_path" ;;
    esac
}
ADB=$(expand_home_tool_path "$ADB")
CURL=$(expand_home_tool_path "$CURL")
AAPT=$(expand_home_tool_path "$AAPT")
APKSIGNER=$(expand_home_tool_path "$APKSIGNER")

controller_prerequisite_gate() {
    need "$CURL"
    need python3
    need "$AAPT"
    need "$APKSIGNER"
    if ! command -v shasum >/dev/null 2>&1; then
        need sha256sum
    fi
    if [ -n "$bridge" ]; then
        need ssh
        need scp
    else
        need "$ADB"
    fi
}

cleanup() {
    status=$?
    trap - 0 HUP INT TERM
    if [ -n "$bridge_temp" ] && [ -n "$bridge" ]; then
        ssh -o BatchMode=yes -o ConnectTimeout=8 "$bridge" rm -f "$bridge_temp" >/dev/null 2>&1 || true
        bridge_temp=
    fi
    if [ "$status" -ne 0 ] && [ "$rollback_needed" -eq 1 ] && [ -n "$current_backup" ]; then
        saved_backup_dir=$backup_dir
        backup_dir=$current_backup
        if [ "$rollback_cec_only" -eq 1 ]; then
            rollback_action=restore_cec_guard
        else
            rollback_action=restore_backup
        fi
        if ("$rollback_action") >&2; then
            printf 'AUTOMATIC_ROLLBACK=PASS\n' >&2
        else
            printf 'AUTOMATIC_ROLLBACK=FAIL backup=%s\n' "$current_backup" >&2
        fi
        backup_dir=$saved_backup_dir
    fi
    if [ -n "$temp_dir" ] && [ -d "$temp_dir" ]; then
        rm -f "$temp_dir/release.json" "$temp_dir/release.fields" \
            "$temp_dir/projectivy.apk.part" "$temp_dir/aurora.apk.part" \
            "$temp_dir/$KARA_EXPLOIT_ASSET.part" "$temp_dir/$KARA_EXPERIMENTAL_ASSET.part"
        rmdir "$temp_dir" 2>/dev/null || true
    fi
    exit "$status"
}
trap cleanup 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

usage() {
    cat <<'EOF'
Usage: scripts/kara-tool.sh [OPTIONS] COMMAND

Commands:
  audit                  Read-only device and package inventory
  download-projectivy    Download and authenticate official Projectivy APK
  download-aurora        Download and authenticate official Aurora Store APK
  download-exploit       Download and authenticate the exact kara exploit
  download-experimental  Download the separate unvalidated newer-build exploit
  probe-newer            Run only the safe compatibility probe on a newer build
  test-newer             Make one experimental temporary-root attempt
  backup                 Save user-0 package, HOME, OTA, and identity state
  apply                  Backup, install Projectivy, set HOME, and debloat
  verify                 Verify the supported durable configuration
  restore                Restore state from --backup DIRECTORY

Options:
  --serial SERIAL        ADB serial (recommended when multiple devices exist)
  --bridge USER@HOST     Run adb through an SSH bridge
  --projectivy TAG       Projectivy release tag (default: latest)
  --aurora TAG           Aurora Store release tag (default: latest)
  --backup DIRECTORY     Backup directory for restore
  --root-helper PATH     Existing device helper accepting: --cmd COMMAND
  --newer-build BUILD    Exact 13-digit newer build shown by the target
  --accept-watchdog-reboot
                         Required for test-newer; the Stick may reboot
  --yes                  Required for mutating or experimental commands
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --serial) [ "$#" -ge 2 ] || fail '--serial needs a value'; serial=$2; shift 2 ;;
        --bridge) [ "$#" -ge 2 ] || fail '--bridge needs a value'; bridge=$2; shift 2 ;;
        --projectivy) [ "$#" -ge 2 ] || fail '--projectivy needs a tag'; release=$2; shift 2 ;;
        --aurora) [ "$#" -ge 2 ] || fail '--aurora needs a tag'; aurora_release=$2; shift 2 ;;
        --backup) [ "$#" -ge 2 ] || fail '--backup needs a directory'; backup_dir=$2; shift 2 ;;
        --root-helper) [ "$#" -ge 2 ] || fail '--root-helper needs a device path'; root_helper=$2; shift 2 ;;
        --newer-build) [ "$#" -ge 2 ] || fail '--newer-build needs a value'; newer_build=$2; shift 2 ;;
        --accept-watchdog-reboot) accept_watchdog_reboot=1; shift ;;
        --yes) assume_yes=1; shift ;;
        -h|--help) usage; exit 0 ;;
        -*) fail "unknown option: $1" ;;
        *) command_name=$1; shift; break ;;
    esac
done
[ "${command_name-}" ] || { usage >&2; exit 2; }
[ "$#" -eq 0 ] || fail 'unexpected positional arguments'
if [ -n "$bridge" ]; then
    printf '%s\n' "$bridge" | grep -Eq '^[A-Za-z0-9._-]+@[A-Za-z0-9._-]+$' || fail 'unsafe SSH bridge name'
fi
case "$KARA_ROOT_WAIT_ATTEMPTS" in ''|*[!0-9]*) fail 'invalid root wait attempt count' ;; esac
[ "$KARA_ROOT_WAIT_ATTEMPTS" -gt 0 ] || fail 'root wait attempt count must be positive'

remote_adb() {
    remote_line=
    for arg do
        case "$arg" in *"'"*|*'
'*|*''*) fail 'unsafe adb argument for SSH bridge' ;; esac
        remote_line="$remote_line '$arg'"
    done
    ssh -o BatchMode=yes -o ConnectTimeout=8 "$bridge" "$remote_line"
}

adb_call() {
    if [ -n "$serial" ]; then set -- -s "$serial" "$@"; fi
    if [ -n "$bridge" ]; then remote_adb adb "$@"; else "$ADB" "$@"; fi
}

stage_bridge_file() {
    local_file=$1
    [ -f "$local_file" ] || fail "local file is missing: $local_file"
    need scp
    bridge_name=$(basename -- "$local_file")
    printf '%s\n' "$bridge_name" | grep -Eq '^[A-Za-z0-9._-]+$' || fail 'unsafe bridge staging filename'
    bridge_temp="/tmp/kara-tool-$$-$bridge_name"
    scp -q -o BatchMode=yes -o ConnectTimeout=8 -- "$local_file" "$bridge:$bridge_temp" ||
        fail 'could not stage file on SSH bridge'
}

clear_bridge_file() {
    [ -n "$bridge_temp" ] || return 0
    ssh -o BatchMode=yes -o ConnectTimeout=8 "$bridge" rm -f "$bridge_temp" >/dev/null ||
        fail 'could not clean SSH bridge staging file'
    bridge_temp=
}

adb_install_file() {
    local_file=$1
    if [ -n "$bridge" ]; then
        stage_bridge_file "$local_file"
        install_status=0
        remote_adb adb install -r "$bridge_temp" || install_status=$?
        clear_bridge_file
        return "$install_status"
    fi
    adb_call install -r "$local_file"
}

adb_push_file() {
    local_file=$1
    device_path=$2
    if [ -n "$bridge" ]; then
        stage_bridge_file "$local_file"
        push_status=0
        remote_adb adb push "$bridge_temp" "$device_path" || push_status=$?
        clear_bridge_file
        return "$push_status"
    fi
    adb_call push "$local_file" "$device_path"
}

device() {
    output=$(adb_call shell "$@") || return $?
    printf '%s\n' "$output" | tr -d '\r'
}

sha256_file() {
    if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk 'NR == 1 {print $1}'
    else sha256sum "$1" | awk 'NR == 1 {print $1}'
    fi
}

identity_values() {
    adb_call get-state | tr -d '\r' | grep -Fx device >/dev/null || fail 'ADB device is unavailable'
    actual_device=$(device getprop ro.product.device)
    actual_model=$(device getprop ro.product.model)
    actual_build=$(device getprop ro.build.version.incremental)
    actual_api=$(device getprop ro.build.version.sdk)
}

mutation_identity_gate() {
    identity_values
    [ "$actual_device" = "$SUPPORTED_DEVICE" ] || fail "unsupported device: $actual_device"
    [ "$actual_model" = "$SUPPORTED_MODEL" ] || fail "unsupported model: $actual_model"
    [ "$actual_build" = "$SUPPORTED_BUILD" ] || fail "unsupported firmware build: $actual_build"
    [ "$actual_api" = "$SUPPORTED_API" ] || fail "unsupported Android API: $actual_api"
}

newer_identity_gate() {
    identity_values
    [ "$actual_device" = "$SUPPORTED_DEVICE" ] || fail "unsupported device: $actual_device"
    [ "$actual_model" = "$SUPPORTED_MODEL" ] || fail "unsupported model: $actual_model"
    [ "$actual_api" = "$SUPPORTED_API" ] || fail "unsupported Android API: $actual_api"
    [ -n "$newer_build" ] || fail 'experimental commands require --newer-build BUILD'
    case "$newer_build" in *[!0-9]*) fail 'newer build must be exactly 13 decimal digits' ;; esac
    [ "${#newer_build}" -eq 13 ] || fail 'newer build must be exactly 13 decimal digits'
    [ "$actual_build" = "$newer_build" ] ||
        fail "requested newer build does not match target: requested=$newer_build actual=$actual_build"
    awk -v requested="$newer_build" -v baseline="$SUPPORTED_BUILD" \
        'BEGIN { exit !(requested > baseline) }' ||
        fail "build is not newer than supported baseline: $newer_build"
}

exploit_runtime_values() {
    actual_kernel=$(device uname -r)
    actual_machine=$(device uname -m)
    actual_abi=$(device getprop ro.product.cpu.abi)
    actual_cpu_online=$(device cat /sys/devices/system/cpu/online)
    if [ "$actual_cpu_online" = "$SUPPORTED_CPU_ONLINE" ]; then
        actual_cpus=$SUPPORTED_CPUS
    else
        actual_cpus="online:$actual_cpu_online"
    fi
    actual_uid=$(device id -u)
    actual_selinux=$(device getenforce)
}

exploit_runtime_gate() {
    exploit_runtime_values
    [ "$actual_kernel" = "$SUPPORTED_KERNEL" ] || fail "unsupported kernel release: $actual_kernel"
    [ "$actual_machine" = "$SUPPORTED_MACHINE" ] || fail "unsupported machine: $actual_machine"
    [ "$actual_abi" = "$SUPPORTED_ABI" ] || fail "unsupported primary ABI: $actual_abi"
    [ "$actual_cpus" = "$SUPPORTED_CPUS" ] || fail "unsupported online CPU count: $actual_cpus"
    [ "$actual_uid" = 2000 ] || fail "ADB shell must be uid 2000 before exploit: $actual_uid"
    [ "$actual_selinux" = Enforcing ] || fail "SELinux must be Enforcing before exploit: $actual_selinux"
}

download_projectivy() {
    need "$CURL"
    need python3
    need "$AAPT"
    need "$APKSIGNER"
    mkdir -p "$cache_dir"
    temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/kara-projectivy.XXXXXX")
    if [ "$release" = latest ]; then
        api_url="https://api.github.com/repos/$PROJECTIVY_REPO/releases/latest"
    else
        case "$release" in *[!0-9A-Za-z._-]*) fail 'unsafe Projectivy release tag' ;; esac
        api_url="https://api.github.com/repos/$PROJECTIVY_REPO/releases/tags/$release"
    fi
    "$CURL" -fsSL --proto '=https' --tlsv1.2 "$api_url" -o "$temp_dir/release.json"
    python3 - "$temp_dir/release.json" > "$temp_dir/release.fields" <<'PY'
import json, re, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
tag = data.get("tag_name", "")
assets = [a for a in data.get("assets", [])
          if re.fullmatch(r"ProjectivyLauncher-[0-9A-Za-z._-]+-xda-release\.apk", a.get("name", ""))]
if not re.fullmatch(r"[0-9]+(?:\.[0-9]+)+", tag) or len(assets) != 1:
    raise SystemExit("invalid or ambiguous official Projectivy release metadata")
asset = assets[0]
print(tag)
print(asset.get("name", ""))
print(asset.get("browser_download_url", ""))
print(asset.get("digest", ""))
PY
    tag=$(sed -n '1p' "$temp_dir/release.fields")
    asset_name=$(sed -n '2p' "$temp_dir/release.fields")
    asset_url=$(sed -n '3p' "$temp_dir/release.fields")
    asset_digest=$(sed -n '4p' "$temp_dir/release.fields")
    case "$asset_url" in
        "https://github.com/$PROJECTIVY_REPO/releases/download/$tag/$asset_name") : ;;
        *) fail 'untrusted Projectivy asset URL' ;;
    esac
    expected_digest=${asset_digest#sha256:}
    if [ "sha256:$expected_digest" != "$asset_digest" ] ||
        ! printf '%s\n' "$expected_digest" | grep -Eq '^[0-9a-f]{64}$'; then
        fail 'official release is missing a valid SHA-256 digest'
    fi
    "$CURL" -fsSL --proto '=https' --tlsv1.2 "$asset_url" -o "$temp_dir/projectivy.apk.part"
    actual_digest=$(sha256_file "$temp_dir/projectivy.apk.part")
    [ "$actual_digest" = "$expected_digest" ] || fail 'Projectivy SHA-256 mismatch'

    badging=$("$AAPT" dump badging "$temp_dir/projectivy.apk.part") || fail 'aapt rejected Projectivy APK'
    package_name=$(printf '%s\n' "$badging" | sed -n "s/^package: name='\([^']*\)'.*/\1/p" | head -n 1)
    version_name=$(printf '%s\n' "$badging" | sed -n "s/^package:.* versionName='\([^']*\)'.*/\1/p" | head -n 1)
    min_sdk=$(printf '%s\n' "$badging" | sed -n "s/^sdkVersion:'\([^']*\)'.*/\1/p" | head -n 1)
    [ "$package_name" = "$PROJECTIVY_PACKAGE" ] || fail 'Projectivy package name mismatch'
    [ "$version_name" = "$tag" ] || fail 'Projectivy tag/version mismatch'
    case "$min_sdk" in ''|*[!0-9]*) fail 'Projectivy minimum SDK is invalid' ;; esac
    [ "$min_sdk" -le "$SUPPORTED_API" ] || fail 'latest Projectivy is incompatible with Android 9'

    certs=$("$APKSIGNER" verify --print-certs "$temp_dir/projectivy.apk.part") || fail 'Projectivy APK signature verification failed'
    cert_digest=$(printf '%s\n' "$certs" | sed -n 's/^Signer #1 certificate SHA-256 digest: //p' | head -n 1)
    [ "$cert_digest" = "$PROJECTIVY_CERT_SHA256" ] || fail 'Projectivy signing certificate mismatch'
    final_apk="$cache_dir/$asset_name"
    mv "$temp_dir/projectivy.apk.part" "$final_apk"
    printf 'PROJECTIVY_VERSION=%s\n' "$tag"
    printf 'PROJECTIVY_APK=%s\n' "$final_apk"
    printf 'PROJECTIVY_SHA256=%s\n' "$actual_digest"
}

download_kara_release() {
    release_tag=$1
    release_asset=$2
    pinned_digest=$3
    output_prefix=$4
    need "$CURL"
    need python3
    mkdir -p "$cache_dir"
    temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/kara-exploit.XXXXXX")
    api_url="https://api.github.com/repos/$KARA_EXPLOIT_REPO/releases/tags/$release_tag"
    "$CURL" -fsSL --proto '=https' --tlsv1.2 "$api_url" -o "$temp_dir/release.json"
    python3 - "$temp_dir/release.json" "$release_tag" "$release_asset" > "$temp_dir/release.fields" <<'PY'
import json, re, sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
expected_tag, expected_name = sys.argv[2:4]
if data.get("tag_name") != expected_tag:
    raise SystemExit("unexpected kara exploit release tag")
assets = [asset for asset in data.get("assets", [])
          if asset.get("name") == expected_name]
if len(assets) != 1:
    raise SystemExit("missing or ambiguous kara exploit asset")
asset = assets[0]
url = asset.get("browser_download_url", "")
digest = asset.get("digest", "")
if not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
    raise SystemExit("kara exploit release is missing a valid SHA-256 digest")
print(url)
print(digest)
PY
    asset_url=$(sed -n '1p' "$temp_dir/release.fields")
    asset_digest=$(sed -n '2p' "$temp_dir/release.fields")
    expected_url="https://github.com/$KARA_EXPLOIT_REPO/releases/download/$release_tag/$release_asset"
    [ "$asset_url" = "$expected_url" ] || fail 'untrusted kara exploit asset URL'
    published_digest=${asset_digest#sha256:}
    [ "$published_digest" = "$pinned_digest" ] ||
        fail 'published kara exploit digest does not match the live-tested artifact'
    "$CURL" -fsSL --proto '=https' --tlsv1.2 "$asset_url" -o "$temp_dir/$release_asset.part"
    actual_digest=$(sha256_file "$temp_dir/$release_asset.part")
    [ "$actual_digest" = "$published_digest" ] || fail 'kara exploit SHA-256 mismatch'
    final_exploit="$cache_dir/$release_asset"
    mv "$temp_dir/$release_asset.part" "$final_exploit"
    printf '%s_VERSION=%s\n' "$output_prefix" "$release_tag"
    printf '%s_PATH=%s\n' "$output_prefix" "$final_exploit"
    printf '%s_SHA256=%s\n' "$output_prefix" "$actual_digest"
}

download_exploit() {
    download_kara_release "$KARA_EXPLOIT_TAG" "$KARA_EXPLOIT_ASSET" \
        "$KARA_EXPLOIT_EXPECTED_SHA256" KARA_EXPLOIT
}

download_experimental() {
    download_kara_release "$KARA_EXPERIMENTAL_TAG" "$KARA_EXPERIMENTAL_ASSET" \
        "$KARA_EXPERIMENTAL_EXPECTED_SHA256" KARA_EXPERIMENTAL
}

download_aurora() {
    need "$CURL"
    need python3
    need "$AAPT"
    need "$APKSIGNER"
    mkdir -p "$cache_dir"
    temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/kara-aurora.XXXXXX")
    case "$aurora_release" in latest) : ;; *[!0-9.]*) fail 'unsafe Aurora release tag' ;; esac
    api_url='https://auroraoss.com/api/files'
    "$CURL" -fsSL --proto '=https' --tlsv1.2 "$api_url" -o "$temp_dir/release.json"
    python3 - "$temp_dir/release.json" "$aurora_release" > "$temp_dir/release.fields" <<'PY'
import json, re, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
requested = sys.argv[2]

def walk(node):
    yield node
    for child in node.get("contents", []):
        if isinstance(child, dict):
            yield from walk(child)

release_dirs = [node for node in walk(data)
                if node.get("path") == "/downloads/AuroraStore/Release"
                and node.get("isDirectory") is True]
if len(release_dirs) != 1:
    raise SystemExit("missing or ambiguous official Aurora release directory")
assets = []
for item in release_dirs[0].get("contents", []):
    match = re.fullmatch(r"AuroraStore-([0-9]+(?:\.[0-9]+)+)\.apk", item.get("name", ""))
    if not match:
        continue
    version = match.group(1)
    expected_path = f"/downloads/AuroraStore/Release/AuroraStore-{version}.apk"
    if (item.get("path") != expected_path or item.get("isDirectory") is not False
            or item.get("mimeType") != "application/vnd.android.package-archive"
            or not isinstance(item.get("size"), int) or item["size"] <= 0):
        raise SystemExit("invalid official Aurora asset metadata")
    assets.append((tuple(map(int, version.split("."))), version, item["name"], item["path"]))
if not assets:
    raise SystemExit("no official Aurora release APK found")
if requested == "latest":
    _, tag, name, path = max(assets)
else:
    matches = [entry for entry in assets if entry[1] == requested]
    if len(matches) != 1:
        raise SystemExit("requested Aurora release is unavailable")
    _, tag, name, path = matches[0]
print(tag)
print(name)
print(path)
PY
    tag=$(sed -n '1p' "$temp_dir/release.fields")
    asset_name=$(sed -n '2p' "$temp_dir/release.fields")
    relative_url=$(sed -n '3p' "$temp_dir/release.fields")
    [ "$relative_url" = "/downloads/AuroraStore/Release/$asset_name" ] || fail 'untrusted Aurora asset URL'
    asset_url="https://auroraoss.com$relative_url"
    "$CURL" -fsSL --proto '=https' --tlsv1.2 "$asset_url" -o "$temp_dir/aurora.apk.part"
    actual_digest=$(sha256_file "$temp_dir/aurora.apk.part")

    badging=$("$AAPT" dump badging "$temp_dir/aurora.apk.part") || fail 'aapt rejected Aurora Store APK'
    package_name=$(printf '%s\n' "$badging" | sed -n "s/^package: name='\([^']*\)'.*/\1/p" | head -n 1)
    version_name=$(printf '%s\n' "$badging" | sed -n "s/^package:.* versionName='\([^']*\)'.*/\1/p" | head -n 1)
    min_sdk=$(printf '%s\n' "$badging" | sed -n "s/^sdkVersion:'\([^']*\)'.*/\1/p" | head -n 1)
    [ "$package_name" = "$AURORA_PACKAGE" ] || fail 'Aurora Store package name mismatch'
    [ "$version_name" = "$tag" ] || fail 'Aurora tag/version mismatch'
    case "$min_sdk" in ''|*[!0-9]*) fail 'Aurora minimum SDK is invalid' ;; esac
    [ "$min_sdk" -le "$SUPPORTED_API" ] || fail 'latest Aurora Store is incompatible with Android 9'

    certs=$("$APKSIGNER" verify --print-certs "$temp_dir/aurora.apk.part") || fail 'Aurora Store APK signature verification failed'
    cert_digest=$(printf '%s\n' "$certs" | sed -n 's/^Signer #1 certificate SHA-256 digest: //p' | head -n 1)
    [ "$cert_digest" = "$AURORA_CERT_SHA256" ] || fail 'Aurora Store signing certificate mismatch'
    final_apk="$cache_dir/$asset_name"
    mv "$temp_dir/aurora.apk.part" "$final_apk"
    printf 'AURORA_VERSION=%s\n' "$tag"
    printf 'AURORA_APK=%s\n' "$final_apk"
    printf 'AURORA_SHA256=%s\n' "$actual_digest"
}

create_backup_values() {
    mkdir -p "$backup_root"
    stamp=$(date -u +%Y%m%dT%H%M%SZ)
    current_backup="$backup_root/$stamp-$$"
    mkdir "$current_backup"
    current_home=$(device cmd package resolve-activity --brief --components --user 0 -a android.intent.action.MAIN -c android.intent.category.HOME)
    ota_value=$(device settings get global ota_disable_automatic_update)
    cec_value=$(device settings get secure block_cec_standby)
    boot_id=$(device cat /proc/sys/kernel/random/boot_id)
    fingerprint=$(device getprop ro.build.fingerprint)
    {
        printf 'DEVICE=%s\n' "$actual_device"
        printf 'MODEL=%s\n' "$actual_model"
        printf 'BUILD=%s\n' "$actual_build"
        printf 'API=%s\n' "$actual_api"
        printf 'HOME=%s\n' "$current_home"
        printf 'OTA_DISABLE_AUTOMATIC_UPDATE=%s\n' "$ota_value"
        printf 'BLOCK_CEC_STANDBY=%s\n' "$cec_value"
        printf 'BOOT_ID=%s\n' "$boot_id"
        printf 'FINGERPRINT=%s\n' "$fingerprint"
    } > "$current_backup/state.env"
    device pm list packages --user 0 > "$current_backup/packages-user0.txt"
    device pm list packages -d --user 0 > "$current_backup/packages-disabled-user0.txt"
    printf 'BACKUP_DIR=%s\n' "$current_backup"
}

create_backup() {
    mutation_identity_gate
    create_backup_values
}

restore_cec_guard() {
    [ -n "$current_backup" ] || fail 'CEC restore has no backup'
    state="$current_backup/state.env"
    [ -r "$state" ] || fail 'CEC restore backup is incomplete'
    old_cec=$(sed -n 's/^BLOCK_CEC_STANDBY=//p' "$state")
    case "$old_cec" in
        null|'') adb_call shell settings delete secure block_cec_standby >/dev/null ;;
        *) adb_call shell settings put secure block_cec_standby "$old_cec" >/dev/null ;;
    esac
}

install_projectivy() {
    download_output=$(download_projectivy)
    printf '%s\n' "$download_output"
    projectivy_apk=$(printf '%s\n' "$download_output" | sed -n 's/^PROJECTIVY_APK=//p')
    [ -f "$projectivy_apk" ] || fail 'verified Projectivy APK is missing'
    install_result=$(adb_install_file "$projectivy_apk" | tr -d '\r') || fail 'Projectivy installation failed'
    printf '%s\n' "$install_result" | tail -n 1 | grep -Fx Success >/dev/null || fail 'Projectivy installation did not report Success'
}

install_kara_settings() {
    settings_apk="$base/app/kara-settings/kara-settings-v5-signed.apk"
    [ -f "$settings_apk" ] || fail 'Kara Settings APK is missing'
    [ "$(sha256_file "$settings_apk")" = "$KARA_SETTINGS_SHA256" ] || fail 'Kara Settings APK hash mismatch'
    install_result=$(adb_install_file "$settings_apk" | tr -d '\r') || fail 'Kara Settings installation failed'
    printf '%s\n' "$install_result" | tail -n 1 | grep -Fx Success >/dev/null || fail 'Kara Settings installation did not report Success'
}

install_aurora() {
    download_output=$(download_aurora)
    printf '%s\n' "$download_output"
    aurora_apk=$(printf '%s\n' "$download_output" | sed -n 's/^AURORA_APK=//p')
    [ -f "$aurora_apk" ] || fail 'verified Aurora Store APK is missing'
    install_result=$(adb_install_file "$aurora_apk" | tr -d '\r') || fail 'Aurora Store installation failed'
    printf '%s\n' "$install_result" | tail -n 1 | grep -Fx Success >/dev/null || fail 'Aurora Store installation did not report Success'
}

verify_root_helper() {
    expected_build=${1:-$SUPPORTED_BUILD}
    expected_mode=${2:-}
    printf '%s\n' "$root_helper" | grep -Eq '^/data/local/tmp/[A-Za-z0-9._-]+$' || fail 'unsafe root-helper path'
    # Pass each client invocation as one quoted remote-shell argument. Older
    # adb clients otherwise split at semicolons and run the tail as uid 2000.
    root_command='id; cat /data/local/tmp/kara-root-ready'
    root_proof=$(device "$root_helper --cmd \"$root_command\"" 2>/dev/null) || return 1
    printf '%s\n' "$root_proof" | grep -E '(^| )uid=0\(root\)( |$)' >/dev/null || return 1
    printf '%s\n' "$root_proof" | grep -F 'ROOTED uid=0 euid=0' >/dev/null || return 1
    printf '%s\n' "$root_proof" | grep -E "(^| )build=$expected_build( |$)" >/dev/null || return 1
    if [ -n "$expected_mode" ]; then
        printf '%s\n' "$root_proof" | grep -E "(^| )mode=$expected_mode( |$)" >/dev/null || return 1
    fi
    daemon_command="readlink /proc/\\\$PPID/exe 2>/dev/null | grep -Fx $root_helper >/dev/null && echo DAEMON_EXE=$root_helper"
    daemon_proof=$(device "$root_helper --cmd \"$daemon_command\"" 2>/dev/null) || return 1
    printf '%s\n' "$daemon_proof" | grep -Fx "DAEMON_EXE=$root_helper" >/dev/null || return 1
}

root_helper_runtime_gate() {
    exploit_runtime_values
    [ "$actual_kernel" = "$SUPPORTED_KERNEL" ] || fail "unsupported kernel release: $actual_kernel"
    [ "$actual_machine" = "$SUPPORTED_MACHINE" ] || fail "unsupported machine: $actual_machine"
    [ "$actual_abi" = "$SUPPORTED_ABI" ] || fail "unsupported primary ABI: $actual_abi"
    [ "$actual_cpus" = "$SUPPORTED_CPUS" ] || fail "unsupported online CPU count: $actual_cpus"
    [ "$actual_uid" = 2000 ] || fail "ADB shell must be uid 2000: $actual_uid"
    case "$actual_selinux" in
        Enforcing|Permissive) : ;;
        *) fail "unsupported SELinux state for root-helper resume: $actual_selinux" ;;
    esac
    verify_root_helper || fail 'supplied root helper did not prove temporary uid 0'
}

clear_empty_ota_collision() {
    # GhostLock can leave both paths present when each is an empty directory.
    # rmdir is deliberately used so a live OTA payload can never be deleted.
    ota_repair='if [ -e /data/local/tmp/kara-ota-package.PS7713-held ] && [ -d /data/ota_package ]; then if rmdir /data/ota_package 2>/dev/null; then sync; echo EMPTY_OTA_COLLISION_CLEARED; else echo NONEMPTY_OTA_LIVE_PATH; fi; fi'
    ota_repair_output=$(device "$root_helper --cmd \"$ota_repair\"") ||
        fail 'could not inspect the OTA collision'
    case "$ota_repair_output" in
        '') : ;;
        EMPTY_OTA_COLLISION_CLEARED)
            printf 'EMPTY_OTA_COLLISION_CLEARED=PASS\n'
            ;;
        NONEMPTY_OTA_LIVE_PATH)
            fail 'live OTA path is not empty; manual review required'
            ;;
        *) fail "unexpected OTA collision response: $ota_repair_output" ;;
    esac
}

verify_staged_ota_absent() {
    ota_check='[ ! -e /data/ota_package ] || echo PRESENT:/data/ota_package; [ ! -e /cache/recovery/command ] || echo PRESENT:/cache/recovery/command; [ ! -e /cache/recovery/block.map ] || echo PRESENT:/cache/recovery/block.map'
    ota_present=$(device "$root_helper --cmd \"$ota_check\"") || fail 'could not verify staged OTA paths'
    [ -z "$ota_present" ] || fail "staged OTA path remains: $ota_present"
    printf 'STAGED_OTA_PATHS=ABSENT\n'
}

obtain_temp_root() {
    if [ -n "$root_helper" ]; then
        verify_root_helper || fail 'supplied root helper did not prove temporary uid 0'
        mutation_identity_gate
        printf 'TEMP_ROOT=PASS supplied-helper\n'
        return
    fi

    exploit_output=$(download_exploit)
    printf '%s\n' "$exploit_output"
    exploit_path=$(printf '%s\n' "$exploit_output" | sed -n 's/^KARA_EXPLOIT_PATH=//p')
    [ -f "$exploit_path" ] || fail 'verified kara exploit is missing'
    remote_exploit="/data/local/tmp/kara-ghostlock-$$"
    adb_push_file "$exploit_path" "$remote_exploit" >/dev/null || fail 'could not stage kara exploit'
    device chmod 700 "$remote_exploit" >/dev/null || fail 'could not make kara exploit executable'
    probe_status=0
    probe_output=$(adb_call shell "$remote_exploit" --probe 2>&1) || probe_status=$?
    [ "$probe_status" -eq 0 ] || fail 'kara exploit safe probe failed'
    printf '%s\n' "$probe_output" | tr -d '\r' | \
        grep -F 'V2 SAFE PROBE PASS (reclaim and GhostLock were not invoked)' >/dev/null ||
        fail 'kara exploit safe probe did not pass'

    root_helper=$remote_exploit
    if verify_root_helper; then
        mutation_identity_gate
        printf 'TEMP_ROOT=PASS reused-live-daemon\n'
        return
    fi

    adb_call shell "nohup $remote_exploit --live RUN-KARA-PS7713-GHOSTLOCK-V2 >/data/local/tmp/kara-ghostlock.start.log 2>&1 </dev/null &" >/dev/null ||
        fail 'could not start kara exploit'
    root_attempt=0
    while [ "$root_attempt" -lt "$KARA_ROOT_WAIT_ATTEMPTS" ]; do
        # If identity changed while the live attempt started, restore only the
        # CEC guard; replaying package state across firmware builds is unsafe.
        saved_rollback_cec_only=$rollback_cec_only
        rollback_cec_only=1
        mutation_identity_gate
        rollback_cec_only=$saved_rollback_cec_only
        if verify_root_helper; then
            mutation_identity_gate
            printf 'TEMP_ROOT=PASS new-live-daemon\n'
            return
        fi
        root_attempt=$((root_attempt + 1))
        sleep 1
    done
    fail 'temporary root was not obtained; no package changes were attempted'
}

begin_experimental_test() {
    newer_identity_gate
    exploit_runtime_gate
    create_backup_values
    rollback_needed=1
    rollback_cec_only=1
    adb_call shell settings put secure block_cec_standby 1 >/dev/null
    [ "$(device settings get secure block_cec_standby)" = 1 ] ||
        fail 'could not enable the exploit CEC reboot guard'
}

stage_and_probe_experimental() {
    experimental_output=$(download_experimental)
    printf '%s\n' "$experimental_output"
    experimental_path=$(printf '%s\n' "$experimental_output" | sed -n 's/^KARA_EXPERIMENTAL_PATH=//p')
    [ -f "$experimental_path" ] || fail 'verified experimental kara exploit is missing'
    experimental_remote="/data/local/tmp/kara-ghostlock-experimental-$$"
    adb_push_file "$experimental_path" "$experimental_remote" >/dev/null ||
        fail 'could not stage experimental kara exploit'
    device chmod 700 "$experimental_remote" >/dev/null ||
        fail 'could not make experimental kara exploit executable'
    experimental_probe_status=0
    experimental_probe=$(adb_call shell "$experimental_remote" --probe-newer "$newer_build" 2>&1) ||
        experimental_probe_status=$?
    [ "$experimental_probe_status" -eq 0 ] || fail 'experimental newer-firmware safe probe failed'
    printf '%s\n' "$experimental_probe" | tr -d '\r' | \
        grep -Fx "KARA_EXPERIMENTAL_NEWER_PROBE=PASS build=$newer_build" >/dev/null ||
        fail 'experimental newer-firmware safe probe did not pass'
}

probe_newer() {
    [ "$assume_yes" -eq 1 ] || fail 'probe-newer requires --yes'
    begin_experimental_test
    stage_and_probe_experimental
    device rm -f "$experimental_remote" >/dev/null || fail 'could not remove experimental probe binary'
    restore_cec_guard
    rollback_needed=0
    rollback_cec_only=0
    printf 'UNVALIDATED_NEWER_FIRMWARE=YES\n'
    printf 'EXPERIMENTAL_NEWER_PROBE=PASS build=%s\n' "$newer_build"
}

test_newer() {
    [ "$assume_yes" -eq 1 ] || fail 'test-newer requires --yes'
    [ "$accept_watchdog_reboot" -eq 1 ] || fail 'test-newer requires --accept-watchdog-reboot'
    begin_experimental_test
    stage_and_probe_experimental
    root_helper=$experimental_remote
    adb_call shell "nohup $experimental_remote --live-newer $newer_build $KARA_EXPERIMENTAL_CONFIRMATION >/data/local/tmp/kara-ghostlock-experimental.start.log 2>&1 </dev/null &" >/dev/null ||
        fail 'could not start experimental kara exploit'
    root_attempt=0
    while [ "$root_attempt" -lt "$KARA_ROOT_WAIT_ATTEMPTS" ]; do
        if verify_root_helper "$newer_build" experimental-newer; then
            newer_identity_gate
            restore_cec_guard
            rollback_needed=0
            rollback_cec_only=0
            printf 'UNVALIDATED_NEWER_FIRMWARE=YES\n'
            printf 'EXPERIMENTAL_NEWER_ROOT=PASS build=%s\n' "$newer_build"
            printf 'TEMPORARY_ROOT_REBOOT_REQUIRED=YES\n'
            return
        fi
        root_attempt=$((root_attempt + 1))
        sleep 1
    done
    fail 'experimental newer-firmware root was not obtained; reboot restores the stock security state'
}

remove_privileged_packages() {
    [ -n "$root_helper" ] || { printf 'PRIVILEGED_REMOVAL=SKIPPED no root helper supplied\n'; return; }
    printf '%s\n' "$root_helper" | grep -Eq '^/data/local/tmp/[A-Za-z0-9._-]+$' || fail 'unsafe root-helper path'
    [ -r "$privileged_manifest" ] || fail 'privileged package manifest is missing'
    while IFS= read -r package_name; do
        [ -n "$package_name" ] || continue
        case "$package_name" in com.amazon.*|amazon.*) : ;; *) fail "unsafe privileged package: $package_name" ;; esac
        fixed_command="runcon u:r:shell:s0 /system/bin/pm uninstall -k --user 0 $package_name"
        device "$root_helper --cmd \"$fixed_command\"" >/dev/null || fail "privileged removal failed: $package_name"
    done < "$privileged_manifest"
    active=$(device pm list packages --user 0)
    while IFS= read -r package_name; do
        [ -n "$package_name" ] || continue
        if printf '%s\n' "$active" | grep -Fx "package:$package_name" >/dev/null; then
            fail "privileged package is still active: $package_name"
        fi
    done < "$privileged_manifest"
    printf 'PRIVILEGED_REMOVAL=PASS\n'
}

apply_changes() {
    [ "$assume_yes" -eq 1 ] || fail 'apply requires --yes'
    controller_prerequisite_gate
    mutation_identity_gate
    if [ -n "$root_helper" ]; then
        root_helper_runtime_gate
    else
        exploit_runtime_gate
    fi
    create_backup
    rollback_needed=1
    rollback_cec_only=1
    adb_call shell settings put secure block_cec_standby 1 >/dev/null
    [ "$(device settings get secure block_cec_standby)" = 1 ] || fail 'could not enable the exploit CEC reboot guard'
    obtain_temp_root
    clear_empty_ota_collision
    verify_staged_ota_absent
    rollback_cec_only=0
    install_projectivy
    install_aurora
    install_kara_settings
    adb_call shell cmd package set-home-activity "$PROJECTIVY_HOME" >/dev/null
    selected_home=$(device cmd package resolve-activity --brief --components --user 0 -a android.intent.action.MAIN -c android.intent.category.HOME)
    [ "$selected_home" = "$PROJECTIVY_HOME" ] || fail "Projectivy did not become HOME: $selected_home"
    adb_call shell am start -W --user 0 -a android.intent.action.MAIN -c android.intent.category.HOME >/dev/null
    [ -r "$manifest" ] || fail 'package removal manifest is missing'
    while IFS= read -r package_name; do
        [ -n "$package_name" ] || continue
        case "$package_name" in com.amazon.*|amazon.*) : ;; *) fail "unsafe package in manifest: $package_name" ;; esac
        adb_call shell pm uninstall -k --user 0 "$package_name" >/dev/null || true
    done < "$manifest"
    remove_privileged_packages
    adb_call shell settings put global ota_disable_automatic_update 1
    verify_device
    rollback_needed=0
    printf 'APPLY_GATE=PASS\n'
}

audit_device() {
    identity_values
    exploit_runtime_values
    printf 'DEVICE=%s\nMODEL=%s\nBUILD=%s\nAPI=%s\n' "$actual_device" "$actual_model" "$actual_build" "$actual_api"
    printf 'KERNEL=%s\nMACHINE=%s\nABI=%s\nCPUS=%s\nSHELL_UID=%s\nSELINUX=%s\n' \
        "$actual_kernel" "$actual_machine" "$actual_abi" "$actual_cpus" "$actual_uid" "$actual_selinux"
    printf 'VERIFIED_BOOT=%s\n' "$(device getprop ro.boot.verifiedbootstate)"
    printf 'FLASH_LOCKED=%s\n' "$(device getprop ro.boot.flash.locked)"
    printf 'HOME=%s\n' "$(device cmd package resolve-activity --brief --components --user 0 -a android.intent.action.MAIN -c android.intent.category.HOME)"
    if [ "$actual_device/$actual_model/$actual_build/API$actual_api" = "$SUPPORTED_DEVICE/$SUPPORTED_MODEL/$SUPPORTED_BUILD/API$SUPPORTED_API" ]; then
        printf 'SUPPORTED_MUTATION_TARGET=YES\n'
    else
        printf 'SUPPORTED_MUTATION_TARGET=NO\n'
    fi
    if [ "$actual_device/$actual_model/$actual_build/API$actual_api" = "$SUPPORTED_DEVICE/$SUPPORTED_MODEL/$SUPPORTED_BUILD/API$SUPPORTED_API" ] &&
        [ "$actual_kernel/$actual_machine/$actual_abi/$actual_cpus/$actual_uid/$actual_selinux" = "$SUPPORTED_KERNEL/$SUPPORTED_MACHINE/$SUPPORTED_ABI/$SUPPORTED_CPUS/2000/Enforcing" ]; then
        printf 'SUPPORTED_EXPLOIT_TARGET=YES\n'
    else
        printf 'SUPPORTED_EXPLOIT_TARGET=NO\n'
    fi
}

verify_device() {
    mutation_identity_gate
    home=$(device cmd package resolve-activity --brief --components --user 0 -a android.intent.action.MAIN -c android.intent.category.HOME)
    [ "$home" = "$PROJECTIVY_HOME" ] || fail "Projectivy is not HOME: $home"
    ota=$(device settings get global ota_disable_automatic_update)
    [ "$ota" = 1 ] || fail 'automatic OTA setting is not disabled'
    active=$(device pm list packages --user 0)
    for required_package in "$PROJECTIVY_PACKAGE" "$AURORA_PACKAGE" local.kara.settingsredirector; do
        printf '%s\n' "$active" | grep -Fx "package:$required_package" >/dev/null ||
            fail "required package is not active: $required_package"
    done
    while IFS= read -r package_name; do
        [ -n "$package_name" ] || continue
        if printf '%s\n' "$active" | grep -Fx "package:$package_name" >/dev/null; then
            fail "removed package is active: $package_name"
        fi
    done < "$manifest"
    if [ -n "$root_helper" ]; then
        while IFS= read -r package_name; do
            [ -n "$package_name" ] || continue
            if printf '%s\n' "$active" | grep -Fx "package:$package_name" >/dev/null; then
                fail "privileged package is active: $package_name"
            fi
        done < "$privileged_manifest"
    fi
    printf 'VERIFY_GATE=PASS\n'
}

restore_backup() {
    [ "$assume_yes" -eq 1 ] || fail 'restore requires --yes'
    mutation_identity_gate
    if [ -z "$backup_dir" ] || [ ! -d "$backup_dir" ]; then
        fail 'restore requires a readable --backup directory'
    fi
    state="$backup_dir/state.env"
    packages="$backup_dir/packages-user0.txt"
    disabled="$backup_dir/packages-disabled-user0.txt"
    if [ ! -r "$state" ] || [ ! -r "$packages" ] || [ ! -r "$disabled" ]; then
        fail 'backup is incomplete'
    fi
    backup_device=$(sed -n 's/^DEVICE=//p' "$state")
    backup_model=$(sed -n 's/^MODEL=//p' "$state")
    backup_build=$(sed -n 's/^BUILD=//p' "$state")
    [ "$backup_device/$backup_model/$backup_build" = "$actual_device/$actual_model/$actual_build" ] || fail 'backup identity mismatch'
    old_home=$(sed -n 's/^HOME=//p' "$state")
    case "$old_home" in *[!A-Za-z0-9._/\$-]*) fail 'unsafe HOME value in backup' ;; esac
    for restore_manifest in "$manifest" "$privileged_manifest"; do
        while IFS= read -r package_name; do
            [ -n "$package_name" ] || continue
            if grep -Fx "package:$package_name" "$packages" >/dev/null; then
                adb_call shell cmd package install-existing --user 0 "$package_name" >/dev/null || fail "could not restore $package_name"
                if grep -Fx "package:$package_name" "$disabled" >/dev/null; then
                    adb_call shell pm disable --user 0 "$package_name" >/dev/null
                fi
            fi
        done < "$restore_manifest"
    done
    [ -n "$old_home" ] && adb_call shell cmd package set-home-activity "$old_home" >/dev/null
    old_ota=$(sed -n 's/^OTA_DISABLE_AUTOMATIC_UPDATE=//p' "$state")
    case "$old_ota" in null|'') adb_call shell settings delete global ota_disable_automatic_update >/dev/null ;;
        *) adb_call shell settings put global ota_disable_automatic_update "$old_ota" >/dev/null ;;
    esac
    old_cec=$(sed -n 's/^BLOCK_CEC_STANDBY=//p' "$state")
    case "$old_cec" in null|'') adb_call shell settings delete secure block_cec_standby >/dev/null ;;
        *) adb_call shell settings put secure block_cec_standby "$old_cec" >/dev/null ;;
    esac
    printf 'RESTORE_GATE=PASS\n'
}

case "$command_name" in
    audit) audit_device ;;
    download-projectivy) download_projectivy ;;
    download-aurora) download_aurora ;;
    download-exploit) download_exploit ;;
    download-experimental) download_experimental ;;
    probe-newer) probe_newer ;;
    test-newer) test_newer ;;
    backup) create_backup ;;
    apply) apply_changes ;;
    verify) verify_device ;;
    restore) restore_backup ;;
    *) usage >&2; fail "unknown command: $command_name" ;;
esac
