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

The service is intentionally retried after attach. On sheng, the first USB-C
uevent can arrive before the battery manager has updated `real_type`,
`adapter_svid`, and `pdo2`. In that window the charger may still look like
`SDP`, or `pdo2` may read as `00000000`. The wrapper waits for a Xiaomi SVID,
a PD/PPS `real_type`, and a non-empty PDO before running the MiPPS handshake,
then retries on later USB power-supply changes.

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

If fast charging is not active, check the service journal first. A log like
`real_type=SDP adapter_svid=10007 pdo2=00000000` means the Xiaomi charger was
detected but PD/PPS source PDOs were not ready yet; unplugging should no longer
be required in the steady state, because later `power_supply` changes retrigger
the service. If the values stay stuck at `SDP` and `pdo2=00000000`, the failure
is below userspace in the Type-C/PD negotiation state.

## Risk and rollback

High-power charging can increase battery and connector temperature. Stop the
test immediately if temperature rises unexpectedly or charging repeatedly
disconnects.

This experiment changes both kernel and rootfs. Roll back by flashing the last
known-good `boot_b` and `linux` images.
