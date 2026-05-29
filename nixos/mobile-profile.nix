{ config, lib, pkgs, ... }:

let
  closureInfo = pkgs.buildPackages.closureInfo {
    rootPaths = [ config.system.build.toplevel ];
  };

  splashWithoutGraphicsTask = pkgs.writeTextDir "zz-sheng-splash-without-graphics.rb" ''
    class Tasks::Splash
      def splash_disabled?()
        Configuration["splash"] && Configuration["splash"]["disabled"]
      end

      def initialize()
        add_dependency(:Target, :Graphics) unless splash_disabled?
        add_dependency(:Task, Tasks::ProgressSocket.instance)
      end

      def run()
        return if splash_disabled?
        args = []
        if LOG_LEVEL ==  Logger::DEBUG
          args << "--verbose"
        end

        if System.cmdline().grep("mobile-nixos.kexec=yes").any?
          args << "--skip-fadein"
        end

        wait_for_input_devices

        begin
          $logger.info "Starting splash..."
          @pid = System.spawn(LOADER, "/applets/boot-splash.mrb", *args)
        rescue System::CommandError
        end
      end

      def quit(reason, sticky: nil)
        return if splash_disabled?
        return if @pid.nil?
        count = 0
        Progress.update({progress: 100, label: reason})
        Progress.update({command: {name: "quit"}, sticky: sticky})
        loop do
          Progress.send_state()
          break if Process.wait(@pid, Process::WNOHANG)
          sleep(0.1)
          count += 1
          if count > 60
            $logger.fatal("Splash applet would not quit by itself...")
            kill
            break
          end
        end
        @pid = nil
      end
    end

    class Tasks::Graphics
      def splash_disabled?()
        Configuration["splash"] && Configuration["splash"]["disabled"]
      end

      def initialize()
        unless splash_disabled?
          add_dependency(
            :Any,
            Dependencies::Task.new(FBDev.instance),
            Dependencies::Task.new(DRM.instance),
          )
        end

        Targets[:Graphics].add_dependency(:Task, self)
      end
    end

    class Tasks::Graphics::FBDev
      def splash_disabled?()
        Configuration["splash"] && Configuration["splash"]["disabled"]
      end

      def initialize()
        return if splash_disabled?
        add_dependency(
          :Files,
          "/sys/class/graphics/fb0",
        )
        add_dependency(:Mount, "/dev")
      end
    end

    class Tasks::Graphics::DRM
      def splash_disabled?()
        Configuration["splash"] && Configuration["splash"]["disabled"]
      end

      def initialize()
        return if splash_disabled?
        add_dependency(
          :Files,
          "/dev/dri/card0",
        )
        add_dependency(:Mount, "/dev")
      end
    end

    class Tasks::SwitchRoot
      def splash_disabled?()
        Configuration["splash"] && Configuration["splash"]["disabled"]
      end

      def selected_generation()
        return @selected_generation if @selected_generation

        if Hal::Recovery.wants_recovery? && !splash_disabled?
          Tasks::Splash.instance.quit("Continuing to recovery menu")
          @selected_generation = choose_generation()
        else
          @selected_generation = NixOSGeneration.new(default_selection_path())
          if will_kexec?()
            Tasks::Splash.instance.quit("Rebooting in generation kernel", sticky: true)
          else
            Tasks::Splash.instance.quit("Continuing to stage-2")
          end
        end
        @selected_generation
      end
    end
  '';
in
{
  mobile.enable = true;

  mobile.generatedFilesystems.rootfs.name = "nixos-sheng-rootfs";
  mobile.generatedFilesystems.rootfs.filesystem = lib.mkDefault "ext4";
  mobile.generatedFilesystems.rootfs.label = lib.mkForce "linux";
  mobile.generatedFilesystems.rootfs.location = lib.mkForce "/rootfs.img";
  mobile.generatedFilesystems.rootfs.extraPadding = lib.mkForce (1024 * 1024 * 1024);
  mobile.generatedFilesystems.rootfs.populateCommands = ''
    mkdir -p ./nix/store
    echo "Copying system closure..."

    err=0
    while IFS= read -r path; do
      echo "  Copying $path"
      if test -e "$path"; then
        cp -prf "$path" ./nix/store
      else
        2>&1 printf "ERROR: path %q does not exist...\n" "$path"
        (( ++err ))
      fi
    done < "${closureInfo}/store-paths"

    if (( err > 0 )); then
      2>&1 printf "... Bailing out, %d errors.\n" "$err"
      exit 2
    fi

    echo "Done copying system closure."
    cp -v ${closureInfo}/registration ./nix-path-registration
  '';

  fileSystems."/" = lib.mkForce {
    device = "/dev/disk/by-partlabel/linux";
    fsType = "ext4";
    neededForBoot = true;
    autoResize = false;
    options = [ "noatime" ];
  };

  mobile.boot.stage-1 = {
    compression = "gzip";
    crashToBootloader = false;

    bootConfig = {
      log.level = "DEBUG";
      boot.fail.shell = true;
      splash.disabled = true;
    };

    gui = {
      enable = false;
    };

    tasks = [
      splashWithoutGraphicsTask
    ];

    shell.shellOnFail = true;

    kernel.modules = [ ];
    kernel.additionalModules = [ ];
  };

  mobile.boot.stage-1.fail.reboot = false;

  mobile.adbd.enable = lib.mkDefault true;

  mobile.beautification.silentBoot = lib.mkForce false;

  systemd.services.adbd = lib.mkIf config.mobile.adbd.enable {
    script = lib.mkForce ''
      ${pkgs.adbd}/bin/adbd &

      # Wait a bit so the FunctionFS userspace endpoint is ready before binding.
      sleep 1

      if [ -e /sys/kernel/config/usb_gadget ]; then
        for gadget in /sys/kernel/config/usb_gadget/*; do
          [ -d "$gadget" ] || continue
          [ -e "$gadget/UDC" ] || continue

          read -r current_udc < "$gadget/UDC" || current_udc=""
          udc_name="$current_udc"

          if [ -z "$udc_name" ]; then
            for udc in /sys/class/udc/*; do
              [ -e "$udc" ] || continue
              udc_name="''${udc##*/}"
              break
            done
          fi

          [ -n "$udc_name" ] || continue
          printf '%s' "$udc_name" > "$gadget/UDC" || true
        done
      fi

      wait
    '';
  };

  boot.postBootCommands = lib.mkBefore ''
    if [ -f /nix-path-registration ]; then
      ${config.nix.package.out}/bin/nix-store --load-db < /nix-path-registration
      touch /etc/NIXOS
      ${config.nix.package.out}/bin/nix-env -p /nix/var/nix/profiles/system --set /run/current-system
      rm -f /nix-path-registration
    fi
  '';

  documentation.enable = false;
}
