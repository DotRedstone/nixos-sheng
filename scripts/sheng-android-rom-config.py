#!/usr/bin/env python3
"""从正在运行的 Android A 槽采集直启参数，并安装到 Sheng EFI 分区。"""

import argparse
import hashlib
import os
from pathlib import Path
import re
import subprocess
import sys


PROFILE_KEYS = (
    "android_profile_version",
    "android_profile_board",
    "android_profile_slot",
    "android_boot_devices",
    "android_bootdevice",
    "android_fstab_suffix",
    "android_dynamic_partitions",
    "android_verifiedbootstate",
)
VALUE_PATTERN = re.compile(r"[A-Za-z0-9._,/+-]+\Z")
GETPROP_PATTERN = re.compile(r"^\[([^]]+)\]: \[(.*)\]$")
REMOTE_STAGE = "/data/local/tmp/sheng-android-profile.tmp"
REMOTE_PROFILE = "/boot/SHENG/ANDROID.ENV"
DTBO_MAGIC = bytes.fromhex("d7b7ab1e")


def adb_command(serial, *args, input_data=None):
    command = ["adb"]
    if serial:
        command.extend(["-s", serial])
    command.extend(args)
    result = subprocess.run(command, input=input_data, capture_output=True, check=False)
    if result.returncode:
        raise RuntimeError(f"ADB 命令失败（退出码 {result.returncode}）；请检查设备连接、授权和当前系统")
    return result.stdout


def adb_shell_script(serial, script):
    return adb_command(serial, "shell", "-T", "sh", input_data=(script + "\n").encode())


def require_nixos_root(serial):
    uid = adb_command(serial, "shell", "id", "-u").decode().strip()
    if uid != "0":
        raise RuntimeError("操作需要 NixOS 的 root ADB")
    release = adb_command(serial, "exec-out", "cat", "/etc/os-release").decode("utf-8", "replace")
    if not re.search(r"^ID=nixos$", release, re.MULTILINE):
        raise RuntimeError("请先返回 NixOS")


def read_partition(serial, partition):
    path = f"/dev/disk/by-partlabel/{partition}"
    size = int(adb_command(serial, "shell", "blockdev", "--getsize64", path).decode().strip())
    if size <= 0 or size > 64 * 1024 * 1024:
        raise RuntimeError(f"{partition} 大小超出预期")
    data = adb_command(serial, "exec-out", "dd", f"if={path}", "bs=1M")
    if len(data) != size:
        raise RuntimeError(f"{partition} 读取长度不一致")
    return data


def parse_getprop(data):
    props = {}
    for line in data.decode("utf-8", "replace").splitlines():
        match = GETPROP_PATTERN.fullmatch(line.strip())
        if match:
            props[match.group(1)] = match.group(2)
    return props


def parse_bootconfig(data):
    values = {}
    for line in data.decode("utf-8", "replace").splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        value = value.strip().strip('"')
        values[key.strip()] = value
    return values


def parse_cmdline(data):
    values = {}
    for word in data.decode("utf-8", "replace").split():
        if "=" in word:
            key, value = word.split("=", 1)
            values[key] = value
    return values


def value_from_android(props, bootconfig, cmdline, suffix):
    return (props.get(f"ro.boot.{suffix}") or
            bootconfig.get(f"androidboot.{suffix}") or
            cmdline.get(f"androidboot.{suffix}") or "")


def validate_profile(profile):
    if set(profile) != set(PROFILE_KEYS):
        raise ValueError("配置字段不完整或含未知字段")
    if profile["android_profile_version"] != "1":
        raise ValueError("配置版本不受支持")
    if profile["android_profile_board"] != "sheng":
        raise ValueError("仅支持 Sheng")
    if profile["android_profile_slot"] != "_a":
        raise ValueError("只支持从 A 槽读取 Android")
    if profile["android_verifiedbootstate"] != "orange":
        raise ValueError("当前实验入口只支持解锁状态 orange；不能伪造 AVB 状态")
    if profile["android_dynamic_partitions"] != "true":
        raise ValueError("当前实验入口只支持动态分区 Android")
    for key, value in profile.items():
        if not value or not VALUE_PATTERN.fullmatch(value):
            raise ValueError(f"{key} 为空或包含不安全字符")
    if len(profile["android_boot_devices"]) > 128:
        raise ValueError("boot_devices 超长")
    if len(profile["android_bootdevice"]) > 128:
        raise ValueError("bootdevice 超长")
    if len(profile["android_fstab_suffix"]) > 32:
        raise ValueError("fstab_suffix 超长")
    return profile


def profile_from_android(props, bootconfig, cmdline):
    if "sheng" not in (props.get("ro.product.device"), props.get("ro.product.vendor.device")):
        raise ValueError("Android 报告的设备不是 sheng")
    boot_devices = value_from_android(props, bootconfig, cmdline, "boot_devices")
    bootdevice = value_from_android(props, bootconfig, cmdline, "bootdevice")
    if not bootdevice and boot_devices.startswith("soc/") and "," not in boot_devices:
        bootdevice = boot_devices.removeprefix("soc/")
    profile = {
        "android_profile_version": "1",
        "android_profile_board": "sheng",
        "android_profile_slot": value_from_android(props, bootconfig, cmdline, "slot_suffix"),
        "android_boot_devices": boot_devices,
        "android_bootdevice": bootdevice,
        "android_fstab_suffix": value_from_android(props, bootconfig, cmdline, "fstab_suffix"),
        "android_dynamic_partitions": value_from_android(props, bootconfig, cmdline, "dynamic_partitions"),
        "android_verifiedbootstate": value_from_android(props, bootconfig, cmdline, "verifiedbootstate"),
    }
    return validate_profile(profile)


def serialize_profile(profile):
    validate_profile(profile)
    return "".join(f"{key}={profile[key]}\n" for key in PROFILE_KEYS).encode("ascii")


def read_profile(path):
    data = Path(path).read_bytes()
    if len(data) > 2048 or b"\r" in data or not data.endswith(b"\n"):
        raise ValueError("配置格式错误或文件过大")
    profile = {}
    for line in data.decode("ascii").splitlines():
        key, sep, value = line.partition("=")
        if not sep or key in profile:
            raise ValueError("配置包含重复或无效行")
        profile[key] = value
    if serialize_profile(profile) != data:
        raise ValueError("配置格式不规范")
    return profile


def check_dtbo_header(header, partition):
    if header != DTBO_MAGIC:
        raise ValueError(f"{partition} 缺少有效 Android DTBO 头；请先备份并按安装指南准备该分区")


def dtbo_copy_needed(dtbo_a, dtbo_b):
    if len(dtbo_a) != len(dtbo_b):
        raise ValueError("A/B DTBO 分区大小不同，拒绝复制")
    check_dtbo_header(dtbo_a[:4], "dtbo_a")
    if dtbo_a == dtbo_b:
        return False
    if any(dtbo_b):
        raise ValueError("dtbo_b 并非空分区且与 A 不同，需人工核对")
    return True


def capture(args):
    props = parse_getprop(adb_command(args.serial, "shell", "getprop"))
    try:
        bootconfig = parse_bootconfig(adb_command(args.serial, "exec-out", "cat", "/proc/bootconfig"))
    except RuntimeError:
        bootconfig = {}
    cmdline = parse_cmdline(adb_command(args.serial, "exec-out", "cat", "/proc/cmdline"))
    profile = profile_from_android(props, bootconfig, cmdline)
    output = Path(args.output)
    if output.exists():
        raise FileExistsError(f"配置已存在：{output}")
    output.write_bytes(serialize_profile(profile))
    os.chmod(output, 0o600)
    print(f"已从 Android A 槽生成 {output}；ROM 更新后须重新采集。")


def install(args):
    read_profile(args.profile)
    require_nixos_root(args.serial)
    dtbo_a = read_partition(args.serial, "dtbo_a")
    dtbo_b = read_partition(args.serial, "dtbo_b")
    check_dtbo_header(dtbo_a[:4], "dtbo_a")
    check_dtbo_header(dtbo_b[:4], "dtbo_b")
    if dtbo_a != dtbo_b:
        raise RuntimeError("A/B DTBO 内容不同，需人工核对后再安装 ROM 配置")
    remote_check = (
        "set -eu; "
        "test -b /dev/disk/by-partlabel/linux-boot; "
        "source=$(findmnt -n -o SOURCE --mountpoint /boot); "
        "test \"$(readlink -f \"$source\")\" = "
        "\"$(readlink -f /dev/disk/by-partlabel/linux-boot)\""
    )
    adb_shell_script(args.serial, remote_check)
    adb_command(args.serial, "push", str(Path(args.profile).resolve()), REMOTE_STAGE)
    remote_install = (
        "set -eu; mkdir -p /boot/SHENG; "
        "if test -e /boot/SHENG/ANDROID.ENV; then "
        "cp /boot/SHENG/ANDROID.ENV /boot/SHENG/ANDROID.ENV.previous; fi; "
        "cp /data/local/tmp/sheng-android-profile.tmp /boot/SHENG/ANDROID.ENV.new; "
        "sync; mv /boot/SHENG/ANDROID.ENV.new /boot/SHENG/ANDROID.ENV; "
        "sync; rm -f /data/local/tmp/sheng-android-profile.tmp; "
        "sha256sum /boot/SHENG/ANDROID.ENV"
    )
    output = adb_shell_script(args.serial, remote_install).decode()
    fields = output.split()
    if len(fields) != 2 or fields[1] != REMOTE_PROFILE:
        raise RuntimeError("无法解析 ESP 配置校验结果")
    digest = fields[0]
    expected = hashlib.sha256(Path(args.profile).read_bytes()).hexdigest()
    if digest != expected:
        raise RuntimeError("ESP 配置哈希不一致")
    print("Android ROM 配置已安装到 linux-boot；原配置保留为 ANDROID.ENV.previous。")


def prepare_dtbo_b(args):
    require_nixos_root(args.serial)
    dtbo_a = read_partition(args.serial, "dtbo_a")
    dtbo_b = read_partition(args.serial, "dtbo_b")
    if not dtbo_copy_needed(dtbo_a, dtbo_b):
        print("dtbo_b 已与 dtbo_a 一致，无需写入。")
        return
    backup_dir = Path(args.backup_dir)
    backup_dir.mkdir(mode=0o700, parents=False, exist_ok=False)
    for name, data in (("dtbo_a.img", dtbo_a), ("dtbo_b.before.img", dtbo_b)):
        with (backup_dir / name).open("xb") as output:
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
    with (backup_dir / "sha256sums.txt").open("x", encoding="ascii") as checksums:
        checksums.write(f"{hashlib.sha256(dtbo_a).hexdigest()}  dtbo_a.img\n")
        checksums.write(f"{hashlib.sha256(dtbo_b).hexdigest()}  dtbo_b.before.img\n")
        checksums.flush()
        os.fsync(checksums.fileno())
    adb_shell_script(
        args.serial,
        "set -eu; dd if=/dev/disk/by-partlabel/dtbo_a "
        "of=/dev/disk/by-partlabel/dtbo_b bs=4M conv=fsync; sync"
    )
    actual = read_partition(args.serial, "dtbo_b")
    if actual != dtbo_a:
        raise RuntimeError(f"dtbo_b 写后校验失败；回退备份位于 {backup_dir}")
    print(f"dtbo_b 已与 dtbo_a 一致；A/B 原始镜像备份位于 {backup_dir}。")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="action", required=True)
    capture_parser = subparsers.add_parser("capture", help="从运行中的 Android A 槽采集配置")
    capture_parser.add_argument("--serial", help="ADB 序列号")
    capture_parser.add_argument("--output", required=True, help="本地输出文件；不得提交到 Git")
    capture_parser.set_defaults(func=capture)
    install_parser = subparsers.add_parser("install", help="在 NixOS 下安装配置到 linux-boot")
    install_parser.add_argument("--serial", help="ADB 序列号")
    install_parser.add_argument("--profile", required=True, help="capture 生成的配置文件")
    install_parser.set_defaults(func=install)
    dtbo_parser = subparsers.add_parser("prepare-dtbo-b", help="备份并准备空的 B 槽 DTBO")
    dtbo_parser.add_argument("--serial", help="ADB 序列号")
    dtbo_parser.add_argument("--backup-dir", required=True, help="不存在的本地备份目录")
    dtbo_parser.set_defaults(func=prepare_dtbo_b)
    args = parser.parse_args()
    try:
        args.func(args)
    except (OSError, RuntimeError, UnicodeError, ValueError) as error:
        parser.exit(1, f"错误：{error}\n")


if __name__ == "__main__":
    main()
