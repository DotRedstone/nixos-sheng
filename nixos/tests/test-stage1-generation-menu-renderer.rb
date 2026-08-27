menu_source = ARGV[0]
raise "usage: #{$0} MENU_SOURCE" unless menu_source

Configuration = {}

module Tasks
  class SwitchRoot
    class NixOSGeneration
      def initialize(*args)
      end
    end
  end

  class Splash
    def self.instance()
      @instance ||= new
    end

    def quit(*args)
    end
  end
end

module ShengEarlyChargeGuard
  def self.wait_if_critical()
  end

  def self.interactive_boot_safe?()
    true
  end
end

class TestLogger
  def warn(message)
    raise message
  end

  def respond_to?(name)
    false
  end
end

$logger = TestLogger.new
eval(File.read(menu_source), nil, menu_source)

class TestGeneration
  def initialize(number)
    @number = number
  end

  def label()
    "NixOS ##{@number} (2026-08-27 - 26.11pre-git)"
  end
end

module ShengHeadlessGenerationMenu
  class << self
    attr_reader :captured_operations
    alias real_present_framebuffer present_framebuffer

    def present_framebuffer()
      @captured_operations = draw_operations().dup
      @draw_operations = []
      @dirty_top = nil
      @dirty_bottom = nil
    end

    def generation_parts(label, index)
      parts = label.to_s.split("#", 2)
      number_and_details = parts.length > 1 ? parts[1] : "#{index + 1}"
      number = number_and_details.split(" ", 2)[0]
      details_parts = number_and_details.split("(", 2)
      details = details_parts.length > 1 ? details_parts[1] : "SYSTEM PROFILE"
      details = details[0, details.length - 1] if details[-1, 1] == ")"
      ["GENERATION #{number}", details]
    end

    def unblank_framebuffer()
      true
    end
  end
end

class TestFramebuffer
  attr_reader :read_count, :write_count, :largest_transfer

  def initialize()
    @read_count = 0
    @write_count = 0
    @largest_transfer = 0
  end

  def sysseek(offset, whence)
    offset
  end

  def sysread(length)
    @read_count += 1
    @largest_transfer = length if length > @largest_transfer
    "\0" * length
  end

  def syswrite(data)
    @write_count += 1
    @largest_transfer = data.bytesize if data.bytesize > @largest_transfer
    data.bytesize
  end

  def flush()
  end
end

class PreviewFramebuffer
  def initialize(size)
    @data = "\0" * size
    @offset = 0
  end

  def sysseek(offset, whence)
    @offset = offset
  end

  def sysread(length)
    data = @data[@offset, length]
    @offset += data.bytesize
    data
  end

  def syswrite(data)
    @data[@offset, data.bytesize] = data
    @offset += data.bytesize
    data.bytesize
  end

  def flush()
  end

  def save(path)
    file = File.open(path, "wb")
    written = 0
    while written < @data.bytesize
      count = file.syswrite(@data[written, @data.bytesize - written])
      raise "short preview write" unless count && count > 0
      written += count
    end
    file.close
  end
end

menu = ShengHeadlessGenerationMenu
menu.instance_variable_set(:@fb_width, 3048)
menu.instance_variable_set(:@fb_height, 2032)
menu.instance_variable_set(:@fb_bpp, 32)
menu.instance_variable_set(:@fb_bytes, 4)
menu.instance_variable_set(:@fb_stride, 12288)
menu.instance_variable_set(:@fb_ready, true)

started_at = Time.now.to_f
generations = (1..63).to_a.reverse.map { |number| TestGeneration.new(number) }
menu.render_framebuffer(generations, 0, remaining: 30)
elapsed = Time.now.to_f - started_at
operations = menu.captured_operations

raise "renderer queued no operations" if operations.empty?
raise "renderer queued too many operations: #{operations.length}" if operations.length > 1500
raise "renderer preparation took #{elapsed}s" if elapsed > 2.0

operations.each do |operation|
  kind, x, y, width, height = operation
  raise "unexpected operation #{kind}" unless kind == :rect || kind == :text
  raise "invalid operation size #{operation.inspect}" if width <= 0 || height <= 0
  raise "operation escaped framebuffer #{operation.inspect}" if x < 0 || y < 0
  raise "operation escaped framebuffer #{operation.inspect}" if x + width > 3048 || y + height > 2032
end

menu.instance_variable_set(:@draw_operations, operations.dup)
rectangles = menu.framebuffer_rectangles()
raise "raster expansion queued too many rectangles: #{rectangles.length}" if rectangles.length > 7000
raise "raster expansion retained a vector operation" unless rectangles.all? { |operation| operation[0] == :rect }

tile = "\0" * (menu::FRAMEBUFFER_TILE_HEIGHT * 12288)
rectangles.each do |operation|
  menu.paint_framebuffer_tile(tile, 0, menu::FRAMEBUFFER_TILE_HEIGHT, operation)
end
raise "tile buffer changed size" unless tile.bytesize == menu::FRAMEBUFFER_TILE_HEIGHT * 12288

fake_framebuffer = TestFramebuffer.new
menu.instance_variable_set(:@framebuffer, fake_framebuffer)
menu.instance_variable_set(:@draw_operations, operations.dup)
menu.instance_variable_set(:@dirty_top, 0)
menu.instance_variable_set(:@dirty_bottom, 2032)
present_started_at = Time.now.to_f
menu.real_present_framebuffer()
present_elapsed = Time.now.to_f - present_started_at
expected_tiles = (2032 + menu::FRAMEBUFFER_TILE_HEIGHT - 1) / menu::FRAMEBUFFER_TILE_HEIGHT
raise "unexpected tile read count #{fake_framebuffer.read_count}" unless fake_framebuffer.read_count == expected_tiles
raise "unexpected tile write count #{fake_framebuffer.write_count}" unless fake_framebuffer.write_count == expected_tiles
raise "tile transfer exceeded memory bound" if fake_framebuffer.largest_transfer > menu::FRAMEBUFFER_TILE_HEIGHT * 12288
raise "tile presentation took #{present_elapsed}s" if present_elapsed > menu::FRAMEBUFFER_RENDER_TIMEOUT

preview_path = ARGV[1]
if preview_path
  preview_framebuffer = PreviewFramebuffer.new(2032 * 12288)
  menu.instance_variable_set(:@framebuffer, preview_framebuffer)
  menu.instance_variable_set(:@draw_operations, operations.dup)
  menu.instance_variable_set(:@dirty_top, 0)
  menu.instance_variable_set(:@dirty_bottom, 2032)
  menu.real_present_framebuffer()
  preview_framebuffer.save(preview_path)
end

menu.render_framebuffer(
  generations,
  1,
  previous_selected: 0,
  remaining: nil,
  previous_remaining: 30
)
partial_operations = menu.captured_operations
raise "partial redraw queued too many operations" if partial_operations.length > 250

menu.render_framebuffer(generations, generations.length - 1, remaining: nil)
bottom_operations = menu.captured_operations
bottom_operations.each do |operation|
  kind, x, y, width, height = operation
  raise "unexpected bottom operation #{kind}" unless kind == :rect || kind == :text
  raise "bottom operation escaped framebuffer #{operation.inspect}" if x < 0 || y < 0
  raise "bottom operation escaped framebuffer #{operation.inspect}" if x + width > 3048 || y + height > 2032
end

menu.instance_variable_set(:@draw_operations, [])
menu.draw_line(-100000, -100000, 100000, 100000, menu::ACCENT, 5)
line_operations = menu.draw_operations()
raise "line sampling is unbounded" if line_operations.length > menu::MAX_LINE_SAMPLES + 1
raise "line emitted a vector operation" unless line_operations.all? { |operation| operation[0] == :rect }

menu.instance_variable_set(:@framebuffer_deadline, Time.now.to_f - 1.0)
begin
  menu.check_framebuffer_deadline()
  raise "expired framebuffer deadline was ignored"
rescue IOError
ensure
  menu.instance_variable_set(:@framebuffer_deadline, nil)
end

puts "generation menu renderer: #{operations.length} operations, #{rectangles.length} rectangles, #{expected_tiles} tiles in #{present_elapsed.round(3)}s"
