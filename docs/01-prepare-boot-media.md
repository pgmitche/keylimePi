# 1. Prepare a CachyOS boot drive (Windows or Mac)

This is "step zero" — done on whatever computer you're reading this from, not the
mini PC. End result: a USB drive that boots into the CachyOS installer.

You'll need a USB drive with **at least 8GB** of free space. Everything on it will
be erased.

## 1. Download the ISO

Go to **[cachyos.org/download](https://cachyos.org/download/)** and grab the
**Desktop edition** ISO. (CachyOS doesn't have a separate server ISO yet — that's
fine, see [docs/02-install-cachyos.md](02-install-cachyos.md) for how this maps onto
a headless mini PC.) Download the matching `.sha256` file from the same page —
you'll use it in the next step to make sure the download isn't corrupted.

The download button pulls from the CachyOS mirror. If you'd rather grab the files
directly (or the button doesn't work), browse
**[mirror.cachyos.org/ISO/desktop/](https://mirror.cachyos.org/ISO/desktop/)** — each
subfolder is a build dated `YYMMDD`, so the highest number is the newest. The ISO is
named `cachyos-desktop-linux-YYMMDD.iso` (the `XXXXXX` in the commands below is that
date stamp), with `.sha256` alongside it.

## 2. Verify the download

### Windows

```powershell
certUtil -hashfile cachyos-desktop-linux-XXXXXX.iso SHA256
```

Compare the output against the contents of the `.sha256` file (open it in Notepad).
They should match exactly.

### Mac

Easiest — let `shasum` do the comparison for you (both files must be in the same
folder):

```bash
shasum -a 256 -c cachyos-desktop-linux-XXXXXX.iso.sha256
```

It prints `cachyos-desktop-linux-XXXXXX.iso: OK` on a match, or `FAILED` if not.

Or print the hash and eyeball it against the `.sha256` file yourself:

```bash
shasum -a 256 cachyos-desktop-linux-XXXXXX.iso
```

If they don't match, re-download before going further — a corrupted ISO is one of
the most common causes of a failed or flaky install.

## 3. Write the ISO to USB

### Windows — Rufus

1. Download **[Rufus](https://rufus.ie)** (portable `.exe`, no install needed).
2. Plug in the USB drive.
3. Open Rufus → **Device**: select your USB drive.
4. **Boot selection** → **SELECT** → choose the CachyOS ISO.
5. Leave the partition scheme on its default (Rufus auto-detects GPT/UEFI for you).
6. Click **START**. Rufus will likely ask whether to write in **ISO Image mode** or
   **DD Image mode** — choose **DD Image mode**. CachyOS's ISO is a hybrid image
   (like most Arch-based distros), and DD mode writes it correctly; ISO mode can
   produce a USB that doesn't boot properly.
7. Confirm the erase warning, wait for it to finish, then eject safely.

### Mac — Terminal (`dd`)

No extra software needed.

```bash
# 1. Find your USB drive — look for the right size in the list
diskutil list

# 2. Unmount it (replace diskN with what you found above, e.g. disk4)
diskutil unmountDisk /dev/diskN

# 3. Write the ISO — target the WHOLE disk (rdiskN), not a partition (rdiskNs1).
#    Note the 'r' in rdiskN — the raw device is much faster than diskN.
#    Use an absolute path for the ISO; '~' may not expand under sudo.
sudo dd if=/Users/you/Downloads/cachyos-desktop-linux-XXXXXX.iso of=/dev/rdiskN bs=4M status=progress

# 4. Eject once it's done
diskutil eject /dev/diskN
```

Double-check the disk number from `diskutil list` before running `dd` — it writes
directly to whatever device you point it at, with no undo.

A few things that look like problems but aren't:

- **`dd` sits there showing nothing for a while.** Normal — `status=progress`
  doesn't print until the first block is written. Give it a minute. (Write speed is
  drive/port dependent; a USB 2.0 drive at ~5 MB/s takes ~10 min for a 2.9GB ISO.)
- **`Resource busy`.** macOS silently re-mounted the drive between steps 2 and 3.
  Re-run `diskutil unmountDisk /dev/diskN`, then the `dd` again.
- **Target the whole disk, not a partition.** `diskutil list` shows both `disk4`
  (the whole drive) and `disk4s1` (a partition on it). Flash the whole disk —
  `/dev/rdisk4`, never `/dev/rdisk4s1`.
- **"The disk you inserted was not readable by this computer" pops up when `dd`
  finishes.** This means it *worked* — macOS just can't read the Linux filesystem
  now on the drive. Click **Eject** (or **Ignore**). **Never click Initialize…** —
  that reformats the drive and destroys the image you just wrote.

### Mac — GUI alternative (balenaEtcher)

If you'd rather not use the terminal, **[balenaEtcher](https://etcher.balena.io)**
does the same job with a 3-step UI: select the ISO, select the USB drive, flash.
It also verifies the write afterwards, which `dd` doesn't do on its own.

## Troubleshooting

**Rufus says the ISO is invalid / won't select it.** Re-download and re-verify the
checksum (step 2) — this is almost always a partial or corrupted download, not a
Rufus problem.

**`dd` finishes in a couple of seconds — too fast to be real.** You likely pointed
it at the wrong disk identifier (or a partition like `/dev/disk4s1` instead of the
whole disk `/dev/disk4`). Re-check `diskutil list` and try again.

**USB drive doesn't show up as a boot option on the mini PC.** Covered in
[docs/02](02-install-cachyos.md) — usually Secure Boot or boot order in the
BIOS/UEFI, not a problem with the drive itself.

## Reference links

- [CachyOS download page](https://cachyos.org/download/) and [wiki](https://wiki.cachyos.org/) (search bar at the top covers most install issues)
- [Rufus FAQ](https://github.com/pbatard/rufus/wiki/FAQ)
- [balenaEtcher docs](https://docs.balena.io/reference/balena-etcher/)

## Next

Take the USB drive to the mini PC and continue with
[docs/02-install-cachyos.md](02-install-cachyos.md).
