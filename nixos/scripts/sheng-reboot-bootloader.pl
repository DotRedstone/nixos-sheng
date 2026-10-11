use strict;
use warnings;

# ARM64 的 __NR_reboot 与 Linux RESTART2 魔数。RESTART2 将字符串交给
# Qualcomm nvmem reboot-mode 驱动，后者把 bootloader 映射为 ABL fastboot 原因。
my $arm64_reboot = 142;
my $magic_1 = 0xfee1dead;
my $magic_2 = 0x28121969;
my $restart_2 = 0xa1b2c3d4;

if ($> != 0) {
  die "Run this command with sudo.\n";
}

my $reason = "bootloader\0";
my $result = syscall($arm64_reboot, $magic_1, $magic_2, $restart_2, $reason);
die "RESTART2(bootloader) returned $result: $!\n";
