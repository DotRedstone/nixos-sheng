# Hall Sensor and GNOME Auto Rotation

[English](hall-sensor-rotation.md) | [简体中文](hall-sensor-rotation_zh.md)

This document records the debugging history and final design for the hall
sensor, magnetic cover handling, and GNOME auto-rotation on Xiaomi Pad 6S Pro
12.4 (`sheng`).

## Background

`sheng` has a physical hall sensor exposed through the `gpio-keys` subsystem.
It reports `SW_LID` input events: `0` for cover open and `1` for cover closed.

GNOME and Mutter have two default behaviors that conflict with the current
device state:

1. **Auto-rotation is blocked**. Mutter treats the presence of `SW_LID` as a
   laptop hint during early startup and may permanently disable auto-rotation
   until it sees an explicit `SW_TABLET_MODE` event.
2. **logind suspends on lid close**. `systemd-logind` reacts to `SW_LID=1` by
   suspending. On the current sheng kernel, suspend can make the ADSP/CDSP
   subsystems time out and crash the kernel.

## Attempts

### Attempt A: hide the switch with udev and ignore it in logind

The first attempt hid `ID_INPUT_SWITCH` for `gpio-keys` with udev rules and set
`HandleLidSwitch=ignore` in logind.

This avoided suspend crashes, but GNOME still observed `SW_LID` through lower
libinput state and auto-rotation stayed broken. It also removed cover-close
screen blanking completely.

### Attempt B: virtual uinput device with event forwarding

The second attempt created a virtual device through a Python script
(`fake-tablet-mode`) and exposed both `SW_TABLET_MODE` and `SW_LID`. The script
intercepted physical hall-sensor events and forwarded them to the virtual
device, while GNOME's lid-close blanking handled display power.

This was unstable. An early inversion bug and Mutter's requirement for a clear
`SW_TABLET_MODE` `0 -> 1` transition made auto-rotation unreliable, especially
when booting with the cover already attached.

### Attempt C: decouple GNOME from real cover control

The final design separates GNOME's tablet-mode state from actual display
blanking.

## Final Design

### 1. Hide `SW_LID` from GNOME

To make GNOME always treat the device as a rotatable tablet:

- udev marks the physical `gpio-keys` device as ignored by libinput.
- `fake-tablet-mode` creates a virtual input device that reports only
  `SW_TABLET_MODE`, not `SW_LID`.

### 2. Force a `0 -> 1` tablet-mode transition after the real session starts

Mutter needs an explicit transition into tablet mode:

- The virtual device reports `SW_TABLET_MODE=0` when it starts.
- The script waits for `iio-sensor-proxy` to register on D-Bus.
- It waits for the real graphical user session and explicitly excludes the GDM
  greeter, then leaves a short delay for Mutter/libinput initialization.
- It then reports `SW_TABLET_MODE=1`.

This unlocks Mutter auto-rotation and floating on-screen keyboard behavior.

### 3. Control cover blanking through D-Bus

Since GNOME no longer sees `SW_LID`, cover-close display blanking is handled by
the custom script:

- `fake-tablet-mode` listens to raw `SW_LID` events from the physical
  `gpio-keys` device.
- On cover close/open, it finds the active GNOME user session through
  `loginctl`.
- It uses `busctl` to call the user's `org.gnome.Mutter.DisplayConfig` D-Bus
  interface and update `PowerSaveMode` directly (`0` for on, `3` for blank).
- On cover open, it also injects `KEY_WAKEUP` to force Mutter to repaint and
  avoid a lit-but-not-redrawn display.

### 4. Disable logind interference

`configuration.nix` sets:

```nix
services.logind.settings.Login.HandleLidSwitch = "ignore";
```

This removes `systemd-logind` from cover-event handling and avoids suspend
crashes.

## Result

The current design provides:

1. Four-way automatic rotation.
2. Cover-close blanking and cover-open wake.
3. No suspend-triggered kernel crash from lid events.
