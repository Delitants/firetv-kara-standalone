# OTA, rollback, and recovery

## Before applying

1. Disconnect the Fire TV from uncontrolled networks if an update is pending.
2. Run `audit` and confirm `SUPPORTED_MUTATION_TARGET=YES`.
3. Run `backup` separately and copy the resulting directory somewhere safe.
4. Do not reboot if the UI says an update will install on the next reboot.

## OTA boundary

The public controller performs two reversible user-space actions:

- removes the known OTA packages for Android user 0 through the reviewed
  removal manifest;
- sets `global ota_disable_automatic_update` to `1`.

These measures do not erase a payload already staged in `/data` or `/cache`, do
not change bootloader/recovery policy, and are not an absolute promise that an
Amazon update can never occur. Clearing a staged recovery update can require
temporary root and exact inspection of the live device. That privileged action
is intentionally outside this public script.

The optional `--root-helper` interface is limited to the protected
`com.amazon.vizzini` user-0 removal. It does not remove staged OTA files.

## Automatic rollback

After a backup exists, any failed `apply` triggers a best-effort automatic
restore. The command still exits non-zero. Read both markers:

```text
AUTOMATIC_ROLLBACK=PASS
AUTOMATIC_ROLLBACK=FAIL backup=/path/to/backup
```

If rollback fails, do not reboot. Preserve the printed backup directory and run
the explicit restore command after ADB connectivity is stable.

## Manual rollback

```sh
./scripts/kara-tool.sh \
  --serial DEVICE_IP:5555 \
  --backup /absolute/path/to/backups/TIMESTAMP-PID \
  --yes restore
```

The restore command:

- confirms the same exact device/build;
- reinstalls only manifest packages that were active in that backup;
- restores their prior disabled state;
- restores the recorded HOME component;
- restores or deletes the OTA setting according to the backup.

It intentionally leaves Projectivy and Kara Settings installed. They can be
removed later with ordinary package-manager commands after a working HOME and
Settings path have been confirmed.

## Recovery priorities

If the device becomes unstable:

1. Keep it powered and keep ADB connected.
2. Restore the latest known-good backup.
3. Confirm HOME resolves and launch it explicitly.
4. Confirm Wi-Fi, Bluetooth remote, HDMI-CEC, audio, and streaming playback.
5. Reboot only after the restored state is verified.
