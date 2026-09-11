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
temp_dir=
current_backup=
rollback_needed=0

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "$1 is required"; }
cleanup() {
    status=$?
    trap - 0 HUP INT TERM
    if [ "$status" -ne 0 ] && [ "$rollback_needed" -eq 1 ] && [ -n "$current_backup" ]; then
        saved_backup_dir=$backup_dir
        backup_dir=$current_backup
        if (restore_backup) >&2; then
            printf 'AUTOMATIC_ROLLBACK=PASS\n' >&2
        else
            printf 'AUTOMATIC_ROLLBACK=FAIL backup=%s\n' "$current_backup" >&2
        fi
        backup_dir=$saved_backup_dir
    fi
    if [ -n "$temp_dir" ] && [ -d "$temp_dir" ]; then
        rm -f "$temp_dir/release.json" "$temp_dir/release.fields" \
            "$temp_dir/projectivy.apk.part" "$temp_dir/aurora.apk.part"
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
  --yes                  Required for apply and restore
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
        --yes) assume_yes=1; shift ;;
        -h|--help) usage; exit 0 ;;
        -*) fail "unknown option: $1" ;;
        *) command_name=$1; shift; break ;;
    esac
done
[ "${command_name-}" ] || { usage >&2; exit 2; }
[ "$#" -eq 0 ] || fail 'unexpected positional arguments'

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

create_backup() {
    mutation_identity_gate
    mkdir -p "$backup_root"
    stamp=$(date -u +%Y%m%dT%H%M%SZ)
    current_backup="$backup_root/$stamp-$$"
    mkdir "$current_backup"
    current_home=$(device cmd package resolve-activity --brief --components --user 0 -a android.intent.action.MAIN -c android.intent.category.HOME)
    ota_value=$(device settings get global ota_disable_automatic_update)
    boot_id=$(device cat /proc/sys/kernel/random/boot_id)
    fingerprint=$(device getprop ro.build.fingerprint)
    {
        printf 'DEVICE=%s\n' "$actual_device"
        printf 'MODEL=%s\n' "$actual_model"
        printf 'BUILD=%s\n' "$actual_build"
        printf 'API=%s\n' "$actual_api"
        printf 'HOME=%s\n' "$current_home"
        printf 'OTA_DISABLE_AUTOMATIC_UPDATE=%s\n' "$ota_value"
        printf 'BOOT_ID=%s\n' "$boot_id"
        printf 'FINGERPRINT=%s\n' "$fingerprint"
    } > "$current_backup/state.env"
    device pm list packages --user 0 > "$current_backup/packages-user0.txt"
    device pm list packages -d --user 0 > "$current_backup/packages-disabled-user0.txt"
    printf 'BACKUP_DIR=%s\n' "$current_backup"
}

install_projectivy() {
    download_output=$(download_projectivy)
    printf '%s\n' "$download_output"
    projectivy_apk=$(printf '%s\n' "$download_output" | sed -n 's/^PROJECTIVY_APK=//p')
    [ -f "$projectivy_apk" ] || fail 'verified Projectivy APK is missing'
    install_result=$(adb_call install -r "$projectivy_apk" | tr -d '\r') || fail 'Projectivy installation failed'
    printf '%s\n' "$install_result" | tail -n 1 | grep -Fx Success >/dev/null || fail 'Projectivy installation did not report Success'
}

install_kara_settings() {
    settings_apk="$base/app/kara-settings/kara-settings-v5-signed.apk"
    [ -f "$settings_apk" ] || fail 'Kara Settings APK is missing'
    [ "$(sha256_file "$settings_apk")" = "$KARA_SETTINGS_SHA256" ] || fail 'Kara Settings APK hash mismatch'
    install_result=$(adb_call install -r "$settings_apk" | tr -d '\r') || fail 'Kara Settings installation failed'
    printf '%s\n' "$install_result" | tail -n 1 | grep -Fx Success >/dev/null || fail 'Kara Settings installation did not report Success'
}

install_aurora() {
    download_output=$(download_aurora)
    printf '%s\n' "$download_output"
    aurora_apk=$(printf '%s\n' "$download_output" | sed -n 's/^AURORA_APK=//p')
    [ -f "$aurora_apk" ] || fail 'verified Aurora Store APK is missing'
    install_result=$(adb_call install -r "$aurora_apk" | tr -d '\r') || fail 'Aurora Store installation failed'
    printf '%s\n' "$install_result" | tail -n 1 | grep -Fx Success >/dev/null || fail 'Aurora Store installation did not report Success'
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
    mutation_identity_gate
    create_backup
    rollback_needed=1
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
    printf 'DEVICE=%s\nMODEL=%s\nBUILD=%s\nAPI=%s\n' "$actual_device" "$actual_model" "$actual_build" "$actual_api"
    printf 'VERIFIED_BOOT=%s\n' "$(device getprop ro.boot.verifiedbootstate)"
    printf 'FLASH_LOCKED=%s\n' "$(device getprop ro.boot.flash.locked)"
    printf 'HOME=%s\n' "$(device cmd package resolve-activity --brief --components --user 0 -a android.intent.action.MAIN -c android.intent.category.HOME)"
    if [ "$actual_device/$actual_model/$actual_build/API$actual_api" = "$SUPPORTED_DEVICE/$SUPPORTED_MODEL/$SUPPORTED_BUILD/API$SUPPORTED_API" ]; then
        printf 'SUPPORTED_MUTATION_TARGET=YES\n'
    else
        printf 'SUPPORTED_MUTATION_TARGET=NO\n'
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
    printf 'RESTORE_GATE=PASS\n'
}

case "$command_name" in
    audit) audit_device ;;
    download-projectivy) download_projectivy ;;
    download-aurora) download_aurora ;;
    backup) create_backup ;;
    apply) apply_changes ;;
    verify) verify_device ;;
    restore) restore_backup ;;
    *) usage >&2; fail "unknown command: $command_name" ;;
esac
