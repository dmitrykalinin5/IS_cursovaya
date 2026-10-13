#!/usr/bin/env bash
# Helios exposes Python 3 as python3.11/python, Fedora normally as python3.
set -euo pipefail
for candidate in "${HELIOS_PYTHON:-python3}" python3.11 python; do
    if command -v "$candidate" >/dev/null && "$candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' 2>/dev/null; then
        exec "$candidate" "$@"
    fi
done
echo 'Python 3.8+ is required (python3, python3.11 or HELIOS_PYTHON)' >&2
exit 2
