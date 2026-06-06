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

  def render(generations, selected, seconds_left)
    labels = ["NixOS - Default"] + generations.map { |generation| generation.label() }

    console.write("\e[H")
    console.write("NixOS Sheng - Select stage-2 generation\n\n")
    labels.each_with_index do |label, index|
      marker = index == selected ? ">" : " "
      console.write("#{marker} #{label}\n")
    end
    console.write("\nVolume +/-: select    Power: boot\n")
    console.write("Booting selection in #{seconds_left}s\n")
    console.write("\e[J")
    console.flush
  end

  def choose(switch_root)
    generations = Tasks::SwitchRoot::NixOSGeneration.generations()
    selected = 0
    deadline = Time.now.to_i + timeout()
    wait_for_release(VOLUME_UP + VOLUME_DOWN + CONFIRM)
    load_font()
    console.write("\e[?25l\e[2J\e[H")
    console.flush
    last_selected = nil
    last_seconds_left = nil

    loop do
      seconds_left = deadline - Time.now.to_i
      seconds_left = 0 if seconds_left < 0
      if selected != last_selected || seconds_left != last_seconds_left
        render(generations, selected, seconds_left)
        last_selected = selected
        last_seconds_left = seconds_left
      end

      if pressed?(VOLUME_UP)
        selected = (selected - 1) % (generations.length + 1)
        wait_for_release(VOLUME_UP)
      elsif pressed?(VOLUME_DOWN)
        selected = (selected + 1) % (generations.length + 1)
        wait_for_release(VOLUME_DOWN)
      elsif pressed?(CONFIRM)
        wait_for_release(CONFIRM)
        break
      elsif Time.now.to_i >= deadline
        break
      end

      sleep(0.1)
    end

    console.write("\e[?25h\nBooting selected generation...\n")
    console.flush

    if selected == 0
      Tasks::SwitchRoot::NixOSGeneration.new(switch_root.default_selection_path())
    else
      generations[selected - 1]
    end
  end
end

class Tasks::SwitchRoot
  def selected_generation()
    return @selected_generation if @selected_generation

    wants_menu = Hal::Recovery.wants_recovery? || ShengHeadlessGenerationMenu.requested?()

    if wants_menu &&
       ShengHeadlessStage1.enabled? &&
       ShengHeadlessGenerationMenu.enabled?
      ShengHeadlessGenerationMenu.consume_request()
      @selected_generation = ShengHeadlessGenerationMenu.choose(self)
    elsif wants_menu && !ShengHeadlessStage1.enabled?
      Tasks::Splash.instance.quit("Continuing to recovery menu")
      @selected_generation = choose_generation()
    else
      if wants_menu
        $logger.info("Headless stage-1: skipping recovery generation menu.")
      end

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
