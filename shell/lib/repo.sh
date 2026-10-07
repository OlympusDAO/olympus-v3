#!/bin/bash
# SPDX-FileCopyrightText: Contributors to OlympusDAO
# SPDX-License-Identifier: Unlicense

# Library for repository-level shell helpers

# @description Changes into the repository root, so that relative paths resolve the same way
#              wherever the script was invoked from. Falls back to the current directory outside a
#              git checkout.
cd_repo_root() {
    cd "$(git rev-parse --show-toplevel 2> /dev/null || pwd)" || exit 1
}

# @description Exits with an error unless the given command is available
# @param {string} $1 The command name
# @param {string} $2 Installation hint, printed after the error (optional, may span several lines)
require_command() {
    if command -v "$1" > /dev/null 2>&1; then
        return 0
    fi

    echo "ERROR: $1 not found." >&2
    if [ -n "${2:-}" ]; then
        echo "$2" >&2
    fi
    exit 1
}
