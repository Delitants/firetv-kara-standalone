# Test evidence

## Exploit repository

- Public source branch: [`kara-PS7713-5443`](https://github.com/Delitants/GhostLock/tree/kara-PS7713-5443/kara)
- Source commit: `e9ae8f5`
- Reproducible-build workflow commit: `5a9e2b0`
- Green build and host-test run: [GitHub Actions 34647714301](https://github.com/Delitants/GhostLock/actions/runs/34647714301)
- Public release: [`kara-PS7713-5443-v1`](https://github.com/Delitants/GhostLock/releases/tag/kara-PS7713-5443-v1)
- Release asset SHA-256:
  `a42185d743ee1d4c9c46c1e35f5fa0a40f5e9a7f81450308c3eab297677847d5`

The ARM32 CI build reproduces that exact digest from the public source. All four
host decision suites compile with warnings treated as errors and pass.

## Standalone controller

- Offline integration suite: 68 passed, 0 failed.
- Package manifests: 106 ordinary removals, zero generic protected removals,
  59 core
  preserves, and 16 compatibility preserves; disjointness gate passed.
- Excluded-content gate passed.
- The public [GitHub Actions test workflow](https://github.com/Delitants/firetv-kara-standalone/actions/workflows/test.yml)
  runs ShellCheck plus the integration, manifest, and excluded-content gates on
  every push and pull request.
- A real GitHub release download returned the pinned release tag and exact
  SHA-256 above.

## Live device validation — 2026-09-11

The physical USB-connected target reported:

```text
DEVICE=kara
MODEL=AFTKA
BUILD=0035334210436
API=28
KERNEL=4.14.87+
MACHINE=armv7l
ABI=armeabi-v7a
CPUS=4
SHELL_UID=2000
SELINUX=Enforcing
VERIFIED_BOOT=green
FLASH_LOCKED=1
HOME=com.spocky.projengmenu/.ui.home.MainActivity
SUPPORTED_MUTATION_TARGET=YES
SUPPORTED_EXPLOIT_TARGET=YES
```

The durable configuration check returned:

```text
VERIFY_GATE=PASS
```

The controller downloaded release `kara-PS7713-5443-v1`, authenticated the
pinned SHA-256 above, staged it temporarily, and invoked only `--probe`. The
physical target returned both safe-probe success markers, including:

```text
V2 SAFE PROBE PASS (reclaim and GhostLock were not invoked)
```

Both temporary probe copies were removed. No live race, root attempt, package
change, HOME change, OTA change, reboot, partition write, or hardware short was
performed during this validation pass.

The live screenshot published at
[`docs/images/projectivy-kara-this-device-2026-09-11.png`](images/projectivy-kara-this-device-2026-09-11.png)
is an unedited 1920x1080 ADB framebuffer capture taken after opening
Projectivy System → About → **This device**. It visibly reports `kara`, `AFTKA`,
`mt8696`, and `PS7713.5443N`. The fingerprint displayed by this screen embeds
`0035334210304`; the independently queried `ro.build.version.incremental` used
by the controller's compatibility gate is `0035334210436`. Its SHA-256 is
`9ecdf497fe9dd458b4e4c8ff46332a72930dfdbad929420b10db08f5847e7895`.

## Evidence boundary

The released binary is the byte-identical artifact previously proven to obtain
temporary uid 0 on the exact supported AFTKA build. That controlled result is
the reason the controller has a second, independent digest pin in addition to
GitHub release metadata.

The 2026-09-11 pass freshly proves the current device identity, Projectivy HOME
selection, configured package/OTA state, and safe-probe compatibility. It does
not claim a fresh live-root result or a new reboot-persistence trial. The live
root statement remains scoped to the earlier controlled run that produced the
byte-identical released artifact.

## Live Settings validation — 2026-09-20

The same physical `kara/AFTKA` target on build `0035334210436` was connected
over the authorized USB ADB bridge. Before testing, the exact hidden stock
Settings dependency set was registered and enabled for Android user 0:

```text
com.amazon.adep
com.amazon.audiohome
com.amazon.ceviche
com.amazon.dcp
com.amazon.device.messaging
com.amazon.device.sale.service
com.amazon.ftv.screensaver
com.amazon.tv.launcher
com.amazon.vizzini
com.amazon.whasettings
```

The updated, same-certificate Kara Settings v6 APK installed successfully and
showed these TV-oriented routes:

```text
Fire TV Settings (Display & Sounds + more)
Network
Applications
Developer & ADB
Controllers & Bluetooth
Device & About
```

Selecting the first route resumed
`com.amazon.tv.launcher/.ui.MainSettingsActivity`, the exported privileged
bridge used by the stock launcher. The full Fire TV Settings menu rendered.
Display & Sounds opened and visibly contained Alexa Home Theater, Screensaver,
Display, Audio, Enable Display Mirroring, and HDMI CEC Device Control.
Applications, Device, Network, and Controllers & Bluetooth also resumed their
stock panels without a `com.amazon.tv.settings.v2` crash during the test.

Fire OS rejects direct third-party launch of the underlying Display & Sounds
activity because it requires the signature/privileged
`com.amazon.tv.permission.LAUNCHER_SETTINGS` permission. This is why the
profile retains the Amazon launcher package while disabling only its HOME
activity. The APK exercised on-device has SHA-256:

```text
7b349318e531300f2c6a0e5541918d932fdd36ab62f5e633e2e284592c17aee0
```

This live pass validates the Settings bridge and Kara Settings UI. It does not
claim a fresh end-to-end `apply`, root-assisted HOME-component disable, reboot,
or profile-owner release on the reference Stick. Those controller paths are
covered by the offline suite; profile-owner removal remains gated to
the exact expected component, dynamic UID/context, and hash-pinned helpers.

## Live LeanKey and Aurora validation — 2026-09-21

On the same USB-connected `kara/AFTKA` target, the standalone keyboard command
downloaded the pinned LeanKey 6.1.31 APK, verified SHA-256
`5a90529fcae55c664128fb36e752f90e84d158266eced85084594c1d336a1468`,
installed package `org.liskovsoft.androidtv.rukeyboard`, waited for Fire OS to
register its input-method service, enabled that service, selected it, and read
back this exact default IME:

```text
org.liskovsoft.androidtv.rukeyboard/com.liskovsoft.leankeyboard.ime.LeanbackImeService
```

Amazon FireTVIME remained enabled. A fresh absence-to-install test reported:

```text
KEYBOARD_GATE=PASS previous=com.amazon.tv.ime/.FireTVIME current=org.liskovsoft.androidtv.rukeyboard/com.liskovsoft.leankeyboard.ime.LeanbackImeService
```

Aurora Store was then force-stopped and reopened. Its Search control opened
LeanKey, a D-pad center click on the focused `t` key inserted `t` into Aurora's
search field, live suggestions appeared, and navigating with D-pad Right to
LeanKey's SEARCH action and clicking it dismissed the IME and loaded matching
Aurora results. Projectivy remained the resolved HOME throughout.

The final offline controller suite reports `74 passed, 0 failed`, including
APK provenance, delayed Fire OS IME discovery, activation readback, failure
rollback, full-apply rollback, and SSH-bridge payload staging.
