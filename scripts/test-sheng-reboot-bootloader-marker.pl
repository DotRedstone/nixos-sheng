use strict;
use warnings;
use File::Spec;
use File::Temp qw(tempdir);

require File::Spec->rel2abs($ARGV[0]);

my $directory = tempdir(CLEANUP => 1);
my $marker = "$directory/nested/force-normal-once";
write_normal_reboot_marker($marker);
open my $handle, '<', $marker or die "Reboot marker was not created: $!\n";
my $value = <$handle>;
close $handle;
die "Unexpected reboot marker content\n" unless $value eq "normal-reboot\n";
die "Temporary reboot marker was left behind\n"
  if glob("$directory/nested/.force-normal-once.*");

write_normal_reboot_marker($marker);
die "Repeated reboot marker write changed its content\n"
  unless -s $marker == length("normal-reboot\n");

print "bootloader reboot marker tests passed\n";
