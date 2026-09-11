#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
tool="$repo/scripts/kara-tool.sh"
pass=0
fail=0

ok() { printf 'ok - %s\n' "$1"; pass=$((pass + 1)); }
not_ok() { printf 'not ok - %s\n' "$1"; fail=$((fail + 1)); }

new_fixture() {
    fixture=$(mktemp -d "${TMPDIR:-/tmp}/kara-public-test.XXXXXX")
    mkdir -p "$fixture/bin" "$fixture/cache" "$fixture/backups"
    printf 'fixture official Projectivy APK\n' > "$fixture/projectivy.apk"
    printf 'fixture official Aurora Store APK\n' > "$fixture/aurora.apk"
    printf 'fixture kara exploit ELF\n' > "$fixture/kara-exploit.arm"
    printf 'package:com.amazon.tv.launcher\npackage:com.amazon.device.software.ota\n' > "$fixture/active.packages"
    printf 'com.amazon.tv.launcher\ncom.amazon.device.software.ota\n' > "$fixture/remove-user0.txt"
    printf 'com.amazon.vizzini\n' > "$fixture/remove-privileged.txt"
    printf '0\n' > "$fixture/ota.state"
    printf '0\n' > "$fixture/cec.state"
    printf '0\n' > "$fixture/root.state"
    fixture_digest=$(shasum -a 256 "$fixture/projectivy.apk" | awk '{print $1}')
    fixture_exploit_digest=$(shasum -a 256 "$fixture/kara-exploit.arm" | awk '{print $1}')
    exploit_duplicate=
    if [ "${FAKE_EXPLOIT_DUPLICATE:-0}" = 1 ]; then
        exploit_duplicate=',{"name":"kara-ghostlock-PS7713-5443.arm","browser_download_url":"https://github.com/Delitants/GhostLock/releases/download/kara-PS7713-5443-v1/kara-ghostlock-PS7713-5443.arm","digest":"sha256:'"$fixture_exploit_digest"'"}'
    fi
    cat > "$fixture/release.json" <<EOF
{"tag_name":"4.71","assets":[{"name":"ProjectivyLauncher-4.71-c95-xda-release.apk","browser_download_url":"${FAKE_RELEASE_URL:-https://github.com/spocky/miproja1/releases/download/4.71/ProjectivyLauncher-4.71-c95-xda-release.apk}","digest":"sha256:$fixture_digest"}]}
EOF
    cat > "$fixture/exploit-release.json" <<EOF
{"tag_name":"kara-PS7713-5443-v1","assets":[{"name":"${FAKE_EXPLOIT_ASSET_NAME:-kara-ghostlock-PS7713-5443.arm}","browser_download_url":"${FAKE_EXPLOIT_URL:-https://github.com/Delitants/GhostLock/releases/download/kara-PS7713-5443-v1/kara-ghostlock-PS7713-5443.arm}","digest":"${FAKE_EXPLOIT_DIGEST:-sha256:$fixture_exploit_digest}"}$exploit_duplicate]}
EOF
    cat > "$fixture/aurora-release.json" <<'EOF'
{"name":"downloads","path":"/downloads","isDirectory":true,"contents":[{"name":"AuroraStore","path":"/downloads/AuroraStore","isDirectory":true,"contents":[{"name":"Release","path":"/downloads/AuroraStore/Release","isDirectory":true,"contents":[{"name":"AuroraStore-4.8.4.apk","path":"/downloads/AuroraStore/Release/AuroraStore-4.8.4.apk","isDirectory":false,"mimeType":"application/vnd.android.package-archive","size":9362660}]}]}]}
EOF
    : > "$fixture/adb.log"
    : > "$fixture/bridge.log"

    cat > "$fixture/bin/curl" <<'EOF'
#!/bin/sh
set -eu
out=
url=
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o) out=$2; shift 2 ;;
        -*) shift ;;
        *) url=$1; shift ;;
    esac
done
case "$url" in
    https://api.github.com/repos/spocky/miproja1/releases/latest)
        cp "$FAKE_RELEASE_JSON" "$out" ;;
    https://github.com/spocky/miproja1/releases/download/*)
        cp "$FAKE_PROJECTIVY_APK" "$out" ;;
    https://auroraoss.com/api/files)
        cp "$FAKE_AURORA_RELEASE_JSON" "$out" ;;
    https://auroraoss.com/downloads/AuroraStore/Release/AuroraStore-*.apk)
        cp "$FAKE_AURORA_APK" "$out" ;;
    https://api.github.com/repos/Delitants/GhostLock/releases/tags/kara-PS7713-5443-v1)
        cp "$FAKE_EXPLOIT_RELEASE_JSON" "$out" ;;
    https://github.com/Delitants/GhostLock/releases/download/kara-PS7713-5443-v1/kara-ghostlock-PS7713-5443.arm)
        cp "$FAKE_EXPLOIT_BINARY" "$out" ;;
    *) printf 'unexpected URL: %s\n' "$url" >&2; exit 90 ;;
esac
EOF

    cat > "$fixture/bin/aapt" <<'EOF'
#!/bin/sh
case "$*" in
*aurora.apk.part) cat <<'OUT'
package: name='com.aurora.store' versionCode='76' versionName='4.8.4'
sdkVersion:'23'
OUT
;;
*) cat <<'OUT'
package: name='com.spocky.projengmenu' versionCode='95' versionName='4.71'
sdkVersion:'23'
OUT
;;
esac
EOF

    cat > "$fixture/bin/apksigner" <<'EOF'
#!/bin/sh
case "$*" in
*aurora.apk.part) cat <<'OUT'
Signer #1 certificate DN: CN=Rahul Patel, C=IN
Signer #1 certificate SHA-256 digest: 4c626157ad02bda3401a7263555f68a79663fc3e13a4d4369a12570941aa280f
OUT
;;
*) cat <<'OUT'
Signer #1 certificate DN: CN=Despesse Mickael, L=Villeurbanne, C=FR
Signer #1 certificate SHA-256 digest: f6697bf4082ee97511e4de07863193884a015b7ab5860430321bda1042b0aadd
OUT
;;
esac
EOF

    cat > "$fixture/bin/adb" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "$FAKE_ADB_LOG"
if [ "${1-}" = -s ]; then shift 2; fi
case "$*" in
    get-state) printf 'device\n' ;;
    'shell getprop ro.product.device') printf '%s\n' "${FAKE_DEVICE:-kara}" ;;
    'shell getprop ro.product.model') printf '%s\n' "${FAKE_MODEL:-AFTKA}" ;;
    'shell getprop ro.build.version.incremental') printf '%s\n' "${FAKE_BUILD:-0035334210436}" ;;
    'shell getprop ro.build.version.sdk') printf '%s\n' "${FAKE_API:-28}" ;;
    'shell getprop ro.build.fingerprint') printf 'Amazon/kara/kara:9/PS7713/0035334210436:user/release-keys\n' ;;
    'shell getprop ro.boot.verifiedbootstate') printf 'green\n' ;;
    'shell getprop ro.boot.flash.locked') printf '1\n' ;;
    'shell getprop ro.product.cpu.abi') printf '%s\n' "${FAKE_ABI:-armeabi-v7a}" ;;
    'shell uname -m') printf '%s\n' "${FAKE_MACHINE:-armv7l}" ;;
    'shell uname -r') printf '%s\n' "${FAKE_KERNEL:-4.14.87+}" ;;
    'shell getconf _NPROCESSORS_ONLN') printf '%s\n' "${FAKE_CPUS:-4}" ;;
    'shell id -u') printf '2000\n' ;;
    'shell getenforce') printf 'Enforcing\n' ;;
    'shell cat /proc/sys/kernel/random/boot_id') printf '11111111-2222-3333-4444-555555555555\n' ;;
    'shell cmd package resolve-activity --brief --components --user 0 -a android.intent.action.MAIN -c android.intent.category.HOME')
        if [ -s "$FAKE_HOME_STATE" ]; then cat "$FAKE_HOME_STATE"
        else printf '%s\n' "${FAKE_HOME:-com.amazon.tv.launcher/.ui.HomeActivity}"; fi ;;
    'shell pm list packages --user 0') cat "$FAKE_ACTIVE_PACKAGES" ;;
    'shell pm list packages -d --user 0') : ;;
    install\ -r\ *ProjectivyLauncher*)
        printf 'package:com.spocky.projengmenu\n' >> "$FAKE_ACTIVE_PACKAGES"
        printf 'Success\n' ;;
    install\ -r\ *AuroraStore*)
        if [ "${FAKE_INSTALL_AURORA_EFFECT:-1}" = 1 ]; then
            printf 'package:com.aurora.store\n' >> "$FAKE_ACTIVE_PACKAGES"
        fi
        printf 'Success\n' ;;
    install\ -r\ *kara-settings-v5-signed.apk)
        printf 'package:local.kara.settingsredirector\n' >> "$FAKE_ACTIVE_PACKAGES"
        printf 'Success\n' ;;
    push\ *\ /data/local/tmp/kara-ghostlock-PS7713-5443.arm) printf '1 file pushed\n' ;;
    'shell chmod 700 /data/local/tmp/kara-ghostlock-PS7713-5443.arm') : ;;
    'shell /data/local/tmp/kara-ghostlock-PS7713-5443.arm --probe') printf 'KARA_V2_PROBE=PASS\n' ;;
    shell\ nohup\ /data/local/tmp/kara-ghostlock-PS7713-5443.arm\ --live\ RUN-KARA-PS7713-GHOSTLOCK-V2*)
        if [ "${FAKE_EXPLOIT_ROOT_EFFECT:-1}" = 1 ]; then printf '1\n' > "$FAKE_ROOT_STATE"; fi ;;
    'shell cmd package set-home-activity com.spocky.projengmenu/.ui.home.MainActivity')
        if [ "${FAKE_SET_HOME_EFFECT:-1}" = 1 ]; then
            printf 'com.spocky.projengmenu/.ui.home.MainActivity\n' > "$FAKE_HOME_STATE"
        fi ;;
    'shell am start -W --user 0 -a android.intent.action.MAIN -c android.intent.category.HOME') : ;;
    shell\ pm\ uninstall\ -k\ --user\ 0\ com.amazon.*)
        package=${7-}
        if [ "$package" = "${FAKE_STICKY_PACKAGE:-}" ]; then printf 'Failure\n'; exit 1; fi
        grep -Fvx "package:$package" "$FAKE_ACTIVE_PACKAGES" > "$FAKE_ACTIVE_PACKAGES.next" || true
        mv "$FAKE_ACTIVE_PACKAGES.next" "$FAKE_ACTIVE_PACKAGES"
        printf 'Success\n' ;;
    shell\ /data/local/tmp/*\ --cmd\ *)
        case "$*" in *kara-root-helper*) root_ready=1 ;; *) root_ready=$(cat "$FAKE_ROOT_STATE") ;; esac
        if [ "$root_ready" != 1 ]; then
            printf 'connect kara root socket: No such file or directory\n' >&2
            exit 2
        fi
        grep -Fvx 'package:com.amazon.vizzini' "$FAKE_ACTIVE_PACKAGES" > "$FAKE_ACTIVE_PACKAGES.next" || true
        mv "$FAKE_ACTIVE_PACKAGES.next" "$FAKE_ACTIVE_PACKAGES"
        printf 'uid=0(root) gid=0(root) context=u:r:kernel:s0\n'
        printf 'ROOTED uid=0 euid=0 context=u:r:kernel:s0 enforce=0 build=0035334210436\n' ;;
    'shell settings get global ota_disable_automatic_update') cat "$FAKE_OTA_STATE" ;;
    'shell settings put global ota_disable_automatic_update 1') printf '1\n' > "$FAKE_OTA_STATE" ;;
    'shell settings get secure block_cec_standby') cat "$FAKE_CEC_STATE" ;;
    'shell settings put secure block_cec_standby 1') printf '1\n' > "$FAKE_CEC_STATE" ;;
    'shell settings put secure block_cec_standby 0') printf '0\n' > "$FAKE_CEC_STATE" ;;
    'shell settings delete secure block_cec_standby') printf 'null\n' > "$FAKE_CEC_STATE" ;;
    'shell cmd package install-existing --user 0 com.amazon.'*) printf 'Package installed\n' ;;
    'shell cmd package set-home-activity com.amazon.tv.launcher/.ui.HomeActivity') : ;;
    *) : ;;
esac
EOF
    cat > "$fixture/bin/scp" <<'EOF'
#!/bin/sh
set -eu
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o) shift 2 ;;
        -q|--) shift ;;
        *) break ;;
    esac
done
[ "$#" -eq 2 ] || exit 91
source_file=$1
destination=$2
remote_file=${destination#*:}
printf 'scp %s %s\n' "$source_file" "$destination" >> "$FAKE_BRIDGE_LOG"
cp "$source_file" "$remote_file"
EOF
    cat > "$fixture/bin/ssh" <<'EOF'
#!/bin/sh
set -eu
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o) shift 2 ;;
        *) break ;;
    esac
done
host=$1
shift
printf 'ssh %s %s\n' "$host" "$*" >> "$FAKE_BRIDGE_LOG"
if [ "$#" -eq 1 ]; then
    sh -c "$1"
else
    "$@"
fi
EOF
    chmod +x "$fixture/bin/curl" "$fixture/bin/aapt" "$fixture/bin/apksigner" \
        "$fixture/bin/adb" "$fixture/bin/scp" "$fixture/bin/ssh"
}

run_tool() {
    PATH="$fixture/bin:$PATH" \
    CURL="$fixture/bin/curl" AAPT="$fixture/bin/aapt" \
    APKSIGNER="$fixture/bin/apksigner" ADB="$fixture/bin/adb" \
    FAKE_RELEASE_JSON="$fixture/release.json" \
    FAKE_PROJECTIVY_APK="$fixture/projectivy.apk" \
    FAKE_AURORA_RELEASE_JSON="$fixture/aurora-release.json" \
    FAKE_AURORA_APK="$fixture/aurora.apk" \
    FAKE_EXPLOIT_RELEASE_JSON="$fixture/exploit-release.json" \
    FAKE_EXPLOIT_BINARY="$fixture/kara-exploit.arm" \
    FAKE_ADB_LOG="$fixture/adb.log" \
    FAKE_BRIDGE_LOG="$fixture/bridge.log" \
    FAKE_HOME_STATE="$fixture/home.state" \
    FAKE_ACTIVE_PACKAGES="$fixture/active.packages" \
    FAKE_OTA_STATE="$fixture/ota.state" \
    FAKE_CEC_STATE="$fixture/cec.state" \
    FAKE_ROOT_STATE="$fixture/root.state" \
    KARA_REMOVE_MANIFEST="$fixture/remove-user0.txt" \
    KARA_PRIVILEGED_MANIFEST="$fixture/remove-privileged.txt" \
    KARA_EXPLOIT_EXPECTED_SHA256="$fixture_exploit_digest" \
    KARA_ROOT_WAIT_ATTEMPTS=1 \
    KARA_CACHE_DIR="$fixture/cache" KARA_BACKUP_DIR="$fixture/backups" \
    "$tool" "$@"
}

test_downloads_and_verifies_kara_exploit() {
    new_fixture
    if output=$(run_tool download-exploit 2>&1) &&
        [ -f "$fixture/cache/kara-ghostlock-PS7713-5443.arm" ] &&
        printf '%s\n' "$output" | grep -F "KARA_EXPLOIT_SHA256=$fixture_exploit_digest" >/dev/null
    then
        ok 'downloads and verifies the kara exploit'
    else
        not_ok 'downloads and verifies the kara exploit'; printf '%s\n' "$output"
    fi
    rm -rf "$fixture"
}

test_rejects_untrusted_kara_exploit_url() {
    FAKE_EXPLOIT_URL=https://evil.invalid/kara.arm new_fixture
    if run_tool download-exploit >"$fixture/out" 2>&1; then
        not_ok 'rejects untrusted kara exploit URL'
    elif grep -F 'untrusted kara exploit asset URL' "$fixture/out" >/dev/null; then
        ok 'rejects untrusted kara exploit URL'
    else
        not_ok 'rejects untrusted kara exploit URL'; cat "$fixture/out"
    fi
    rm -rf "$fixture"
}

test_rejects_wrong_kara_exploit_asset_name() {
    FAKE_EXPLOIT_ASSET_NAME=wrong.arm new_fixture
    if run_tool download-exploit >"$fixture/out" 2>&1; then
        not_ok 'rejects wrong kara exploit asset name'
    elif grep -F 'missing or ambiguous kara exploit asset' "$fixture/out" >/dev/null; then
        ok 'rejects wrong kara exploit asset name'
    else
        not_ok 'rejects wrong kara exploit asset name'; cat "$fixture/out"
    fi
    rm -rf "$fixture"
}

test_rejects_missing_kara_exploit_digest() {
    FAKE_EXPLOIT_DIGEST=missing new_fixture
    if run_tool download-exploit >"$fixture/out" 2>&1; then
        not_ok 'rejects missing kara exploit digest'
    elif grep -F 'missing a valid SHA-256 digest' "$fixture/out" >/dev/null; then
        ok 'rejects missing kara exploit digest'
    else
        not_ok 'rejects missing kara exploit digest'; cat "$fixture/out"
    fi
    rm -rf "$fixture"
}

test_rejects_unpinned_kara_exploit_digest() {
    FAKE_EXPLOIT_DIGEST=sha256:0000000000000000000000000000000000000000000000000000000000000000 new_fixture
    if run_tool download-exploit >"$fixture/out" 2>&1; then
        not_ok 'rejects unpinned kara exploit digest'
    elif grep -F 'does not match the live-tested artifact' "$fixture/out" >/dev/null; then
        ok 'rejects unpinned kara exploit digest'
    else
        not_ok 'rejects unpinned kara exploit digest'; cat "$fixture/out"
    fi
    rm -rf "$fixture"
}

test_rejects_duplicate_kara_exploit_asset() {
    FAKE_EXPLOIT_DUPLICATE=1 new_fixture
    if run_tool download-exploit >"$fixture/out" 2>&1; then
        not_ok 'rejects duplicate kara exploit asset'
    elif grep -F 'missing or ambiguous kara exploit asset' "$fixture/out" >/dev/null; then
        ok 'rejects duplicate kara exploit asset'
    else
        not_ok 'rejects duplicate kara exploit asset'; cat "$fixture/out"
    fi
    rm -rf "$fixture"
}

test_downloads_and_verifies_official_aurora() {
    new_fixture
    if output=$(run_tool download-aurora 2>&1) &&
        [ -f "$fixture/cache/AuroraStore-4.8.4.apk" ] &&
        printf '%s\n' "$output" | grep -F 'AURORA_VERSION=4.8.4' >/dev/null
    then ok 'downloads and verifies official Aurora Store'; else not_ok 'downloads and verifies official Aurora Store'; printf '%s\n' "$output"; fi
    rm -rf "$fixture"
}

test_uses_explicit_root_helper_for_protected_package() {
    new_fixture
    printf 'package:com.amazon.vizzini\n' >> "$fixture/active.packages"
    if run_tool --root-helper /data/local/tmp/kara-root-helper --yes apply >"$fixture/out" 2>&1 &&
        grep -F 'shell /data/local/tmp/kara-root-helper --cmd' "$fixture/adb.log" >/dev/null &&
        grep -F 'PRIVILEGED_REMOVAL=PASS' "$fixture/out" >/dev/null &&
        ! grep -Fx 'package:com.amazon.vizzini' "$fixture/active.packages" >/dev/null
    then
        ok 'uses explicit root helper for protected package'
    else
        not_ok 'uses explicit root helper for protected package'; cat "$fixture/out"; cat "$fixture/adb.log"
    fi
    rm -rf "$fixture"
}

test_apply_obtains_temporary_root_before_mutation() {
    new_fixture
    printf 'package:com.amazon.vizzini\n' >> "$fixture/active.packages"
    if run_tool --yes apply >"$fixture/out" 2>&1; then
        push_line=$(grep -n 'push .*kara-ghostlock-PS7713-5443.arm /data/local/tmp/kara-ghostlock-PS7713-5443.arm' "$fixture/adb.log" | head -n 1 | cut -d: -f1)
        probe_line=$(grep -n -- '--probe' "$fixture/adb.log" | head -n 1 | cut -d: -f1)
        live_line=$(grep -n -- '--live RUN-KARA-PS7713-GHOSTLOCK-V2' "$fixture/adb.log" | head -n 1 | cut -d: -f1)
        install_line=$(grep -n '^install -r ' "$fixture/adb.log" | head -n 1 | cut -d: -f1)
        if [ -n "$push_line" ] && [ "$push_line" -lt "$probe_line" ] &&
            [ "$probe_line" -lt "$live_line" ] && [ "$live_line" -lt "$install_line" ] &&
            grep -F 'TEMP_ROOT=PASS' "$fixture/out" >/dev/null &&
            grep -F 'PRIVILEGED_REMOVAL=PASS' "$fixture/out" >/dev/null
        then
            ok 'apply obtains temporary root before package mutation'
        else
            not_ok 'apply obtains temporary root before package mutation'; cat "$fixture/out"; cat "$fixture/adb.log"
        fi
    else
        not_ok 'apply obtains temporary root before package mutation'; cat "$fixture/out"; cat "$fixture/adb.log"
    fi
    rm -rf "$fixture"
}

test_refuses_wrong_kernel_before_exploit_or_mutation() {
    new_fixture
    if FAKE_KERNEL=4.14.88 run_tool --yes apply >"$fixture/out" 2>&1; then
        not_ok 'refuses wrong kernel before exploit or mutation'
    elif grep -F 'unsupported kernel release' "$fixture/out" >/dev/null &&
        ! grep -E 'push |--probe|--live|install -r|set-home-activity|pm uninstall|settings put' "$fixture/adb.log" >/dev/null
    then
        ok 'refuses wrong kernel before exploit or mutation'
    else
        not_ok 'refuses wrong kernel before exploit or mutation'; cat "$fixture/out"; cat "$fixture/adb.log"
    fi
    rm -rf "$fixture"
}

test_root_failure_aborts_before_package_mutation_and_rolls_back_cec() {
    new_fixture
    if FAKE_EXPLOIT_ROOT_EFFECT=0 run_tool --yes apply >"$fixture/out" 2>&1; then
        not_ok 'root failure aborts before package mutation'
    elif grep -F 'temporary root was not obtained' "$fixture/out" >/dev/null &&
        ! grep -E 'install -r|pm uninstall' "$fixture/adb.log" >/dev/null &&
        [ "$(cat "$fixture/cec.state")" = 0 ] &&
        grep -F 'AUTOMATIC_ROLLBACK=PASS' "$fixture/out" >/dev/null
    then
        ok 'root failure aborts before package mutation and rolls back CEC guard'
    else
        not_ok 'root failure aborts before package mutation'; cat "$fixture/out"; cat "$fixture/adb.log"
    fi
    rm -rf "$fixture"
}

test_ssh_bridge_stages_every_local_payload() {
    new_fixture
    if run_tool --bridge root@test --yes apply >"$fixture/out" 2>&1 &&
        [ "$(grep -c '^scp ' "$fixture/bridge.log")" -eq 4 ] &&
        grep -E "push /tmp/kara-tool-[0-9]+-kara-ghostlock-PS7713-5443.arm /data/local/tmp/" "$fixture/adb.log" >/dev/null &&
        [ "$(grep -c "install -r /tmp/kara-tool-" "$fixture/adb.log")" -eq 3 ] &&
        [ "$(grep -c "ssh root@test rm -f /tmp/kara-tool-" "$fixture/bridge.log")" -eq 4 ]
    then
        ok 'SSH bridge stages and cleans every local payload'
    else
        not_ok 'SSH bridge stages and cleans every local payload'; cat "$fixture/out"; cat "$fixture/bridge.log"; cat "$fixture/adb.log"
    fi
    rm -rf "$fixture"
}

test_fails_when_requested_package_remains_active() {
    new_fixture
    if FAKE_STICKY_PACKAGE=com.amazon.tv.launcher run_tool --yes apply >"$fixture/out" 2>&1; then
        not_ok 'fails when requested package remains active'
    elif grep -F 'removed package is active: com.amazon.tv.launcher' "$fixture/out" >/dev/null &&
        grep -F 'cmd package install-existing --user 0 com.amazon.tv.launcher' "$fixture/adb.log" >/dev/null &&
        grep -F 'set-home-activity com.amazon.tv.launcher/.ui.HomeActivity' "$fixture/adb.log" >/dev/null
    then
        ok 'fails when requested package remains active'
    else
        not_ok 'fails when requested package remains active'; cat "$fixture/out"
    fi
    rm -rf "$fixture"
}

test_refuses_removal_when_projectivy_does_not_become_home() {
    new_fixture
    if FAKE_SET_HOME_EFFECT=0 run_tool --yes apply >"$fixture/out" 2>&1; then
        not_ok 'refuses removal unless Projectivy becomes HOME'
    elif grep -F 'Projectivy did not become HOME' "$fixture/out" >/dev/null &&
        ! grep -F 'pm uninstall' "$fixture/adb.log" >/dev/null
    then ok 'refuses removal unless Projectivy becomes HOME'; else not_ok 'refuses removal unless Projectivy becomes HOME'; cat "$fixture/out"; cat "$fixture/adb.log"; fi
    rm -rf "$fixture"
}

test_installs_kara_settings_before_home_switch() {
    new_fixture
    if run_tool --yes apply >"$fixture/out" 2>&1; then
        settings_line=$(grep -n 'install -r .*kara-settings-v5-signed.apk' "$fixture/adb.log" | head -n 1 | cut -d: -f1)
        home_line=$(grep -n 'set-home-activity com.spocky.projengmenu' "$fixture/adb.log" | head -n 1 | cut -d: -f1)
        if [ -n "$settings_line" ] && [ "$settings_line" -lt "$home_line" ]; then
            ok 'installs Kara Settings before HOME switch'
        else
            not_ok 'installs Kara Settings before HOME switch'; cat "$fixture/adb.log"
        fi
    else
        not_ok 'installs Kara Settings before HOME switch'; cat "$fixture/out"
    fi
    rm -rf "$fixture"
}

test_installs_aurora_before_home_switch() {
    new_fixture
    if run_tool --yes apply >"$fixture/out" 2>&1; then
        aurora_line=$(grep -n 'install -r .*AuroraStore-4.8.4.apk' "$fixture/adb.log" | head -n 1 | cut -d: -f1)
        home_line=$(grep -n 'set-home-activity com.spocky.projengmenu' "$fixture/adb.log" | head -n 1 | cut -d: -f1)
        if [ -n "$aurora_line" ] && [ "$aurora_line" -lt "$home_line" ]; then
            ok 'installs Aurora Store before HOME switch'
        else
            not_ok 'installs Aurora Store before HOME switch'; cat "$fixture/adb.log"
        fi
    else
        not_ok 'installs Aurora Store before HOME switch'; cat "$fixture/out"
    fi
    rm -rf "$fixture"
}

test_fails_when_aurora_install_has_no_package_effect() {
    new_fixture
    if FAKE_INSTALL_AURORA_EFFECT=0 run_tool --yes apply >"$fixture/out" 2>&1; then
        not_ok 'fails when Aurora is absent after install'
    elif grep -F 'required package is not active: com.aurora.store' "$fixture/out" >/dev/null; then
        ok 'fails when Aurora is absent after install'
    else
        not_ok 'fails when Aurora is absent after install'; cat "$fixture/out"
    fi
    rm -rf "$fixture"
}

test_downloads_and_verifies_official_projectivy() {
    new_fixture
    if output=$(run_tool download-projectivy 2>&1) &&
        [ -f "$fixture/cache/ProjectivyLauncher-4.71-c95-xda-release.apk" ] &&
        printf '%s\n' "$output" | grep -F "PROJECTIVY_SHA256=$fixture_digest" >/dev/null
    then ok 'downloads and verifies official Projectivy'; else not_ok 'downloads and verifies official Projectivy'; printf '%s\n' "$output"; fi
    rm -rf "$fixture"
}

test_rejects_nonofficial_projectivy_url() {
    FAKE_RELEASE_URL=https://evil.invalid/Projectivy.apk new_fixture
    if run_tool download-projectivy >"$fixture/out" 2>&1; then
        not_ok 'rejects nonofficial Projectivy URL'
    elif grep -F 'untrusted Projectivy asset URL' "$fixture/out" >/dev/null; then
        ok 'rejects nonofficial Projectivy URL'
    else
        not_ok 'rejects nonofficial Projectivy URL'; cat "$fixture/out"
    fi
    unset FAKE_RELEASE_URL
    rm -rf "$fixture"
}

test_refuses_wrong_model_before_mutation() {
    new_fixture
    if FAKE_MODEL=AFTKRT run_tool --yes apply >"$fixture/out" 2>&1; then
        not_ok 'refuses wrong model before mutation'
    elif grep -F 'unsupported model' "$fixture/out" >/dev/null &&
        ! grep -E 'install -r|set-home-activity|pm uninstall|settings put' "$fixture/adb.log" >/dev/null
    then ok 'refuses wrong model before mutation'; else not_ok 'refuses wrong model before mutation'; cat "$fixture/out"; fi
    rm -rf "$fixture"
}

test_requires_confirmation_before_mutation() {
    new_fixture
    if run_tool apply >"$fixture/out" 2>&1; then
        not_ok 'requires confirmation before mutation'
    elif grep -F 'apply requires --yes' "$fixture/out" >/dev/null &&
        ! grep -E 'install -r|set-home-activity|pm uninstall|settings put' "$fixture/adb.log" >/dev/null
    then ok 'requires confirmation before mutation'; else not_ok 'requires confirmation before mutation'; cat "$fixture/out"; fi
    rm -rf "$fixture"
}

test_installs_home_before_removing_amazon_packages() {
    new_fixture
    if run_tool --yes apply >"$fixture/out" 2>&1; then
        install_line=$(grep -n '^install -r ' "$fixture/adb.log" | head -n 1 | cut -d: -f1)
        home_line=$(grep -n 'set-home-activity com.spocky.projengmenu' "$fixture/adb.log" | head -n 1 | cut -d: -f1)
        remove_line=$(grep -n 'pm uninstall -k --user 0 com.amazon' "$fixture/adb.log" | head -n 1 | cut -d: -f1)
        if [ -n "$install_line" ] && [ "$install_line" -lt "$home_line" ] && [ "$home_line" -lt "$remove_line" ] &&
            find "$fixture/backups" -type f -name state.env | grep . >/dev/null
        then ok 'installs Projectivy and selects HOME before removal'; else not_ok 'installs Projectivy and selects HOME before removal'; cat "$fixture/adb.log"; fi
    else
        not_ok 'installs Projectivy and selects HOME before removal'; cat "$fixture/out"
    fi
    rm -rf "$fixture"
}

test_manifests_are_scoped_and_disjoint() {
    if MANIFEST_ROOT="$repo/manifests" python3 "$repo/tests/verify-manifests.py"; then
        ok 'manifests are scoped and disjoint'
    else
        not_ok 'manifests are scoped and disjoint'
    fi
}

test_downloads_and_verifies_official_projectivy
test_downloads_and_verifies_official_aurora
test_downloads_and_verifies_kara_exploit
test_rejects_untrusted_kara_exploit_url
test_rejects_wrong_kara_exploit_asset_name
test_rejects_missing_kara_exploit_digest
test_rejects_unpinned_kara_exploit_digest
test_rejects_duplicate_kara_exploit_asset
test_apply_obtains_temporary_root_before_mutation
test_refuses_wrong_kernel_before_exploit_or_mutation
test_root_failure_aborts_before_package_mutation_and_rolls_back_cec
test_ssh_bridge_stages_every_local_payload
test_rejects_nonofficial_projectivy_url
test_refuses_wrong_model_before_mutation
test_requires_confirmation_before_mutation
test_installs_home_before_removing_amazon_packages
test_refuses_removal_when_projectivy_does_not_become_home
test_installs_kara_settings_before_home_switch
test_installs_aurora_before_home_switch
test_fails_when_aurora_install_has_no_package_effect
test_fails_when_requested_package_remains_active
test_uses_explicit_root_helper_for_protected_package
test_manifests_are_scoped_and_disjoint

printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
