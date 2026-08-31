# ---
# Module: Sheng Performance Policy
# Description: Reversible memory-pressure defaults for the sheng platform
# Scope: Host
# ---

{ config, lib, ... }:

let
  cfg = config.services.sheng-performance;
in
{
  options.services.sheng-performance = {
    enable = lib.mkEnableOption "sheng platform performance defaults" // {
      default = true;
    };

    zramMemoryPercent = lib.mkOption {
      type = lib.types.ints.between 1 100;
      default = 50;
      description = ''
        Maximum uncompressed size of the zram swap device as a percentage of
        physical memory. This is an address-space limit and does not reserve
        that amount of RAM.
      '';
    };

    protectUserSessions = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Let systemd-oomd act on sustained memory pressure in user slices before
        the kernel reaches an unrecoverable global OOM stall.
      '';
    };

    protectInteractiveWorkloads = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Limit device-side Nix build parallelism and give the Nix daemon lower
        CPU and I/O weights than interactive services. The daemon can still use
        idle resources; the weights only matter during contention.
      '';
    };

    buildMaxJobs = lib.mkOption {
      type = lib.types.ints.between 1 1024;
      default = 2;
      description = ''
        Maximum number of Nix derivations built concurrently when interactive
        workload protection is enabled.
      '';
    };

    buildCores = lib.mkOption {
      type = lib.types.ints.between 1 1024;
      default = 4;
      description = ''
        Maximum parallelism exposed to an individual Nix build when interactive
        workload protection is enabled.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    zramSwap = {
      enable = lib.mkDefault true;
      algorithm = lib.mkDefault "zstd";
      memoryPercent = lib.mkDefault cfg.zramMemoryPercent;
      priority = lib.mkDefault 100;
    };

    # zram has no seek penalty. Read one compressed page at a time and allow
    # anonymous pages to use it before reclaim turns into a long global stall.
    boot.kernel.sysctl = {
      "vm.swappiness" = lib.mkDefault 100;
      "vm.page-cluster" = lib.mkDefault 0;
    };

    systemd.oomd = {
      enable = lib.mkDefault true;
      enableUserSlices = lib.mkDefault cfg.protectUserSessions;
    };

    nix.settings = lib.mkIf cfg.protectInteractiveWorkloads {
      max-jobs = lib.mkDefault cfg.buildMaxJobs;
      cores = lib.mkDefault cfg.buildCores;
    };

    # A low weight does not cap an idle build. It only lets desktop and hardware
    # services win when they contend with a device-side rebuild.
    systemd.services.nix-daemon.serviceConfig =
      lib.mkIf cfg.protectInteractiveWorkloads
        {
          CPUWeight = lib.mkDefault 50;
          IOWeight = lib.mkDefault 50;
        };
  };
}
