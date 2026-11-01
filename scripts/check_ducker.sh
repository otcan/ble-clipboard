#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD=$(mktemp -d)
trap 'rm -rf "$BUILD"' EXIT HUP INT TERM
CC=${CC:-cc}
"$CC" -std=c11 -Wall -Wextra -Werror "$ROOT/Vendor/Ducker/tests/test_protocol.c" -o "$BUILD/protocol"
"$BUILD/protocol"
"$CC" -std=c11 -Wall -Wextra -Werror -I"$ROOT/Vendor/Ducker/tests/stubs" \
    "$ROOT/Vendor/Ducker/tests/test_hid.c" "$ROOT/Vendor/Ducker/trans_the_flip_hid.c" -o "$BUILD/hid"
"$BUILD/hid"
"$CC" -std=c11 -Wall -Wextra -Werror -I"$ROOT/Vendor/Ducker/tests/stubs" \
    "$ROOT/scripts/tests/ducker_contract.c" "$ROOT/Vendor/Ducker/trans_the_flip_hid.c" -o "$BUILD/contract"
"$BUILD/contract"
