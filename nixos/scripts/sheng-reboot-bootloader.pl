use strict;
use warnings;
use Fcntl qw(O_RDONLY);
use File::Path qw(make_path);
use File::Temp qw(tempfile);
use IO::Handle;

# ARM64 的 __NR_reboot 与 Linux RESTART2 魔数。RESTART2 将字符串交给
# Qualcomm nvmem reboot-mode 驱动，后者把 bootloader 映射为 ABL fastboot 原因。
sub write_normal_reboot_marker {
  my ($marker) = @_;
  my ($directory) = $marker =~ m{\A(.+)/[^/]+\z};
  die "Invalid normal reboot marker path.\n" unless defined $directory;

  make_path($directory);
  my ($handle, $temporary) = tempfile('.force-normal-once.XXXXXX', DIR => $directory, UNLINK => 0);
  eval {
    print {$handle} "normal-reboot\n" or die "Could not write reboot marker: $!\n";
    $handle->flush or die "Could not flush reboot marker: $!\n";
    $handle->sync or die "Could not sync reboot marker: $!\n";
    close $handle or die "Could not close reboot marker: $!\n";
    rename $temporary, $marker or die "Could not install reboot marker: $!\n";
    sysopen(my $directory_handle, $directory, O_RDONLY)
      or die "Could not open reboot marker directory: $!\n";
    $directory_handle->sync or die "Could not sync reboot marker directory: $!\n";
    close $directory_handle or die "Could not close reboot marker directory: $!\n";
    1;
  } or do {
    my $error = $@;
    unlink $temporary if -e $temporary;
    die $error;
  };
}

unless (caller) {
  if ($> != 0) {
    die "Run this command with sudo.\n";
  }

  # RESTART2 绕过 systemd 的 reboot.target，需先写入一次性正常启动标记。
  write_normal_reboot_marker('/var/lib/sheng-offline-charging/force-normal-once');
  my $reason = "bootloader\0";
  my $result = syscall(142, 0xfee1dead, 0x28121969, 0xa1b2c3d4, $reason);
  unlink '/var/lib/sheng-offline-charging/force-normal-once';
  die "RESTART2(bootloader) returned $result: $!\n";
}

1;
