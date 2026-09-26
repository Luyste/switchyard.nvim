#!/usr/bin/env bash
# Records the demo GIFs into demo/media (needs vhs, a local pi with pi-nvim).
# Usage: demo/record.sh [yard|prompt|dispatch|follow ...]   (default: all)
set -euo pipefail
cd "$(dirname "$0")/.."
for name in "${@:-yard prompt dispatch follow}"; do
	for n in $name; do
		echo "recording $n"
		vhs "demo/$n.tape"
	done
done
demo/setup.sh --clean
