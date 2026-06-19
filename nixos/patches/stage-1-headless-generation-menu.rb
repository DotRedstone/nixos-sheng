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
  MENU_CONSOLE_PATH = "/dev/tty1"
  FALLBACK_CONSOLE_PATH = "/dev/tty0"

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

  def console_path()
    @console_path || FALLBACK_CONSOLE_PATH
  end

  def console()
    @console ||= begin
      File.open(console_path(), "w")
    rescue
      $stderr
    end
  end

  def activate_console()
    System.run("chvt", "1")
    @console_path = MENU_CONSOLE_PATH
  rescue System::CommandError => error
    @console_path = FALLBACK_CONSOLE_PATH
    $logger.warn("Could not switch to sheng generation menu console: #{error}")
  end

  def load_font()
    System.run("setfont", "-C", console_path(), FONT_PATH)
  rescue System::CommandError => error
    $logger.warn("Could not load sheng generation menu font: #{error}")
  end

  def set_console_echo(enabled)
    System.run("stty", "-F", console_path(), enabled ? "echo" : "-echo")
  rescue System::CommandError => error
    $logger.warn("Could not update sheng generation menu console echo: #{error}")
  end

  def set_console_keyboard(enabled)
    mode = enabled ? "-u" : "-d"
    System.run("kbd_mode", "-f", mode, "-C", console_path())
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

  def menu_line(row, text = "")
    "\e[#{row};1H#{text}\e[0m\e[K"
  end

  def generation_line(label, index, selected)
    padded_label = label.ljust(70)
    if index == selected
      "\e[1m\e[32m  > #{padded_label}"
    else
      "    #{padded_label}"
    end
  end

  def status_line(remaining)
    if remaining
      msg = "  Autoboot in #{remaining} seconds. Press any key to stop."
      msg.sub(remaining.to_s, "\e[1m#{remaining}\e[0m")
    else
      "  Autoboot stopped. Waiting for selection..."
    end
  end

  def render(generations, selected, previous_selected: nil, remaining: nil, previous_remaining: nil)
    labels = generations.empty? ? ["NixOS - Default"] : generations.map { |generation| generation.label() }
    help_row = 5 + labels.length
    status_row = help_row + 2
    full_redraw = previous_selected.nil?

    # Use absolute cursor positioning instead of streaming newline-delimited
    # rows. fbcon can scroll if a redraw lands near the bottom of its logical
    # tty, which duplicates the menu tail below the intended viewport.
    out = full_redraw ? "\e[0m\e[r\e[?7l\e[1;1H\e[J" : "\e[0m\e[r\e[?7l"

    if full_redraw
      out += menu_line(2, "  \e[1m\e[36m=== NixOS Boot Menu ===")
      labels.each_with_index do |label, index|
        out += menu_line(4 + index, generation_line(label, index, selected))
      end
      out += menu_line(help_row, "  [Vol +/-] Navigate   [Power] Select")
    elsif previous_selected != selected
      if previous_selected && previous_selected >= 0 && previous_selected < labels.length
        out += menu_line(4 + previous_selected, generation_line(labels[previous_selected], previous_selected, selected))
      end
      out += menu_line(4 + selected, generation_line(labels[selected], selected, selected))
    end

    if full_redraw || previous_remaining != remaining
      out += menu_line(status_row, status_line(remaining))
    end

    out += "\e[1;1H"
    console.write(out)
    console.flush
  end

  def choose(switch_root)
    generations = Tasks::SwitchRoot::NixOSGeneration.generations()
    selected = 0
    deadline = Time.now.to_i + timeout()
    countdown_active = true
    activate_console()
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
        render(
          generations,
          selected,
          previous_selected: last_selected,
          remaining: remaining,
          previous_remaining: last_remaining
        )
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
    console.write("\e[?7h\e[?25h\nBooting selected generation...\n")
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
