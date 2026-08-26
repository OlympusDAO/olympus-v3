#!/bin/bash
# SPDX-FileCopyrightText: Contributors to OlympusDAO
# SPDX-License-Identifier: Unlicense

# @description Displays an error message in red
# @param {string} $1 The error message
display_error() {
    echo -e "\033[31m$1\033[0m"  # Red color for error message
}
