menu_source = ARGV[0]
command_path = ARGV[1]
raise "usage: #{$0} MENU_SOURCE COMMAND_OUTPUT" unless menu_source && command_path

Configuration = {
  "sheng_generation_menu" => {
    "enable" => true,
    "timeout" => 3
  }
}

class Task
  def _try_run_task()
    :original_result
  end
end

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
  attr_reader :messages

  def initialize()
    @messages = []
  end

  def info(message)
    @messages << message
  end

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

menu = ShengHeadlessGenerationMenu
raise "unexpected default menu timeout" unless menu.timeout() == 3
raise "keyboard up is not mapped" unless menu.input_action_for_code(menu::KEY_UP) == :up
raise "keyboard down is not mapped" unless menu.input_action_for_code(menu::KEY_DOWN) == :down
raise "keyboard Enter is not mapped" unless menu.input_action_for_code(menu::KEY_ENTER) == :confirm
raise "volume up is not mapped" unless menu.input_action_for_code(menu::KEY_VOLUMEUP) == :up
raise "volume down is not mapped" unless menu.input_action_for_code(menu::KEY_VOLUMEDOWN) == :down
raise "navigation repeated before its delay" if menu.navigation_repeat_due?(10.0, 10.0, 10.39)
raise "navigation did not repeat after its delay" unless menu.navigation_repeat_due?(10.0, 10.0, 10.4)
raise "navigation repeated faster than its interval" if menu.navigation_repeat_due?(10.0, 10.35, 10.4)
class WouldBlockError
  def errno()
    11
  end
end
raise "EAGAIN was not recognized as a normal empty read" unless menu.input_would_block?(WouldBlockError.new)

def input_event(code, value)
  bytes = Array.new(24, 0)
  bytes[16] = 1
  bytes[18] = code & 0xff
  bytes[19] = (code >> 8) & 0xff
  bytes[20] = value & 0xff
  bytes[21] = (value >> 8) & 0xff
  bytes[22] = (value >> 16) & 0xff
  bytes[23] = (value >> 24) & 0xff
  bytes.pack("C*")
end

class BatchInput
  def initialize(data)
    @data = data
  end

  def sysread(_length)
    @data
  end
end

test_input_path = "/dev/input/test-volume"
menu.input_held()[test_input_path] = {}
action = menu.read_input_events(
  test_input_path,
  BatchInput.new(input_event(menu::KEY_VOLUMEDOWN, 1) + input_event(0, 0))
)
raise "batched volume press did not navigate down" unless action == :down
raise "batched volume press did not remain held" unless menu.input_held()[test_input_path][menu::KEY_VOLUMEDOWN]
menu.read_input_events(test_input_path, BatchInput.new(input_event(menu::KEY_VOLUMEDOWN, 0)))
raise "batched volume release remained held" if menu.input_held()[test_input_path][menu::KEY_VOLUMEDOWN]
menu.input_held().delete(test_input_path)

menu.instance_variable_set(:@fb_width, 3048)
menu.instance_variable_set(:@fb_height, 2032)
menu.instance_variable_set(:@fb_bpp, 32)
menu.instance_variable_set(:@fb_bytes, 4)
menu.instance_variable_set(:@fb_stride, 12288)
menu.instance_variable_set(:@fb_ready, true)

menu.instance_variable_set(:@fb_height, 2032.0)
raise "floating framebuffer height produced a non-integer page size" unless menu.max_visible_generations() == 13
raise "page size remained a float" unless menu.max_visible_generations().is_a?(Integer)
menu.instance_variable_set(:@fb_height, 2032)

started_at = Time.now.to_f
generations = (1..63).to_a.reverse.map { |number| TestGeneration.new(number) }
page_size = menu.max_visible_generations()
raise "first page is unstable" unless menu.visible_range(generations.length, 0) == [0, page_size]
raise "selection moved the first page" unless menu.visible_range(generations.length, page_size - 1) == [0, page_size]
raise "next page did not begin at a page boundary" unless menu.visible_range(generations.length, page_size) == [page_size, page_size * 2]
last_page_start = menu.last_page_start(generations.length, page_size)
raise "last page escaped the generation list" unless menu.visible_range(generations.length, generations.length - 1) == [last_page_start, generations.length]

selected, page_start = [0, 0]
(page_size - 1).times do
  selected, page_start = menu.move_selection(selected, page_start, :down, generations.length, page_size)
end
raise "selection changed page before its final row" unless selected == page_size - 1 && page_start == 0
selected, page_start = menu.move_selection(selected, page_start, :down, generations.length, page_size)
raise "selection did not switch page after its final row" unless selected == page_size && page_start == page_size
selected, page_start = menu.move_selection(selected, page_start, :up, generations.length, page_size)
raise "up navigation did not return to the previous page" unless selected == page_size - 1 && page_start == 0
selected, page_start = menu.move_selection(26, 26, :up, generations.length, 13.0)
raise "floating page size broke mirrored up navigation" unless selected == 25 && page_start == 13
selected, page_start = menu.move_selection(selected, page_start, :up, generations.length, 13.0)
raise "up navigation changed page inside the previous page" unless selected == 24 && page_start == 13
selected, page_start = menu.move_selection(0, 0, :up, generations.length, page_size)
raise "up navigation did not wrap to the last page" unless selected == generations.length - 1 && page_start == last_page_start
selected, page_start = menu.move_selection(generations.length - 1, last_page_start, :down, generations.length, page_size)
raise "down navigation did not wrap to the first page" unless selected == 0 && page_start == 0

menu.render_framebuffer(generations, 0, remaining: 3)
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

command_data = menu.framebuffer_command_data(rectangles)
raise "invalid framebuffer command magic" unless command_data[0, 4] == menu::FRAMEBUFFER_COMMAND_MAGIC
raise "invalid framebuffer command size" unless command_data.bytesize == 4 + rectangles.length * 12
file = File.open(command_path, "wb")
written = 0
while written < command_data.bytesize
  count = file.syswrite(command_data[written, command_data.bytesize - written])
  raise "short framebuffer command test write" unless count && count > 0
  written += count
end
file.close
menu.instance_variable_set(:@draw_operations, [])
menu.instance_variable_set(:@dirty_top, nil)
menu.instance_variable_set(:@dirty_bottom, nil)

menu.render_framebuffer(
  generations,
  1,
  previous_selected: 0,
  page_start: 0,
  previous_page_start: 0,
  remaining: nil,
  previous_remaining: 3
)
partial_operations = menu.captured_operations
raise "partial redraw queued too many operations" if partial_operations.length > 250

menu.render_framebuffer(
  generations,
  page_size - 1,
  previous_selected: 1,
  page_start: 0,
  previous_page_start: 0,
  remaining: nil,
  previous_remaining: nil
)
last_row_operations = menu.captured_operations
raise "last row unexpectedly redrew the whole page" if last_row_operations.length > 250

menu.render_framebuffer(
  generations,
  page_size,
  previous_selected: page_size - 1,
  page_start: page_size,
  previous_page_start: 0,
  remaining: nil,
  previous_remaining: nil
)
next_page_operations = menu.captured_operations
raise "page boundary did not redraw the new page" if next_page_operations.length <= 250

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

puts "generation menu renderer: #{operations.length} operations, #{rectangles.length} native rectangles"
