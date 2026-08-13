#!/bin/sh

# Exercise CAMSS runtime power transitions while issuing read-only UFS I/O.

set -eu

CAMSS_POWER=/sys/bus/platform/devices/acb7000.isp/power
ITERATIONS="${1:-20}"

case "$ITERATIONS" in
	''|*[!0-9]*|0)
		echo "usage: $0 [positive-iteration-count]" >&2
		exit 2
		;;
esac

if [ "$(id -u)" -ne 0 ]; then
	echo "run this test as root" >&2
	exit 1
fi

if [ ! -w "$CAMSS_POWER/control" ]; then
	echo "CAMSS runtime power controls are unavailable" >&2
	exit 1
fi

ROOT_DEVICE="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
case "$ROOT_DEVICE" in
	/dev/*) ;;
	*) ROOT_DEVICE= ;;
esac

ORIGINAL_CONTROL="$(cat "$CAMSS_POWER/control")"
DMESG_LINES="$(dmesg | wc -l)"
READ_PID=

restore() {
	if [ -n "$READ_PID" ]; then
		kill "$READ_PID" 2>/dev/null || true
		wait "$READ_PID" 2>/dev/null || true
	fi
	echo "$ORIGINAL_CONTROL" > "$CAMSS_POWER/control" 2>/dev/null || true
}
trap restore EXIT HUP INT TERM

wait_for_status() {
	expected="$1"
	attempt=0
	while [ "$attempt" -lt 50 ]; do
		status="$(cat "$CAMSS_POWER/runtime_status")"
		if [ "$status" = "$expected" ]; then
			return 0
		fi
		attempt=$((attempt + 1))
		sleep 0.1
	done

	echo "expected CAMSS runtime status $expected, got $status" >&2
	return 1
}

if [ -n "$ROOT_DEVICE" ]; then
	(
		while :; do
			dd if="$ROOT_DEVICE" of=/dev/null bs=4M count=64 status=none
		done
	) &
	READ_PID=$!
	echo "read-only UFS load: $ROOT_DEVICE (pid $READ_PID)"
else
	echo "root block device is not directly readable; testing CAMSS only"
fi

i=1
while [ "$i" -le "$ITERATIONS" ]; do
	echo on > "$CAMSS_POWER/control"
	wait_for_status active

	echo auto > "$CAMSS_POWER/control"
	wait_for_status suspended
	echo "iteration $i/$ITERATIONS: active -> suspended"
	i=$((i + 1))
done

NEW_ERRORS="$(dmesg | tail -n "+$((DMESG_LINES + 1))" | \
	grep -Ei 'camss|interconnect|rpmh|tcs|ufshcd|ufs.*(error|timeout|abort)' || true)"

if [ -n "$NEW_ERRORS" ]; then
	echo "new CAMSS/RPMh/UFS messages detected:" >&2
	echo "$NEW_ERRORS" >&2
	exit 1
fi

echo "CAMSS runtime PM test passed without new CAMSS/RPMh/UFS errors"
