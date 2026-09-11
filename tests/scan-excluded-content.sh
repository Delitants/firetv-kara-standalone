#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
matches=$(rg -n -i \
    'G071R|192\.168\.|obta[in]ium|BEGIN .*PRIVATE KEY|update-kindle|\.img\b' \
    "$repo" --glob '!.git/**' --glob '!.worktrees/**' \
    --glob '!tests/scan-excluded-content.sh' || true)
[ -z "$matches" ] || {
    printf '%s\n' "$matches" >&2
    printf 'EXCLUDED_CONTENT_GATE=FAIL\n' >&2
    exit 1
}
printf 'EXCLUDED_CONTENT_GATE=PASS\n'
