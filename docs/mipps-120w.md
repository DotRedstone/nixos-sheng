# Xiaomi MiPPS fast charging

The `sheng` branch includes Xiaomi MiPPS charger authentication support for
sheng. The integration is verified, while sustained input power and thermal
behavior still require long-term testing.

This support has two required parts:

- A kernel patch that exposes Xiaomi battery-manager properties under
  `/sys/devices/platform/pmic-glink/*/xiaomi/`.
- The `xiaomi-mipps-auth` userspace service, triggered when a USB-C partner is
  attached.

The authentication service only attempts the Xiaomi private flow when the
charger reports Xiaomi SVID `0x2717`. Other chargers continue using standard
PD/PPS negotiation.

## Verified result

The integration was verified on sheng with a compatible Xiaomi 120 W charger
and cable. A successful authentication run reported:

```text
adapter_svid=0x2717
authentic_verified=1
slave_authentic_verified=1
pd_auth=1
authentic=1
slave_authentic=1
apdo_max=120
power_max=120
fastchg_mode=1
pd_verifed=1
```

This proves that the kernel interface and userspace authentication flow can
unlock the charger's 120 W MiPPS profile. It does not prove that the tablet
continuously draws 120 W; actual input power remains dependent on battery
state, temperature, and the charger control loop.

## Build and flash

Both the boot image and GNOME rootfs are required:

```sh
nix build ./nixos#mobileAndroidBootimg -o out/mobile-bootimg
nix build ./nixos#mobileRootfsImageGnome -o out/mobile-rootfs

fastboot flash boot_b out/mobile-bootimg
fastboot flash linux out/mobile-rootfs/rootfs.img
```

Do not flash `userdata`.

## Runtime verification

Use a compatible Xiaomi charger and cable, then run:

```sh
find /sys/devices/platform/pmic-glink -path '*/xiaomi/*' -maxdepth 8 -type f -print | sort

systemctl status xiaomi-mipps-auth --no-pager -l
journalctl -b -u xiaomi-mipps-auth --no-pager -o short-monotonic

for f in /sys/devices/platform/pmic-glink/*/xiaomi/{request_vdm_cmd,authentic,slave_authentic,adapter_svid,adapter_id,apdo_max,power_max,fastchg_mode,pd_verifed,bq2597x_bus_voltage,bq2597x_bus_current,bq2597x_slave_bus_current}; do
  [ -e "$f" ] || continue
  printf '%s: ' "$f"
  cat "$f"
done

for d in /sys/class/power_supply/*; do
  echo "--- $d ---"
  grep -H . "$d"/{type,online,status,usb_type,voltage_now,current_now,power_now,temp} 2>/dev/null || true
done
```

Do not treat `power_max=120` alone as proof of 120 W charging. Successful
validation requires:

- `pd_auth=1` in the service journal.
- `pd_verifed=1` in the Xiaomi battery-manager attributes.
- Increased measured voltage and current.
- Stable battery and charger temperatures.
- Confirmation with an external USB-C power meter.

## Risk and rollback

High-power charging can increase battery and connector temperature. Stop the
test immediately if temperature rises unexpectedly or charging repeatedly
disconnects.

This experiment changes both kernel and rootfs. Roll back by flashing the last
known-good `boot_b` and `linux` images.
