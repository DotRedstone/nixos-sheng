#!/bin/sh

# Collect a privacy-conscious, read-only hardware baseline on a running sheng.

set -u

INTERVAL="${1:-10}"
case "$INTERVAL" in
	''|*[!0-9]*)
		echo "usage: $0 [idle-sample-seconds]" >&2
		exit 2
		;;
esac

TMPDIR_BASE="${TMPDIR:-/tmp}"
WORKDIR="$(mktemp -d "$TMPDIR_BASE/sheng-baseline.XXXXXX")" || exit 1
trap 'rm -rf "$WORKDIR"' EXIT HUP INT TERM

section() {
	printf '\n== %s ==\n' "$1"
}

read_value() {
	label="$1"
	path="$2"
	if [ -r "$path" ]; then
		value="$(cat "$path")"
		printf '%s=%s\n' "$label" "$value"
	fi
}

sanitize() {
	sed -E \
		-e 's/((androidboot\.)?serialno|androidboot\.deviceid)=[^ ]+/\1=<redacted>/g' \
		-e 's/(Serial(Number)?|serial)[=:][[:space:]]*[^[:space:]]+/\1=<redacted>/Ig'
}

collect_cpuidle() {
	output="$1"
	: > "$output"
	for state in /sys/devices/system/cpu/cpu[0-9]*/cpuidle/state[0-9]*; do
		[ -d "$state" ] || continue
		cpu="$(basename "$(dirname "$(dirname "$state")")")"
		name="$(basename "$state")"
		usage="$(cat "$state/usage" 2>/dev/null || printf 0)"
		time="$(cat "$state/time" 2>/dev/null || printf 0)"
		printf '%s/%s %s %s\n' "$cpu" "$name" "$usage" "$time" >> "$output"
	done
}

section "system"
date --iso-8601=seconds 2>/dev/null || date
uname -a
if [ -r /etc/os-release ]; then
	grep -E '^(NAME|VERSION|PRETTY_NAME)=' /etc/os-release
fi
read_value uptime_seconds /proc/uptime
if [ -r /proc/cmdline ]; then
	printf 'cmdline='
	sanitize < /proc/cmdline
fi

section "systemd"
if command -v systemctl >/dev/null 2>&1; then
	systemctl --failed --no-legend --no-pager 2>&1 || true
fi
if command -v systemd-analyze >/dev/null 2>&1; then
	printf '\n[boot-time]\n'
	systemd-analyze time 2>&1 || true
	printf '\n[slowest-units]\n'
	systemd-analyze blame --no-pager 2>&1 | head -30 || true
	printf '\n[graphical-critical-chain]\n'
	systemd-analyze critical-chain graphical.target --no-pager 2>&1 || true
fi

section "cpu-frequency"
for policy in /sys/devices/system/cpu/cpufreq/policy[0-9]*; do
	[ -d "$policy" ] || continue
	printf '[%s]\n' "$(basename "$policy")"
	for item in related_cpus scaling_governor scaling_min_freq scaling_max_freq scaling_cur_freq cpuinfo_min_freq cpuinfo_max_freq; do
		read_value "$item" "$policy/$item"
	done
done

section "device-frequency"
for devfreq in /sys/class/devfreq/*; do
	[ -d "$devfreq" ] || continue
	printf '[%s]\n' "$(basename "$devfreq")"
	for item in name governor cur_freq min_freq max_freq available_governors available_frequencies; do
		read_value "$item" "$devfreq/$item"
	done
done

section "idle-residency-${INTERVAL}s"
collect_cpuidle "$WORKDIR/cpuidle.before"
sleep "$INTERVAL"
collect_cpuidle "$WORKDIR/cpuidle.after"
awk '
	NR == FNR { usage[$1] = $2; time[$1] = $3; next }
	{
		du = $2 - usage[$1]
		dt = $3 - time[$1]
		printf "%s entries=%d residency_us=%d\n", $1, du, dt
	}
' "$WORKDIR/cpuidle.before" "$WORKDIR/cpuidle.after"

section "thermal"
for zone in /sys/class/thermal/thermal_zone[0-9]*; do
	[ -d "$zone" ] || continue
	type="$(cat "$zone/type" 2>/dev/null || printf unknown)"
	temp="$(cat "$zone/temp" 2>/dev/null || printf unknown)"
	printf '%s type=%s temp_millic=%s\n' "$(basename "$zone")" "$type" "$temp"
done

section "memory-and-zram"
grep -E '^(MemTotal|MemAvailable|SwapTotal|SwapFree|Dirty|Writeback):' /proc/meminfo 2>/dev/null || true
if command -v zramctl >/dev/null 2>&1; then
	zramctl 2>&1 || true
fi

section "storage"
for blockdev in /sys/block/sd[a-z]; do
	[ -d "$blockdev" ] || continue
	printf '[%s]\n' "$(basename "$blockdev")"
	for item in queue/scheduler queue/read_ahead_kb queue/nr_requests queue/rotational; do
		read_value "$item" "$blockdev/$item"
	done
done

section "power-management"
read_value state /sys/power/state
read_value mem_sleep /sys/power/mem_sleep
read_value suspend_success /sys/power/suspend_stats/success
read_value suspend_fail /sys/power/suspend_stats/fail
if [ -r /sys/kernel/debug/wakeup_sources ]; then
	awk 'NR == 1 || $6 > 0 || $7 > 0 { print }' /sys/kernel/debug/wakeup_sources
fi

section "camera-runtime-power"
CAMSS_POWER=/sys/bus/platform/devices/acb7000.isp/power
if [ -d "$CAMSS_POWER" ]; then
	for item in control runtime_status runtime_active_time runtime_suspended_time; do
		read_value "$item" "$CAMSS_POWER/$item"
	done
fi
if [ -r /sys/kernel/debug/interconnect/interconnect_summary ]; then
	grep -E 'acb7000\.isp|camera_cfg|camnoc_hf|mnoc_hf' \
		/sys/kernel/debug/interconnect/interconnect_summary 2>/dev/null || true
fi
if [ -r /sys/kernel/debug/pm_genpd/pm_genpd_summary ]; then
	grep -E 'cam_cc_titan_top_gdsc|genpd:[0-9]+:acb7000\.isp' \
		/sys/kernel/debug/pm_genpd/pm_genpd_summary 2>/dev/null || true
fi

section "tracing"
read_value current_tracer /sys/kernel/tracing/current_tracer
read_value tracing_on /sys/kernel/tracing/tracing_on

section "power-supplies"
for supply in /sys/class/power_supply/*; do
	[ -d "$supply" ] || continue
	printf '[%s]\n' "$(basename "$supply")"
	for item in type online present status capacity voltage_now current_now power_now usb_type charge_type health temp; do
		read_value "$item" "$supply/$item"
	done
done

section "remote-processors"
for remoteproc in /sys/class/remoteproc/remoteproc[0-9]*; do
	[ -d "$remoteproc" ] || continue
	printf '[%s]\n' "$(basename "$remoteproc")"
	read_value name "$remoteproc/name"
	read_value state "$remoteproc/state"
	read_value firmware "$remoteproc/firmware"
done

section "usb-c"
for port in /sys/class/typec/port[0-9]*; do
	[ -e "$port" ] || continue
	printf '[%s]\n' "$(basename "$port")"
	for item in data_role power_role port_type preferred_role power_operation_mode usb_power_delivery_revision; do
		read_value "$item" "$port/$item"
	done
done
for role in /sys/class/usb_role/*; do
	[ -d "$role" ] || continue
	printf '[%s]\n' "$(basename "$role")"
	read_value role "$role/role"
done

section "pci-and-wireless"
if command -v lspci >/dev/null 2>&1; then
	lspci -nnk 2>&1 || true
fi
for netdev in /sys/class/net/*; do
	[ -e "$netdev/device/driver" ] || continue
	printf '%s driver=%s operstate=%s\n' \
		"$(basename "$netdev")" \
		"$(basename "$(readlink "$netdev/device/driver")")" \
		"$(cat "$netdev/operstate" 2>/dev/null || printf unknown)"
done

section "audio"
cat /proc/asound/cards 2>/dev/null || true
cat /proc/asound/devices 2>/dev/null || true
if command -v wpctl >/dev/null 2>&1 && [ -n "${XDG_RUNTIME_DIR:-}" ]; then
	wpctl status 2>&1 || true
fi

section "kernel-chain-events"
if command -v dmesg >/dev/null 2>&1; then
	dmesg 2>/dev/null | sanitize | grep -Ei \
		'adsp|cdsp|remoteproc|fastrpc|sensor_pd|charger_pd|pd_running|ucsi|typec|mipps|qcom.battmgr|ath12k|wcn7850|pcie|soundwire|cs35l43|lpass|gpu|drm|haptics' \
		| tail -n 500 || true
fi

section "kernel-warnings"
if command -v dmesg >/dev/null 2>&1; then
	dmesg --level=warn,err,crit,alert,emerg 2>/dev/null | sanitize | tail -n 300 || true
fi
