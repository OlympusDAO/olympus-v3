#!/bin/bash

print_test_event() {
	echo -e "\033[1m$1\033[0m"
	echo
}

source ../.env

forge run src/policies/test/LockingVault.t.sol -t LockingVaultTest --sig "Integrative1(int32)" 103072000 -vvv >src/policies/test/logs/LockingVault1.log

print_test_event "Integrative1 test for LockingVault printed to logs."

forge test
