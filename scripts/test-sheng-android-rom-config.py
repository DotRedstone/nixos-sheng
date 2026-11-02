#!/usr/bin/env python3
"""Android ROM 配置采集的离线边界测试。"""

import importlib.util
from pathlib import Path
import tempfile
import unittest


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

    def test_missing_boot_parameter_is_rejected(self):
        del self.props["ro.boot.fstab_suffix"]
        with self.assertRaisesRegex(ValueError, "android_fstab_suffix"):
            MODULE.profile_from_android(self.props, {}, {})

    def test_wrong_slot_or_locked_state_is_rejected(self):
        self.props["ro.boot.slot_suffix"] = "_b"
        with self.assertRaisesRegex(ValueError, "A 槽"):
            MODULE.profile_from_android(self.props, {}, {})
        self.props["ro.boot.slot_suffix"] = "_a"
        self.props["ro.boot.verifiedbootstate"] = "green"
        with self.assertRaisesRegex(ValueError, "orange"):
            MODULE.profile_from_android(self.props, {}, {})

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


if __name__ == "__main__":
    unittest.main()
