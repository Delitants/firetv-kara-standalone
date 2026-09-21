# Parental-controls profile-owner release helpers

Fire OS registers `com.amazon.tv.parentalcontrols/.PCONAdminReceiver` as the
Android profile owner on some devices. Android correctly refuses to uninstall
an active owner, even from uid 0.

`kara-tool.sh` uses these helpers only after it has verified all of the
following:

- exact `kara/AFTKA` build `0035334210436`;
- a proven temporary uid-0 daemon;
- the exact expected profile-owner component;
- the package's dynamically reported application UID;
- the immutable `/system/priv-app` package path; and
- the pinned SHA-256 of both helper artifacts.

`uid-context-exec.c` starts a single program as that application UID and SELinux
context. `ClearProfileOwner.java` calls Android's hidden
`IDevicePolicyManager.clearProfileOwner(ComponentName)` API for only the exact
Amazon parental-controls admin. The controller verifies the UID/context before
the call, verifies DevicePolicyManager afterward, deletes staged helpers, and
then removes the package.

The compiled release artifacts are intentionally checked in because the target
has no compiler:

```text
clear-profile-owner.dex  9974b0f45ed1bac1ff4d607246bf09da2550607ee7c95327393002432dc1c2c8
uid-context-exec.arm      e6dd64b64473ac825eace02f0b588aeb377ff815ad067a4d4ce9620f1961cf2b
```

To rebuild the DEX, compile `ClearProfileOwner.java` against the exact target's
`/system/framework/framework.jar` (the public Android SDK stubs omit these
hidden interfaces), then run D8 with minimum API 28. Rebuild
`uid-context-exec.arm` with an ARMv7 Android/Linux cross-compiler and static
linking. A rebuilt artifact is not accepted by the controller until its new
digest is reviewed and deliberately updated in `kara-tool.sh`.

The pre-release backup includes the policy dump, `profile_owner.xml`, and
`device_policies.xml` for forensic/manual recovery. Automated restore does not
copy those files back or claim to recreate Android profile ownership.
