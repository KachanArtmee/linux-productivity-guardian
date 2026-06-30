#!/usr/bin/env bash

# Backwards-compatible entry point kept for existing installations.
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec "$script_dir/guardian.sh" all "$@"
