#!/bin/sh

set -eu

if [ "$#" -ne 1 ]; then
    echo "usage: generate_secrets_xcconfig.sh OUTPUT_PATH" >&2
    exit 64
fi

output_path=$1
umask 077

for variable_name in GOOGLE_PLACES_API_KEY BRAVE_SEARCH_API_KEY UNSPLASH_ACCESS_KEY; do
    eval "variable_value=\${$variable_name-}"
    case "$variable_value" in
        *"
"*)
            echo "$variable_name invalid" >&2
            exit 65
            ;;
        *[!A-Za-z0-9._-]*)
            echo "$variable_name has unsupported xcconfig characters" >&2
            exit 65
            ;;
    esac
done

mkdir -p "$(dirname "$output_path")"
{
    printf 'GOOGLE_PLACES_API_KEY = %s\n' "${GOOGLE_PLACES_API_KEY-}"
    printf 'BRAVE_SEARCH_API_KEY = %s\n' "${BRAVE_SEARCH_API_KEY-}"
    printf 'UNSPLASH_ACCESS_KEY = %s\n' "${UNSPLASH_ACCESS_KEY-}"
} > "$output_path"

for variable_name in GOOGLE_PLACES_API_KEY BRAVE_SEARCH_API_KEY UNSPLASH_ACCESS_KEY; do
    eval "variable_value=\${$variable_name-}"
    if [ -n "$variable_value" ]; then
        echo "$variable_name configured"
    else
        echo "$variable_name missing"
    fi
done

if [ "${REQUIRE_DISTRIBUTION_SECRETS-}" = "TRUE" ]; then
    if [ -z "${GOOGLE_PLACES_API_KEY-}" ] || [ -z "${BRAVE_SEARCH_API_KEY-}" ]; then
        echo "Required Xcode Cloud distribution secrets are missing; configure GOOGLE_PLACES_API_KEY and BRAVE_SEARCH_API_KEY in the workflow Environment section." >&2
        exit 66
    fi
fi
