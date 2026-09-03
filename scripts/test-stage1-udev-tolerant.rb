#!/usr/bin/env ruby

patch_path = ARGV[0] || "nixos/patches/stage-1-udev-trigger-tolerant.rb"

class LoggerStub
  def warn(*)
  end
end

$logger = LoggerStub.new

class SingletonTask
end

module System
  class CommandError < StandardError
  end

  def self.run(*)
    true
  end
end

module Tasks
  class UDev < SingletonTask
    def udevd
    end

    def udevadm(*)
    end
  end
end

module ShengEarlyChargeGuard
  @handoff_prepared = false

  def self.charger_mode?()
    true
  end

  def self.prepare_offline_charging_handoff()
    @handoff_prepared = true
  end

  def self.handoff_prepared?()
    @handoff_prepared
  end
end

eval(File.read(patch_path), nil, patch_path)
Tasks::UDev.new.run()

unless ShengEarlyChargeGuard.handoff_prepared?()
  raise "udev task did not prepare the offline charging handoff"
end

puts "stage-1 udev compatibility test passed"
