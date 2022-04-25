#!/bin/bash

source .env
forge test --fork-url $RPC_URL -vvvv
