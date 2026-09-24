set -eu

# A generator runs again at daemon-reload. Resolve once and retain both normal
# and charger decisions until /run disappears at reboot, before consuming any
# persistent override. Never reclassify a running desktop from stale USB PON.
output_dir="$2"
boot_mode=/run/sheng-boot-ui.mode
normal_reboot_marker=/var/lib/sheng-offline-charging/force-normal-once
mode=
if [ -r "$boot_mode" ]; then
  IFS= read -r mode < "$boot_mode" || mode=
fi
case "$mode" in
  normal|charger) ;;
  *)
    mode=normal
    if [ ! -e "$normal_reboot_marker" ] &&
       [ ! -e /run/sheng-boot-ui.normal ] &&
       [ ! -e /run/sheng-boot-ui.done ] &&
       @detect@ detect >/dev/null 2>&1; then
      mode=charger
    fi
    printf '%s\n' "$mode" > "$boot_mode.tmp"
    @mv@ -f "$boot_mode.tmp" "$boot_mode"
    ;;
esac

echo "Sheng boot decision: $mode" >&2
if [ "$mode" = charger ]; then
  @mkdir@ -p "$output_dir"
  @ln@ -sfn /etc/systemd/system/sheng-offline-charging.target "$output_dir/default.target"
fi
