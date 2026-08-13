# ---
# Module: Early Charge Guard
# Description: Keep critically low batteries out of the full userspace boot
# Scope: Patch
# ---

module ShengEarlyChargeGuard
  extend self

  # Sheng reports this after a battery brownout followed by USB insertion.
  # The low byte is Qualcomm PON HARD_RESET (bit 0) | USB_CHG (bit 4).
  SHENG_USB_HARD_RESET_REASON = /^bootinfo\.pureason=0x0*8000?11$/i

  def config()
    Configuration["sheng_early_charge_guard"] || {}
  end

  def enabled?()
    config()["enable"] == true
  end

  def critical_capacity()
    (config()["critical_capacity"] || 2).to_i
  end

  def boot_capacity()
    (config()["boot_capacity"] || 5).to_i
  end

  def max_wait_seconds()
    [(config()["max_wait_seconds"] || 30).to_i, 0].max
  end

  def charger_mode?()
    return true if System.cmdline().include?("androidboot.mode=charger")
    return true if System.cmdline().any? do |argument|
      argument =~ SHENG_USB_HARD_RESET_REASON
    end
    return false unless File.exist?("/proc/bootconfig")

    File.read("/proc/bootconfig").each_line.any? do |line|
      line =~ /^\s*androidboot\.mode\s*=\s*"?charger"?\s*$/
    end
  rescue
    false
  end

  def power_supply_type(path)
    File.read(File.join(path, "type")).strip
  rescue
    ""
  end

  def battery_capacity()
    Dir.glob("/sys/class/power_supply/*").each do |path|
      next unless power_supply_type(path) == "Battery"

      capacity_path = File.join(path, "capacity")
      next unless File.exist?(capacity_path)

      return File.read(capacity_path).strip.to_i
    rescue
      next
    end

    nil
  end

  def external_power_online?()
    battery_is_charging = false

    Dir.glob("/sys/class/power_supply/*").each do |path|
      if power_supply_type(path) == "Battery"
        status = File.read(File.join(path, "status")).strip
        battery_is_charging = true if status == "Charging" || status == "Full"
        next
      end

      online_path = File.join(path, "online")
      return true if File.exist?(online_path) && File.read(online_path).strip == "1"
    rescue
      next
    end

    battery_is_charging
  end

  def saved_backlights()
    @saved_backlights ||= {}
  end

  def blank_display()
    Dir.glob("/sys/class/backlight/*/brightness").each do |path|
      saved_backlights[path] = File.read(path).strip unless saved_backlights.key?(path)
      File.write(path, "0\n")
    rescue
    end

    Dir.glob("/sys/class/graphics/fb*/blank").each do |path|
      File.write(path, "1\n")
    rescue
    end
  end

  def restore_display()
    saved_backlights.each do |path, brightness|
      File.write(path, "#{brightness}\n") if File.exist?(path)
    rescue
    end

    Dir.glob("/sys/class/graphics/fb*/blank").each do |path|
      File.write(path, "0\n")
    rescue
    end
  end

  def wait_for_battery()
    15.times do
      capacity = battery_capacity()
      return capacity unless capacity.nil?
      sleep(1)
    end

    nil
  end

  def wait_for_external_power()
    15.times do
      return true if external_power_online?()
      sleep(1)
    end

    false
  end

  def wait_if_critical()
    return unless enabled?

    capacity = wait_for_battery()
    if capacity.nil?
      $logger.warn("Early charge guard: battery capacity is unavailable; continuing boot.")
      return
    end
    return if capacity > critical_capacity()

    unless wait_for_external_power()
      $logger.warn("Early charge guard: battery is at #{capacity}% but external power is offline; continuing boot.")
      return
    end

    charger_boot = charger_mode?()
    wait_limit = charger_boot ? "without a timeout" : "for at most #{max_wait_seconds()} seconds"
    $logger.info(
      "Early charge guard: battery is at #{capacity}%; charging with the display off until #{boot_capacity()}% " \
      "(#{wait_limit})."
    )
    blank_display()
    last_report = nil
    offline_checks = 0
    elapsed = 0
    target_reached = false

    loop do
      capacity = battery_capacity()
      if capacity && capacity >= boot_capacity()
        target_reached = true
        break
      end

      if !charger_boot && elapsed >= max_wait_seconds()
        $logger.warn(
          "Early charge guard: pre-charge timed out at #{capacity || "unknown"}%; continuing boot so userspace charging can start."
        )
        break
      end

      if external_power_online?()
        offline_checks = 0
      else
        offline_checks += 1
        if offline_checks >= 3
          $logger.warn("Early charge guard: charger disconnected while battery is critical; powering off.")
          System.run("poweroff", "-f")
          sleep(60)
        end
      end

      if capacity != last_report
        $logger.info("Early charge guard: battery capacity is #{capacity || "unknown"}%.")
        last_report = capacity
      end
      sleep(5)
      elapsed += 5
    end

    $logger.info("Early charge guard: battery reached #{capacity}%; continuing boot.") if target_reached
    restore_display() unless charger_boot
  end
end
