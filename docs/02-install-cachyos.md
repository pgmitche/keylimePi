# 2. Install CachyOS on the mini PC

Done on the mini PC itself, with the USB drive from
[docs/01-prepare-boot-media.md](01-prepare-boot-media.md) plugged in, and (for this
step only) a monitor, keyboard, and a wired or Wi-Fi internet connection.

CachyOS's installer pulls packages during installation rather than only from the
ISO, so it needs working internet. **The installer won't even launch without a
connection** — plug in Ethernet if you can (it just works, no setup). If you only
have Wi-Fi and no mouse, connect from a terminal with the text-based tool:

```bash
nmtui
```

It's fully keyboard-navigable — arrows to move, Enter to select, Tab to jump to
buttons. Choose **Activate a connection**, pick your network, enter the password.
Confirm you're online with `ping -c3 cachyos.org`.

## A note on the Windows install already on it

This guide assumes you're replacing Windows entirely — sensible for a box whose job
is to run a 24/7 home server stack. If you'd rather keep Windows around for
something else, CachyOS's wiki has a
[dual-boot guide](https://wiki.cachyos.org/installation/installation_on_root/);
the short version is that dual-booting Windows and Linux on the same drive is
reliable most of the time, but a Windows update can occasionally overwrite the boot
partition, so a second drive (if your mini PC has room for one) is the safer way to
dual-boot if that's the route you want.

## 1. Boot from the USB

1. Power on the mini PC and immediately start tapping the boot-menu key. This
   varies by brand — commonly `F7`, `F11`, `Esc`, or `Del` — check the splash
   screen on first boot or your mini PC's manual if none of those work.
2. In the boot menu, select the USB drive. It often appears **twice** — a
   `UEFI: <drive name>` entry and a plain/legacy one. **Choose the `UEFI:` entry**;
   the ISO was written for UEFI booting.
3. The USB boots into a **GRUB menu** — select the top **CachyOS** entry to start the
   live environment.
4. If the USB doesn't appear as a boot option at all, go into the BIOS/UEFI setup
   proper and **disable Secure Boot** (CachyOS isn't signed for it) and **disable
   Fast Boot** if present, then try again.
5. You should land in the CachyOS live desktop.

## 2. Run the installer

CachyOS uses the **Calamares** graphical installer. Launch it from the **Welcome to
CachyOS** window that opens on the live desktop — its **Launch Installer** button —
not a desktop icon.

### No mouse? Keyboard-only navigation

Calamares is click-heavy, so if you don't have a mouse, either:

- **Enable Mouse Keys** — press **Left Alt + Left Shift + Num Lock** to control the
  pointer with the numpad (`8/2/4/6` move, `5` clicks). Easiest if your keyboard has
  a numpad.
- **Navigate by keyboard** — **Tab / Shift+Tab** move between controls, **arrows**
  move within a list or radio group, and — importantly — **Space** selects *and
  presses buttons*. Enter often does nothing on a focused button, so use **Space**
  for every Next / Install / Confirm.

### Through the wizard

- **Desktop environment**: pick one. For a box that's mostly going to run headless
  once it's set up, **XFCE** is a good choice — light on resources, but still a full
  desktop if you ever plug in a monitor for troubleshooting. (KDE Plasma or Hyprland
  are popular if you'd prefer something richer.) The choice isn't permanent — you can
  install another desktop later with `sudo pacman -S <name>`.
- **Partitioning**: for a dedicated server, **erase the disk** and use it entirely
  for CachyOS — simplest and most reliable. Only choose manual partitioning if
  you're deliberately dual-booting (see above). When you pick Erase disk, Calamares
  asks for a **filesystem** — choose **btrfs**: it's the CachyOS default and gives you
  snapshots, so a broken update on this unattended box is a one-step rollback instead
  of a reinstall. Leave **Encrypt system** *unchecked* — a headless server can't type
  a passphrase at every boot.
- **User account**: create your user, and pick a **hostname** now — using the same
  one you'll later put in `.env` (`keylime-pi` by default) keeps things consistent.
- Finish the install, reboot when prompted, and remove the USB drive when it tells
  you to. **If it boots straight back into the installer**, your BIOS is still set to
  boot the USB first — power off, unplug the USB, and power on (or use the boot menu
  to pick the internal disk). Booting the live USB again is harmless; it doesn't touch
  the installed system.

## 3. First boot housekeeping

> **Note:** CachyOS's default shell is **fish**, not bash. Plain commands work
> everywhere, but bash-only syntax (`<<EOF` heredocs, `$()` in some forms) won't —
> when you hit that, either pipe from `printf`/`echo`, or wrap the command in
> `bash -c "..."`. `setup.sh` is unaffected; it has its own bash shebang.

Once you're logged into the fresh install, open a terminal and run:

```bash
# Update everything
sudo pacman -Syu

# Find the fastest mirrors for your location (CachyOS-specific tool)
cachyos-rate-mirrors

# Make sure these are installed — setup.sh will also do this, but no harm
# making sure SSH access works before you walk away from the monitor
sudo pacman -S --needed git openssh
sudo systemctl enable --now sshd
```

CachyOS's installer auto-detects your CPU and GPU and installs the right drivers
and optimized package set for them (handled by its `chwd` hardware-detection tool),
so there's nothing extra to configure there — this matters later for Jellyfin's
hardware transcoding, which `setup.sh` wires up automatically.

## 4. Confirm you can reach it over the network

The goal here is to reach the box over SSH so you can ditch the monitor and keyboard.
Three things commonly block this on a fresh CachyOS install — do all three on the
mini PC:

**1. Enable SSH** (also in §3, repeated here because it's the first requirement):

```bash
sudo systemctl enable --now sshd
```

**2. Open SSH in the firewall.** CachyOS may ship **ufw** active, which silently drops
*all* inbound TCP (you'll see connections time out while ping still works). Check and
allow SSH — keep the firewall on, just permit the port:

```bash
sudo ufw status                                   # if "active", the next line is needed
sudo ufw allow from 192.168.0.0/16 to any port 22 proto tcp   # adjust to your LAN range
```

**3. If the mini PC is on Wi-Fi, disable power saving.** A dozing Wi-Fi card answers
pings but drops incoming TCP, so SSH times out intermittently. Make it permanent:

```bash
printf '[connection]\nwifi.powersave = 2\n' | sudo tee /etc/NetworkManager/conf.d/wifi-powersave-off.conf
sudo systemctl restart NetworkManager
```

(Better yet, use Ethernet for a 24/7 server and skip this entirely.)

**Find the IP** to connect to:

```bash
ip -4 addr show scope global      # the address before the "/" (e.g. 192.168.1.50)
```

**Then, from another machine on the same LAN:**

```bash
ssh your-username@<mini-pc-ip-address>
```

Once SSH works, disconnect the monitor and keyboard — everything from here is remote.
After Tailscale is up (doc 04), you'll connect over the tailnet by its stable
Tailscale IP / MagicDNS name, which survives reboots and IP changes.

## Keep it always-on (headless hardening)

A 24/7 server must never sleep — but a **desktop-profile install will suspend on idle**
when nobody's at the keyboard, which silently takes the whole stack *and* Tailscale
offline (symptom: the box shows "offline" / an exit node stops working whenever you're
*not* SSH'd in). Two culprits: the desktop's idle daemon (Hyprland ships `hypridle`)
and logind's idle handling.

`setup.sh` already handles the core of this — it masks the sleep targets and sets
logind to ignore idle. If you're hardening an existing box by hand:

```bash
# Never suspend/sleep/hibernate (also neutralizes a desktop idle daemon)
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
# logind: ignore idle + lid
sudo mkdir -p /etc/systemd/logind.conf.d
printf '[Login]\nIdleAction=ignore\nHandleLidSwitch=ignore\nHandleLidSwitchExternalPower=ignore\n' | sudo tee /etc/systemd/logind.conf.d/keepawake.conf
sudo systemctl restart systemd-logind
```

**Recommended for a headless box: drop the desktop entirely.** It removes `hypridle`
outright, frees RAM, and there's nothing to display anyway:

```bash
sudo systemctl set-default multi-user.target   # boot to console; graphical.target to undo
sudo systemctl reboot
```

**If it still goes dormant when idle after all that**, the remaining cause is the
**Ethernet NIC powering down its link** when there's no traffic (the wired twin of
Wi-Fi power save). Disable it persistently — turn off Energy-Efficient Ethernet on the
wired interface (swap `eno1` for yours from `ip -br link`):

```bash
# one-off test
sudo ethtool --set-eee eno1 eee off
# make it stick every boot via a NetworkManager dispatcher script
printf '#!/bin/sh\n[ "$2" = up ] && ethtool --set-eee %s eee off\n' eno1 \
  | sudo tee /etc/NetworkManager/dispatcher.d/50-eee-off >/dev/null
sudo chmod +x /etc/NetworkManager/dispatcher.d/50-eee-off
```

## Troubleshooting

**No boot menu key works.** Check the mini PC manufacturer's site for the exact
key — common alternatives beyond F7/F11/Esc/Del include F2, F9, or F12 depending
on brand. As a fallback, most BIOS/UEFI setups let you reorder the boot priority
to put the USB drive first, then just power-cycle.

**Installer hangs or fails partway through.** Almost always the internet
connection (see the note above) or a corrupted ISO — re-verify the checksum from
[docs/01](01-prepare-boot-media.md) if you skipped it the first time.

**Install fails at `create-pacman-keyring` / "could not be locally signed".** The
system clock is wrong, so GPG rejects the keys (a fresh Linux boot on a PC that ran
Windows often reads the hardware clock hours off). Fix the clock, rebuild the
keyring, then relaunch the installer. In a terminal:

```bash
# 1. Correct the clock (needs the network up)
sudo timedatectl set-ntp true
timedatectl                       # confirm "System clock synchronized: yes"

# 2. Rebuild the keyring the crashed run left half-built.
#    /etc/pacman.d/gnupg is a tmpfs mount, so unmount before deleting.
sudo umount /etc/pacman.d/gnupg   # add -l if it says "device or resource busy"
sudo rm -rf /etc/pacman.d/gnupg
sudo pacman-key --init
sudo pacman-key --populate        # should finish with no "locally signed" errors
```

Then relaunch from the Welcome app and run the installer again.

**No Wi-Fi adapter detected in the live environment.** Use Ethernet for the
install if at all possible — CachyOS's hardware detection installs the right
Wi-Fi driver as part of installation, so a Wi-Fi-only first boot can be a
chicken-and-egg problem on less common chipsets.

## Reference links

- [CachyOS wiki](https://wiki.cachyos.org/) — search bar covers almost everything
- [CachyOS forum](https://discuss.cachyos.org) — for anything install-specific
  that the wiki doesn't cover
- [Arch Wiki: General recommendations](https://wiki.archlinux.org/title/General_recommendations) —
  useful once you're past install and into day-to-day system administration

## Next

Clone this repo onto the mini PC and continue with
[docs/03-deploy-the-stack.md](03-deploy-the-stack.md).
