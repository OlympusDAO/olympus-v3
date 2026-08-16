#!/bin/bash

# Exit if there are any errors
set -e

echo "*** Clearing dependencies"
rm -rf dependencies/
rm -rf lib/

echo "*** Setting up submodules"
git submodule init
git submodule update

echo "*** Forge Version"
forge --version

echo "*** Running forge install"
forge install

echo "*** Restoring submodule commits"
# Lock the submodules to specific commits

echo "*** Running forge soldeer update"
rm -rf dependencies/
forge soldeer update

# Local fixes for known upstream defects; see shell/patches/README.md.
echo "*** Patching chainlink-local 0.2.9 (sender abi.encode)"
git apply --verbose --directory=dependencies/chainlink-local-029-0.2.9 \
    shell/patches/chainlink-local-029-sender-abi-encode.patch

# This must happen after the dependencies are installed, otherwise it may complain
echo "*** Cleaning build artifacts"
forge clean
