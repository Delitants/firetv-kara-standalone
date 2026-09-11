#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
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
    printf 'package:com.amazon.tv.launcher\npackage:com.amazon.device.software.ota\n' > "$fixture/active.packages"
    printf 'com.amazon.tv.launcher\ncom.amazon.device.software.ota\n' > "$fixture/remove-user0.txt"
    printf 'com.amazon.vizzini\n' > "$fixture/remove-privileged.txt"
    printf '0\n' > "$fixture/ota.state"
    fixture_digest=$(shasum -a 256 "$fixture/projectivy.apk" | awk '{print $1}')
    cat > "$fixture/release.json" <<EOF
{"tag_name":"4.71","assets":[{"name":"ProjectivyLauncher-4.71-c95-xda-release.apk","browser_download_url":"${FAKE_RELEASE_URL:-https://github.com/spocky/miproja1/releases/download/4.71/ProjectivyLauncher-4.71-c95-xda-release.apk}","digest":"sha256:$fixture_digest"}]}
EOF
    cat > "$fixture/aurora-release.json" <<'EOF'
{"name":"downloads","path":"/downloads","isDirectory":true,"contents":[{"name":"AuroraStore","path":"/downloads/AuroraStore","isDirectory":true,"contents":[{"name":"Release","path":"/downloads/AuroraStore/Release","isDirectory":true,"contents":[{"name":"AuroraStore-4.8.4.apk","path":"/downloads/AuroraStore/Release/AuroraStore-4.8.4.apk","isDirectory":false,"mimeType":"application/vnd.android.package-archive","size":9362660}]}]}]}
EOF
    : > "$fixture/adb.log"

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
    shell\ /data/local/tmp/kara-root-helper\ --cmd\ *)
        grep -Fvx 'package:com.amazon.vizzini' "$FAKE_ACTIVE_PACKAGES" > "$FAKE_ACTIVE_PACKAGES.next" || true
        mv "$FAKE_ACTIVE_PACKAGES.next" "$FAKE_ACTIVE_PACKAGES"
        printf 'Success\n' ;;
    'shell settings get global ota_disable_automatic_update') cat "$FAKE_OTA_STATE" ;;
    'shell settings put global ota_disable_automatic_update 1') printf '1\n' > "$FAKE_OTA_STATE" ;;
    'shell cmd package install-existing --user 0 com.amazon.'*) printf 'Package installed\n' ;;
    'shell cmd package set-home-activity com.amazon.tv.launcher/.ui.HomeActivity') : ;;
    *) : ;;
esac
EOF
    chmod +x "$fixture/bin/curl" "$fixture/bin/aapt" "$fixture/bin/apksigner" "$fixture/bin/adb"
}

run_tool() {
    PATH="$fixture/bin:$PATH" \
    CURL="$fixture/bin/curl" AAPT="$fixture/bin/aapt" \
    APKSIGNER="$fixture/bin/apksigner" ADB="$fixture/bin/adb" \
    FAKE_RELEASE_JSON="$fixture/release.json" \
    FAKE_PROJECTIVY_APK="$fixture/projectivy.apk" \
    FAKE_AURORA_RELEASE_JSON="$fixture/aurora-release.json" \
    FAKE_AURORA_APK="$fixture/aurora.apk" \
    FAKE_ADB_LOG="$fixture/adb.log" \
    FAKE_HOME_STATE="$fixture/home.state" \
    FAKE_ACTIVE_PACKAGES="$fixture/active.packages" \
    FAKE_OTA_STATE="$fixture/ota.state" \
    KARA_REMOVE_MANIFEST="$fixture/remove-user0.txt" \
    KARA_PRIVILEGED_MANIFEST="$fixture/remove-privileged.txt" \
    KARA_CACHE_DIR="$fixture/cache" KARA_BACKUP_DIR="$fixture/backups" \
    "$tool" "$@"
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
