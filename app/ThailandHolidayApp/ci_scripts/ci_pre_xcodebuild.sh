#!/bin/sh

set -eu

if [ "${CI_XCODE_CLOUD-}" != "TRUE" ]; then
    exit 0
fi

project_directory=$(dirname "$CI_PROJECT_FILE_PATH")
script_directory=$(CDPATH= cd -- "$(dirname "$0")" && pwd)

require_distribution_secrets=FALSE
if [ "${CI_XCODEBUILD_ACTION-}" = "archive" ] || [ "${CONFIGURATION-}" = "Release" ]; then
    require_distribution_secrets=TRUE
fi

REQUIRE_DISTRIBUTION_SECRETS=$require_distribution_secrets \
    "$script_directory/generate_secrets_xcconfig.sh" \
        "$project_directory/Config/Secrets.xcconfig"
