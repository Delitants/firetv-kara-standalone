# Kara Settings v5

`local.kara.settingsredirector` is a small Android 9 TV application used when
the stock top-level Fire TV Settings handler depends on Amazon launcher
components removed by the debloat profile.

The checked-in APK is the reviewed build installed by `kara-tool.sh`:

```text
versionName: 5.0
versionCode: 5
SHA-256: 56f45a726a98a237d91a43e90f34b8a51e1b42a41b397b2d7388c614c1c9a373
```

The private signing key is intentionally not included. Java source and the
Android manifest are provided for audit and rebuilding with your own key using
Android SDK 28 or newer build tools.

## Rebuild notes

Compile for Java 8 against `platforms/android-28/android.jar`, convert with D8
at minimum API 28, link the manifest with AAPT2, add `classes.dex`, align, and
sign with your own key.

When using current JDK 23 with the old Android Build Tools 28.0.3 D8, recompile
these three classes with `javac --release 8 -parameters` before creating the
classes JAR:

```text
WifiSecurity.java
NetworkActivity.java
BluetoothActivity.java
```

Without that workaround, D8 28.0.3 can fail while reading unnamed method
parameters. A newer compatible D8 toolchain may not require it.

The app requests only the permissions declared in `AndroidManifest.xml` and
does not contain analytics, update code, networking backends, advertising, or
root functionality.
