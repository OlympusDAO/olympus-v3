#!/bin/bash

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
cd lib/forge-std/ && git checkout 73d44ec7d124e3831bc5f832267889ffb6f9bc3f && cd ../..
cd lib/openzeppelin-contracts/ && git checkout 49c0e4370d0cc50ea6090709e3835a3091e33ee2 && cd ../..
cd lib/solidity-examples/ && git checkout a4954e5747baca5e7fd2b62c639e7600ad388a5f && cd ../..
cd lib/solmate/ && git checkout fadb2e2778adbf01c80275bfb99e5c14969d964b && cd ../..
cd lib/uniswap-v3-core/ && git checkout 6562c52e8f75f0c10f9deaf44861847585fc8129 && cd ../..
cd lib/uniswap-v3-periphery/ && git checkout b325bb0905d922ae61fcc7df85ee802e8df5e96c && cd ../..

echo "*** Running forge build"
forge build
