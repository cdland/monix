# nix-config

A single-repo, modular NixOS configuration built on the **Dendritic Pattern**
(flake-parts with `*.mod.nix` auto-discovery). It is Linux-only and designed so
that adding a host is a few lines.

Hosts: **fw3** (Framework 13 AMD 7040 running a Hyprland desktop shelled by
DankMaterialShell; formerly "fwork") and **vs0** (server running LiteLLM,
Open WebUI, and Tailscale).

## How it fits together

`flake.nix` imports every `*.mod.nix` file in the tree (via
`listFilesRecursive`), so modules are never listed centrally. Each module
registers *aspects* into one of three collections:

- `commonModules` — imported by every host (base system, options, secrets).
- `nixosModules` — the menu of NixOS aspects (ssh, hyprland, tailscale, the AI
  services, ...). All are imported into every host but most are inert until
  enabled.
- `homeModules` — Home Manager aspects applied to the primary user.

Packages follow one convention: a tool that carries configuration gets its own
concern file with package and settings together (`modules/git.mod.nix`,
`modules/ghostty.mod.nix`); config-less tools are grouped in
`modules/packages.mod.nix` as functional bundles; Nix-workflow tools sit with the
Nix concern in `modules/nix.mod.nix`. There is no separate `home/` directory — a
concern file registers its Home Manager aspect directly, and may also register a
NixOS aspect (as `hyprland.mod.nix` does for the compositor and the session).

`lib/` extends nixpkgs' lib. `lib.systems.nixosSystem "<name>" <module>` defines
`nixosConfigurations.<name>`.

A host (`hosts/<name>/<name>.mod.nix`) just imports the collections, sets its
class and hardware, and enables the services it wants:

```nix
imports =
  attrValues self.commonModules
  ++ attrValues self.nixosModules;

isDesktop = true;            # or false for a server
nixpkgs.hostPlatform = "x86_64-linux";
disko.devices.disk.main = { ... };   # declarative disk layout (see disko.mod.nix)
system.stateVersion = "26.05";
```

There is no `hardware-configuration.nix`: the host module carries the few
per-machine hardware facts (initrd kernel modules, microcode) directly, and
the disk layout is declared with disko, which both generates the mount config
and can format a blank disk to match.

### Desktop vs server

The single switch is `isDesktop` (default `false` ⇒ server). Desktop aspects
(Hyprland, audio, fonts, NetworkManager, the user's graphical session) gate on
it with `mkIf config.isDesktop`, so a server simply omits them by leaving the
flag false. Service aspects (LiteLLM, Open WebUI, Tailscale) gate on their own
`enable` option, which the host turns on.

## Adding a host

1. `mkdir hosts/<name>` and create `hosts/<name>/<name>.mod.nix` (copy fw3 or
   vs0). Set `isDesktop`, `nixpkgs.hostPlatform`, `system.stateVersion`.
2. Set the hardware facts and disko layout in the host module (crib the
   kernel-module list from `nixos-generate-config --show-hardware-config` on
   the machine; point `disko.devices.disk.main.device` at the disk's
   `/dev/disk/by-id/...` path).
3. Add the host's SSH host public key to `keys.nix` under `hosts.<name>`.
4. Add the host's secret rules to `secrets.nix` and create the secrets.
5. Build: `nixos-rebuild switch --flake .#<name>`.

No other file needs editing — auto-discovery and the aspect collections handle
the rest.

## Secrets (agenix)

agenix is used only for vs0's three service credentials (Tailscale, LiteLLM,
Open WebUI); login passwords are set imperatively (see below), so no user or
host needs a password secret to boot.

> **Warning — this repo's secrets are placeholders.** `keys.nix` currently
> holds the real admin key but **placeholder host keys**, and all three
> `.age` files under `hosts/vs0/` are **unencrypted placeholder text**
> (present only so test builds succeed). Before any real deploy: put the
> real host SSH keys in `keys.nix`, then recreate every `.age` file with
> `agenix -e`.

`keys.nix` is the single source of truth for SSH public keys (host keys + admin
keys). `secrets.nix` maps each secret file to the keys it is encrypted to and is
read by the `agenix` CLI. Secrets are decrypted on the host using its SSH host
key (`/etc/ssh/ssh_host_ed25519_key`).

**Bootstrap (per host):**

1. On the target machine, ensure host keys exist: `ssh-keygen -A`.
2. Copy its public key into `keys.nix`:
   `cat /etc/ssh/ssh_host_ed25519_key.pub`.
3. Put your personal public key in `keys.nix` under `admin`.
4. Create the secrets (an entry must already exist in `secrets.nix`):

   ```sh
   nix run github:ryantm/agenix -- -e hosts/vs0/tailscale.age
   nix run github:ryantm/agenix -- -e hosts/vs0/litellm.env.age
   nix run github:ryantm/agenix -- -e hosts/vs0/open-webui.env.age
   ```

`tailscale.age` holds a one-line reusable auth key (`tskey-auth-...`).

> Users are mutable (the NixOS default) — after install, set each account's
> login password imperatively with `passwd`. Login never depends on agenix,
> so a host can be built and activated with no secrets present at all.

## The AI stack on vs0

- **LiteLLM** runs on `127.0.0.1:4000` as an OpenAI-compatible gateway. Its
  `model_list` (in `hosts/vs0/vs0.mod.nix`) is illustrative — edit it for your
  providers. `os.environ/NAME` reads NAME from `litellm.env.age`, which must
  define `LITELLM_MASTER_KEY` and every referenced provider key, e.g.:

  ```sh
  LITELLM_MASTER_KEY=sk-...generate-a-strong-key...
  OPENAI_API_KEY=sk-...your-openai-key...
  ANTHROPIC_API_KEY=sk-ant-...your-anthropic-key...
  ```

- **Open WebUI** runs on `0.0.0.0:8080` and uses LiteLLM as its backend
  (`OPENAI_API_BASE_URL=http://127.0.0.1:4000/v1`). `open-webui.env.age` must
  set `OPENAI_API_KEY` to the **same value** as LiteLLM's `LITELLM_MASTER_KEY`
  (this is how Open WebUI authenticates to LiteLLM), plus a `WEBUI_SECRET_KEY`:

  ```sh
  OPENAI_API_KEY=sk-...same-as-LITELLM_MASTER_KEY...
  WEBUI_SECRET_KEY=...generate-a-strong-key...
  ```

Neither service opens the public firewall. They are reachable over **Tailscale**
(the `tailscale0` interface is trusted) and via localhost. Reach Open WebUI at
`http://<vs0-tailscale-ip>:8080`.

## Building

```sh
nix flake check                          # evaluate everything
nixos-rebuild switch --flake .#fw3       # or .#vs0
```

First install of a host, from any NixOS installer ISO (formats the disk
declared in the host's disko layout — destructive, check the device path):

```sh
sudo nix run github:nix-community/disko -- --mode disko --flake .#<host>
sudo nixos-install --flake .#<host>
```

## Design choices (deliberate)

- **Linux-only** — no darwin/macOS support.
- **`isDesktop` flag** with `mkIf` gating rather than per-host aspect menus —
  every aspect is imported everywhere and gates itself.
- **Home Manager** for the user session (best Hyprland support), organised as
  `homeModules` aspects.
- **No hardware-configuration.nix / nixos-facter** — per-host hardware facts
  live directly in the host module; disk layouts are declared with disko.
- **Explicit `secrets.nix` rules** (so `agenix -e` works when first creating a
  secret); agenix identity is the system SSH host key rather than a separate
  key partition.
- **No pipe operators** — see AGENTS.md.

## Hyprland notes

- **Hyprland config is written in Lua** (`configType = "lua"`), not hyprlang.
  Hyprland deprecated hyprlang at 0.55 (nixpkgs currently ships 0.55.4) in
  favor of Lua, with hyprlang stated to be dropped "1-2 releases" after 0.55
  (no specific version number given). `modules/hyprland/hyprland.mod.nix`
  carries a full rename table in its module-level comment (dispatcher names,
  window-rule effect names, the env-var mechanism, the bind/bindm/bindel/bindl
  merge) for anyone diffing it against hyprlang syntax. Binds are built with a
  small `mkBind`/`mkEnv` helper rather than hand-repeated `_args` blocks —
  this is also what makes `show-keybindings` work: each bind carries a
  `description`, read back at runtime via `hyprctl binds -j`, since a `.lua`
  config is executed rather than parseable the way a grep-based script would
  assume. None of this has been evaluated by `nix` or run against a live
  Hyprland — there is neither in this environment — so treat it as unverified
  until built.
- **Hyprland is pulled from nixpkgs**, not a git flake input — there are no
  Hyprland-specific flake inputs to track. UWSM is not used; greetd launches
  Hyprland directly.
- fw3's `system.stateVersion` is `"26.05"`. CaskaydiaMono Nerd Font is the
  desktop's default font.

### Desktop shell: DankMaterialShell

fw3's desktop shell is **DankMaterialShell** (DMS), enabled via the native
nixpkgs NixOS module `programs.dms-shell`
(nixpkgs ≥ 26.05, no extra flake input) in `modules/dank.mod.nix`, gated on
`isDesktop`. Hyprland starts it with `exec-once = dms run` plus a
`wl-paste --watch cliphist store` clipboard watcher. DMS supplies the bar,
notifications, app launcher (spotlight), OSD, control center, lock screen
with idle handling, wallpaper manager, clipboard history UI, and its own
polkit agent — replacing the `waybar`, `mako`, `tofi`, `hyprpaper`,
`hyprlock`, and `hypridle` aspects (all deleted) and home's
`services.hyprpolkitagent` (also deleted); `clipse` was replaced by
`cliphist`. Five binds were rewired to `dms ipc call ...`; the rest of the
66 `mkBind` entries are unchanged.

### Theming

Custom theming has been removed. `modules/theme/` (a static base16
gruvbox-dark-hard palette, a GTK Adwaita override, and the Bierstadt
wallpaper) is deleted; every app now uses its default theme — Hyprland's
default border colors, ghostty and btop's default palettes. hyprlock itself
is gone entirely rather than left unthemed. Theming may return in a future
pass.
