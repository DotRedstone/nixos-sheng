# ---
# Module: Headless Generation Menu
# Description: Mobile NixOS stage-1 headless boot menu implementation
# Scope: Patch
# ---

module ShengHeadlessGenerationMenu
  extend self

  VOLUME_UP = [:KEY_VOLUMEUP, :KEY_UP]
  VOLUME_DOWN = [:KEY_VOLUMEDOWN, :KEY_DOWN]
  CONFIRM = [:KEY_POWER, :KEY_ENTER]
  REQUEST_PATH = "/mnt/var/lib/sheng-boot-menu/requested"
  FONT_PATH = "/etc/sheng-generation-menu-font.psf.gz"

  def config()
    Configuration["sheng_generation_menu"] || {}
  end

  def enabled?()
    config()["enable"] == true
  end

  def timeout()
    (config()["timeout"] || 30).to_i
  end

  def pressed?(keys)
    Evdev.keys_held(keys)
  end

  def requested?()
    File.exist?(REQUEST_PATH)
  end

  def consume_request()
    File.delete(REQUEST_PATH) if requested?()
  end

  def wait_for_release(keys)
    sleep(0.1) while pressed?(keys)
  end

  def console()
    @console ||= begin
      File.open("/dev/tty0", "w")
    rescue
      $stderr
    end
  end

  def load_font()
    System.run("setfont", "-C", "/dev/tty0", FONT_PATH)
  rescue System::CommandError => error
    $logger.warn("Could not load sheng generation menu font: #{error}")
  end

  def set_console_echo(enabled)
    System.run("stty", "-F", "/dev/tty0", enabled ? "echo" : "-echo")
  rescue System::CommandError => error
    $logger.warn("Could not update sheng generation menu console echo: #{error}")
  end

  def set_console_keyboard(enabled)
    mode = enabled ? "-u" : "-d"
    System.run("kbd_mode", "-f", mode, "-C", "/dev/tty0")
  rescue System::CommandError => error
    $logger.warn("Could not update sheng generation menu keyboard mode: #{error}")
  end

  def suppress_console_logs()
    @previous_printk = File.read("/proc/sys/kernel/printk")
    File.write("/proc/sys/kernel/printk", "1\n")
  rescue => error
    $logger.warn("Could not suppress kernel logs during sheng generation menu: #{error}")
  end

  def restore_console_logs()
    File.write("/proc/sys/kernel/printk", @previous_printk) if @previous_printk
  rescue => error
    $logger.warn("Could not restore kernel console log level: #{error}")
  end

  def render(generations, selected, remaining: nil)
    labels = generations.empty? ? ["NixOS - Default"] : generations.map { |generation| generation.label() }

    # \e[H moves to top-left. We use space padding instead of \e[2K to completely eliminate flicker.
    # \e[2K clears the line to black before drawing, causing a visible flash. Space padding overwrites seamlessly.
    out = "\e[H"
    out += "                                                                                \n"
    out += "  \e[1m\e[36m=== NixOS Boot Menu ===\e[0m                                                       \n"
    out += "                                                                                \n"

    labels.each_with_index do |label, index|
      padded_label = label.ljust(70)
      if index == selected
        out += "\e[1m\e[32m  > #{padded_label}\e[0m\n"
      else
        out += "    #{padded_label}\n"
      end
    end

    out += "                                                                                \n"
    out += "  [Vol +/-] Navigate   [Power] Select                                           \n"
    out += "                                                                                \n"

    if remaining
      msg = "  Autoboot in #{remaining} seconds. Press any key to stop."
      # Embolden just the number, but calculate padding correctly
      # We just pad the raw string and then insert the color codes
      padded_msg = msg.ljust(80).sub(remaining.to_s, "\e[1m#{remaining}\e[0m")
      out += "#{padded_msg}\n"
    else
      msg = "  Autoboot stopped. Waiting for selection..."
      out += "#{msg.ljust(80)}\n"
    end

    # Clear anything below our menu just in case, this won't flicker because the area is already empty
    out += "\e[J"
    console.write(out)
    console.flush
  end

  def choose(switch_root)
    generations = Tasks::SwitchRoot::NixOSGeneration.generations()
    selected = 0
    deadline = Time.now.to_i + timeout()
    countdown_active = true
    load_font()
    set_console_echo(false)
    set_console_keyboard(false)
    suppress_console_logs()
    wait_for_release(VOLUME_UP + VOLUME_DOWN + CONFIRM)
    console.write("\e[?25l\e[2J\e[H")
    console.flush
    last_selected = nil
    last_remaining = nil
    volume_up_was_pressed = false
    volume_down_was_pressed = false
    up_pressed_time = 0.0
    up_last_repeat = 0.0
    down_pressed_time = 0.0
    down_last_repeat = 0.0

    loop do
      remaining = countdown_active ? [deadline - Time.now.to_i, 0].max : nil
      needs_redraw = (selected != last_selected) || (remaining != last_remaining)

      if needs_redraw
        render(generations, selected, remaining: remaining)
        last_selected = selected
        last_remaining = remaining
      end

      volume_up_pressed = pressed?(VOLUME_UP)
      volume_down_pressed = pressed?(VOLUME_DOWN)

      action_up = false
      action_down = false
      now_t = Time.now.to_f

      if volume_up_pressed
        if !volume_up_was_pressed
          action_up = true
          up_pressed_time = now_t
          up_last_repeat = now_t
        elsif now_t - up_pressed_time > 0.4 && now_t - up_last_repeat > 0.1
          action_up = true
          up_last_repeat = now_t
        end
      end

      if volume_down_pressed
        if !volume_down_was_pressed
          action_down = true
          down_pressed_time = now_t
          down_last_repeat = now_t
        elsif now_t - down_pressed_time > 0.4 && now_t - down_last_repeat > 0.1
          action_down = true
          down_last_repeat = now_t
        end
      end

      if action_up
        countdown_active = false
        menu_length = generations.empty? ? 1 : generations.length
        selected = (selected - 1) % menu_length
      elsif action_down
        countdown_active = false
        menu_length = generations.empty? ? 1 : generations.length
        selected = (selected + 1) % menu_length
      elsif pressed?(CONFIRM)
        wait_for_release(CONFIRM)
        break
      elsif countdown_active && Time.now.to_i >= deadline
        break
      end

      volume_up_was_pressed = volume_up_pressed
      volume_down_was_pressed = volume_down_pressed
      sleep(0.01)
    end

    set_console_echo(true)
    set_console_keyboard(true)
    restore_console_logs()
    console.write("\e[?25h\nBooting selected generation...\n")
    console.flush

    if generations.empty?
      Tasks::SwitchRoot::NixOSGeneration.new(switch_root.default_selection_path())
    else
      generations[selected]
    end
  end
end

class Tasks::SwitchRoot
  def selected_generation()
    return @selected_generation if @selected_generation

    explicit_request = Hal::Recovery.wants_recovery? || ShengHeadlessGenerationMenu.requested?()
    multiple_generations = NixOSGeneration.generations().length > 0
    wants_menu = explicit_request || multiple_generations

    if wants_menu &&
       ShengHeadlessStage1.enabled? &&
       ShengHeadlessGenerationMenu.enabled?
      ShengHeadlessGenerationMenu.consume_request()
      @selected_generation = ShengHeadlessGenerationMenu.choose(self)
    elsif wants_menu && !ShengHeadlessStage1.enabled?
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
