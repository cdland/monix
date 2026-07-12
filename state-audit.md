# fw3 state & determinism audit — 2026-07-12

Everything below reflects the end of the 2026-07-12 hardening pass. The fixes
themselves (ghostty activation race, xdg-document-portal mask, journald bound,
Plymouth LUKS prompt, KDE app integration, DMS-owned cursors, greeter
wallpaper mirror, Comic Code via agenix, assets/ layout) are merged, deployed
to fw3, and documented in the modules that carry them — this file tracks only
what is still OPEN.

## Open: declarative user password (gate before enabling)

`users.mutableUsers = false` + `hashedPasswordFile` wiring sits **commented**
in `hosts/fw3/fw3.mod.nix`; the agenix rule (`hosts/fw3/dylan-password.age`)
is already in `secrets.nix`. With `mutableUsers = false` and no declared
password the account is locked out (wheel sudo needs a password; SSH keys
don't help). Enable only after:

```
mkpasswd -m yescrypt                          # copy the hash
cd ~/ark/monix && agenix -e hosts/fw3/dylan-password.age   # paste hash, save
# then uncomment the block in hosts/fw3/fw3.mod.nix (add `config` to its args),
# build, switch, and verify `sudo -v` from a second session before logging out.
```

fw0 note: when hosts eventually all go immutable, fw0 needs the same
treatment for its user first.

## Open: one-time checks on fw3

- Confirm the agenix host key added to `keys.nix` (taken TOFU over the
  tailnet) matches `cat /etc/ssh/ssh_host_ed25519_key.pub` on fw3. Comic Code
  decrypting successfully is already strong evidence it's right.
- Delete the flatpak husk: `rm -r ~/.local/share/flatpak` (empty db dir;
  flatpak was never installed, `/var/lib/flatpak` does not exist).
- Delete the manually-installed Comic Code copy once `fc-list | grep -i
  comic` shows only `/var/lib/fonts/comic-code` paths, then `fc-cache -f`.

## Open: on-host census (read-only; paste results back for triage)

```bash
# uid/gid allocations vs declared users/groups (report only)
cat /var/lib/nixos/uid-map /var/lib/nixos/gid-map

# root filesystem census: regular files outside expected trees
sudo find / -xdev \( -path /nix -o -path /boot -o -path /home -o -path /proc \
  -o -path /sys -o -path /run -o -path /tmp -o -path /var/lib/nixos \
  -o -path /var/log -o -path /var/lib/tailscale -o -path /etc/ssh \
  -o -path /var/lib/systemd -o -path /var/lib/private \) -prune -o -type f -print | sort

# GC roots census (stale result symlinks, orphaned direnv roots)
nix-store --gc --print-roots | grep -v ^/proc

# expected keepers: /etc/machine-id, /etc/ssh/ssh_host_*, /var/lib/nixos/*,
# /var/lib/tailscale, journal under /var/log, /var/lib/systemd (timers/rtc),
# /var/lib/bluetooth, /var/lib/NetworkManager, /var/lib/fwupd, syncthing state,
# CUPS state under /var/cache+/etc/cups if any.
```

## Deliberately imperative (keep, by design)

- DMS GUI-owned runtime files: `~/.config/hypr/dms/outputs.lua`,
  `~/.config/hypr/dms/cursor.lua`, DMS theme/settings state, and the seeded
  `~/.config/kdeglobals` (KDE apps write back to it). Documented in
  hyprland.mod.nix / kde.mod.nix.
- Login password stays `passwd`-managed until the gate above is done.

## Resolved this pass (for the record)

- Boot/LUKS "hybrid prompt": a display race — systemd-cryptsetup's console
  prompt vs amdgpu's async modeset; which wins is drive-enumeration timing.
  Fixed by Plymouth (`modules/desktop/plymouth.mod.nix`), verified clean at
  boot. Early KMS was already forced by nixos-hardware; Plymouth was never
  the cause (it had never been enabled).
- Repo/host drift: fw3's behind-and-dirty checkout is converged; its
  `nix flake update` is committed (also clearing the khal/`click-threading`
  build breakage that had made fw3 unbuildable from the committed lock);
  fw3 pushes/pulls GitHub fine from an interactive session.
