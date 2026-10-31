<img src="assets/icon.svg" width="64" height="64" alt="">

# arduino-tailscaled

Minimal Tailscale path for an Arduino Yún Rev2 (OpenWrt, AR9330, 8 MiB overlay):
a Rust userspace bridge that accepts tailnet TCP 22 and forwards it to local
Dropbear, plus USB watchdog/crash notes and a LAN-PC alert listener.

Official Go `tailscaled` does not fit the overlay. Do not put an auth key in
this repo, a script, or flash.

## Configure

Machine-specific values live in env files, not in git:

```sh
cp .env.example .env          # LAN PC
cp scripts/yun.env.example scripts/yun.env   # then copy yun.env onto the USB stick
```

Fill IPs, the PC MAC for Wake-on-LAN, and `YUN_ALERTS_SCRIPT` (absolute path to
`scripts/watch-yun-alerts-host.sh`).

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

## Build

`scripts/build-yun-tailssh-bridge.sh` cross-builds a soft-float MIPS binary
with the OpenWrt 25.12.6 ath79 SDK. Details: `docs/feasibility-report.md`.
