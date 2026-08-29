# ---
# Module: Headless Generation Menu
# Description: Mobile NixOS stage-1 headless boot menu implementation
# Scope: Patch
# ---

module ShengHeadlessGenerationMenu
  extend self

  VOLUME_UP = [:KEY_VOLUMEUP, :KEY_UP]
  VOLUME_DOWN = [:KEY_VOLUMEDOWN, :KEY_DOWN]
  CONFIRM = [:KEY_POWER, :KEY_ENTER, :KEY_KPENTER]
  REQUEST_PATH = "/mnt/var/lib/sheng-boot-menu/requested"
  MENU_CONSOLE_PATH = "/dev/tty2"
  FALLBACK_CONSOLE_PATH = "/dev/tty0"
  FB_PATH = "/dev/fb0"
  FB_SYSFS = "/sys/class/graphics/fb0"
  OUTER_MARGIN = 64
  PANEL_MIN_WIDTH = 720
  PANEL_MAX_WIDTH = 2080
  PANEL_PADDING = 56
  PANEL_BORDER = 2
  FONT_SCALE = 4
  TITLE_FONT_SCALE = 6
  SUBTITLE_FONT_SCALE = 3
  HEADER_HEIGHT = 184
  ROW_HEIGHT = 108
  ROW_GAP = 12
  FOOTER_HEIGHT = 190
  SCROLLBAR_WIDTH = 8
  SCROLLBAR_GAP = 28
  FRAMEBUFFER_PAINTER = "sheng-fb-painter"
  FRAMEBUFFER_COMMAND_PATH = "/run/sheng-generation-menu.fbops"
  FRAMEBUFFER_COMMAND_MAGIC = "SFB1"
  MAX_FRAMEBUFFER_RECTANGLES = 10_000
  MAX_LINE_SAMPLES = 48
  BG = [8, 10, 11]
  PANEL_BG = [17, 19, 21]
  PANEL_BORDER_COLOR = [57, 64, 66]
  ROW_BG = [24, 27, 29]
  SELECT_BG = [35, 67, 67]
  ACCENT = [115, 210, 199]
  ACCENT_DIM = [51, 101, 97]
  TITLE_FG = [242, 246, 245]
  SELECT_FG = [248, 251, 250]
  NORMAL_FG = [207, 214, 212]
  MUTED_FG = [137, 150, 147]
  STATUS_FG = [238, 186, 96]
  BOOT_FG = [121, 218, 158]
  EV_KEY = 1
  KEY_VOLUMEUP = 115
  KEY_VOLUMEDOWN = 114
  KEY_POWER = 116
  KEY_UP = 103
  KEY_DOWN = 108
  KEY_ENTER = 28
  KEY_KPENTER = 96
  INPUT_EVENT_SIZE = 24
  INPUT_SCAN_INTERVAL = 0.25
  NAVIGATION_REPEAT_DELAY = 0.4
  NAVIGATION_REPEAT_INTERVAL = 0.1
  INPUT_ACTION_CODES = {
    up: [KEY_VOLUMEUP, KEY_UP],
    down: [KEY_VOLUMEDOWN, KEY_DOWN],
    confirm: [KEY_POWER, KEY_ENTER, KEY_KPENTER]
  }

  FONT = {
    " " => ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
    "!" => ["00100", "00100", "00100", "00100", "00100", "00000", "00100"],
    "#" => ["01010", "11111", "01010", "01010", "11111", "01010", "01010"],
    "(" => ["00010", "00100", "01000", "01000", "01000", "00100", "00010"],
    ")" => ["01000", "00100", "00010", "00010", "00010", "00100", "01000"],
    "+" => ["00000", "00100", "00100", "11111", "00100", "00100", "00000"],
    "-" => ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
    "." => ["00000", "00000", "00000", "00000", "00000", "01100", "01100"],
    "/" => ["00001", "00010", "00100", "01000", "10000", "00000", "00000"],
    "0" => ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
    "1" => ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    "2" => ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
    "3" => ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
    "4" => ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    "5" => ["11111", "10000", "10000", "11110", "00001", "00001", "11110"],
    "6" => ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
    "7" => ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
    "8" => ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
    "9" => ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
    ":" => ["00000", "01100", "01100", "00000", "01100", "01100", "00000"],
    ">" => ["10000", "01000", "00100", "00010", "00100", "01000", "10000"],
    "?" => ["01110", "10001", "00001", "00010", "00100", "00000", "00100"],
    "[" => ["01110", "01000", "01000", "01000", "01000", "01000", "01110"],
    "]" => ["01110", "00010", "00010", "00010", "00010", "00010", "01110"],
    "_" => ["00000", "00000", "00000", "00000", "00000", "00000", "11111"],
    "A" => ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    "B" => ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
    "C" => ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
    "D" => ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    "E" => ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "F" => ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
    "G" => ["01110", "10001", "10000", "10111", "10001", "10001", "01110"],
    "H" => ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
    "I" => ["01110", "00100", "00100", "00100", "00100", "00100", "01110"],
    "J" => ["00111", "00010", "00010", "00010", "00010", "10010", "01100"],
    "K" => ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
    "L" => ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    "M" => ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
    "N" => ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    "O" => ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "P" => ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
    "Q" => ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
    "R" => ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
    "S" => ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
    "T" => ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    "U" => ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
    "V" => ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
    "W" => ["10001", "10001", "10001", "10101", "10101", "10101", "01010"],
    "X" => ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
    "Y" => ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
    "Z" => ["11111", "00001", "00010", "00100", "01000", "10000", "11111"]
  }

  def config()
    Configuration["sheng_generation_menu"] || {}
  end

  def enabled?()
    config()["enable"] == true
  end

  def timeout()
    [(config()["timeout"] || 3).to_i, 1].max
  end

  def monotonic_time()
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  rescue NameError, NoMethodError
    Time.now.to_f
  end

  def countdown_remaining(deadline)
    remaining = deadline - monotonic_time()
    return 0 if remaining <= 0

    whole_seconds = remaining.to_i
    whole_seconds + (remaining > whole_seconds ? 1 : 0)
  end

  def navigation_repeat_due?(pressed_at, last_repeat, now)
    now - pressed_at >= NAVIGATION_REPEAT_DELAY &&
      now - last_repeat >= NAVIGATION_REPEAT_INTERVAL
  end

  def requested?()
    File.exist?(REQUEST_PATH)
  end

  def consume_request()
    File.delete(REQUEST_PATH) if requested?()
  end

  def wait_for_release(keys)
    20.times do
      poll_input_action(0.01)
      break unless input_held?(keys)
    end
  end

  def input_devices()
    @input_devices ||= {}
  end

  def input_held()
    @input_held ||= {}
  end

  def input_open_flags()
    @input_open_flags ||= begin
      flags = File::RDONLY
      @input_nonblocking = File.const_defined?(:NONBLOCK)
      flags |= File::NONBLOCK if @input_nonblocking
      flags
    end
  end

  def key_codes(keys)
    keys.map do |key|
      case key
      when :KEY_VOLUMEUP
        KEY_VOLUMEUP
      when :KEY_VOLUMEDOWN
        KEY_VOLUMEDOWN
      when :KEY_POWER
        KEY_POWER
      when :KEY_UP
        KEY_UP
      when :KEY_DOWN
        KEY_DOWN
      when :KEY_ENTER
        KEY_ENTER
      when :KEY_KPENTER
        KEY_KPENTER
      else
        nil
      end
    end.compact
  end

  def remove_input_device(path)
    dev = input_devices.delete(path)
    input_held.delete(path)
    dev.close if dev && !dev.closed?
  rescue
  end

  def refresh_input_devices(force: false)
    now = Time.now.to_f
    if !force && @last_input_scan && now - @last_input_scan < INPUT_SCAN_INTERVAL
      return
    end

    @last_input_scan = now

    input_devices.keys.each do |path|
      remove_input_device(path) unless File.exist?(path)
    end

    Dir.glob("/dev/input/event*").sort.each do |path|
      next if input_devices.key?(path)

      begin
        input_devices[path] = File.open(path, input_open_flags())
        input_held[path] = {}
      rescue Errno::ENOENT, Errno::ENODEV, IOError, SystemCallError => error
        $logger.warn("Ignoring unavailable sheng generation menu input device #{path}: #{error}")
      end
    end
  end

  def input_action_for_code(code)
    return :up if INPUT_ACTION_CODES[:up].include?(code)
    return :down if INPUT_ACTION_CODES[:down].include?(code)
    return :confirm if INPUT_ACTION_CODES[:confirm].include?(code)

    nil
  end

  def unpack_input_event(data)
    return nil unless data && data.bytesize == INPUT_EVENT_SIZE

    bytes = data.bytes
    type = bytes[16] | (bytes[17] << 8)
    code = bytes[18] | (bytes[19] << 8)
    value = bytes[20] | (bytes[21] << 8) | (bytes[22] << 16) | (bytes[23] << 24)
    value -= 0x100000000 if value >= 0x80000000
    [type, code, value]
  rescue => error
    $logger.warn("Ignoring malformed sheng generation menu input event: #{error}")
    nil
  end

  def read_input_events(path, dev)
    action = nil
    reads = 0

    loop do
      data = dev.sysread(INPUT_EVENT_SIZE)
      break unless data && data.bytesize == INPUT_EVENT_SIZE

      event = unpack_input_event(data)
      next unless event

      type, code, value = event
      if type == EV_KEY
        input_held[path] ||= {}
        if value == 0
          input_held[path].delete(code)
        elsif value == 1 || value == 2
          input_held[path][code] = true
          # Kernel key-repeat rates differ between the tablet buttons and USB
          # keyboards. Emit only the press edge here; choose() provides one
          # predictable repeat clock for every navigation device.
          action ||= input_action_for_code(code) if value == 1
        end
      end

      reads += 1
      break if reads >= 32 || !@input_nonblocking
    end

    action
  rescue Errno::EAGAIN
    action
  rescue EOFError, Errno::ENOENT, Errno::ENODEV, IOError, SystemCallError => error
    $logger.warn("Removing stale sheng generation menu input device #{path}: #{error}")
    remove_input_device(path)
    action
  end

  def poll_input_action(timeout)
    refresh_input_devices()

    readers = input_devices.values
    if readers.empty?
      sleep(timeout)
      return nil
    end

    ready = IO.select(readers, nil, nil, timeout)
    return nil unless ready

    ready[0].each do |dev|
      path = input_devices.key(dev)
      next unless path

      action = read_input_events(path, dev)
      return action if action
    end

    nil
  rescue => error
    $logger.warn("Ignoring sheng generation menu input polling failure: #{error}")
    sleep(timeout)
    nil
  end

  def input_held?(keys)
    codes = key_codes(keys)
    input_held.values.any? do |states|
      codes.any? { |code| states[code] }
    end
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
    System.run("chvt", "2")
    @console_path = MENU_CONSOLE_PATH
  rescue System::CommandError => error
    @console_path = FALLBACK_CONSOLE_PATH
    $logger.warn("Could not switch to sheng generation menu console: #{error}")
  end

  def set_console_echo(enabled)
    if enabled
      System.run("stty", "-F", console_path(), "sane")
    else
      System.run(
        "stty",
        "-F",
        console_path(),
        "raw",
        "-echo",
        "-echoe",
        "-echok",
        "-echoctl",
        "-echoke",
        "min",
        "0",
        "time",
        "0"
      )
    end
  rescue System::CommandError => error
    $logger.warn("Could not update sheng generation menu console echo: #{error}")
  end

  def set_console_keyboard(enabled)
    mode = enabled ? "-u" : "-s"
    System.run("kbd_mode", mode, "-C", console_path())
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

  def read_fb_integer(name, fallback)
    path = "#{FB_SYSFS}/#{name}"
    return fallback unless File.exist?(path)

    File.read(path).strip.to_i
  rescue
    fallback
  end

  def framebuffer_info()
    return if @fb_ready

    size = File.read("#{FB_SYSFS}/virtual_size").strip.split(",").map { |part| part.to_i }
    @fb_width = size[0]
    @fb_height = size[1]
    @fb_bpp = read_fb_integer("bits_per_pixel", 32)
    @fb_bytes = [@fb_bpp / 8, 2].max
    @fb_stride = read_fb_integer("stride", @fb_width * @fb_bytes)
    @fb_stride = @fb_width * @fb_bytes if @fb_stride <= 0
    @fb_ready = true
  end

  def draw_operations()
    @draw_operations ||= []
  end

  def mark_framebuffer_dirty(y, height)
    top = clamp(y, 0, @fb_height)
    bottom = clamp(y + height, 0, @fb_height)
    return if bottom <= top

    @dirty_top = top if !@dirty_top || top < @dirty_top
    @dirty_bottom = bottom if !@dirty_bottom || bottom > @dirty_bottom
  end

  def unblank_framebuffer()
    blank_path = "#{FB_SYSFS}/blank"
    return true unless File.exist?(blank_path)

    File.write(blank_path, "0\n")
    state = File.read(blank_path).strip
    raise IOError, "framebuffer remained blank (state #{state})" unless state == "0"

    true
  rescue => error
    $logger.warn("Could not unblank sheng generation menu framebuffer: #{error}")
    false
  end

  def framebuffer_rectangles()
    rectangles = []
    draw_operations().each do |operation|
      if operation[0] == :rect
        rectangles << operation
        next
      end

      x = operation[1]
      y = operation[2]
      width = operation[3]
      height = operation[4]
      text, fg, bg, scale, align = operation[5]
      rectangles << [:rect, x, y, width, height, bg]
      chars = text.upcase.each_char.to_a
      max_chars = [width / (6 * scale), 0].max
      chars = chars[0, max_chars]
      rendered_width = [chars.length * 6 * scale - scale, 0].max
      start_x =
        case align
        when :right
          [width - rendered_width, 0].max
        when :center
          [(width - rendered_width) / 2, 0].max
        else
          0
        end

      chars.each_with_index do |char, char_index|
        glyph_runs(char).each_with_index do |runs, glyph_y|
          destination_y = glyph_y * scale
          next if destination_y >= height

          runs.each do |run_start, run_width|
            destination_x = start_x + (char_index * 6 + run_start) * scale
            next if destination_x >= width

            clipped_width = [run_width * scale, width - destination_x].min
            rectangles << [
              :rect,
              x + destination_x,
              y + destination_y,
              clipped_width,
              [scale, height - destination_y].min,
              fg
            ]
          end
        end
      end
    end
    rectangles
  end

  def framebuffer_command_data(rectangles)
    raise IOError, "no framebuffer rectangles were generated" if rectangles.empty?()
    if rectangles.length > MAX_FRAMEBUFFER_RECTANGLES
      raise IOError, "framebuffer rectangle limit exceeded (#{rectangles.length})"
    end

    data = FRAMEBUFFER_COMMAND_MAGIC.dup
    rectangles.each do |operation|
      x, y, width, height, color = operation[1], operation[2], operation[3], operation[4], operation[5]
      data << [x, y, width, height].pack("v4")
      data << [color[0], color[1], color[2], 0].pack("C4")
    end
    data
  end

  def write_framebuffer_commands(path, rectangles)
    data = framebuffer_command_data(rectangles)
    file = File.open(path, "wb")
    written = 0
    while written < data.bytesize
      count = file.syswrite(data[written, data.bytesize - written])
      raise IOError, "short framebuffer command write" unless count && count > 0

      written += count
    end
    file.close
  rescue
    file.close if file && !file.closed?
    raise
  end

  def present_framebuffer()
    return unless @dirty_top && @dirty_bottom

    started_at = Time.now.to_f
    operation_count = draw_operations().length
    rectangles = framebuffer_rectangles()
    raise IOError, "sheng generation menu framebuffer is blank" unless unblank_framebuffer()
    begin
      write_framebuffer_commands(FRAMEBUFFER_COMMAND_PATH, rectangles)
      System.run(FRAMEBUFFER_PAINTER, FRAMEBUFFER_COMMAND_PATH)
      raise IOError, "sheng generation menu framebuffer became blank" unless unblank_framebuffer()
    ensure
      File.delete(FRAMEBUFFER_COMMAND_PATH) if File.exist?(FRAMEBUFFER_COMMAND_PATH)
      @draw_operations = []
      @dirty_top = nil
      @dirty_bottom = nil
    end
    if $logger.respond_to?(:debug)
      $logger.debug(
        "Sheng generation framebuffer presented #{operation_count} operations as " \
        "#{rectangles.length} native rectangles in #{(Time.now.to_f - started_at).round(3)}s."
      )
    end
  end
  def pixel(color)
    r, g, b = color
    case @fb_bpp
    when 16
      value = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)
      [value].pack("v")
    when 24
      [b, g, r].pack("C3")
    else
      [b, g, r, 0].pack("C4")
    end
  end

  def clamp(value, min, max)
    return min if value < min
    return max if value > max

    value
  end

  def draw_rect(x, y, width, height, color)
    framebuffer_info()
    return if width <= 0 || height <= 0

    x = clamp(x, 0, @fb_width)
    y = clamp(y, 0, @fb_height)
    width = clamp(width, 0, @fb_width - x)
    height = clamp(height, 0, @fb_height - y)
    return if width <= 0 || height <= 0

    draw_operations() << [:rect, x, y, width, height, color]
    mark_framebuffer_dirty(y, height)
  end

  def glyph(char)
    FONT[char.upcase] || FONT["?"]
  end

  def glyph_runs(char)
    @glyph_run_cache ||= {}
    normalized = char.upcase
    return @glyph_run_cache[normalized] if @glyph_run_cache.key?(normalized)

    @glyph_run_cache[normalized] = glyph(normalized).map do |bits|
      runs = []
      run_start = nil
      bits.each_char.with_index do |bit, index|
        if bit == "1"
          run_start = index if run_start.nil?
        elsif run_start
          runs << [run_start, index - run_start]
          run_start = nil
        end
      end
      runs << [run_start, bits.length - run_start] if run_start
      runs
    end
  end

  def draw_text_box(x, y, width, height, text, fg, bg, scale: FONT_SCALE, align: :left)
    framebuffer_info()
    return if width <= 0 || height <= 0

    x = clamp(x, 0, @fb_width)
    y = clamp(y, 0, @fb_height)
    width = clamp(width, 0, @fb_width - x)
    height = clamp(height, 0, @fb_height - y)
    return if width <= 0 || height <= 0

    draw_operations() << [:text, x, y, width, height, [text.to_s, fg, bg, scale, align]]
    mark_framebuffer_dirty(y, height)
  end

  def draw_line(x0, y0, x1, y1, color, thickness = 3)
    framebuffer_info()
    x0 = clamp(x0, 0, @fb_width - 1)
    y0 = clamp(y0, 0, @fb_height - 1)
    x1 = clamp(x1, 0, @fb_width - 1)
    y1 = clamp(y1, 0, @fb_height - 1)
    steps = [(x1 - x0).abs, (y1 - y0).abs].max
    samples = [steps, MAX_LINE_SAMPLES].min
    samples = 1 if samples < 1
    index = 0
    while index <= samples
      x = x0 + (x1 - x0) * index / samples
      y = y0 + (y1 - y0) * index / samples
      draw_rect(x - thickness / 2, y - thickness / 2, thickness, thickness, color)
      index += 1
    end
  end

  def draw_circle(cx, cy, radius, color, thickness = 3)
    half = radius * 3 / 4
    points = [
      [cx, cy - radius], [cx + half, cy - half], [cx + radius, cy], [cx + half, cy + half],
      [cx, cy + radius], [cx - half, cy + half], [cx - radius, cy], [cx - half, cy - half],
      [cx, cy - radius]
    ]
    index = 0
    while index + 1 < points.length
      draw_line(
        points[index][0], points[index][1],
        points[index + 1][0], points[index + 1][1],
        color, thickness
      )
      index += 1
    end
  end

  def draw_brand_mark(x, y, size, color)
    half = size / 2
    diagonal_x = size / 4
    diagonal_y = size * 7 / 16
    center_x = x + half
    center_y = y + half
    thickness = [size / 12, 3].max

    draw_line(center_x - half, center_y, center_x + half, center_y, color, thickness)
    draw_line(
      center_x - diagonal_x,
      center_y - diagonal_y,
      center_x + diagonal_x,
      center_y + diagonal_y,
      color,
      thickness
    )
    draw_line(
      center_x + diagonal_x,
      center_y - diagonal_y,
      center_x - diagonal_x,
      center_y + diagonal_y,
      color,
      thickness
    )
    draw_rect(center_x - thickness, center_y - thickness, thickness * 2, thickness * 2, PANEL_BG)
  end

  def draw_chevron(cx, cy, direction, color, size = 12, thickness = 3)
    if direction == :up
      draw_line(cx - size, cy + size / 2, cx, cy - size / 2, color, thickness)
      draw_line(cx, cy - size / 2, cx + size, cy + size / 2, color, thickness)
    elsif direction == :down
      draw_line(cx - size, cy - size / 2, cx, cy + size / 2, color, thickness)
      draw_line(cx, cy + size / 2, cx + size, cy - size / 2, color, thickness)
    else
      draw_line(cx - size / 2, cy - size, cx + size / 2, cy, color, thickness)
      draw_line(cx + size / 2, cy, cx - size / 2, cy + size, color, thickness)
    end
  end

  def draw_power_icon(cx, cy, color)
    draw_circle(cx, cy + 2, 16, color, 3)
    draw_rect(cx - 5, cy - 19, 10, 20, PANEL_BG)
    draw_rect(cx - 2, cy - 20, 5, 21, color)
  end

  def panel_width()
    framebuffer_info()
    min_width = [PANEL_MIN_WIDTH, @fb_width].min
    max_width = [PANEL_MAX_WIDTH, @fb_width].min
    clamp(@fb_width - OUTER_MARGIN * 2, min_width, max_width)
  end

  def panel_x()
    framebuffer_info()
    (@fb_width - panel_width()) / 2
  end

  def rows_height(visible_count)
    visible_count * ROW_HEIGHT + [visible_count - 1, 0].max * ROW_GAP
  end

  def panel_height(visible_count)
    HEADER_HEIGHT + rows_height(visible_count) + FOOTER_HEIGHT
  end

  def panel_y(visible_count)
    framebuffer_info()
    [(@fb_height - panel_height(visible_count)) / 2, 24].max
  end

  def content_x()
    panel_x() + PANEL_PADDING
  end

  def content_width()
    panel_width() - PANEL_PADDING * 2
  end

  def max_visible_generations()
    framebuffer_info()
    available = @fb_height - OUTER_MARGIN * 2 - HEADER_HEIGHT - FOOTER_HEIGHT
    clamp((available + ROW_GAP) / (ROW_HEIGHT + ROW_GAP), 1, 18)
  end

  def visible_range(count, selected)
    visible = [count, max_visible_generations()].min
    start = count > visible ? (selected / visible) * visible : 0
    [start, [start + visible, count].min]
  end

  def generation_parts(label, index)
    match = /NixOS\s+#(\d+)\s*\((.*)\)/i.match(label.to_s)
    number = match ? match[1] : (index + 1).to_s
    details = match ? match[2].to_s.strip : label.to_s.strip
    details = "SYSTEM PROFILE" if details.empty?
    ["GENERATION #{number}", details]
  end

  def generation_label(generation, index)
    generation.label().to_s
  rescue => error
    $logger.warn("Could not read NixOS generation label: #{error}")
    "NixOS ##{index + 1}"
  end

  def selection_count(selected, count)
    current = (selected + 1).to_s
    total = count.to_s
    current = "0#{current}" if current.length < 2
    total = "0#{total}" if total.length < 2
    "#{current} / #{total}"
  end

  def draw_panel(x, y, width, height)
    draw_rect(x, y, width, height, PANEL_BG)
    draw_rect(x, y, width, PANEL_BORDER, PANEL_BORDER_COLOR)
    draw_rect(x, y + height - PANEL_BORDER, width, PANEL_BORDER, PANEL_BORDER_COLOR)
    draw_rect(x, y, PANEL_BORDER, height, PANEL_BORDER_COLOR)
    draw_rect(x + width - PANEL_BORDER, y, PANEL_BORDER, height, PANEL_BORDER_COLOR)
    draw_rect(x, y, width, 5, ACCENT)
  end

  def row_width(scrollable)
    content_width() - (scrollable ? SCROLLBAR_GAP : 0)
  end

  def draw_generation_row(labels, index, selected, start, visible_count)
    row_y = panel_y(visible_count) + HEADER_HEIGHT +
      (index - start) * (ROW_HEIGHT + ROW_GAP)
    is_selected = index == selected
    bg = is_selected ? SELECT_BG : ROW_BG
    fg = is_selected ? SELECT_FG : NORMAL_FG
    width = row_width(labels.length > visible_count)
    title, details = generation_parts(labels[index], index)
    text_x = content_x() + (is_selected ? 54 : 30)
    text_width = width - (text_x - content_x()) - 24

    draw_rect(content_x(), row_y, width, ROW_HEIGHT, bg)
    if is_selected
      draw_rect(content_x(), row_y, 8, ROW_HEIGHT, ACCENT)
      draw_chevron(content_x() + 29, row_y + ROW_HEIGHT / 2, :right, ACCENT, 9, 3)
    end
    draw_text_box(
      text_x,
      row_y + 17,
      text_width,
      32,
      title,
      fg,
      bg
    )
    draw_text_box(
      text_x,
      row_y + 66,
      text_width,
      24,
      details,
      is_selected ? ACCENT : MUTED_FG,
      bg,
      scale: SUBTITLE_FONT_SCALE
    )
  end

  def draw_controls(footer_y)
    controls_y = footer_y + 128
    first_x = content_x() + 18

    draw_rect(first_x, controls_y - 23, 48, 46, ROW_BG)
    draw_chevron(first_x + 24, controls_y - 7, :up, NORMAL_FG, 9, 3)
    draw_chevron(first_x + 24, controls_y + 10, :down, NORMAL_FG, 9, 3)
    draw_text_box(first_x + 68, controls_y - 14, 180, 30, "SELECT", MUTED_FG, PANEL_BG, scale: SUBTITLE_FONT_SCALE)

    second_x = first_x + 290
    draw_power_icon(second_x + 18, controls_y, NORMAL_FG)
    draw_text_box(second_x + 52, controls_y - 14, 180, 30, "BOOT", MUTED_FG, PANEL_BG, scale: SUBTITLE_FONT_SCALE)
  end

  def draw_countdown(footer_y, remaining)
    label_y = footer_y + 25
    track_y = footer_y + 76
    width = content_width()
    status = remaining ? "AUTO BOOT" : "MANUAL SELECTION"
    value = remaining ? "#{remaining} SEC" : "PAUSED"
    color = remaining ? STATUS_FG : MUTED_FG

    draw_text_box(content_x(), label_y, width / 2, 28, status, color, PANEL_BG, scale: SUBTITLE_FONT_SCALE)
    draw_text_box(
      content_x() + width / 2,
      label_y,
      width / 2,
      28,
      value,
      color,
      PANEL_BG,
      scale: SUBTITLE_FONT_SCALE,
      align: :right
    )
    draw_rect(content_x(), track_y, width, 8, ROW_BG)
    progress = remaining ? clamp(remaining, 0, timeout()) : 0
    draw_rect(content_x(), track_y, width * progress / [timeout(), 1].max, 8, remaining ? STATUS_FG : ACCENT_DIM)
  end

  def draw_scrollbar(count, visible_count, start_index, rows_y)
    return unless count > visible_count

    track_x = panel_x() + panel_width() - PANEL_PADDING - SCROLLBAR_WIDTH
    track_height = rows_height(visible_count)
    thumb_height = [track_height * visible_count / count, 48].max
    thumb_height = [thumb_height, track_height].min
    travel = track_height - thumb_height
    denominator = count - visible_count
    thumb_y = rows_y + (denominator > 0 ? travel * start_index / denominator : 0)

    draw_rect(track_x, rows_y, SCROLLBAR_WIDTH, track_height, ROW_BG)
    draw_rect(track_x, thumb_y, SCROLLBAR_WIDTH, thumb_height, ACCENT)
  end

  def render_framebuffer(generations, selected, previous_selected: nil, remaining: nil, previous_remaining: nil)
    started_at = Time.now.to_f
    $logger.debug("Sheng generation framebuffer render started.") if $logger.respond_to?(:debug)
    framebuffer_info()
    labels =
      if generations.empty?
        ["NixOS - Default"]
      else
        generations.each_with_index.map { |generation, index| generation_label(generation, index) }
      end
    start_index, end_index = visible_range(labels.length, selected)
    previous_start, previous_end =
      previous_selected.nil? ? [nil, nil] : visible_range(labels.length, previous_selected)
    full_redraw = previous_selected.nil? ||
      previous_start != start_index ||
      previous_end != end_index
    visible_count = end_index - start_index
    x = panel_x()
    y = panel_y(visible_count)
    width = panel_width()
    height = panel_height(visible_count)
    rows_y = y + HEADER_HEIGHT
    footer_y = rows_y + rows_height(visible_count)
    title_scale = content_width() < 900 ? 4 : TITLE_FONT_SCALE
    mark_size = content_width() < 900 ? 52 : 68
    brand_x = content_x() + mark_size + 34
    count_width = content_width() < 900 ? 140 : 210

    if full_redraw
      draw_rect(0, 0, @fb_width, @fb_height, BG)
      draw_panel(x, y, width, height)
      draw_brand_mark(content_x(), y + 41, mark_size, ACCENT)
      draw_text_box(
        brand_x,
        y + 35,
        content_width() - mark_size - 34 - count_width,
        48,
        "NIXOS SHENG",
        TITLE_FG,
        PANEL_BG,
        scale: title_scale
      )
      draw_text_box(
        brand_x,
        y + 101,
        content_width() - mark_size - 34,
        28,
        "RECOVERY / GENERATIONS",
        ACCENT,
        PANEL_BG,
        scale: SUBTITLE_FONT_SCALE
      )
      draw_text_box(
        content_x() + content_width() - count_width,
        y + 48,
        count_width,
        30,
        selection_count(selected, labels.length),
        MUTED_FG,
        PANEL_BG,
        scale: SUBTITLE_FONT_SCALE,
        align: :right
      )
      draw_rect(x + PANEL_BORDER, y + HEADER_HEIGHT - 2, width - PANEL_BORDER * 2, 2, PANEL_BORDER_COLOR)
      index = start_index
      while index < end_index
        draw_generation_row(labels, index, selected, start_index, visible_count)
        index += 1
      end
      draw_scrollbar(labels.length, visible_count, start_index, rows_y)
      draw_rect(x + PANEL_BORDER, footer_y, width - PANEL_BORDER * 2, 2, PANEL_BORDER_COLOR)
      draw_controls(footer_y)
    elsif previous_selected != selected
      draw_generation_row(labels, previous_selected, selected, start_index, visible_count) if previous_selected
      draw_generation_row(labels, selected, selected, start_index, visible_count)
      draw_text_box(
        content_x() + content_width() - count_width,
        y + 48,
        count_width,
        30,
        selection_count(selected, labels.length),
        MUTED_FG,
        PANEL_BG,
        scale: SUBTITLE_FONT_SCALE,
        align: :right
      )
    end

    if full_redraw || previous_remaining != remaining
      draw_countdown(footer_y, remaining)
    end

    if $logger.respond_to?(:debug)
      $logger.debug(
        "Sheng generation framebuffer prepared #{draw_operations().length} operations in " \
        "#{(Time.now.to_f - started_at).round(3)}s."
      )
    end
    present_framebuffer()
    true
  rescue => error
    $logger.warn("Could not render sheng generation menu framebuffer: #{error}")
    @framebuffer_failed = true
    false
  end

  def render_console(generations, selected, remaining)
    labels =
      if generations.empty?
        ["NixOS - Default"]
      else
        generations.each_with_index.map { |generation, index| generation_label(generation, index) }
      end
    lines = ["NixOS Sheng", "", "Select a system generation", ""]
    labels.each_with_index do |label, index|
      marker = index == selected ? ">" : " "
      lines << "#{marker} #{label}"
    end
    lines << ""
    lines << "Volume +/- or Up/Down: select    Power or Enter: boot"
    lines << (remaining ? "Automatic boot in #{remaining}s" : "Automatic boot paused")
    console.write("\e[2J\e[H#{lines.join("\n")}\n")
    console.flush
  rescue => error
    $logger.warn("Could not render sheng generation menu console fallback: #{error}")
  end

  def render(generations, selected, previous_selected: nil, remaining: nil, previous_remaining: nil)
    rendered = false
    unless @framebuffer_failed
      rendered = render_framebuffer(
        generations,
        selected,
        previous_selected: previous_selected,
        remaining: remaining,
        previous_remaining: previous_remaining
      )
    end
    render_console(generations, selected, remaining) unless rendered
  end

  def render_booting(label = "NixOS - Default")
    if @framebuffer_failed
      console.write("\e[2J\e[HNixOS Sheng\n\nStarting selected generation...\n")
      console.flush
      return
    end

    framebuffer_info()
    width = panel_width()
    height = 380
    x = panel_x()
    y = [(@fb_height - height) / 2, 24].max
    title, details = generation_parts(label, 0)

    draw_rect(0, 0, @fb_width, @fb_height, BG)
    draw_panel(x, y, width, height)
    draw_brand_mark(x + PANEL_PADDING, y + 51, 68, ACCENT)
    draw_text_box(
      x + PANEL_PADDING + 102,
      y + 46,
      width - PANEL_PADDING * 2 - 102,
      48,
      "NIXOS SHENG",
      TITLE_FG,
      PANEL_BG,
      scale: TITLE_FONT_SCALE
    )
    draw_rect(x + PANEL_PADDING, y + 145, 8, 104, BOOT_FG)
    draw_text_box(
      x + PANEL_PADDING + 28,
      y + 147,
      width - PANEL_PADDING * 2 - 28,
      34,
      title,
      TITLE_FG,
      PANEL_BG
    )
    draw_text_box(
      x + PANEL_PADDING + 28,
      y + 202,
      width - PANEL_PADDING * 2 - 28,
      28,
      details,
      MUTED_FG,
      PANEL_BG,
      scale: SUBTITLE_FONT_SCALE
    )
    draw_text_box(
      x + PANEL_PADDING,
      y + 292,
      width - PANEL_PADDING * 2,
      28,
      "HANDING OFF TO STAGE 2",
      BOOT_FG,
      PANEL_BG,
      scale: SUBTITLE_FONT_SCALE
    )
    draw_rect(x + PANEL_PADDING, y + 339, width - PANEL_PADDING * 2, 8, ROW_BG)
    draw_rect(x + PANEL_PADDING, y + 339, width - PANEL_PADDING * 2, 8, BOOT_FG)
    present_framebuffer()
  rescue => error
    $logger.warn("Could not render sheng generation menu boot status: #{error}")
  end

  def choose(switch_root)
    $logger.debug("Sheng generation menu initialization started.") if $logger.respond_to?(:debug)
    generations = Tasks::SwitchRoot::NixOSGeneration.generations()
    selected = 0
    countdown_active = true
    activate_console()
    unblank_framebuffer()
    $logger.debug("Sheng generation menu console activated.") if $logger.respond_to?(:debug)
    set_console_echo(false)
    set_console_keyboard(false)
    suppress_console_logs()
    $logger.debug("Sheng generation menu input scan started.") if $logger.respond_to?(:debug)
    refresh_input_devices(force: true)
    input_held.clear
    wait_for_release(VOLUME_UP + VOLUME_DOWN + CONFIRM)
    $logger.debug("Sheng generation menu input ready.") if $logger.respond_to?(:debug)
    deadline = monotonic_time() + timeout()
    last_selected = nil
    last_remaining = nil
    up_was_pressed = false
    down_was_pressed = false
    up_pressed_time = 0.0
    up_last_repeat = 0.0
    down_pressed_time = 0.0
    down_last_repeat = 0.0

    loop do
      remaining = countdown_active ? countdown_remaining(deadline) : nil
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

      input_action = poll_input_action(0.01)
      up_pressed = input_held?(VOLUME_UP)
      down_pressed = input_held?(VOLUME_DOWN)

      action_up = input_action == :up
      action_down = input_action == :down
      confirm_pressed = input_action == :confirm
      now_t = monotonic_time()

      if up_pressed
        if !up_was_pressed
          up_pressed_time = now_t
          up_last_repeat = now_t
          action_up = true
        elsif navigation_repeat_due?(up_pressed_time, up_last_repeat, now_t)
          action_up = true
          up_last_repeat = now_t
        end
      end

      if down_pressed
        if !down_was_pressed
          down_pressed_time = now_t
          down_last_repeat = now_t
          action_down = true
        elsif navigation_repeat_due?(down_pressed_time, down_last_repeat, now_t)
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
      elsif confirm_pressed
        wait_for_release(CONFIRM)
        break
      elsif countdown_active && monotonic_time() >= deadline
        break
      end

      up_was_pressed = up_pressed
      down_was_pressed = down_pressed
    end

    chosen_generation =
      if generations.empty?
        Tasks::SwitchRoot::NixOSGeneration.new(switch_root.default_selection_path())
      else
        generations[selected]
      end

    set_console_keyboard(true)
    restore_console_logs()
    set_console_echo(true)
    render_booting(generation_label(chosen_generation, selected))
    chosen_generation
  end
end

class Tasks::SwitchRoot
  def selected_generation()
    return @selected_generation if @selected_generation

    ShengEarlyChargeGuard.wait_if_critical()
    wants_menu = ShengEarlyChargeGuard.interactive_boot_safe?()

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
