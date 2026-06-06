module ShengHeadlessGenerationMenu
  extend self

  VOLUME_UP = [:KEY_VOLUMEUP]
  VOLUME_DOWN = [:KEY_VOLUMEDOWN]
  CONFIRM = [:KEY_POWER, :KEY_ENTER]

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

  def render(generations, selected, seconds_left)
    labels = ["NixOS - Default"] + generations.map { |generation| generation.label() }

    console.write("\e[2J\e[H")
    console.write("NixOS Sheng - Select stage-2 generation\n\n")
    labels.each_with_index do |label, index|
      marker = index == selected ? ">" : " "
      console.write("#{marker} #{label}\n")
    end
    console.write("\nVolume +/-: select    Power: boot\n")
    console.write("Booting selection in #{seconds_left}s\n")
    console.flush
  end

  def choose(switch_root)
    generations = Tasks::SwitchRoot::NixOSGeneration.generations()
    selected = 0
    deadline = Time.now.to_i + timeout()
    wait_for_release(VOLUME_UP + VOLUME_DOWN + CONFIRM)

    loop do
      seconds_left = deadline - Time.now.to_i
      seconds_left = 0 if seconds_left < 0
      render(generations, selected, seconds_left)

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

    console.write("\nBooting selected generation...\n")
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

    if Hal::Recovery.wants_recovery? &&
       ShengHeadlessStage1.enabled? &&
       ShengHeadlessGenerationMenu.enabled?
      @selected_generation = ShengHeadlessGenerationMenu.choose(self)
    elsif Hal::Recovery.wants_recovery? && !ShengHeadlessStage1.enabled?
      Tasks::Splash.instance.quit("Continuing to recovery menu")
      @selected_generation = choose_generation()
    else
      if Hal::Recovery.wants_recovery?
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
