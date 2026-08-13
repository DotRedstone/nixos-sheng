#!/bin/sh

# Restart the user-space sensor chain and require SSC/IIO readiness each time.

set -eu

ITERATIONS="${1:-5}"

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

for command in systemctl ssccli; do
	if ! command -v "$command" >/dev/null 2>&1; then
		echo "missing command: $command" >&2
		exit 1
	fi
done

i=1
while [ "$i" -le "$ITERATIONS" ]; do
	start="$(date +%s)"

	systemctl restart adsprpcd-sensorspd.service
	systemctl restart iio-sensor-proxy.service

	if ! ssccli --sensor light --timeout 2 >/dev/null 2>&1; then
		echo "iteration $i: SSC query failed" >&2
		exit 1
	fi

	if ! systemctl is-active --quiet adsprpcd-sensorspd.service iio-sensor-proxy.service; then
		echo "iteration $i: sensor services are not active" >&2
		systemctl --no-pager --full status adsprpcd-sensorspd.service iio-sensor-proxy.service >&2 || true
		exit 1
	fi

	elapsed="$(( $(date +%s) - start ))"
	echo "iteration $i/$ITERATIONS: ready in ${elapsed}s"
	i=$((i + 1))
done

echo "sensor startup test passed"
