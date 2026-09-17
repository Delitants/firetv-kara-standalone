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
    mkdir -p "$fixture/bin" "$fixture/cache"
    printf 'fixture official Projectivy APK\n' > "$fixture/projectivy.apk"
    printf 'fixture official Aurora Store APK\n' > "$fixture/aurora.apk"
    printf 'fixture kara exploit ELF\n' > "$fixture/kara-exploit.arm"
    printf 'fixture experimental kara exploit ELF\n' > "$fixture/kara-experimental.arm"
    printf 'package:com.amazon.tv.launcher\npackage:com.amazon.firehomestarter\npackage:com.amazon.device.software.ota\n' > "$fixture/active.packages"
    printf 'com.amazon.tv.launcher\ncom.amazon.firehomestarter\ncom.amazon.device.software.ota\n' > "$fixture/remove-user0.txt"
    printf 'com.amazon.vizzini\n' > "$fixture/remove-privileged.txt"
    printf '0\n' > "$fixture/ota.state"
    printf '0\n' > "$fixture/cec.state"
    printf '0\n' > "$fixture/root.state"
    printf 'enabled\n' > "$fixture/amazon-launcher.state"
    printf 'enabled\n' > "$fixture/firehomestarter.state"
    printf '0035334210436\n' > "$fixture/build.state"
    printf '%s\n' "${FAKE_OTA_LIVE_PATH:-missing}" > "$fixture/ota-live-path.state"
    printf '%s\n' "${FAKE_OTA_HELD_PATH:-missing}" > "$fixture/ota-held-path.state"
    fixture_digest=$(shasum -a 256 "$fixture/projectivy.apk" | awk '{print $1}')
    fixture_exploit_digest=$(shasum -a 256 "$fixture/kara-exploit.arm" | awk '{print $1}')
    fixture_experimental_digest=$(shasum -a 256 "$fixture/kara-experimental.arm" | awk '{print $1}')
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
    cat > "$fixture/experimental-release.json" <<EOF
{"tag_name":"kara-experimental-newer-v1","assets":[{"name":"kara-ghostlock-experimental-newer.arm","browser_download_url":"https://github.com/Delitants/GhostLock/releases/download/kara-experimental-newer-v1/kara-ghostlock-experimental-newer.arm","digest":"sha256:$fixture_experimental_digest"}]}
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
    https://api.github.com/repos/Delitants/GhostLock/releases/tags/kara-experimental-newer-v1)
        cp "$FAKE_EXPERIMENTAL_RELEASE_JSON" "$out" ;;
    https://github.com/Delitants/GhostLock/releases/download/kara-experimental-newer-v1/kara-ghostlock-experimental-newer.arm)
        cp "$FAKE_EXPERIMENTAL_BINARY" "$out" ;;
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
if [ "${FAKE_APKSIGNER_FORMAT:-legacy}" = build-tools-37 ]; then
    cat >&2 <<'OUT'
WARNING: A restricted method in java.lang.System has been called
WARNING: java.lang.System::loadLibrary has been called by org.conscrypt.NativeLibraryUtil in an unnamed module
OUT
    signer_prefix='V2 Signer:'
else
    signer_prefix='Signer #1'
fi
case "$*" in
*aurora.apk.part)
    printf '%s certificate DN: CN=Rahul Patel, C=IN\n' "$signer_prefix"
    printf '%s certificate SHA-256 digest: 4c626157ad02bda3401a7263555f68a79663fc3e13a4d4369a12570941aa280f\n' "$signer_prefix"
;;
*)
    printf '%s certificate DN: CN=Despesse Mickael, L=Villeurbanne, C=FR\n' "$signer_prefix"
    printf '%s certificate SHA-256 digest: f6697bf4082ee97511e4de07863193884a015b7ab5860430321bda1042b0aadd\n' "$signer_prefix"
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
    'shell getprop ro.build.version.incremental')
        if [ -n "${FAKE_BUILD:-}" ]; then printf '%s\n' "$FAKE_BUILD"; else cat "$FAKE_BUILD_STATE"; fi ;;
    'shell getprop ro.build.version.sdk') printf '%s\n' "${FAKE_API:-28}" ;;
    'shell getprop ro.build.fingerprint') printf 'Amazon/kara/kara:9/PS7713/0035334210436:user/release-keys\n' ;;
    'shell getprop ro.boot.verifiedbootstate') printf 'green\n' ;;
    'shell getprop ro.boot.flash.locked') printf '1\n' ;;
    'shell getprop ro.product.cpu.abi') printf '%s\n' "${FAKE_ABI:-armeabi-v7a}" ;;
    'shell uname -m') printf '%s\n' "${FAKE_MACHINE:-armv7l}" ;;
    'shell uname -r') printf '%s\n' "${FAKE_KERNEL:-4.14.87+}" ;;
    'shell getconf _NPROCESSORS_ONLN') printf 'getconf: not found\n' >&2; exit 127 ;;
    'shell cat /sys/devices/system/cpu/online') printf '%s\n' "${FAKE_CPU_ONLINE:-0-3}" ;;
    'shell id -u') printf '%s\n' "${FAKE_UID:-2000}" ;;
    'shell getenforce') printf '%s\n' "${FAKE_SELINUX:-Enforcing}" ;;
    'shell cat /proc/sys/kernel/random/boot_id') printf '11111111-2222-3333-4444-555555555555\n' ;;
    'shell cmd package resolve-activity --brief --components --user 0 -a android.intent.action.MAIN -c android.intent.category.HOME')
        if [ "$(cat "$FAKE_AMAZON_LAUNCHER_STATE")" = enabled ] &&
            grep -Fx 'package:com.amazon.tv.launcher' "$FAKE_ACTIVE_PACKAGES" >/dev/null; then
            printf 'com.amazon.tv.launcher/.ui.HomeActivity_vNext\n'
        elif [ "$(cat "$FAKE_FIREHOMESTARTER_STATE")" = enabled ] &&
            grep -Fx 'package:com.amazon.firehomestarter' "$FAKE_ACTIVE_PACKAGES" >/dev/null; then
            printf 'com.amazon.firehomestarter/.HomeStarterActivity\n'
        elif [ -s "$FAKE_HOME_STATE" ]; then cat "$FAKE_HOME_STATE"
        else printf '%s\n' "${FAKE_HOME:-com.amazon.tv.launcher/.ui.HomeActivity_vNext}"; fi ;;
    'shell pm list packages --user 0') cat "$FAKE_ACTIVE_PACKAGES" ;;
    'shell pm list packages -d --user 0')
        if [ "$(cat "$FAKE_AMAZON_LAUNCHER_STATE")" = disabled ] &&
            grep -Fx 'package:com.amazon.tv.launcher' "$FAKE_ACTIVE_PACKAGES" >/dev/null; then
            printf 'package:com.amazon.tv.launcher\n'
        fi
        if [ "$(cat "$FAKE_FIREHOMESTARTER_STATE")" = disabled ] &&
            grep -Fx 'package:com.amazon.firehomestarter' "$FAKE_ACTIVE_PACKAGES" >/dev/null; then
            printf 'package:com.amazon.firehomestarter\n'
        fi ;;
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
    push\ *\ /data/local/tmp/kara-ghostlock-[0-9]*) printf '1 file pushed\n' ;;
    push\ *\ /data/local/tmp/kara-ghostlock-experimental-[0-9]*) printf '1 file pushed\n' ;;
    shell\ chmod\ 700\ /data/local/tmp/kara-ghostlock-[0-9]*) : ;;
    shell\ chmod\ 700\ /data/local/tmp/kara-ghostlock-experimental-[0-9]*) : ;;
    shell\ /data/local/tmp/kara-ghostlock-[0-9]*\ --probe)
        printf 'V2 SAFE PROBE PASS (reclaim and GhostLock were not invoked)\n' >&2 ;;
    shell\ /data/local/tmp/kara-ghostlock-experimental-[0-9]*\ --probe-newer\ *)
        requested=${4-}
        actual=$(cat "$FAKE_BUILD_STATE")
        [ "$requested" = "$actual" ] || exit 3
        printf 'KARA_EXPERIMENTAL_NEWER_PROBE=PASS build=%s\n' "$actual" ;;
    shell\ nohup\ /data/local/tmp/kara-ghostlock-[0-9]*\ --live\ RUN-KARA-PS7713-GHOSTLOCK-V2*)
        if [ -n "${FAKE_BUILD_AFTER_LIVE:-}" ]; then printf '%s\n' "$FAKE_BUILD_AFTER_LIVE" > "$FAKE_BUILD_STATE"; fi
        if [ "${FAKE_EXPLOIT_ROOT_EFFECT:-1}" = 1 ]; then printf '1\n' > "$FAKE_ROOT_STATE"; fi ;;
    shell\ nohup\ /data/local/tmp/kara-ghostlock-experimental-[0-9]*\ --live-newer\ *)
        if [ "${FAKE_EXPLOIT_ROOT_EFFECT:-1}" = 1 ]; then printf '1\n' > "$FAKE_ROOT_STATE"; fi ;;
    'shell cmd package set-home-activity com.spocky.projengmenu/.ui.home.MainActivity')
        if [ "${FAKE_SET_HOME_EFFECT:-1}" = 1 ]; then
            printf 'com.spocky.projengmenu/.ui.home.MainActivity\n' > "$FAKE_HOME_STATE"
        fi ;;
    'shell am start -W --user 0 -n com.spocky.projengmenu/.ui.home.MainActivity')
        printf 'Status: ok\nActivity: com.spocky.projengmenu/.ui.home.MainActivity\n' ;;
    'shell am start -W --user 0 -a android.intent.action.MAIN -c android.intent.category.HOME') : ;;
    shell\ pm\ uninstall\ -k\ --user\ 0\ com.amazon.*)
        package=${7-}
        if [ "$package" = "${FAKE_STICKY_PACKAGE:-}" ]; then printf 'Failure\n'; exit 1; fi
        grep -Fvx "package:$package" "$FAKE_ACTIVE_PACKAGES" > "$FAKE_ACTIVE_PACKAGES.next" || true
        mv "$FAKE_ACTIVE_PACKAGES.next" "$FAKE_ACTIVE_PACKAGES"
        printf 'Success\n' ;;
    shell\ /data/local/tmp/*\ --cmd\ *)
        if [ "$#" -ne 2 ]; then
            printf 'root helper command was not quoted as one remote shell argument\n' >&2
            exit 64
        fi
        case "$*" in *kara-root-helper*) root_ready=1 ;; *) root_ready=$(cat "$FAKE_ROOT_STATE") ;; esac
        if [ "$root_ready" != 1 ]; then
            printf 'connect kara root socket: No such file or directory\n' >&2
            exit 2
        fi
        helper_path=$(printf '%s\n' "$*" | sed -n 's#^shell \(/data/local/tmp/[^ ]*\) --cmd.*#\1#p')
        case "$*" in
            *'EMPTY_OTA_COLLISION_CLEARED'*)
                live_state=$(cat "$FAKE_OTA_LIVE_PATH_STATE")
                held_state=$(cat "$FAKE_OTA_HELD_PATH_STATE")
                if [ "$live_state" = empty ] && [ "$held_state" != missing ]; then
                    printf 'missing\n' > "$FAKE_OTA_LIVE_PATH_STATE"
                    printf 'EMPTY_OTA_COLLISION_CLEARED\n'
                elif [ "$live_state" = nonempty ]; then
                    printf 'NONEMPTY_OTA_LIVE_PATH\n'
                fi ;;
            *'PRESENT:/data/ota_package'*)
                [ "$(cat "$FAKE_OTA_LIVE_PATH_STATE")" = missing ] ||
                    printf 'PRESENT:/data/ota_package\n' ;;
            *'runcon u:r:shell:s0 /system/bin/pm uninstall -k --user 0 com.amazon.vizzini'*)
                grep -Fvx 'package:com.amazon.vizzini' "$FAKE_ACTIVE_PACKAGES" > "$FAKE_ACTIVE_PACKAGES.next" || true
                mv "$FAKE_ACTIVE_PACKAGES.next" "$FAKE_ACTIVE_PACKAGES"
                printf 'Success\n' ;;
            *'runcon u:r:shell:s0 /system/bin/pm disable --user 0 com.amazon.tv.launcher'*)
                printf 'disabled\n' > "$FAKE_AMAZON_LAUNCHER_STATE"
                printf 'Package com.amazon.tv.launcher new state: disabled\n' ;;
            *'runcon u:r:shell:s0 /system/bin/pm disable --user 0 com.amazon.firehomestarter'*)
                printf 'disabled\n' > "$FAKE_FIREHOMESTARTER_STATE"
                printf 'Package com.amazon.firehomestarter new state: disabled\n' ;;
            *'runcon u:r:shell:s0 /system/bin/cmd package set-home-activity --user 0 com.spocky.projengmenu/.ui.home.MainActivity'*)
                if [ "${FAKE_SET_HOME_EFFECT:-1}" = 1 ]; then
                    printf 'com.spocky.projengmenu/.ui.home.MainActivity\n' > "$FAKE_HOME_STATE"
                fi
                printf 'Success\n' ;;
            *'runcon u:r:shell:s0 /system/bin/pm uninstall -k --user 0 com.amazon.tv.launcher'*)
                [ "${FAKE_ROOT_UNINSTALL_FAIL_PACKAGE:-}" != com.amazon.tv.launcher ] || exit 1
                grep -Fvx 'package:com.amazon.tv.launcher' "$FAKE_ACTIVE_PACKAGES" > "$FAKE_ACTIVE_PACKAGES.next" || true
                mv "$FAKE_ACTIVE_PACKAGES.next" "$FAKE_ACTIVE_PACKAGES"
                printf 'Success\n' ;;
            *'runcon u:r:shell:s0 /system/bin/pm uninstall -k --user 0 com.amazon.firehomestarter'*)
                [ "${FAKE_ROOT_UNINSTALL_FAIL_PACKAGE:-}" != com.amazon.firehomestarter ] || exit 1
                grep -Fvx 'package:com.amazon.firehomestarter' "$FAKE_ACTIVE_PACKAGES" > "$FAKE_ACTIVE_PACKAGES.next" || true
                mv "$FAKE_ACTIVE_PACKAGES.next" "$FAKE_ACTIVE_PACKAGES"
                printf 'Success\n' ;;
            *'runcon u:r:shell:s0 /system/bin/cmd package install-existing --user 0 com.amazon.tv.launcher'*)
                if [ "${FAKE_ROOT_RESTORE_EFFECT:-1}" = 1 ]; then
                    grep -Fx 'package:com.amazon.tv.launcher' "$FAKE_ACTIVE_PACKAGES" >/dev/null ||
                        printf 'package:com.amazon.tv.launcher\n' >> "$FAKE_ACTIVE_PACKAGES"
                fi
                printf 'Package installed\n' ;;
            *'runcon u:r:shell:s0 /system/bin/cmd package install-existing --user 0 com.amazon.firehomestarter'*)
                if [ "${FAKE_ROOT_RESTORE_EFFECT:-1}" = 1 ]; then
                    grep -Fx 'package:com.amazon.firehomestarter' "$FAKE_ACTIVE_PACKAGES" >/dev/null ||
                        printf 'package:com.amazon.firehomestarter\n' >> "$FAKE_ACTIVE_PACKAGES"
                fi
                printf 'Package installed\n' ;;
            *'runcon u:r:shell:s0 /system/bin/pm enable --user 0 com.amazon.tv.launcher'*)
                printf 'enabled\n' > "$FAKE_AMAZON_LAUNCHER_STATE"
                printf 'Package com.amazon.tv.launcher new state: enabled\n' ;;
            *'runcon u:r:shell:s0 /system/bin/pm enable --user 0 com.amazon.firehomestarter'*)
                printf 'enabled\n' > "$FAKE_FIREHOMESTARTER_STATE"
                printf 'Package com.amazon.firehomestarter new state: enabled\n' ;;
            *'runcon u:r:shell:s0 /system/bin/cmd package set-home-activity --user 0 com.amazon.tv.launcher/.ui.HomeActivity_vNext'*)
                printf 'com.amazon.tv.launcher/.ui.HomeActivity_vNext\n' > "$FAKE_HOME_STATE"
                printf 'Success\n' ;;
            *'id; cat /data/local/tmp/kara-root-ready'*)
                printf '%s\n' "${FAKE_ROOT_ID_LINE:-uid=0(root) gid=0(root) context=u:r:kernel:s0}"
                current_build=$(cat "$FAKE_BUILD_STATE")
                case "$helper_path" in
                    *kara-ghostlock-experimental-*) mode=' mode=experimental-newer' ;;
                    *) mode= ;;
                esac
                printf 'ROOTED uid=0 euid=0 context=u:r:kernel:s0 enforce=0 build=%s%s\n' "$current_build" "$mode" ;;
            *'/proc/\$PPID/exe'*'DAEMON_EXE='*)
                daemon_path=${FAKE_DAEMON_PATH:-$helper_path}
                [ "$daemon_path" = "$helper_path" ] && printf 'DAEMON_EXE=%s\n' "$daemon_path" ;;
            *'DAEMON_EXE='*)
                # A scan of every process sees the waiting client itself and
                # cannot distinguish it from the socket-owning daemon.
                printf 'DAEMON_EXE=%s\n' "$helper_path" ;;
            *) printf 'unexpected root helper command\n' >&2; exit 65 ;;
        esac ;;
    'shell settings get global ota_disable_automatic_update') cat "$FAKE_OTA_STATE" ;;
    'shell settings put global ota_disable_automatic_update 1') printf '1\n' > "$FAKE_OTA_STATE" ;;
    'shell settings get secure block_cec_standby') cat "$FAKE_CEC_STATE" ;;
    'shell settings put secure block_cec_standby 1') printf '1\n' > "$FAKE_CEC_STATE" ;;
    'shell settings put secure block_cec_standby 0') printf '0\n' > "$FAKE_CEC_STATE" ;;
    'shell settings delete secure block_cec_standby') printf 'null\n' > "$FAKE_CEC_STATE" ;;
    'shell cmd package install-existing --user 0 com.amazon.'*) printf 'Package installed\n' ;;
    'shell cmd package set-home-activity com.amazon.tv.launcher/.ui.HomeActivity_vNext') : ;;
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
    HOME="${TEST_HOME:-$HOME}" PATH="$fixture/bin:$PATH" \
    CURL="${TEST_CURL:-$fixture/bin/curl}" AAPT="${TEST_AAPT:-$fixture/bin/aapt}" \
    APKSIGNER="${TEST_APKSIGNER:-$fixture/bin/apksigner}" ADB="${TEST_ADB:-$fixture/bin/adb}" \
    FAKE_RELEASE_JSON="$fixture/release.json" \
    FAKE_PROJECTIVY_APK="$fixture/projectivy.apk" \
    FAKE_AURORA_RELEASE_JSON="$fixture/aurora-release.json" \
    FAKE_AURORA_APK="$fixture/aurora.apk" \
    FAKE_EXPLOIT_RELEASE_JSON="$fixture/exploit-release.json" \
    FAKE_EXPLOIT_BINARY="$fixture/kara-exploit.arm" \
    FAKE_EXPERIMENTAL_RELEASE_JSON="$fixture/experimental-release.json" \
    FAKE_EXPERIMENTAL_BINARY="$fixture/kara-experimental.arm" \
    FAKE_ADB_LOG="$fixture/adb.log" \
    FAKE_BRIDGE_LOG="$fixture/bridge.log" \
    FAKE_HOME_STATE="$fixture/home.state" \
    FAKE_ACTIVE_PACKAGES="$fixture/active.packages" \
    FAKE_OTA_STATE="$fixture/ota.state" \
    FAKE_CEC_STATE="$fixture/cec.state" \
    FAKE_ROOT_STATE="$fixture/root.state" \
    FAKE_AMAZON_LAUNCHER_STATE="$fixture/amazon-launcher.state" \
    FAKE_FIREHOMESTARTER_STATE="$fixture/firehomestarter.state" \
    FAKE_BUILD_STATE="$fixture/build.state" \
    FAKE_OTA_LIVE_PATH_STATE="$fixture/ota-live-path.state" \
    FAKE_OTA_HELD_PATH_STATE="$fixture/ota-held-path.state" \
    KARA_REMOVE_MANIFEST="$fixture/remove-user0.txt" \
    KARA_PRIVILEGED_MANIFEST="$fixture/remove-privileged.txt" \
    KARA_EXPLOIT_EXPECTED_SHA256="$fixture_exploit_digest" \
    KARA_EXPERIMENTAL_EXPECTED_SHA256="$fixture_experimental_digest" \
    KARA_ROOT_WAIT_ATTEMPTS=1 \
    KARA_CACHE_DIR="$fixture/cache" KARA_BACKUP_DIR="$fixture/backups" \
    "$tool" "$@"
}

test_expands_home_relative_build_tool_paths() {
    new_fixture
    mkdir -p "$fixture/home/tools"
    cp "$fixture/bin/adb" "$fixture/home/tools/adb"
    cp "$fixture/bin/curl" "$fixture/home/tools/curl"
    cp "$fixture/bin/aapt" "$fixture/home/tools/aapt"
    cp "$fixture/bin/apksigner" "$fixture/home/tools/apksigner"
    # These literal tildes exercise the tool's explicit home expansion.
    # shellcheck disable=SC2088
    if output=$(TEST_HOME="$fixture/home" TEST_ADB='~/tools/adb' \
        TEST_CURL='~/tools/curl' TEST_AAPT='~/tools/aapt' \
        TEST_APKSIGNER='~/tools/apksigner' run_tool download-projectivy 2>&1) &&
        audit=$(TEST_HOME="$fixture/home" TEST_ADB='~/tools/adb' \
        TEST_CURL='~/tools/curl' TEST_AAPT='~/tools/aapt' \
        TEST_APKSIGNER='~/tools/apksigner' run_tool audit 2>&1) &&
        printf '%s\n' "$output" | grep -F 'PROJECTIVY_VERSION=4.71' >/dev/null &&
        printf '%s\n' "$audit" | grep -F 'SUPPORTED_EXPLOIT_TARGET=YES' >/dev/null
    then
        ok 'expands leading home shorthand in build-tool paths'
    else
        not_ok 'expands leading home shorthand in build-tool paths'; printf '%s\n' "$output"
    fi
    rm -rf "$fixture"
}

test_apply_preflights_build_tools_before_device_or_root() {
    new_fixture
    missing_aapt="$fixture/missing-aapt"
    if TEST_AAPT="$missing_aapt" run_tool --yes apply >"$fixture/out" 2>&1
    then
        not_ok 'apply preflights build tools before device or root'
    elif grep -F "FAIL: $missing_aapt is required" "$fixture/out" >/dev/null &&
        ! grep -F 'BACKUP_DIR=' "$fixture/out" >/dev/null &&
        [ ! -s "$fixture/adb.log" ] &&
        [ ! -e "$fixture/backups" ]
    then
        ok 'apply preflights build tools before device or root'
    else
        not_ok 'apply preflights build tools before device or root'; cat "$fixture/out"; cat "$fixture/adb.log"
    fi
    rm -rf "$fixture"
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

test_downloads_and_verifies_experimental_exploit() {
    new_fixture
    if output=$(run_tool download-experimental 2>&1) &&
        [ -f "$fixture/cache/kara-ghostlock-experimental-newer.arm" ] &&
        printf '%s\n' "$output" | grep -F "KARA_EXPERIMENTAL_SHA256=$fixture_experimental_digest" >/dev/null
    then
        ok 'downloads and verifies the separate experimental exploit'
    else
        not_ok 'downloads and verifies the separate experimental exploit'; printf '%s\n' "$output"
    fi
    rm -rf "$fixture"
}

test_probe_newer_is_safe_and_restores_cec() {
    new_fixture
    printf '0035334219999\n' > "$fixture/build.state"
    if run_tool --newer-build 0035334219999 --yes probe-newer >"$fixture/out" 2>&1 &&
        grep -F 'EXPERIMENTAL_NEWER_PROBE=PASS build=0035334219999' "$fixture/out" >/dev/null &&
        grep -F 'UNVALIDATED_NEWER_FIRMWARE=YES' "$fixture/out" >/dev/null &&
        grep -F -- '--probe-newer 0035334219999' "$fixture/adb.log" >/dev/null &&
        ! grep -E -- '--live-newer|install -r|set-home-activity|pm uninstall|settings put global ota_' "$fixture/adb.log" >/dev/null &&
        [ "$(cat "$fixture/cec.state")" = 0 ] &&
        find "$fixture/backups" -type f -name state.env | grep . >/dev/null
    then
        ok 'newer-firmware probe is safe and restores the CEC guard'
    else
        not_ok 'newer-firmware probe is safe and restores the CEC guard'; cat "$fixture/out"; cat "$fixture/adb.log"
    fi
    rm -rf "$fixture"
}

test_probe_newer_rejects_nonnewer_or_mismatched_builds() {
    for requested in 0035334210436 0035334210000 0035334219998 malformed; do
        new_fixture
        printf '0035334219999\n' > "$fixture/build.state"
        if run_tool --newer-build "$requested" --yes probe-newer >"$fixture/out" 2>&1; then
            result=0
        else
            result=$?
        fi
        if [ "$result" -ne 0 ] &&
            ! grep -E 'push |settings put|--probe-newer|--live-newer|install -r|pm uninstall' "$fixture/adb.log" >/dev/null
        then
            ok "newer probe rejects unsafe build request $requested"
        else
            not_ok "newer probe rejects unsafe build request $requested"; cat "$fixture/out"; cat "$fixture/adb.log"
        fi
        rm -rf "$fixture"
    done
}

test_probe_newer_rejects_wrong_runtime_before_mutation() {
    new_fixture
    printf '0035334219999\n' > "$fixture/build.state"
    if FAKE_KERNEL=4.14.88 run_tool --newer-build 0035334219999 --yes probe-newer >"$fixture/out" 2>&1; then
        not_ok 'newer probe rejects wrong runtime before mutation'
    elif grep -F 'unsupported kernel release' "$fixture/out" >/dev/null &&
        ! grep -E 'push |settings put|--probe-newer|--live-newer' "$fixture/adb.log" >/dev/null
    then
        ok 'newer probe rejects wrong runtime before mutation'
    else
        not_ok 'newer probe rejects wrong runtime before mutation'; cat "$fixture/out"; cat "$fixture/adb.log"
    fi
    rm -rf "$fixture"
}

test_newer_live_requires_watchdog_acceptance() {
    new_fixture
    printf '0035334219999\n' > "$fixture/build.state"
    if run_tool --newer-build 0035334219999 --yes test-newer >"$fixture/out" 2>&1; then
        not_ok 'newer live test requires watchdog reboot acceptance'
    elif grep -F 'test-newer requires --accept-watchdog-reboot' "$fixture/out" >/dev/null &&
        ! grep -E 'push |settings put|--probe-newer|--live-newer' "$fixture/adb.log" >/dev/null
    then
        ok 'newer live test requires watchdog reboot acceptance'
    else
        not_ok 'newer live test requires watchdog reboot acceptance'; cat "$fixture/out"; cat "$fixture/adb.log"
    fi
    rm -rf "$fixture"
}

test_newer_live_only_attempts_root_and_restores_cec() {
    new_fixture
    printf '0035334219999\n' > "$fixture/build.state"
    if run_tool --newer-build 0035334219999 --accept-watchdog-reboot --yes test-newer >"$fixture/out" 2>&1; then
        probe_line=$(grep -n -- '--probe-newer 0035334219999' "$fixture/adb.log" | head -n 1 | cut -d: -f1)
        live_line=$(grep -n -- '--live-newer 0035334219999 RUN-KARA-EXPERIMENTAL-NEWER-I-ACCEPT-WATCHDOG-REBOOT' "$fixture/adb.log" | head -n 1 | cut -d: -f1)
        root_line=$(grep -n -- '--cmd' "$fixture/adb.log" | tail -n 1 | cut -d: -f1)
        if [ -n "$probe_line" ] && [ "$probe_line" -lt "$live_line" ] && [ "$live_line" -lt "$root_line" ] &&
            grep -F 'EXPERIMENTAL_NEWER_ROOT=PASS build=0035334219999' "$fixture/out" >/dev/null &&
            ! grep -E 'install -r|set-home-activity|pm uninstall|settings put global ota_' "$fixture/adb.log" >/dev/null &&
            [ "$(cat "$fixture/cec.state")" = 0 ]
        then
            ok 'newer live test only attempts root and restores the CEC guard'
        else
            not_ok 'newer live test only attempts root and restores the CEC guard'; cat "$fixture/out"; cat "$fixture/adb.log"
        fi
    else
        not_ok 'newer live test only attempts root and restores the CEC guard'; cat "$fixture/out"; cat "$fixture/adb.log"
    fi
    rm -rf "$fixture"
}

test_newer_root_failure_rolls_back_without_unrelated_mutation() {
    new_fixture
    printf '0035334219999\n' > "$fixture/build.state"
    if FAKE_EXPLOIT_ROOT_EFFECT=0 run_tool --newer-build 0035334219999 --accept-watchdog-reboot --yes test-newer >"$fixture/out" 2>&1; then
        not_ok 'newer root failure rolls back safely'
    elif grep -F 'experimental newer-firmware root was not obtained' "$fixture/out" >/dev/null &&
        grep -F 'AUTOMATIC_ROLLBACK=PASS' "$fixture/out" >/dev/null &&
        ! grep -E 'install -r|pm uninstall|settings put global ota_' "$fixture/adb.log" >/dev/null &&
        [ "$(cat "$fixture/cec.state")" = 0 ]
    then
        ok 'newer root failure rolls back without unrelated mutation'
    else
        not_ok 'newer root failure rolls back safely'; cat "$fixture/out"; cat "$fixture/adb.log"
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

test_resumes_verified_root_helper_while_selinux_is_permissive() {
    new_fixture
    printf 'package:com.amazon.vizzini\n' >> "$fixture/active.packages"
    if FAKE_SELINUX=Permissive run_tool \
        --root-helper /data/local/tmp/kara-root-helper --yes apply >"$fixture/out" 2>&1 &&
        grep -F 'TEMP_ROOT=PASS supplied-helper' "$fixture/out" >/dev/null &&
        ! grep -F -- '--live RUN-KARA-PS7713-GHOSTLOCK-V2' "$fixture/adb.log" >/dev/null
    then
        ok 'resumes a verified root helper while SELinux is permissive'
    else
        not_ok 'resumes a verified root helper while SELinux is permissive'; cat "$fixture/out"; cat "$fixture/adb.log"
    fi
    rm -rf "$fixture"
}

test_rejects_root_helper_that_is_not_daemon_parent() {
    new_fixture
    if FAKE_SELINUX=Permissive FAKE_DAEMON_PATH=/data/local/tmp/kara-ghostlock-other run_tool \
        --root-helper /data/local/tmp/kara-root-helper --yes apply >"$fixture/out" 2>&1
    then
        not_ok 'rejects a root helper that is not the daemon parent'
    elif grep -F 'supplied root helper did not prove temporary uid 0' "$fixture/out" >/dev/null &&
        ! grep -E -- '--live|BACKUP_DIR=|install -r|pm uninstall|set-home-activity|settings put' "$fixture/out" "$fixture/adb.log" >/dev/null
    then
        ok 'rejects a root helper that is not the daemon parent'
    else
        not_ok 'rejects a root helper that is not the daemon parent'; cat "$fixture/out"; cat "$fixture/adb.log"
    fi
    rm -rf "$fixture"
}

test_rejects_euid_only_root_helper_proof() {
    new_fixture
    if FAKE_SELINUX=Permissive \
        FAKE_ROOT_ID_LINE='uid=2000(shell) gid=2000(shell) euid=0(root)' \
        run_tool --root-helper /data/local/tmp/kara-root-helper --yes apply >"$fixture/out" 2>&1
    then
        not_ok 'rejects euid-only root helper proof'
    elif grep -F 'supplied root helper did not prove temporary uid 0' "$fixture/out" >/dev/null &&
        ! grep -E -- '--live|BACKUP_DIR=|install -r|pm uninstall|set-home-activity|settings put' "$fixture/out" "$fixture/adb.log" >/dev/null
    then
        ok 'rejects euid-only root helper proof'
    else
        not_ok 'rejects euid-only root helper proof'; cat "$fixture/out"; cat "$fixture/adb.log"
    fi
    rm -rf "$fixture"
}

test_clears_only_empty_live_ota_collision() {
    FAKE_OTA_LIVE_PATH=empty FAKE_OTA_HELD_PATH=empty new_fixture
    printf 'package:com.amazon.vizzini\n' >> "$fixture/active.packages"
    if FAKE_SELINUX=Permissive run_tool \
        --root-helper /data/local/tmp/kara-root-helper --yes apply >"$fixture/out" 2>&1 &&
        grep -F 'EMPTY_OTA_COLLISION_CLEARED=PASS' "$fixture/out" >/dev/null &&
        [ "$(cat "$fixture/ota-live-path.state")" = missing ] &&
        [ "$(cat "$fixture/ota-held-path.state")" = empty ] &&
        ! grep -F -- '--live RUN-KARA-PS7713-GHOSTLOCK-V2' "$fixture/adb.log" >/dev/null
    then
        ok 'clears only an empty live OTA collision and preserves held state'
    else
        not_ok 'clears only an empty live OTA collision and preserves held state'; cat "$fixture/out"; cat "$fixture/adb.log"
    fi
    rm -rf "$fixture"
}

test_refuses_nonempty_live_ota_collision() {
    FAKE_OTA_LIVE_PATH=nonempty FAKE_OTA_HELD_PATH=empty new_fixture
    if FAKE_SELINUX=Permissive run_tool \
        --root-helper /data/local/tmp/kara-root-helper --yes apply >"$fixture/out" 2>&1
    then
        not_ok 'refuses a non-empty live OTA collision'
    elif grep -F 'live OTA path is not empty; manual review required' "$fixture/out" >/dev/null &&
        [ "$(cat "$fixture/ota-live-path.state")" = nonempty ] &&
        [ "$(cat "$fixture/ota-held-path.state")" = empty ] &&
        [ "$(cat "$fixture/cec.state")" = 0 ] &&
        ! grep -E 'install -r|cmd package install-existing|pm (uninstall|disable|enable)|set-home-activity' "$fixture/adb.log" >/dev/null
    then
        ok 'refuses a non-empty live OTA collision before package mutation'
    else
        not_ok 'refuses a non-empty live OTA collision'; cat "$fixture/out"; cat "$fixture/adb.log"
    fi
    rm -rf "$fixture"
}

test_refuses_nonempty_live_ota_collision_after_new_root() {
    FAKE_OTA_LIVE_PATH=nonempty FAKE_OTA_HELD_PATH=empty new_fixture
    if run_tool --yes apply >"$fixture/out" 2>&1
    then
        not_ok 'refuses a non-empty live OTA collision after new root'
    elif grep -F 'live OTA path is not empty; manual review required' "$fixture/out" >/dev/null &&
        [ "$(cat "$fixture/ota-live-path.state")" = nonempty ] &&
        [ "$(cat "$fixture/ota-held-path.state")" = empty ] &&
        [ "$(cat "$fixture/cec.state")" = 0 ] &&
        ! grep -E 'install -r|cmd package install-existing|pm (uninstall|disable|enable)|set-home-activity' "$fixture/adb.log" >/dev/null
    then
        ok 'refuses a non-empty live OTA collision after new root before package mutation'
    else
        not_ok 'refuses a non-empty live OTA collision after new root'; cat "$fixture/out"; cat "$fixture/adb.log"
    fi
    rm -rf "$fixture"
}

test_apply_obtains_temporary_root_before_mutation() {
    new_fixture
    printf 'package:com.amazon.vizzini\n' >> "$fixture/active.packages"
    if run_tool --yes apply >"$fixture/out" 2>&1; then
        push_line=$(grep -n 'push .*kara-ghostlock-PS7713-5443.arm /data/local/tmp/kara-ghostlock-' "$fixture/adb.log" | head -n 1 | cut -d: -f1)
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

test_refuses_incompatible_exploit_runtime_before_mutation() {
    for runtime_case in abi cpus uid selinux; do
        new_fixture
        case "$runtime_case" in
            abi) FAKE_ABI=arm64-v8a run_tool --yes apply >"$fixture/out" 2>&1 && result=0 || result=$? ;;
            cpus) FAKE_CPU_ONLINE=0-7 run_tool --yes apply >"$fixture/out" 2>&1 && result=0 || result=$? ;;
            uid) FAKE_UID=0 run_tool --yes apply >"$fixture/out" 2>&1 && result=0 || result=$? ;;
            selinux) FAKE_SELINUX=Permissive run_tool --yes apply >"$fixture/out" 2>&1 && result=0 || result=$? ;;
        esac
        if [ "$result" -ne 0 ] &&
            ! grep -E 'push |--probe|--live|install -r|set-home-activity|pm uninstall|settings put' "$fixture/adb.log" >/dev/null
        then
            ok "refuses incompatible $runtime_case before mutation"
        else
            not_ok "refuses incompatible $runtime_case before mutation"; cat "$fixture/out"; cat "$fixture/adb.log"
        fi
        rm -rf "$fixture"
    done
}

test_stops_if_firmware_changes_during_exploit() {
    new_fixture
    if FAKE_BUILD_AFTER_LIVE=0035334219999 run_tool --yes apply >"$fixture/out" 2>&1; then
        not_ok 'stops if firmware changes during exploit'
    elif grep -F 'unsupported firmware build: 0035334219999' "$fixture/out" >/dev/null &&
        ! grep -E 'install -r|pm uninstall' "$fixture/adb.log" >/dev/null
    then
        ok 'stops if firmware changes during exploit'
    else
        not_ok 'stops if firmware changes during exploit'; cat "$fixture/out"; cat "$fixture/adb.log"
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
        grep -E "push /tmp/kara-tool-[0-9]+-kara-ghostlock-PS7713-5443.arm /data/local/tmp/kara-ghostlock-[0-9]+" "$fixture/adb.log" >/dev/null &&
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
    if FAKE_STICKY_PACKAGE=com.amazon.device.software.ota run_tool --yes apply >"$fixture/out" 2>&1; then
        not_ok 'fails when requested package remains active'
    elif grep -F 'removed package is active: com.amazon.device.software.ota' "$fixture/out" >/dev/null &&
        grep -F 'cmd package install-existing --user 0 com.amazon.device.software.ota' "$fixture/adb.log" >/dev/null &&
        grep -F 'set-home-activity --user 0 com.amazon.tv.launcher/.ui.HomeActivity' "$fixture/adb.log" >/dev/null
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

test_replaces_both_fire_os_home_blockers_under_root() {
    new_fixture
    if run_tool --root-helper /data/local/tmp/kara-root-helper --yes apply >"$fixture/out" 2>&1; then
        direct_line=$(grep -n 'am start -W --user 0 -n com.spocky.projengmenu/.ui.home.MainActivity' "$fixture/adb.log" | head -n 1 | cut -d: -f1)
        launcher_disable_line=$(grep -n 'pm disable --user 0 com.amazon.tv.launcher' "$fixture/adb.log" | head -n 1 | cut -d: -f1)
        starter_disable_line=$(grep -n 'pm disable --user 0 com.amazon.firehomestarter' "$fixture/adb.log" | head -n 1 | cut -d: -f1)
        home_line=$(grep -n 'cmd package set-home-activity --user 0 com.spocky.projengmenu/.ui.home.MainActivity' "$fixture/adb.log" | head -n 1 | cut -d: -f1)
        launcher_remove_line=$(grep -n 'pm uninstall -k --user 0 com.amazon.tv.launcher' "$fixture/adb.log" | head -n 1 | cut -d: -f1)
        starter_remove_line=$(grep -n 'pm uninstall -k --user 0 com.amazon.firehomestarter' "$fixture/adb.log" | head -n 1 | cut -d: -f1)
        if [ -n "$direct_line" ] && [ "$direct_line" -lt "$launcher_disable_line" ] &&
            [ "$launcher_disable_line" -lt "$home_line" ] && [ "$starter_disable_line" -lt "$home_line" ] &&
            [ "$home_line" -lt "$launcher_remove_line" ] && [ "$home_line" -lt "$starter_remove_line" ] &&
            ! grep -Fx 'package:com.amazon.tv.launcher' "$fixture/active.packages" >/dev/null &&
            ! grep -Fx 'package:com.amazon.firehomestarter' "$fixture/active.packages" >/dev/null
        then
            ok 'replaces both higher-priority Fire OS HOME blockers under root'
        else
            not_ok 'replaces both higher-priority Fire OS HOME blockers under root'; cat "$fixture/adb.log"
        fi
    else
        not_ok 'replaces both higher-priority Fire OS HOME blockers under root'; cat "$fixture/out"; cat "$fixture/adb.log"
    fi
    rm -rf "$fixture"
}

test_home_switch_failure_restores_fire_os_home_blockers() {
    new_fixture
    if FAKE_SET_HOME_EFFECT=0 run_tool --root-helper /data/local/tmp/kara-root-helper --yes apply >"$fixture/out" 2>&1; then
        not_ok 'HOME switch failure restores both Fire OS HOME blockers'
    elif grep -F 'Projectivy did not become HOME' "$fixture/out" >/dev/null &&
        grep -F 'AUTOMATIC_ROLLBACK=PASS' "$fixture/out" >/dev/null &&
        [ "$(cat "$fixture/amazon-launcher.state")" = enabled ] &&
        [ "$(cat "$fixture/firehomestarter.state")" = enabled ] &&
        grep -Fx 'package:com.amazon.tv.launcher' "$fixture/active.packages" >/dev/null &&
        grep -Fx 'package:com.amazon.firehomestarter' "$fixture/active.packages" >/dev/null &&
        grep -F 'pm enable --user 0 com.amazon.tv.launcher' "$fixture/adb.log" >/dev/null &&
        grep -F 'pm enable --user 0 com.amazon.firehomestarter' "$fixture/adb.log" >/dev/null &&
        grep -F 'cmd package set-home-activity --user 0 com.amazon.tv.launcher/.ui.HomeActivity' "$fixture/adb.log" >/dev/null
    then
        ok 'HOME switch failure restores both Fire OS HOME blockers'
    else
        not_ok 'HOME switch failure restores both Fire OS HOME blockers'; cat "$fixture/out"; cat "$fixture/adb.log"
    fi
    rm -rf "$fixture"
}

test_failure_after_home_blocker_removal_reinstalls_it() {
    new_fixture
    if FAKE_ROOT_UNINSTALL_FAIL_PACKAGE=com.amazon.firehomestarter \
        run_tool --root-helper /data/local/tmp/kara-root-helper --yes apply >"$fixture/out" 2>&1; then
        not_ok 'failure after HOME blocker removal reinstalls it'
    elif grep -F 'could not remove Fire OS HOME blocker: com.amazon.firehomestarter' "$fixture/out" >/dev/null &&
        grep -F 'AUTOMATIC_ROLLBACK=PASS' "$fixture/out" >/dev/null &&
        grep -Fx 'package:com.amazon.tv.launcher' "$fixture/active.packages" >/dev/null &&
        grep -Fx 'package:com.amazon.firehomestarter' "$fixture/active.packages" >/dev/null &&
        [ "$(cat "$fixture/amazon-launcher.state")" = enabled ] &&
        [ "$(cat "$fixture/firehomestarter.state")" = enabled ]
    then
        remove_line=$(grep -n 'pm uninstall -k --user 0 com.amazon.tv.launcher' "$fixture/adb.log" | head -n 1 | cut -d: -f1)
        install_line=$(grep -n 'cmd package install-existing --user 0 com.amazon.tv.launcher' "$fixture/adb.log" | tail -n 1 | cut -d: -f1)
        enable_line=$(grep -n 'pm enable --user 0 com.amazon.tv.launcher' "$fixture/adb.log" | tail -n 1 | cut -d: -f1)
        if [ -n "$remove_line" ] && [ "$remove_line" -lt "$install_line" ] && [ "$install_line" -lt "$enable_line" ]; then
            ok 'failure after HOME blocker removal reinstalls it'
        else
            not_ok 'failure after HOME blocker removal reinstalls it'; cat "$fixture/adb.log"
        fi
    else
        not_ok 'failure after HOME blocker removal reinstalls it'; cat "$fixture/out"; cat "$fixture/adb.log"
    fi
    rm -rf "$fixture"
}

test_rollback_fails_when_home_blocker_readback_is_wrong() {
    new_fixture
    if FAKE_ROOT_UNINSTALL_FAIL_PACKAGE=com.amazon.firehomestarter FAKE_ROOT_RESTORE_EFFECT=0 \
        run_tool --root-helper /data/local/tmp/kara-root-helper --yes apply >"$fixture/out" 2>&1; then
        not_ok 'rollback fails when HOME blocker readback is wrong'
    elif grep -F 'AUTOMATIC_ROLLBACK=FAIL' "$fixture/out" >/dev/null &&
        ! grep -F 'RESTORE_GATE=PASS' "$fixture/out" >/dev/null
    then
        ok 'rollback fails when HOME blocker readback is wrong'
    else
        not_ok 'rollback fails when HOME blocker readback is wrong'; cat "$fixture/out"; cat "$fixture/adb.log"
    fi
    rm -rf "$fixture"
}

test_restore_requires_root_for_backed_up_home_blockers() {
    new_fixture
    backup_output=$(run_tool backup)
    saved_backup=$(printf '%s\n' "$backup_output" | sed -n 's/^BACKUP_DIR=//p')
    if run_tool --backup "$saved_backup" --yes restore >"$fixture/out" 2>&1; then
        not_ok 'restore requires root for backed-up Fire OS HOME blockers'
    elif grep -F 'restore of Fire OS HOME blockers requires --root-helper' "$fixture/out" >/dev/null &&
        ! grep -E 'install-existing|set-home-activity|pm (disable|enable)' "$fixture/adb.log" >/dev/null
    then
        ok 'restore requires root for backed-up Fire OS HOME blockers'
    else
        not_ok 'restore requires root for backed-up Fire OS HOME blockers'; cat "$fixture/out"; cat "$fixture/adb.log"
    fi
    rm -rf "$fixture"
}

test_installs_kara_settings_before_home_switch() {
    new_fixture
    if run_tool --yes apply >"$fixture/out" 2>&1; then
        settings_line=$(grep -n 'install -r .*kara-settings-v5-signed.apk' "$fixture/adb.log" | head -n 1 | cut -d: -f1)
        home_line=$(grep -n 'set-home-activity --user 0 com.spocky.projengmenu' "$fixture/adb.log" | head -n 1 | cut -d: -f1)
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
        home_line=$(grep -n 'set-home-activity --user 0 com.spocky.projengmenu' "$fixture/adb.log" | head -n 1 | cut -d: -f1)
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

test_accepts_build_tools_37_signer_output() {
    new_fixture
    if projectivy_output=$(FAKE_APKSIGNER_FORMAT=build-tools-37 run_tool download-projectivy 2>&1) &&
        aurora_output=$(FAKE_APKSIGNER_FORMAT=build-tools-37 run_tool download-aurora 2>&1) &&
        [ -f "$fixture/cache/ProjectivyLauncher-4.71-c95-xda-release.apk" ] &&
        [ -f "$fixture/cache/AuroraStore-4.8.4.apk" ] &&
        printf '%s\n' "$projectivy_output" | grep -F "PROJECTIVY_SHA256=$fixture_digest" >/dev/null &&
        printf '%s\n' "$aurora_output" | grep -F 'AURORA_VERSION=4.8.4' >/dev/null
    then
        ok 'accepts Build Tools 37 signer output'
    else
        not_ok 'accepts Build Tools 37 signer output'
        printf '%s\n' "${projectivy_output-}" "${aurora_output-}"
    fi
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
        home_line=$(grep -n 'set-home-activity --user 0 com.spocky.projengmenu' "$fixture/adb.log" | head -n 1 | cut -d: -f1)
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

test_readme_documents_the_complete_workflow() {
    missing=0
    for phrase in 'Exact supported device' 'The exploit can reboot the Stick' \
        'Wi-Fi ADB quick start' 'USB through a Linux host' 'Root is temporary' \
        'Restore the backup' 'Complete exploit source' \
        'Carefully test a newer firmware' 'probe-newer' 'test-newer'; do
        grep -F "$phrase" "$repo/README.md" >/dev/null || missing=1
    done
    if [ "$missing" -eq 0 ]; then
        ok 'README documents the complete exploit workflow'
    else
        not_ok 'README documents the complete exploit workflow'
    fi
}

test_downloads_and_verifies_official_projectivy
test_downloads_and_verifies_official_aurora
test_expands_home_relative_build_tool_paths
test_apply_preflights_build_tools_before_device_or_root
test_downloads_and_verifies_kara_exploit
test_downloads_and_verifies_experimental_exploit
test_rejects_untrusted_kara_exploit_url
test_rejects_wrong_kara_exploit_asset_name
test_rejects_missing_kara_exploit_digest
test_rejects_unpinned_kara_exploit_digest
test_rejects_duplicate_kara_exploit_asset
test_apply_obtains_temporary_root_before_mutation
test_probe_newer_is_safe_and_restores_cec
test_probe_newer_rejects_nonnewer_or_mismatched_builds
test_probe_newer_rejects_wrong_runtime_before_mutation
test_newer_live_requires_watchdog_acceptance
test_newer_live_only_attempts_root_and_restores_cec
test_newer_root_failure_rolls_back_without_unrelated_mutation
test_refuses_wrong_kernel_before_exploit_or_mutation
test_refuses_incompatible_exploit_runtime_before_mutation
test_stops_if_firmware_changes_during_exploit
test_root_failure_aborts_before_package_mutation_and_rolls_back_cec
test_ssh_bridge_stages_every_local_payload
test_accepts_build_tools_37_signer_output
test_rejects_nonofficial_projectivy_url
test_refuses_wrong_model_before_mutation
test_requires_confirmation_before_mutation
test_installs_home_before_removing_amazon_packages
test_refuses_removal_when_projectivy_does_not_become_home
test_replaces_both_fire_os_home_blockers_under_root
test_home_switch_failure_restores_fire_os_home_blockers
test_failure_after_home_blocker_removal_reinstalls_it
test_rollback_fails_when_home_blocker_readback_is_wrong
test_restore_requires_root_for_backed_up_home_blockers
test_installs_kara_settings_before_home_switch
test_installs_aurora_before_home_switch
test_fails_when_aurora_install_has_no_package_effect
test_fails_when_requested_package_remains_active
test_uses_explicit_root_helper_for_protected_package
test_resumes_verified_root_helper_while_selinux_is_permissive
test_rejects_root_helper_that_is_not_daemon_parent
test_rejects_euid_only_root_helper_proof
test_clears_only_empty_live_ota_collision
test_refuses_nonempty_live_ota_collision
test_refuses_nonempty_live_ota_collision_after_new_root
test_manifests_are_scoped_and_disjoint
test_readme_documents_the_complete_workflow

printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
