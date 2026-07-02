{
  self,
  inputs,
  lib,
  ...
}:
let
  inherit (lib.lists) singleton;
in
{
  imports = singleton (
    lib.systems.nixosSystem "fw3" (
      { config, lib, pkgs, ... }:
      let
        inherit (lib.attrsets) attrValues;
        inherit (lib.lists) singleton;
        inherit (lib.modules) mkForce;
      in
      {
        imports =
          attrValues self.commonModules
          ++ attrValues self.nixosModules
          ++ [
            inputs.nixos-hardware.nixosModules.framework-13-7040-amd
            ./hardware-configuration.nix
          ];

        # HOST CLASS
        isDesktop = true;

        nixpkgs.hostPlatform = "x86_64-linux";

        # POWER (Framework 13 AMD tuning carried over from fwork; amd_pstate
        # and the amdgpu PSR workaround come from nixos-hardware and are not
        # repeated here)
        boot.kernelPackages = pkgs.linuxPackages_zen;

        boot.kernelParams = [
          "amdgpu.runpm=1"
          "video.use_native_backlight=1"
          "amdgpu.abmlevel=1"
        ];

        boot.kernel.sysctl = {
          "kernel.nmi_watchdog" = 0;
          "kernel.timer_migration" = 1;
        };

        powerManagement.enable = true;
        powerManagement.powertop.enable = true;

        services.logind.settings.Login.HandlePowerKey = "suspend";

        systemd.timers."fwupd-refresh".enable = false;

        # FRAMEWORK QUIRKS
        hardware.framework.enableKmod = mkForce false;
        hardware.sensor.iio.enable = false;
        hardware.fw-fanctrl.enable = true;

        # PERIPHERALS
        hardware.keyboard.zsa.enable = true;

        # SERVICES
        services.tailscale.enable = true;
        services.syncthing.enable = true;
        services.printing.enable = true;

        # DESKTOP EXTRAS
        programs.steam = {
          enable = true;
          remotePlay.openFirewall = true;
          dedicatedServer.openFirewall = true;
          localNetworkGameTransfers.openFirewall = true;
        };

        # USER
        users.users.${config.primaryUser}.shell = pkgs.nushell;

        system.stateVersion = "26.05";
      }
    )
  );
}
