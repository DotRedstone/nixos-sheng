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

  def console_size()
    width, height = File.read("/sys/class/graphics/fb0/virtual_size").strip.split(",").map(&:to_i)
    columns = width / 16
    rows = height / 32
    rows = 40 if rows.nil? || rows <= 0
    columns = 80 if columns.nil? || columns <= 0
    [rows, columns]
  rescue
    [40, 80]
  end

  def visible_line(text, columns)
    visible_length = text.gsub(/\e\[[0-9;?]*[A-Za-z]/, "").length
    "#{text}\e[0m#{' ' * [columns - visible_length, 0].max}"
  end

  def render(generations, selected, remaining: nil)
    labels = generations.empty? ? ["NixOS - Default"] : generations.map { |generation| generation.label() }
    rows, columns = console_size()
    blank_line = " " * columns

    # Repaint the whole visible console with spaces instead of relying on ED/J.
    # On sheng's early fbcon, erase-to-end can occasionally leave stale scanout
    # contents below the menu until the panel refreshes again.
    lines = Array.new(rows, blank_line)
    lines[1] = visible_line("  \e[1m\e[36m=== NixOS Boot Menu ===", columns)

    labels.each_with_index do |label, index|
      line_index = 3 + index
      break if line_index >= rows

      max_label_width = [columns - 6, 10].max
      padded_label = label[0, max_label_width].ljust(max_label_width)
      if index == selected
        lines[line_index] = visible_line("\e[1m\e[32m  > #{padded_label}", columns)
      else
        lines[line_index] = visible_line("    #{padded_label}", columns)
      end
    end

    help_index = [4 + labels.length, rows - 3].min
    lines[help_index] = visible_line("  [Vol +/-] Navigate   [Power] Select", columns)

    if remaining
      msg = "  Autoboot in #{remaining} seconds. Press any key to stop."
      lines[[help_index + 2, rows - 1].min] =
        visible_line(msg.sub(remaining.to_s, "\e[1m#{remaining}\e[0m"), columns)
    else
      msg = "  Autoboot stopped. Waiting for selection..."
      lines[[help_index + 2, rows - 1].min] = visible_line(msg, columns)
    end

    console.write("\e[H\e[0m")
    console.write(lines.join("\n"))
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
    console.write("\e[?25l\e[0m\e[H\e[2J\e[3J")
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
