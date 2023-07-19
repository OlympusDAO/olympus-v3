#!/bin/bash

print_test_event() {
	echo -e "\033[1m$1\033[0m"
	echo
}

source .env

print_test_event "Running non-fork tests"
forge test --no-match-contract ".*Fork$" -vvv

print_test_event "Running fork tests"
forge test --match-contract ".*Fork$" --fork-url $FORK_TEST_RPC_URL -vvv
