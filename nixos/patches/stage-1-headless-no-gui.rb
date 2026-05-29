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
    if LOG_LEVEL == Logger::DEBUG
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
