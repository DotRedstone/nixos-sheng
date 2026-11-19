#!/usr/bin/env python3
"""在 Sheng 的 RAM 恢复环境中校验并安装配套的 NixOS rootfs 和 EFI 载荷。"""

import argparse
import hashlib
import json
import os
import re
import runpy
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path


LINUX_TYPE = "0fc63daf-8483-4772-8e79-3d69d8477de4"
ESP_TYPE = "c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
MARKER = "/run/sheng-storage-installer-v1"
LOCK = "/run/sheng-storage-installer.lock"
IDENTITY = ("path", "partuuid", "parttype", "size", "maj:min")
COLUMNS = "PATH,PKNAME,TYPE,PARTLABEL,PARTUUID,PARTTYPE,SIZE,FSTYPE,MOUNTPOINTS,MAJ:MIN,PTTYPE,LOG-SEC"
BOOTLOADER = "EFI/BOOT/BOOTAA64.EFI"
PAYLOAD = r"EFI/NixOS/sheng-[0-9A-Za-z._-]+/(linux|initrd|sm8550-xiaomi-sheng\.dtb|kernel\.store-path)"


class MissingLayout(ValueError):
    def __init__(self, disk, labels):
        self.disk = disk
        super().__init__(f"缺少 {'、'.join(labels)} 分区，需先准备 Linux 分区布局")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def capture(*args):
    return run(*args, stdout=subprocess.PIPE, text=True).stdout.strip()


def file_digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def checked_file(base, name):
    require(re.fullmatch(r"[A-Za-z0-9._+/-]+", name) and
            all(piece not in ("", ".", "..") for piece in name.split("/")),
            f"不支持的安装包路径 {name!r}")
    current = base
    for piece in name.split("/"):
        current = current / piece
        require(not current.is_symlink(), f"安装包文件不可使用符号链接 {name}")
    require(current.is_file() and current.stat().st_size > 0, f"文件不存在或为空 {name}")
    return current


def read_manifest(base, name):
    records = {}
    for line in checked_file(base, name).read_text(encoding="utf-8").splitlines():
        match = re.fullmatch(r"([0-9a-f]{64}) [ *](.+)", line)
        require(match is not None, f"无法读取 {name} 的 SHA-256 记录")
        digest, filename = match.groups()
        require(filename not in records, f"清单包含重复路径 {filename}")
        checked_file(base, filename)
        records[filename] = digest
    require(records, f"清单为空 {name}")
    return records


def validate_bundle(base):
    require(base.is_dir() and not base.is_symlink(), "请提供实际安装包目录")
    outer = read_manifest(base, "SHA256SUMS")
    require(outer.keys() == {"rootfs.img", "esp/manifest.sha256"},
            "SHA256SUMS 必须包含 rootfs.img 与 esp/manifest.sha256")
    for name, expected in outer.items():
        require(file_digest(checked_file(base, name)) == expected, f"SHA-256 不匹配 {name}")

    rootfs = checked_file(base, "rootfs.img")
    with rootfs.open("rb") as stream:
        stream.seek(1080)
        require(stream.read(2) == b"\x53\xef", "rootfs.img 必须是原始 ext4 分区镜像")
    efi = read_manifest(base / "esp", "manifest.sha256")
    entries = [name for name in efi if re.fullmatch(r"loader/entries/nixos-sheng-[0-9A-Za-z._-]+\.conf", name)]
    require(len(entries) == 1, "安装包必须提供一个 NixOS Sheng EFI 条目")
    entry = entries[0]
    for name, expected in efi.items():
        require(name in (entry, BOOTLOADER, "loader/loader.conf", "loader/entries.srel") or
                re.fullmatch(PAYLOAD, name), f"安装包超出 NixOS EFI 载荷范围 {name}")
        require(file_digest(checked_file(base / "esp", name)) == expected, f"SHA-256 不匹配 {name}")
    require({BOOTLOADER, "loader/loader.conf"}.issubset(efi), "缺少 EFI 引导器或默认项配置")
    config = checked_file(base / "esp", "loader/loader.conf").read_text(encoding="utf-8")
    defaults = [line.split() for line in config.splitlines() if line.split()[:1] == ["default"]]
    require(defaults == [["default", Path(entry).name]], "EFI 默认项与安装包条目不匹配")

    checker = Path(__file__).with_name("sheng-check-linux-efi-entry.py")
    checks = runpy.run_path(str(checker))
    fields = checks["parse_entry"](checked_file(base / "esp", entry))
    paths = [path for key in ("linux", "initrd", "devicetree") for path in fields[key]]
    require(all(path.startswith("/") and path[1:] in efi and len(path.split()) == 1 for path in paths),
            "EFI 条目引用了清单之外的载荷")
    checks["check_aa64_pe"](checked_file(base / "esp", BOOTLOADER))
    checks["check_aa64_pe"](checked_file(base / "esp", fields["linux"][0][1:]))
    checks["check_dtb"](checked_file(base / "esp", fields["devicetree"][0][1:]))
    kernel_names = [name for name in efi if name.endswith("/kernel.store-path")]
    require(len(kernel_names) == 1 and "/" + kernel_names[0].removesuffix("kernel.store-path") + "linux" in paths,
            "缺少与 EFI 条目配对的 NixOS 内核闭包信息")
    kernel_path = checked_file(base / "esp", kernel_names[0]).read_text(encoding="utf-8").strip()
    require(re.fullmatch(r"/nix/store/[0-9a-z]{32}-linux-[0-9A-Za-z._+-]+", kernel_path),
            "EFI 内核闭包路径无效")
    require(re.search(r"^Inode:\s+\d+", capture("debugfs", "-R", f"stat {kernel_path}", rootfs), re.MULTILINE),
            "rootfs 缺少 EFI 载荷声明的内核闭包")
    return rootfs, outer["rootfs.img"], efi


class Device:
    def __init__(self, serial):
        self.adb = ("adb", "-s", serial)

    def boot_recovery(self, serial, image):
        require(image.is_file() and image.stat().st_size > 0, "缺少 RAM 恢复镜像")
        fastboot = ("fastboot", "-s", serial)
        for variable, expected in (("product", "sheng"), ("is-userspace", "no"), ("unlocked", "yes")):
            result = run(*fastboot, "getvar", variable, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            require(f"{variable}: {expected}" in result.stdout.splitlines(), f"ABL Fastboot 的 {variable} 校验失败")
        run(*fastboot, "boot", image)
        run(*self.adb, "wait-for-device", timeout=90)
        for _ in range(25):
            if self.command(f"if test -f {MARKER}; then cat {MARKER}; fi") == "sheng":
                return
            time.sleep(1)
        raise ValueError("设备未进入预期的安装器 RAM 恢复环境")

    def shell(self, *args):
        return self.command(shlex.join(args))

    def command(self, command):
        # 恢复镜像的 adbd 可能没有 shell v2，通过 exec-out 显式获取返回值。
        output = capture(*self.adb, "exec-out", command + "; printf '\\nSHENG_COMMAND_STATUS=%s\\n' \"$?\"")
        body, separator, status = output.rpartition("\nSHENG_COMMAND_STATUS=")
        if not separator and output.startswith("SHENG_COMMAND_STATUS="):
            status = output.split("=", 1)[1]
        require(status == "0", f"设备命令失败 {command}: {body}")
        return body.strip()

    def layout(self):
        board = self.command(r"tr '\000' '\n' </proc/device-tree/compatible")
        require("xiaomi,sheng" in board.splitlines(), "连接的设备不是 Xiaomi Sheng")
        devices = json.loads(self.shell("lsblk", "--list", "--json", "--bytes", "--output", COLUMNS))
        return select_targets(devices["blockdevices"])

    def guard(self, layout):
        require(self.shell("cat", MARKER) == "sheng" and self.shell("id", "-u") == "0",
                "写入需要带安装器标识的 Sheng RAM 恢复环境")
        current = self.layout()
        require(all(old[key] == new[key] for old, new in zip(layout[1:], current[1:]) for key in IDENTITY),
                "设备分区状态已变化，请重新预览")
        _, rootfs, esp = current
        swaps = self.shell("cat", "/proc/swaps").splitlines()[1:]
        for target in (rootfs, esp):
            require(not any(target["mountpoints"]), f"{target['partlabel']} 当前已挂载")
            holders = f"/sys/class/block/{Path(target['path']).name}/holders"
            require(not self.shell("ls", "-A", holders), f"{target['partlabel']} 正被块设备映射使用")
            require(all(not line.split() or self.shell("readlink", "-f", line.split()[0]) != target["path"]
                        for line in swaps), f"{target['partlabel']} 正被用作 swap")

    def back_up(self, target, destination):
        with destination.open("xb") as output:
            run(*self.adb, "exec-out", "cat", target["path"], stdout=output)
            output.flush()
            os.fsync(output.fileno())
        require(destination.stat().st_size == target["size"], "备份读取长度不完整")

    def write_verified(self, target, image, expected):
        label = target["partlabel"]
        print(f"正在写入并校验 {label}，此过程需要等待。", flush=True)
        with image.open("rb") as stream:
            marker = shlex.quote(f"{LOCK}/{label}.complete")
            command = shlex.join(["dd", f"of={target['path']}", "bs=4M", "iflag=fullblock", "conv=fsync"])
            run(*self.adb, "exec-in", f"{command} >{LOCK}/dd.log 2>&1 && touch {marker}", stdin=stream)
        for _ in range(60):
            if self.command(f"if test -f {marker}; then echo ready; fi") == "ready":
                break
            time.sleep(1)
        else:
            raise ValueError(f"{label} 未收到写入完成标记：{self.shell('cat', f'{LOCK}/dd.log')}")
        command = shlex.join(["head", "-c", str(image.stat().st_size), target["path"]]) + " | sha256sum"
        digest = self.command(command).split()
        require(digest and digest[0] == expected, f"{label} 读回 SHA-256 校验失败")


def select_targets(devices):
    def lookup(label):
        candidates = [item for item in devices if item["partlabel"] == label]
        require(len(candidates) == 1, f"缺少唯一的 {label} 分区，需先准备 Linux 分区布局")
        result = candidates[0]
        require(result["type"] == "part" and re.fullmatch(r"/dev/sd[a-z]+[1-9][0-9]*", result["path"])
                and re.fullmatch(r"[0-9a-fA-F-]{36}", result["partuuid"] or ""),
                f"{label} 不是可识别的 Sheng UFS GPT 分区")
        return result

    userdata, super_part = lookup("userdata"), lookup("super")
    disk = next((item for item in devices if item["path"] == f"/dev/{userdata['pkname']}"), None)
    require(disk and disk["type"] == "disk" and disk["pttype"] == "gpt" and disk["log-sec"] in (512, 4096) and
            re.fullmatch(r"/dev/sd[a-z]+", disk["path"]) and super_part["pkname"] == userdata["pkname"],
            "无法从 Android 分区确定目标 UFS GPT")
    labels = {item["partlabel"] for item in devices}
    missing = [name for name in ("linux", "linux-boot") if name not in labels]
    if missing:
        raise MissingLayout(disk["path"], missing)
    rootfs, esp = lookup("linux"), lookup("linux-boot")
    require(all(item["pkname"] == userdata["pkname"] for item in (rootfs, esp)),
            "Android 与 Linux 分区必须位于同一目标 UFS GPT")
    require(len({item["maj:min"] for item in (userdata, super_part, rootfs, esp)}) == 4,
            "分区设备号冲突")
    require(rootfs["parttype"] == LINUX_TYPE and rootfs["fstype"] in (None, "ext4"),
            "linux 分区类型必须是 Linux 文件系统，且为空或 ext4")
    require(esp["parttype"] == ESP_TYPE and esp["fstype"] in (None, "vfat"),
            "linux-boot 分区类型必须是 EFI，且为空或 FAT")
    return disk, rootfs, esp


def prepare_esp(previous, candidate, esp, bundle, hashes, sector_size):
    if esp["fstype"] == "vfat":
        shutil.copyfile(previous, candidate)
        run("fsck.fat", "-n", candidate, stdout=subprocess.DEVNULL)
    else:
        with candidate.open("xb") as stream:
            stream.truncate(esp["size"])
        run("mkfs.fat", "-F", "32", "-S", str(sector_size), "-n", "linux-boot", candidate)
    folders = set()
    for name in hashes:
        for folder in reversed(Path(name).parents):
            if folder == Path(".") or folder in folders:
                continue
            dest = f"::/{folder.as_posix()}"
            found = subprocess.run(("mdir", "-i", candidate, dest), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if found.returncode:
                run("mmd", "-i", candidate, dest)
            folders.add(folder)
        run("mcopy", "-o", "-i", candidate, checked_file(bundle / "esp", name), f"::/{name}")
    # 更新整个 ESP 的清单，保留原有社区条目与 Android 启动配置。
    with tempfile.TemporaryDirectory(dir=candidate.parent) as directory:
        root = Path(directory)
        run("mcopy", "-s", "-i", candidate, "::/EFI", "::/loader", root)
        manifest = {}
        for entry in sorted(root.rglob("*")):
            name = entry.relative_to(root).as_posix()
            if entry.is_file() and name != "loader/random-seed":
                manifest[name] = file_digest(checked_file(root, name))
        require(all(manifest.get(name) == digest for name, digest in hashes.items()), "预制 ESP 读回校验失败")
        entry = root / "manifest.sha256"
        entry.write_text("".join(f"{digest}  {name}\n" for name, digest in manifest.items()), encoding="utf-8")
        run("mcopy", "-o", "-i", candidate, entry, "::/manifest.sha256")
    run("fsck.fat", "-n", candidate, stdout=subprocess.DEVNULL)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["plan", "install"])
    parser.add_argument("bundle", type=Path, nargs="?")
    parser.add_argument("--adb-serial", required=True)
    parser.add_argument("--backup-dir", type=Path)
    parser.add_argument("--replace-linux", action="store_true", help="已备份现有 Linux 数据，允许替换 ext4")
    parser.add_argument("--recovery-image", type=Path, help="从已解锁的 ABL Fastboot 临时启动安装器")
    parser.add_argument("--fastboot-serial", help="临时启动时的 ABL Fastboot 设备序列号")
    args = parser.parse_args()

    device = Device(args.adb_serial)
    if args.action == "install":
        require(args.bundle and args.backup_dir, "安装需要安装包目录和一个新的 --backup-dir")
        require(sys.stdin.isatty(), "请在交互式终端确认目标")
    if args.recovery_image or args.fastboot_serial:
        require(args.action == "install" and args.recovery_image and args.fastboot_serial,
                "从 Fastboot 启动需要 install、--recovery-image 和 --fastboot-serial")
    if args.bundle:
        rootfs, checksum, files = validate_bundle(args.bundle)
    if args.recovery_image:
        device.boot_recovery(args.fastboot_serial, args.recovery_image)
    try:
        layout = device.layout()
    except MissingLayout as error:
        if args.action == "plan":
            print(device.shell("sfdisk", "--list-free", "--bytes", error.disk))
        raise
    disk, linux, esp = layout
    for target in (linux, esp):
        status = ("挂载中" if any(target["mountpoints"]) else target["fstype"] or "无可识别文件系统")
        print(f"{target['partlabel']:10} {target['path']:12} {target['size'] // (1024 ** 2):8} MiB  {status}")
    print("写入范围限定为上列两个 Linux 分区。")
    if args.bundle:
        require(rootfs.stat().st_size <= linux["size"], "rootfs.img 放不进 linux 分区")
    if args.action == "plan":
        return

    require(linux["fstype"] != "ext4" or args.replace_linux,
            "现有 Linux 数据会被替换；先备份，再显式指定 --replace-linux")
    device.guard(layout)
    keyword = f"INSTALL {linux['partuuid']}"
    require(input(f"将覆写 {linux['path']}。已备份现有 Linux 数据时输入 {keyword}\n> ").strip() == keyword,
            "安装已取消")
    device.shell("mkdir", LOCK)
    args.backup_dir.mkdir(mode=0o700)
    previous = args.backup_dir / "linux-boot.before.img"
    candidate = args.backup_dir / "linux-boot.candidate.img"
    device.guard(layout)
    device.back_up(esp, previous)
    prepare_esp(previous, candidate, esp, args.bundle, files, disk["log-sec"])
    device.guard(layout)
    device.write_verified(linux, rootfs, checksum)
    device.guard(layout)
    device.write_verified(esp, candidate, file_digest(candidate))
    # 失败时锁保留到下次 RAM 启动，避免上一次写入尚未退出便再次写盘。
    device.command(f"rm -f {LOCK}/dd.log {LOCK}/linux.complete {LOCK}/linux-boot.complete; rmdir {LOCK}")
    print(f"NixOS 与 EFI 载荷写入校验完成。旧 ESP 备份保存在 {previous}。")


if __name__ == "__main__":
    try:
        main()
    except (OSError, subprocess.SubprocessError, ValueError, EOFError) as error:
        print(f"Sheng 安装器停止：{error}", file=sys.stderr)
        sys.exit(1)
