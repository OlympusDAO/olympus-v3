#!/bin/bash

# Exit if there are any errors
set -e

echo "*** Clearing dependencies"
rm -rf dependencies/
rm -rf lib/

echo "*** Installing dependencies using pnpm"
pnpm install

echo "*** Setting up submodules"
git submodule init
git submodule update

echo "*** Running forge install"
forge install

echo "*** Restoring submodule commits"
# Lock the submodules to specific commits

echo "*** Running forge soldeer update"
forge soldeer update

echo "*** Installing safe-utils dependencies"
cd dependencies/safe-utils-0.0.13/ && forge install && cd ../..

# This must happen after the dependencies are installed, otherwise it may complain
echo "*** Cleaning build artifacts"
forge clean

echo "*** Running forge build"
forge build
