# ---
# Module: Early Charge Guard
# Description: Keep critically low batteries out of the full userspace boot
# Scope: Patch
# ---

module ShengEarlyChargeGuard
  extend self

  # Qualcomm PON encodes trigger sources in the low byte. A power-key bit wins
  # over USB_CHG so booting normally while connected is never forced offline.
  PON_USB_CHG = 1 << 4
  PON_KPDPWR_N = 1 << 7

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

  def cmdline_value(key)
    prefix = "#{key}="
    argument = System.cmdline().find { |item| item.start_with?(prefix) }
    argument ? argument[prefix.length..-1].delete('"') : nil
  end

  def bootconfig_value(key)
    return nil unless File.exist?("/proc/bootconfig")

    pattern = /^\s*#{Regexp.escape(key)}\s*=\s*"?([^"\s]+)"?\s*$/
    File.read("/proc/bootconfig").each_line do |line|
      match = line.match(pattern)
      return match[1] if match
    end
    nil
  rescue
    nil
  end

  def boot_value(key)
    cmdline_value(key) || bootconfig_value(key)
  end

  def charger_power_on_reason?(value)
    return false if value.nil? || value.empty?()

    reason = Integer(value, 0)
    pon = reason & 0xff
    (pon & PON_USB_CHG) != 0 && (pon & PON_KPDPWR_N) == 0
  rescue ArgumentError, TypeError
    false
  end

  def power_key_power_on_reason?(value)
    return false if value.nil? || value.empty?()

    reason = Integer(value, 0)
    ((reason & 0xff) & PON_KPDPWR_N) != 0
  rescue ArgumentError, TypeError
    false
  end

  def charger_mode?()
    return false if boot_value("androidboot.force_normal_boot") == "1"
    pureason = boot_value("bootinfo.pureason")
    return false if power_key_power_on_reason?(pureason)
    return true if boot_value("androidboot.mode").to_s.downcase == "charger"

    charger_power_on_reason?(pureason)
  rescue
    false
  end

  def interactive_boot_safe?()
    !charger_mode?()
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

  def prepare_offline_charging_handoff()
    return if @offline_charging_handoff_prepared

    Dir.glob("/sys/class/graphics/fb*/blank").each do |path|
      File.write(path, "1\n")
    rescue
    end
    @offline_charging_handoff_prepared = true
    $logger.info("Charger boot: handing off to the offline charging target with the framebuffer blanked.")
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
    # Both paths leave stage-1 and continue into the graphical system. Restore
    # what we blanked even for a charger-mode boot that reached the threshold;
    # otherwise the successful boot can inherit a black panel.
    restore_display()
  end
end
