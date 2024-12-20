#!/bin/bash

# Exit if there are any errors
set -e

echo "*** Installing dependencies using pnpm"
pnpm install

echo "*** Setting up submodules"
git submodule init
git submodule update

echo "*** Running forge install"
forge install

echo "*** Restoring submodule commits"
# Lock the submodules to specific commits
# TODO look at how to improve submodules
cd lib/clones-with-immutable-args/ && git checkout 5950723ffcfa047f13262e5dbd7218b54360c42e && cd ../..
cd lib/ds-test/ && git checkout 9310e879db8ba3ea6d5c6489a579118fd264a3f5 && cd ../..
cd lib/forge-std/ && git checkout 2f112697506eab12d433a65fdc31a639548fe365 && cd ../..
cd lib/openzeppelin-contracts/ && git checkout 49c0e4370d0cc50ea6090709e3835a3091e33ee2 && cd ../..
cd lib/solidity-examples/ && git checkout a4954e5747baca5e7fd2b62c639e7600ad388a5f && cd ../..
cd lib/solmate/ && git checkout fadb2e2778adbf01c80275bfb99e5c14969d964b && cd ../..
cd lib/forge-proposal-simulator && git checkout 864b357b650f9dc7b2fb1ae23562454815d51def && cd ../..

echo "*** Running forge soldeer update"
forge soldeer update

echo "*** Running forge build"
forge build
