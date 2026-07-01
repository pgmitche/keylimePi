# 5. Storage: simple vs NAS-like

`MEDIA_PATH` in `.env` is the only thing that connects the stack to your storage —
Jellyfin just reads whatever's at that path. That means "simple" and "NAS-like" are
both just a question of **what you point `MEDIA_PATH` at**, not anything that needs
to change in `docker-compose.yml` or `setup.sh`. This doc covers the options so you
can pick one now and switch later without touching the stack itself.

`setup.sh` deliberately does **not** automate any of this — partitioning and pooling
drives is destructive and specific to your exact hardware, so it's a manual,
doc-driven step, unlike the networking side of things.

## Mode 1: Simple (what you'd use today)

Just a folder on the mini PC's own internal drive:

```ini
MEDIA_PATH=/home/youruser/media
```

Nothing else to configure. This is the right starting point given the storage
you've described — come back to this doc when you've actually got more drives in
hand.

## Getting media onto the server

The box is headless, so you add media over the network from your laptop with `scp`
(single files) or `rsync` (big files/folders — it shows progress and can resume).
`MEDIA_PATH` is mounted into Jellyfin as `/media`, so lay files out like this on the
host (under `MEDIA_PATH`):

```text
film/The Matrix (1999).mkv                     ← Movies  → Jellyfin "/media/film"
tv/Spider-Noir/Spider-Noir.S01E01.mkv          ← Shows   → Jellyfin "/media/tv"
photos/...                                      ← Photos  → Jellyfin "/media/photos"
```

Name movies `Title (Year).ext` and TV files with `SxxEyy` tokens so Jellyfin matches
metadata; one folder per show is enough (it reads the season from the episode names).

**Copy a movie** (run on your laptop; use the mini PC's LAN IP at home, or its
Tailscale IP from anywhere):

```bash
scp "The Matrix (1999).mkv" <user>@<mini-pc>:/home/<user>/media/film/
```

**Copy a season / large file** — `rsync` is better (progress, resumable). Note macOS's
built-in rsync is old and lacks `--info=progress2`; use `-P`:

```bash
rsync -avP "Spider-Noir S01/" <user>@<mini-pc>:/home/<user>/media/tv/Spider-Noir/
```

**Skip the password prompt** for repeat transfers — install your SSH key once:

```bash
ssh-copy-id <user>@<mini-pc>      # ssh-keygen -t ed25519 first if you have no key
```

**Then scan it in:** Jellyfin watches the folders and usually picks new files up on
its own; to force it, `http://<mini-pc>:8096` → Dashboard → Libraries → Scan Library
Files. Files land owned by your user (the UID Jellyfin runs as), so permissions just
work; if something ever doesn't appear, `sudo chown -R "$(id -u):$(id -g)" ~/media`.

Prefer drag-and-drop? Mount the media folder as a network share instead — see
[Mode 2C](#c-re-share-the-mini-pcs-own-pool-as-a-nas-for-other-devices).

## Mode 2: NAS-like

Three different things can fall under "NAS-like," depending on what you mean:

### A. Pool multiple drives *in* the mini PC (most likely what you meant)

The recommended pattern for a home media library that grows over time, with
mismatched drive sizes, no RAID card, and infrequent writes, is
**mergerfs + SnapRAID**:

- **mergerfs** pools several drives into one mount point (e.g. `/mnt/storage`) —
  drives can be any size, any filesystem, added or removed without rebuilding
  anything.
- **SnapRAID** adds parity protection calculated on a schedule (not real-time) —
  if a data drive dies, you restore it from parity; if you delete something by
  accident, you can recover it from the last sync. It's explicitly designed for
  "large files that rarely change" — i.e. exactly a media library.

This is deliberately *not* traditional RAID (mdadm) or ZFS:

- **btrfs RAID5/6** has a long-standing, still-unresolved "write hole" stability
  issue — useful to know if you see it suggested elsewhere, but not recommended.
  **btrfs RAID1** (mirroring) is solid and built into the kernel already if you
  ever just want to mirror two identical drives — simpler than mergerfs+SnapRAID,
  but less flexible about mismatched sizes or odd numbers of drives.
- **ZFS** is excellent, but on Arch/CachyOS it ships via DKMS from the AUR, and a
  fast-moving rolling kernel occasionally outpaces what OpenZFS supports — it gets
  fixed, but it's a real maintenance burden on a box that's supposed to mostly run
  itself. Worth it if you already know and like ZFS; not the easiest default here.

**Setup outline** (drive identifiers and sizes are examples — adjust to your
actual hardware):

```bash
# mergerfs and snapraid aren't in the official repos — install an AUR helper
# first if you don't have one. CachyOS's own repos still provide paru as an
# installable package even though recent ISOs no longer include it by default:
sudo pacman -S --needed paru
paru -S mergerfs snapraid

# Mount each physical drive somewhere sensible — add each to /etc/fstab first
# (by UUID, via `blkid`) so they're there reliably on every boot, then:
sudo mkdir -p /mnt/disk1 /mnt/disk2 /mnt/parity1
sudo mount -a

# Pool the data drives into one mount point with mergerfs. Test it by hand
# first, then make it permanent in /etc/fstab so it survives a reboot:
sudo mkdir -p /mnt/storage
sudo mergerfs /mnt/disk1:/mnt/disk2 /mnt/storage -o defaults,allow_other,use_ino

# /etc/fstab line for the above (uses mergerfs' own fstab syntax, not a
# regular bind mount):
# /mnt/disk1:/mnt/disk2 /mnt/storage fuse.mergerfs defaults,allow_other,use_ino,category.create=mfs 0 0

# Configure SnapRAID (/etc/snapraid.conf) pointing its parity at /mnt/parity1
# and its data disks at /mnt/disk1, /mnt/disk2, then run an initial sync:
sudo snapraid sync
```

Then point the stack at the pool:

```ini
MEDIA_PATH=/mnt/storage
```

Schedule `snapraid sync` (a systemd timer or cron, e.g. nightly) so parity stays
reasonably current — full automation of this is intentionally left to you, since
it depends on how often your library actually changes.

### B. Mount an existing/external NAS over the network

If "NAS-like" actually means a *separate* NAS device (Synology, TrueNAS, another
box) rather than the mini PC growing more drives, this is simpler — mount its
share and point `MEDIA_PATH` at the mount:

```bash
sudo mkdir -p /mnt/nas-media
# SMB:
sudo mount -t cifs //nas-ip/share /mnt/nas-media -o username=you,uid=1000,gid=1000
# or NFS:
sudo mount -t nfs nas-ip:/share /mnt/nas-media
```

Add the same to `/etc/fstab` so it survives a reboot, then:

```ini
MEDIA_PATH=/mnt/nas-media
```

### C. Re-share the mini PC's own pool as a NAS for other devices

If you want other devices on your network (not just Jellyfin) to see the same
media pool — e.g. to drop files onto it from a laptop — install Samba and share
`/mnt/storage` the normal way (`sudo pacman -S samba`, configure `/etc/samba/smb.conf`,
`sudo systemctl enable --now smb nmb`). This is independent of everything else
here and doesn't affect Jellyfin at all.

## Quick comparison

| | Simple | mergerfs + SnapRAID | btrfs RAID1 | ZFS |
| --- | --- | --- | --- | --- |
| Drives | 1 | 2+, any size | 2, matched | 2+ |
| Survives a drive dying | No | Yes (parity) | Yes (mirror) | Yes |
| Mismatched drive sizes | n/a | Yes | No | Awkward |
| Add a drive later | n/a | Easy | Rebuild | Easy (new vdev) |
| Packages | none | AUR | none (built in) | AUR, DKMS |
| Maintenance burden | none | low (schedule a sync) | none | medium on rolling kernel |

For where you're at right now — start with **Simple** — and when you add drives,
**mergerfs + SnapRAID** is the option most people in your situation end up on.

## Reference links

- [SnapRAID — Arch Wiki](https://wiki.archlinux.org/title/SnapRAID)
- [mergerfs — official docs](https://trapexit.github.io/mergerfs/)
- [SnapRAID official site](https://www.snapraid.it) — full config reference
- [ZFS — Arch Wiki](https://wiki.archlinux.org/title/ZFS) if you go that route
  anyway — read the DKMS/rolling-kernel caveats near the top first
