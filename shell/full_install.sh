#!/bin/bash

yarn
# yes doing this because preferable to submodule update
forge install

# same here
for lib in lib/*; do
	forge update $lib
done

forge build
