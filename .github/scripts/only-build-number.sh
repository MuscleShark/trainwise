#!/usr/bin/env bash
# Prints "true" when the change between two commits only bumps the build number
# (CURRENT_PROJECT_VERSION in the Xcode project) and touches docs, as the PR after
# each TestFlight upload does; "false" for anything else. Such a change can't alter
# what the iOS tests check, so the iOS workflow skips them.
#
#     .github/scripts/only-build-number.sh <base> <head>
set -euo pipefail

base=$1
head=$2
project=ios/IronSage.xcodeproj/project.pbxproj

files=$(git diff --name-only "$base" "$head")
if [ -z "$files" ] || ! echo "$files" | grep -qx "$project"; then
  echo false
  exit 0
fi

# Every file other than the project is documentation.
if echo "$files" | grep -vx "$project" | grep -qvE '^docs/|\.md$'; then
  echo false
  exit 0
fi

# Every changed line in the project sets the build number.
changed=$(git diff --unified=0 "$base" "$head" -- "$project" | grep -E '^[+-]' | grep -vE '^(\+\+\+|---) ')
if echo "$changed" | grep -qvE '^[+-][[:space:]]*CURRENT_PROJECT_VERSION = [0-9]+;$'; then
  echo false
else
  echo true
fi
