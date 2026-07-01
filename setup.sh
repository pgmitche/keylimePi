#!/usr/bin/env bash
#
# keylimePi — one-command setup.
#
# Installs Podman + Tailscale, brings this box up as a Tailscale subnet router for
# your home LAN, detects a GPU for Jellyfin hardware transcoding, pre-installs the
# Jellyfin Bookshelf plugin, and starts Pi-hole + Unbound + Jellyfin under Podman.
#
# Runs Podman in rootful mode (via sudo), not rootless: this stack needs to bind
# port 53 and use host networking, which rootless Podman makes needlessly painful
# for very little benefit on a single dedicated appliance box.
#
# Safe to re-run: it only fills in .env values that are still blank, and every
# system change it makes (pacman installs, systemd enables, podman-compose up) is
# idempotent.

set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENV_FILE=".env"

log() { printf '\n==> %s\n' "$1"; }
warn() { printf '\n!! %s\n' "$1" >&2; }

# ---------------------------------------------------------------------------
# 0. Sanity checks
# ---------------------------------------------------------------------------
if ! command -v pacman >/dev/null 2>&1; then
  warn "This script expects an Arch-based system (pacman not found)."
  warn "It's written for CachyOS — see docs/02-install-cachyos.md."
  exit 1
fi

if [ "$(id -u)" -eq 0 ]; then
  warn "Run this as your normal user, not root — it will ask for sudo when needed."
  exit 1
fi

log "Checking sudo access (you may be asked for your password)..."
sudo -v

# ---------------------------------------------------------------------------
# 1. Load / scaffold .env
# ---------------------------------------------------------------------------
if [ ! -f "$ENV_FILE" ]; then
  log "No .env found — creating one from .env.example."
  cp .env.example "$ENV_FILE"
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

update_env() {
  local key="$1" val="$2"
  if grep -q "^${key}=" "$ENV_FILE"; then
    sed -i "s|^${key}=.*|${key}=${val}|" "$ENV_FILE"
  else
    echo "${key}=${val}" >> "$ENV_FILE"
  fi
  export "${key}=${val}"
}

generate_password() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | cut -c1-20
  else
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c20
  fi
}

default_iface() {
  ip -o -4 route show to default 2>/dev/null | awk '{print $5}' | head -n1
}

detect_lan_cidr() {
  local iface
  iface="$(default_iface)"
  [ -z "$iface" ] && return 1
  ip -o -4 route show scope link dev "$iface" 2>/dev/null | awk '{print $1}' | head -n1
}

detect_lan_ip() {
  local iface
  iface="$(default_iface)"
  [ -z "$iface" ] && return 1
  ip -o -4 addr show dev "$iface" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1
}

log "Filling in any blank .env values..."
[ -z "${TZ:-}" ]              && update_env TZ "$(timedatectl show -p Timezone --value 2>/dev/null || echo UTC)"
[ -z "${HOSTNAME:-}" ]        && update_env HOSTNAME "keylime-pi"
[ -z "${PIHOLE_PASSWORD:-}" ] && update_env PIHOLE_PASSWORD "$(generate_password)"
[ -z "${PUID:-}" ]            && update_env PUID "1000"
[ -z "${PGID:-}" ]            && update_env PGID "1000"
[ -z "${MEDIA_PATH:-}" ]      && update_env MEDIA_PATH "./media"
[ -z "${INSTALL_BOOKSHELF_PLUGIN:-}" ] && update_env INSTALL_BOOKSHELF_PLUGIN "true"
if [ -z "${LAN_CIDR:-}" ]; then
  DETECTED_CIDR="$(detect_lan_cidr || true)"
  if [ -n "$DETECTED_CIDR" ]; then
    update_env LAN_CIDR "$DETECTED_CIDR"
  else
    warn "Couldn't auto-detect your LAN subnet. Tailscale will still work for this"
    warn "box itself — set LAN_CIDR in .env and re-run if you want it to route your"
    warn "whole home network too."
  fi
fi

echo "Settings in use:"
echo "  HOSTNAME=${HOSTNAME}"
echo "  TZ=${TZ}"
echo "  LAN_CIDR=${LAN_CIDR:-<not detected>}"
echo "  MEDIA_PATH=${MEDIA_PATH}"

# ---------------------------------------------------------------------------
# 2. Install Podman + Tailscale
# ---------------------------------------------------------------------------
log "Installing Podman and Tailscale (pacman)..."
# -Syu, not just -Sy: installing new packages without a full sync+upgrade risks a
# partial upgrade on Arch (a new package built against newer libs than what's
# currently on disk) — see wiki.archlinux.org/title/System_maintenance#Partial_upgrades.
sudo pacman -Syu --noconfirm --needed podman podman-compose podman-docker tailscale openssh git curl unzip bind ufw

# Podman is daemonless — no dockerd-style service to enable. The one thing that
# does need enabling is podman-restart.service: without it, containers with
# restart: unless-stopped come back after a crash but NOT after a host reboot,
# since there's no persistent daemon to relaunch them — this systemd unit is
# Podman's own mechanism for that, run once at boot.
sudo systemctl enable --now podman-restart.service
sudo systemctl enable --now tailscaled
sudo systemctl enable --now sshd || true

# Keep this 24/7 headless box awake. A desktop-profile install ships an idle daemon
# (e.g. Hyprland's hypridle) and logind can suspend on idle — which takes the whole
# stack AND Tailscale offline whenever nobody's connected. Masking the sleep targets
# makes even a stray `systemctl suspend` from an idle daemon a no-op; the logind drop
# is belt-and-suspenders (applies on next boot). To go further, drop the desktop
# entirely with `sudo systemctl set-default multi-user.target` (see docs/02).
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target >/dev/null 2>&1 || true
sudo mkdir -p /etc/systemd/logind.conf.d
printf '[Login]\nIdleAction=ignore\nHandleLidSwitch=ignore\nHandleLidSwitchExternalPower=ignore\n' \
  | sudo tee /etc/systemd/logind.conf.d/keepawake.conf >/dev/null

# ---------------------------------------------------------------------------
# 3. Bring up Tailscale as a subnet router
# ---------------------------------------------------------------------------
log "Enabling IP forwarding so this box can route your home LAN over Tailscale..."
echo 'net.ipv4.ip_forward = 1' | sudo tee /etc/sysctl.d/99-tailscale.conf >/dev/null
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf >/dev/null
sudo sysctl -p /etc/sysctl.d/99-tailscale.conf >/dev/null

if sudo tailscale status >/dev/null 2>&1; then
  # Already logged in to a tailnet — re-apply settings rather than skipping
  # entirely, so changing LAN_CIDR or HOSTNAME in .env and re-running actually
  # takes effect without needing to log out and back in.
  log "Tailscale already connected — refreshing its settings..."
  SET_ARGS=(--hostname="${HOSTNAME}" --accept-dns=false)
  if [ -n "${LAN_CIDR:-}" ]; then
    SET_ARGS+=(--advertise-routes="${LAN_CIDR}")
  fi
  if [ "${ADVERTISE_EXIT_NODE:-false}" = "true" ]; then
    SET_ARGS+=(--advertise-exit-node)
  fi
  sudo tailscale set "${SET_ARGS[@]}"
  if [ -n "${LAN_CIDR:-}" ] || [ "${ADVERTISE_EXIT_NODE:-false}" = "true" ]; then
    warn "Newly-advertised routes/exit-node need approval at:"
    warn "  https://login.tailscale.com/admin/machines  →  this device  →  Edit route settings"
  fi
else
  UP_ARGS=(--hostname="${HOSTNAME}" --accept-dns=false)
  if [ -n "${LAN_CIDR:-}" ]; then
    UP_ARGS+=(--advertise-routes="${LAN_CIDR}")
  fi
  if [ "${ADVERTISE_EXIT_NODE:-false}" = "true" ]; then
    UP_ARGS+=(--advertise-exit-node)
  fi
  if [ -n "${TAILSCALE_AUTHKEY:-}" ]; then
    UP_ARGS+=(--authkey="${TAILSCALE_AUTHKEY}")
  fi

  log "Starting Tailscale. If no auth key was set, a login link will be printed below"
  echo "    — open it in a browser once to connect this device to your tailnet."
  sudo tailscale up "${UP_ARGS[@]}"

  if [ -n "${LAN_CIDR:-}" ]; then
    warn "Subnet route ${LAN_CIDR} still needs a one-time approval:"
    warn "  https://login.tailscale.com/admin/machines  →  this device  →  Edit route settings"
  fi
fi

# ---------------------------------------------------------------------------
# 4. Detect a GPU for Jellyfin hardware transcoding
# ---------------------------------------------------------------------------
if [ -d /dev/dri ] && [ -n "$(ls -A /dev/dri 2>/dev/null)" ]; then
  log "GPU found at /dev/dri — enabling hardware transcoding for Jellyfin."
  cat > docker-compose.override.yml <<'EOF'
services:
  jellyfin:
    devices:
      - /dev/dri:/dev/dri
EOF
else
  log "No /dev/dri found — Jellyfin will use software transcoding for now."
  rm -f docker-compose.override.yml
fi

# ---------------------------------------------------------------------------
# 5. Preflight: free port 53 for Pi-hole
# ---------------------------------------------------------------------------
# Pi-hole (host networking, listeningMode=all) binds port 53 on every interface.
# systemd-resolved's DNS stub sits on 127.0.0.53:53 and collides with that, so
# Pi-hole's DNS silently fails to start. On a box whose whole job is to BE the
# resolver, the right move is to hand port 53 to Pi-hole: disable + mask resolved
# and give the host a static resolver so it keeps working (and stays fixed across
# reboots). ponytail: mask, not just stop — 'disable --now' alone gets undone when
# something pulls resolved back in (e.g. a NetworkManager restart).
if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
  warn "systemd-resolved holds port 53 — handing that port to Pi-hole."
  sudo systemctl disable --now systemd-resolved || true
  sudo systemctl mask systemd-resolved || true
  # 'disable --now' can leave the process alive when socket-triggering units
  # (systemd-resolved-*.socket) keep pulling it back — kill it so port 53 is
  # actually freed. The mask above stops it starting again.
  sudo pkill -9 systemd-resolve 2>/dev/null || true
  gateway="$(ip route 2>/dev/null | awk '/default/ {print $3; exit}')"
  sudo rm -f /etc/resolv.conf
  {
    echo "nameserver 127.0.0.1"                       # Pi-hole itself, once it's up
    [ -n "${gateway}" ] && echo "nameserver ${gateway}"  # fallback so DNS works if Pi-hole is down
  } | sudo tee /etc/resolv.conf >/dev/null
  if [ -d /etc/NetworkManager ]; then
    printf '[main]\ndns=none\n' | sudo tee /etc/NetworkManager/conf.d/dns-none.conf >/dev/null
    sudo systemctl reload NetworkManager 2>/dev/null || sudo systemctl restart NetworkManager || true
  fi
fi

# Anything else still on port 53 (that isn't ours) will block Pi-hole — warn only,
# since we don't know what it is or whether it's safe to stop.
if sudo ss -tulpn 2>/dev/null | grep ':53 ' | grep -qv 'pihole-FTL'; then
  warn "Something other than Pi-hole is still listening on port 53 — Pi-hole may fail"
  warn "to start. See the port-53 troubleshooting in docs/03-deploy-the-stack.md."
fi

# ---------------------------------------------------------------------------
# 6. Create data directories
# ---------------------------------------------------------------------------
log "Creating data directories..."
mkdir -p data/pihole data/unbound data/jellyfin/config data/jellyfin/cache
mkdir -p "${MEDIA_PATH}"

# ---------------------------------------------------------------------------
# 7. Pre-install the Bookshelf plugin (books & audiobooks) for Jellyfin
# ---------------------------------------------------------------------------
# Jellyfin scans its plugins/ folder on startup, so dropping the official
# plugin in place before the container's first boot means it's just there —
# no clicking through Dashboard > Plugins > Catalog needed. Safe to re-run:
# it leaves an existing install alone so it doesn't fight with Jellyfin's own
# update mechanism once you're managing it from the UI.
if [ "${INSTALL_BOOKSHELF_PLUGIN:-true}" = "true" ]; then
  PLUGIN_DIR="data/jellyfin/config/plugins/Bookshelf"
  if [ -d "$PLUGIN_DIR" ] && [ -n "$(ls -A "$PLUGIN_DIR" 2>/dev/null)" ]; then
    log "Bookshelf plugin already present — leaving it as-is."
  else
    log "Installing the Bookshelf plugin (books & audiobooks) for Jellyfin..."
    BOOKSHELF_VERSION="13.0.0.0"
    BOOKSHELF_URL="https://repo.jellyfin.org/releases/plugin/bookshelf/bookshelf_${BOOKSHELF_VERSION}.zip"
    TMP_DIR="$(mktemp -d)"
    if curl -fsSL "$BOOKSHELF_URL" -o "$TMP_DIR/bookshelf.zip" 2>/dev/null; then
      mkdir -p "$PLUGIN_DIR"
      if unzip -oq "$TMP_DIR/bookshelf.zip" -d "$PLUGIN_DIR" 2>/dev/null \
         && [ -n "$(find "$PLUGIN_DIR" -name '*.dll' 2>/dev/null)" ]; then
        sudo chown -R "${PUID:-1000}:${PGID:-1000}" "$PLUGIN_DIR"
        log "Bookshelf plugin installed — point a library at your books/audiobooks"
        echo "    folder and pick the 'Books' content type once Jellyfin is up."
      else
        warn "Bookshelf plugin didn't extract cleanly — skipping it for now."
        warn "Install it later from Jellyfin's Dashboard > Plugins > Catalog instead."
        rm -rf "$PLUGIN_DIR"
      fi
    else
      warn "Couldn't reach repo.jellyfin.org to fetch the Bookshelf plugin — skipping."
      warn "Install it later from Jellyfin's Dashboard > Plugins > Catalog (it's"
      warn "official and listed there by default)."
    fi
    rm -rf "$TMP_DIR"
  fi
fi

# ---------------------------------------------------------------------------
# 8. Start the stack
# ---------------------------------------------------------------------------
log "Pulling images..."
sudo podman-compose pull

log "Starting the stack..."
sudo podman-compose up -d

# ---------------------------------------------------------------------------
# 9. Firewall: lock the box down to SSH + the stack (ufw)
# ---------------------------------------------------------------------------
# This box is a dedicated appliance — the only things that should be reachable are
# your SSH access and the stack (Pi-hole DNS + its admin UI + Jellyfin). ufw enforces
# that: default deny-incoming, plus explicit allows scoped to the tailnet interface
# and the LAN subnet — never the public internet.
#
# Rules are by INTERFACE (tailscale0) and SUBNET (LAN_CIDR), not by device IP, and
# ufw persists them across reboots: set once, they survive restarts and any DHCP
# address change. Re-running setup.sh just re-applies them (ufw skips duplicates).
#
# Order matters: allow SSH BEFORE enabling, so the SSH session you're running this
# over isn't cut. If LAN_CIDR is unknown we do NOT enable the firewall (that could
# lock you out) — we only warn.
if command -v ufw >/dev/null 2>&1; then
  sudo ufw allow in on tailscale0 >/dev/null 2>&1 || true   # all tailnet traffic (SSH/DNS/admin/Jellyfin)
  if [ -n "${LAN_CIDR:-}" ]; then
    sudo ufw allow from "${LAN_CIDR}" to any port 22 proto tcp   >/dev/null 2>&1 || true  # SSH
    sudo ufw allow from "${LAN_CIDR}" to any port 53             >/dev/null 2>&1 || true  # Pi-hole DNS
    sudo ufw allow from "${LAN_CIDR}" to any port 80 proto tcp   >/dev/null 2>&1 || true  # Pi-hole admin
    sudo ufw allow from "${LAN_CIDR}" to any port 8096 proto tcp >/dev/null 2>&1 || true  # Jellyfin
    sudo ufw default deny incoming  >/dev/null 2>&1 || true
    sudo ufw default allow outgoing >/dev/null 2>&1 || true
    sudo ufw --force enable >/dev/null 2>&1 || true
    log "Firewall locked to SSH + the stack, over the LAN (${LAN_CIDR}) and tailnet."
  else
    warn "LAN_CIDR unknown — NOT enabling ufw (could lock out SSH). Set LAN_CIDR in"
    warn ".env and re-run to enable the locked-down firewall."
  fi
fi

# ---------------------------------------------------------------------------
# 10. Summary
# ---------------------------------------------------------------------------
TS_IP="$(sudo tailscale ip -4 2>/dev/null || echo 'unavailable')"
# Deliberately not `hostname -I`: once Tailscale is up, that can return the
# tailscale0 address first depending on interface ordering. Asking for the
# address on the default-route interface is unambiguous.
LAN_IP="$(detect_lan_ip || echo '<run: ip addr>')"

cat <<EOF

================================================================
 keylimePi is up.
================================================================
 Pi-hole admin:   http://${LAN_IP}/admin
 Pi-hole password: ${PIHOLE_PASSWORD}   (also saved in .env)
 Jellyfin:        http://${LAN_IP}:8096
 Tailscale IP:    ${TS_IP}

 Bookshelf plugin (books & audiobooks): ${INSTALL_BOOKSHELF_PLUGIN:-true}

 Next steps:
 1. On your router, set the LAN DNS server to ${LAN_IP} so every device on
    your network gets ad-blocking automatically (see docs/03).
 2. In the Tailscale admin console, set ${TS_IP} as a global DNS nameserver
    so you get the same ad-blocking + private DNS away from home
    (see docs/04-tailscale-and-remote-dns.md).
 3. Open Jellyfin and run through its first-time setup wizard.
 4. Manage the stack later with: sudo podman-compose [logs|restart|pull] ...
    Podman's rootful mode always needs sudo — there's no group-membership
    shortcut around it the way Docker has.

 Re-run ./setup.sh any time — it's safe to run again.
================================================================
EOF
