# 4. Tailscale and remote DNS

After `setup.sh` finishes, your mini PC is on your tailnet as a **subnet router**,
advertising your whole home LAN — not just itself. This section wires up the rest:
ad-blocked, private DNS on every device you own, wherever you are, plus access to
Jellyfin (and anything else on your home LAN) from outside the house.

> **Before this works, you need a Tailscale account.** Create a free one at
> [login.tailscale.com/start](https://login.tailscale.com/start) — you sign in with
> a Google/GitHub/Microsoft/Apple identity (SSO, no separate password), and the
> Personal plan covers this whole stack. Your **tailnet is defined by the account
> you sign in with**, so use a *personal* identity here — if you already use
> Tailscale for work and sign in with that same work SSO, the mini PC lands on your
> employer's tailnet instead of your own. When `setup.sh` prints a login link, open
> it and sign in with this personal account to put the mini PC on your own tailnet.

## 1. Approve the subnet route (one-time)

If `setup.sh` detected your LAN subnet, the route needs a one-time approval before
it's usable:

1. Go to **[login.tailscale.com/admin/machines](https://login.tailscale.com/admin/machines)**.
2. Find this device — it'll show a **Subnets** badge.
3. Open its menu → **Edit route settings** → enable the advertised subnet.

## 2. Make Pi-hole your tailnet-wide DNS server

This is what gets you ad-blocking and private DNS on your phone, laptop, anywhere —
not just at home.

1. Go to **[login.tailscale.com/admin/dns](https://login.tailscale.com/admin/dns)**.
2. Under **Nameservers**, add a nameserver and enter the mini PC's **Tailscale IP**
   (printed at the end of `setup.sh`, or run `tailscale ip -4` on the mini PC).
3. Toggle **Override DNS servers** on.

From now on, every device connected to your tailnet uses Pi-hole + Unbound for DNS
— ads and trackers blocked, queries resolved privately, no matter what network
you're actually on.

## 3. Install Tailscale on your other devices

Download the app for [iOS](https://apps.apple.com/app/tailscale/id1470499037),
[Android](https://play.google.com/store/apps/details?id=com.tailscale.ipn),
[macOS/Windows/Linux](https://tailscale.com/download), sign in with the same
account, and you're connected. No port forwarding, no firewall rules on your
router — Tailscale punches through NAT on both ends.

### Connecting after a reboot (why you don't need a static LAN IP)

A device's **Tailscale IP is permanent** — it's tied to the node's identity and
survives reboots, DHCP lease changes, even moving to a different network. With
**MagicDNS** on, the box also gets a stable name. So the reboot-proof way to reach the
mini PC is over the tailnet, not the LAN:

```bash
tailscale ip -4          # on the mini PC: its stable Tailscale IP, e.g. 100.x.y.z
ssh your-username@100.x.y.z
# or, with MagicDNS: ssh your-username@<hostname>.<your-tailnet>.ts.net
```

(See [Connecting to your services remotely](#connecting-to-your-services-remotely)
below for how to find your exact MagicDNS name — the tailnet part is auto-assigned.)

The mini PC's **LAN** IP (from your router's DHCP) *can* change on reboot — that only
matters if you point LAN devices at Pi-hole by its LAN IP (see
[docs/03](03-deploy-the-stack.md#point-your-devices-at-pi-hole-for-dns)), in which case
set a DHCP reservation on your router. For everything over the tailnet, the Tailscale
address already gives you a fixed target.

### Your iPhone: ad-blocking + Jellyfin anywhere

This is the payoff — an iPhone that's ad-blocked and can stream your media whether
it's at home or on mobile data on the other side of the world. One-time setup:

1. **Install Tailscale** from the App Store and sign in with the **same personal
   account** the mini PC is on.
2. **Turn Tailscale on.** iOS adds it as a VPN profile and connects. To keep it
   always up, enable **VPN On Demand** in the Tailscale app settings — that's what
   makes the ad-blocking and Jellyfin access "just work" without thinking about it.

Once connected:

- **Ad-blocking + private DNS, everywhere.** Because the tailnet's DNS is pointed at
  Pi-hole (step 2 above, *Override DNS servers* on), your iPhone uses Pi-hole for
  every DNS lookup whenever Tailscale is connected — at home *and* on cellular. Ads
  and trackers are blocked network-wide, in every app and Safari, with no per-app
  content blocker. (Disconnect Tailscale and you fall back to normal DNS — so leave
  it on.)
- **Jellyfin, from anywhere.** Install a Jellyfin client — the official **Jellyfin**
  app, or **Swiftfin** / **Infuse** — and point it at the mini PC over the tailnet:

  ```text
  http://<mini-pc-Tailscale-IP>:8096                 e.g. http://100.x.y.z:8096
  # or, with MagicDNS:  http://<hostname>.<your-tailnet>.ts.net:8096
  ```

  (Find the Tailscale IP with `tailscale ip -4` on the mini PC, or in the
  [admin console](https://login.tailscale.com/admin/machines).) It streams over the
  encrypted tunnel — same URL at home or away, no port-forwarding, nothing exposed to
  the public internet.

The same steps work on Android (Tailscale + a Jellyfin client) and on a laptop.

### Your Mac (or any laptop)

1. **Install Tailscale** and sign in with the **same personal account**. On macOS,
   prefer the **Mac App Store** build — its login is per-macOS-user, so if someone
   else on the Mac uses Tailscale for work, your tailnet stays separate. (If you use
   the standalone build and share it with a work login, switch profiles with
   `tailscale switch <your-personal-email>`.)
2. **Connect from the menu-bar icon**, and enable **Connect on login** so it's always
   up.
3. **Turn on the app's DNS setting** ("Use Tailscale DNS Settings" in the menu-bar
   menu). This is what makes the Mac use Pi-hole — without it, macOS keeps its own DNS
   and you get no ad-blocking.

Once connected:

- **Ad-blocking + private DNS, everywhere.** Same as the phone: with the tailnet DNS
  pointed at Pi-hole and the app's DNS setting on, every lookup on the Mac goes through
  Pi-hole whenever Tailscale is connected — home or anywhere.
- **Jellyfin in the browser** — no app needed:

  ```text
  http://<mini-pc-Tailscale-IP>:8096                 e.g. http://100.x.y.z:8096
  # or, with MagicDNS:  http://<hostname>.<your-tailnet>.ts.net:8096
  ```

  (Swiftfin and Infuse have Mac apps too if you'd rather not use the browser.)

- **SSH / admin** over the tailnet works from here as well — `ssh <user>@100.x.y.z`
  and the Pi-hole admin UI at `http://<Tailscale-IP>/admin`.

## Connecting to your services remotely

Once Tailscale is running on the device you're using, your services are reachable from
anywhere — home, cellular, another country — over the encrypted tunnel. Nothing is
exposed to the public internet, so **access only works while Tailscale is connected**:
turn it off and connections fail. That's the security model working, not a bug.

### Addressing the mini PC

Two stable ways to reach it, both surviving reboots:

- **Tailscale IP** — run `tailscale ip -4` on the mini PC, or read it from the
  [admin console](https://login.tailscale.com/admin/machines). Looks like `100.x.y.z`.
  Always works, needs no DNS.
- **MagicDNS name** (if MagicDNS is enabled under admin → DNS): the form is
  `<hostname>.<your-tailnet>.ts.net`. Your **tailnet name is randomly assigned** by
  Tailscale (e.g. `happy-panda.ts.net`) — find your exact one in the
  [admin console](https://login.tailscale.com/admin/dns). The short `<hostname>` alone
  resolves only on devices that have **Use Tailscale DNS Settings** turned on.

Same URLs at home and away — swap in your Tailscale IP (or MagicDNS name):

| Service | URL |
| --- | --- |
| Jellyfin | `http://<tailscale-ip>:8096` |
| Pi-hole admin | `http://<tailscale-ip>/admin` |
| SSH | `ssh <username>@<tailscale-ip>` |

Point client apps (the Jellyfin mobile app, etc.) at the **Tailscale IP**, not the LAN
address — the LAN address only works over the tailnet if you've approved the subnet
route (step 1).

### Sharing with a family member

The **Personal plan includes up to 6 users** plus device sharing. Two ways:

- **Invite them to your tailnet** — simplest for household family. Admin console →
  **Users → Invite**, send the link. They install Tailscale, sign in, and can reach
  shared devices (Jellyfin, and Pi-hole DNS if you want them ad-blocked too).
  [How-to](https://tailscale.com/docs/features/sharing/how-to/invite-users).
- **Share just the mini PC** — for someone who has their own Tailscale, or to limit
  them to *only* this box. Admin console → **Machines → the mini PC → Share**. They get
  access to that one machine only — invisible to their other devices, no reach into the
  rest of your network. [How-to](https://tailscale.com/docs/features/sharing).

## 4. Reaching things on your home LAN remotely

Because this box is a subnet router, your phone (say, on mobile data, away from
home) can reach:

- **Jellyfin**: `http://<mini-pc-LAN-IP>:8096` works exactly as it does at home —
  Tailscale routes it through the tunnel transparently.
- **Pi-hole admin**: `http://<mini-pc-LAN-IP>/admin`
- Anything else on your home LAN (a NAS, a smart TV, a router admin page), once the
  subnet route is approved — that's the point of a subnet router over just
  installing Tailscale on individual devices.

## Optional: exit node

If you also want to route *all* of a device's internet traffic through your home
connection (e.g. for a consistent home IP while travelling), make this box an exit
node too. The repeatable way is to set it in `.env` and re-run `setup.sh`:

```bash
# in .env
ADVERTISE_EXIT_NODE=true
```
```bash
./setup.sh          # re-applies the exit-node advertisement (IP forwarding is already on)
```

Or set it directly without re-running setup:

```bash
sudo tailscale set --advertise-exit-node
```

Either way, two manual steps remain (Tailscale's double opt-in — a script can't do
them):

1. **Approve it:** admin console → this device → **Edit route settings** → enable
   **Use as exit node**.
2. **Select it on the client:** in the Tailscale app choose this box as the Exit Node
   (or `tailscale set --exit-node=<this-device-hostname>`).

This is optional and unrelated to the DNS/media-server goals above — skip it unless
you specifically want it.

> **Using this to get through a censored network (e.g. China):** an exit node only
> helps if Tailscale can *connect* in the first place, and heavily-censored networks
> block Tailscale's coordination and DERP relay servers. See the note below on DERP —
> and be aware that a DERP relay has to live somewhere reachable from *outside* the
> censored network, which your home mini PC (behind your ISP's NAT) is not.

## Why not just port-forward instead?

You could open ports 53 and 8096 on your router and skip Tailscale entirely — this
stack deliberately doesn't, because:

- Port 53 (DNS) exposed to the internet is a classic target for DNS amplification
  abuse.
- Pi-hole and Jellyfin's web UIs aren't designed to be internet-facing without
  additional hardening (a reverse proxy, auth, TLS, rate limiting).
- Tailscale gets you the same remote access with none of that — every connection
  is mutually authenticated and encrypted, and nothing is reachable by anyone who
  isn't a device on your tailnet.

## Troubleshooting

**Device doesn't show up in the admin console.** `setup.sh` either printed a login
link (click it) or, if `TAILSCALE_AUTHKEY` was set, should have connected silently
— check with `sudo tailscale status` on the mini PC; `Logged out` means the login
never completed.

**Subnet route shows but traffic doesn't reach your LAN.** Almost always the
one-time approval in step 1 above being missed, or `--accept-routes` not being on
for the *client* device — check the
[subnet router setup guide](https://tailscale.com/docs/features/subnet-routers) for the
double-opt-in model (advertise *and* approve, on two different devices).

**A device is on the tailnet but still sees ads / doesn't use Pi-hole.** Work
through these in order — each one bypasses Pi-hole even when everything else is right:

1. **Override DNS servers is off.** Confirm it's toggled on under **Global
   nameservers** at [login.tailscale.com/admin/dns](https://login.tailscale.com/admin/dns).
   Without it, Tailscale's resolver (`100.100.100.100`) only answers `*.ts.net` names
   and forwards everything else to the device's *other* DNS — no ad-blocking. (After
   flipping it, reconnect Tailscale on the device so it re-reads the setting.)
2. **The device has a DNS server hardcoded.** A manually-set DNS (e.g. `8.8.8.8`)
   overrides Tailscale's. On macOS: `networksetup -getdnsservers Wi-Fi` — if it lists
   anything, clear it with `sudo networksetup -setdnsservers Wi-Fi Empty`. On iOS:
   Settings → Wi-Fi → (i) → Configure DNS → **Automatic**.
3. **IPv6 DNS leak.** Many routers advertise an IPv6 DNS server that the OS keeps
   using *alongside* Tailscale, quietly bypassing Pi-hole for anything with an IPv6
   path. Symptom: `dig @100.100.100.100 doubleclick.net` returns `0.0.0.0` (Pi-hole
   works) but a plain `dig doubleclick.net` returns a real IP. Fix on macOS:
   `sudo networksetup -setv6off Wi-Fi` (reversible with `-setv6automatic`; IPv4 still
   does everything). This is a per-device setting.

Verify the *system* resolver — not just `dig @<pihole-ip>`, which bypasses the OS
config — with a plain `dig doubleclick.net +short` (want `0.0.0.0`) and
`dig example.com +short` (want a real IP). On macOS, flush first with
`sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder`.

**Exit node approved but client won't select it.** Exit nodes need the same
double-opt-in as subnet routes — check
[login.tailscale.com/admin/machines](https://login.tailscale.com/admin/machines)
for an **Exit node** badge needing approval, separate from the subnet route badge.

## Reference links

- [Tailscale docs](https://tailscale.com/kb) — the canonical source for anything
  in this doc, especially if Tailscale's UI has moved since this was written
- [Subnet routers](https://tailscale.com/docs/features/subnet-routers)
- [DNS in Tailscale / MagicDNS](https://tailscale.com/docs/reference/dns-in-tailscale)
- [Tailscale status page](https://status.tailscale.com) if remote access stops
  working and nothing here explains why
