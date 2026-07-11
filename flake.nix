{
  description = "NixOS configuration (Dendritic, single-repo, modular)";

  inputs.nixpkgs = {
    url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  # Codex releases move faster than nixos-unstable. Consume only that package
  # from master; the system and every other package remain on nixos-unstable.
  inputs.nixpkgs-master = {
    url = "github:NixOS/nixpkgs/master";
  };

  inputs.nixos-hardware = {
    url = "github:NixOS/nixos-hardware/master";
  };

  inputs.flake-parts = {
    url = "github:hercules-ci/flake-parts";
    inputs.nixpkgs-lib.follows = "nixpkgs";
  };

  inputs.home-manager = {
    url = "github:nix-community/home-manager";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  inputs.disko = {
    url = "github:nix-community/disko";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  inputs.agenix = {
    url = "github:ryantm/agenix";
    inputs.nixpkgs.follows = "nixpkgs";
    inputs.home-manager.follows = "home-manager";
    inputs.darwin.follows = "";
  };

  # master, not stable: v1.4.6/stable predate the fixes for Hyprland 0.55's
  # Lua command socket (old-style `dispatch workspace N` strings are rejected,
  # breaking DMS workspace clicking; fixed on master ~2026-05).
  inputs.dank-material-shell = {
    url = "github:AvengeMedia/DankMaterialShell";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  inputs.nix4nvchad = {
    url = "github:nix-community/nix4nvchad";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  # microvm.nix: hypervisor-backed guests for the agent fleet (see
  # modules/server/microvm-host.mod.nix, gated on agentFleet.enable).
  inputs.microvm = {
    url = "github:microvm-nix/microvm.nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  # nix-minecraft: declarative Fabric/vanilla/etc. Minecraft servers as a
  # NixOS service, plus prebuilt server packages pinned per game version
  # (see modules/server/minecraft.mod.nix, gated on services.minecraft-servers
  # via minecraft.enable). Does NOT follow our nixpkgs: the flake's server
  # packages (fabricServers.*) and their loader/launcher wrapper are built and
  # cached against its own pinned nixpkgs, and only its `minecraft-servers`
  # NixOS module + overlay are consumed here — so leaving its nixpkgs pinned
  # avoids a mass rebuild and keeps the binary cache hits.
  inputs.nix-minecraft = {
    url = "github:Infinidoge/nix-minecraft";
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake
      {
        inherit inputs;
        specialArgs.lib = import ./lib inputs.nixpkgs.lib;
      }
      (
        { lib, ... }:
        {
          systems = [
            "x86_64-linux"
            "aarch64-linux"
          ];

          # The Dendritic Pattern: every `*.mod.nix` file in the tree is a
          # flake-parts module and is imported automatically. There is no
          # central list of modules to maintain.
          imports = lib.lists.filter (lib.strings.hasSuffix ".mod.nix") (
            lib.filesystem.listFilesRecursive ./.
          );
        }
      );
}
