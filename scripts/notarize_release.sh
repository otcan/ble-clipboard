#!/bin/zsh
set -euo pipefail
root=${0:A:h:h}
# This driver records the exact candidate before submitting. Retries only poll/finalize.
version=${1-}
if [[ -z "$version" ]]; then version=$(cat "$root/VERSION"); fi
exec "${PYTHON:-python3}" "$root/scripts/notarize_candidate.py" "$version"
