#!/bin/bash

pnpm install
git submodule init
git submodule update
forge install
forge update
forge build
