# ---
# Module: Kernel Config (Sheng)
# Description: Custom kernel and patches for xiaomi-sheng
# Scope: Host
# ---

{ mobile-nixos
, shengKernelSrc
, buildPackages
, ...
}:

let
  pkgs = buildPackages;
  llvmPkgs = pkgs.llvmPackages;
in
mobile-nixos.kernel-builder-clang {
  version = "7.1.8";
  modDirVersion = "7.1.8";
  src = shengKernelSrc;
  configfile = ./config.aarch64;
  patches = [ ];

  isModular = true;
  isCompressed = "gz";
  isImageGzDtb = false;
  enableRemovingWerror = true;
  nativeBuildInputs = [
    buildPackages.lld
    buildPackages.llvmPackages.clang
    buildPackages.llvmPackages.llvm
    pkgs.buildPackages.python3
    pkgs.buildPackages.zstd
  ];
  makeFlags = [
    "LLVM=1"
    "CC=${llvmPkgs.clang-unwrapped}/bin/clang"
    "LD=${pkgs.lld}/bin/ld.lld"
    "AR=${llvmPkgs.llvm}/bin/llvm-ar"
    "NM=${llvmPkgs.llvm}/bin/llvm-nm"
    "OBJCOPY=${llvmPkgs.llvm}/bin/llvm-objcopy"
    "OBJDUMP=${llvmPkgs.llvm}/bin/llvm-objdump"
    "READELF=${llvmPkgs.llvm}/bin/llvm-readelf"
    "STRIP=${llvmPkgs.llvm}/bin/llvm-strip"
    "KCFLAGS=-Wno-error=unused-command-line-argument"
    "KCPPFLAGS=-Wno-error=unused-command-line-argument"
  ];

  postConfigure = ''
    echo "===== effective kernel config diagnostics ====="

    require_config() {
      expected="$1"
      symbol="''${expected%%=*}"
      if ! grep -qxF "$expected" build/.config; then
        echo "ERROR: required sheng kernel option is missing: $expected"
        grep -nE "^$symbol=|^# $symbol is not set" build/.config || true
        exit 1
      fi
    }

    # These are device/user ABI requirements rather than optional generic
    # drivers. Keep this list small so accidental config pruning fails early.
    require_config "CONFIG_COMPAT=y"
    require_config "CONFIG_KUSER_HELPERS=y"
    require_config "CONFIG_KERNEL_MODE_NEON=y"
    require_config "CONFIG_F2FS_FS=m"
    require_config "CONFIG_EXFAT_FS=m"
    require_config "CONFIG_VFAT_FS=m"
    require_config "CONFIG_BTRFS_FS=m"
    require_config "CONFIG_EROFS_FS=m"
    require_config "CONFIG_INPUT_FPC1552=y"

    # These groups can disappear without making the image unbootable. Check
    # the effective Kconfig so dependency changes fail in CI instead of later
    # showing up as a missing tablet function.
    require_config "CONFIG_PREEMPT=y"
    require_config "CONFIG_NO_HZ_IDLE=y"
    require_config "CONFIG_SCHED_CLUSTER=y"
    require_config "CONFIG_UCLAMP_TASK=y"
    require_config "CONFIG_ENERGY_MODEL=y"
    require_config "CONFIG_LRU_GEN=y"
    require_config "CONFIG_WQ_POWER_EFFICIENT_DEFAULT=y"
    require_config "CONFIG_ARM_QCOM_CPUFREQ_HW=y"
    require_config "CONFIG_ARM_PSCI_CPUIDLE=y"
    require_config "CONFIG_QCOM_RPMH=y"
    require_config "CONFIG_QCOM_RPMHPD=y"
    require_config "CONFIG_INTERCONNECT_QCOM_SM8550=y"

    require_config "CONFIG_SCSI_UFS_QCOM=y"
    require_config "CONFIG_PHY_QCOM_QMP_UFS=y"
    require_config "CONFIG_QCOM_Q6V5_PAS=y"
    require_config "CONFIG_QCOM_PDR_HELPERS=y"
    require_config "CONFIG_QCOM_PD_MAPPER=y"
    require_config "CONFIG_QRTR=y"
    require_config "CONFIG_QRTR_SMD=y"
    require_config "CONFIG_QCOM_FASTRPC=y"

    require_config "CONFIG_QCOM_PMIC_GLINK=y"
    require_config "CONFIG_UCSI_PMIC_GLINK=y"
    require_config "CONFIG_TYPEC_MUX_PS5169=y"
    require_config "CONFIG_BATTERY_QCOM_BATTMGR=y"
    require_config "CONFIG_QCOM_TSENS=y"
    require_config "CONFIG_QCOM_SPMI_TEMP_ALARM=y"
    require_config "CONFIG_DRM_MSM=y"

    require_config "CONFIG_SND_SOC_SC8280XP=m"
    require_config "CONFIG_SND_SOC_WCD938X_SDW=m"
    require_config "CONFIG_SND_SOC_CS35L43_I2C=m"
    require_config "CONFIG_TOUCHSCREEN_NT36532E_SPI=m"
    require_config "CONFIG_VIDEO_S5KJN1_SHENG=m"
    require_config "CONFIG_VIDEO_OV32D40=m"

    echo "--- io_uring ---"
    grep -nE '^CONFIG_IO_URING=|^# CONFIG_IO_URING is not set' build/.config || true

    echo "--- rootfs essentials ---"
    grep -nE '^CONFIG_EXT4_FS=|^CONFIG_BLK_DEV_INITRD=|^CONFIG_DEVTMPFS=|^CONFIG_TMPFS=' build/.config || true

    echo "--- compat / neon ---"
    grep -nE '^CONFIG_COMPAT=|^# CONFIG_COMPAT is not set|^CONFIG_COMPAT_VDSO=|^# CONFIG_COMPAT_VDSO is not set|^CONFIG_KUSER_HELPERS=|^# CONFIG_KUSER_HELPERS is not set|^CONFIG_KERNEL_MODE_NEON=|^# CONFIG_KERNEL_MODE_NEON is not set' build/.config || true

    echo "--- gpio shared proxy ---"
    grep -nE '^CONFIG_HAVE_SHARED_GPIOS=|^CONFIG_GPIO_SHARED=|^CONFIG_GPIO_SHARED_PROXY=' build/.config || true

    echo "--- mobile-nixos network validation related ---"
    grep -nE '^CONFIG_BRIDGE=|^CONFIG_BRIDGE_NETFILTER=|^CONFIG_NF_TABLES=|^CONFIG_NETFILTER_XTABLES=|^CONFIG_IP6_NF_IPTABLES=' build/.config || true

    echo "--- general-purpose userspace and filesystems ---"
    grep -nE '^CONFIG_BPF_SYSCALL=|^CONFIG_BPF_UNPRIV_DEFAULT_OFF=|^CONFIG_CGROUP_BPF=|^CONFIG_IO_URING=|^CONFIG_ZRAM=|^CONFIG_ZRAM_DEF_COMP=|^CONFIG_FUSE_FS=|^CONFIG_OVERLAY_FS=|^CONFIG_SQUASHFS=|^CONFIG_EROFS_FS=|^CONFIG_F2FS_FS=|^CONFIG_EXFAT_FS=|^CONFIG_VFAT_FS=|^CONFIG_BTRFS_FS=|^CONFIG_UDF_FS=|^CONFIG_NFS_FS=|^CONFIG_NFS_V3=|^CONFIG_NFS_V4=|^CONFIG_CIFS=' build/.config || true

    echo "--- usb/input config ---"
    grep -nE '^(CONFIG_USB=|CONFIG_USB_COMMON=|CONFIG_USB_XHCI_HCD=|CONFIG_USB_XHCI_PLATFORM=|CONFIG_USB_DWC3=|CONFIG_USB_DWC3_QCOM=|CONFIG_USB_ROLE_SWITCH=|CONFIG_TYPEC=|CONFIG_TYPEC_UCSI=|CONFIG_UCSI_PMIC_GLINK=|CONFIG_QCOM_PMIC_GLINK=|CONFIG_QCOM_PMIC_GLINK_ALT_MODE=|CONFIG_QCOM_PDR_HELPERS=|CONFIG_QCOM_PD_MAPPER=|CONFIG_QRTR=|CONFIG_HID=|CONFIG_HID_GENERIC=|CONFIG_USB_HID=|CONFIG_INPUT_EVDEV=|CONFIG_USB_STORAGE=)' build/.config || true

    echo "--- qcom typec/pdr config ---"
    grep -nE '^CONFIG_QRTR=|^CONFIG_QCOM_PD_MAPPER=|^CONFIG_QCOM_PDR_HELPERS=|^CONFIG_QCOM_PMIC_GLINK=|^CONFIG_UCSI_PMIC_GLINK=|^CONFIG_TYPEC_UCSI=|^CONFIG_USB_ROLE_SWITCH=' build/.config || true

    echo "--- pmic glink power supply config ---"
    grep -nE '^CONFIG_POWER_SUPPLY=|^CONFIG_BATTERY_QCOM_BATTMGR=|^CONFIG_QCOM_PMIC_GLINK=|^CONFIG_UCSI_PMIC_GLINK=|^CONFIG_TYPEC_UCSI=|^CONFIG_TYPEC=|^CONFIG_QRTR=|^CONFIG_QCOM_PD_MAPPER=' build/.config || true

    echo "--- Xiaomi MiPPS hooks ---"
    grep -nE 'BATTMGR_XM_PROPERTY_GET|request_vdm_cmd|qcom_battmgr_xiaomi_attr_group' drivers/power/supply/qcom_battmgr.c || true

    echo "--- compiler identity ---"
    command -v clang || true
    clang --version | head -3 || true
    clang -print-target-triple || true
    clang -print-resource-dir || true
  '';
}
