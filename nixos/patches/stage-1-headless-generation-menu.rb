# ---
# Module: Headless Generation Menu
# Description: Mobile NixOS stage-1 headless boot menu implementation
# Scope: Patch
# ---

module ShengHeadlessGenerationMenu
  extend self

  VOLUME_UP = [:KEY_VOLUMEUP]
  VOLUME_DOWN = [:KEY_VOLUMEDOWN]
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

    console.write("\e[H")
    console.write("\e[2K\n")
    console.write("\e[2K  \e[1m\e[36m=== NixOS Boot Menu ===\e[0m\n\n")
    labels.each_with_index do |label, index|
      console.write("\e[2K\r")
      if index == selected
        console.write("\e[1m\e[32m  > #{label}  \e[0m\n")
      else
        console.write("    #{label}\n")
      end
    end
    console.write("\e[2K\n\e[2K  [Vol +/-] Navigate   [Power] Select\n")
    if remaining
      console.write("\e[2K\n\e[2K  Autoboot in \e[1m#{remaining}\e[0m seconds. Press any key to stop.\n")
    else
      console.write("\e[2K\n\e[2K  Autoboot stopped. Waiting for selection...\n")
    end
    console.write("\e[J")
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

      if volume_up_pressed && !volume_up_was_pressed
        countdown_active = false
        menu_length = generations.empty? ? 1 : generations.length
        selected = (selected - 1) % menu_length
      elsif volume_down_pressed && !volume_down_was_pressed
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
