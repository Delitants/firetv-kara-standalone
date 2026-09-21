#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
out=$(mktemp -d "${TMPDIR:-/tmp}/kara-settings-models.XXXXXX")
trap 'rm -rf "$out"' EXIT HUP INT TERM

javac --release 8 -Xlint:-options -encoding UTF-8 -d "$out" \
    "$repo/app/kara-settings/src/local/kara/settingsredirector/AppEntry.java" \
    "$repo/app/kara-settings/src/local/kara/settingsredirector/DeveloperFacts.java" \
    "$repo/tests/TestKaraSettingsModels.java"
java -ea -cp "$out" TestKaraSettingsModels
