#!/bin/bash

npm install
git submodule init
git submodule update
forge install
forge update
forge build
