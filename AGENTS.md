# Conventions

This repository follows the **Dendritic Pattern**: every `*.mod.nix` file in the
tree is a flake-parts module and is discovered automatically by `flake.nix`.
There is no central module list. A file's directory is organisational only.

## Module shape

Each `*.mod.nix` is a flake-parts module. It typically registers one or more
*aspects* into a collection:

- `flake.commonModules.<name>` — imported by every host (base/cross-cutting).
- `flake.nixosModules.<name>`  — NixOS aspects (provided collection).
- `flake.homeModules.<name>`   — Home Manager aspects, applied to the primary user.

A single concern file may register several aspects at once — e.g. `hyprland.mod.nix`
defines both `nixosModules.hyprland` (compositor) and `homeModules.hyprland`
(session). Group files by concern, not by aspect target; there is no `home/`
directory.

Hosts in `hosts/<name>/<name>.mod.nix` compose these via
`attrValues self.commonModules ++ attrValues self.nixosModules`.

`self` and `inputs` are flake-parts top-level module arguments. Inner aspect
modules close over them lexically; they are not passed through NixOS specialArgs.

## Optional aspects must self-gate

Every aspect is imported into every host, so an optional aspect must be inert
until switched on. Gate its `config` with `mkIf`:

- desktop-only aspects gate on `config.isDesktop` (or `osConfig.isDesktop` in
  Home Manager aspects);
- service aspects gate on their service's `enable` option
  (e.g. `mkIf config.services.litellm.enable`), which the host turns on.

Never make an aspect apply unconditionally unless it is genuinely universal.

## Host classes

`isDesktop` (top-level option, default `false`) is the only host-class switch.
`false` means server. Do not reintroduce per-host module include/exclude lists.

## Nix style

- Always `let inherit (lib.<path>) foo;` with full paths, e.g.
  `lib.lists.singleton`, `lib.modules.mkIf`, `lib.meta.getExe`.
- Prefer `lib.lists.singleton x` over `[ x ]`.
- Do not use `builtins.` inside modules; use the `lib.*` equivalents.
- Never use `rec`.
- Prefer `getExe`/`getExe'` over bare command names in scripts and exec lines.
- Prefer setting individual options with `mkIf` over wrapping whole attrsets:
  `foo.bar = mkIf c v;` not `foo = mkIf c { bar = v; };`.
- Put a blank line between unrelated options.
- Section comments are uppercase, no trailing period: `# AI STACK`.
- The OS is always referred to as "darwin" in names, never "macOS" — but note
  this repo is Linux-only and contains no darwin modules.

## Packages

A package lives in the file for its concern; it is never scattered into an
unrelated module.

- A tool that carries configuration gets its own concern file, package and
  settings co-located (`git.mod.nix`, `ghostty.mod.nix`). Name the file for the
  tool/concern.
- Tools coupled to another concern live in that concern's file — `nh` and
  `nix-output-monitor` are in `nix.mod.nix`, font packages in `fonts.mod.nix`.
- Config-less tools with no natural home are grouped in `modules/packages.mod.nix`
  as small functional bundles, each a named aspect with a bare package list
  (`packages-shell-utils`, `packages-desktop`, ...). Desktop-only bundles gate on
  `osConfig.isDesktop`. There is no host-class (`server`/`desktop`) partition of
  packages; differentiation comes from the per-aspect gate.

Home aspects are expressed with home-manager (`home.packages`,
`programs.<tool>`).

## Secrets

`secrets.nix` is the agenix rule set (read by the CLI, not the flake). Add a
line there for each new secret before creating it with `agenix -e <path>.age`.
Reference secrets in modules as `config.secrets.<name>.path`.

## Pipe operators

This repository avoids Nix pipe operators (`|>`, `<|`) so the
flake evaluates without the `pipe-operators` experimental feature enabled. If
you adopt them, add `pipe-operators` to `nix.settings.experimental-features` and
to the flake's `nixConfig`.
