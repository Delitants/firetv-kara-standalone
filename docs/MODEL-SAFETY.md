# Model, firmware, and exploit safety

## Exact mutation gate

The controller requires `kara/AFTKA`, build `0035334210436`, API 28, kernel
`4.14.87+`, `armv7l` with primary ABI `armeabi-v7a`, four online CPUs, ADB
shell uid 2000, and enforcing SELinux. It rechecks firmware after root is
obtained and stops before app or package changes if anything differs.

`audit` may inspect another device. `backup`, `apply`, `verify`, and `restore`
refuse another device or build; the exploit runtime gate adds the remaining
requirements before live mode.

## Similar names are not compatible

| Marketing name | Codename | Model | Supported |
| --- | --- | --- | --- |
| Fire TV Stick 4K (2018) | `mantis` | `AFTMM` | No |
| Fire TV Stick 4K Max 1st Gen | `kara` | `AFTKA` | Exact build only |
| Fire TV Stick 4K 2nd Gen | `mantra` | `AFTKM` | No |
| Fire TV Stick 4K Max 2nd Gen | `karat` | `AFTKRT` | No |

Do not reuse this payload, offsets, firmware, or instructions on a related
model. Marketing similarity is not compatibility evidence.

## Root, reboot, and bootloader boundary

The published exploit is a build-specific kernel race. Live mode may fail
safely, succeed, or trigger a watchdog reboot. The controller invokes it at
most once per `apply`; it does not automatically retry after a reboot.

Root exists only in the current boot through a device-local command daemon. No
bootloader state, verified-boot state, partition, recovery, or ROM is changed.
The toolkit does not require a hardware short and does not make the bootloader
unlocked.

## Streaming stack

The preserve manifests retain Fire OS framework, DRM/vendor integration,
WebView, remote/Bluetooth, Wi-Fi, device control, input, and media compatibility
components. Application certification and streaming behavior can still change;
test the services important to you before deleting backups.
