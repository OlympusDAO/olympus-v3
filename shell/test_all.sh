#!/bin/bash

print_test_event() {
	echo -e "\033[1m$1\033[0m"
	echo
}

source .env

print_test_event "Running non-fork tests"
npm run test:unit

print_test_event "Running fork tests"
npm run test:fork
