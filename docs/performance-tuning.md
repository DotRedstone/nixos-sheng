# Sheng Performance Policy

[简体中文](performance-tuning_zh.md)

The default policy aims to keep the desktop responsive under memory pressure
without pinning CPU, GPU, or UFS clocks. The existing `schedutil` and devfreq
governors already reach their lowest idle frequencies on tested hardware, so
clock-floor changes require separate performance-per-watt evidence.

## Defaults

`services.sheng-performance.enable` is enabled by default and applies:

- one zstd zram swap device with an uncompressed limit of 50% of physical RAM;
- `vm.swappiness=100`, so anonymous memory can use zram before reclaim becomes a
  long global stall;
- `vm.page-cluster=0`, because compressed RAM has no seek penalty and clustered
  swap-in can decompress pages that are never used;
- systemd-oomd monitoring for user slices, so sustained desktop memory pressure
  can be recovered before a kernel-wide OOM deadlock.

The zram size is a logical limit. It does not reserve half of physical RAM.
Actual use and compression ratio are visible in `zramctl` and `mm_stat`.

## Report

Run the repository's read-only report script:

```sh
sudo ./scripts/collect-hardware-baseline.sh 10 > sheng-performance.txt
```

It records boot timing, CPU and device-frequency policy, idle residency,
thermals, PSI, MGLRU/THP state, zram statistics, OOMD state, storage counters,
power supplies, hardware services, coredumps, and kernel warnings. It does not
collect SSIDs, IP addresses, or MAC addresses. Review a report before publishing
it because kernel and service logs can still contain device-specific details.

For a useful A/B comparison, collect three normal boots and the same workload on
both generations. Compare boot time, `memory full` PSI, zram compression ratio,
OOMD actions, application survival, temperature, and idle residency. A single
benchmark run is not enough to justify governor or clock changes.

## Override Or Roll Back

Downstream configurations can change the zram limit or disable the policy:

```nix
{
  services.sheng-performance = {
    zramMemoryPercent = 35;
    protectUserSessions = false;
    # enable = false;
  };
}
```

Disabling the module restores upstream NixOS defaults; it does not alter the
kernel, boot image, or Android partitions.

## Device Validation: 2026-08-31

The pre-change running system used `vm.swappiness=60`, `vm.page-cluster=3`, and
had no cgroups under `Memory Pressure Monitored CGroups` in `oomctl dump`. After
a device-side stage-2 rebuild and a normal reboot, sheng reported:

- `vm.swappiness=100` and `vm.page-cluster=0`;
- `/user.slice` and its application descendants monitored at 80% pressure for
  30 seconds;
- no failed units or coredumps;
- ADSP, pd-mapper, sensor PD, iio-sensor-proxy, NetworkManager, and the display
  manager active with zero restarts;
- zero idle memory PSI and no recurrence of the build-time GPU warning after
  reboot.

The rebuild is not a before/after performance benchmark. A first-time Rnote
source build dominated it, taking 28 minutes 54 seconds and reaching 5.7 GiB of
RAM plus 7.2 GiB of swap. One Adreno GMU performance-vote timeout occurred under
that pre-activation load and did not recur after reboot.

The validation boot took 36.082 seconds, but stage-1 logs show that 14.8 seconds
were a scheduled full ext4 check after 12 mounts. Userspace reached
`graphical.target` in 11.513 seconds, close to the 11.216-second prior sample.
Keep the ext4 check in comparisons: it protects the writable root filesystem and
is unrelated to this memory policy.
