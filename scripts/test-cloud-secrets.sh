#!/usr/bin/env bash

set -euo pipefail

test_directory=$(mktemp -d /tmp/thailand-cloud-secrets.XXXXXX)
trap 'rm -rf "$test_directory"' EXIT
output_file="$test_directory/Config/Secrets.xcconfig"
generator="$(dirname "$0")/../app/ThailandHolidayApp/ci_scripts/generate_secrets_xcconfig.sh"

GOOGLE_PLACES_API_KEY=test-google \
BRAVE_SEARCH_API_KEY=test-brave \
UNSPLASH_ACCESS_KEY=test-unsplash \
    "$generator" "$output_file" >/dev/null

test "$(stat -c '%a' "$output_file")" = "600"
grep -qx 'GOOGLE_PLACES_API_KEY = test-google' "$output_file"
grep -qx 'BRAVE_SEARCH_API_KEY = test-brave' "$output_file"
grep -qx 'UNSPLASH_ACCESS_KEY = test-unsplash' "$output_file"

missing_output="$test_directory/Missing.xcconfig"
env -u GOOGLE_PLACES_API_KEY -u BRAVE_SEARCH_API_KEY -u UNSPLASH_ACCESS_KEY \
    "$generator" "$missing_output" >/dev/null
grep -qx 'GOOGLE_PLACES_API_KEY = ' "$missing_output"
grep -qx 'BRAVE_SEARCH_API_KEY = ' "$missing_output"
grep -qx 'UNSPLASH_ACCESS_KEY = ' "$missing_output"

if REQUIRE_DISTRIBUTION_SECRETS=TRUE \
    GOOGLE_PLACES_API_KEY= BRAVE_SEARCH_API_KEY= UNSPLASH_ACCESS_KEY= \
    "$generator" "$test_directory/Distribution.xcconfig" >/dev/null 2>&1; then
    echo "Distribution config zonder vereiste secrets had moeten falen" >&2
    exit 1
fi

project_directory="$test_directory/CloudProject"
mkdir -p "$project_directory/ThailandHolidayApp.xcodeproj"
CI_XCODE_CLOUD=TRUE \
CI_XCODEBUILD_ACTION=archive \
CI_PROJECT_FILE_PATH="$project_directory/ThailandHolidayApp.xcodeproj" \
GOOGLE_PLACES_API_KEY=test-google \
BRAVE_SEARCH_API_KEY=test-brave \
UNSPLASH_ACCESS_KEY= \
    "$(dirname "$generator")/ci_pre_xcodebuild.sh" >/dev/null
test -f "$project_directory/Config/Secrets.xcconfig"
