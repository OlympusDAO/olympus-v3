#!/bin/bash

npm install
git submodule init
git submodule update --recursive --remote
forge install
forge update
forge build
