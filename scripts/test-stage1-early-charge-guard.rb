#!/usr/bin/env ruby

require "logger"

module Configuration
  def self.[](_key)
    {}
  end
end

module System
  def self.cmdline
    []
  end

  def self.run(*_args)
    raise "unexpected poweroff"
  end
end

$logger = Logger.new(File::NULL)

guard_path = ARGV[0] || File.expand_path(
  "../nixos/patches/stage-1-early-charge-guard.rb",
  __dir__
)
load guard_path

def assert(condition, message)
  raise message unless condition
end

assert(
  ShengEarlyChargeGuard.charger_power_on_reason?("0x800011"),
  "USB charger PON reason was not detected"
)
assert(
  ShengEarlyChargeGuard.charger_power_on_reason?("0x00000010"),
  "plain USB charger PON reason was not detected"
)
assert(
  !ShengEarlyChargeGuard.charger_power_on_reason?("0x800091"),
  "power-key boot while connected was misdetected as charger mode"
)
assert(
  !ShengEarlyChargeGuard.charger_power_on_reason?("invalid"),
  "malformed PON reason was accepted"
)

def charger_mode_for(values)
  ShengEarlyChargeGuard.define_singleton_method(:boot_value) do |key|
    values[key]
  end
  ShengEarlyChargeGuard.charger_mode?
end

assert(
  charger_mode_for("androidboot.mode" => "charger"),
  "androidboot charger mode was not detected"
)
assert(
  !charger_mode_for(
    "androidboot.mode" => "charger",
    "androidboot.force_normal_boot" => "1"
  ),
  "force-normal boot did not override charger mode"
)
assert(
  !charger_mode_for(
    "androidboot.mode" => "charger",
    "bootinfo.pureason" => "0x800091"
  ),
  "power-key PON reason did not override a stale charger mode"
)
charger_mode_for("androidboot.mode" => "charger")
assert(
  !ShengEarlyChargeGuard.interactive_boot_safe?(),
  "charger mode incorrectly allowed the generation menu"
)

def run_case(charger_boot:, capacities:, max_wait_seconds:)
  state = {
    blanked: 0,
    restored: 0,
    sleeps: 0,
    capacities: capacities.dup
  }

  ShengEarlyChargeGuard.define_singleton_method(:enabled?) { true }
  ShengEarlyChargeGuard.define_singleton_method(:critical_capacity) { 2 }
  ShengEarlyChargeGuard.define_singleton_method(:boot_capacity) { 5 }
  ShengEarlyChargeGuard.define_singleton_method(:max_wait_seconds) { max_wait_seconds }
  ShengEarlyChargeGuard.define_singleton_method(:charger_mode?) { charger_boot }
  ShengEarlyChargeGuard.define_singleton_method(:wait_for_battery) { 1 }
  ShengEarlyChargeGuard.define_singleton_method(:wait_for_external_power) { true }
  ShengEarlyChargeGuard.define_singleton_method(:external_power_online?) { true }
  ShengEarlyChargeGuard.define_singleton_method(:battery_capacity) do
    state[:capacities].shift || capacities.last
  end
  ShengEarlyChargeGuard.define_singleton_method(:blank_display) do
    state[:blanked] += 1
  end
  ShengEarlyChargeGuard.define_singleton_method(:restore_display) do
    state[:restored] += 1
  end
  ShengEarlyChargeGuard.define_singleton_method(:sleep) do |_seconds|
    state[:sleeps] += 1
  end

  ShengEarlyChargeGuard.wait_if_critical
  state
end

charger = run_case(charger_boot: true, capacities: [1, 1, 5], max_wait_seconds: 0)
assert(charger[:sleeps] == 2, "charger mode incorrectly honored the normal timeout")
assert(charger[:blanked] == 1, "charger mode did not blank the display")
assert(charger[:restored] == 1, "charger mode did not restore the display")

normal = run_case(charger_boot: false, capacities: [1], max_wait_seconds: 0)
assert(normal[:sleeps] == 0, "normal boot did not honor the timeout")
assert(normal[:blanked] == 1, "normal boot did not blank the display")
assert(normal[:restored] == 1, "normal boot did not restore the display")

puts "stage-1 early charge guard tests passed"
