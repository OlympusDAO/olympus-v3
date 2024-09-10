#!/bin/bash

# Exit if there are any errors
set -e

pnpm install
git submodule init
git submodule update
forge install
forge update
forge build
