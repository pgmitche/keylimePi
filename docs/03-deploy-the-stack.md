# 3. Deploy the stack

Done on the mini PC, over SSH or directly.

## Clone and run

```bash
git clone <your-repo-url> keylimePi
cd keylimePi
./setup.sh
```

## What `setup.sh` actually does

1. Creates `.env` from `.env.example` if it doesn't exist yet, and fills in any
   value you left blank: timezone (from the OS), a random Pi-hole password, your
   LAN subnet (from your default route), sensible defaults for everything else.
2. Installs Podman and Tailscale via `pacman`, and enables `podman-restart.service`
   (Podman's daemonless equivalent of "containers come back after a reboot") and
   `tailscaled`.
3. Brings Tailscale up as a **subnet router** for your home LAN (see
   [docs/04-tailscale-and-remote-dns.md](04-tailscale-and-remote-dns.md) for what
   that buys you) — opens a one-time browser login link if you didn't set
   `TAILSCALE_AUTHKEY`.
4. Checks for `/dev/dri` (an Intel or AMD iGPU) and, if found, generates a
   `docker-compose.override.yml` that passes it through to Jellyfin for hardware
   transcoding.
5. Downloads and pre-installs Jellyfin's official **Bookshelf** plugin (books and
   audiobooks) into the Jellyfin config volume before first start, so it's just
   there — no clicking through Dashboard → Plugins → Catalog. Set
   `INSTALL_BOOKSHELF_PLUGIN=false` in `.env` to skip this.
6. Starts Pi-hole, Unbound, and Jellyfin with `podman-compose up -d`.
7. Prints a summary: URLs, the Pi-hole password, your Tailscale IP, and next steps.

It's safe to re-run — re-running only fills in `.env` values still blank, and every
step downstream of that is idempotent.

## Firewall

This box is a dedicated appliance, so `setup.sh` locks it down with **ufw**: a default
deny-incoming policy plus explicit allows for exactly what should be reachable — your
**SSH** access and the stack (**Pi-hole DNS**, its **admin UI**, and **Jellyfin**) —
scoped to your LAN subnet and the tailnet interface, never the public internet. You
don't run anything by hand; setup.sh does it. The effective rules:

```text
allow in on tailscale0                       # all tailnet traffic (SSH/DNS/admin/Jellyfin)
allow from <LAN_CIDR> to any port 22/tcp     # SSH
allow from <LAN_CIDR> to any port 53         # Pi-hole DNS
allow from <LAN_CIDR> to any port 80/tcp     # Pi-hole admin UI
allow from <LAN_CIDR> to any port 8096/tcp   # Jellyfin
default deny incoming
```

These are by **interface** (`tailscale0`) and **subnet** (`LAN_CIDR` from `.env`), not
by device IP, and **ufw persists them across reboots** — set once, they survive
restarts and any DHCP address changes. Check them any time with `sudo ufw status`.

> setup.sh allows SSH *before* enabling ufw, so it never cuts the session you run it
> over. If `LAN_CIDR` can't be detected it deliberately leaves ufw *off* rather than
> risk locking you out — set `LAN_CIDR` in `.env` and re-run to enable it.

## Point your devices at Pi-hole for DNS

Getting ad-blocking onto your devices happens two ways, and they're not either/or:

- **Whole home (every device on your LAN):** set your **router's DHCP DNS server** to
  the mini PC's LAN IP. Every phone, TV, and IoT device then uses Pi-hole automatically
  while at home. This needs the mini PC's **LAN IP to be stable** — set a **DHCP
  reservation** on your router (map the mini PC's MAC to a fixed address) so it doesn't
  change on reboot.
- **Your devices anywhere (via the tailnet):** point the tailnet's DNS at the mini PC's
  Tailscale IP — covered in [docs/04](04-tailscale-and-remote-dns.md#2-make-pi-hole-your-tailnet-wide-dns-server).
  The Tailscale IP is stable across reboots, so no static LAN IP is needed for this
  path. This is what gets you Pi-hole on your phone on mobile data, away from home.

Most setups use both. If you only care about your own devices everywhere, the tailnet
path alone is enough and you can skip the router/DHCP-reservation step.

## Verify it's working

A few quick checks once `setup.sh` finishes (give Pi-hole 30–60 seconds first —
its first start downloads blocklists):

```bash
# Pi-hole is blocking ads and resolving real domains
dig @127.0.0.1 doubleclick.net +short      # expect 0.0.0.0 (blocked)
dig @127.0.0.1 example.com +short          # expect a real IP

# Unbound is answering behind it, recursively
dig @127.0.0.1 -p 5335 example.com +short  # expect the same real IP

# Jellyfin is up
curl -sI http://localhost:8096/health      # expect HTTP/1.1 200 OK

# Tailscale is connected
tailscale status
```

If the first `dig` hangs or errors, that's the Pi-hole troubleshooting section
below, not a Jellyfin or Tailscale problem — work through it in this order, since
later checks depend on earlier ones working.

## Environment variables (`.env`)

| Variable | What it's for | Default if blank |
| --- | --- | --- |
| `TZ` | Timezone for Pi-hole and Jellyfin logs/schedules | detected from OS |
| `HOSTNAME` | Name for the Pi-hole container and the tailnet device | `keylime-pi` |
| `PIHOLE_PASSWORD` | Pi-hole admin web UI password | randomly generated |
| `PUID` / `PGID` | UID/GID Jellyfin runs as (match your user — check with `id`) | `1000` / `1000` |
| `MEDIA_PATH` | Host path containing your media folders | `./media` |
| `LAN_CIDR` | Your home subnet, e.g. `192.168.1.0/24` — advertised to the tailnet | detected from default route |
| `TAILSCALE_AUTHKEY` | Reusable auth key for non-interactive login | unset → interactive browser login |
| `ADVERTISE_EXIT_NODE` | Offer this box as a Tailscale exit node (route all traffic through home) | `false` |
| `INSTALL_BOOKSHELF_PLUGIN` | Pre-install Jellyfin's Bookshelf plugin (books/audiobooks) | `true` |

## If you actually wanted a different fourth tool

`docker-compose.yml` only has three services (`pihole`, `unbound`, `jellyfin`) —
Tailscale runs on the host, not in a container (see docs/04). If Unbound wasn't
what you meant by "that other one," some common swaps:

- **Portainer** (container management UI) — add a service with
  `image: portainer/portainer-ce:latest`, mount `/run/podman/podman.sock` (rootful
  Podman's API socket — needs `sudo systemctl enable --now podman.socket` first,
  which `setup.sh` doesn't currently do) and a `portainer_data` volume, publish
  port `9443`.
- **Watchtower** (automatic container updates) — add a service with
  `image: containrrr/watchtower`, same `/run/podman/podman.sock` mount.
- An `*arr` stack (Sonarr/Radarr/Prowlarr for automated media fetching) — each is
  its own service, typically on a shared bridge network rather than host
  networking. Worth its own follow-up if you want it.

## Why Podman, and how it's wired up

This stack runs on **Podman**, in **rootful** mode (every `podman`/`podman-compose`
call in `setup.sh` goes through `sudo`) — `docker-compose.yml` works unchanged,
`podman-compose` reads the same file. A few things worth knowing about the choice:

- Podman is daemonless, so there's no `dockerd`-equivalent service to enable. The
  one thing that **does** need enabling is `podman-restart.service` — without it,
  containers come back after a crash but not after a host reboot, since there's no
  background process to relaunch them. `setup.sh` enables it for you.
- Rootful, not rootless: Podman's headline feature is rootless containers, but
  this stack needs to bind port 53 and use `network_mode: host`, both of which
  rootless mode makes genuinely painful (low ports need extra sysctl tuning) for
  no real benefit on a single dedicated appliance box. There's also no
  group-membership shortcut around `sudo` the way Docker's `docker` group
  provides — every management command needs it.
- Pi-hole ⇄ Unbound talk over a published port bound to `127.0.0.1` on the host,
  rather than Docker's container-network-sharing trick
  (`network_mode: service:pihole`) — support for that syntax is inconsistent
  across Compose-for-Podman implementations, so this uses only the plain
  port-publishing every compose tool handles identically. Same end result: Unbound
  is reachable from Pi-hole (and nothing else, anywhere).
- **OrbStack** doesn't enter into this — it's a macOS/Windows desktop app, not
  something you'd install on the headless mini PC. It's only worth knowing about
  if you want to test `docker-compose.yml` locally on your Mac before deploying
  the real thing (OrbStack's Linux machines come with a container engine built in).

## Troubleshooting

**Pi-hole's web UI is up but DNS doesn't work / `dig @127.0.0.1 example.com` says
"connection refused".** The container is running but FTL (Pi-hole's DNS engine)
couldn't bind port 53. Confirm it in the logs:

```bash
sudo podman logs --tail 40 pihole | grep -i 'port 53\|address in use'
# CRIT: ... failed to create listening socket for port 53: Address in use
```

Then find what's holding port 53:

```bash
sudo ss -tulpn | grep ':53'
```

`setup.sh` handles this automatically on a fresh install, but if you're fixing a
running box, there are **two** things that squat on port 53, and you may hit either
or both:

*1. `systemd-resolved` (on `127.0.0.53:53` / `127.0.0.54:53`).* Its DNS stub
collides with Pi-hole's all-interfaces bind. Disabling isn't enough — it gets pulled
back in (e.g. by a NetworkManager restart), so **mask** it, and give the host a
static resolver so it keeps working:

```bash
sudo systemctl disable --now systemd-resolved
sudo systemctl mask systemd-resolved
sudo rm -f /etc/resolv.conf
printf 'nameserver 127.0.0.1\nnameserver <your-router-ip>\n' | sudo tee /etc/resolv.conf   # 2nd = your router (e.g. 192.168.1.1)
printf '[main]\ndns=none\n' | sudo tee /etc/NetworkManager/conf.d/dns-none.conf     # stop NM overwriting it
sudo systemctl restart NetworkManager
```

*2. `aardvark-dns` (on the Podman bridge gateway, e.g. `10.89.0.1:53`).* Podman runs
this whenever a container is on a **bridge** network — and it takes port 53 on that
bridge, colliding with Pi-hole's wildcard bind. This stack avoids it by putting
**Unbound on `network_mode: host`** (not a bridge with published ports) — see the
comment on the `unbound` service in `docker-compose.yml`. If you see `aardvark-dns`
on port 53, a container has ended up on a bridge network; recreate the stack cleanly:

```bash
sudo podman-compose down          # removes the bridge network, stopping aardvark-dns
sudo podman-compose up -d
```

After clearing whichever applies, confirm FTL now owns port 53:

```bash
sudo ss -tulpn | grep ':53'        # should now show pihole-FTL
dig @127.0.0.1 example.com +short  # should return a real IP
```

**Jellyfin transcoding isn't using the GPU.** `setup.sh` only wires up the device
passthrough — you still need to turn it on inside Jellyfin: **Dashboard → Playback
→ Transcoding → Hardware acceleration → Intel QuickSync (QSV)** (or VAAPI for AMD),
then enable the codecs you want hardware-accelerated.

**Bookshelf plugin isn't showing up in Jellyfin.** `setup.sh` pulls a pinned
version from `repo.jellyfin.org` and skips cleanly (with a warning, not a failed
setup) if that fails — check the warning output, or just install it the normal
way from **Dashboard → Plugins → Catalog → Bookshelf** (it's official, listed by
default) and restart the Jellyfin container.

**Containers didn't come back after a power outage / reboot.** Check
`systemctl status podman-restart.service` — if it's not enabled, run
`sudo systemctl enable --now podman-restart.service` and reboot to confirm.

**`podman-compose: command not found`.** The pacman install step in `setup.sh`
should have covered this — check it actually completed without errors
(`sudo pacman -Q podman-compose`), and re-run `./setup.sh` if not.

**Checking logs:**

```bash
sudo podman-compose logs -f pihole
sudo podman-compose logs -f unbound
sudo podman-compose logs -f jellyfin
```

## Reference links

- [Pi-hole docs](https://docs.pi-hole.net) — see especially the
  [Docker configuration page](https://docs.pi-hole.net/docker/configuration/)
  for the full `FTLCONF_*` environment variable reference
- [Pi-hole Discourse forum](https://discourse.pi-hole.net) for anything not
  covered in the docs
- [Unbound's own docs](https://unbound.docs.nlnetlabs.nl) if you want to tune
  `config/unbound/unbound.conf` further
- [Jellyfin docs](https://jellyfin.org/docs) and
  [hardware acceleration guide](https://jellyfin.org/docs/general/post-install/transcoding/hardware-acceleration/)
- [Podman docs](https://docs.podman.io) and
  [troubleshooting guide](https://github.com/containers/podman/blob/main/troubleshooting.md)
- [Arch Wiki: Podman](https://wiki.archlinux.org/title/Podman)

## Updating

```bash
cd keylimePi
git pull
sudo podman-compose pull
sudo podman-compose up -d
```

## Next

[docs/04-tailscale-and-remote-dns.md](04-tailscale-and-remote-dns.md) — making this
all reachable (and ad-blocked) from outside your home network.
