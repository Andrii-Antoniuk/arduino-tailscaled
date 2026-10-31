<img src="assets/icon.svg" width="64" height="64" alt="">

# Arduino Yún Tailscale SSH bridge and Wake-on-LAN

Remote-wake a sleeping home PC from a phone, using an always-on Arduino Yún
on the LAN as a Tailscale node. The Yun is too small for official
`tailscaled`, so this repo ships a Rust userspace bridge: Tailscale TCP port
22 is forwarded to local Dropbear, and port 80 serves a one-button
Wake-on-LAN page.

This is for people who want:

- an always-on, low-power gadget on the home network
- SSH to that gadget from anywhere on their tailnet
- a phone button that sends WOL to a desktop that is allowed to sleep
- no VPN appliance and no cloud “wake my PC” subscription

It is **not** an official Tailscale product. Do not put an auth key in this
repo, a script, or flash.

## Why a Yun

The desktop sleeps. The Yun stays up on Ethernet, joins the tailnet, and is
the thing you hit from a phone:

1. Phone (Tailscale) → Yun:80 → `etherwake` → sleeping PC
2. Phone (Tailscale) → Yun:22 → Dropbear, for shell / `wol`

Crash notes from the Yun are pushed over the LAN to the PC when that PC is
awake, so a dead bridge can make a desktop notification with sound.

Official Go `tailscaled` is about 15 MiB extra-small. The Yun Rev2 overlay
is about 8 MiB. The binary and node state live on a USB stick (or a
temporary NFS share while testing), not on overlayfs.

## What this is

| Piece | Role |
| --- | --- |
| `rust-dropbear-bridge` (`yun-tailssh-bridge`) | Tailnet TCP 22 → `127.0.0.1:22` (Dropbear); tailnet TCP 80 → WOL page |
| USB `start.sh` / `supervise.sh` / `watchdog.sh` | Keep the bridge up; reboot the board on a crash loop |
| USB `wol` | `etherwake` wrapper, so `ssh root@<yun> wol` works from a phone |
| USB `notify.sh` | Queue crash lines and push them to the LAN PC |
| `scripts/watch-yun-alerts-host.sh` | PC listener: log + desktop notification + sound |

Machine-specific IPs, MAC, and paths stay in gitignored `.env` / `yun.env`.

## Architectures

**Proven on this repo’s build:** Arduino Yún Rev2, Atheros AR9330, OpenWrt
`ath79/generic`, **MIPS32r2 `24kc`, big-endian, soft-float**, static musl.
The board has no FPU. A hard-float MIPS `crt1.o` dies with `Illegal
instruction`. Use the OpenWrt ath79 SDK as the linker (`scripts/build-yun-tailssh-bridge.sh`).

**Same binary class (rebuild still required if the libc/SDK differs):** other
big-endian `mips_24kc` / ath79 OpenWrt boxes (many cheap Atheros routers).
Confirm endianness from `/bin/busybox` ELF byte 6: `02` is big-endian
(`GOARCH=mips`). `01` is little-endian (`mipsle`) and must not use this
artifact.

**Likely to work after a new cross toolchain, not this MIPS artifact:**

- other OpenWrt targets with enough RAM to hold a ~10 MiB static Rust
  binary (USB or extra storage; not a 4/32 overlay)
- little-endian MIPS (`mipsle` / ramips), ARM (`arm_cortex-a7`, `aarch64`),
  or x86_64 Linux, if you point Cargo at that target and a matching
  OpenWrt/Linux SDK
- any board that already has Dropbear or OpenSSH on localhost:22 and
  `etherwake`/`wol` on the LAN

**A poor fit:**

- devices with no storage besides a tiny overlay (the bridge is ~10 MiB)
- hard-float-only MIPS toolchains on soft-float SoCs
- trying to run unmodified Go `tailscaled` on 8 MiB flash
- anything that is not Linux (the bridge is userspace, no TUN, Tailscale
  userspace netstack)

RAM is the other limit. Sample RSS on the device before you leave it
running; the feasibility notes are in `docs/feasibility-report.md`.

## Configure

```sh
cp .env.example .env
cp scripts/yun.env.example scripts/yun.env
```

Fill LAN IPs, the PC’s WOL MAC, and `YUN_ALERTS_SCRIPT` (absolute path to
`scripts/watch-yun-alerts-host.sh`). Copy `yun.env` onto the USB stick next
to `start.sh`.

## Host alerts

```sh
ln -sfr "$PWD/.env" ~/.config/arduino-tailscaled.env
ln -sfr "$PWD/scripts/yun-alerts-host.service" ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now yun-alerts-host.service
```

## USB stick on the Yun

Copy `start.sh`, `supervise.sh`, `watchdog.sh`, `notify.sh`, `usb-env.sh`,
`wol`, and `yun.env` onto the stick (the `yun-usb-*.sh` names in this repo).
`rc.local` should call `start.sh` after USB and DNS are up.

Auth is a one-shot `--auth-key-stdin` on the bridge. The node identity then
lives in the state file on USB.

## Build

`scripts/build-yun-tailssh-bridge.sh` cross-builds the soft-float MIPS
binary with the OpenWrt 25.12.6 ath79 SDK.

## License

[Do whatever you want except sell it](LICENSE). Use it, fork it, give it
away. Do not sell this software.
