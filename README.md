# keylimePi 🥧

> Turn a blank mini PC into a private home server — install CachyOS, then bring up
> ad-blocking DNS, a mesh VPN, and a media server with **one command**.

Clone-and-go: two prep steps to get CachyOS onto the box, then `./setup.sh` stands up
the whole stack.

## The stack

| Service | What it does |
| --- | --- |
| **Pi-hole** | Network-wide ad/tracker blocking (DNS sinkhole). |
| **Unbound** | Recursive resolver answering Pi-hole's queries straight from the root servers — no third-party DNS provider ever sees your browsing. |
| **Tailscale** | WireGuard mesh VPN to reach the stack from anywhere, with no port-forwarding and nothing exposed to the public internet. |
| **Jellyfin** | Media server — movies, TV, music, photos, books/audiobooks — with hardware-accelerated transcoding on an Intel/AMD iGPU. |

## Requirements

- A mini PC to dedicate to this (the guide replaces its current OS with CachyOS; see
  [docs/02](docs/02-install-cachyos.md) to dual-boot instead).
- A USB drive, 8GB or larger, that's OK to fully erase.
- A free [Tailscale account](https://login.tailscale.com/start).
- About an hour of hands-on time across the two prep steps, plus unattended
  download/install time in between.

## Quick start

Once CachyOS is installed on the mini PC:

```bash
git clone <your-repo-url> keylimePi
cd keylimePi
./setup.sh
```

`setup.sh` installs Podman and Tailscale, brings up Tailscale as a subnet router for
your home LAN, detects a GPU for hardware transcoding if present, and starts Pi-hole +
Unbound + Jellyfin. It's safe to re-run: it only fills in values you haven't already
set, and `podman-compose up -d` is idempotent.

New to any of this? [docs/03](docs/03-deploy-the-stack.md) walks through what each
part does and why before you run it.

## Documentation

| Step | Docs |
| --- | --- |
| 🥧 Prep a CachyOS boot drive from Windows or Mac, then install it | [01-prepare-boot-media](docs/01-prepare-boot-media.md) · [02-install-cachyos](docs/02-install-cachyos.md) |
| 🚀 One-command Pi-hole + Unbound + Tailscale + Jellyfin stack | [03-deploy-the-stack](docs/03-deploy-the-stack.md) · [04-tailscale-and-remote-dns](docs/04-tailscale-and-remote-dns.md) · [05-storage-simple-vs-naslike](docs/05-storage-simple-vs-naslike.md) |

## Repo layout

```text
keylimePi/
├── setup.sh                    ← the one command
├── docker-compose.yml          ← pihole + unbound + jellyfin
├── .env.example                ← copy to .env; setup.sh fills in the blanks
├── config/
│   └── unbound/unbound.conf    ← recursive resolver config
├── data/                       ← created at runtime, gitignored (persistent state)
└── docs/                       ← the numbered guides above
```

## Architecture

- **Pi-hole and Jellyfin run with `network_mode: host`.** This binds Pi-hole to port
  53 on every interface (LAN *and* Tailscale) without juggling port mappings, and it's
  what Jellyfin's docs recommend for reliable local network discovery. The trade-off —
  no network isolation from the host — is acceptable here since nothing is exposed to
  the public internet; Tailscale is the only inbound path, and it's a private,
  authenticated mesh, not a port forward.
- **Unbound is published only to `127.0.0.1`** on the host — not the LAN, not the
  tailnet — which is exactly where Pi-hole (sharing the host's loopback via
  `network_mode: host`) needs it.
- **Tailscale runs natively on the host**, not in a container, so it can act as a
  *subnet router* and advertise your whole home LAN to the tailnet. Remote devices
  reach not just Pi-hole and Jellyfin but anything on your home network, through one
  encrypted tunnel.
- **The container runtime is Podman, run rootful** (via `sudo`) — daemonless, a good
  fit for a single-purpose Linux box, and in the official Arch/CachyOS repos.
  `docker-compose.yml` keeps that filename since every tool involved reads it
  identically regardless of runtime.

Full reasoning in [docs/03-deploy-the-stack.md](docs/03-deploy-the-stack.md).

## Getting help

Each doc ends with a **Troubleshooting** or **Reference links** section pointing at the
relevant project's own docs. Starting points:

- [Pi-hole docs](https://docs.pi-hole.net) · [Pi-hole Discourse](https://discourse.pi-hole.net)
- [Jellyfin docs](https://jellyfin.org/docs) · [Jellyfin forum](https://forum.jellyfin.org)
- [Tailscale docs](https://tailscale.com/kb)
- [Podman docs](https://docs.podman.io) · [Podman troubleshooting](https://github.com/containers/podman/blob/main/troubleshooting.md)
- [CachyOS wiki](https://wiki.cachyos.org) · [CachyOS forum](https://discuss.cachyos.org)
- [Arch Wiki](https://wiki.archlinux.org)

## Verified against

Put together June 2026, against CachyOS's June 2026 release, Pi-hole v6 (Alpine-based
image with `FTLCONF_*` config), Jellyfin 10.11, Podman 5.8, and Tailscale's current
CLI. If something doesn't match what you're seeing — a renamed flag, a moved path — the
project's own current docs (linked above) are the tiebreaker.
