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

- Offline integration suite: 39 passed, 0 failed.
- Package manifests: 115 ordinary removals, one protected removal, 49 core
  preserves, and 16 compatibility preserves; disjointness gate passed.
- Excluded-content gate passed.
- ShellCheck, integration, manifest, and excluded-content gates passed in
  [GitHub Actions 34649184296](https://github.com/Delitants/firetv-kara-standalone/actions/runs/34649184296).
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
[`docs/images/projectivy-kara-live-2026-09-11.png`](images/projectivy-kara-live-2026-09-11.png)
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
