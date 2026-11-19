#!/usr/bin/env python3
"""Sheng 安装器的离线布局与文件校验回归测试。"""

from pathlib import Path
import runpy
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch


INSTALLER = runpy.run_path(str(Path(__file__).with_name("sheng-installer.py")))
SELECT = INSTALLER["select_targets"]
DIGEST = INSTALLER["file_digest"]
VALIDATE = INSTALLER["validate_bundle"]
PREPARE = INSTALLER["prepare_esp"]
MIB = 1024 ** 2


def disks():
    result = [{"path": "/dev/sdz", "type": "disk", "partlabel": None, "pttype": "gpt", "log-sec": 4096}]
    for number, (label, guid, fs) in enumerate([
        ("super", "android-super", None),
        ("userdata", "android-data", "f2fs"),
        ("linux", INSTALLER["LINUX_TYPE"], "ext4"),
        ("linux-boot", INSTALLER["ESP_TYPE"], "vfat"),
    ], 1):
        result.append({
            "path": f"/dev/sdz{number}", "pkname": "sdz", "type": "part", "partlabel": label,
            "partuuid": f"00000000-0000-4000-8000-{number:012d}", "parttype": guid,
            "fstype": fs, "size": 96 * MIB, "mountpoints": [], "maj:min": f"8:{number}",
        })
    return result


def make_bundle(path):
    version = "7.3.0-test"
    payload = f"EFI/NixOS/sheng-{version}"
    closure = "/nix/store/00000000000000000000000000000000-linux-7.3.0"
    entry = f"nixos-sheng-{version}.conf"

    pe = bytearray(64)
    pe[:2] = b"MZ"
    struct.pack_into("<I", pe, 0x3C, 64)
    pe += b"PE\0\0\x64\xaa"
    dtb = b"\xd0\x0d\xfe\xed" + struct.pack(">I", 40) + bytes(32)
    files = {
        INSTALLER["BOOTLOADER"]: pe,
        f"{payload}/linux": pe,
        f"{payload}/initrd": b"synthetic initrd",
        f"{payload}/sm8550-xiaomi-sheng.dtb": dtb,
        f"{payload}/kernel.store-path": f"{closure}\n".encode(),
        "loader/loader.conf": f"default {entry}\n".encode(),
        f"loader/entries/{entry}": (
            f"title Sheng\nversion {version}\narchitecture aa64\noptions ro\n"
            f"linux /{payload}/linux\ninitrd /{payload}/initrd\ndevicetree /{payload}/sm8550-xiaomi-sheng.dtb\n"
        ).encode(),
    }
    esp = path / "esp"
    for name, content in files.items():
        file = esp / name
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_bytes(content)
    def manifest(base, output, names):
        (base / output).write_text("".join(f"{DIGEST(base / name)}  {name}\n" for name in names))

    manifest(esp, "manifest.sha256", files)
    with tempfile.TemporaryDirectory() as root:
        (Path(root) / closure.lstrip("/")).mkdir(parents=True)
        subprocess.run(["mkfs.ext4", "-q", "-F", "-d", root, path / "rootfs.img", "16M"], check=True)
    manifest(path, "SHA256SUMS", ["rootfs.img", "esp/manifest.sha256"])


class InstallerTests(unittest.TestCase):
    def test_preserved_layout_uses_names_and_types(self):
        _, root, esp = SELECT(disks())
        self.assertEqual(root["path"], "/dev/sdz3")
        self.assertEqual(esp["path"], "/dev/sdz4")

    def test_original_layout_and_ambiguous_label_are_refused(self):
        with self.assertRaisesRegex(ValueError, "缺少 linux、linux-boot 分区"):
            SELECT(disks()[:3])
        table = disks()
        table.append({**table[3], "path": "/dev/sdz5"})
        with self.assertRaisesRegex(ValueError, "唯一的 linux"):
            SELECT(table)

    def test_wrong_lun_or_efi_type_is_refused(self):
        table = disks()
        table[4]["pkname"] = "sda"
        with self.assertRaisesRegex(ValueError, "同一目标"):
            SELECT(table)
        table = disks()
        table[4]["parttype"] = INSTALLER["LINUX_TYPE"]
        with self.assertRaisesRegex(ValueError, "必须是 EFI"):
            SELECT(table)

    def test_mounted_and_unmarked_systems_are_refused(self):
        layout = SELECT(disks())
        device = INSTALLER["Device"]("fixture")
        with patch.object(device, "shell", return_value=""):
            with self.assertRaisesRegex(ValueError, "RAM"):
                device.guard(layout)
        current = SELECT(disks())
        current[1]["mountpoints"] = ["/nix/store"]
        with patch.object(device, "layout", return_value=current), patch.object(
            device, "shell", side_effect=["sheng", "0", "Filename"]
        ):
            with self.assertRaisesRegex(ValueError, "已挂载"):
                device.guard(layout)

    def test_manifest_tampering_stops_install(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            make_bundle(root)
            VALIDATE(root)
            (root / "esp" / INSTALLER["BOOTLOADER"]).write_bytes(b"modified")
            with self.assertRaisesRegex(ValueError, "SHA-256 不匹配"):
                VALIDATE(root)

    def test_fat_merge_preserves_android_and_other_entries(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            make_bundle(root)
            _, _, hashes = VALIDATE(root)
            previous, candidate = root / "previous.fat", root / "candidate.fat"
            with previous.open("wb") as stream:
                stream.truncate(96 * MIB)
            subprocess.run(["mkfs.fat", "-F", "32", previous], check=True, stdout=subprocess.DEVNULL)
            original = root / "original"
            original.write_bytes(b"existing configuration\n")
            for parent in ("SHENG", "loader", "loader/entries"):
                subprocess.run(["mmd", "-i", previous, f"::/{parent}"], check=True)
            for name in ("SHENG/ANDROID.ENV", "loader/entries/other-linux.conf"):
                subprocess.run(["mcopy", "-i", previous, original, f"::/{name}"], check=True)
            backup_digest = DIGEST(previous)
            PREPARE(previous, candidate, {"fstype": "vfat"}, root, hashes, 512)

            def read(name):
                return subprocess.check_output(["mtype", "-i", candidate, f"::/{name}"])

            self.assertEqual(DIGEST(previous), backup_digest)
            self.assertEqual(read("SHENG/ANDROID.ENV"), original.read_bytes())
            self.assertEqual(read("loader/entries/other-linux.conf"), original.read_bytes())
            self.assertIn(b"  loader/entries/other-linux.conf\n", read("manifest.sha256"))
            self.assertEqual(read(INSTALLER["BOOTLOADER"]), (root / "esp" / INSTALLER["BOOTLOADER"]).read_bytes())

    def test_unformatted_esp_uses_the_ufs_sector_size(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            make_bundle(root)
            _, _, hashes = VALIDATE(root)
            candidate = root / "candidate.fat"
            PREPARE(root / "unused", candidate, {"fstype": None, "size": 384 * MIB}, root, hashes, 4096)
            with candidate.open("rb") as stream:
                stream.seek(11)
                self.assertEqual(struct.unpack("<H", stream.read(2))[0], 4096)
            self.assertEqual(candidate.stat().st_size, 384 * MIB)


if __name__ == "__main__":
    unittest.main()
