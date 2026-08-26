#!/bin/bash
# SPDX-FileCopyrightText: Contributors to OlympusDAO
# SPDX-License-Identifier: Unlicense

print_test_event() {
    echo -e "\033[1m$1\033[0m"
    echo
}

source .env

print_test_event "Running non-fork tests"
pnpm run test:unit

print_test_event "Running invariant tests"
pnpm run test:invariant

print_test_event "Running fork tests"
pnpm run test:fork
