#!/usr/bin/env python3
"""Android ROM 配置采集的离线边界测试。"""

import importlib.util
from pathlib import Path
import struct
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


SOURCE = Path(__file__).with_name("sheng-android-rom-config.py")
SPEC = importlib.util.spec_from_file_location("sheng_android_rom_config", SOURCE)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class RomConfigTests(unittest.TestCase):
    def setUp(self):
        self.props = {
            "ro.product.device": "sheng",
            "ro.boot.slot_suffix": "_a",
            "ro.boot.boot_devices": "soc/1d84000.ufshc",
            "ro.boot.bootdevice": "1d84000.ufshc",
            "ro.boot.fstab_suffix": "default",
            "ro.boot.dynamic_partitions": "true",
            "ro.boot.verifiedbootstate": "orange",
        }

    def test_getprop_and_bootconfig_parse(self):
        props = MODULE.parse_getprop(b"[ro.product.device]: [sheng]\n[ro.boot.slot_suffix]: [_a]\n")
        bootconfig = MODULE.parse_bootconfig(b'androidboot.boot_devices = "soc/1d84000.ufshc"\n')
        cmdline = MODULE.parse_cmdline(b"quiet androidboot.verifiedbootstate=orange")
        self.assertEqual(props["ro.product.device"], "sheng")
        self.assertEqual(bootconfig["androidboot.boot_devices"], "soc/1d84000.ufshc")
        self.assertEqual(cmdline["androidboot.verifiedbootstate"], "orange")

    def test_valid_profile_roundtrip(self):
        profile = MODULE.profile_from_android(self.props, {}, {})
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "ANDROID.ENV"
            path.write_bytes(MODULE.serialize_profile(profile))
            self.assertEqual(MODULE.read_profile(path), profile)

    def test_bootconfig_fallback_and_bootdevice_derivation(self):
        del self.props["ro.boot.boot_devices"]
        del self.props["ro.boot.bootdevice"]
        profile = MODULE.profile_from_android(
            self.props, {"androidboot.boot_devices": "soc/1d84000.ufshc"}, {}
        )
        self.assertEqual(profile["android_bootdevice"], "1d84000.ufshc")

    def test_capture_uses_properties_when_proc_files_are_unreadable(self):
        properties = "".join(f"[{key}]: [{value}]\n" for key, value in self.props.items()).encode()

        def adb_result(_serial, *args):
            if args == ("shell", "getprop"):
                return properties
            raise RuntimeError("/proc 访问被 Android 拒绝")

        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "ANDROID.ENV"
            with patch.object(MODULE, "adb_command", side_effect=adb_result):
                MODULE.capture(SimpleNamespace(serial=None, output=output))
            self.assertEqual(MODULE.read_profile(output)["android_profile_slot"], "_a")

    def test_vendor_device_identifies_custom_rom(self):
        self.props["ro.product.device"] = "custom-sheng-rom"
        self.props["ro.product.vendor.device"] = "sheng"
        self.assertEqual(MODULE.profile_from_android(self.props, {}, {})["android_profile_board"], "sheng")

    def test_missing_boot_parameter_is_rejected(self):
        del self.props["ro.boot.fstab_suffix"]
        with self.assertRaisesRegex(ValueError, "android_fstab_suffix"):
            MODULE.profile_from_android(self.props, {}, {})

    def test_wrong_slot_is_rejected_and_native_green_becomes_unverified_handoff(self):
        self.props["ro.boot.slot_suffix"] = "_b"
        with self.assertRaisesRegex(ValueError, "A 槽"):
            MODULE.profile_from_android(self.props, {}, {})
        self.props["ro.boot.slot_suffix"] = "_a"
        self.props["ro.boot.verifiedbootstate"] = "green"
        self.assertEqual(
            MODULE.profile_from_android(self.props, {}, {})["android_verifiedbootstate"],
            "orange",
        )

    def test_shell_metacharacters_and_extra_fields_are_rejected(self):
        self.props["ro.boot.boot_devices"] = "soc/ufs;reset"
        with self.assertRaisesRegex(ValueError, "不安全字符"):
            MODULE.profile_from_android(self.props, {}, {})
        self.props["ro.boot.boot_devices"] = "soc/1d84000.ufshc"
        profile = MODULE.profile_from_android(self.props, {}, {})
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "ANDROID.ENV"
            path.write_bytes(MODULE.serialize_profile(profile) + b"bootcmd=reset\n")
            with self.assertRaisesRegex(ValueError, "未知字段"):
                MODULE.read_profile(path)

    def test_dtbo_preflight_rejects_empty_b_slot(self):
        MODULE.check_dtbo_header(bytes.fromhex("d7b7ab1e"), "dtbo_a")
        with self.assertRaisesRegex(ValueError, "dtbo_b"):
            MODULE.check_dtbo_header(b"\0\0\0\0", "dtbo_b")

    def test_dtbo_copy_requires_blank_equal_sized_b(self):
        image = MODULE.DTBO_MAGIC + b"payload"
        self.assertFalse(MODULE.dtbo_copy_needed(image, image))
        self.assertTrue(MODULE.dtbo_copy_needed(image, b"\0" * len(image)))
        with self.assertRaisesRegex(ValueError, "大小不同"):
            MODULE.dtbo_copy_needed(image, b"\0")
        with self.assertRaisesRegex(ValueError, "人工核对"):
            MODULE.dtbo_copy_needed(image, MODULE.DTBO_MAGIC + b"changed")

    def test_v4_image_sizes_fit_windows_even_when_partitions_are_larger(self):
        boot = bytearray(4096)
        init = bytearray(4096)
        vendor = bytearray(4096)
        dtbo = bytearray(4096)
        for header in (boot, init):
            header[:8] = b"ANDROID!"
            struct.pack_into("<II", header, 20, 1584, 0)
            struct.pack_into("<I", header, 40, 4)
        struct.pack_into("<I", boot, 8, 47 * 1024 * 1024)
        struct.pack_into("<I", init, 12, 2 * 1024 * 1024)
        vendor[:8] = b"VNDRBOOT"
        for offset, value in ((8, 4), (12, 4096), (24, 30 * 1024 * 1024),
                              (2096, 2128), (2100, 4 * 1024 * 1024),
                              (2112, 108), (2116, 1), (2120, 108), (2124, 128)):
            struct.pack_into("<I", vendor, offset, value)
        dtbo[:4] = MODULE.DTBO_MAGIC
        struct.pack_into(">II", dtbo, 4, 14 * 1024 * 1024, 32)
        headers = (boot, vendor, init, dtbo)
        sizes = MODULE.v4_image_lengths(*headers)
        MODULE.check_read_windows(sizes, {
            "boot_a": 192 * 1024 * 1024,
            "vendor_boot_a": 96 * 1024 * 1024,
            "init_boot_a": 8 * 1024 * 1024,
            "dtbo_a": 24 * 1024 * 1024,
        })
        struct.pack_into("<I", boot, 8, 65 * 1024 * 1024)
        with self.assertRaisesRegex(ValueError, "boot_a 镜像有效长度"):
            MODULE.check_read_windows(MODULE.v4_image_lengths(*headers), {
                name: 192 * 1024 * 1024 for name in MODULE.READ_WINDOWS
            })
        struct.pack_into("<I", boot, 40, 3)
        with self.assertRaisesRegex(ValueError, "boot_a 不是"):
            MODULE.v4_image_lengths(*headers)


if __name__ == "__main__":
    unittest.main()
