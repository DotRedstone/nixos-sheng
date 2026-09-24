require "tmpdir"

Configuration = { "sheng_boot_animation" => { "enable" => true } }
module System
  class << self
    attr_accessor :arguments, :commands, :spawns, :make_ready, :control
    def cmdline() = arguments
    def run(*args)
      commands << args
      File.delete("#{control}.ready") if args.include?("--stop") && File.exist?("#{control}.ready")
    end
    def spawn(*args)
      spawns << args
      File.write("#{control}.ready", "ready") if make_ready
      nil
    end
  end
end
class Log
  def warn(_message); end
end
$logger = Log.new
module Tasks
  class Splash
    attr_reader :dependencies
    def initialize() = @dependencies = []
    def add_dependency(*args) = @dependencies << args
    def run(); end
    def kill(); end
  end
end

Dir.mktmpdir("sheng-stage1-animation-") do |directory|
  System.arguments = ["bootinfo.pureason=0x10"]
  System.commands = []
  System.spawns = []
  System.make_ready = true
  System.control = File.join(directory, "control")
  source, guard = ARGV
  eval(File.read(guard), TOPLEVEL_BINDING, guard)
  marker = File.join(directory, "force-normal-once")
  ShengEarlyChargeGuard.define_singleton_method(:normal_reboot_marker_path) { marker }
  boot_mode = File.join(directory, "boot-mode")
  ShengEarlyChargeGuard.define_singleton_method(:boot_mode_path) { boot_mode }
  eval(File.read(source).sub('"/run/sheng-boot-ui"', System.control.inspect), TOPLEVEL_BINDING, source)
  splash = Tasks::Splash.new
  raise "Early splash lacks proc dependency" unless splash.dependencies.include?([:Mount, "/proc"])
  raise "Early splash lacks dev dependency" unless splash.dependencies.include?([:Mount, "/dev"])

  splash.run
  raise "Charger boot animated before the charging target" unless System.spawns.empty?
  raise "Early splash cached a missing root marker" if ShengEarlyChargeGuard.instance_variable_defined?(:@normal_reboot_requested)
  File.write(marker, "normal")
  raise "USB reboot lost its one-shot normal-boot marker" if ShengEarlyChargeGuard.charger_mode?
  raise "Stage-1 removed the legacy stage-2 fallback marker" unless File.exist?(marker)
  ShengEarlyChargeGuard.commit_boot_mode("normal")
  raise "Stage-1 normal decision was not persisted" unless File.read(boot_mode) == "normal\n"
  ShengBootAnimation.start("start")
  raise "Normal reboot did not start its handoff animation" unless System.spawns.last.include?("start")
  raise "Normal-boot marker missing" unless File.exist?("#{System.control}.normal")

  System.arguments = ["androidboot.force_normal_boot=1"]
  splash.run
  raise "Normal boot lacks early animation" unless System.spawns.last.include?("prepare")
  System.arguments = ["sheng.boot-ui=0"]
  previous = System.spawns.length
  splash.run
  raise "Debug override started an animation" unless System.spawns.length == previous
  raise "Debug override failed to reveal diagnostics" unless System.commands.last.include?("--details")
  System.arguments = []
  File.write("#{System.control}.disabled", "details")
  ShengBootAnimation.start("start")
  raise "User diagnostics were overwritten" unless System.spawns.length == previous
  File.delete("#{System.control}.disabled")
  splash.kill
  raise "Normal splash shutdown revealed diagnostics" if System.commands.last.include?("--details")

  File.delete(boot_mode)
  ShengEarlyChargeGuard.remove_instance_variable(:@boot_mode) if
    ShengEarlyChargeGuard.instance_variable_defined?(:@boot_mode)
  ShengEarlyChargeGuard.commit_boot_mode("charger")
  previous = System.spawns.length
  ShengBootAnimation.start("start")
  raise "Committed charger decision started the normal animation" unless System.spawns.length == previous
end
puts "stage-1 animation ordering, charger isolation, reboot-marker and diagnostics tests passed"
