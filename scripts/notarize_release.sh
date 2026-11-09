#!/bin/zsh
set -euo pipefail
root=${0:A:h:h}
# This driver records the exact candidate before submitting. Retries only poll/finalize.
exec "${PYTHON:-python3}" "$root/scripts/notarize_candidate.py" "${1:-$(<"$root/VERSION")}"
