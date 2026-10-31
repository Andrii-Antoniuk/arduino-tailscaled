# Arduino Yún Rev2 minimal Tailscale feasibility report

Date: 2026-10-31

## Current decision

Official Go `tailscaled` remains too large for the 8,348 KiB overlay. The
active path is a Rust userspace bridge (`yun-tailssh-bridge`) that accepts
tailnet TCP port 22 and forwards it to local Dropbear. It is stored on a
temporary PC NFSv4 share (`$HOST_LAN_IP:$EXPORT_DIR` from `.env`), not on
the overlay.

The first MIPS binary died with `Illegal instruction` because
`messense/rust-musl-cross` links rustc's bundled MIPS `crt1.o`, which is
hard-float. The AR9330 has no FPU. Rebuilding with the OpenWrt 25.12.6
ath79 SDK (`--with-float=soft`, `mips32r2`/`24kc`) produced a static
soft-float binary that runs on the device:

* Artifact: `dist/rust/yun-tailssh-bridge.mips`
* ELF: ELF32 MSB, MIPS32r2, static, `Tag_GNU_MIPS_ABI_FP: Soft float`
* Size: 9,767,880 bytes
* SHA-256: `2214f45cea0da9a8630fa51f57f695e40c6fdb3668479982441f052242dc5a1e`
* `--help` on the Yún via NFS: usage text, exit 2. No SIGILL.
* Rebuild: `scripts/build-yun-tailssh-bridge.sh`

No Tailscale node has been registered. Dropbear, firewall, LAN, and flash
are unchanged. Next step is a user-approved one-time auth key on stdin
(`--auth-key-stdin`) with state on the NFS share, then RSS sampling. Do not
hardcode the key.

## Target verification

Read-only SSH checks reported OpenWrt 25.12.6 on `ath79/generic`, kernel
6.12.112, Atheros AR9330 rev 1, and `/bin/busybox` ELF bytes `7f 45 4c 46 01
02`. `02` means big-endian. Therefore the firmware uses OpenWrt's
`mips_24kc`/Go `mips` ABI, not `mipsle`. The correct build selection is:

```
GOOS=linux GOARCH=mips GOMIPS=softfloat CGO_ENABLED=0
```

The `mipsle` artifact is included only as an inspected comparison artifact and
must not be installed.

## Source and reproducible build

* Official source: `https://github.com/tailscale/tailscale`
* Release: `v1.104.4`
* Commit: `27047635f237d1f3e0b08c0f487674757f30d2f7`
* Go compiler: Go 1.27.3, Docker image digest
  `golang@sha256:d9b6a1beb9474adc2a1ce842573639b44b2a0dd49b6669f51d3821baf9ec37c9`
* Build: upstream `build_dist.sh --extra-small --box ./cmd/tailscaled`
* Link flags supplied by upstream: version stamp plus `-w -s`.
* Build environment: CGO disabled. The resulting executable is static and has
  no dynamic section, dynamic linker, or libc dependency.

Run `scripts/build-tailscale-minimal.sh` to rebuild and inspect both ELF
variants. Its Docker cache volumes affect speed only, not source selection.

## Artifact report

| Artifact | ELF | Size | SHA-256 |
| --- | --- | ---: | --- |
| `dist/tailscaled.mips` | ELF32, MSB, MIPS32 o32, static | 15 MiB | `79d9431e25b5f63ea8bdbbe358a6460148b8ca0bfcaa2e0cf5dbc5bcc18ef325` |
| `dist/tailscaled.mipsle` | ELF32, LSB, MIPS32 o32, static | 15 MiB | `65aea29da96d1ccdeea0664284ff237898977fc03e01d9cb4b6dc5884f44c81a` |

Removing the embedded CLI did not materially reduce this 15 MiB rounded size.
UPX was deliberately not used: it only moves the storage cost and requires
runtime decompression memory, which is contrary to the device RAM limit.

## Included and excluded functionality

`--extra-small` is an official upstream preset. In this release it keeps
`osrouter` (kernel TUN IP/routing setup) and `nattraversal`, whose dependency
keeps UDP peer transport. Thus it retains registration/control coordination,
WireGuard data plane, direct UDP/STUN/disco NAT traversal, and DERP peer-relay
client fallback. `--box` only embeds the local `tailscale` CLI in the daemon
binary.

It omits gVisor/netstack, Tailscale SSH, Serve/Funnel, Taildrop, MagicDNS and
system DNS integration, route advertising, route use, exit-node advertising
and use, port mapping, web client, relay server, logging upload, debug,
metrics, systemd/DBus integration, and the other feature tags not required by
`osrouter,nattraversal,cli`. `etherwake` is not presently installed; no package
was installed to investigate it because deployment is infeasible.

## Required USB-backed measurement sequence

Attach a USB drive and mount it at (for example) `/mnt/tailscale-usb`; do not
use the writable overlay for the binary or its state. First perform
`scripts/audit-yun-readonly.sh`; then copy the big-endian binary to the USB
drive, start it with explicit state, socket, and log paths on that drive, and
authenticate interactively or with a short-lived user-approved auth key.
Sample its PID using
`scripts/measure-tailscaled-rss.sh` at startup, after auth, after a peer path,
after forced DERP, and after several idle minutes. Do not place an auth key in
a script, binary, image, or persistent configuration.

Only after all samples are within budget should a procd service and an
`etherwake -i "$WOL_IFACE" "$WOL_MAC"` command (from `yun.env`) be introduced. The current
hardware has not passed this prerequisite, so no installation, rollback, or
startup service is supplied yet.
