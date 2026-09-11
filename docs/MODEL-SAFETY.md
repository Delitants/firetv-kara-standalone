# Model and firmware safety

## Supported identity

Mutation is limited to all four simultaneous values:

```text
ro.product.device=kara
ro.product.model=AFTKA
ro.build.version.incremental=0035334210436
ro.build.version.sdk=28
```

`audit` can inspect another device, but `backup`, `apply`, `verify`, and
`restore` stop on any mismatch.

## Similar names are not compatible

| Marketing name | Codename | Model | SoC/base | Supported |
| --- | --- | --- | --- | --- |
| Fire TV Stick 4K (2018) | `mantis` | `AFTMM` | MT8695 / Fire OS 6 | No |
| Fire TV Stick 4K Max 1st Gen | `kara` | `AFTKA` | MT8696 / Fire OS 7 | Yes, exact build only |
| Fire TV Stick 4K 2nd Gen | `mantra` | `AFTKM` | MT8696D / Fire OS 8 | No |
| Fire TV Stick 4K Max 2nd Gen | `karat` | `AFTKRT` | MT8696T / Fire OS 8 | No |

Never flash a preloader, LK, boot image, recovery, or exploit payload from one
of these related devices onto another.

## Root and bootloader scope

The ordinary workflow uses authorized ADB and user-0 package operations. This
repository deliberately does not automate a kernel exploit, BootROM exploit,
hardware short, bootloader unlock, partition write, downgrade, or ROM flash.

The exact exploitability of `kara` varies by firmware and security patch. A
payload that works on a related MediaTek Fire TV is not compatibility evidence.

## Streaming stack

The preserve manifests were selected to keep Fire OS framework, DRM/vendor
integration, WebView, remote/Bluetooth, Wi-Fi, device control, settings, input,
and media compatibility components. Nevertheless, application certification
and streaming behavior can change independently. Verify the services important
to you before deleting a backup.
