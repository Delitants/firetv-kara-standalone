# Fire TV 4K Max 1st Gen (`kara`) standalone toolkit

A fail-closed, reversible toolkit for turning the **Amazon Fire TV Stick 4K
Max 1st Generation** into a Projectivy-based, low-Amazon-UI streaming device
while retaining Fire OS and its vendor media stack.

## Exact supported target

| Property | Required value |
| --- | --- |
| Product codename | `kara` |
| Amazon model | `AFTKA` |
| Device generation | Fire TV Stick 4K Max 1st Gen (2021) |
| Fire OS base | Fire OS 7 / Android 9 / API 28 |
| Tested build | `0035334210436` (`PS7713/5443`) |
| SoC | MediaTek MT8696 |

The mutating commands refuse every other identity or build. In particular,
this is **not** for `mantis/AFTMM`, `mantra/AFTKM`, or `karat/AFTKRT`.

## What it does

`scripts/kara-tool.sh` provides six commands:

- `audit` — read-only identity and launcher inventory;
- `download-projectivy` — downloads the latest official Projectivy APK;
- `backup` — records current HOME, OTA, package, and firmware state;
- `apply` — backs up, installs the apps, switches HOME, debloats user 0,
  applies the OTA preference, and verifies the result;
- `verify` — read-only post-change checks;
- `restore` — reinstalls packages and restores HOME/OTA from a backup.

The `apply` sequence is deliberately ordered:

1. Require exact `kara/AFTKA/API28/build 0035334210436` identity.
2. Create a timestamped backup.
3. Download Projectivy from `spocky/miproja1` and Aurora Store from
   `AuroraOSS/AuroraStore` over HTTPS.
4. Verify their official source URLs, package names, Android compatibility, and
   developer signing-certificate SHA-256 values; also require GitHub's published
   digest for Projectivy.
5. Install Projectivy, Aurora Store, and the included open-source Kara Settings
   app.
6. Require all three packages to be active.
7. Set Projectivy as HOME and require package-manager readback.
8. Remove the reviewed 115 ordinary Amazon packages for user 0.
9. Optionally remove the single protected package through a caller-supplied
   temporary-root helper.
10. Set `ota_disable_automatic_update=1`.
11. Verify HOME, OTA, identity, and package absence.

If a post-mutation check fails, the script automatically attempts restoration
from the backup it just created and still exits non-zero.

## Important boundaries

- This is not a custom ROM, bootloader unlock, or persistent-root package.
- It does not flash or overwrite any partition.
- Package removal is `pm uninstall -k --user 0`: system APKs remain on the
  read-only system partition and can be restored with `install-existing`.
- It does not bundle an exploit, Amazon firmware, partition images, premium
  apps, Projectivy binaries, credentials, or device-specific identifiers.
- It preserves the 49-package core set and 16-package compatibility set under
  [`manifests/`](manifests/).
- `com.amazon.vizzini` is isolated in `remove-privileged.txt`; it is attempted
  only when `--root-helper` is explicitly supplied.
- No software-only OTA block is an absolute guarantee. See
  [OTA and recovery](docs/RECOVERY.md) before rebooting a device that already
  reports an update staged for the next boot.

## Prerequisites

On the controller computer:

- POSIX shell, Python 3, `curl`, and `shasum` or `sha256sum`;
- Android platform tools (`adb`);
- Android SDK build tools providing `aapt` and `apksigner`;
- ADB debugging enabled on the Fire TV;
- direct ADB access, or SSH key access to a Linux machine attached over USB.

On macOS, `adb` can be installed with Homebrew:

```sh
brew install android-platform-tools
```

Install Android SDK Build Tools with Android Studio or `sdkmanager`, then point
the script at their executables if they are not on `PATH`:

```sh
export AAPT="$ANDROID_SDK_ROOT/build-tools/35.0.0/aapt"
export APKSIGNER="$ANDROID_SDK_ROOT/build-tools/35.0.0/apksigner"
```

## Quick start — direct network ADB

Replace the example serial with the value shown by `adb devices`:

```sh
adb connect DEVICE_IP:5555
./scripts/kara-tool.sh --serial DEVICE_IP:5555 audit
./scripts/kara-tool.sh --serial DEVICE_IP:5555 download-projectivy
./scripts/kara-tool.sh --serial DEVICE_IP:5555 download-aurora
./scripts/kara-tool.sh --serial DEVICE_IP:5555 --yes apply
./scripts/kara-tool.sh --serial DEVICE_IP:5555 verify
```

If an already-audited temporary-root helper exists on the device and implements
`HELPER --cmd COMMAND`, opt into the protected-package step explicitly:

```sh
./scripts/kara-tool.sh \
  --serial DEVICE_IP:5555 \
  --root-helper /data/local/tmp/YOUR_REVIEWED_HELPER \
  --yes apply
```

The script accepts helper paths only under `/data/local/tmp`, sends only its
fixed `com.amazon.vizzini` user-0 removal command, and does not acquire root or
launch an exploit itself.

Pin the known-tested Projectivy release instead of following `latest`:

```sh
./scripts/kara-tool.sh --projectivy 4.71 download-projectivy
./scripts/kara-tool.sh --aurora 4.8.4 download-aurora
./scripts/kara-tool.sh --serial DEVICE_IP:5555 \
  --projectivy 4.71 --aurora 4.8.4 --yes apply
```

## Quick start — USB ADB through a Linux bridge

The bridge must have `adb`, the USB device must already be authorized, and SSH
must work without an interactive password prompt:

```sh
./scripts/kara-tool.sh \
  --bridge root@LINUX_HOST \
  --serial USB_SERIAL \
  audit

./scripts/kara-tool.sh \
  --bridge root@LINUX_HOST \
  --serial USB_SERIAL \
  --yes apply
```

Only the ADB commands run on the bridge. Projectivy is downloaded and verified
on the controller, then `adb install` streams it to the device.

## Restore

Every backup command prints its directory. Keep that exact path:

```sh
./scripts/kara-tool.sh --serial DEVICE_IP:5555 backup
```

Restore with:

```sh
./scripts/kara-tool.sh \
  --serial DEVICE_IP:5555 \
  --backup backups/20260911T120000Z-12345 \
  --yes restore
```

The restore operation uses the recorded package inventory; it does not activate
Amazon packages that were absent before the corresponding backup.

## Projectivy supply-chain verification

The repository does not redistribute Projectivy. During installation the script
queries the official
[`spocky/miproja1`](https://github.com/spocky/miproja1/releases/latest)
release, requires the asset URL to remain under that repository, verifies the
SHA-256 digest published by GitHub, and checks:

- package: `com.spocky.projengmenu`;
- minimum SDK: no higher than API 28;
- signer certificate SHA-256:
  `f6697bf4082ee97511e4de07863193884a015b7ab5860430321bda1042b0aadd`.

The known-tested official 4.71 asset has SHA-256:
`6818fc2db44411a605ca4d7067fb9d7227aaef2414cff42de58fe13e9321b47a`.

## Aurora Store supply-chain verification

The installer queries AuroraOSS's official `https://auroraoss.com/api/files`
catalog, selects only a standard APK immediately under
`/downloads/AuroraStore/Release/`, and requires the download URL to remain on
`auroraoss.com`. It then verifies:

- package: `com.aurora.store`;
- minimum SDK: no higher than API 28;
- version name: identical to the official release tag;
- signer certificate SHA-256:
  `4c626157ad02bda3401a7263555f68a79663fc3e13a4d4369a12570941aa280f`.

The known-tested official 4.8.4 APK has SHA-256:
`8a1ed9aa09631290da91cb793e0517b0f20dc70239ac94ae6682cd94f91a4bad`.

No other application store or updater is included or installed.

## Kara Settings

Fire OS Settings can crash or route through removed Amazon launcher components
after aggressive debloating. The included `local.kara.settingsredirector`
application supplies a standalone TV-oriented Settings entry for network,
Bluetooth, and device information. Its source and reviewed signed APK are under
[`app/kara-settings/`](app/kara-settings/).

## Testing

The offline test suite uses controlled fake ADB and download endpoints; it never
contacts or mutates a real device:

```sh
sh tests/run-tests.sh
```

See [MODEL-SAFETY.md](docs/MODEL-SAFETY.md) and
[RECOVERY.md](docs/RECOVERY.md) before modifying a device.

## License and third-party software

Original scripts and Kara Settings source are MIT licensed. Projectivy is a
third-party application and is downloaded from its developer; it is not covered
by this repository's license. See [NOTICE.md](NOTICE.md).
