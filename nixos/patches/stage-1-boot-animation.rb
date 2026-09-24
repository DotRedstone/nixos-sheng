# ---
# Module: Sheng Boot Animation
# Description: Coordinate the native splash, generation menu and diagnostic VT
# Scope: Patch
# ---
module ShengBootAnimation
  CONTROL = "/run/sheng-boot-ui"
  PAINTER = "sheng-fb-painter"
  ASSETS = "/etc/sheng-boot-animation"

  def self.enabled?()
    cfg = Configuration["sheng_boot_animation"]
    cfg && cfg["enable"] == true &&
      !System.cmdline().include?("sheng.boot-ui=0") &&
      !File.exist?("#{CONTROL}.disabled")
  end

  def self.start(phase)
    return unless enabled?
    if phase == "prepare"
      # /mnt may not exist yet. Do not call charger_mode? here: its reboot
      # marker probe is cached and would misclassify a normal USB reboot.
      reason = ShengEarlyChargeGuard.boot_value("bootinfo.pureason")
      force_normal = ShengEarlyChargeGuard.boot_value("androidboot.force_normal_boot") == "1"
      power_key = ShengEarlyChargeGuard.power_key_power_on_reason?(reason)
      charger = ShengEarlyChargeGuard.boot_value("androidboot.mode").to_s.downcase == "charger" ||
        ShengEarlyChargeGuard.charger_power_on_reason?(reason)
      return if charger && !force_normal && !power_key
    else
      return if ShengEarlyChargeGuard.charger_mode?()
    end
    File.write("#{CONTROL}.normal", "normal\n")
    File.delete("#{CONTROL}.ready") if File.exist?("#{CONTROL}.ready")
    @pid = System.spawn(PAINTER, "--animate", ASSETS, phase, CONTROL)
    # Before switch_root unlinks the old initrd, the child must have loaded its
    # frames and opened the control/VT descriptors it carries across the move.
    if phase == "start"
      100.times do
        return if File.exist?("#{CONTROL}.ready")
        sleep(0.01)
      end
      stop()
      details()
    end
  rescue => error
    $logger.warn("Could not start Sheng boot animation: #{error}")
    details()
  end

  def self.stop()
    # The previous stage can leave a painter alive across switch_root even when
    # this Ruby instance no longer owns its pid. The control protocol is safe
    # to send when no painter exists and makes the writer handoff explicit.
    System.run(PAINTER, "--stop", CONTROL)
    Process.wait(@pid, Process::WNOHANG) if @pid
    @pid = nil
  rescue => error
    $logger.warn("Could not stop Sheng boot animation: #{error}")
    # Never leave a painter racing the menu after a control timeout.
    begin
      System.run("kill", "-KILL", @pid.to_s) if @pid
      Process.wait(@pid) if @pid
    rescue
      # It may already have exited or been reaped by the task runner.
    end
    @pid = nil
  end

  def self.details()
    System.run(PAINTER, "--details", CONTROL)
  rescue => error
    $logger.warn("Could not switch to Sheng diagnostic console: #{error}")
  end
end

class Tasks::Splash
  alias_method :sheng_initialize_without_animation, :initialize
  alias_method :sheng_run_without_animation, :run
  alias_method :sheng_kill_without_animation, :kill

  def initialize()
    sheng_initialize_without_animation
    add_dependency(:Mount, "/proc")
    add_dependency(:Mount, "/dev")
  end

  def run()
    if ShengBootAnimation.enabled?
      ShengBootAnimation.start("prepare")
    elsif System.cmdline().include?("sheng.boot-ui=0")
      ShengBootAnimation.details()
    else
      sheng_run_without_animation
    end
  end

  def kill()
    ShengBootAnimation.stop()
    # Upstream System.failure -> Progress.kill is the caller. Successful
    # switch_root does not kill the splash; keep real failures diagnosable.
    ShengBootAnimation.details()
    sheng_kill_without_animation
  end
end
