#!/bin/sh
# Run from the checkout: ./rollback.sh lgtv
set -eu
[ "$#" -eq 1 ] || { echo 'usage: ./rollback.sh user@TV-IP' >&2; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
ssh -o BatchMode=yes -o ConnectTimeout=8 "$1" 'sh -s' < "$HERE/tv/restore-magic-pointer.sh"
