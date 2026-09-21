#!/bin/sh
set -eu

base=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
sdk=${ANDROID_SDK_ROOT:?ANDROID_SDK_ROOT is required}
build_tools=${ANDROID_BUILD_TOOLS_VERSION:-28.0.3}
keystore=${KARA_SETTINGS_KEYSTORE:?KARA_SETTINGS_KEYSTORE is required}
key_alias=${KARA_SETTINGS_KEY_ALIAS:-kara-settings-redirector}
store_pass=${KARA_SETTINGS_STORE_PASS:?KARA_SETTINGS_STORE_PASS is required}
key_pass=${KARA_SETTINGS_KEY_PASS:?KARA_SETTINGS_KEY_PASS is required}
output=${KARA_SETTINGS_OUTPUT:-$base/kara-settings-v6-signed.apk}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/kara-settings-build.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

platform="$sdk/platforms/android-28/android.jar"
tools="$sdk/build-tools/$build_tools"
classes="$tmp/classes"
dex="$tmp/dex"
unsigned="$tmp/kara-settings-v6-unsigned.apk"
aligned="$tmp/kara-settings-v6-aligned.apk"
mkdir -p "$classes" "$dex"

javac --release 8 -Xlint:-options -encoding UTF-8 -classpath "$platform" -d "$classes" \
    $(find "$base/src" -name '*.java' -print)
# Current JDKs can emit unnamed enum/anonymous-class parameters that old D8
# cannot read. Recompile the affected units with explicit parameter metadata.
javac --release 8 -parameters -Xlint:-options -encoding UTF-8 -classpath "$classes:$platform" -d "$classes" \
    "$base/src/local/kara/settingsredirector/WifiSecurity.java" \
    "$base/src/local/kara/settingsredirector/NetworkActivity.java" \
    "$base/src/local/kara/settingsredirector/BluetoothActivity.java" \
    "$base/src/local/kara/settingsredirector/AppEntry.java" \
    "$base/src/local/kara/settingsredirector/AppsActivity.java"
jar cf "$tmp/classes.jar" -C "$classes" .
"$tools/d8" --lib "$platform" --min-api 28 --output "$dex" "$tmp/classes.jar"
"$tools/aapt2" link -I "$platform" --manifest "$base/AndroidManifest.xml" \
    --min-sdk-version 28 --target-sdk-version 28 --version-code 6 --version-name 6.0 -o "$unsigned"
touch -t 198001010000 "$dex/classes.dex"
(cd "$dex" && zip -q -u "$unsigned" classes.dex)
"$tools/zipalign" -f 4 "$unsigned" "$aligned"
"$tools/apksigner" sign --ks "$keystore" --ks-key-alias "$key_alias" \
    --ks-pass "pass:$store_pass" --key-pass "pass:$key_pass" --out "$output" "$aligned"
