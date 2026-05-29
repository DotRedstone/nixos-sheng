class Tasks::SwitchRoot
  def run()
    init = File.join(selected_generation.path, "init")

    # This is the traditional way we printed the init path.
    # This is still helpful to take vertical real estate when visually looking
    # through the log.
    log("")
    log("***")
    log("")
    if will_kexec?
      log("Kexecing into #{selected_generation.path}")
    else
      log("Switching root to #{init}")
    end
    log("")
    log("***")
    log("")

    kexec_in_generation(selected_generation) if will_kexec?

    Tasks::UDev.instance.teardown()

    [
      "/proc",
      "/sys",
      "/dev",
      "/run",
    ].each do |mount_point|
      new_location = File.join(SYSTEM_MOUNT_POINT, mount_point)
      FileUtils.mkdir_p(new_location)
      System.run("mount", "--move", mount_point, new_location)
    end

    switch_root = System.which("switch_root")

    # Temporary bring-up delay: remove after confirming stage-2 takes over.
    log("sheng debug: about to switch_root to #{init}; sleeping 10 seconds for adb log capture")
    sleep(10)

    System.exec({}, switch_root, SYSTEM_MOUNT_POINT, init)
  end
end
