# Run an ext filesystem check before Mobile NixOS mounts the root filesystem.
#
# AutoResize normally checks the filesystem only when it also needs resizing.
# That leaves an already full-sized filesystem with a recorded error mounted
# without e2fsck, which can turn later metadata damage into a read-only root.
class Tasks::AutoResize
  unless method_defined?(:sheng_run_without_root_fsck)
    alias_method :sheng_run_without_root_fsck, :run
  end

  def run()
    if @type.match(/^ext[234]$/)
      Progress.exec_with_message("Checking #{@device}...") do
        begin
          System.run_long_running("e2fsck", "-p", @device)
        rescue System::CommandError => error
          $logger.warn("Automatic filesystem check failed (#{error}); retrying with repairs enabled.")
          System.run_long_running("e2fsck", "-y", @device)
        end
      end
    end

    sheng_run_without_root_fsck
  end
end
