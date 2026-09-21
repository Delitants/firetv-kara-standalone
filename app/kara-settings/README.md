# Kara Settings v6

`local.kara.settingsredirector` is a small Android 9 TV application used when
the stock top-level Fire TV Settings handler depends on Amazon launcher
components removed by the debloat profile.

The checked-in APK is the reviewed build installed by `kara-tool.sh`:

```text
versionName: 6.0
versionCode: 6
SHA-256: 7b349318e531300f2c6a0e5541918d932fdd36ab62f5e633e2e284592c17aee0
```

The private signing key is intentionally not included. Java source, the Android
manifest, and `build.sh` are provided for audit and rebuilding with your own key
using Android SDK 28 or newer build tools.

The hub provides local, Amazon-independent screens for:

- the retained stock Fire TV Settings bridge, including Display & Sounds;
- Wi-Fi scanning, connection, and saved-network removal;
- installed application inventory, launching, and confirmed user-app uninstall;
- live ADB, USB transport, TCP port, and Wi-Fi endpoint status;
- controllers and Bluetooth; and
- device/build information.

The stock bridge uses the exported Amazon launcher `MainSettingsActivity`; the
installer retains that package only as a privileged settings host while its
HOME activity stays disabled. The ADB screen is intentionally read-only. Kara Settings is not granted the
broad `WRITE_SECURE_SETTINGS` permission. The installer preserves and verifies
ADB access, while changes to ADB remain an authorized-host operation.

## Rebuild notes

Set `ANDROID_SDK_ROOT`, `KARA_SETTINGS_KEYSTORE`,
`KARA_SETTINGS_STORE_PASS`, and `KARA_SETTINGS_KEY_PASS`, then run `build.sh`.
It compiles for Java 8 against `platforms/android-28/android.jar`, converts with
D8 at minimum API 28, links the manifest with AAPT2, aligns, and signs.

When using current JDK 23 with the old Android Build Tools 28.0.3 D8, recompile
the enum/anonymous-callback classes with `javac --release 8 -parameters` before creating the
classes JAR:

```text
WifiSecurity.java
NetworkActivity.java
BluetoothActivity.java
AppEntry.java
AppsActivity.java
```

Without that workaround, D8 28.0.3 can fail while reading unnamed method
parameters. A newer compatible D8 toolchain may not require it.

The app requests only the permissions declared in `AndroidManifest.xml` and
does not contain analytics, update code, networking backends, advertising, or
root functionality.
