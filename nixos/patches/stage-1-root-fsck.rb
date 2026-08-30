# Run an ext filesystem check before Mobile NixOS mounts the root filesystem.
#
# AutoResize normally checks the filesystem only when it also needs resizing.
# That leaves an already full-sized filesystem with a recorded error mounted
# without e2fsck, which can turn later metadata damage into a read-only root.
class Tasks::AutoResize
  unless method_defined?(:sheng_run_without_root_fsck)
    alias_method :sheng_run_without_root_fsck, :run
  end

  def sheng_run_e2fsck(mode)
    script =
      'e2fsck "$1" "$2"; status=$?; ' \
      'case "$status" in ' \
      '0|1) exit 0 ;; ' \
      '2) e2fsck -p "$2"; status=$?; ' \
      'case "$status" in 0|1) exit 0 ;; *) exit "$status" ;; esac ;; ' \
      '*) exit "$status" ;; ' \
      'esac'

    System.run_long_running("sh", "-c", script, "sheng-e2fsck", mode, @device)
  end

  def run()
    if @type.match(/^ext[234]$/)
      Progress.exec_with_message("Checking #{@device}...") do
        # Let e2fsck replay the journal and perform checks when the filesystem
        # state, mount count, or check interval requires them. Forcing a full
        # scan after every hard reset delays stage-2 long enough for the ADSP
        # sensor service registration window to expire on sheng.
        log("Running e2fsck -p on #{@device}.")

        begin
          sheng_run_e2fsck("-p")
        rescue System::CommandError => error
          $logger.warn("Automatic filesystem check failed (#{error}); retrying with repairs enabled.")
          sheng_run_e2fsck("-fy")
        end
      end
    end

    sheng_run_without_root_fsck
  end
end
