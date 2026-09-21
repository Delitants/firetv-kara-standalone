#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
src="$repo/app/kara-settings/src/local/kara/settingsredirector"
manifest="$repo/app/kara-settings/AndroidManifest.xml"
owner_helper="$repo/helpers/profile-owner/ClearProfileOwner.java"

for source in AppsActivity.java DeveloperActivity.java; do
    test -f "$src/$source" || { echo "FAIL: missing $source" >&2; exit 1; }
done

for label in '"Fire TV Settings (Display & Sounds + more)"' '"Network"' '"Applications"' '"Developer & ADB"' '"Controllers & Bluetooth"' '"Device & About"'; do
    grep -F "$label" "$src/MainActivity.java" >/dev/null || { echo "FAIL: missing menu label $label" >&2; exit 1; }
done

grep -F 'AppsActivity.class' "$src/MainActivity.java" >/dev/null
grep -F 'DeveloperActivity.class' "$src/MainActivity.java" >/dev/null
grep -F 'com.amazon.tv.launcher' "$src/MainActivity.java" >/dev/null
grep -F 'com.amazon.tv.launcher.ui.MainSettingsActivity' "$src/MainActivity.java" >/dev/null
grep -F 'android.permission.REQUEST_DELETE_PACKAGES' "$manifest" >/dev/null
grep -F 'local.kara.settingsredirector.AppsActivity' "$manifest" >/dev/null
grep -F 'local.kara.settingsredirector.DeveloperActivity' "$manifest" >/dev/null
grep -F 'Intent.ACTION_DELETE' "$src/AppsActivity.java" >/dev/null
grep -F 'ApplicationInfo.FLAG_SYSTEM' "$src/AppsActivity.java" >/dev/null
grep -F 'Settings.Global.ADB_ENABLED' "$src/DeveloperActivity.java" >/dev/null
test -f "$owner_helper"
grep -F 'IDevicePolicyManager' "$owner_helper" >/dev/null
grep -F 'com.amazon.tv.parentalcontrols.PCONAdminReceiver' "$owner_helper" >/dev/null
grep -F 'clearProfileOwner(admin)' "$owner_helper" >/dev/null
grep -F 'SystemProperties' "$src/DeveloperActivity.java" >/dev/null && {
    echo 'FAIL: DeveloperActivity must not use hidden SystemProperties API' >&2
    exit 1
}
if rg -n 'com[.]amazon[.]tv[.]settings[.]v2|android[.]settings[.](MANAGE_APPLICATIONS|APPLICATION_DEVELOPMENT)' "$src" >/dev/null; then
    echo 'FAIL: local fallback screens must not route directly to fragile Amazon Settings panels' >&2
    exit 1
fi

echo 'KARA_SETTINGS_SOURCE_GATE=PASS'
