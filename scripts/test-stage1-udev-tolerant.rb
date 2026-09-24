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

eval(File.read(patch_path), nil, patch_path)
Tasks::UDev.new.run()

puts "stage-1 udev compatibility test passed without selecting a boot mode"
