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
  version = "7.0.0";
  modDirVersion = "7.0.0";
  src = shengKernelSrc;
  configfile = ./config.aarch64;
  patches = [
    ./0001-disable-dp0-sheng.patch
    ./0002-ucsi-glink-debug-retry.patch
    ./0003-pdr-pd-mapper-debug.patch
    ./0004-pdr-add-sheng-sensor-pd-lookup.patch
  ];

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

    echo "--- usb/input config ---"
    grep -nE '^(CONFIG_USB=|CONFIG_USB_COMMON=|CONFIG_USB_XHCI_HCD=|CONFIG_USB_XHCI_PLATFORM=|CONFIG_USB_DWC3=|CONFIG_USB_DWC3_QCOM=|CONFIG_USB_ROLE_SWITCH=|CONFIG_TYPEC=|CONFIG_TYPEC_UCSI=|CONFIG_UCSI_PMIC_GLINK=|CONFIG_QCOM_PMIC_GLINK=|CONFIG_QCOM_PMIC_GLINK_ALT_MODE=|CONFIG_QCOM_PDR_HELPERS=|CONFIG_QCOM_PD_MAPPER=|CONFIG_QRTR=|CONFIG_HID=|CONFIG_HID_GENERIC=|CONFIG_USB_HID=|CONFIG_INPUT_EVDEV=|CONFIG_USB_STORAGE=)' build/.config || true

    echo "--- qcom typec/pdr config ---"
    grep -nE '^CONFIG_QRTR=|^CONFIG_QCOM_PD_MAPPER=|^CONFIG_QCOM_PDR_HELPERS=|^CONFIG_QCOM_PMIC_GLINK=|^CONFIG_UCSI_PMIC_GLINK=|^CONFIG_TYPEC_UCSI=|^CONFIG_USB_ROLE_SWITCH=' build/.config || true

    echo "--- pmic glink power supply config ---"
    grep -nE '^CONFIG_POWER_SUPPLY=|^CONFIG_BATTERY_QCOM_BATTMGR=|^CONFIG_QCOM_PMIC_GLINK=|^CONFIG_UCSI_PMIC_GLINK=|^CONFIG_TYPEC_UCSI=|^CONFIG_TYPEC=|^CONFIG_QRTR=|^CONFIG_QCOM_PD_MAPPER=' build/.config || true

    echo "--- sensors / iio config ---"
    sensor_config_pattern='^CONFIG_IIO=|^CONFIG_IIO_BUFFER=|^CONFIG_IIO_KFIFO_BUF=|^CONFIG_IIO_TRIGGERED_BUFFER=|^CONFIG_IIO_TRIGGER=|^CONFIG_QCOM_SSC_BLOCK_BUS=|^CONFIG_QCOM_FASTRPC=|^CONFIG_INV_ICM42600=|^CONFIG_INV_ICM42600_I2C=|^CONFIG_INV_ICM42600_SPI=|^CONFIG_IIO_INV_SENSORS_TIMESTAMP=|^CONFIG_STK3310=|^CONFIG_I2C=|^CONFIG_SPI_MASTER=|^CONFIG_REGMAP_I2C=|^CONFIG_REGMAP_SPI='
    grep -nE "$sensor_config_pattern" build/.config || true

    echo "--- required sensors / iio config check ---"
    sensor_config_failed=0
    require_kernel_config() {
      symbol="$1"
      if grep -qE "^''${symbol}=(y|m)$" build/.config; then
        grep -nE "^''${symbol}=" build/.config
      else
        echo "ERROR: required kernel config ''${symbol}=y/m is missing from final build/.config" >&2
        grep -nE "^''${symbol}=|^# ''${symbol} is not set" build/.config >&2 || \
          echo "ERROR: ''${symbol} is absent from final build/.config" >&2
        sensor_config_failed=1
      fi
    }

    require_kernel_config CONFIG_IIO
    require_kernel_config CONFIG_IIO_BUFFER
    require_kernel_config CONFIG_IIO_KFIFO_BUF
    require_kernel_config CONFIG_IIO_TRIGGERED_BUFFER
    require_kernel_config CONFIG_IIO_TRIGGER
    require_kernel_config CONFIG_I2C
    require_kernel_config CONFIG_SPI_MASTER
    require_kernel_config CONFIG_REGMAP_I2C
    require_kernel_config CONFIG_REGMAP_SPI
    require_kernel_config CONFIG_QCOM_SSC_BLOCK_BUS
    require_kernel_config CONFIG_INV_ICM42600
    require_kernel_config CONFIG_INV_ICM42600_I2C
    require_kernel_config CONFIG_INV_ICM42600_SPI
    require_kernel_config CONFIG_STK3310

    if [ "$sensor_config_failed" -ne 0 ]; then
      echo "ERROR: refusing to build/upload a boot image without the requested sheng IIO sensor configs" >&2
      exit 1
    fi

    echo "--- compiler identity ---"
    command -v clang || true
    clang --version | head -3 || true
    clang -print-target-triple || true
    clang -print-resource-dir || true
  '';
}
