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

- Offline integration suite: 29 passed, 0 failed.
- Package manifests: 115 ordinary removals, one protected removal, 49 core
  preserves, and 16 compatibility preserves; disjointness gate passed.
- Excluded-content gate passed.
- ShellCheck, integration, manifest, and excluded-content gates passed in
  [GitHub Actions 34649184296](https://github.com/Delitants/firetv-kara-standalone/actions/runs/34649184296).
- A real GitHub release download returned the pinned release tag and exact
  SHA-256 above.

## Device boundary

The released binary is the byte-identical artifact previously proven to obtain
temporary uid 0 on the exact supported AFTKA build. That controlled result is
the reason the controller has a second, independent digest pin in addition to
GitHub release metadata.

A fresh device pass was not run during this publication check because neither
USB nor network ADB exposed the Stick. No live race was attempted while the
target was unavailable. This document therefore does not claim a newly
observed current device state or a fresh reboot-persistence result.
