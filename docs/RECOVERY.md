# OTA, rollback, and recovery

## Before applying

1. If an update is pending for the next reboot, disconnect the Stick from
   uncontrolled networks.
2. Run `audit`; continue only when both support markers say `YES`.
3. Keep stable power and ADB connectivity during `apply`.
4. Record the printed `BACKUP_DIR` immediately.

## Exploit and reboot boundary

The safe probe validates the exact kernel surface without entering the race.
Live mode is different: it can watchdog-reboot the Stick. The script launches
live mode once, waits for a uid-0 proof, and refuses app/package changes without
that proof. It never retries the race automatically.

If ADB returns after an unexpected reboot, run `audit` again. Do not rerun
`apply` until the build still matches and you have inspected the prior attempt's
backup, launcher log at `/data/local/tmp/kara-ghostlock.start.log`, and detailed
exploit log at `/data/local/tmp/kara-ghostlock.log`.

If the detailed log ends with `ROOT DAEMON READY`, do not reboot or start the
exploit again. Find the exact daemon path from `ps -A | grep kara-ghostlock` or
`/proc/PID/exe`, update this repository, and resume the interrupted apply:

```sh
./scripts/kara-tool.sh \
  --serial FIRE_TV_IP:5555 \
  --root-helper /data/local/tmp/kara-ghostlock-NUMBER \
  --yes apply
```

The script proves that the supplied path is the live uid-0 daemon for the exact
supported build before accepting a permissive SELinux state. It does not launch
another exploit attempt. If GhostLock left both the live and held OTA paths as
empty directories, the script removes only the empty live directory with
`rmdir` and preserves the held path. A non-empty live OTA path is never removed;
`apply` stops for manual review before installing or removing packages.

Fire OS gives its launcher and Home Starter higher HOME resolver priorities
than an installed launcher. Current `apply` verifies that Projectivy starts,
uses the proven root helper to disable both blockers, verifies Projectivy as
HOME, and only then removes the blockers for user 0. If that transition fails,
automatic rollback reinstalls and re-enables the blockers according to the
backup and restores the previous HOME before reporting success or failure.
For every other reviewed package, `apply` first tries the ordinary ADB shell
uninstall. If Fire OS leaves it active, the script retries that exact manifest
package through the proven root helper and requires an absent readback.

## OTA boundary

After root succeeds, the exploit quarantines any staged `/data/ota_package`,
`/cache/recovery/command`, and `/cache/recovery/block.map`, disables the three
known OTA packages, and sets `ota_disable_automatic_update=1`. The controller
requires all three paths to be absent before installing apps or debloating.

These are build-specific software controls, not an absolute guarantee against
all future updater behavior. The toolkit never modifies the bootloader or
recovery partition.

## Automatic rollback

After a backup exists, a failed `apply` attempts restoration and still exits
non-zero:

```text
AUTOMATIC_ROLLBACK=PASS
AUTOMATIC_ROLLBACK=FAIL backup=/path/to/backup
```

A watchdog reboot or lost ADB connection can prevent automatic rollback. In
that case, preserve the backup and restore explicitly after ADB is stable.

## Manual rollback

```sh
./scripts/kara-tool.sh \
  --serial DEVICE_IP:5555 \
  --root-helper /data/local/tmp/kara-ghostlock-NUMBER \
  --backup /absolute/path/to/backups/TIMESTAMP-PID \
  --yes restore
```

Add the same `--bridge` option used during installation when applicable. The
restore command verifies the same device/build, reinstalls only manifest
packages recorded as present, restores their disabled state, restores HOME,
and restores or deletes the OTA and CEC settings according to the backup. It
then reads back package presence, disabled state, HOME, OTA, and CEC before
printing `RESTORE_GATE=PASS`.

Backups containing `com.amazon.tv.launcher` or `com.amazon.firehomestarter`
require the exact still-live root helper because Fire OS protects these package
state changes. Restore registers those packages for user 0 from the ordinary
ADB shell context, verifies that registration immediately, and then uses root
only to restore the protected enabled state and HOME selection. This split is
intentional: on kara, the root-derived package-manager context can report
success without changing user-0 registration. If a reboot destroyed temporary
root, do not attempt a rootless restore: obtain fresh temporary root for the
exact supported build first, then run the command above with that daemon path.

Projectivy, Aurora Store, and Kara Settings remain installed after this package
state rollback. Remove them only after a working HOME and Settings path have
been confirmed.

## Recovery priorities

1. Keep stable power and reconnect ADB.
2. Confirm the exact build with `audit`.
3. Restore the latest known-good backup.
4. Confirm HOME and launch it explicitly.
5. Test Wi-Fi, the Bluetooth remote, HDMI-CEC, audio, and streaming playback.
6. Reboot only after the restored state is verified and no update is staged.
